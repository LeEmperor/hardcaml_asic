"""Protocol 1 import-only payload for the OCaml runtime probe owner.

No orchestration, subprocesses, policy, file writes or preparation. Execute with
host/container argument; container owner may supply this installed text via -c.
"""
import json
import sys
from importlib.metadata import distribution

role = sys.argv[-1]
if role not in ("host", "container"):
    raise ValueError("expected host or container")
result = {"python_version": ".".join(map(str, sys.version_info[:3])),
          "librelane_version": None, "requires_python": None, "metadata_error": None}
try:
    dist = distribution("librelane")
    result.update(librelane_version=dist.version,
                  requires_python=dist.metadata.get("Requires-Python"))
except Exception as exc:
    result["metadata_error"] = str(exc)
if role == "container" and result["metadata_error"] is None:
    # Import-only: no Config/State/Flow construction or physical tool invocation.
    from librelane.flows.classic import Classic
    from librelane.common import Filter
    ids = [step.id for step in Classic.Steps]
    gates = {}
    for key, names in Classic.gating_config_vars.items():
        for step_id in ([key] if key in ids else Filter([key]).filter(ids)):
            gates[step_id] = names
    defaults = {var.name: var.default for var in Classic.config_vars}
    result["classic_inventory"] = [
        {"id": step.id, "implementation": step.get_implementation_id(),
         "inputs": sorted(view.id for view in step.inputs),
         "outputs": sorted(view.id for view in step.outputs),
         "gates": [{"name": name, "default": defaults[name]}
                   for name in gates.get(step.id, [])]}
        for step in Classic.Steps]
    from decimal import Decimal
    from typing import get_args
    def setting(var):
        kind = {bool: "boolean", int: "integer", Decimal: "decimal"}.get(var.type)
        if kind is None:
            kind = "optional_decimal" if set(get_args(var.type)) == {Decimal, type(None)} else str(var.type)
        default = (None if var.default is None else
                   str(var.default).lower() if isinstance(var.default, bool) else str(var.default))
        return {"name": var.name, "kind": kind, "units": var.units,
                "default": default, "pdk": var.pdk}
    result["classic_settings"] = {
        step.get_implementation_id(): [setting(var) for var in step.config_vars]
        for step in Classic.Steps
        if step.get_implementation_id() in (
            "OpenROAD.GlobalPlacement", "OpenROAD.GlobalPlacementSkipIO",
            "OpenROAD.RepairDesignPostGPL", "OpenROAD.DetailedPlacement")}
if role == "host":
    result["tcl"] = {"ready": False, "version": None, "error": None}
    try:
        import tkinter, _tkinter
        tcl = tkinter.Tcl()
        if str(tcl.eval("expr {6 * 7}")) != "42":
            raise ValueError("Tcl expression failed")
        result["tcl"].update(ready=True, version=str(tcl.eval("info patchlevel")))
    except Exception as exc:
        result["tcl"]["error"] = str(exc)
print(json.dumps({"protocol_version": 1, "kind": "stage_runtime_metadata",
                  "role": role, "metadata": result}, allow_nan=False))
