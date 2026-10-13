"""Bounded official-API bridge. Runs inside the selected LibreLane runtime.

Only Step.run is substituted; the final start methods and flow engine are intact.
Checkpoint copies are experiment-local, path-bound handoffs, not a public format.
"""

import argparse
import hashlib
import importlib.metadata
import inspect
import json
import os
from pathlib import Path
import platform
import shutil
import sys
import time

import librelane
from librelane.common import GenericDictEncoder, Path as StatePath
from librelane.flows import Flow, SequentialFlow
from librelane.state import State
from librelane.steps import Step


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    Path(path).write_text(json.dumps(value, cls=GenericDictEncoder, indent=2) + "\n")


def runtime():
    package = Path(inspect.getfile(librelane)).parent
    return {"python": platform.python_version(), "executable": sys.executable,
            "librelane": importlib.metadata.version("librelane"), "package": str(package),
            "pid": os.getpid(), "bridge_path": str(Path(__file__).absolute()),
            "bridge_sha256": digest(__file__),
            "upstream_sha256": {name: digest(package / name) for name in
                                ("flows/flow.py", "flows/sequential.py", "steps/step.py",
                                 "config/config.py", "state/state.py")}}


def observed(flow_type, event_file):
    """Supported substitutions capture body facts and raw update keys/values."""
    def emit(value):
        with Path(event_file).open("a") as stream:
            stream.write(json.dumps(value, cls=GenericDictEncoder) + "\n")

    class Body:
        def run(self, state_in, **kwargs):
            base = {"occurrence": self.id, "implementation": self.get_implementation_id(),
                    "step_dir": self.step_dir}
            emit(base | {"event": "body_entered", "time": time.time(),
                         "input_metrics": dict(state_in.metrics)})
            try:
                views, updates = super().run(state_in, **kwargs)
            except BaseException as exc:
                emit(base | {"event": "body_exception", "exception": type(exc).__name__})
                raise
            emit(base | {"event": "body_returned", "time": time.time(),
                         "raw_updates": dict(updates),
                         "views": {getattr(key, "value", key).id if hasattr(key, "value") else key: value
                                   for key, value in views.items()}})
            return views, updates

    result = flow_type.Substitute({cls.id: type("Observed" + cls.__name__, (Body, cls), {})
                                   for cls in flow_type.Steps})
    assert result.start is Flow.start and result.run is SequentialFlow.run
    assert all(cls.start is Step.start for cls in result.Steps)
    return result


def checkpoint(state, destination):
    """Copy every state view, preserving nested mappings; validate reloaded state."""
    destination = Path(destination)
    destination.mkdir()  # no overwrite/reuse of a partial checkpoint
    inventory = []

    def copy(value, keys):
        if isinstance(value, StatePath):
            target = destination / "views" / Path(*keys) / Path(value).name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(value, target)
            inventory.append({"source": str(value), "path": str(target),
                              "sha256": digest(target), "bytes": target.stat().st_size})
            return str(target)
        if isinstance(value, dict):
            return {key: copy(child, keys + [str(key)]) for key, child in value.items()}
        return value

    # State.dumps is the official state serialization, including cumulative metrics.
    raw = json.loads(state.dumps())
    # Recover Path typing from the actual State rather than treating arbitrary
    # metric strings as files. Nested view dictionaries are supported.
    for key, value in state.items():
        raw[key] = copy(value, [str(key)])
    save(destination / "state.json", raw)
    reloaded = State.loads((destination / "state.json").read_text())
    reloaded.validate()
    save(destination / "views.json", inventory)
    return inventory


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("synthesis", "physical"))
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--pdk-root", type=Path, required=True)
    parser.add_argument("--physical-to", default="OpenROAD.Floorplan")
    args = parser.parse_args()
    report_path = args.project / (args.mode + ".json")
    report = {"designation": "REAL EDA official Classic flow on consumer bundle",
              "mode": args.mode, "runtime": runtime(), "status": "starting"}
    save(report_path, report)
    classic = Flow.factory.get("Classic")
    observed_class = observed(classic, args.project / (args.mode + "-events.jsonl"))
    flow = observed_class(str(args.project / "src/config.json"), pdk_root=str(args.pdk_root))
    ids = [cls.id for cls in flow.Steps]
    synthesis_end = "Yosys.Synthesis"
    physical_from = ids[ids.index(synthesis_end) + 1]
    report.update(plan=ids, synthesis_to=synthesis_end, physical_from=physical_from,
                  physical_to=args.physical_to, engine_methods_unmodified=True)
    save(report_path, report)
    initial = None
    if args.mode == "physical":
        initial = State.loads((args.project / "checkpoint/state.json").read_text())
        initial.validate()
        report["input_state_sha256"] = digest(args.project / "checkpoint/state.json")
        assert not (args.project / "src/runs/synthesis").exists()
        report["original_synthesis_run_absent"] = True
    try:
        state = flow.start(tag=args.mode, with_initial_state=initial,
                           **({"to": synthesis_end} if args.mode == "synthesis" else
                              {"frm": physical_from, "to": args.physical_to}))
        # Only the returned Flow.start supplies the whole segment success fact.
        report.update(status="completed", run_dir=flow.run_dir,
                      returned_steps=[s.id for s in flow.step_objects],
                      final_metrics=dict(state.metrics), final_state=json.loads(state.dumps()),
                      resolved_config_sha256=digest(flow.config_resolved_path))
        if args.mode == "synthesis":
            assert flow.step_objects[-1].id == synthesis_end
            report["checkpoint_views"] = checkpoint(state, args.project / "checkpoint")
            shutil.copyfile(flow.config_resolved_path, args.project / "checkpoint/resolved.json")
        else:
            assert flow.step_objects[0].id == physical_from
            assert flow.step_objects[-1].id == args.physical_to
            assert not any(s.id == synthesis_end for s in flow.step_objects)
            assert state["odb"] is not None and Path(state["odb"]).is_file()
            assert state["def"] is not None and Path(state["def"]).is_file()
            report["physical_artifacts"] = {key: {"path": str(state[key]), "sha256": digest(state[key])}
                                            for key in ("odb", "def")}
    except BaseException as exc:
        report.update(status="failed", exception=type(exc).__name__, error=str(exc))
        raise
    finally:
        save(report_path, report)
    print(json.dumps({"status": report["status"], "report": str(report_path),
                      "returned_steps": report["returned_steps"]}))


if __name__ == "__main__":
    main()
