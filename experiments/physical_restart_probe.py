"""Official-API boundary proof before enabling production restart capabilities.

Uses the existing transport and publisher; experimental bridge changes are confined
to the fresh external workspace. No provisioning, source-bundle edits or Dune calls.
"""
import argparse
import json
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "flow"))
from hardcaml_asic_flow import checkpoint as cp, stages


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--consumer", type=Path, required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--workspace", type=Path, required=True)
    args = parser.parse_args()
    tools = args.consumer.resolve() / "_flow_tools"
    adapter = stages.prepare(bundle=args.bundle, support_tools=tools / "tt", pdk_root=tools / "pdk",
                             python=tools / ".venv/bin/python", workspace=args.workspace,
                             checkpoint_store=args.workspace / "checkpoints", timeout=7200)
    bridge = adapter.project / "bridge/librelane_bridge.py"
    legacy_bridge = '"routing": "OpenROAD.DetailedRouting"' not in bridge.read_text()
    text = bridge.read_text().replace(
        '"placement": "OpenROAD.DetailedPlacement"}',
        '"placement": "OpenROAD.DetailedPlacement", "cts": "OpenROAD.CTS", '
        '"routing": "OpenROAD.DetailedRouting", "signoff": "Misc.ReportManufacturability"}')
    text = text.replace('ENDPOINTS["synthesis"]) + 1', 'ENDPOINTS[request["source_boundary"]]) + 1')
    text = text.replace('if frm != "Checker.YosysUnmappedCells":', 'if ids.index(frm) > ids.index(ENDPOINTS[boundary]):')
    bridge.write_text(text)
    adapter.compatibility["bridge_sha256"] = cp.digest(bridge)
    source = None
    summary = {"binding": adapter.compatibility["binding"], "bridge_sha256": cp.digest(bridge),
               "segments": [], "acceptance": "not_evaluated"}
    for boundary in ("synthesis", "floorplan", "placement", "cts", "routing", "signoff"):
        tag = "probe-" + boundary
        candidate = adapter.project / "candidates" / tag
        candidate.parent.mkdir(exist_ok=True)
        request = {"boundary": boundary, "source_boundary": source["boundary"] if source else None,
                   "checkpoint": source["path"] if source else None,
                   "candidate": str(candidate), "project": str(adapter.project),
                   "pdk_root": str(adapter.pdk_root), "tag": tag, "bridge_sha256": cp.digest(bridge)}
        request_path = adapter.project / (tag + "-request.json")
        request_path.write_text(cp.canonical(request))
        started = time.monotonic()
        code = adapter.launch(bridge, request_path, tag)
        entry = {"boundary": boundary, "exit_code": code, "seconds": round(time.monotonic() - started, 3)}
        summary["segments"].append(entry)
        (args.workspace / "probe-summary.json").write_text(json.dumps(summary, indent=2))
        if code:
            raise RuntimeError(entry)
        report = cp.read(candidate / "segment.json")
        entry.update(report)
        # Before production schema expansion the publisher only knows the first
        # three boundaries. Keep later proof views in a private snapshot, using
        # the same publisher under its physical view contract (never advertise it).
        published_boundary = (boundary if not legacy_bridge or boundary in ("synthesis", "floorplan", "placement")
                              else "placement")
        if published_boundary != boundary:
            report["boundary"] = published_boundary
            (candidate / "segment.json").write_text(cp.canonical(report))
        def validate_runtime(private):
            validation = dict(request, mode="validate_publication", candidate=str(private))
            path = adapter.project / (tag + "-validation.json")
            path.write_text(cp.canonical(validation))
            if adapter.launch(bridge, path, tag + "-validation"):
                raise ValueError("runtime closure mismatch")
        artifact = cp.publish(candidate, adapter.checkpoint_store, compatibility=adapter.compatibility,
                              boundary=published_boundary, validate_runtime=validate_runtime)
        source = dict(artifact, boundary=boundary)
        entry["artifact"] = artifact
        original = Path(entry["run_dir"])
        original.rename(args.workspace / ("retained-" + boundary))
        entry["original_run_absent"] = not original.exists()
        (args.workspace / "probe-summary.json").write_text(json.dumps(summary, indent=2, allow_nan=False))
        print(boundary, entry["seconds"], "passed", flush=True)


if __name__ == "__main__":
    main()
