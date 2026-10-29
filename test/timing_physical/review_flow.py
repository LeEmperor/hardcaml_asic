"""A's independent source-rebound review of B. No EDA, no B source edits.

Run after building B's emitter/consumer and flow_cli under the shared lock.
Reuses only B's modeled native fixture construction, not B's negative tests.
Retains all independent cases/results in a new /tmp/opencode directory.
"""
import ast
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ASIC = Path(__file__).resolve().parents[2]
WORK = Path(tempfile.mkdtemp(prefix="timing-physical-flow-review-", dir="/tmp/opencode"))
fixture_path = ASIC / "test/timing_physical_flow/check.py"
helpers = ASIC / "flow/hardcaml_asic_flow"
for name, original in (
    ("emitter", ASIC / "_build/default/test/timing_physical_flow/emitter.exe"),
    ("consumer", ASIC / "_build/default/test/timing_physical_flow/consumer.exe"),
    ("flow_cli", ASIC / "_build/default/bin/flow_cli.exe"),
):
    shutil.copy2(original, WORK / name)
shutil.copy2(helpers / "timing_physical_runtime.py", WORK / "timing_physical_runtime.py")
shutil.copy2(helpers / "timing_intent_runtime.py", WORK / "timing_intent_runtime.py")
shutil.copy2(fixture_path, WORK / "fixture-source.py")

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def read(path):
    return json.loads(path.read_text())

def write(path, value):
    path.write_text(json.dumps(value, separators=(",", ":")) + "\n")

def invoke(*args):
    p = subprocess.run(list(map(str, args)), text=True, capture_output=True, timeout=60,
                       cwd=ASIC / "test/timing_physical_flow")
    return dict(code=p.returncode, stdout=p.stdout, stderr=p.stderr)

# Only the fixture's imports, constants and function definitions before main.
tree = ast.parse(fixture_path.read_text(), filename=str(fixture_path))
nodes = []
for node in tree.body:
    if isinstance(node, ast.If):
        break
    nodes.append(node)
saved = sys.argv
sys.argv = [str(fixture_path), str(WORK / "emitter"), str(WORK / "consumer"),
            str(WORK / "flow_cli"), str(WORK / "timing_physical_runtime.py")]
ns = {"__file__": str(fixture_path)}
try:
    exec(compile(ast.Module(body=nodes, type_ignores=[]), str(fixture_path), "exec"), ns)
finally:
    sys.argv = saved
bundle = WORK / "bundle"
emission = invoke(WORK / "emitter", bundle)
assert emission["code"] == 0, emission
root = WORK / "baseline"
config = ns["fixture"](root, bundle)
write(root / "request-unused.json", dict(physical=True))
ns["runtime"](root, config)
for corner in ns["CORNERS"]:
    (root / "timing-intent/corners" / corner / "checks.rpt").write_text(
        "report_parasitic_annotation -report_unannotated\nNo unannotated nets.\n"
        "===========================================================================\n")
assert invoke(WORK / "consumer", "publish", root, "true")["code"] == 0
baseline = invoke(WORK / "consumer", "inspect", root)
assert baseline["code"] == 0, baseline
assert json.loads(baseline["stdout"])["all_corner_timing_goal"] == "pass"
CORNERS = ns["CORNERS"]
CORNER = CORNERS[0]
CORNER_DIR = Path("timing-intent/corners") / CORNER
results = [dict(label="baseline", **baseline)]

def rebind(case):
    """Recompute references bottom-up; no current reader/rendered source oracle."""
    result_path = case / "timing-intent/runtime-result.json"
    result = read(result_path)
    for row in result["audits"]:
        directory = (case / row["audit"]["path"]).parent
        receipt = read(directory / "receipt.json")
        for source in receipt["inputs"]:
            source["sha256"] = sha(directory / source["path"])
        write(directory / "receipt.json", receipt)
        log = directory / "sta.log"
        lines = log.read_text().splitlines()
        lines[0] = "PT7_AUDIT_RECEIPT " + json.dumps(receipt, separators=(",", ":"))
        log.write_text("\n".join(lines) + "\n")
        process = read(directory / "process-result.json")
        process["receipt_sha256"] = sha(directory / "receipt.json")
        write(directory / "process-result.json", process)
        associations = read(directory / "native-inputs.json")
        for association in associations["associations"]:
            source = case / association["retained"]["path"]
            association["retained"]["sha256"] = sha(source)
            association["bytes"] = source.stat().st_size
        write(directory / "native-inputs.json", associations)
        audit = read(directory / "audit.json")
        for source in audit["sources"]:
            source["sha256"] = sha(directory / source["path"])
        write(directory / "audit.json", audit)

    # Ref-bearing JSON objects form a DAG: repeatedly rebind until stable.
    def refs(value):
        if isinstance(value, dict):
            if isinstance(value.get("path"), str) and "sha256" in value:
                path = case / value["path"]
                if not Path(value["path"]).is_absolute() and path.is_file():
                    value["sha256"] = sha(path)
            for v in value.values():
                refs(v)
        elif isinstance(value, list):
            for v in value:
                refs(v)
    paths = [case / "timing-intent/input-selection.json", result_path,
             case / "timing-intent/corner-progress.json", case / "timing-intent/analysis.json"]
    for _ in range(5):
        for path in paths:
            value = read(path)
            refs(value)
            write(path, value)

