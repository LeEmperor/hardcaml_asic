"""Full production shared-runner sequence; raw evidence stays in explicit workspace.

Uses only existing callbacks. Renames every producer run immediately after ready
publication, proving consumers do not need original backend output paths.
No provisioning, source-bundle edits, observation journal or Dune subprocesses.
"""
import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "flow"))
from hardcaml_asic_flow import checkpoint as cp, execution_plan as plans, runner, stages


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
    summary = {"binding": adapter.compatibility["binding"],
               "bridge_sha256": adapter.compatibility["bridge_sha256"],
               "bundle_identity": adapter.compatibility["bundle_identity"],
               "segments": [], "acceptance": "not_evaluated"}
    def lifecycle(event, action, occurrence, artifact):
        if event != "finished" or not artifact:
            return
        manifest = cp.validate(artifact["path"], compatibility=adapter.compatibility)
        report = cp.read(Path(artifact["path"]) / "segment.json")
        original = Path(report["run_dir"])
        original.rename(args.workspace / ("retained-" + action.stage))
        summary["segments"].append({"artifact": artifact, "seconds": occurrence["duration_seconds"],
                                   "from": report["from"], "to": report["to"],
                                   "returned_steps": report["returned_steps"],
                                   "configured_gates": report["configured_gates"],
                                   "external_files": len(manifest["external"]),
                                   "closure_sha256": cp.digest(Path(artifact["path"]) / "closure.json"),
                                   "resolved_sha256": cp.digest(Path(artifact["path"]) / "resolved.json"),
                                   "manifest_sha256": cp.digest(Path(artifact["path"]) / "manifest.json"),
                                   "copied_views": sum(name.startswith("views/") for name in manifest["files"]),
                                   "unavailable_metrics": sum(m["availability"] == "unavailable" for m in manifest["metrics"].values()),
                                   "original_run_absent": not original.exists()})
        (args.workspace / "summary.json").write_text(json.dumps(summary, indent=2, allow_nan=False))
        print(action.stage, occurrence["duration_seconds"], "published", flush=True)
    plan = plans.resolve_sequence(plans.STAGE_ORDER)
    execution = runner.execute(plan, adapter, lifecycle=lifecycle)
    (args.workspace / "execution.json").write_text(json.dumps(execution.as_dict(), indent=2, allow_nan=False))
    if execution.exit_code:
        raise RuntimeError(execution.as_dict())
    print("PASSED", args.workspace / "summary.json")


if __name__ == "__main__":
    main()
