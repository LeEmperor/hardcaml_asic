"""Real helper + public native/source readers; only native Step boundary modeled.

These tests establish source/association rejection, not EDA qualification.
"""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import types
import venv

EMITTER, CONSUMER, CLI, HELPER = map(lambda p: Path(p).resolve(), sys.argv[1:5])
COUNT = 0
CORNERS = ["nom_fast_1p32V_m40C", "nom_slow_1p08V_125C", "nom_typ_1p20V_25C"]
CATEGORIES = ["no_input_delay", "no_output_delay", "multiple_clock", "no_clock", "unconstrained_endpoints", "loops", "generated_clocks"]


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def read(p):
    return json.loads(p.read_text())


def write(p, value):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(value, separators=(",", ":")) + "\n")


def call(args, code=0, diagnostic=None):
    global COUNT
    p = subprocess.run(list(map(str, args)), text=True, capture_output=True, timeout=60)
    if p.returncode != code and p.stdout.strip().startswith("{"):
        outcome = json.loads(p.stdout)
        if "run_dir" in outcome:
            log = Path(outcome["run_dir"]) / "execution.log"
            if log.exists():
                p.stderr += "\n" + log.read_text()
    assert p.returncode == code, (args, p.returncode, p.stdout, p.stderr)
    if diagnostic:
        assert diagnostic in p.stderr, (diagnostic, p.stderr)
    COUNT += 1
    return json.loads(p.stdout) if p.stdout.strip() else None


def fixture(root, bundle, physical=True, implementation_only=False):
    if not (root / "project").exists():
        shutil.copytree(bundle, root / "project")
    for name in ("timing_physical_runtime.py", "timing_intent_runtime.py"):
        if not (root / "project" / name).exists():
            shutil.copyfile(HELPER.with_name(name), root / "project" / name)
    flow = root / "project/runs/asic"
    flow.mkdir(parents=True, exist_ok=True)
    netlist = flow / "mapped.v"
    netlist.write_text("// structural fixture, no native engine\nmodule top; wire clk,d,r,q0,q1;\n"
        "sg13cmos5l_dfrbpq_1 u0 (.CLK(clk),.D(d),.RESET_B(r),.Q(q0));\n"
        "sg13cmos5l_dfrbpq_2 u1 (.CLK(clk),.D(q0),.RESET_B(r),.Q(q1));\nendmodule\n")
    odb = flow / "design.odb"
    odb.write_text("opaque ODB fixture\n")
    spefs = {}
    for corner in CORNERS:
        p = flow / (corner + ".spef")
        p.write_text("*SPEF fixture " + corner + "\n")
        spefs[corner] = str(p)
    state = dict(nl=str(netlist), odb=str(odb), spef=spefs, metrics={}) if physical else dict(nl=str(netlist), metrics={})
    classes = [(1, "Yosys.Synthesis"), (2, "OpenROAD.GlobalPlacement"), (3, "OpenROAD.CTS"), (4, "OpenROAD.DetailedRouting"),
               (5, "OpenROAD.RCX"), (6, "OpenROAD.STAPostPNR")] if physical else [(1, "Yosys.Synthesis")]
    for ordinal, cls in classes:
        directory = flow / (f"{ordinal:02d}-" + cls.lower().replace(".", "-"))
        write(directory / "config.json", dict(meta=dict(step=cls, librelane_version="3.1.0.dev3")))
        write(directory / "state_in.json", state)
        write(directory / "state_out.json", state)
        (directory / "runtime.txt").write_text("00:00:00.001\n")
    libs = {}
    for corner in CORNERS:
        p = root.parent / (corner + ".lib")
        p.write_text('library (fixture) {\n time_unit : "1ns";\n}\n')
        libs[corner] = [str(p)]
    resolved = dict(DEFAULT_CORNER=CORNERS[2], STA_CORNERS=CORNERS, STA_THREADS=1, OPENROAD_THREADS=6,
                    PNR_SDC_FILE=str(root / "project/constraints/top.sdc"), SIGNOFF_SDC_FILE=str(root / "project/constraints/top.sdc"),
                    STA_EXTRA_CORNER_TCL_FILE=None, STA_MACRO_PRIORITIZE_NL=True, CELL_LIBS=libs, PAD_LIBS={},
                    DESIGN_NAME=read(bundle / "manifest.json")["top_module"], EXTRA_LIBS=None, EXTRA_VERILOG_MODELS=None, EXTRA_SPEFS=None,
                    TECH_LEFS={"nom_*": [str(flow / "tech.lef")]}, CELL_LEFS=[str(flow / "cells.lef")], EXTRA_LEFS=None, PAD_LEFS=[])
    (flow / "tech.lef").write_text("tech LEF fixture\n")
    (flow / "cells.lef").write_text("cell LEF fixture\n")
    write(flow / "resolved.json", resolved)
    if implementation_only:
        return resolved
    binding = call([CONSUMER, "binding"])
    stage = "full" if physical else "synthesis"
    argv = call([CONSUMER, "argv", root, "implementation", stage])
    manifest = read(root / "project/manifest.json")
    process = dict(outcome="exited", code=0, succeeded=True, argv=argv)
    record = dict(schema_version=1, run_id="physical-fixture", status="completed", requested_stage=stage, completed_stage=stage,
                  timing_intent_expected=True, timing_physical_expected=True, build_identity=manifest["identity"],
                  manifest_sha256=sha(root / "project/manifest.json"), execution_binding=binding, implementation_process=process,
                  commands=[argv], outputs=dict(project="project", flow="project/runs/asic"), bundle=str(bundle), environment={})
    record["timing_runtime_helpers"] = {name: sha(root / "project" / name) for name in ("timing_physical_runtime.py", "timing_intent_runtime.py")}
    write(root / "run.json", record)
    out = root / "timing-intent"
    out.mkdir()
    for name in ("timing_physical_runtime.py", "timing_intent_runtime.py"):
        shutil.copyfile(HELPER.with_name(name), out / name)
    request = dict(schema=2, run_id=record["run_id"], build_identity=manifest["identity"], manifest_sha256=record["manifest_sha256"],
                   analysis_id="physical-fixture/" + ("post-pnr-sta" if physical else "pre-pnr-sta"),
                   stage="post_pnr" if physical else "synthesized_netlist", implementation_process=process,
                   execution_root=str(root), host_uid=os.getuid(), host_gid=os.getgid(), binding=binding,
                   pdk_root=str(root.parent / "pdk"), helper_sha256=sha(out / "timing_physical_runtime.py"),
                   base_helper_sha256=sha(out / "timing_intent_runtime.py"), producer_sha256=sha(root / "project/constraints/pt7-native-coverage.tcl"))
    write(out / "request.json", request)
    write(out / "transport.json", dict(request_sha256=sha(out / "request.json"), binding=binding,
          argv=call([CONSUMER, "argv", root, "analysis", stage]), workers=6, sta_threads=1, timeout_seconds=600))
    write(out / "transport-result.json", dict(request_sha256=sha(out / "request.json"), succeeded=True, outcome="exited", code=0, cleanup_error=None))
    return resolved


AUTHORITATIVE_REPORTS = {
    "40-openroad-checkantennas": ("OpenROAD.CheckAntennas", ("antenna.rpt", "antenna_summary.rpt")),
    "46-openroad-checkantennas-1": ("OpenROAD.CheckAntennas", ("antenna.rpt", "antenna_summary.rpt")),
    "62-magic-drc": ("Magic.DRC", ("drc.magic.rpt",)),
    "66-netgen-lvs": ("Netgen.LVS", ("lvs.netgen.json", "lvs.netgen.rpt")),
}


def authoritative_report_fixture(root):
    """The exact seven actual-run path shapes; native tools remain modeled."""
    paths = []
    for name, (producer, reports) in AUTHORITATIVE_REPORTS.items():
        step = root / "project/runs/asic" / name
        write(step / "config.json", dict(meta=dict(step=producer, librelane_version="3.1.0.dev3")))
        write(step / "state_out.json", dict(metrics={}))
        (step / "runtime.txt").write_text("00:00:00.123\n")
        (step / "reports").mkdir()
        for report in reports:
            path = step / "reports" / report
            path.write_text('{"fixture_native_lvs_errors":0}\n' if report.endswith(".json") else producer + ": modeled zero violations\n")
            paths.append(str(path.relative_to(root)))
    return paths


