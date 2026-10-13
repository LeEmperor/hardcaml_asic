"""Reuse the retained slice-4 consumer implementation; real external checks."""
import json
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "flow"))
from hardcaml_asic_flow import checkpoint, finalization, phase4

consumer = Path("/home/wayne/devel/jane/hardcaml_asic_example")
workspace = Path("/tmp/opencode/librelane-slice4-production")
store = Path("/tmp/opencode/librelane-slice6-finalizations")
exporter = consumer / "_build/default/acceptance/export_trace.exe"
if "--launch" in sys.argv:
    with (store / "smoke-launch.log").open("w") as log:
        process = subprocess.Popen([sys.executable, "-B", str(Path(__file__).resolve())],
                                   stdout=log, stderr=log, start_new_session=True)
    print(json.dumps({"pid": process.pid, "log": str(store / "smoke-launch.log")}))
    sys.exit(0)
trace = store / "consumer-replay-trace.txt"
trace.write_text(subprocess.run([str(exporter)], check=True, text=True, capture_output=True).stdout)
directory, receipt = finalization.finalize(execution=workspace / "execution.json", store=store,
    accept=True, support_tools=consumer / "_flow_tools/tt",
    precheck_python=consumer / "_flow_tools/.venv-precheck/bin/python",
    testbench=consumer / "acceptance/replay.v", testbench_top="replay", replay_trace=trace)
phase4.save(store / "smoke-summary.json", {"operation": str(directory),
    "receipt": receipt, "trace": {"exporter": str(exporter), "exporter_sha256": checkpoint.digest(exporter),
    "command": [str(exporter)], "path": str(trace), "sha256": checkpoint.digest(trace),
    "rows": len(trace.read_text().splitlines())}})
print(json.dumps({"operation": str(directory), "status": receipt["status"],
                  "acceptance": receipt["acceptance"], "error": receipt["error"]}, indent=2))
sys.exit(receipt["exit_code"])
