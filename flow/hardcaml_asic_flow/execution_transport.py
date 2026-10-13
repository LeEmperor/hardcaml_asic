"""Exact observed-runtime launch transport; no LibreLane flow sequencing."""

import copy
import os
from pathlib import Path
import re
import uuid

from . import runtime_observation as observation


class BindingError(ValueError):
    pass


def validate(binding):
    if (type(binding) is not dict or type(binding.get("schema_version")) is not int
            or binding["schema_version"] != 1):
        raise BindingError("missing or malformed execution binding")
    mode = binding.get("execution_mode")
    flags = binding.get("interpreter_flags")
    if flags not in (["-I", "-B"], ["-B"]):
        raise BindingError("invalid execution interpreter flags")
    if mode == "native":
        if (flags != ["-I", "-B"] or type(binding.get("interpreter")) is not str
                or not Path(binding["interpreter"]).is_absolute()):
            raise BindingError("invalid native interpreter binding")
    elif mode == "dockerized":
        image = binding.get("image_identity", {})
        engine = binding.get("engine_identity", {})
        if (type(image) is not dict or type(engine) is not dict
                or image.get("binding") != "local-image-id"
                or type(image.get("image_id")) is not str
                or not re.fullmatch(r"sha256:[0-9a-f]{64}", image["image_id"])
                or type(image.get("declared_ref")) is not str
                or not image["declared_ref"]
                or type(image.get("repo_digests")) is not list
                or any(type(d) is not str for d in image["repo_digests"])
                or type(image.get("platform")) is not dict
                or any(type(image["platform"].get(k)) is not str or not image["platform"][k]
                       for k in ("os", "architecture"))
                or engine.get("name") != "docker"
                or type(engine.get("executable")) is not str
                or not Path(engine["executable"]).is_absolute()
                or type(engine.get("rootless")) is not bool
                or type(engine.get("server_version")) is not str
                or not engine["server_version"]
                or binding.get("interpreter") != "python3"):
            raise BindingError("invalid Docker image/engine binding")
    else:
        raise BindingError("invalid execution mode")
    return binding


def from_preflight(report, *, native):
    mode = "native" if native else "dockerized"
    runtime = report.get("runtime_contract", {})
    if runtime.get("execution_mode") != mode:
        raise BindingError("missing or inconsistent preflight execution binding")
    observed = runtime.get("observations", {}).get("host" if native else "container", {})
    binding = {"schema_version": 1, "execution_mode": mode,
               "interpreter": observed.get("interpreter"),
               "interpreter_flags": observed.get("interpreter_flags")}
    if not native:
        for key in ("image_identity", "engine_identity"):
            binding[key] = observed.get(key)
    return copy.deepcopy(validate(binding))


def environment():
    env = observation.clean_environment()
    for key in ("LIBRELANE_IMAGE_OVERRIDE", "LIBRELANE_CONTAINER_ENGINE",
                "OPENLANE_CONTAINER_ENGINE", "_MOUNT_HOST_LIBRELANE"):
        env.pop(key, None)
    return env


def verify_image(binding):
    validate(binding)
    engine = binding["engine_identity"]["executable"]
    image = binding["image_identity"]["image_id"]
    actual = observation.output([engine, "image", "inspect", "--format", "{{.Id}}", image]).strip()
    if actual != image:
        raise BindingError(f"execution image ID mismatch: {actual!r}; expected {image}")
    return actual


def verify_engine(binding):
    """Check the selected executable still reaches the observed Docker server."""
    validate(binding)
    expected = binding["engine_identity"]
    argv = [expected["executable"], "info", "--format", "{{json .}}"]
    info = observation.decode(observation.output(argv))
    if type(info) is not dict or type(info.get("SecurityOptions")) is not list:
        raise BindingError("missing execution engine identity")
    actual = {"name": "docker", "executable": expected["executable"],
              "rootless": any("rootless" in str(s) for s in info["SecurityOptions"]),
              "server_version": info.get("ServerVersion"),
              "daemon_id": info.get("ID"), "name_on_server": info.get("Name")}
    for key, value in expected.items():
        if value is not None and actual.get(key) != value:
            raise BindingError(f"execution engine identity changed: {key}")
    return actual


def owned_name():
    return "hardcaml-asic-execution-" + uuid.uuid4().hex


def docker_command(binding, project, pdk_root, *, name, workdir=None, entrypoint="python3",
                   pdk=None):
    validate(binding)
    if (not re.fullmatch(r"hardcaml-asic-execution-[0-9a-f]{32}", name)
            or not Path(project).is_absolute() or not Path(pdk_root).is_absolute()
            or (workdir is not None and not Path(workdir).is_absolute())):
        raise BindingError("invalid owned container name or mount/workdir path")
    engine = binding["engine_identity"]
    argv = [engine["executable"], "run", "--rm", "--pull=never", "--name", name]
    if not engine["rootless"]:
        argv += ["--user", f"{os.getuid()}:{os.getgid()}"]
    argv += ["-v", f"{project}:{project}:rw", "-v", f"{pdk_root}:{pdk_root}:ro",
             "-w", str(workdir or project)]
    if pdk is not None:
        argv += ["-e", f"PDK_ROOT={pdk_root}", "-e", f"PDK={pdk}"]
    return argv + ["--entrypoint", entrypoint, binding["image_identity"]["image_id"]]


def cleanup(binding, name):
    """Remove only this launch's owned name, with a separate bounded deadline."""
    if not re.fullmatch(r"hardcaml-asic-execution-[0-9a-f]{32}", name):
        raise BindingError("invalid owned container name")
    try:
        observation.output([binding["engine_identity"]["executable"], "rm", "-f", name],
                           timeout=observation.CLEANUP_TIMEOUT)
    except observation.ObservationError as exc:
        if "No such container" not in str(exc) and "no container" not in str(exc):
            raise
