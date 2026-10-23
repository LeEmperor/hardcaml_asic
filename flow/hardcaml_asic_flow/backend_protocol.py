"""Version 1 backend wire contract. No backend state decoding or publication.

This stdlib-only resource is transported beside the isolated bridge. Its exact
bytes are pinned in that bridge, hence transitively in checkpoint compatibility.
Legacy unversioned requests are inspection evidence only, never executable v1.
Process failure/cancellation remains authoritative even if a reply exists.
"""

import hashlib
import json
import math
from pathlib import Path
import re

VERSION = 1
REQUEST_FIELDS = {"protocol_version", "operation", "request_id", "reply_path",
                  "boundary", "checkpoint", "source_boundary", "candidate",
                  "project", "pdk_root", "tag", "bridge_sha256"}
REPLY_FIELDS = {"protocol_version", "operation", "request_id", "request_sha256",
                "boundary", "candidate", "bridge_sha256", "outcome", "artifacts", "error"}
TRANSITIONS = {"synthesis": ("floorplan", "placement"), "floorplan": ("placement",),
               "placement": ("cts",), "cts": ("routing",), "routing": ("timing",), "timing": ("signoff",),
               "signoff": ()}
OPERATIONS = ("execute_segment", "validate_publication")


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)


def identity(value):
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def loads(text):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError("duplicate protocol field: " + key)
            result[key] = value
        return result
    def invalid(value):
        raise ValueError("nonfinite protocol JSON: " + value)
    value = json.loads(text, object_pairs_hook=pairs, parse_constant=invalid)
    def visit(value, depth=0):
        if depth > 256:
            raise ValueError("protocol JSON nesting limit")
        if isinstance(value, str):
            value.encode("utf-8")  # reject unpaired surrogates, do not repair
        elif isinstance(value, float) and not math.isfinite(value):
            raise ValueError("nonfinite protocol JSON")
        elif isinstance(value, dict):
            for key, child in value.items():
                visit(key, depth + 1)
                visit(child, depth + 1)
        elif isinstance(value, list):
            for child in value:
                visit(child, depth + 1)
    visit(value)
    return value


def exact(value, fields):
    if not isinstance(value, dict) or set(value) != set(fields):
        raise ValueError("missing/unknown protocol fields")


def text(value):
    if not isinstance(value, str) or not value or "\0" in value:
        raise ValueError("expected nonempty protocol string")
    value.encode("utf-8")


def path(value):
    text(value)
    if not value.startswith("/"):
        raise ValueError("expected absolute protocol path")


def sha(value):
    if not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None:
        raise ValueError("expected lowercase SHA-256")


def header(value):
    if type(value["protocol_version"]) is not int or value["protocol_version"] != VERSION:
        raise ValueError("unsupported backend protocol version")
    if value["operation"] not in OPERATIONS:
        raise ValueError("unsupported backend operation")
    text(value["request_id"])
    if not isinstance(value["boundary"], str) or value["boundary"] not in TRANSITIONS:
        raise ValueError("unknown backend boundary")
    path(value["candidate"])
    sha(value["bridge_sha256"])


def validate_request(value):
    exact(value, REQUEST_FIELDS)
    header(value)
    for key in ("reply_path", "project", "pdk_root"):
        path(value[key])
    text(value["tag"])
    if "/" in value["tag"] or value["tag"] in (".", ".."):
        raise ValueError("invalid backend tag")
    source = value["source_boundary"]
    checkpoint = value["checkpoint"]
    if value["operation"] == "validate_publication":
        if source is not None or checkpoint is not None:
            raise ValueError("publication validation has no continuation source")
    elif checkpoint is None:
        if source is not None or value["boundary"] != "synthesis":
            raise ValueError("fresh segment must be synthesis without a source")
    else:
        path(checkpoint)
        if (not isinstance(source, str) or
                (value["boundary"] not in TRANSITIONS.get(source, ())
                 and (source, value["boundary"]) != ("routing", "signoff"))):
            raise ValueError("unsupported backend source transition")
    if value["reply_path"] == value["candidate"]:
        raise ValueError("reply path aliases candidate")
    return value


def artifact_names(operation):
    return (("state.json", "resolved.json", "closure.json", "segment.json")
            if operation == "execute_segment" else ("resolved.json", "closure.json"))


def validate_reply(value, request):
    validate_request(request)
    exact(value, REPLY_FIELDS)
    header(value)
    sha(value["request_sha256"])
    if any(value[key] != request[key] for key in
           ("operation", "request_id", "boundary", "candidate", "bridge_sha256")):
        raise ValueError("backend reply/request mismatch")
    if value["request_sha256"] != identity(request):
        raise ValueError("backend reply request hash mismatch")
    if value["outcome"] not in ("completed", "validated", "failed"):
        raise ValueError("unknown backend outcome")
    if value["outcome"] == "failed":
        exact(value["artifacts"], ())
        text(value["error"])
    else:
        expected = "completed" if request["operation"] == "execute_segment" else "validated"
        if value["outcome"] != expected or value["error"] is not None:
            raise ValueError("inconsistent backend success")
        exact(value["artifacts"], artifact_names(request["operation"]))
        for name, evidence in value["artifacts"].items():
            exact(evidence, ("path", "sha256", "bytes"))
            if evidence["path"] != request["candidate"].rstrip("/") + "/" + name:
                raise ValueError("backend artifact path mismatch")
            sha(evidence["sha256"])
            if type(evidence["bytes"]) is not int or evidence["bytes"] < 0:
                raise ValueError("expected nonnegative artifact byte count")
    return value


def file_evidence(path):
    declared_path = str(path)
    path = Path(path)
    h = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
            size += len(block)
    return {"path": declared_path, "sha256": h.hexdigest(), "bytes": size}


def reply(request, *, error=None):
    validate_request(request)
    result = {key: request[key] for key in
              ("protocol_version", "operation", "request_id", "boundary", "candidate", "bridge_sha256")}
    result.update(request_sha256=identity(request), error=error,
                  outcome=("failed" if error is not None else
                           "completed" if request["operation"] == "execute_segment" else "validated"),
                  artifacts=({} if error is not None else
                             {name: file_evidence(request["candidate"].rstrip("/") + "/" + name)
                              for name in artifact_names(request["operation"])}))
    return validate_reply(result, request)


def write_reply(request, *, error=None):
    result = reply(request, error=error)
    # Exclusive fresh file. Partial writes cannot pass the strict host reader.
    with Path(request["reply_path"]).open("x", encoding="utf-8") as stream:
        stream.write(canonical(result) + "\n")


def read_reply(request):
    result = validate_reply(loads(Path(request["reply_path"]).read_text(encoding="utf-8")), request)
    if result["outcome"] == "failed":
        raise ValueError("backend failed: " + result["error"])
    for evidence in result["artifacts"].values():
        if file_evidence(evidence["path"]) != evidence:
            raise ValueError("backend artifact evidence mismatch")
    return result
