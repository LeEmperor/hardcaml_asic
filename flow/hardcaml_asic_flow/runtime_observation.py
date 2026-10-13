"""Bounded, metadata-only runtime observations shared by provision and preflight.

Host paths are literal (venv symlinks must not be resolved). Container tags are
inspected once; probes bind to the local image ID, never to a RepoDigest. An
isolated import is attempted first. Nix images may require their own PYTHONPATH:
only a metadata import failure permits a second -B probe preserving image-owned
packaging paths. No host variables are forwarded into the container. The chosen
interpreter_flags are recorded for the later launch transport to reuse.

Every created container has a UUID-owned name and is removed with a separately
bounded rm -f even on timeout/interruption. No pulls, mounts, installs or caches.
"""

import argparse
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import uuid

from . import runtime_contract as rc

TIMEOUT = 20
CLEANUP_TIMEOUT = 5


class ObservationError(ValueError):
    pass


METADATA_CODE = '''import json, sys
from importlib.metadata import distribution
result = {"python_version": ".".join(map(str, sys.version_info[:3])),
          "librelane_version": None, "requires_python": None, "metadata_error": None}
try:
    dist = distribution("librelane")
    result.update(librelane_version=dist.version, requires_python=dist.metadata.get("Requires-Python"))
except Exception as exc:
    result["metadata_error"] = str(exc)
'''
HOST_CODE = METADATA_CODE + '''result["tcl"] = {"ready": False, "version": None, "error": None}
try:
    import tkinter, _tkinter
    tcl = tkinter.Tcl()
    if str(tcl.eval("expr {6 * 7}")) != "42":
        raise ValueError("Tcl expression failed")
    result["tcl"].update(ready=True, version=str(tcl.eval("info patchlevel")))
except Exception as exc:
    result["tcl"]["error"] = str(exc)
print(json.dumps(result, allow_nan=False))
'''
CONTAINER_CODE = METADATA_CODE + 'print(json.dumps(result, allow_nan=False))\n'


def clean_environment():
    """Sanitize a child copy only, as the managed Python readiness helper does."""
    return {k: v for k, v in os.environ.items()
            if k not in ("PYTHONHOME", "PYTHONPATH", "TCL_LIBRARY", "TK_LIBRARY",
                         "TCLLIBPATH", "GCONV_PATH", "GLIBC_TUNABLES")
            and not k.startswith(("LD_", "DYLD_"))}


def output(argv, *, timeout=TIMEOUT):
    try:
        result = subprocess.run(argv, capture_output=True, text=True, check=False,
                                timeout=timeout, env=clean_environment())
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ObservationError(f"runtime probe {argv[:3]!r}: {exc}") from exc
    if result.returncode:
        raise ObservationError(f"runtime probe {argv[:3]!r}: {result.stderr.strip()}")
    return result.stdout


def decode(text):
    def invalid(value):
        raise ObservationError(f"nonfinite JSON: {value}")
    try:
        value = json.loads(text, parse_constant=invalid)
        def finite(item):
            if isinstance(item, float) and not math.isfinite(item):
                raise ObservationError("nonfinite JSON number")
            if isinstance(item, dict):
                for child in item.values():
                    finite(child)
            elif isinstance(item, list):
                for child in item:
                    finite(child)
        finite(value)
        return value
    except (ValueError, TypeError) as exc:
        raise ObservationError(f"invalid runtime JSON: {exc}") from exc


def metadata(text, *, host=False):
    value = decode(text)
    if type(value) is not dict:
        raise ObservationError("runtime metadata must be an object")
    for key in ("python_version", "librelane_version", "requires_python", "metadata_error"):
        if key not in value or (value[key] is not None and type(value[key]) is not str):
            raise ObservationError(f"invalid or missing runtime metadata: {key}")
    if not isinstance(value["python_version"], str):
        raise ObservationError("missing Python version")
    if host:
        tcl = value.get("tcl")
        if (type(tcl) is not dict or type(tcl.get("ready")) is not bool
                or any(k not in tcl or (tcl[k] is not None and type(tcl[k]) is not str)
                       for k in ("version", "error"))):
            raise ObservationError("invalid or missing Tcl readiness")
    return value


def observe_host(python):
    literal = str(python)
    value = metadata(output([literal, "-I", "-B", "-c", HOST_CODE]), host=True)
    value.update(interpreter=literal, interpreter_flags=["-I", "-B"])
    return value