def runtime(root, resolved, mode="good"):
    spec = importlib.util.spec_from_file_location("physical_runtime_test", HELPER)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    script_root = root.parent / "scripts"
    script_root.mkdir(exist_ok=True)
    (script_root / "openroad/common").mkdir(parents=True, exist_ok=True)
    corner_script = script_root / "corner.tcl"
    corner_script.write_text("# modeled corner script\n")
    (script_root / "odbpy").mkdir(exist_ok=True)
    (script_root / "odbpy/filter_unannotated.py").write_text("# modeled annotation filter\n")
    (script_root / "odbpy/reader.py").write_text("# modeled retained dependency\n")

    class FakeStep:
        id = "OpenROAD.STAPostPNR" if read(root / "request-unused.json").get("physical") else "OpenROAD.STAPrePNR"

        @classmethod
        def get_all_config_variables(cls):
            return [types.SimpleNamespace(name=k) for k in resolved]

        @classmethod
        def load(cls, config, state_in, pdk_root):
            instance = cls()
            instance.config = read(Path(config))
            instance.state = read(Path(state_in))
            assert instance.config["STA_THREADS"] == instance.config["OPENROAD_THREADS"] == 1
            assert instance.config["STA_CORNERS"] == CORNERS
            return instance

        def get_script_path(self):
            return str(corner_script)

        def _get_corner_files(self, corner, prioritize_nl):
            return corner, types.SimpleNamespace(libs=resolved["CELL_LIBS"][corner], netlists=[], spefs=[], extra_spefs_backcompat=None,
                    current_corner_spef=self.state.get("spef", {}).get(corner))

        def start(self, toolbox, step_dir):
            step_dir = Path(step_dir)
            step_dir.mkdir()
            self.step_dir = str(step_dir)
            write(step_dir / "config.json", self.config)
            write(step_dir / "state_in.json", self.state)
            self.results = {}
            self.run(self.state)
            write(step_dir / "state_out.json", dict(self.state, metrics=self.results))
            (step_dir / "runtime.txt").write_text("00:00:00.002\n")

        def run(self, state_in, **kwargs):
            step_dir = Path(self.step_dir)
            import librelane.steps.openroad as native
            executor = native.ThreadPoolExecutor(max_workers=1)
            futures = []
            for corner in CORNERS[:-1] if mode == "missing" else CORNERS:
                directory = step_dir / corner
                directory.mkdir()
                env = dict(STA_EXTRA_CORNER_TCL_FILE=self.config["STA_EXTRA_CORNER_TCL_FILE"], OPENLANE_SDC_IDEAL_CLOCKS="0")
                futures.append(executor.submit(self.run_corner, self.state, env, corner, str(directory)))
            for future in futures:
                future.result()

        def run_corner(self, state, env, corner, corner_dir):
            d = Path(corner_dir)
            physical = "spef" in state
            if physical:
                assert env["_CURRENT_SPEF_BY_CORNER"] == str(d / "extracted.spef")
                assert sha(d / "extracted.spef") == sha(Path(state["spef"][corner]))
            self.run_subprocess(self.get_command(), report_dir=corner_dir)
            event = lambda name, **fields: dict(schema_version=1, event=name, **fields)
            trace = lambda label, root, sink: event("trace", label=label, root=root, sink=sink, nets=["net_" + label], hops=[])
            counts = dict(stage_count=2, exception_count=1)
            events = [event("begin", **counts)]
            for i in range(2):
                events += [trace(f"anchor for rx{i}", f"u{i}/Q", f"hc_pt7_rx{i}"), trace(f"clock for rx{i}", "clk", f"u{i}/CLK"),
                           event("stage", id=f"rx{i}", anchor=f"hc_pt7_rx{i}", cell=f"u{i}", master="sg13cmos5l_dfrbpq_1",
                                 q_pin=f"u{i}/Q", data_pin=f"u{i}/D", async_pin=f"u{i}/RESET_B")]
            scope = dict(id="capture", kind="async_capture", source="ena", targets=["u0/D"])
            events += [event("inventory", cells=["u0", "u1"]), trace("interstage for rx1", "u0/Q", "u1/D"),
                       trace("async_capture for rx0", "ena", "u0/D"), event("resolved", **scope),
                       event("validated", **counts), event("applied", **scope), event("complete", **counts)]
            log = "PT7_AUDIT_RECEIPT " + json.dumps(read(d / "receipt.json"), separators=(",", ":")) + "\n"
            log += "".join("HC_ASIC_TIMING_V1\t" + json.dumps(e, separators=(",", ":")) + "\n" for e in events)
            for metric, value in [("timing__setup__ws", 2.5), ("timing__hold__ws", 0.125),
                                  ("timing__setup_vio__count", 0), ("timing__hold_vio__count", 0),
                                  ("design__max_slew_violation__count", 0), ("design__max_cap_violation__count", 0)]:
                key = metric + "__corner:" + corner
                log += ("%OL_METRIC_I " if metric.endswith("count") else "%OL_METRIC_F ") + key + " " + str(value) + "\n"
                self.results[key] = value
            log += "HC_ASIC_NATIVE_V2_COMPLETE\nPT7_AUDIT_COMPLETE\n"
            (d / "sta.log").write_text(log)
            if mode == "later_failure":
                raise subprocess.CalledProcessError(9, self.get_command())
            (d / "native-state.sdc").write_text("current_design " + self.config["DESIGN_NAME"] + "\n" +
                ("set_propagated_clock [get_clocks {clk}]\n" if physical else "") +
                "set_false_path -from [get_ports {ena}] -to [get_pins {u0/D}]\n")
            write(d / "native-data.json", dict(schema=2, contract="hardcaml-asic.timing-native-coverage", profile="opensta-2.7-native-state-v2",
                  complete=True, categories=[dict(name=n, group_count=0, groups=[]) for n in CATEGORIES], endpoint_count=2, endpoints=["u0/D", "u1/D"]))
            (d / "native-checks.rpt").write_text("HC_ASIC_NATIVE_CHECKS_V2 opensta-2.7-native-state-v2\n" +
                "".join(f"HC_ASIC_NATIVE_CATEGORY_BEGIN {n}\nHC_ASIC_NATIVE_CATEGORY_END {n}\n" for n in CATEGORIES) + "HC_ASIC_NATIVE_CHECKS_V2_COMPLETE\n")
            (d / "native-endpoints.rpt").write_text('"u0/D"\n"u1/D"\nHC_ASIC_NATIVE_ENDPOINTS_COMPLETE\n')
            for name in ("downstream_min.rpt", "downstream_max.rpt"):
                (d / name).write_text("bounded witness, not closure authority\n")
            if physical:
                (d / "parasitic-annotation.rpt").write_text("No unannotated nets.\n")
                if mode != "missing_checks":
                    (d / "checks.rpt").write_text("report_parasitic_annotation -report_unannotated\nNo unannotated nets.\n===========================================================================\n")
                write(d / "clock-state.json", dict(schema=1, all_propagated=1, clocks=["clk"]))
                self.run_subprocess(["openroad", "-exit", "-no_splash", "-metrics", str(d / "filter_unannotated_metrics.json"),
                    "-python", str(script_root / ("wrong-filter.py" if mode == "wrong_filter" else "odbpy/filter_unannotated.py")), "--corner", corner,
                    "--checks-report", str(d / "checks.rpt"), state["odb"], "--input-lef", resolved["TECH_LEFS"]["nom_*"][0],
                    "--input-lef", resolved["CELL_LEFS"][0]], report_dir=corner_dir)
                key = "timing__unannotated_net_filtered__count__corner:" + corner
                write(d / "filter_unannotated_metrics.json", {key: 0})
                self.results[key] = 0
            return {}

        def run_subprocess(self, command, *args, **kwargs):
            return {}

    modules = {"librelane": types.ModuleType("librelane"), "librelane.steps": types.ModuleType("librelane.steps"),
               "librelane.steps.openroad": types.SimpleNamespace(STAPrePNR=FakeStep, STAPostPNR=FakeStep),
               "librelane.common": types.SimpleNamespace(Toolbox=lambda p: p, set_tpe=lambda p: p.shutdown(), get_script_dir=lambda: str(script_root)),
               "librelane.steps.tclstep": types.SimpleNamespace(TclStep=types.SimpleNamespace(value_to_tcl=lambda xs: " ".join(helper.base.tcl_word(x) for x in xs)))}
    previous = {k: sys.modules.get(k) for k in modules}
    sys.modules.update(modules)
    original = subprocess.run
    try:
        subprocess.run = lambda *a, **k: types.SimpleNamespace(stdout="2.7.0\n", stderr="", returncode=0)
        helper.execute(root / "timing-intent/request.json")
    finally:
        subprocess.run = original
        for k, value in previous.items():
            if value is None:
                sys.modules.pop(k, None)
            else:
                sys.modules[k] = value


