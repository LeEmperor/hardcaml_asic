"""Read-only audit of a retained terminal finalization and current shared policy."""
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "flow"))
from hardcaml_asic_flow import checkpoint as cp, finalization as final, phase4, report

directory = Path(sys.argv[1]).resolve()
receipt = final.inspect(directory)
assert receipt["status"] == "completed" and receipt["acceptance"] == "pass"
assert not (directory / "run.json").exists()
assert cp.digest(receipt["execution"]["path"]) == receipt["execution"]["sha256"]
execution, compatibility, publications = final.selected(Path(receipt["execution"]["path"]))
assert compatibility["binding"] == receipt["binding"]
assert [p[1]["identity"] for p in publications] == [p["identity"] for p in receipt["selected_checkpoints"]]
for relative, expected in receipt["mapped_files"].items():
    assert cp.file_record(directory / relative) == expected
for path, expected in receipt["postcheck_collateral"].items():
    assert cp.file_record(path) == expected
assert cp.digest(receipt["results"]["path"]) == receipt["results"]["sha256"]
results = phase4.read_json(Path(receipt["results"]["path"]))
context = receipt["evidence_context"]
current = phase4.collect(directory, context=context, synthesis_state=directory / "evidence/synthesis-state.json")
for key in ("metrics", "checks", "synthesis_checks"):
    for name, item in current[key].items():
        item["origin_boundary"] = "synthesis" if item["stage"] == "Yosys.Synthesis" else "signoff"
    assert current[key] == results[key], key
assert current["errors"] == results["errors"] == []
postcheck = phase4.read_json(Path(receipt["postcheck_record"]))
assert postcheck["status"] == "completed" and postcheck["checks"] == {"precheck": "pass", "gate_level": "pass"}
assert postcheck["tools"]["execution_binding"] == receipt["binding"]
assert postcheck["inputs"]["gds_sha256"] == cp.digest(next((directory / "evidence/final/gds").glob("*.gds")))
assert postcheck["inputs"]["netlist_sha256"] == cp.digest(next((directory / "evidence/final/nl").glob("*.v")))
assert postcheck["inputs"]["testbench_sha256"] == cp.digest(Path(receipt["postcheck_record"]).parent / "testbench.v")
assert postcheck["inputs"]["replay_trace_sha256"] == cp.digest(Path(receipt["postcheck_record"]).parent / "replay-trace.txt")
lines = []
assert report.report(directory, current, "read-only current-code audit", output=lines.append, context=context) == 0
state = phase4.read_json(publications[-1][0] / "state.json")
print(json.dumps({"operation": str(directory), "receipt_sha256": cp.digest(directory / "operation.json"),
    "results_sha256": receipt["results"]["sha256"], "postcheck_sha256": cp.digest(receipt["postcheck_record"]),
    "started_at": receipt["started_at"], "ended_at": receipt["ended_at"],
    "acceptance": "pass", "current_code_read_only_audit": "pass",
    "setup_slack": current["metrics"]["setup_slack"], "hold_slack": current["metrics"]["hold_slack"],
    "inputs": postcheck["inputs"], "tools": postcheck["tools"],
    "known_retained_counts": {key: state["metrics"][key] for key in (
        "design__disconnected_pin__count", "design__max_fanout_violation__count")}}, indent=2))
