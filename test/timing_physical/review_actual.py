"""Independent read-only review of C's actual full physical result. No EDA.

Writes only a new /tmp/opencode review directory. Native inputs/evidence and
captured provider remain read-only; only public inspection/collect --stdout/report
are invoked. Assertions use raw logs, States, netlists and source hashes.
"""
from collections import Counter
import fnmatch
import hashlib
import json
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ASIC = Path(__file__).resolve().parents[2]
EXAMPLE = ASIC.parent / "hardcaml_asic_example"
AREA = EXAMPLE / ".dev/asic-timing-physical"
RUN = AREA / "full-runs/20261029T075052976305Z_23a6954b"
FLOW = RUN / "project/runs/asic"
PROVIDER = AREA / "provider/generations/4856e6af993642988c18c07f47a8c689"
OUT = Path(tempfile.mkdtemp(prefix="timing-physical-final-review-", dir="/tmp/opencode"))
HASHES = {}
ASSERTIONS = 0

def sha(path):
    path = Path(path)
    with path.open("rb") as stream:
        value = hashlib.file_digest(stream, "sha256").hexdigest()
    HASHES[str(path)] = value
    return value

def read(path):
    path = Path(path)
    sha(path)
    return json.loads(path.read_text())

def raw(path):
    path = Path(path)
    sha(path)
    return path.read_text(errors="strict")

def check(value, label):
    global ASSERTIONS
    assert value, label
    ASSERTIONS += 1

def ref(reference, root=RUN):
    path = root / reference["path"]
    check(path.is_file() and sha(path) == reference["sha256"], "source hash " + str(path))
    return path

def public(name, args, code=0):
    p = subprocess.run([str(PROVIDER / "bin/hardcaml-asic-flow"), *map(str, args)],
                       cwd=ASIC, text=True, capture_output=True, timeout=120)
    (OUT / (name + ".stdout")).write_text(p.stdout)
    (OUT / (name + ".stderr")).write_text(p.stderr)
    check(p.returncode == code, (name, p.returncode, p.stderr))
    return json.loads(p.stdout)

def metric_log(path):
    values = {}
    for line in raw(path).splitlines():
        words = line.split()
        if len(words) == 3 and words[0] in ("%OL_METRIC_F", "%OL_METRIC_I"):
            check(words[1] not in values, "duplicate native metric " + words[1])
            values[words[1]] = float(words[2])
    return values

record = read(RUN / "run.json")
manifest = read(RUN / "project/manifest.json")
check(record["run_id"] == "23a6954b852d4205b542d3815634d772", "run identity")
check(record["build_identity"] == manifest["identity"] == "ac513e0e7e9cfa935f73d697caebca8f601aeeb4ea62c2a2ccf61c10a10789cd", "build identity")
check(record["status"] == "completed" and record["completed_stage"] == "full", "full completion")
for member in manifest["files"]:
    ref(member, RUN / "project")
check(sha(RUN / "project/manifest.json") == record["manifest_sha256"], "manifest hash")
analysis = read(RUN / "timing-intent/analysis.json")
for source in analysis["sources"]:
    ref(source)
check(analysis["status"] == "completed", "linked companion completion")
runtime = read(RUN / "timing-intent/runtime-result.json")
progress = read(RUN / "timing-intent/corner-progress.json")
corners = ["nom_fast_1p32V_m40C", "nom_slow_1p08V_125C", "nom_typ_1p20V_25C"]
check(runtime["configured_corners"] == runtime["requested_corners"] == runtime["executed_corners"] == corners, "three actual corners")
check(progress["step_completed"] and not progress["not_observed_corners"] and not runtime["equivalent_corners"], "no missing/alias corner")
original = FLOW / "55-openroad-stapostpnr"
state = read(original / "state_in.json")
original_output = read(original / "state_out.json")
linked_input = read(RUN / "timing-intent/corners/state_in.json")
linked_output = read(RUN / "timing-intent/corners/state_out.json")
rcx = read(FLOW / "54-openroad-rcx/state_out.json")
check(state == linked_input, "linked exact original INPUT State")
for key in ("nl", "spef", "odb"):
    check(state[key] == rcx[key] == original_output[key] == linked_output[key], "RCX/original/linked implementation view " + key)

