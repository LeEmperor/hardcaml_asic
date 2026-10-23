"""Explicitly transported isolated-runtime bridge; official Classic APIs only.

No host imports, substitutions, step hooks or alternate sequencing engine. The
host owns the process and publication. This module emits a candidate only after
Flow.start (including final snapshot and deferred checks) returns successfully.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import types

from librelane.common import Path as ToolPath
from librelane.flows import Flow
from librelane.state import State


ENDPOINTS = {"synthesis": "Yosys.Synthesis", "floorplan": "OpenROAD.Floorplan",
             "placement": "OpenROAD.DetailedPlacement", "cts": "OpenROAD.CTS",
             "routing": "OpenROAD.DetailedRouting", "timing": "OpenROAD.STAPostPNR",
             "signoff": "Misc.ReportManufacturability"}
SUCCESSORS = {"synthesis": "Checker.YosysUnmappedCells", "floorplan": "OpenROAD.DumpRCValues",
              "placement": "OpenROAD.CTS", "cts": "OpenROAD.STAMidPNR-1",
              "routing": "Odb.RemoveRoutingObstructions", "timing": "OpenROAD.IRDropReport"}
RESTART_TARGETS = {"synthesis": ("floorplan", "placement"), "floorplan": ("placement",),
                   "placement": ("cts",), "cts": ("routing",), "routing": ("timing",),
                   "timing": ("signoff",)}

# This literal is part of the bridge digest used by checkpoint compatibility.
# Load only these verified bytes, including under Python -I (no sys.path edits).
PROTOCOL_SHA256 = "eb6490db856f551ffe2ab35ea872bdc85c86801339e67a9d5bdf427238b25ae1"


def protocol_module():
    support = Path(__file__).with_name("backend_protocol.py")
    source = support.read_bytes()
    if hashlib.sha256(source).hexdigest() != PROTOCOL_SHA256:
        raise ValueError("transported backend protocol hash mismatch")
    module = types.ModuleType("backend_protocol")
    exec(compile(source, str(support), "exec"), module.__dict__)
    return module


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def record(path):
    path = Path(path)
    if not path.is_file():
        raise ValueError(f"missing declared dependency: {path}")
    return {"sha256": digest(path), "bytes": path.stat().st_size}


def metrics(raw):
    result = {}
    for key, value in raw.items():
        # Backend sentinels stay raw in state.json. No finite surrogate or zero.
        try:
            finite = not isinstance(value, (str, bool)) and math.isfinite(value)
        except (TypeError, ValueError, OverflowError):
            finite = False
        result[key] = ({"availability": "available", "value": float(value)} if finite else
                       {"availability": "unavailable", "reason": "nonfinite_or_nonnumeric",
                        "raw": str(value)})
    return result


def closure(config, project, pdk_root):
    """Conservative declared closure, not a minimal artifact cache.

    Inventory typed config paths recursively (including corners/lists), all
    bundle inputs and support references, and the entire target PDK tree to cover
    indirect Tcl/collateral reads. Runtime-only files are tied to the exact image.
    MACROS are deliberately unsupported until a complete macro contract is proved.
    """
    if config.get("MACROS"):
        raise ValueError("macro handoffs are not supported by this bounded contract")
    paths = set()

    def tree(path, ancestors=()):
        path = Path(path)
        resolved = path.resolve(strict=True)
        if resolved in ancestors:
            raise ValueError(f"cyclic dependency directory: {path}")
        if path.is_dir():
            for child in sorted(path.iterdir()):
                tree(child, (*ancestors, resolved))
        else:
            paths.add(str(path.absolute()))

    def visit(value):
        if isinstance(value, ToolPath):
            tree(value)
        elif isinstance(value, dict):
            for child in value.values():
                visit(child)
        elif isinstance(value, (list, tuple)):
            for child in value:
                visit(child)

    for key, value in config.items():
        if key not in ("DESIGN_DIR", "PDK_ROOT"):
            visit(value)
    manifest_path = project / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    paths.add(str(manifest_path))
    for entry in manifest["files"]:
        tree(project / entry["path"])
    for ref in manifest["target"]["external_references"]:
        if ref["source"] == "Support_tools":
            tree(project / "tt" / ref["path"])
    tree(pdk_root / manifest["target"]["technology"])
    return {p: record(p) for p in sorted(paths)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("request", type=Path)
    args = parser.parse_args()
    protocol = protocol_module()
    request = protocol.validate_request(protocol.loads(args.request.read_text(encoding="utf-8")))
    if digest(__file__) != request["bridge_sha256"]:
        raise ValueError("transported bridge hash mismatch")
    if Path(request["reply_path"]).exists():
        raise ValueError("backend reply must be fresh")
    try:
        execute(request)
        protocol.write_reply(request)
    except Exception as exc:
        # Ordinary backend failures have diagnostic replies AND nonzero exit.
        # BaseException (signals/SystemExit/KeyboardInterrupt) is never completed.
        protocol.write_reply(request, error=str(exc) or type(exc).__name__)
        raise


def execute(request):
    project, pdk = Path(request["project"]), Path(request["pdk_root"])
    candidate = Path(request["candidate"])
    boundary = request["boundary"]
    validating = request["operation"] == "validate_publication"
    if not validating:
        candidate.mkdir()  # fresh output only, never read a stale success file
    classic = Flow.factory.get("Classic")
    flow = classic(str(project / "src/config.json"), pdk_root=str(pdk))
    resolved = flow.config.dumps()
    dependencies = closure(flow.config, project, pdk)
    if validating:
        if resolved != (candidate / "resolved.json").read_text():
            raise ValueError("publication resolved configuration mismatch")
        if dependencies != json.loads((candidate / "closure.json").read_text()):
            raise ValueError("publication config/input/collateral/runtime closure mismatch")
        return  # no Flow.start; validation cannot produce readiness or artifacts
    initial, frm = None, None
    if request["checkpoint"] is not None:
        source = Path(request["checkpoint"])
        if resolved != (source / "resolved.json").read_text():
            raise ValueError("resolved configuration mismatch before continuation")
        if dependencies != json.loads((source / "closure.json").read_text()):
            raise ValueError("configuration/input/collateral closure mismatch before continuation")
        initial = State.loads((source / "state.json").read_text())
        initial.validate()
        ids = [cls.id for cls in flow.Steps]
        source_boundary = request["source_boundary"]
        source_manifest = json.loads((source / "manifest.json").read_text())
        if source_manifest["boundary"] != source_boundary or boundary not in RESTART_TARGETS.get(source_boundary, ()):
            raise ValueError("unsupported checkpoint transition")
        frm = ids[ids.index(ENDPOINTS[source_boundary]) + 1]
        if frm != SUCCESSORS[source_boundary] or ids.index(frm) > ids.index(ENDPOINTS[boundary]):
            raise ValueError("unsupported Classic immediate successor")
    elif boundary != "synthesis":
        raise ValueError("physical segment requires a tested checkpoint")
    state = flow.start(tag=request["tag"], with_initial_state=initial,
                       frm=frm, to=ENDPOINTS[boundary])
    # Mutation during a segment invalidates publication even after tool success.
    if closure(flow.config, project, pdk) != dependencies:
        raise ValueError("declared closure changed during segment")
    if not flow.step_objects or flow.step_objects[-1].id != ENDPOINTS[boundary]:
        raise ValueError("endpoint was not reached")
    if initial is not None and flow.step_objects[0].id != frm:
        raise ValueError("successor checks were not preserved")
    (candidate / "state.json").write_text(state.dumps())
    (candidate / "resolved.json").write_text(resolved)
    (candidate / "closure.json").write_text(json.dumps(dependencies, allow_nan=False))
    report = {"status": "completed", "boundary": boundary, "from": frm,
              "source_boundary": request.get("source_boundary"),
              "to": ENDPOINTS[boundary], "run_dir": flow.run_dir,
              "returned_steps": [step.id for step in flow.step_objects],
              "bridge_sha256": digest(__file__), "metrics": metrics(dict(state.metrics)),
              "metric_origin": "cumulative_final_state; not per-step measurement provenance",
              "configured_gates": {pattern: {var: flow.config[var] for var in variables}
                                   for pattern, variables in flow.gating_config_vars.items()},
              "gate_evidence": "configured Classic gates; returned_steps are successful outer step objects, not body/skip provenance",
              "acceptance": "not_evaluated"}
    (candidate / "segment.json").write_text(json.dumps(report, allow_nan=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