def case(label, mutation, expected="reject"):
    target = WORK / label
    shutil.copytree(root, target)
    mutation(target)
    rebind(target)
    result = invoke(WORK / "consumer", "inspect", target)
    result.update(label=label, expected=expected, directory=str(target))
    if result["code"] == 0:
        view = json.loads(result["stdout"])
        result["observed"] = dict(status=view["status"], timing=view["all_corner_timing_goal"],
             annotation=[r["timing"].get("annotation_goal") for r in view.get("corners", [])])
    results.append(result)

def change(path, key, value):
    data = read(path)
    data[key] = value
    write(path, data)

def edit(path, operation):
    path.write_text(operation(path.read_text()))

def both(case, filenames, operation):
    for filename in filenames:
        edit(case / CORNER_DIR / filename, operation)

# Narrow SDC parser addition: valid writer forms vs unsupported commands/queries.
case("missing-propagation", lambda p: both(p, ["native-state.sdc", "exceptions.rpt"],
     lambda t: t.replace("set_propagated_clock [get_clocks {clk}]\n", "")))
case("propagation-commented-out", lambda p: both(p, ["native-state.sdc", "exceptions.rpt"],
     lambda t: t.replace("set_propagated_clock", "# set_propagated_clock")))
case("propagation-wrong-clock", lambda p: both(p, ["native-state.sdc", "exceptions.rpt"],
     lambda t: t.replace("get_clocks {clk}", "get_clocks {other}")))
case("propagation-continued-comment", lambda p: both(p, ["native-state.sdc", "exceptions.rpt"],
     lambda t: t.replace("set_propagated_clock", "# continued \\\nset_propagated_clock")))
case("propagation-literal-list", lambda p: both(p, ["native-state.sdc", "exceptions.rpt"],
     lambda t: t.replace("[get_clocks {clk}]", "[list [get_clocks {clk}]]")), "accept equivalent literal selector")

def filter_script(p):
    path = p / CORNER_DIR / "filter-inputs.json"
    data = read(path)
    old = data["script_path"]
    data["script_path"] = "/tmp/independent-always-zero.py"
    write(path, data)
    process = p / CORNER_DIR / "native-process-1.json"
    j = read(process)
    j["argv"][j["argv"].index(old)] = data["script_path"]
    write(process, j)
case("filter-executed-script-substitution", filter_script)
case("filter-negative-exit", lambda p: change(p / CORNER_DIR / "native-process-1.json", "exit_code", 9))
case("native-negative-exit", lambda p: change(p / CORNER_DIR / "native-process-0.json", "exit_code", 9))

# The filter consumes checks.rpt, not the hook's parasitic-annotation.rpt.
def missing_filter_report(p):
    path = p / CORNER_DIR / "checks.rpt"
    path.unlink()
    analysis = p / "timing-intent/analysis.json"
    j = read(analysis)
    j["sources"] = [r for r in j["sources"] if r["path"] != str(CORNER_DIR / "checks.rpt")]
    write(analysis, j)
case("filter-input-report-not-retained", missing_filter_report)
case("raw-annotation-contradicts-zero", lambda p: (p / CORNER_DIR / "parasitic-annotation.rpt").write_text(
    "Found 1 unannotated drivers.\n  data_real_wire\n"), "inspect may retain, cannot claim complete raw annotation")

