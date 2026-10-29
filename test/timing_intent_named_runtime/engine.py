#!/usr/bin/python3
"""Fake Docker/native API boundary; real provider supervision/publication/helper."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import types


def read(p):
    return json.loads(Path(p).read_text())


def write(p, value):
    Path(p).parent.mkdir(parents=True, exist_ok=True)
    Path(p).write_text(json.dumps(value, separators=(",", ":")) + "\n")


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def load_module(name, p):
    spec = importlib.util.spec_from_file_location(name, p)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def retarget_alias(case):
    path=Path(read(case / "alias-paths.json")[0])
    target=case / "pdk/ihp-sg13g2/shared/equal-bytes-new-target.lib"
    target.write_bytes(path.read_bytes())
    path.unlink()
    path.symlink_to(target)


def native(helper_path, request_path, mode):
    helper = load_module("actual_named_runtime", helper_path)
    request = read(request_path)
    root = Path(request["execution_root"])
    out = Path(request["analysis_directory"])
    resolved = read(request["resolved_path"])
    library = root.parent / "cells.lib"
    library.write_text('library (fixture) { time_unit : "1ns"; }\n')
    if (root.parent / "alias-paths.json").exists():
        library=Path(read(root.parent / "alias-paths.json")[0])
    script = root.parent / "corner.tcl"
    script.write_text("# fixture, no EDA\n")

    class Step:
        @classmethod
        def get_all_config_variables(cls):
            return [types.SimpleNamespace(name=k) for k in resolved]

        @classmethod
        def load(cls, config, state_in, pdk_root):
            assert state_in == request["checkpoint"]["path"] + "/state.json"
            assert sha(state_in) == next(s["sha256"] for s in read(request["publication"]["path"])["sources"]
                                         if s["path"] == state_in)
            obj = cls()
            obj.config, obj.state = read(config), read(state_in)
            assert obj.config["STA_THREADS"] == obj.config["OPENROAD_THREADS"] == 1
            assert obj.config["STA_CORNERS"] == [resolved["DEFAULT_CORNER"]]
            (root / "actual-state-input").write_text(state_in)
            return obj

        def get_script_path(self):
            return str(script)

        def _get_corner_files(self, *args, **kwargs):
            return "typ", types.SimpleNamespace(libs=[str(library)], netlists=[], spefs=[],
                current_corner_spef=None, extra_spefs_backcompat=None)

        def start(self, toolbox, step_dir):
            step_dir = Path(step_dir)
            step_dir.mkdir()
            write(step_dir / "config.json", self.config)
            write(step_dir / "state_in.json", self.state)
            if mode == "unexecuted":
                return
            corner = resolved["DEFAULT_CORNER"]
            d = step_dir / corner
            d.mkdir()
            env = dict(STA_EXTRA_CORNER_TCL_FILE=self.config["STA_EXTRA_CORNER_TCL_FILE"])
            self.run_corner(self.state, env, corner, str(d))
            write(step_dir / "state_out.json", self.state)
            (step_dir / "runtime.txt").write_text("00:00:00.010")
            if mode == "alias_after":
                retarget_alias(root.parent)

        def run_corner(self, state, env, corner, corner_dir):
            d = Path(corner_dir)
            assert env["CURRENT_NL"] == str(d / "mapped.v")
            assert env["_SDC_IN"] == str(d / "top.sdc")
            assert self.get_command() == ["sta", "-threads", "1", "-no_splash", "-exit", str(out / "driver.tcl")]
            receipt = read(d / "receipt.json")
            event = lambda event_name, **kw: dict(schema_version=1, event=event_name, **kw)
            counts = dict(stage_count=2, exception_count=1)
            scope = dict(id="capture", kind="async_capture", source="ena", targets=["u0/D"])
            stages = [event("stage", id=f"rx{i}", anchor=f"hc_pt7_rx{i}", cell=f"u{i}",
                master="sg13cmos5l_dfrbpq_1", q_pin=f"u{i}/Q", data_pin=f"u{i}/D", async_pin=f"u{i}/RESET_B") for i in range(2)]
            events = [event("begin", **counts), *stages, event("resolved", **scope), event("validated", **counts),
                      event("applied", **scope), event("complete", **counts)]
            log = "PT7_AUDIT_RECEIPT " + json.dumps(receipt, separators=(",", ":")) + "\n"
            log += "".join("HC_ASIC_TIMING_V1\t" + json.dumps(e, separators=(",", ":")) + "\n" for e in events)
            log += "HC_ASIC_NATIVE_V2_COMPLETE\nPT7_AUDIT_COMPLETE\n"
            (d / "sta.log").write_text(log)
            if mode in ("later_failure", "later_failure_cleanup", "failure_obstruction", "malformed_obstruction"):
                raise subprocess.CalledProcessError(9, self.get_command())
            (d / "native-state.sdc").write_text("current_design " + self.config["DESIGN_NAME"] +
                "\nset_false_path -from [get_ports {ena}] -to [get_pins {u0/D}]\n")
            categories = ("no_input_delay", "no_output_delay", "multiple_clock", "no_clock",
                          "unconstrained_endpoints", "loops", "generated_clocks")
            write(d / "native-data.json", dict(schema=2, contract="hardcaml-asic.timing-native-coverage",
                profile="opensta-2.7-native-state-v2", complete=True,
                categories=[dict(name=n, group_count=0, groups=[]) for n in categories],
                endpoint_count=2, endpoints=["u0/D", "u1/D"]))
            (d / "native-checks.rpt").write_text("HC_ASIC_NATIVE_CHECKS_V2 opensta-2.7-native-state-v2\n" +
                "".join(f"HC_ASIC_NATIVE_CATEGORY_BEGIN {n}\nHC_ASIC_NATIVE_CATEGORY_END {n}\n" for n in categories) +
                "HC_ASIC_NATIVE_CHECKS_V2_COMPLETE\n")
            (d / "native-endpoints.rpt").write_text('"u0/D"\n"u1/D"\nHC_ASIC_NATIVE_ENDPOINTS_COMPLETE\n')
            for name in ("downstream_min.rpt", "downstream_max.rpt"):
                (d / name).write_text("slack -0.044244 VIOLATED (synthetic)\n")
            return {}

    def set_tpe(executor):
        assert executor._max_workers == 1
        executor.shutdown()
    sys.modules.update({"librelane": types.ModuleType("librelane"),
        "librelane.steps": types.ModuleType("librelane.steps"),
        "librelane.steps.openroad": types.SimpleNamespace(STAPrePNR=Step),
        "librelane.steps.tclstep": types.SimpleNamespace(TclStep=types.SimpleNamespace(
            value_to_tcl=lambda xs: " ".join(helper.tcl_word(str(x)) for x in xs))),
        "librelane.common": types.SimpleNamespace(Toolbox=lambda path: path, set_tpe=set_tpe)})
    subprocess.run = lambda args, **kw: types.SimpleNamespace(stdout="2.7.0\n", stderr="", returncode=0)
    helper.execute(Path(request_path))


def main():
    root = Path(os.environ["SERVICE_ENGINE_ROOT"])
    args = sys.argv[1:]
    mode = os.environ.get("NAMED_RUNTIME_MODE", "good")
    # Every actual external command must see the first durable pending request,
    # including the very first collateral Git/metadata process.
    receipts = list((root / "evidence/operations").glob("*/operation.json"))
    assert len(receipts) == 1, receipts
    receipt = read(receipts[0])
    early = receipt["timing_intent"]
    snapshot = receipt["timing_intent_snapshot"]
    assert read(snapshot["path"]) == early and sha(snapshot["path"]) == snapshot["sha256"]
    assert read(receipts[0].parent / "preflight.json")["timing_intent"] == early
    write(root / "early-expectation-observed.json", early)
    if args[:2] == ["rm", "-f"]:
        if mode in ("cleanup", "later_failure_cleanup", "cancel_cleanup") and (root / "workspace/analysis-started").exists():
            print("fixture removal failure", file=sys.stderr)
            return 23
        print("No such container: " + args[2], file=sys.stderr)
        return 1
    if args[0] == "info" and mode == "postverify" and (root / "workspace/analysis-started").exists():
        print(json.dumps(dict(ServerVersion="changed", SecurityOptions=[], ID="fixture-daemon", Name="fixture-server")))
        return 0
    if args[0] != "run" or "-c" in args:
        script=root / "bin/stage_preparation_engine.py"
        exec(compile(script.read_text(), str(script), "exec"), {"__name__": "__main__", "__file__": str(script)})
        return 0
    with (root / "runtime-argv.jsonl").open("a") as f:
        f.write(json.dumps(args) + "\n")
    assert args.count("--cpus=6") == 1
    assert "_OPENLANE_MAX_CORES=6" in args and "OMP_NUM_THREADS=6" in args
    payload, request_path = args[-2:]
    request = read(request_path)
    execution = read(next((root / "workspace").glob("execution-*.json")))
    assert execution["timing_intent"]["occurrence_id"] == execution["attempt_id"] + "/implementation.synthesis"
    if request.get("kind") == "hardcaml-asic.named-timing-request":
        assert len(execution["artifacts"]) == 1 and execution["occurrences"][0]["status"] == "running"
        cp = Path(execution["artifacts"][0]["path"])
        before = {str(p): sha(p) for p in cp.rglob("*") if p.is_file()}
        write(root / "checkpoint-before.json", before)
        (root / "workspace/analysis-started").touch()
        if mode in ("failure_obstruction", "cancel_obstruction", "timeout_obstruction"):
            Path(request["expectation"]["companion"]).mkdir()
        if mode == "malformed_obstruction":
            Path(request["expectation"]["companion"]).write_text("not a valid companion\n")
        if mode in ("cancel", "cancel_cleanup", "cancel_obstruction", "timeout", "timeout_obstruction"):
            time.sleep(20)
        if mode == "publication_failure":
            Path(request["expectation"]["companion"]).mkdir()
        if mode == "wrong_state":
            request["state_path"] = request["synthesis_run_dir"] + "/06-yosys-synthesis/state_out.json"
            write(request_path, request)
        if mode == "alias_before":
            retarget_alias(root)
        if mode == "metadata_alias":
            source=Path(request_path)
            copy=root / "foreign-request-copy.json"
            copy.write_bytes(source.read_bytes())
            source.unlink()
            source.symlink_to(copy)
        native(payload, request_path, mode)
        if mode == "alias_post_runtime":
            retarget_alias(root)
        return 0
    assert not (root / "workspace/analysis-started").exists(), "analysis must not run during validation"
    protocol = load_module("protocol", Path(payload).with_name("backend_protocol.py"))
    if request["operation"] == "validate_publication":
        (root / "validation-observed").touch()
        protocol.write_reply(request)
        return 0
    assert not execution.get("artifacts")
    project, candidate = Path(request["project"]), Path(request["candidate"])
    flow = project / "src/runs" / request["tag"]
    producer = flow / "06-yosys-synthesis"
    producer.mkdir(parents=True)
    netlist = producer / "mapped.v"
    netlist.write_text("// fixture, not EDA\n")
    state = dict(nl=str(netlist), json_h=str(netlist), metrics={"finite": 1, "unavailable": float("inf")})
    config = read(project / "src/config.json")
    config.update(DEFAULT_CORNER="typ", STA_CORNERS=["fast", "typ", "slow"], STA_THREADS=1,
        OPENROAD_THREADS=6, PNR_SDC_FILE=str(project / "constraints/top.sdc"),
        STA_EXTRA_CORNER_TCL_FILE=None, STA_MACRO_PRIORITIZE_NL=True, EXTRA_LIBS=None, EXTRA_VERILOG_MODELS=None)
    write(producer / "config.json", dict(meta=dict(step="Yosys.Synthesis", librelane_version="3.1.0.dev3")))
    write(producer / "state_out.json", state)
    write(flow / "resolved.json", config)
    write(candidate / "state.json", state)
    write(candidate / "resolved.json", config)
    closure = {"/nix/store/fixture-runtime": dict(sha256="a" * 64, bytes=1)}
    # Genuine inventoried staged inputs are part of the declared source closure.
    manifest = read(project / "manifest.json")
    for relative in ["manifest.json"] + [entry["path"] for entry in manifest["files"]]:
        p = project / relative
        closure[str(p)] = dict(sha256=sha(p), bytes=p.stat().st_size)
    for p in project.rglob("*"):
        if p.is_file() and (p == project / "manifest.json" or p.relative_to(project).parts[0] in ("constraints", "inputs", "src", "tt")) and not p.is_relative_to(project / "src/runs"):
            closure[str(p)] = dict(sha256=sha(p), bytes=p.stat().st_size)
    for p in (root / "pdk-closure").glob("*"):
        closure[str(p)] = dict(sha256=sha(p), bytes=p.stat().st_size)
    if (root / "declared-pdk-paths.json").exists():
        for name in read(root / "declared-pdk-paths.json"):
            p=Path(name)
            closure[name]=dict(sha256=sha(p), bytes=p.stat().st_size)
    write(candidate / "closure.json", closure)
    steps = ["Verilator.Lint", "Checker.LintTimingConstructs", "Checker.LintErrors", "Checker.LintWarnings",
             "Yosys.JsonHeader", "Yosys.Synthesis"]
    write(candidate / "segment.json", dict(status="completed", boundary="synthesis", **{"from": None}, source_boundary=None,
        to="Yosys.Synthesis", run_dir=str(flow), returned_steps=steps, bridge_sha256=request["bridge_sha256"],
        metrics={}, metric_origin="cumulative_final_state; not per-step measurement provenance", configured_gates={},
        gate_evidence="configured Classic gates; returned_steps are successful outer step objects, not body/skip provenance",
        acceptance="not_evaluated"))
    protocol.write_reply(request)
    return 0


if __name__ == "__main__":
    sys.exit(main())
