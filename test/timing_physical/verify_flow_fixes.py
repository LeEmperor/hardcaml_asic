"""Focused independent F1–F6 closure controls after review_flow.py replay.

Usage: python3 -B verify_flow_fixes.py ORIGINAL_REPLAY_DIRECTORY
Uses its captured consumer and passing baseline; no builds, B edits or EDA.
"""
import ast
import json
from pathlib import Path
import shutil
import sys
import tempfile

ASIC = Path(__file__).resolve().parents[2]
replay = Path(sys.argv[1]).resolve()
root = replay / "baseline"
WORK = Path(tempfile.mkdtemp(prefix="timing-physical-fix-controls-", dir="/tmp/opencode"))
shutil.copy2(replay / "consumer", WORK / "consumer")
tree = ast.parse(Path(__file__).with_name("review_flow.py").read_text())
names = {"sha", "read", "write", "invoke", "rebind", "case", "change", "edit", "both", "metric"}
namespace = globals()
exec("import hashlib, subprocess", namespace)
exec(compile(ast.Module(body=[node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name in names],
                        type_ignores=[]), str(Path(__file__).with_name("review_flow.py")), "exec"), namespace)
CORNERS = read(root / "timing-intent/runtime-result.json")["configured_corners"]
CORNER = CORNERS[0]
CORNER_DIR = Path("timing-intent/corners") / CORNER
results = []

# Assert all original repros/controls on the freshly rebuilt reader, including
# malformed duplicate being valid evidence with unknown, not pass.
original = read(replay / "results.json")
for result in original:
    if result.get("expected") == "reject":
        assert result["code"] == 2, result["label"]
    if result["label"] == "malformed-second-setup-metric":
        assert result["code"] == 0 and result["observed"]["timing"] == "unknown"
    if result.get("expected") in ("valid evidence, timing fail", "timing unknown", "timing unknown or invalid"):
        expected = "fail" if result["expected"] == "valid evidence, timing fail" else "unknown"
        assert result["code"] == 0 and result["observed"]["timing"] == expected, result
assert json.loads(original[0]["stdout"])["all_corner_timing_goal"] == "pass"

def add_source(p, relative):
    target = p / relative
    analysis = p / "timing-intent/analysis.json"
    value = read(analysis)
    value["sources"].append(dict(path=str(relative), sha256=sha(target)))
    write(analysis, value)

def state_change(p, path, key, value):
    change(p / path, key, value)

historical = read(root / "timing-intent/request.json")["execution_root"]
case("unmodified-control", lambda p: None, "pass")
case("serialized-clk-duplicate", lambda p: both(p, ["native-state.sdc", "exceptions.rpt"],
    lambda text: text + "set_propagated_clock [get_clocks {clk}]\n"))
case("actual-extra-hook-substitution", lambda p: change(p / CORNER_DIR / "native-inputs.json", "environment",
    dict(read(p / CORNER_DIR / "native-inputs.json")["environment"], _EXTRA_CORNER_TCL_FILE="/tmp/unrelated-extra-hook.tcl")))

def checks_changed(p, bind):
    report = p / CORNER_DIR / "checks.rpt"
    # Preserve report semantics: this is a harmless trailing newline.
    report.write_text(report.read_text() + "\n")
    if bind:
        path = p / CORNER_DIR / "filter-inputs.json"
        value = read(path)
        value["checks_report"]["sha256"] = sha(report)
        write(path, value)
case("checks-bytes-unbound-to-filter", lambda p: checks_changed(p, False))
case("checks-bytes-bound-to-filter-positive", lambda p: checks_changed(p, True), "pass")

def substitute_report(p):
    relative = CORNER_DIR / "other-checks.rpt"
    shutil.copyfile(p / CORNER_DIR / "checks.rpt", p / relative)
    add_source(p, relative)
    path = p / CORNER_DIR / "filter-inputs.json"
    value = read(path)
    value["checks_report"] = dict(path=str(relative), sha256=sha(p / relative))
    write(path, value)
case("same-check-bytes-wrong-report-source", substitute_report)

def actual_odb_mismatch(p):
    relative = Path("project/runs/asic/other-rcx.odb")
    (p / relative).write_text("existing different RCX physical database\n")
    add_source(p, relative)
    result = read(p / "timing-intent/runtime-result.json")
    state_change(p, result["physical_chain"][-1]["output_state"]["path"], "odb", historical + "/" + str(relative))
case("rcx-odb-existing-bound-but-different", actual_odb_mismatch)

def coherent_odb(p):
    data = "consistent replacement modeled ODB bytes\n"
    (p / "project/runs/asic/design.odb").write_text(data)
    for corner in CORNERS:
        directory = p / "timing-intent/corners" / corner
        (directory / "filter-input.odb").write_text(data)
        path = directory / "filter-inputs.json"
        value = read(path)
        for row in value["inputs"]:
            if row["retained"]["path"].endswith(".odb"):
                row["retained"]["sha256"] = sha(directory / "filter-input.odb")
                row["bytes"] = (directory / "filter-input.odb").stat().st_size
        write(path, value)
case("coherent-odb-bytes-positive", coherent_odb, "pass")

def order_positive_ordinal(p):
    before = "project/runs/asic/06-openroad-stapostpnr"
    after = "project/runs/asic/04-openroad-stapostpnr"
    (p / before).rename(p / after)
    for name in ("input-selection.json", "runtime-result.json", "analysis.json"):
        path = p / "timing-intent" / name
        path.write_text(path.read_text().replace(before, after))
case("sta-positive-ordinal-before-rcx", order_positive_ordinal)

def changed_cts_views(p):
    result = read(p / "timing-intent/runtime-result.json")
    state = result["physical_chain"][1]["output_state"]["path"]
    directory = Path(state).parent
    for key, suffix in (("nl", "v"), ("odb", "odb")):
        relative = directory / ("distinct-cts." + suffix)
        (p / relative).write_text("separate retained CTS fixture view\n")
        add_source(p, relative)
        state_change(p, state, key, historical + "/" + str(relative))
case("different-retained-cts-views-positive", changed_cts_views, "pass")

for result in results:
    if result["expected"] == "reject":
        assert result["code"] == 2, result
    else:
        assert result["code"] == 0 and result["observed"]["timing"] == "pass", result
        assert result["observed"]["annotation"] == ["pass"] * 3, result
write(WORK / "results.json", dict(original_replay=str(replay), original_observations=len(original),
                                  controls=results, verified=True))
print(json.dumps(dict(directory=str(WORK), original_observations=len(original), controls=[
    {k:v for k,v in result.items() if k != "stdout"} for result in results], verified=True), indent=2))