def implementation_limits():
    global COUNT
    spec = importlib.util.spec_from_file_location("physical_implementation_limits", HELPER)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    class Pre:
        id = "OpenROAD.STAPrePNR"
        def get_command(self):
            return ["sta", "-exit", "corner.tcl"]
    class Post(Pre):
        id = "OpenROAD.STAPostPNR"
    class Mid:
        id = "OpenROAD.STAMidPNR"
        def get_command(self):
            return ["openroad", "-exit", "-threads", "6", "-no_splash", "timing.tcl"]
    class Ordinary:
        pass
    classic = types.SimpleNamespace(Steps=[Pre, Mid, Post, Ordinary])
    budgets = []
    def set_tpe(pool):
        budgets.append(pool._max_workers)
        pool.shutdown()
    modules = {"librelane": types.ModuleType("librelane"), "librelane.flows": types.ModuleType("librelane.flows"),
        "librelane.flows.classic": types.SimpleNamespace(Classic=classic), "librelane.steps": types.ModuleType("librelane.steps"),
        "librelane.steps.openroad": types.SimpleNamespace(STAPrePNR=Pre, STAPostPNR=Post, STAMidPNR=Mid),
        "librelane.common": types.SimpleNamespace(set_tpe=set_tpe)}
    previous = {k: sys.modules.get(k) for k in modules}
    sys.modules.update(modules)
    argv, run_module = sys.argv, helper.runpy.run_module
    def classic_entry(name, run_name):
        assert name == "librelane" and run_name == "__main__"
        assert sys.argv[1:] == ["--jobs", "6", "src/config.json"]
        assert budgets == [6] and classic.Steps[3] is Ordinary
        assert [cls.id for cls in classic.Steps[:3]] == [Pre.id, Mid.id, Post.id]
        for cls in classic.Steps[:3]:
            command = cls().get_command()
            assert command.count("-threads") == 1 and command[command.index("-threads") + 1] == "1"
    try:
        sys.argv = [str(HELPER), "implementation", "--jobs", "6", "src/config.json"]
        helper.runpy.run_module = classic_entry
        helper.implementation()
        COUNT += 1
    finally:
        sys.argv = argv
        helper.runpy.run_module = run_module
        for k, value in previous.items():
            if value is None:
                sys.modules.pop(k, None)
            else:
                sys.modules[k] = value


if len(sys.argv) > 5:
    mode = sys.argv[5]
    path = Path(sys.argv[6])
    if mode == "--implementation":
        fixture(path, path / "project", physical=sys.argv[7] == "full", implementation_only=True)
        write(path / "request-unused.json", dict(physical=sys.argv[7] == "full"))
    else:
        root = path.parent.parent
        runtime(root, read(root / "project/runs/asic/resolved.json"))
    sys.exit(0)