inspection = public("inspect", ["timing-intent-inspect", RUN, "--kind", "coarse_run", "--json"], 1)
collected = public("collect", ["collect", RUN, "--stdout", "--json"])
report = public("report", ["report", RUN, "--json"])
check(inspection == collected["timing_intent"] == report["timing_intent"], "public timing parity")
check(inspection["all_corner_timing_goal"] == "pass" and inspection["qualification_corner_coverage"] == "complete", "public closure")
check(inspection["verdict"] == "unavailable", "exhaustive coverage not promoted")

keys = ["timing__setup__ws", "timing__hold__ws", "timing__setup_vio__count", "timing__hold_vio__count",
        "design__max_slew_violation__count", "design__max_cap_violation__count"]
corner_results = []
expected_pairs = [("_06_", "_05_"), ("_05_", "_04_"), ("_03_", "_02_")]
stages_expected = {"capture_first": "_06_", "capture_second": "_05_", "capture_third": "_04_", "control_first": "_03_", "control_second": "_02_"}
for corner in corners:
    d = RUN / "timing-intent/corners" / corner
    old = original / corner
    audit = read(d / "audit.json")
    check(audit["schema"] == 3 and audit["stage"] == "post_pnr" and audit["corner"] == corner, "audit3 stage/corner")
    for source in audit["sources"]:
        ref(source, d)
    inputs = read(d / "native-inputs.json")
    for association in inputs["associations"]:
        retained = ref(association["retained"])
        check(str(retained) == association["actual_path"] and retained.stat().st_size == association["bytes"], "actual native consumed association")
        check(sha(retained) == sha(Path(association["original_path"])), "original/consumed bytes " + association["role"])
    libs = [a for a in inputs["associations"] if a["role"] == "liberty"]
    check(len(libs) == 2 and "sg13cmos5l_stdcell" in libs[0]["original_path"] and "sg13cmos5l_io" in libs[1]["original_path"], "ordered two actual libs")
    for lib in libs:
        check('time_unit' in raw(lib["actual_path"]) and re.search(r'time_unit\s*:\s*"1ns"', raw(lib["actual_path"])), "Liberty ns units")
    matches = [value for pattern, value in state["spef"].items() if fnmatch.fnmatchcase(corner, pattern)]
    check(len(matches) == 1 and sha(matches[0]) == sha(d / "extracted.spef"), "exact corner-selected extracted SPEF")
    env = inputs["environment"]
    check(env["_CURRENT_SPEF_BY_CORNER"] == str(d / "extracted.spef") and env["CURRENT_NL"] == str(d / "mapped.v"), "actual native env paths")
    log = raw(d / "sta.log")
    old_log = raw(old / "sta.log")
    check(str(d / "extracted.spef") in log and matches[0] in old_log, "original/linked actual SPEF read log")
    for lib in libs:
        check(lib["actual_path"] in log and lib["original_path"] in old_log, "actual original/linked loaded libs")
    check(state["nl"] in old_log and str(d / "mapped.v") in log, "actual original/linked netlist read")
    check(env["OPENLANE_SDC_IDEAL_CLOCKS"] == "0" and read(d / "clock-state.json") == dict(schema=1, all_propagated=1, clocks=["clk"]), "propagated primary clock")
    sdc = raw(d / "native-state.sdc").replace("\\\n", " ")
    check(len(re.findall(r'^set_propagated_clock \[get_clocks \{clk\}\]', sdc, re.M)) == 1, "real serialized primary propagation")
    relations = set()
    for line in sdc.splitlines():
        if line.startswith("set_false_path"):
            sources = re.findall(r'-from \[get_ports \{([^}]+)\}\]', line)
            targets = re.findall(r'\[get_pins \{([^}]+)\}\]', line)
            check(len(sources) == 1 and targets, "native literal false-path selectors")
            relations.update((sources[0], target) for group in targets for target in group.split())
    expected = {("ena", "_06_/D")} | {("rst_n", cell + "/RESET_B") for cell in stages_expected.values()}
    check(relations == expected and len(re.findall(r'^set_false_path', sdc, re.M)) == 2, "six narrow native stored relations")
    check(not re.search(r'^set_(disable_timing|clock_groups|case_analysis|min_delay|max_delay)\b', sdc, re.M), "no masking exceptions")
    check(re.search(r'set_clock_uncertainty 0\.250000000000 clk', sdc), "native .25 uncertainty")
    events = [json.loads(line.split("\t", 1)[1]) for line in raw(d / "resolution.jsonl").splitlines()]
    mapped = {e["id"]: e["cell"] for e in events if e["event"] == "stage"}
    check(mapped == stages_expected, "five exact original stage cells")
    check(next(e["cells"] for e in events if e["event"] == "inventory") == sorted(stages_expected.values()), "complete sequential inventory")
    check(all(e["master"] == "sg13cmos5l_dfrbpq_1" for e in events if e["event"] == "stage"), "same supported reset flops")
    traces = [e for e in events if e["event"] == "trace"]
    check(max(len(e["hops"]) for e in traces) == 2, "max checked depth2")
    data = read(d / "native-data.json")
    check(data["endpoint_count"] == 13 and "clkload0/Y" in data["endpoints"], "13 actual endpoints incl combinational CTS load")
    check(len(data["categories"]) == 7 and all(not c["groups"] for c in data["categories"]), "seven empty native categories")
    witnesses = {}
    for mode in ("min", "max"):
        witness = raw(d / ("downstream_" + mode + ".rpt"))
        pairs = list(zip(re.findall(r'^Startpoint: (\S+)', witness, re.M), re.findall(r'^Endpoint: (\S+)', witness, re.M)))
        slacks = [(float(n), status) for n, status in re.findall(r'([-+\d.]+)\s+slack \((\w+)\)', witness)]
        check(pairs == expected_pairs and len(slacks) == 3 and all(n >= 0 and status == "MET" for n, status in slacks), "three nonempty timed downstream " + mode)
        check("clock uncertainty" in witness and "sg13cmos5l_dlygate4sd3_1" in witness, "real delay/clock witnesses")
        witnesses[mode] = slacks
    old_metrics, linked_metrics = metric_log(old / "sta.log"), metric_log(d / "sta.log")
    values = {}
    for key in keys:
        full = key + "__corner:" + corner
        value = linked_metrics[full]
        check(value == old_metrics[full] == float(original_output["metrics"][full]) == float(linked_output["metrics"][full]), "original/linked log/State metric " + full)
        check(value >= 0 and (value == 0 if key.endswith("count") else True), "per-corner metric closure " + full)
        values[key] = value
    for name in ("native-process-0.json", "native-process-1.json"):
        process = read(d / name)
        check(process["exit_code"] == 0 and process["argv"][process["argv"].index("-threads")+1] == "1", "actual single-thread process completed")
    filter_inputs = read(d / "filter-inputs.json")
    for key in ("script", "filter_source", "checks_report"):
        ref(filter_inputs[key])
    for dependency in filter_inputs["dependencies"]:
        ref(dependency)
    check(filter_inputs["checks_report"]["path"] == str((d / "checks.rpt").relative_to(RUN)), "actual annotation report binding")
    for association in filter_inputs["inputs"]:
        check(sha(ref(association["retained"])) == sha(association["original_path"]), "actual ODB/LEF filter bytes")
    check(sha(d / "filter-input.odb") == sha(state["odb"]) == sha(rcx["odb"]), "causal exact physical ODB")
    filtered = read(d / "filter_unannotated_metrics.json")
    annotation_key = "timing__unannotated_net_filtered__count__corner:" + corner
    check(filtered[annotation_key] == linked_output["metrics"][annotation_key] == original_output["metrics"][annotation_key] == 0, "filtered annotation0 agreement")
    corner_results.append(dict(corner=corner, libraries=[a["retained"]["sha256"] for a in libs],
        spef_sha256=sha(d / "extracted.spef"), metrics=values, witnesses=witnesses, raw_annotation=filtered))

