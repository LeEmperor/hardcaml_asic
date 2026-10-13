"""Read-only independent audit of the real boundary experiment's evidence."""

import argparse
import hashlib
import json
import math
from pathlib import Path


def load(path):
    return json.loads(Path(path).read_text())


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def verify(root):
    project = root / "project"
    summary = load(root / "summary.json")
    preflight = load(root / "preflight.json")
    transport = load(root / "transport.json")
    assert summary["status"] == "passed" and preflight["ready"]
    assert preflight["issues"] == [] and preflight["waivers"] == []
    assert transport["binding"] == preflight["execution_binding"]
    assert not (project / "src/runs/synthesis").exists()
    assert (project / "retained-synthesis").is_dir()
    checkpoint = load(project / "checkpoint/state.json")
    for item in load(project / "checkpoint/views.json"):
        assert digest(item["path"]) == item["sha256"]
    for item in summary["physical_artifacts"].values():
        assert digest(item["path"]) == item["sha256"]
    synthesis = load(project / "synthesis.json")
    physical = load(project / "physical.json")
    assert synthesis["resolved_config_sha256"] == physical["resolved_config_sha256"]
    assert digest(project / "checkpoint/resolved.json") == synthesis["resolved_config_sha256"]
    assert physical["input_state_sha256"] == digest(project / "checkpoint/state.json")
    assert synthesis["returned_steps"][-1] == "Yosys.Synthesis"
    assert physical["returned_steps"][0] == "Checker.YosysUnmappedCells"
    assert physical["returned_steps"][-1] == summary["physical_to"]
    all_events = {}
    for mode, report in (("synthesis", synthesis), ("physical", physical)):
        events = [json.loads(line) for line in (project / (mode + "-events.jsonl")).read_text().splitlines()]
        entered = [e for e in events if e["event"] == "body_entered"]
        returned = [e for e in events if e["event"] == "body_returned"]
        assert [e["occurrence"] for e in entered] == report["returned_steps"]
        assert [e["occurrence"] for e in returned] == report["returned_steps"]
        assert report["engine_methods_unmodified"]
        assert report["runtime"]["bridge_sha256"] == transport["bridge"]["backend_probe.py"]
        for event in returned:
            # The synthesis run has been renamed, leaving event paths historical.
            directory = Path(event["step_dir"])
            if mode == "synthesis":
                directory = project / "retained-synthesis" / directory.name
            assert (directory / "runtime.txt").is_file()
            assert (directory / "state_out.json").is_file()
        all_events[mode] = events
    first = all_events["physical"][0]
    assert load(Path(first["step_dir"]) / "state_in.json") == checkpoint
    assert "Yosys.Synthesis" not in physical["returned_steps"]
    assert len(transport["containers"]) == 3
    assert len({c["name"] for c in transport["containers"]}) == 3
    assert all(c["status"] == "removed-or-absent" for c in transport["container_cleanup"])
    synthetic_paths = list(project.glob("librelane-observation-*/evidence.json"))
    assert len(synthetic_paths) == 1
    synthetic = load(synthetic_paths[0])
    assert synthetic["all_assertions"] == "passed" and synthetic["case_count"] == 12
    success = synthetic["cases"][0]
    updates = [e["raw_updates"] for e in success["events"] if e["event"] == "body_returned"]
    assert updates == [{"synthetic__value": 7}, {}, {"synthetic__value": 7}, {}]
    noops = [e["occurrence"] for e in all_events["physical"]
             if e["event"] == "body_returned" and not e["raw_updates"] and not e["views"]]
    nonfinite = [key for key, value in physical["final_metrics"].items()
                 if isinstance(value, float) and not math.isfinite(value)]
    return {"status": "passed", "scratch": str(root), "synthetic_cases": 12,
            "real_synthesis_steps": len(synthesis["returned_steps"]),
            "real_physical_steps": len(physical["returned_steps"]),
            "body_noop_occurrences": noops, "nonfinite_metric_keys": nonfinite,
            "note": "Audit verifies retained artifacts and segment returns; body no-ops are not flow-gated skips."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("scratch", type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.scratch), indent=2, allow_nan=False))
