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
           "Odb.RemoveRoutingObstructions", "Misc.ReportManufacturability"]
    class Classic:
        Steps = [types.SimpleNamespace(id=id_) for id_ in ids]
        gating_config_vars = {"*": ["CLOCK_PERIOD"]}
        def __init__(self, config, pdk_root):
            Path(config).with_name("constructed").touch()
            self.project = Path(config).parents[1]
            self.config = Config(CLOCK_PERIOD=10)
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
            self.run_dir = str(self.project / "runs" / tag)
            output = Path(self.run_dir)
            output.mkdir(parents=True)
            view = output / "view.v"
            view.write_text("module fixture; endmodule")
            raw = {"nl": str(view), "json_h": str(view), "odb": str(view), "def": str(view),
                   "metrics": {"backend_nonfinite": float("inf"), "finite": 3.5}}
            return State(raw)
    librelane = types.ModuleType("librelane")
    common = types.ModuleType("librelane.common")
    common.Path = type("ToolPath", (str,), {})
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