with tempfile.TemporaryDirectory(prefix="timing physical [retained] ") as tmp:
    implementation_limits()
    tmp = Path(tmp)
    bundle = tmp / "bundle"
    call([EMITTER, bundle])
    # Real Tcl language check of the generated hook with inert native operations.
    # Objects deliberately do not have anchor/driver spellings: witnesses must
    # use A's checked map, not reconstruct an immediate Q driver after repair.
    spec = importlib.util.spec_from_file_location("physical_hook_language", HELPER)
    hook_helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(hook_helper)
    hook_dir = tmp / "hook [native] $objects"
    hook_dir.mkdir()
    (hook_dir / "native-producer.tcl").write_text("namespace eval ::hc_pt7_native { proc write {directory} {} }\n")
    (hook_dir / "hook.tcl").write_text(hook_helper.hook(read(bundle / "manifest.json"), True))
    oracle = hook_dir / "oracle.tcl"
    oracle.write_text(r'''
namespace eval ::hc_pt7 {
    proc checked_endpoints {} { return [dict create rx0 [dict create q moved_Q0 data moved_D0] rx1 [dict create q moved_Q1 data moved_D1]] }
    proc json_string {value} { return "\"$value\"" }
}
namespace eval sta { proc all_clocks {} { return [list clk] } }
proc get_property {object property} { return 1 }
proc get_full_name {object} { return $object }
proc report_checks {args} { set f [open [file join $::env(PT7_AUDIT_DIR) queries] a]; puts $f $args; close $f }
proc report_parasitic_annotation {args} { set f [open [lindex $args end] w]; puts $f "inert annotation report"; close $f }
''' + "\nset ::env(PT7_AUDIT_DIR) " + hook_helper.base.tcl_word(str(hook_dir)) + "\nsource " + hook_helper.base.tcl_word(str(hook_dir / "hook.tcl")) + "\n")
    tcl = subprocess.run(["tclsh", str(oracle)], text=True, capture_output=True, timeout=20)
    assert tcl.returncode == 0, tcl.stderr
    assert read(hook_dir / "clock-state.json") == dict(schema=1, all_propagated=1, clocks=["clk"])
    queries = (hook_dir / "queries").read_text().splitlines()
    assert len(queries) == 2 and all("-from moved_Q0 -to moved_D1" in q for q in queries)
    COUNT += 1
    bootstrap_root = tmp / "retained-filter-bootstrap"
    driver_dir = bootstrap_root / "timing-intent/corners/fast"
    dependency_dir = bootstrap_root / "timing-intent/native-sources/odbpy"
    driver_dir.mkdir(parents=True); dependency_dir.mkdir(parents=True)
    (driver_dir / "filter-driver.py").write_text(hook_helper.FILTER_DRIVER)
    (dependency_dir / "reader.py").write_text("VALUE = 'retained dependency'\n")
    (dependency_dir / "filter_unannotated.py").write_text("import json, reader, sys\nfrom pathlib import Path\nPath(sys.argv[-1]).write_text(json.dumps([reader.VALUE, reader.__file__, sys.argv]))\n")
    poison = tmp / "poisoned-python-path"; poison.mkdir()
    (poison / "reader.py").write_text("VALUE = 'wrong ambient dependency'\n")
    observation = driver_dir / "bootstrap-observation.json"
    result = subprocess.run([sys.executable, "-B", str(driver_dir / "filter-driver.py"), "--corner", "fast", str(observation)],
        env=dict(os.environ, PYTHONPATH=str(poison)), text=True, capture_output=True, timeout=20)
    assert result.returncode == 0, result.stderr
    value, dependency, argv = read(observation)
    assert value == "retained dependency" and dependency == str(dependency_dir / "reader.py")
    assert argv[0] == str(dependency_dir / "filter_unannotated.py") and argv[1:3] == ["--corner", "fast"]
    assert not (dependency_dir / "__pycache__").exists()
    COUNT += 1
    root = tmp / "full"
    resolved = fixture(root, bundle)
    authoritative_paths = authoritative_report_fixture(root)
    write(root / "request-unused.json", dict(physical=True))
    before = {p: sha(p) for p in (root / "project/runs/asic").rglob("*") if p.is_file()}
    runtime(root, resolved)
    assert all(sha(p) == h for p, h in before.items())
    call([CONSUMER, "publish", root, "true"])
    baseline = call([CONSUMER, "inspect", root])
    assert baseline["status"] == "completed" and baseline["all_corner_timing_goal"] == "pass", [r["timing"] for r in baseline["corners"]]
    assert baseline["verdict"] == "unavailable" and len(baseline["corners"]) == 3
    assert call([CLI, "timing-intent-inspect", root, "--kind", "coarse_run", "--json"], 1) == baseline
    collected = call([CONSUMER, "collect", root])
    assert collected["timing_intent"] == baseline
    assert set(authoritative_paths).issubset(collected["raw_artifacts"])
    write(root / "results.json", collected)
    original_report = call([CONSUMER, "report", root])
    assert original_report["timing_intent"] == baseline

    # Archive-only controls: a cache advertises requirements, never authorizes
    # reading an arbitrary path. All native inputs/producer evidence stay intact.
    def archive_report_negative(label, mutate, diagnostic):
        case = tmp / ("report-archive-" + label)
        shutil.copytree(root, case)
        mutate(case)
        destination = tmp / ("report-archive-rejected-" + label)
        call([CLI, "archive", case, "--output", destination, "--json"], 2, diagnostic)
        assert not destination.exists()

    def raw_advertisement(p, values):
        path = p / "results.json"
        j = read(path); j["raw_artifacts"] += values
        write(path, j)

    archive_report_negative("traversal", lambda p: raw_advertisement(p, ["../not-authorized.rpt"]), "unsafe advertised raw artifact")
    archive_report_negative("absolute", lambda p: raw_advertisement(p, [str(tmp / "not-authorized.rpt")]), "unsafe advertised raw artifact")
    archive_report_negative("missing-advertised", lambda p: (p / authoritative_paths[0]).unlink(), "advertised authoritative report is missing")
    archive_report_negative("producer-mismatch", lambda p: write(p / "project/runs/asic/40-openroad-checkantennas/config.json", dict(meta=dict(step="Magic.DRC", librelane_version="3.1.0.dev3"))), "producer/metadata mismatch")
    archive_report_negative("wrong-version", lambda p: write(p / "project/runs/asic/40-openroad-checkantennas/config.json", dict(meta=dict(step="OpenROAD.CheckAntennas", librelane_version="unsupported"))), "unsupported authoritative report metadata")
    archive_report_negative("missing-completion", lambda p: (p / "project/runs/asic/40-openroad-checkantennas/state_out.json").unlink(), "state_out.json")
    archive_report_negative("invalid-runtime", lambda p: (p / "project/runs/asic/40-openroad-checkantennas/runtime.txt").write_text("not completed\n"), "malformed native runtime")
    outside = tmp / "outside-report-secret"
    outside.write_text("never selected through a link\n")
    def linked_report(p):
        path = p / authoritative_paths[0]
        path.unlink(); path.symlink_to(outside)
    archive_report_negative("file-symlink", linked_report, "symlink")
    def linked_directory(p):
        path = p / "project/runs/asic/40-openroad-checkantennas/reports"
        shutil.rmtree(path); path.symlink_to(root / "project/runs/asic/40-openroad-checkantennas/reports", target_is_directory=True)
    archive_report_negative("directory-symlink", linked_directory, "linked or not a directory")
    def oversized_report(p):
        with (p / authoritative_paths[0]).open("wb") as stream:
            stream.truncate(32 * 1024 * 1024 + 1)
    archive_report_negative("source-byte-bound", oversized_report, "source byte bound")
    def report_entry_bound(p):
        directory = p / "project/runs/asic/40-openroad-checkantennas/reports"
        for i in range(1025): (directory / (str(i) + ".txt")).touch()
    archive_report_negative("directory-bound", report_entry_bound, "exceeds1024 entries")
    archive_report_negative("advertisement-bound", lambda p: raw_advertisement(p, ["unselected.txt"] * 8193), "exceeds8192 entries")
    def unauthorized_namespace(p):
        path = p / "project/runs/asic/private-notes/reports/secret.rpt"
        path.parent.mkdir(parents=True); path.write_text("not a native producer\n")
    archive_report_negative("unqualified-producer", unauthorized_namespace, "unsupported authoritative report producer")
    unselected = tmp / "report-archive-unselected-cache"
    shutil.copytree(root, unselected)
    (unselected / "project/private-secret.txt").write_text("cache cannot authorize copying this file\n")
    nested = unselected / "project/runs/asic/40-openroad-checkantennas/reports/private/secret.rpt"
    nested.parent.mkdir(); nested.write_text("do not recursively export report trees\n")
    raw_advertisement(unselected, ["project/private-secret.txt"])
    unselected_output = tmp / "report-archive-unselected-output"
    call([CLI, "archive", unselected, "--output", unselected_output, "--json"])
    assert "project/private-secret.txt" not in read(unselected_output / "archive.json")["members"]
    assert str(nested.relative_to(unselected)) not in read(unselected_output / "archive.json")["members"]
    uncached = tmp / "report-archive-no-collection-cache"
    shutil.copytree(root, uncached); (uncached / "results.json").unlink()
    uncached_output = tmp / "report-archive-no-cache-output"
    call([CLI, "archive", uncached, "--output", uncached_output, "--json"])
    assert set(authoritative_paths).issubset(read(uncached_output / "archive.json")["members"])
    late_change = tmp / "report-archive-late-change"
    shutil.copytree(root, late_change)
    destination = tmp / "report-archive-preserved-output"; destination.mkdir()
    (destination / "archive.json").write_text('{"prior":"unchanged"}\n')
    (destination / "user-sentinel").write_text("preserve existing output on failure\n")
    prior = {p.name: p.read_bytes() for p in destination.iterdir()}
    fake_gzip = tmp / "gzip-report-mutation"
    marker = tmp / "gzip-report-mutated"
    fake_gzip.write_text(f'''#!{sys.executable}
import pathlib, subprocess, sys
result=subprocess.run([{shutil.which("gzip")!r}, *sys.argv[1:]], stdout=sys.stdout.buffer)
marker=pathlib.Path({str(marker)!r})
if not marker.exists():
    marker.write_text("changed after reports were encoded")
    with pathlib.Path({str(late_change / authoritative_paths[0])!r}).open("ab") as f: f.write(b"changed after snapshot\\n")
sys.exit(result.returncode)
''')
    fake_gzip.chmod(0o700)
    archive_consumer = CLI.parent.parent / "test/archive_consumer.exe"
    failed = subprocess.run([str(archive_consumer), "publish", str(late_change), str(destination), "true", str(fake_gzip), str(tmp)],
                            text=True, capture_output=True, timeout=60)
    assert failed.returncode == 2 and "authoritative report source changed during publication" in failed.stderr, failed.stderr
    assert {p.name: p.read_bytes() for p in destination.iterdir()} == prior
    COUNT += 1

    def reseal(case):
        # Refresh retained references, including original State/config sources,
        # before and after the inner receipts. This intentionally permits fully
        # rebound semantic repros; rejection must not rely on a stale digest.
        def refresh(value):
            if isinstance(value, list):
                return [refresh(v) for v in value]
            if not isinstance(value, dict):
                return value
            value = {k: refresh(v) for k, v in value.items()}
            if isinstance(value.get("path"), str) and "sha256" in value and not Path(value["path"]).is_absolute():
                target = case / value["path"]
                if target.is_file():
                    value["sha256"] = sha(target)
            if "retained" in value and "bytes" in value:
                target = case / value["retained"]["path"]
                if target.is_file():
                    value["bytes"] = target.stat().st_size
            return value

        def refresh_file(path):
            old = read(path)
            new = refresh(old)
            if new != old:
                write(path, new)

        for path in case.rglob("*.json"):
            if path.name not in ("analysis.json", "audit.json", "receipt.json", "process-result.json"):
                refresh_file(path)
        result_path = case / "timing-intent/runtime-result.json"
        result = read(result_path)
        for row in result["audits"]:
            p = case / row["audit"]["path"]
            audit = read(p)
            receipt_path = p.parent / "receipt.json"
            receipt = read(receipt_path)
            for source in receipt["inputs"]:
                source["sha256"] = sha(p.parent / source["path"])
            write(receipt_path, receipt)
            log_path = p.parent / "sta.log"
            lines = log_path.read_text().splitlines()
            lines[0] = "PT7_AUDIT_RECEIPT " + json.dumps(receipt, separators=(",", ":"))
            log_path.write_text("\n".join(lines) + "\n")
            process_path = p.parent / "process-result.json"
            process = read(process_path)
            process["receipt_sha256"] = sha(receipt_path)
            write(process_path, process)
            inputs_path = p.parent / "native-inputs.json"
            inputs = read(inputs_path)
            for association in inputs["associations"]:
                target = case / association["retained"]["path"]
                association["retained"]["sha256"] = sha(target)
                association["bytes"] = target.stat().st_size
            write(inputs_path, inputs)
            for source in audit["sources"]:
                source["sha256"] = sha(p.parent / source["path"])
            write(p, audit)
            row["audit"]["sha256"] = sha(p)
        write(result_path, result)
        progress_path = case / "timing-intent/corner-progress.json"
        progress = read(progress_path)
        for row in progress["observations"]:
            if row["audit"] is not None:
                row["audit"]["sha256"] = sha(case / row["audit"]["path"])
        write(progress_path, progress)
        for name in ("input-selection.json", "runtime-result.json", "corner-progress.json"):
            refresh_file(case / "timing-intent" / name)
        (case / "timing-intent/analysis.json").unlink()
        call([CONSUMER, "publish", case, "true"])

    def negative(label, mutate, diagnostic, seal=True):
        case = tmp / label
        shutil.copytree(root, case)
        mutate(case)
        if seal:
            reseal(case)
        call([CONSUMER, "inspect", case], 2, diagnostic)
        destination = tmp / (label + "-archive-rejected")
        call([CLI, "archive", case, "--output", destination, "--json"], 2)
        assert not destination.exists()

    def change(path, key, value):
        j = read(path)
        j[key] = value
        write(path, j)

    corner = "timing-intent/corners/" + CORNERS[0] + "/"
    negative("spef-bytes", lambda p: (p / corner / "extracted.spef").write_text("wrong SPEF\n"), "selected SPEF differs")
    negative("missing-corner", lambda p: change(p / "timing-intent/runtime-result.json", "executed_corners", CORNERS[:-1]), "not actually executed")
    negative("later-process-failure", lambda p: change(p / corner / "process-result.json", "exit_code", 9), "did not exit successfully")
    negative("wrong-stage", lambda p: change(p / corner / "audit.json", "stage", "synthesized_netlist"), "schema/scope/stage")
    negative("wrong-clock", lambda p: change(p / corner / "clock-state.json", "all_propagated", 0), "clock observation contradicts")
    # F1: serialized state, not just an asserted native observation, is required.
    for label, replacement in [("F1-missing-propagation", ""), ("F1-commented-propagation", "# set_propagated_clock [get_clocks {clk}]\n")]:
        def remove_propagation(p, replacement=replacement):
            for name in ("native-state.sdc", "exceptions.rpt"):
                path = p / corner / name
                path.write_text(path.read_text().replace("set_propagated_clock [get_clocks {clk}]\n", replacement))
        negative(label, remove_propagation, "serialized propagated primary clk")

    # F2/F3: execution authority and the actual annotation input are independent
    # of matching source hashes or the separate hook annotation report.
    def substitute_filter(p):
        path = p / corner / "filter-inputs.json"
        j = read(path); old = j["script_path"]
        j["script_path"] = "/tmp/unrelated-always-zero.py"
        write(path, j)
        process_path = p / corner / "native-process-1.json"
        process = read(process_path)
        process["argv"] = [j["script_path"] if v == old else v for v in process["argv"]]
        write(process_path, process)
    negative("F2-filter-path", substitute_filter, "executed script authority")
    negative("F2-filter-driver-bytes", lambda p: (p / corner / "filter-driver.py").write_text("# always zero substitute\n"), "executed script authority")
    def substitute_hook(p):
        path = p / corner / "native-inputs.json"
        j = read(path); j["environment"]["STA_EXTRA_CORNER_TCL_FILE"] = "/tmp/unrelated-hook.tcl"
        write(path, j)
    negative("F2-actual-hook", substitute_hook, "actual native input differs: STA_EXTRA_CORNER_TCL_FILE")
    def substitute_internal_hook(p):
        path = p / corner / "native-inputs.json"
        j = read(path); j["environment"]["_EXTRA_CORNER_TCL_FILE"] = "/tmp/unrelated-hook.tcl"
        write(path, j)
    negative("F2-actual-internal-hook", substitute_internal_hook, "extra-corner hook differs")
    negative("F3-missing-checks", lambda p: (p / corner / "checks.rpt").unlink(), "checks.rpt")
    def substitute_checks(p):
        path = p / corner / "filter-inputs.json"
        j = read(path)
        j["checks_report"] = dict(path=corner + "parasitic-annotation.rpt", sha256=sha(p / corner / "parasitic-annotation.rpt"))
        write(path, j)
    negative("F3-hook-report-substitution", substitute_checks, "checks report source mismatch")
    negative("F2-missing-dependency", lambda p: (p / "timing-intent/native-sources/odbpy/reader.py").unlink(), "reader.py")

    def retain_view(p, relative, content):
        path = p / relative; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(content)
        for name in ("input-selection.json", "runtime-result.json"):
            meta_path = p / "timing-intent" / name
            j = read(meta_path)
            j["retained_producer_files"].append(dict(path=relative, sha256=sha(path)))
            write(meta_path, j)
        return read(p / "timing-intent/request.json")["execution_root"] + "/" + relative

    def change_rcx_odb(p):
        other = retain_view(p, "project/runs/asic/05-openroad-rcx/unrelated.odb", "unrelated retained physical design\n")
        change(p / "project/runs/asic/05-openroad-rcx/state_out.json", "odb", other)
    negative("F4-rcx-odb", change_rcx_odb, "RCX/STA extracted nl/SPEF/ODB input mismatch")

    def rename_producer(p, before, after):
        (p / after).parent.mkdir(parents=True, exist_ok=True)
        (p / before).rename(p / after)
        def replace(value):
            if isinstance(value, str): return value.replace(before, after)
            if isinstance(value, list): return [replace(v) for v in value]
            if isinstance(value, dict): return {k: replace(v) for k, v in value.items()}
            return value
        for path in p.rglob("*.json"):
            if path.name != "analysis.json":
                old = read(path); new = replace(old)
                if new != old: write(path, new)
    negative("F5-sta-before-rcx", lambda p: rename_producer(p, "project/runs/asic/06-openroad-stapostpnr", "project/runs/asic/04-openroad-stapostpnr"), "noncausal original post-PNR STA")
    negative("F5-zero-sta-ordinal", lambda p: rename_producer(p, "project/runs/asic/06-openroad-stapostpnr", "project/runs/asic/00-openroad-stapostpnr"), "invalid native producer ordinal")
    negative("F5-synthesis-after-placement", lambda p: rename_producer(p, "project/runs/asic/01-yosys-synthesis", "project/runs/asic/08-yosys-synthesis"), "noncausal synthesis/physical")
    def dangling_cts(p):
        historical = read(p / "timing-intent/request.json")["execution_root"]
        path = p / "project/runs/asic/03-openroad-cts/state_out.json"
        j = read(path); j.update(nl=historical + "/project/runs/asic/missing.nl.v", odb=historical + "/project/runs/asic/missing.odb")
        write(path, j)
    negative("F5-dangling-cts", dangling_cts, "missing physical source")

    # True controls: native list serialization is equivalent; real CTS views may
    # differ from routed views because later buffering/repair is legitimate.
    for label, mutate in [
        ("propagation-literal-list", lambda p: (p / corner / "native-state.sdc").write_text((p / corner / "native-state.sdc").read_text().replace("[get_clocks {clk}]", "[list [get_clocks {clk}]]"))),
        ("retained-filter-report", lambda p: (p / corner / "checks.rpt").write_text("report_parasitic_annotation -report_unannotated\nFound 1 unannotated driver.\n unused_pad\n===========================================================================\n"))]:
        control = tmp / label; shutil.copytree(root, control); mutate(control); reseal(control)
        assert call([CONSUMER, "inspect", control])["all_corner_timing_goal"] == "pass"
    control = tmp / "different-valid-cts-views"; shutil.copytree(root, control)
    state_path = control / "project/runs/asic/03-openroad-cts/state_out.json"
    cts = read(state_path)
    cts["nl"] = retain_view(control, "project/runs/asic/03-openroad-cts/cts-only.nl.v", "// CTS before routed repair\n")
    cts["odb"] = retain_view(control, "project/runs/asic/03-openroad-cts/cts-only.odb", "CTS physical view before repair\n")
    cts["sdf"] = {"nom_typ_1p20V_25C": [retain_view(control, "project/runs/asic/03-openroad-cts/cts-only.sdf", "retained CTS timing view\n")]}
    write(state_path, cts); reseal(control)
    assert call([CONSUMER, "inspect", control])["all_corner_timing_goal"] == "pass"
    for suffix in ("-0.5 unexpected", "", "1 2"):
        label = "F6-malformed-setup-" + str(len(suffix))
        case = tmp / label; shutil.copytree(root, case)
        log = case / corner / "sta.log"
        log.write_text(log.read_text() + "%OL_METRIC_F timing__setup__ws__corner:" + CORNERS[0] + " " + suffix + "\n")
        reseal(case)
        view = call([CONSUMER, "inspect", case])
        assert view["status"] == "completed" and view["all_corner_timing_goal"] == "unknown"
    control = tmp / "irrelevant-metric-text"; shutil.copytree(root, control)
    log = control / corner / "sta.log"
    log.write_text(log.read_text() + "irrelevant timing__setup__ws__corner:" + CORNERS[0] + " -0.5 unexpected\n"
        + "%OL_METRIC_F timing__setup__ws__corner:other_corner -0.5 unexpected\n")
    reseal(control)
    assert call([CONSUMER, "inspect", control])["all_corner_timing_goal"] == "pass"
    negative("native-mask", lambda p: (p / corner / "native-state.sdc").write_text("current_design " + resolved["DESIGN_NAME"] + "\nset_disable_timing [get_cells u1]\n"), "unsupported native SDC command")
    for label, command in [("clock-wildcard", "set_propagated_clock [get_clocks {*}]"),
                           ("clock-query", "set_propagated_clock [all_clocks]"),
                           ("clock-extra", "set_propagated_clock [get_clocks {clk}] extra")]:
        negative(label, lambda p, command=command: (p / corner / "native-state.sdc").write_text(
            "current_design " + resolved["DESIGN_NAME"] + "\n" + command + "\n"), "native coverage")
    def corrupt_trace(p):
        stream = p / corner / "resolution.jsonl"
        old = stream.read_text()
        events = [json.loads(line.split("\t", 1)[1]) for line in old.splitlines()]
        next(e for e in events if e.get("label") == "interstage for rx1")["root"] = "wrong/Q"
        new = "".join("HC_ASIC_TIMING_V1\t" + json.dumps(e, separators=(",", ":")) + "\n" for e in events)
        stream.write_text(new)
        log = p / corner / "sta.log"
        log.write_text(log.read_text().replace(old, new))
    negative("wrong-predecessor", corrupt_trace, "trace root mismatch")
    def wrong_library(p):
        file = p / corner / "native-inputs.json"
        j = read(file)
        next(a for a in j["associations"] if a["role"] == "liberty")["original_path"] = resolved["CELL_LIBS"][CORNERS[1]][0]
        write(file, j)
    negative("wrong-library", wrong_library, "ordered native library selection")
    negative("cleanup-failure", lambda p: change(p / "timing-intent/transport-result.json", "cleanup_error", "failed cleanup"), "success contradiction")
    negative("cpu-override", lambda p: change(p / "timing-intent/transport.json", "argv", read(p / "timing-intent/transport.json")["argv"] + ["--cpus=20"]), "exact bounded invocation")
    def downgrade(p):
        manifest_path = p / "project/manifest.json"
        m = read(manifest_path)
        m.pop("timing_physical_qualification")
        m.pop("timing_native_coverage")
        m["files"] = [r for r in m["files"] if r["path"] != "constraints/pt7-native-coverage.tcl"]
        m["timing_intent"]["resolution_policy"] = "scalar-q-driver-cmos5l-v1"
        write(manifest_path, m)
        record = read(p / "run.json")
        record.update(timing_intent_expected=False, manifest_sha256=sha(manifest_path))
        write(p / "run.json", record)
    negative("independent-physical-expectation", downgrade, "physical timing marker missing", seal=False)
    assert call([CONSUMER, "collect", tmp / "independent-physical-expectation"])["timing_intent"]["status"] == "invalid"

    # A coherent metric mutation remains valid evidence but cannot earn closure.
    case = tmp / "negative-hold"
    shutil.copytree(root, case)
    log = case / corner / "sta.log"
    log.write_text(log.read_text().replace("timing__hold__ws__corner:" + CORNERS[0] + " 0.125", "timing__hold__ws__corner:" + CORNERS[0] + " -0.25"))
    state_path = case / "timing-intent/corners/state_out.json"
    state = read(state_path)
    state["metrics"]["timing__hold__ws__corner:" + CORNERS[0]] = -0.25
    write(state_path, state)
    reseal(case)
    assert call([CONSUMER, "inspect", case])["all_corner_timing_goal"] == "fail"

    # Missing metrics cannot be borrowed from State or sampled witnesses.
    case = tmp / "inherited-hold"
    shutil.copytree(root, case)
    log = case / corner / "sta.log"
    log.write_text("\n".join(line for line in log.read_text().splitlines() if not line.startswith("%OL_METRIC_F timing__hold__ws")) + "\n")
    reseal(case)
    assert call([CONSUMER, "inspect", case])["all_corner_timing_goal"] == "unknown"

    metric_input = dict(corner=CORNERS[0], log=(root / corner / "sta.log").read_text(),
                        output=read(root / "timing-intent/corners/state_out.json"),
                        libraries=[(root / corner / "library-0.lib").read_text()])
    for mode, expected in [("duplicate", "unknown"), ("state-conflict", "unknown"), ("unknown-unit", "unknown"),
                           ("nan", "unknown"), ("fractional-count", "unknown"), ("violation", "fail"), ("valid", "pass")]:
        j = copy.deepcopy(metric_input)
        key = "timing__setup_vio__count__corner:" + CORNERS[0]
        slack = "timing__setup__ws__corner:" + CORNERS[0]
        if mode == "duplicate":
            j["log"] += "%OL_METRIC_F " + slack + " 2.5\n"
        elif mode == "state-conflict":
            j["output"]["metrics"][slack] = 3
        elif mode == "unknown-unit":
            j["libraries"] = ['time_unit : "1ps";\n']
        elif mode == "nan":
            j["log"] = j["log"].replace(slack + " 2.5", slack + " NaN")
        elif mode in ("fractional-count", "violation"):
            value = 0.5 if mode == "fractional-count" else 1
            j["log"] = j["log"].replace(key + " 0", key + " " + str(value))
            j["output"]["metrics"][key] = value
        path = tmp / ("metric-" + mode + ".json")
        write(path, j)
        assert call([CONSUMER, "metrics", path])["setup_goal"] == expected

    archive = tmp / "archive"
    call([CLI, "archive", root, "--output", archive, "--json"])
    archived_inventory = read(archive / "archive.json")
    assert set(authoritative_paths).issubset(archived_inventory["members"])
    verified_reports = archived_inventory["verified"]["authoritative_report_inventory"]["reports"]
    assert {row["source"]["path"] for row in verified_reports} == set(authoritative_paths)
    assert all(row["source"]["sha256"] == sha(root / row["source"]["path"]) for row in verified_reports)
    restored = tmp / "restored"
    restored.mkdir()
    shutil.copyfile(archive / "run.json", restored / "run.json")
    with tarfile.open(archive / "reports.tar.gz") as stream:
        stream.extractall(restored, filter="data")
    unpack = tmp / "unpack"
    unpack.mkdir()
    with tarfile.open(archive / "input-bundle.tar.gz") as stream:
        stream.extractall(unpack, filter="data")
    shutil.copytree(unpack / "bundle", restored / "project", dirs_exist_ok=True)
    for corner_name in CORNERS:
        (tmp / (corner_name + ".lib")).unlink()
    hidden_root, hidden_bundle = tmp / "original-run-hidden", tmp / "original-bundle-hidden"
    root.rename(hidden_root); bundle.rename(hidden_bundle)
    try:
        assert call([CONSUMER, "inspect", restored]) == baseline
        restored_collection = call([CLI, "collect", restored, "--json"])
        assert restored_collection == collected, (set(collected["raw_artifacts"]) - set(restored_collection["raw_artifacts"]))
        assert call([CONSUMER, "report", restored]) == original_report
    finally:
        hidden_root.rename(root); hidden_bundle.rename(bundle)

    synth = tmp / "synthesis"
    resolved = fixture(synth, bundle, physical=False)
    write(synth / "request-unused.json", dict(physical=False))
    runtime(synth, resolved)
    call([CONSUMER, "publish", synth, "true"])
    synth_view = call([CONSUMER, "inspect", synth])
    assert synth_view["stage"] == "synthesized_netlist" and len(synth_view["corners"]) == 3
    assert all(row["evidence"]["schema"] == 2 for row in synth_view["corners"])
    legacy_synth = tmp / "synthesis-unused-historical-view"
    shutil.copytree(synth, legacy_synth)
    for relative in ("project/runs/asic/01-yosys-synthesis/state_out.json", "timing-intent/corners/state_in.json", "timing-intent/corners/state_out.json"):
        path = legacy_synth / relative
        j = read(path); j["json_h"] = "/historical/unused-json-header.vh"
        write(path, j)
    reseal(legacy_synth)
    assert call([CONSUMER, "inspect", legacy_synth])["stage"] == "synthesized_netlist"

    for mode in ("later_failure", "missing"):
        case = tmp / ("runtime-" + mode)
        resolved = fixture(case, bundle)
        write(case / "request-unused.json", dict(physical=True))
        try:
            runtime(case, resolved, mode)
            raise AssertionError("runtime failure was promoted")
        except (ValueError, subprocess.CalledProcessError):
            assert not (case / "timing-intent/runtime-result.json").exists()
            terminal_path = case / "timing-intent/transport-result.json"
            terminal = read(terminal_path)
            terminal.update(succeeded=False, code=9)
            write(terminal_path, terminal)
            call([CONSUMER, "publish", case, "false"])
            view = call([CONSUMER, "inspect", case])
            assert view["status"] == "failed" and view["all_corner_timing_goal"] == "unknown"
            progress = view["corner_execution"]
            assert progress["executed_corners"] == (CORNERS[:-1] if mode == "missing" else CORNERS)

    for label, mutate in [
        ("runtime-noncausal-sta", lambda p: rename_producer(p, "project/runs/asic/06-openroad-stapostpnr", "project/runs/asic/00-openroad-stapostpnr")),
        ("runtime-unclosed-cts-view", dangling_cts),
        ("runtime-rcx-odb-mismatch", lambda p: change(p / "project/runs/asic/05-openroad-rcx/state_out.json", "odb", str(p / "project/runs/asic/unrelated.odb")))]:
        case = tmp / label; resolved = fixture(case, bundle)
        write(case / "request-unused.json", dict(physical=True))
        mutate(case)
        try:
            runtime(case, resolved)
            raise AssertionError("invalid implementation lineage launched linked STA")
        except (ValueError, FileNotFoundError):
            assert not (case / "timing-intent/corners").exists()
            assert not (case / "timing-intent/runtime-result.json").exists()
            COUNT += 1
    for mode in ("wrong_filter", "missing_checks"):
        case = tmp / ("runtime-" + mode); resolved = fixture(case, bundle)
        write(case / "request-unused.json", dict(physical=True))
        try:
            runtime(case, resolved, mode)
            raise AssertionError("incomplete/wrong actual filter execution was promoted")
        except (ValueError, FileNotFoundError):
            assert not (case / "timing-intent/runtime-result.json").exists()
            COUNT += 1

    # Public enable gates reject before allocation/probes, with real emitted
    # bundles rather than manufactured manifest identities.
    synth_bundle, default_bundle = tmp / "synth-bundle", tmp / "default-bundle"
    call([EMITTER, synth_bundle, "synthesis"])
    call([EMITTER, default_bundle, "default"])
    (tmp / "tt").mkdir()
    (tmp / "pdk").mkdir()
    for b, diagnostic in [(synth_bundle, "Hardening bundle"), (default_bundle, "coarse synthesis only")]:
        runs = tmp / (b.name + "-rejected-runs")
        call([CLI, "run", b, "--stage", "full", "--support-tools", tmp / "tt", "--pdk-root", tmp / "pdk",
              "--python", sys.executable, "--runs", runs, "--json"], 2, diagnostic)
        assert not runs.exists()

    # Actual supervised transport over a fake Docker executable. No EDA is run.
    docker = tmp / "docker-fixture"
    docker.write_text('''#!/usr/bin/env python3
import json, pathlib, sys, time
root=pathlib.Path(__file__).parent
mode=(root/"docker-mode").read_text()
if sys.argv[1] == "rm":
    sys.exit(8 if mode == "cleanup" else 0)
assert "--cpus=6" in sys.argv and not any(x == "--cpus=20" for x in sys.argv)
if mode == "timeout":
    time.sleep(60)
if mode == "obstruct":
    request=json.loads(pathlib.Path(sys.argv[-1]).read_text())
    (pathlib.Path(request["execution_root"])/"timing-intent/analysis.json").mkdir()
sys.exit(0 if mode == "cleanup" else 9)
''')
    docker.chmod(0o700)
    for mode, code in [("exit", 9), ("timeout", 124), ("cancel", 130), ("cleanup", 1), ("obstruct", 9)]:
        case = tmp / ("transport-" + mode)
        fixture(case, bundle)
        shutil.rmtree(case / "timing-intent")
        record = read(case / "run.json")
        record["execution_binding"]["engine_identity"]["executable"] = str(docker)
        record["implementation_process"]["argv"][0] = str(docker)
        record["commands"] = [record["implementation_process"]["argv"]]
        write(case / "run.json", record)
        (tmp / "docker-mode").write_text(mode)
        # Capture has no successful native Step, so its failure companion must
        # remain failed/unavailable even when the fake native payload exits0.
        p = subprocess.run([str(CONSUMER), "capture", str(case), str(docker), str(HELPER.parent),
                            "0.1" if mode == "timeout" else "5", "cancel" if mode == "cancel" else "run"],
                           text=True, capture_output=True, timeout=30)
        assert p.returncode == code, (mode, p.returncode, p.stderr)
        COUNT += 1
        if mode == "obstruct":
            assert "companion publication failed" in p.stderr
            assert (case / "timing-intent/analysis.json").is_dir()
        else:
            view = call([CONSUMER, "inspect", case])
            assert view["status"] == "failed" and view["all_corner_timing_goal"] == "unknown"

    # Fresh public coarse full/synthesis orchestration, including early six-worker
    # metadata probes, actual helper staging and automatic required capture.
    fake_bin, tools, pdk = tmp / "public-bin", tmp / "public-tools", tmp / "public-pdk"
    fake_bin.mkdir(); tools.mkdir(); pdk.mkdir()
    cell_dir = pdk / "ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog"
    cell_dir.mkdir(parents=True)
    (cell_dir / "sg13cmos5l_stdcell.v").write_bytes(Path(__file__).with_name("vendor_cells.v").read_bytes())
    (cell_dir / "sg13cmos5l_udp.v").write_text("// supplied UDP fixture\n")
    public_bundle = tmp / "public-bundle"
    shutil.copytree(bundle, public_bundle)
    manifest = read(public_bundle / "manifest.json")
    for ref in manifest["target"]["external_references"]:
        path = (tools if ref["source"] == "Support_tools" else pdk / manifest["target"]["technology"]) / ref["path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists():
            path.write_text("fixture collateral\n")
        ref["sha256"] = None
    write(public_bundle / "manifest.json", manifest)
    write(public_bundle / "manifest.json", call([CONSUMER, "seal", public_bundle / "manifest.json"]))
    image = call([CONSUMER, "binding"])["image_identity"]["image_id"]
    engine_args = [str(Path(__file__).resolve()), *map(str, (EMITTER, CONSUMER, CLI, HELPER))]
    fake_source = f'''#!{sys.executable}
import json, os, pathlib, sys
a=sys.argv[1:]; name=pathlib.Path(sys.argv[0]).name
manifest=json.loads(pathlib.Path({str(public_bundle / 'manifest.json')!r}).read_text())
with pathlib.Path({str(tmp / 'public-calls.jsonl')!r}).open("a") as f: f.write(json.dumps([name,a])+"\\n")
if name == "git":
    if "rev-parse" in a: print(manifest["requested_tools"]["support_tools_revision" if a[1] == {str(tools)!r} else "pdk_revision"])
    sys.exit(0)
if name == "docker":
    if a[0] == "info":
        print(json.dumps(dict(ServerVersion="29.0",SecurityOptions=["rootless"],ID="daemon",Name="fixture"))); sys.exit(0)
    if a[:2] == ["image","inspect"]:
        print({image!r} if "--format" in a else json.dumps([dict(Id={image!r},RepoDigests=[],Os="linux",Architecture="amd64")])); sys.exit(0)
    if a[0] == "rm": sys.exit(0)
    assert a[0] == "run" and "--cpus=6" in a and "--pull=never" in a
    if "implementation" in a:
        assert a[a.index("--jobs")+1] == "6" and "STA_THREADS=1" in a and "KLAYOUT_DRC_THREADS=6" in a
        root=pathlib.Path.cwd().parent
        os.execv(sys.executable,[sys.executable,"-B",*{engine_args!r},"--implementation",str(root),"synthesis" if "--to" in a else "full"])
    if a[-1].endswith("/timing-intent/request.json"):
        os.execv(sys.executable,[sys.executable,"-B",*{engine_args!r},"--analysis",a[-1]])
host=name != "docker"
code=a[a.index("-c")+1]
value=dict(python_version="3.11.9" if host else "3.13.1",librelane_version="3.1.0.dev3",requires_python=">=3.10",metadata_error=None)
if host: value["tcl"]=dict(ready=True,version="8.6",error=None)
if "stage_runtime_metadata" in code: value=dict(protocol_version=1,kind="stage_runtime_metadata",role="host" if host else "container",metadata=value)
print(json.dumps(value))
'''
    for name in ("python", "git", "docker"):
        path = fake_bin / name
        path.write_text(fake_source)
        path.chmod(0o700)
    old_path = os.environ["PATH"]
    os.environ["PATH"] = str(fake_bin)
    try:
        for stage in ("synthesis", "full"):
            outcome = call([CLI, "run", public_bundle, "--stage", stage, "--support-tools", tools,
                "--pdk-root", pdk, "--python", fake_bin / "python", "--runs", tmp / ("public-" + stage + "-runs"), "--json"])
            assert outcome["status"] == "completed", outcome
            run = Path(outcome["run_dir"])
            record = read(run / "run.json")
            assert record["timing_physical_expected"] and record["resource_limits"] == dict(tool_workers=6, container_cpus=6, sta_workers=1)
            view = call([CLI, "timing-intent-inspect", run, "--kind", "coarse_run", "--json"], 1)
            assert view["status"] == "completed" and len(view["executed_corners"]) == 3
            assert view["stage"] == ("post_pnr" if stage == "full" else "synthesized_netlist")
    finally:
        os.environ["PATH"] = old_path

    # Exercise the real public postcheck on the macro-free qualification marker:
    # bounded Nix, host affinity, container quotas and nested-tool environment.
    spec = importlib.util.spec_from_file_location("postcheck_boundary_fixture", Path(__file__).parent.parent / "check_postcheck.py")
    post_fixture = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(post_fixture)
    post_root = tmp / "postcheck-boundary"
    post_root.mkdir()
    write(post_root / "mode.json", dict(engine="29.0"))
    post_bin = post_root / "bin"
    post_bin.mkdir()
    fake = post_fixture.FAKE.replace("INTERPRETER", sys.executable).replace("=='20'", "=='6'").replace("<=20", "<=6").replace("--cpus=20", "--cpus=6")
    fake = fake.replace("'a'*64", repr(image.split(":", 1)[1])).replace("SecurityOptions=[]", "SecurityOptions=['rootless']")
    fake = fake.replace("('b' if mode.get('image_mismatch') else 'a')*64", repr(image.split(":", 1)[1]))
    fake = fake.replace("    if 'iverilog' in a:", "    if 'python3' in a and 'models' in a:\n        sys.exit(subprocess.call([sys.executable] + a[a.index('python3')+1:]))\n    if 'iverilog' in a:")
    fake = fake.replace("        block('compile')", "        block('compile')\n        if mode.get('corrupt_model'):\n            target=pathlib.Path(a[a.index('-o')+1]).parent/mode['corrupt_model']\n            target.write_text(target.read_text()+'\\n// changed after model derivation\\n')")
    for name in ("docker", "nix-shell"):
        path = post_bin / name
        path.write_text(fake)
        path.chmod(0o700)
    # Bind the already captured Docker path to this controlled boundary without
    # changing the recorded runtime identity or introducing a provider action.
    (fake_bin / "docker").write_text(fake)
    for name in ("env", "dirname", "readlink"):
        (post_bin / name).symlink_to(shutil.which(name))
    (post_bin / "python3").symlink_to(sys.executable)
    pre = tools / "precheck"
    pre.mkdir(exist_ok=True)
    (tools / "tech").mkdir(exist_ok=True)
    (pre / "default.nix").write_text('let pkgs = import (fetchTarball "https://example.invalid/pinned.tar.gz") {}; in pkgs.mkShell {}')
    write(pre / "tool-versions.json", dict(klayout="0.28.17"))
    (pre / "precheck.py").write_text(post_fixture.PRECHECK.replace("=='20'", "=='6'").replace("<=20", "<=6"))
    venv_dir = post_root / "venv"
    venv.EnvBuilder(with_pip=False).create(venv_dir)
    site = next((venv_dir / "lib").glob("python*/site-packages"))
    dist = site / "klayout-0.28.17.dist-info"
    dist.mkdir()
    (dist / "METADATA").write_text("Name: klayout\nVersion: 0.28.17\n")
    for relative in ("sg13cmos5l_io/verilog/sg13cmos5l_io.v", "sg13cmos5l_stdcell/verilog/sg13cmos5l_udp.v", "sg13cmos5l_stdcell/verilog/sg13cmos5l_stdcell.v"):
        path = pdk / "ihp-sg13cmos5l/libs.ref" / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists():
            path.write_text("// fixture functional model\n")
    final = run / "project/runs/asic/final"
    top = read(run / "project/manifest.json")["top_module"]
    (final / "gds").mkdir(parents=True)
    (final / "nl").mkdir()
    (final / "gds" / (top + ".gds")).write_text("fixture GDS\n")
    (final / "nl" / (top + ".nl.v")).write_bytes((run / "project/runs/asic/mapped.v").read_bytes())
    tb = post_root / "tb.v"
    tb.write_text("module memory_tb; endmodule\n")
    p = subprocess.run([str(CLI), "postcheck", str(run), "--support-tools", str(tools), "--pdk-root", str(pdk),
        "--precheck-python", str(venv_dir / "bin/python"), "--testbench", str(tb), "--testbench-top", "memory_tb", "--timeout", "20", "--json"],
        text=True, capture_output=True, timeout=60, env=dict(os.environ, PATH=str(post_bin), FIXTURE=str(post_root)))
    assert p.returncode == 0, (p.returncode, p.stdout, p.stderr)
    outcome = json.loads(p.stdout)
    record = read(Path(outcome["check_record"]))
    assert record["resource_limits"]["host_cpu_affinity_max"] == 6
    assert record["tools"]["replay_profile"] == "cmos5l_physical_timing_used_cells_v1"
    assert record["tools"]["replay_scope"] == "zero_delay_gate_functional_not_timing_conformance"
    check_dir = Path(outcome["check_dir"])
    assert (check_dir / "stdcell-vendor.v").read_bytes() == (cell_dir / "sg13cmos5l_stdcell.v").read_bytes()
    assert "assign delayed_CLK = CLK;" in (check_dir / "stdcell-functional.v").read_text()
    inventory = read(check_dir / "replay-models.json")
    assert inventory["netlist_sha256"] == sha(final / "nl" / (top + ".nl.v"))
    assert record["inputs"]["replay_models_sha256"] == sha(check_dir / "replay-models.json")
    calls = [json.loads(line) for line in (post_root / "calls.jsonl").read_text().splitlines()]
    assert all(a[:4] == ["--max-jobs", "1", "--cores", "6"] for name, a in calls if name == "nix-shell")
    assert all("--cpus=6" in a for name, a in calls if name == "docker" and a[0] == "run")
    COUNT += 1

    # Public archive must retain every model artifact advertised by postcheck,
    # including the unchanged supplied vendor bytes and derivation inventory.
    archive_path = tmp / "postcheck-archive"
    call([CLI, "archive", run, "--output", archive_path, "--json"])
    with tarfile.open(archive_path / "reports.tar.gz") as stream:
        names = set(stream.getnames())
        prefix = "checks/" + outcome["check_id"] + "/"
        assert all(prefix + name in names for name in record["artifacts"])

    derived = check_dir / "stdcell-functional.v"
    stored_results = run / "results.json"
    write(stored_results, call([CONSUMER, "collect", run]))
    stored_hash = sha(stored_results)
    original = derived.read_bytes()
    try:
        derived.write_bytes(original + b"\n// changed after completed postcheck\n")
        changed = call([CONSUMER, "collect", run])
        assert any("postcheck artifact changed: stdcell-functional.v" in error for error in changed["errors"])
        reported = call([CONSUMER, "report", run])
        assert any("postcheck artifact changed: stdcell-functional.v" in error for error in reported["errors"])
        assert sha(stored_results) == stored_hash
        rejected = tmp / "postcheck-tampered-archive"
        call([CLI, "archive", run, "--output", rejected, "--json"], 2, "postcheck artifact changed")
        assert not rejected.exists()
    finally:
        derived.write_bytes(original)

    post_args = [str(CLI), "postcheck", str(run), "--support-tools", str(tools), "--pdk-root", str(pdk),
        "--precheck-python", str(venv_dir / "bin/python"), "--testbench", str(tb), "--testbench-top", "memory_tb", "--timeout", "20", "--json"]
    post_env = dict(os.environ, PATH=str(post_bin), FIXTURE=str(post_root))
    for label, path, diagnostic in [
        ("final-netlist", final / "nl" / (top + ".nl.v"), "differs from native physical timing input"),
        ("supplied-vendor", cell_dir / "sg13cmos5l_stdcell.v", "postcheck collateral changed"),
        ("native-evidence", run / "timing-intent/corners/state_in.json", "intact completed native post-PNR evidence")]:
        original = path.read_bytes()
        before_checks = set((run / "checks").iterdir())
        try:
            path.write_bytes(original + b"\n// changed input\n")
            result = subprocess.run(post_args, text=True, capture_output=True, timeout=60, env=post_env)
            assert result.returncode == 2 and diagnostic in result.stderr, (label, result.returncode, result.stderr)
            assert set((run / "checks").iterdir()) == before_checks
            COUNT += 1
        finally:
            path.write_bytes(original)
    for name in ("stdcell-functional.v", "replay-models.json"):
        save_mode = dict(engine="29.0", corrupt_model=name)
        write(post_root / "mode.json", save_mode)
        result = subprocess.run(post_args, text=True, capture_output=True, timeout=60, env=post_env)
        assert result.returncode == 1, (name, result.returncode, result.stderr)
        failed = read(Path(json.loads(result.stdout)["check_record"]))
        assert failed["status"] == "failed" and failed["checks"]["gate_level"] != "pass"
        assert "changed" in failed["error"], failed
        COUNT += 1

print(f"{COUNT} timing physical public/runtime/source checks passed (modeled native boundary)")
