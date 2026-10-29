"""Run the actual transported bridge under -I, with deterministic native APIs.

Only LibreLane is replaced. Protocol parsing, integrity, requests/replies, closure
checks, flow range selection and segment reporting are production bridge code.
This fixture establishes wire semantics, not physical-tool readiness.
"""
import importlib.util
import json
import os
from pathlib import Path
import signal
import sys
import types


def run(bridge, request_path):
    mode = os.environ.get("BRIDGE_FIXTURE_MODE", "success")
    class Config(dict):
        def dumps(self):
            if mode == "validation_mismatch":
                return '{"CLOCK_PERIOD":11}'
            if os.environ.get("BRIDGE_FIXTURE_BUNDLE_CONFIG"):
                return json.dumps(self)
            return '{"CLOCK_PERIOD":10}'
    class State:
        def __init__(self, raw):
            self.raw = raw
            self.metrics = raw["metrics"]
        @staticmethod
        def loads(text):
            return State(json.loads(text))
        def validate(self):
            if mode == "invalid_state":
                raise ValueError("fixture incompatible state")
        def dumps(self):
            return json.dumps(self.raw)  # Infinity is intentionally opaque.
    ids = ["Yosys.Synthesis", "Checker.YosysUnmappedCells", "OpenROAD.Floorplan",
           "OpenROAD.DumpRCValues", "OpenROAD.DetailedPlacement", "OpenROAD.CTS",
           "OpenROAD.STAMidPNR-1", "OpenROAD.DetailedRouting",
           "Odb.RemoveRoutingObstructions", "OpenROAD.FillInsertion", "OpenROAD.RCX",
           "OpenROAD.STAPostPNR", "OpenROAD.IRDropReport", "Misc.ReportManufacturability"]
    class Classic:
        Steps = [types.SimpleNamespace(id=id_) for id_ in ids]
        gating_config_vars = {"*": ["CLOCK_PERIOD"]}
        def __init__(self, config, pdk_root, config_override_strings=()):
            assert list(config_override_strings) == ["OPENROAD_THREADS=6", "STA_THREADS=1",
                                                     "KLAYOUT_DRC_THREADS=6", "KLAYOUT_XOR_THREADS=6"]
            Path(config).with_name("constructed").touch()
            self.project = Path(config).parents[1]
            self.config = Config(CLOCK_PERIOD=10)
            if os.environ.get("BRIDGE_FIXTURE_BUNDLE_CONFIG"):
                self.config = Config(json.loads(Path(config).read_text()))
            wrong = os.environ.get("BRIDGE_FIXTURE_WRONG_PARAMETER")
            if wrong:
                self.config[wrong] = json.loads(os.environ["BRIDGE_FIXTURE_WRONG_VALUE"])
            missing = os.environ.get("BRIDGE_FIXTURE_MISSING_PARAMETER")
            if missing:
                self.config.pop(missing, None)
            if os.environ.get("BRIDGE_FIXTURE_RUNTIME_FILE"):
                self.config["RUNTIME_FILE"] = common.Path(os.environ["BRIDGE_FIXTURE_RUNTIME_FILE"])
            self.step_objects = []
        def start(self, *, tag, with_initial_state, frm, to):
            (self.project / "started").touch()
            if mode == "failure":
                raise ValueError("fixture deferred check failed")
            if mode == "interrupt":
                raise KeyboardInterrupt()
            if mode == "signal":
                os.kill(os.getpid(), signal.SIGTERM)
            selected = ids[(ids.index(frm) if frm else 0):ids.index(to) + 1]
            self.step_objects = [types.SimpleNamespace(id=id_) for id_ in selected]
            self.run_dir = str(self.project / "src/runs" / tag)
            output = Path(self.run_dir)
            output.mkdir(parents=True)
            sta_mode = os.environ.get("STA_COMPLETION_MODE")
            if sta_mode and to == "OpenROAD.STAPostPNR":
                producer = output / "11-openroad-stapostpnr"
                corner = producer / "typ"
                corner.mkdir(parents=True)
                (producer / "config.json").write_text(json.dumps({
                    "meta": {"step": "OpenROAD.STAPostPNR", "librelane_version": "3.1.0.dev3"},
                    "STA_CORNERS": ["typ"]}))
                (producer / "state_in.json").write_text('{"metrics":{}}')
                lib = corner / "generated.lib"
                lib.write_text('library (fixture) {\n time_unit : "1ns";\n}\n')
                metrics = {"timing__setup__ws__corner:typ": 1.25,
                           "timing__hold__ws__corner:typ": 0.25,
                           "timing__setup_vio__count__corner:typ": 0,
                           "timing__hold_vio__count__corner:typ": 0}
                (corner / "sta.log").write_text("\n".join(
                    ("%OL_METRIC_I" if "count" in key else "%OL_METRIC_F") + f" {key} {value}"
                    for key, value in metrics.items()) + "\n")
                for report in ("max.rpt", "min.rpt"):
                    (corner / report).write_text("Startpoint: input\nEndpoint: output\nPath Group: clk\nPath Type: max\n 1.0 slack (MET)\n")
                (producer / "state_out.json").write_text(json.dumps({"metrics": metrics, "lib": {"typ": str(lib)}}))
                (producer / "runtime.txt").write_text("00:00:01.575")
                (self.project / "sta-completed").touch()
                if sta_mode == "timing_failure":
                    raise ValueError("Timing deferred check failed after native STA")
            if sta_mode and to == "Misc.ReportManufacturability":
                (self.project / "signoff-started").touch()
                if sta_mode == "failure":
                    raise ValueError("later DRC failed after STA completed")
                if sta_mode == "timeout":
                    import time
                    time.sleep(20)
            view = output / "view.v"
            view.write_text("module fixture; endmodule")
            raw = {"nl": str(view), "json_h": str(view), "odb": str(view), "def": str(view),
                   "metrics": {"backend_nonfinite": float("inf"), "finite": 3.5}}
            if os.environ.get("BRIDGE_FIXTURE_FINAL_VIEWS"):
                raw.update(gds=str(view), lef=str(view))
            return State(raw)
    librelane = types.ModuleType("librelane")
    common = types.ModuleType("librelane.common")
    common.Path = type("ToolPath", (str,), {})
    def set_tpe(executor):
        assert executor._max_workers == 6
        executor.shutdown()
    common.set_tpe = set_tpe
    flows = types.ModuleType("librelane.flows")
    flows.Flow = types.SimpleNamespace(factory=types.SimpleNamespace(get=lambda name: Classic))
    state = types.ModuleType("librelane.state")
    state.State = State
    sys.modules.update({"librelane": librelane, "librelane.common": common,
                        "librelane.flows": flows, "librelane.state": state})
    spec = importlib.util.spec_from_file_location("actual_bridge", bridge)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    sys.argv = [str(bridge), str(request_path)]
    module.main()


if __name__ == "__main__":
    run(Path(sys.argv[1]), Path(sys.argv[2]))
