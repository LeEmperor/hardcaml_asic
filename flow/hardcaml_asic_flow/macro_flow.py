"""Versioned stock-macro LVS reader adapter around pinned Classic.

The supplied CDL, powered netlist and implementation state remain immutable.
Only Netgen's schematic-side inputs use graph-isomorphic naming views.
"""
import importlib.util
from pathlib import Path
import runpy


def install(project, helper=None):
    from librelane.steps import Netgen
    from librelane.flows.classic import Classic
    from librelane.state import State, DesignFormat
    from librelane.common import Path as ToolPath

    project = Path(project).resolve()
    helper = Path(helper) if helper is not None else project / "physical-runtime.py"
    spec = importlib.util.spec_from_file_location("macro_physical_runtime", helper)
    runtime = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runtime)
    manifest, _ = runtime.validate_plan(project)
    runtime.require(manifest["macro_contract"]["execution"] == "fresh_full", "physical flow capability required")

    class Cmos5lLVS(Netgen.LVS):
        id = "Netgen.LVS"

        def run(self, state_in, **kwargs):
            originals = self.config["EXTRA_SPICE_MODELS"]
            runtime.require(len(originals) == 1, "exact stock CDL reader input required")
            derived_cdl, derived_verilog = runtime.prepare_lvs_inputs(
                project, originals[0], state_in[DesignFormat.POWERED_NETLIST], self.step_dir)
            original_config = self.config
            self.config = self.config.copy(EXTRA_SPICE_MODELS=[ToolPath(str(derived_cdl))])
            adapted = State(copying=state_in, overrides={DesignFormat.POWERED_NETLIST: ToolPath(str(derived_verilog))},
                            metrics=state_in.metrics)
            try:
                views, metrics = super().run(adapted, **kwargs)
                runtime.validate_lvs_result(Path(self.step_dir), manifest)
                return views, metrics
            finally:
                self.config = original_config

    Classic.Steps = [Cmos5lLVS if cls is Netgen.LVS else cls for cls in Classic.Steps]
    return Cmos5lLVS


if __name__ == "__main__":
    install(Path.cwd())
    runpy.run_module("librelane", run_name="__main__")