# Independent restricted named-pin Verilog reader for the actual emitted flat
# CMOS5L netlists. Not a general parser and never used as production timing input.
def cells(path):
    text = raw(path)
    matches = re.findall(r'\b(sg13cmos5l_\w+)\s+(\S+)\s*\((.*?)\);', text, re.S)
    result = {name: (master, dict(re.findall(r'\.(\w+)\s*\(\s*([^()]*?)\s*\)', pins))) for master, name, pins in matches}
    check(len(result) == len(matches), "unique native instances")
    return result

stage_counts = {}
stage_cells = {}
for label, directory in (("synthesis", "06-yosys-synthesis"), ("cts", "35-openroad-cts"), ("repair", "37-openroad-resizertimingpostcts"), ("final", "52-openroad-fillinsertion")):
    native_state = read(FLOW / directory / "state_out.json")
    instances = cells(native_state["nl"])
    check({name for name, (master, _) in instances.items() if "dfr" in master} == set(stages_expected.values()), "exact five flops " + label)
    check(all(instances[name][0] == "sg13cmos5l_dfrbpq_1" for name in stages_expected.values()), "unchanged flop sizing " + label)
    count = Counter(master for master, pins in instances.values())
    check(count["sg13cmos5l_dlygate4sd3_1"] == (9 if label in ("repair", "final") else 0), "actual hold-delay insertion " + label)
    stage_counts[label] = dict(count)
    stage_cells[label] = instances
