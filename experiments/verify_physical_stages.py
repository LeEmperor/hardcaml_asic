"""Re-audit retained production publications without rerunning physical tools."""
import argparse
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "flow"))
from hardcaml_asic_flow import checkpoint as cp, execution_plan as plans, stages


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("workspace", type=Path)
    parser.add_argument("--evidence", type=Path)
    args = parser.parse_args()
    summary = cp.read(args.workspace / "summary.json")
    execution = cp.read(args.workspace / "execution.json")
    assert execution["exit_code"] == 0 and execution["status"] == "completed"
    assert plans.StagePlan.from_dict(execution["plan"]).sequence == plans.STAGE_ORDER
    assert len(summary["segments"]) == len(plans.STAGE_ORDER)
    assert summary["bridge_sha256"] == cp.digest(Path(stages.__file__).with_name("librelane_bridge.py"))
    compatibility = None
    closures, configs = set(), set()
    previous = None
    for name, entry, artifact, occurrence in zip(plans.STAGE_ORDER, summary["segments"],
                                                execution["artifacts"], execution["occurrences"]):
        assert entry["artifact"] == artifact and artifact["boundary"] == name
        path = Path(artifact["path"])
        compatibility = compatibility or cp.read(path / "manifest.json")["compatibility"]
        manifest = cp.validate(path, compatibility=compatibility)
        if previous:
            cp.validate(previous, compatibility=compatibility, restart_to=name)
        report = cp.read(path / "segment.json")
        assert manifest["identity"] == artifact["identity"]
        assert report["to"] == plans.BOUNDARIES[name]
        assert report["from"] == (plans.SUCCESSORS[plans.STAGE_ORDER[plans.STAGE_ORDER.index(name) - 1]]
                                  if previous else None)
        assert report["returned_steps"][-1] == report["to"]
        assert report["bridge_sha256"] == summary["bridge_sha256"]
        assert report["acceptance"] == "not_evaluated"
        assert occurrence["status"] == "completed" and occurrence["exit_code"] == 0
        assert not Path(report["run_dir"]).exists()
        assert cp.digest(path / "manifest.json") == entry["manifest_sha256"]
        closures.add(cp.digest(path / "closure.json"))
        configs.add(cp.digest(path / "resolved.json"))
        previous = path
        print(name, len(report["returned_steps"]), "steps", entry["seconds"], "seconds; validated")
    assert len(closures) == len(configs) == 1
    if args.evidence:
        evidence = cp.read(args.evidence)
        production = evidence["production"]
        assert evidence["image_id"] == summary["binding"]["image_identity"]["image_id"]
        assert production["bridge_sha256"] == summary["bridge_sha256"]
        assert production["closure_sha256_all_segments"] in closures
        assert production["resolved_config_sha256_all_segments"] in configs
        assert len(production["segments"]) == len(summary["segments"])
        for compact, raw in zip(production["segments"], summary["segments"]):
            assert compact["boundary"] == raw["artifact"]["boundary"]
            for key in ("from", "to", "seconds", "copied_views", "unavailable_metrics"):
                assert compact[key] == raw[key]
            assert compact["returned_steps"] == len(raw["returned_steps"])
            assert compact["checkpoint"] == str(Path(raw["artifact"]["path"]).relative_to(args.workspace))
        for key, value in production["physical_evidence"].items():
            if key != "origin":
                assert report["metrics"][key] == {"availability": "available", "value": value}
        print("Compact evidence matches retained production artifacts")
    for key in ("route__drc_errors", "magic__drc_error__count", "design__lvs_error__count",
                "timing__setup_vio__count", "timing__hold_vio__count",
                "design__max_slew_violation__count", "design__max_cap_violation__count"):
        metric = report["metrics"][key]
        assert metric["availability"] == "available" and metric["value"] == 0
        print(key, metric["value"], "cumulative final-state evidence")
    print("PASS; physical segment completion, not postcheck/acceptance")


if __name__ == "__main__":
    main()
