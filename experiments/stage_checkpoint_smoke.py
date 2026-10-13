"""Production adapter smoke, retaining raw outputs in caller-selected workspace.

One shared-runner composed recipe and one independent resume from its synthesis
handoff. No observation instrumentation, provisioning or Dune subprocesses.
"""

import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "flow"))
from hardcaml_asic_flow import checkpoint, execution_plan, runner, stages


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--consumer", type=Path, required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--workspace", type=Path, required=True)
    args = parser.parse_args()
    tools = args.consumer.resolve() / "_flow_tools"
    workspace = args.workspace.absolute()
    adapter = stages.prepare(bundle=args.bundle, support_tools=tools / "tt", pdk_root=tools / "pdk",
                             python=tools / ".venv/bin/python", workspace=workspace,
                             checkpoint_store=workspace / "checkpoints")
    floorplan = runner.execute(execution_plan.resolve_stages("floorplan"), adapter)
    (workspace / "floorplan-execution.json").write_text(json.dumps(floorplan.as_dict(), indent=2))
    if floorplan.exit_code:
        raise RuntimeError(floorplan.as_dict())
    synthesis = floorplan.artifacts[0]["path"]
    report = checkpoint.read(Path(synthesis) / "segment.json")
    original = Path(report["run_dir"])
    original.rename(workspace / "retained-synthesis")
    # Same explicit binding/transport, a separately useful stage API/recipe. It
    # cannot select a newest run, reuse the original state paths or bypass checks.
    physical = stages.SegmentAdapter(project=adapter.project, pdk_root=adapter.pdk_root,
                                    compatibility=adapter.compatibility, launch=adapter.launch,
                                    checkpoint_store=adapter.checkpoint_store,
                                    initial_checkpoint=synthesis)
    placement = runner.execute(execution_plan.resolve_stages("placement", resume=True), physical)
    (workspace / "placement-execution.json").write_text(json.dumps(placement.as_dict(), indent=2))
    if placement.exit_code:
        raise RuntimeError(placement.as_dict())
    summary = {"designation": "real production adapter consumer smoke; not acceptance",
               "workspace": str(workspace), "bundle_identity": adapter.compatibility["bundle_identity"],
               "binding": adapter.compatibility["binding"],
               "bridge_sha256": adapter.compatibility["bridge_sha256"],
               "original_synthesis_run_absent": not original.exists(), "segments": []}
    for artifact in [*floorplan.artifacts, *placement.artifacts]:
        manifest = checkpoint.validate(artifact["path"], compatibility=adapter.compatibility)
        segment = checkpoint.read(Path(artifact["path"]) / "segment.json")
        summary["segments"].append({"artifact": artifact, "from": segment["from"], "to": segment["to"],
                                    "returned_steps": segment["returned_steps"],
                                    "manifest_sha256": checkpoint.digest(Path(artifact["path"]) / "manifest.json"),
                                    "files": manifest["files"], "external_files": len(manifest["external"]),
                                    "unavailable_metrics": sum(m["availability"] == "unavailable"
                                                               for m in manifest["metrics"].values())})
    path = workspace / "summary.json"
    path.write_text(json.dumps(summary, indent=2, allow_nan=False) + "\n")
    print(f"PASSED {path}")


if __name__ == "__main__":
    main()