check(set(stage_cells["repair"]) - set(stage_cells["cts"]) == {"hold" + str(n) for n in range(26, 35)}, "exact nine postCTS inserted instances")
repair_log = raw(FLOW / "37-openroad-resizertimingpostcts/openroad-resizertimingpostcts.log")
check("Found 6 endpoints with hold violations" in repair_log and "Inserted 9 hold buffers" in repair_log and "No setup violations found" in repair_log, "actual ordinary hold repair log")
repair_in = read(FLOW / "37-openroad-resizertimingpostcts/state_in.json")
cts_out = read(FLOW / "35-openroad-cts/state_out.json")
check(repair_in["nl"] == cts_out["nl"] and repair_in["odb"] == cts_out["odb"], "CTS genuinely pre-repair")

def root_of(instances, net):
    drivers = {pins["X"]: (name, master, pins["A"]) for name, (master, pins) in instances.items() if "X" in pins and "A" in pins}
    hops = []
    while net in drivers:
        name, master, previous = drivers[net]
        check(master in ("sg13cmos5l_buf_1", "sg13cmos5l_buf_8", "sg13cmos5l_dlygate4sd3_1"), "only qualified path transforms")
        check(name not in hops and len(hops) < 8, "bounded acyclic native topology")
        hops.append(name)
        net = previous
    return net, hops

topology = {}
for label, instances in stage_cells.items():
    traces = {}
    for (previous, downstream) in expected_pairs:
        expected_net = instances[previous][1]["Q"]
        net, hops = root_of(instances, instances[downstream][1]["D"])
        check(net == expected_net, "native original predecessor relation " + label)
        traces[previous + "/Q -> " + downstream + "/D"] = hops
    for cell in stages_expected.values():
        check(root_of(instances, instances[cell][1]["CLK"])[0] == "clk", "native primary clock connectivity")
        check(root_of(instances, instances[cell][1]["RESET_B"])[0] == "rst_n", "native active-low reset connectivity")
    check(root_of(instances, instances["_06_"][1]["D"])[0] == "ena", "native first capture source")
    check(root_of(instances, instances["_03_"][1]["D"])[0] == "ui_in[1]", "native synchronous control source")
    topology[label] = traces

check(sha(RUN / "project/src/tt_um_pt7_timing.v") == "dc387d8d445d55cbd75eb11d71bf5c36f4dc7ce395749e476e3614af55f2124a", "unchanged emitted RTL")
check(sha(RUN / "project/src/tt_um_pt7_timing.v") == sha(AREA / "bundles/synth-emit-native-01/src/tt_um_pt7_timing.v"), "native-control/full identical source architecture")
check(sha(RUN / "project/constraints/top.sdc") == sha(AREA / "bundles/synth-emit-native-01/constraints/top.sdc"), "exact native-control/full SDC unchanged")

check_dir = RUN / "checks/bc95939552ae415c9a5aaa8c1fff1cfe"
post = read(check_dir / "postcheck.json")
check(post["checks"] == dict(gate_level="pass", precheck="pass"), "normal postcheck passes")
for name, value in post["artifacts"].items():
    check(sha(check_dir / name) == value, "postcheck artifact " + name)