def observe_container(image_ref, *, engine="docker"):
    """Explicit Docker/Podman metadata readiness, not Podman runner support."""
    if engine not in ("docker", "podman"):
        raise ObservationError("unsupported metadata engine")
    executable = shutil.which(engine)
    if not executable:
        raise ObservationError(f"{engine} not installed")
    info = decode(output([executable, "info", "--format", "{{json .}}"]))
    if type(info) is not dict:
        raise ObservationError("invalid engine info")
    images = decode(output([executable, "image", "inspect", image_ref]))
    if type(images) is not list or len(images) != 1 or type(images[0]) is not dict:
        raise ObservationError("invalid image inspection")
    image = images[0]
    image_id = image.get("Id")
    if type(image_id) is not str or not re.fullmatch(r"sha256:[0-9a-f]{64}", image_id):
        raise ObservationError("invalid local image ID")
    digests = image.get("RepoDigests")
    if digests is None:
        digests = []
    if type(digests) is not list or any(type(d) is not str for d in digests):
        raise ObservationError("invalid RepoDigests")
    if any(type(image.get(k)) is not str or not image[k] for k in ("Os", "Architecture")):
        raise ObservationError("missing image platform")
    identity = {"declared_ref": image_ref, "image_id": image_id,
                "repo_digests": digests,
                "platform": {"os": image["Os"], "architecture": image["Architecture"],
                             "variant": image.get("Variant")},
                "binding": "local-image-id"}
    security = info.get("SecurityOptions")
    rootless = (any("rootless" in str(s) for s in security)
                if type(security) is list else None)
    if engine == "podman":
        host_info = info.get("host", {})
        if type(host_info) is not dict or type(host_info.get("security", {})) is not dict:
            raise ObservationError("invalid Podman engine identity")
        rootless = host_info.get("security", {}).get("rootless")
        if rootless is not None and type(rootless) is not bool:
            raise ObservationError("invalid Podman rootless flag")
    engine_identity = {"name": engine, "executable": executable,
                       "server_version": info.get("ServerVersion"), "rootless": rootless,
                       "daemon_id": info.get("ID"), "name_on_server": info.get("Name")}

    def probe(flags):
        name = "hardcaml-asic-metadata-" + uuid.uuid4().hex
        argv = [executable, "run", "--rm", "--pull=never", "--network", "none",
                "--read-only", "--name", name, "--entrypoint", "python3",
                image_id, *flags, "-c", CONTAINER_CODE]
        try:
            return metadata(output(argv))
        finally:
            # Killing the client cannot stop a daemon-owned container.
            try:
                output([executable, "rm", "-f", name], timeout=CLEANUP_TIMEOUT)
            except ObservationError as exc:
                # --rm normally already removed it. Other failures must be visible.
                if "No such container" not in str(exc) and "no container" not in str(exc):
                    raise

    flags = ["-I", "-B"]
    value = probe(flags)
    if value["metadata_error"]:
        flags = ["-B"]
        value = probe(flags)
    if value["metadata_error"] or not value["librelane_version"] or not value["requires_python"]:
        raise ObservationError(f"missing container distribution metadata: {value}")
    value.update(interpreter="python3", interpreter_flags=flags,
                 packaging_path="isolated" if "-I" in flags else "image-owned-environment",
                 image_identity=identity, engine_identity=engine_identity)
    return value


def evaluate_observations(contract, host, container=None, *, native=False,
                          allow_python_mismatch=False):
    """Shared policy plus exact host LibreLane and honest headless Tcl readiness."""
    result = rc.evaluate(contract, host, container, native=native,
                         allow_python_mismatch=allow_python_mismatch)
    for field, expected, actual in (
        ("librelane_version", contract["librelane"], host.get("librelane_version")),
        ("tcl_ready", True, host.get("tcl", {}).get("ready")),
    ):
        row = {"role": "host", "field": field, "expected": expected, "actual": actual,
               "status": "pass" if type(actual) is type(expected) and actual == expected else "fail"}
        result["comparisons"].append(row)
        if row["status"] == "fail":
            result["issues"].append(row.copy())
    return result


def evaluate_container(contract, container):
    """Provision's applicable subset; existing host/base/precheck checks stay separate."""
    result = rc.evaluate(contract, {"python_version": contract["host"]["python"]["version"] + ".0"}, container)
    for key in ("comparisons", "issues", "waivers"):
        result[key] = [row for row in result[key] if row["role"] == "container"]
    return result


def read_lock(path):
    values = {}
    for line in Path(path).read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or key in values:
            raise rc.ContractError("malformed or duplicate lock entry")
        values[key] = value
    return values


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("policy", "container"))
    parser.add_argument("--lock", required=True)
    parser.add_argument("--engine", choices=("docker", "podman"), default="docker")
    args = parser.parse_args(argv)
    try:
        contract = rc.policy_from_lock(read_lock(args.lock))
        result = {"authority": "provisioning-lock", "normalized_policy": contract}
        if args.action == "container":
            observation = observe_container(contract["implementation"]["dockerized"]["image_ref"], engine=args.engine)
            result.update(observation=observation, evaluation=evaluate_container(contract, observation))
        print(json.dumps(result, allow_nan=False, sort_keys=True))
        return 5 if result.get("evaluation", {}).get("issues") else 0
    except rc.ContractError as exc:
        print(str(exc), file=sys.stderr)
        return 3
    except (ObservationError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 7


if __name__ == "__main__":
    sys.exit(main())