def metric(p, key, value, state=True):
    key += "__corner:" + CORNER
    path = p / CORNER_DIR / "sta.log"
    lines = path.read_text().splitlines()
    path.write_text("\n".join(" ".join(line.split()[:2] + [str(value)]) if
        line.startswith(("%OL_METRIC_F " + key + " ", "%OL_METRIC_I " + key + " ")) else line for line in lines) + "\n")
    if state:
        target = p / "timing-intent/corners/state_out.json"
        data = read(target)
        data["metrics"][key] = value
        write(target, data)
case("negative-hold-consistent", lambda p: metric(p, "timing__hold__ws", -0.5), "valid evidence, timing fail")
case("hold-state-conflict", lambda p: metric(p, "timing__hold__ws", -0.5, state=False), "timing unknown")
case("missing-setup-log", lambda p: edit(p / CORNER_DIR / "sta.log", lambda t: "\n".join(
    line for line in t.splitlines() if not line.startswith("%OL_METRIC_F timing__setup__ws")) + "\n"), "timing unknown")
case("duplicate-setup-metric", lambda p: edit(p / CORNER_DIR / "sta.log", lambda t:
    t + "%OL_METRIC_F timing__setup__ws__corner:" + CORNER + " 2.5\n"), "timing unknown")
case("malformed-second-setup-metric", lambda p: edit(p / CORNER_DIR / "sta.log", lambda t:
    t + "%OL_METRIC_F timing__setup__ws__corner:" + CORNER + " -0.5 unexpected\n"), "timing unknown or invalid")
case("missing-corner-runtime", lambda p: change(p / "timing-intent/runtime-result.json", "executed_corners", CORNERS[:-1]))
case("missing-spef-consumed-copy", lambda p: (p / CORNER_DIR / "extracted.spef").write_text("wrong extracted bytes\n"))
def change_spef(p):
    path = p / CORNER_DIR / "native-inputs.json"
    j = read(path)
    next(a for a in j["associations"] if a["role"] == "spef")["original_path"] = str(root / "project/runs/asic" / (CORNERS[1] + ".spef"))
    write(path, j)
case("wrong-corner-spef-association", change_spef)

def mutate_chain_state(p):
    result = read(p / "timing-intent/runtime-result.json")
    row = result["physical_chain"][1]
    path = p / row["output_state"]["path"]
    data = read(path)
    data["nl"] = str(root / "project/runs/asic/not-the-cts-netlist.v")
    data["odb"] = str(root / "project/runs/asic/not-the-cts.odb")
    write(path, data)
case("cts-output-not-associated-to-later-state", mutate_chain_state)

def different_rcx_odb(p):
    result = read(p / "timing-intent/runtime-result.json")
    path = p / result["physical_chain"][-1]["output_state"]["path"]
    data = read(path)
    data["odb"] = str(root / "project/runs/asic/unrelated-rcx.odb")
    write(path, data)
case("rcx-odb-not-sta-input-odb", different_rcx_odb)

def producer_order(p):
    # Rename only the selected original STA producer and rebind its source refs.
    before = "project/runs/asic/06-openroad-stapostpnr"
    after = "project/runs/asic/00-openroad-stapostpnr"
    (p / before).rename(p / after)
    for name in ("input-selection.json", "runtime-result.json", "analysis.json"):
        path = p / "timing-intent" / name
        path.write_text(path.read_text().replace(before, after))
case("post-sta-producer-before-rcx", producer_order)

case("native-threads20", lambda p: change(p / CORNER_DIR / "native-process-0.json", "argv",
    ["sta", "-threads", "20", "-no_splash", "-exit", str(root / "timing-intent/driver.tcl")]))
case("clock-state-false", lambda p: change(p / CORNER_DIR / "clock-state.json", "all_propagated", 0))
case("unbound-spef-copy-annotation-only", lambda p: change(p / CORNER_DIR / "native-inputs.json", "environment",
    dict(read(p / CORNER_DIR / "native-inputs.json")["environment"], _CURRENT_SPEF_BY_CORNER="/tmp/wrong.spef")))
case("actual-native-hook-substitution", lambda p: change(p / CORNER_DIR / "native-inputs.json", "environment",
    dict(read(p / CORNER_DIR / "native-inputs.json")["environment"], STA_EXTRA_CORNER_TCL_FILE="/tmp/unrelated-hook.tcl")))