check(sha(FLOW / "final/nl/tt_um_pt7_timing.nl.v") == post["inputs"]["netlist_sha256"] == sha(state["nl"]), "same final functional/native STA netlist")
check(sha(FLOW / "final/gds/tt_um_pt7_timing.gds") == post["inputs"]["gds_sha256"], "same TT checked GDS")
check(sha(check_dir / "testbench.v") == post["inputs"]["testbench_sha256"], "actual replay testbench hash")
models = read(check_dir / "replay-models.json")
check(models["profile"] == "cmos5l_physical_timing_used_cells_v1" and models["scope"] == "zero_delay_gate_functional", "reviewed functional-only profile")
check(models["netlist_sha256"] == sha(state["nl"]) and models["manifest_sha256"] == sha(RUN / "project/manifest.json"), "replay model design association")
for name, value in models["retained_hashes"].items():
    check(sha(check_dir / name) == value, "retained functional model hash")
check(set(models["vendor_module_sha256"]) == set(stage_counts["final"]), "models cover exactly used native masters")
vendor = raw(check_dir / "stdcell-vendor.v")
functional = raw(check_dir / "stdcell-functional.v")
for name, digest in models["vendor_module_sha256"].items():
    bodies = re.findall(r'\bmodule\s+' + re.escape(name) + r'\s*\(.*?\bendmodule', vendor, re.S)
    check(len(bodies) == 1 and hashlib.sha256(bodies[0].encode()).hexdigest() == digest, "actual supplied used module hash " + name)
check(set(re.findall(r'\bmodule\s+(sg13cmos5l_\w+)', functional)) == set(models["vendor_module_sha256"]), "no extra model modules")
check(models["adaptations"]["sg13cmos5l_dfrbpq_1"] == ["CLK", "D", "RESET_B"] and
      all(not pins for name, pins in models["adaptations"].items() if name != "sg13cmos5l_dfrbpq_1"), "only qualified delayed reference adaptation")
for pin in ("CLK", "D", "RESET_B"):
    check("assign delayed_" + pin + " = " + pin + ";" in functional, "actual delayed reference bridge " + pin)
for path, digest in models["source_hashes"].items():
    check(sha(path) == digest, "unchanged original PDK functional model")
postlog = raw(check_dir / "postcheck.log")
check("checks=512" in postlog and "PASS physical timing functional replay" in postlog, "actual 512 observation replay")
check(all(p["succeeded"] and p["outcome"] == "exited" and p["code_or_ocaml_signal"] == 0 for p in post["process_results"]), "actual postcheck processes successful")
tt_root = check_dir / "tt/precheck/reports"
tt_xml = tt_root / "results.xml"
sha(tt_xml)
tt = ET.parse(tt_xml).getroot()
tt_checks = [node.attrib["name"] for node in tt.findall(".//testcase")]
check(len(tt_checks) == 9 and not tt.findall(".//failure") and not tt.findall(".//error") and not tt.findall(".//skipped"), "nine actual TT checks without skips")
check("KLayout SG13CMOS5L DRC" in tt_checks and "KLayout will use 6 thread(s)" in postlog and "Precheck passed for" in postlog, "actual CMOS5L TT DRC execution")
for filename in ("drc_sg13cmos5l.xml", "drc_pin_label_purposes_overlapping_drawing.xml", "drc_zero_area.xml"):
    path = tt_root / filename
    sha(path)
    check(not ET.parse(path).getroot().findall(".//items/item"), "raw TT violation report empty " + filename)

final_metrics = read(FLOW / "72-misc-reportmanufacturability/state_out.json")["metrics"]
gates = {key: value for key, value in final_metrics.items() if any(x in key for x in ("drc", "lvs", "antenna", "overlap"))}
for key in ("antenna__violating__nets", "antenna__violating__pins", "route__drc_errors", "magic__drc_error__count", "design__lvs_error__count"):
    check(float(final_metrics[key]) == 0, "ordinary native physical gate " + key)
check("[INFO] COUNT: 0" in raw(FLOW / "62-magic-drc/reports/drc.magic.rpt"), "raw Magic DRC0")
check("Final result: Circuits match uniquely." in raw(FLOW / "66-netgen-lvs/reports/lvs.netgen.rpt"), "raw Netgen unique match")
for directory in ("40-openroad-checkantennas", "46-openroad-checkantennas-1"):
    raw(FLOW / directory / "reports/antenna.rpt")
    raw(FLOW / directory / "reports/antenna_summary.rpt")
