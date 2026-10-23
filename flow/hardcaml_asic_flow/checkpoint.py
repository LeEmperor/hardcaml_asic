"""Atomic, content-checked, path-bound handoffs; never mutable run workspaces.

Backend state JSON is opaque official serialization (it can contain Infinity).
The public manifest and metric representation are strict JSON. External closure
is explicit: host files are checked here, image-only files by the bridge before
Flow.start. A checkpoint is ready only after publish returns.
"""

import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import tempfile

from .execution_plan import BOUNDARIES, RESTART_TARGETS, TESTED_IMAGE


class CheckpointError(ValueError):
    pass


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)


def identity(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def read(path):
    def pairs(items):
        value = {}
        for key, item in items:
            if key in value:
                raise CheckpointError(f"duplicate public JSON key: {key}")
            value[key] = item
        return value
    def invalid(value):
        raise CheckpointError(f"nonfinite public JSON: {value}")
    value = json.loads(Path(path).read_text(), object_pairs_hook=pairs, parse_constant=invalid)
    # JSON exponent overflow bypasses parse_constant (e.g. 1e999).
    try:
        canonical(value)
    except ValueError as exc:
        raise CheckpointError("nonfinite public JSON") from exc
    return value


def file_record(path):
    path = Path(path)
    if not path.is_file():
        raise CheckpointError(f"missing artifact: {path}")
    return {"sha256": digest(path), "bytes": path.stat().st_size}


def valid_record(value):
    return (isinstance(value, dict) and set(value) == {"sha256", "bytes"}
            and isinstance(value["sha256"], str)
            and re.fullmatch(r"[0-9a-f]{64}", value["sha256"]) is not None
            and type(value["bytes"]) is int and value["bytes"] >= 0)


def state_paths(value):
    """All non-null state view leaves must be paths, including lists/corners."""
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        return [p for child in value.values() for p in state_paths(child)]
    if isinstance(value, list):
        return [p for child in value for p in state_paths(child)]
    raise CheckpointError("invalid state view leaf")


def validate(path, *, compatibility, restart=False, restart_to=None, check_external=True, _location=None):
    path = Path(path).absolute()
    location = path if _location is None else Path(_location)
    manifest = read(path / "manifest.json")
    fields = {"schema_version", "identity", "location", "boundary", "restart_supported",
              "compatibility", "files", "external", "metrics", "acceptance"}
    version = manifest.get("schema_version") if isinstance(manifest, dict) else None
    if version == 2:
        fields |= {"restart_targets", "tested_image_id", "closure_scope"}
    if (not isinstance(manifest, dict) or set(manifest) != fields
            or type(version) is not int or version not in (1, 2)):
        raise CheckpointError("unsupported checkpoint manifest")
    unsigned = {k: v for k, v in manifest.items() if k != "identity"}
    if manifest["identity"] != identity(unsigned) or manifest["location"] != str(location):
        raise CheckpointError("checkpoint identity/location mismatch")
    if manifest["compatibility"] != compatibility:
        raise CheckpointError("incompatible target, tools, runtime, bridge or workspace")
    boundary = manifest["boundary"]
    targets = (("floorplan", "placement") if boundary == "synthesis" else ()) if version == 1 else RESTART_TARGETS.get(boundary, ())
    if version == 2 and boundary == "routing" and manifest.get("restart_targets") == ["signoff"]:
        targets = ("signoff",)  # historical evidence; bridge compatibility still gates restart
    if (boundary not in (BOUNDARIES if version == 2 else ("synthesis", "floorplan", "placement"))
            or manifest["restart_supported"] is not bool(targets)
            or manifest["acceptance"] != "not_evaluated"):
        raise CheckpointError("invalid boundary capability")
    if version == 2 and (manifest["restart_targets"] != list(targets)
                         or manifest["tested_image_id"] != TESTED_IMAGE
                         or manifest["closure_scope"] != "path_bound"):
        raise CheckpointError("invalid tested restart/closure capability")
    if restart and not manifest["restart_supported"]:
        raise CheckpointError("checkpoint has no tested restart target")
    if restart_to is not None and restart_to not in targets:
        raise CheckpointError(f"untested restart transition: {boundary} -> {restart_to}")
    if version == 2:
        binding = compatibility.get("binding")
        image = binding.get("image_identity") if isinstance(binding, dict) else None
        if not isinstance(image, dict) or image.get("image_id") != TESTED_IMAGE:
            raise CheckpointError("restart eligibility is tested only in the declared exact image")
    files = manifest["files"]
    if (not isinstance(files, dict) or not all(isinstance(name, str) and valid_record(record)
                                             for name, record in files.items())):
        raise CheckpointError("malformed checkpoint file inventory")
    if not {"state.json", "resolved.json", "closure.json", "segment.json"} <= set(files):
        raise CheckpointError("incomplete checkpoint metadata")
    actual = {str(p.relative_to(path)) for p in path.rglob("*") if p.is_file()}
    if actual != set(files) | {"manifest.json"}:
        raise CheckpointError("checkpoint file inventory mismatch")
    for name, expected in files.items():
        child = path / name
        if (Path(name).is_absolute() or ".." in Path(name).parts or child.is_symlink()
                or not child.resolve().is_relative_to(path.resolve())
                or file_record(child) != expected):
            raise CheckpointError(f"missing/corrupt checkpoint artifact: {name}")
    state = json.loads((path / "state.json").read_text())
    if not isinstance(state, dict) or not isinstance(state.get("metrics"), dict):
        raise CheckpointError("malformed official state")
    views = {key: value for key, value in state.items() if key != "metrics"}
    paths = state_paths(views)
    required = ("nl", "json_h") if manifest["boundary"] == "synthesis" else ("odb", "def")
    if any(not views.get(key) for key in required):
        raise CheckpointError("missing required boundary view")
    for name in paths:
        child = Path(name)
        if not child.is_absolute() or not child.is_relative_to(location / "views"):
            raise CheckpointError("state view escapes checkpoint")
        if str(child.relative_to(location)) not in files:
            raise CheckpointError("state view not inventoried")
    closure = read(path / "closure.json")
    if (closure != manifest["external"] or not isinstance(closure, dict) or not closure
            or not all(isinstance(name, str) and Path(name).is_absolute() and valid_record(record)
                       for name, record in closure.items())):
        raise CheckpointError("missing declared config/input/collateral closure")
    if not isinstance(manifest["metrics"], dict):
        raise CheckpointError("malformed public metrics")
    for metric in manifest["metrics"].values():
        if not isinstance(metric, dict) or metric.get("availability") not in ("available", "unavailable"):
            raise CheckpointError("metric must declare availability")
        if metric["availability"] == "available" and (
                type(metric.get("value")) not in (int, float) or not math.isfinite(metric["value"])):
            raise CheckpointError("available metric must be finite numeric evidence")
    if check_external:
        for name, expected in closure.items():
            if not Path(name).is_absolute():
                raise CheckpointError("external dependency must be an absolute declared path")
            # These paths are inside the immutable image, unavailable on host.
            if not name.startswith("/nix/store/") and file_record(name) != expected:
                raise CheckpointError(f"changed external dependency: {name}")
    return manifest


def publish(candidate, store, *, compatibility, boundary, validate_runtime=None):
    """Copy all views; atomically rename a verified, read-only publication.

    No overwrite, no partial ready directory, no caching. Store/retention are
    caller-owned. Location is intentional: cross-machine relocation is unsupported.
    """
    candidate, store = Path(candidate), Path(store).absolute()
    if not store.is_dir():
        raise CheckpointError("checkpoint store must already exist")
    report = read(candidate / "segment.json")
    if not isinstance(report, dict) or report.get("status") != "completed" or report.get("boundary") != boundary:
        raise CheckpointError("cannot publish an unsuccessful segment")
    tmp = Path(tempfile.mkdtemp(prefix=".publishing-", dir=store))
    # Unique names avoid overwrites, and are independent of recipe/run identity.
    final = store / (boundary + "-" + tmp.name.removeprefix(".publishing-"))
    promoted = False
    try:
        state = json.loads((candidate / "state.json").read_text())
        count = 0

        def copy(value):
            nonlocal count
            if value is None:
                return None
            if isinstance(value, dict):
                return {k: copy(v) for k, v in value.items()}
            if isinstance(value, list):
                return [copy(v) for v in value]
            if not isinstance(value, str):
                raise CheckpointError("invalid state view")
            source = Path(value)
            file_record(source)
            count += 1
            name = f"views/{count:05d}-{source.name}"
            (tmp / name).parent.mkdir(exist_ok=True)
            shutil.copyfile(source, tmp / name)
            if file_record(source) != file_record(tmp / name):
                raise CheckpointError("view changed during publication")
            return str(final / name)

        for key in state:
            if key != "metrics":
                state[key] = copy(state[key])
        (tmp / "state.json").write_text(json.dumps(state, indent=2) + "\n")
        for name in ("resolved.json", "closure.json", "segment.json"):
            shutil.copyfile(candidate / name, tmp / name)
            if file_record(candidate / name) != file_record(tmp / name):
                raise CheckpointError("candidate metadata changed during publication")
        if boundary not in BOUNDARIES:
            raise CheckpointError("unsupported publication boundary")
        manifest = {"schema_version": 2, "location": str(final), "boundary": boundary,
                    "restart_supported": bool(RESTART_TARGETS[boundary]),
                    "restart_targets": list(RESTART_TARGETS[boundary]),
                    "tested_image_id": TESTED_IMAGE, "closure_scope": "path_bound",
                    "compatibility": compatibility,
                    "files": {str(p.relative_to(tmp)): file_record(p)
                              for p in tmp.rglob("*") if p.is_file()},
                    "external": read(tmp / "closure.json"), "metrics": report["metrics"],
                    "acceptance": "not_evaluated"}
        manifest["identity"] = identity(manifest)
        (tmp / "manifest.json").write_text(canonical(manifest) + "\n")
        validate(tmp, compatibility=compatibility, _location=final)
        if any(name.startswith("/nix/store/") for name in manifest["external"]):
            if validate_runtime is None:
                raise CheckpointError("image-only closure requires an explicit runtime validator before publication")
            validate_runtime(tmp)
            # The validator must not mutate the private publication candidate.
            validate(tmp, compatibility=compatibility, _location=final)
        for p in tmp.rglob("*"):
            p.chmod(0o555 if p.is_dir() else 0o444)
        tmp.chmod(0o555)
        if final.exists() or final.is_symlink():
            raise CheckpointError("checkpoint destination already exists")
        os.rename(tmp, final)
        promoted = True
        return {"path": str(final), "identity": manifest["identity"], "boundary": boundary,
                "restart_supported": manifest["restart_supported"],
                "restart_targets": manifest["restart_targets"], "closure_scope": "path_bound",
                "tested_image_id": TESTED_IMAGE, "acceptance": "not_evaluated"}
    except BaseException:
        for root in ((tmp, final) if promoted else (tmp,)):
            if root.exists():
                root.chmod(0o755)
                for p in root.rglob("*"):
                    p.chmod(0o755 if p.is_dir() else 0o644)
                shutil.rmtree(root)
        raise