case("transport-workers20", lambda p: change(p / "timing-intent/transport.json", "workers", 20))
case("transport-docker-cpus20", lambda p: change(p / "timing-intent/transport.json", "argv",
    [arg.replace("--cpus=6", "--cpus=20") for arg in read(p / "timing-intent/transport.json")["argv"]]))
case("transport-cleanup-contradiction", lambda p: change(p / "timing-intent/transport-result.json", "cleanup_error", "cleanup failed"))
case("transport-failed-but-success-claimed", lambda p: change(p / "timing-intent/transport-result.json", "code", 9))

def failed_terminal(p):
    transport = p / "timing-intent/transport-result.json"
    value = read(transport)
    value.update(code=9, succeeded=False)
    write(transport, value)
    change(p / "timing-intent/analysis.json", "status", "failed")
case("failed-terminal-keeps-no-coverage", failed_terminal, "failed evidence, timing unknown")

def downgrade(p, marker):
    if marker:
        path = p / "project/manifest.json"
        value = read(path)
        value.pop("timing_physical_qualification")
        write(path, value)
        record = p / "run.json"
        value = read(record)
        value["manifest_sha256"] = sha(path)
        value["timing_intent_expected"] = False
        write(record, value)
    else:
        change(p / "run.json", "timing_physical_expected", False)
case("marker-removed-expectation-retained", lambda p: downgrade(p, True))
case("expectation-removed-marker-retained", lambda p: downgrade(p, False), "marker still selects physical reader")
case("linked-input-state-substitution", lambda p: change(p / "timing-intent/corners/state_in.json", "nl", "/tmp/unrelated.v"))

def audit_downgrade(p):
    directory = p / CORNER_DIR
    audit = read(directory / "audit.json")
    audit.update(schema=2, stage="synthesized_netlist", scope="standalone_synthesized_netlist_sta")
    audit["sources"] = [row for row in audit["sources"] if row["role"] not in ("spef", "clock_state", "parasitic_annotation")]
    write(directory / "audit.json", audit)
    receipt = read(directory / "receipt.json")
    receipt["stage"] = "synthesized_netlist"
    receipt["inputs"] = [row for row in receipt["inputs"] if row["role"] != "spef"]
    write(directory / "receipt.json", receipt)
    edit(directory / "native-state.sdc", lambda text: text.replace("set_propagated_clock [get_clocks {clk}]\n", ""))
case("inner-audit3-downgrade-to2", audit_downgrade)

# Actual helper failure must retain drained per-corner process observations and
# never publish runtime-result success. This remains a modeled native boundary.
for mode in ("later_failure", "missing"):
    failure = WORK / ("helper-failure-" + mode)
    resolved = ns["fixture"](failure, bundle)
    write(failure / "request-unused.json", dict(physical=True))
    error = None
    try:
        ns["runtime"](failure, resolved, mode)
    except (ValueError, subprocess.CalledProcessError) as exc:
        error = str(exc)
    assert error and not (failure / "timing-intent/runtime-result.json").exists()
    terminal = failure / "timing-intent/transport-result.json"
    value = read(terminal)
    value.update(succeeded=False, code=9)
    write(terminal, value)
    assert invoke(WORK / "consumer", "publish", failure, "false")["code"] == 0
    observed = invoke(WORK / "consumer", "inspect", failure)
    assert observed["code"] == 0, observed
    view = json.loads(observed["stdout"])
    assert view["status"] == "failed" and view["all_corner_timing_goal"] == "unknown"
    progress = view["corner_execution"]
    assert progress["step_completed"] == (mode == "missing")
    assert progress["executed_corners"] == (CORNERS[:-1] if mode == "missing" else CORNERS)
    results.append(dict(label="helper-failure-" + mode, expected="retained failed/unavailable",
         directory=str(failure), error=error, observed=dict(status=view["status"], timing=view["all_corner_timing_goal"], progress=progress)))

ns["implementation_limits"]()
results.append(dict(label="implementation-worker-model", observed="TPE6 and pre/mid/post native STA thread1; ordinary steps unchanged"))

write(WORK / "results.json", results)
print(json.dumps(dict(directory=str(WORK), source_sha256={str(p): sha(p) for p in
    [fixture_path, helpers / "timing_physical_runtime.py", ASIC / "execution/results/timing_physical_flow.ml",
     ASIC / "execution/results/timing_physical_metrics.ml", ASIC / "execution/results/timing_native_coverage.ml"]},
    cases=[{k:v for k,v in result.items() if k not in ("stdout",)} for result in results]), indent=2))