check("macro_contract" not in manifest, "no SRAM macro waiver contract")
check(record["resource_limits"] == dict(tool_workers=6, container_cpus=6, sta_workers=1), "run resource ceilings")
check("--cpus=6" in record["commands"][0] and record["commands"][0][record["commands"][0].index("--jobs")+1] == "6", "actual bounded implementation argv")
check(all(c["status"] == "removed-or-absent" for c in record["container_cleanup"]), "implementation owned cleanup")
transport = read(RUN / "timing-intent/transport-result.json")
check(transport["succeeded"] and transport["cleanup_error"] is None and transport["code"] == 0, "linked success/cleanup")
native_commands = []
for commands_file in sorted(FLOW.glob("*/COMMANDS")):
    for line in raw(commands_file).splitlines():
        args = shlex.split(line)
        if args and Path(args[0]).name in ("sta", "openroad"):
            threads = int(args[args.index("-threads") + 1]) if "-threads" in args else None
            check(threads is None or threads <= 6, "native command within six-worker allocation")
            if Path(args[0]).name == "sta":
                check(threads == 1, "original standalone STA thread1")
            native_commands.append(dict(stage=commands_file.parent.name, executable=args[0], threads=threads))
mid_threads = {row["stage"]: row["threads"] for row in native_commands if "stamidpnr" in row["stage"]}
limits = dict(original_mid_sta_threads=mid_threads,
              deviation="repeated_mid_sta_aliases_use6_not_promised1" if any(v != 1 for v in mid_threads.values()) else None,
              native_commands=native_commands, postcheck=post["resource_limits"])
check(post["resource_limits"]["container_cpus"] == post["resource_limits"]["host_cpu_affinity_max"] == post["resource_limits"]["tool_threads"] == 6, "actual postcheck ceilings")

# Installed sources are historical executable companions, not clean-tree claims.
source_comparison = []
for relative in ("lib/elaboration/timing_tcl.ml", "lib/elaboration/timing_intent.ml", "lib/elaboration/timing_coverage_tcl.ml",
                 "execution/results/timing_physical_flow.ml", "execution/results/timing_physical_metrics.ml",
                 "execution/results/timing_native_coverage.ml", "execution/results/timing_intent_evidence.ml",
                 "execution/results/postcheck_service.ml", "execution/archive/archive_service.ml",
                 "flow/hardcaml_asic_flow/timing_physical_runtime.py", "flow/hardcaml_asic_flow/physical_runtime.py"):
    installed = PROVIDER / "lib/hardcaml_asic" / (relative[4:] if relative.startswith("lib/") else relative)
    source_comparison.append(dict(source=relative, retained=sha(installed), current=sha(ASIC / relative), equal=sha(installed) == sha(ASIC / relative)))
receipt = read(PROVIDER / "receipt.json")
check(receipt["snapshot_sha256"] == "4a821a382619f33eda6be911cb1bddc9d71345a882e97c5fb5b5de68979153a3", "captured source snapshot")
for name in ("timing_physical_runtime.py", "timing_intent_runtime.py"):
    check(sha(RUN / "project" / name) == sha(RUN / "timing-intent" / name) == record["timing_runtime_helpers"][name], "implementation/analysis helper identity")

# Ensure public read-only replay did not change any hashed run evidence.
for path, value in list(HASHES.items()):
    if str(RUN) in path:
        with Path(path).open("rb") as stream:
            check(hashlib.file_digest(stream, "sha256").hexdigest() == value, "evidence unchanged after review " + path)

summary = dict(run=str(RUN), run_id=record["run_id"], build=manifest["identity"], provider=str(PROVIDER),
    assertions=ASSERTIONS, corners=corner_results, stage_counts=stage_counts, topology=topology,
    physical_metrics=gates, tt_checks=tt_checks, resource_observations=limits, source_comparison=source_comparison, source_hashes=HASHES,
    archive_confirmation="deferred_known_seven_report_omission", evidence_unmodified=True)
(OUT / "review.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(dict(directory=str(OUT), assertions=ASSERTIONS, corners=corner_results,
    stage_counts=stage_counts, topology=topology, tt_checks=tt_checks, mid_sta_threads=mid_threads, source_comparison=source_comparison), indent=2))
