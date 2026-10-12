"""Opt-in local LibreLane sequencing experiment; no EDA and no engine overrides."""

import hashlib
import importlib.metadata
import inspect
import json
import platform
import shlex
import signal
import sys
import tempfile
import threading
import time
import traceback
from pathlib import Path

import librelane
from librelane.common import Path as StatePath
from librelane.config import Variable
from librelane.flows import Flow, FlowError, FlowException, SequentialFlow
from librelane.state import DesignFormat
from librelane.steps import DeferredStepError, Step, StepError

from fixture import build


EVENTS = []
OBJECTS = []
ENTERED = threading.Event()
RELEASE = threading.Event()


def require(condition, detail):
    if not condition:
        raise AssertionError(detail)


class ObserveBody:
    """Only run() is wrapped. 'body_returned' is deliberately not 'completed'."""

    def run(self, state_in, **kwargs):
        OBJECTS.append(self)
        base = {"occurrence": self.id, "implementation": self.get_implementation_id()}
        EVENTS.append(base | {"event": "body_entered", "input_metrics": dict(state_in.metrics)})
        try:
            views, updates = super().run(state_in, **kwargs)
        except BaseException as exc:
            EVENTS.append(base | {"event": "body_exception", "exception": type(exc).__name__})
            raise
        EVENTS.append(base | {"event": "body_returned", "raw_updates": dict(updates)})
        return views, updates


class Measure(Step):
    id = "Probe.Measure"
    inputs = []
    outputs = []

    def run(self, state_in, **kwargs):
        return {}, {"synthetic__value": 7}


class Inherit(Measure):
    id = "Probe.Inherit"

    def run(self, state_in, **kwargs):
        require(state_in.metrics["synthetic__value"] == 7, "real state propagation")
        return {}, {}


class Hold(Measure):
    id = "Probe.Hold"

    def run(self, state_in, **kwargs):
        require(state_in.metrics["synthetic__value"] == 7, "held body received earlier metric")
        ENTERED.set()
        require(RELEASE.wait(5), "observer did not release held body")
        return {}, {}


class Immediate(Measure):
    id = "Probe.Immediate"

    def run(self, state_in, **kwargs):
        raise StepError("synthetic immediate failure")


class Deferred(Measure):
    id = "Probe.Deferred"

    def run(self, state_in, **kwargs):
        raise DeferredStepError("synthetic deferred failure")


class Invalid(Measure):
    id = "Probe.Invalid"
    outputs = [DesignFormat.NETLIST]

    def run(self, state_in, **kwargs):
        return {DesignFormat.NETLIST: StatePath(str(Path(self.step_dir) / "missing.v"))}, {}


class RuntimeWriteFault(Measure):
    id = "Probe.RuntimeWriteFault"

    def run(self, state_in, **kwargs):
        # Explicit experiment-only filesystem fault: final Step.start cannot open
        # this directory as its runtime.txt file. No upstream function is patched.
        (Path(self.step_dir) / "runtime.txt").mkdir()
        return {}, {"synthetic__value": 7}


class Interrupt(Measure):
    id = "Probe.Interrupt"

    def run(self, state_in, **kwargs):
        raise KeyboardInterrupt("INJECTED exception; not process/descendant cancellation")


WRAPPED = {cls: type("Observed" + cls.__name__, (ObserveBody, cls), {}) for cls in (
    Measure, Inherit, Hold, Immediate, Deferred, Invalid, RuntimeWriteFault, Interrupt
)}


def make_flow(config, pdk_root, steps, gated=False):
    class SyntheticFlow(SequentialFlow):
        Steps = steps
        config_vars = [Variable("OBS_ENABLE", bool, "Synthetic gate", default=False)]
        gating_config_vars = {"Probe.Measure*": ["OBS_ENABLE"]} if gated else {}

    observed = SyntheticFlow.Substitute({
        cls.id + "*": WRAPPED[cls] for cls in dict.fromkeys(steps)
    })
    require(observed.start is Flow.start, "Flow.start must be unmodified")
    require(observed.run is SequentialFlow.run, "SequentialFlow.run must be unmodified")
    require(all(cls.start is Step.start for cls in observed.Steps), "Step.start must be unmodified")
    return observed(str(config), pdk_root=str(pdk_root))


def run_case(config, pdk_root, name, steps, expected=None, gated=False, live=False, **kwargs):
    EVENTS.clear()
    OBJECTS.clear()
    flow = make_flow(config, pdk_root, steps, gated)
    live_result = {}
    observer = None
    if live:
        ENTERED.clear()
        RELEASE.clear()

        def observe_files():
            try:
                require(ENTERED.wait(5), "later body did not enter")
                previous = OBJECTS[:-1]
                states = [json.loads((Path(s.step_dir) / "state_out.json").read_text()) for s in previous]
                require(len(states) == 3, "three earlier outputs visible")
                require(all(s["metrics"]["synthetic__value"] == 7 for s in states), "earlier metrics visible")
                require(all((Path(s.step_dir) / "runtime.txt").is_file() for s in previous), "earlier runtime written")
                held = OBJECTS[-1]
                require(held.state_out is None, "held body not published")
                require(not (Path(held.step_dir) / "state_out.json").exists(), "no held output yet")
                require(not any(e["event"] == "body_returned" and e["occurrence"] == held.id for e in EVENTS), "held body has not returned")
                live_result.update(earlier_metrics=[s["metrics"] for s in states],
                                   held_occurrence=held.id, held_output_absent=True,
                                   barrier="later body waits until observer releases; no sleeps")
            except BaseException as exc:
                live_result["error"] = repr(exc)
            finally:
                RELEASE.set()

        observer = threading.Thread(target=observe_files, daemon=True)
        observer.start()
    outcome = "returned"
    message = None
    final = None
    try:
        final = flow.start(tag=name, **kwargs)
    except BaseException as exc:
        outcome = type(exc).__name__
        message = str(exc)
        require(expected is not None and type(exc) is expected, f"{name}: unexpected {exc!r}")
    finally:
        if observer:
            observer.join(6)
    require(outcome == (expected.__name__ if expected else "returned"), f"{name}: expected failure absent")
    if live:
        require(not observer.is_alive() and "error" not in live_result, f"live observer: {live_result}")
    files = []
    for obj in OBJECTS:
        directory = Path(obj.step_dir)
        files.append({"occurrence": obj.id, "in_memory_state_out": obj.state_out is not None,
                      "state_out_file": (directory / "state_out.json").is_file(),
                      "runtime_file": (directory / "runtime.txt").is_file(),
                      "metrics": json.loads((directory / "state_out.json").read_text())["metrics"]
                      if (directory / "state_out.json").is_file() else None})
    return {"name": name, "outer_outcome": outcome, "outer_message": message,
            "plan": [s.id for s in flow.Steps], "events": list(EVENTS), "outputs": files,
            "live": live_result, "final_metrics": dict(final.metrics) if final is not None else None,
            "returned_step_objects": [s.id for s in flow.step_objects], "assertions": "passed"}


def run_cases(root):
    config, pdk_root = build(root)
    started = time.monotonic()
    # An overall hard bound in addition to the external timeout and barrier bounds.
    signal.alarm(50)
    cases = []
    c = run_case(config, pdk_root, "success-live-origin", [Measure, Inherit, Measure, Hold], live=True)
    require(c["plan"] == ["Probe.Measure", "Probe.Inherit", "Probe.Measure-1", "Probe.Hold"], "normalized repeated occurrences")
    returns = [e for e in c["events"] if e["event"] == "body_returned"]
    require([e["raw_updates"] for e in returns] == [{"synthetic__value": 7}, {}, {"synthetic__value": 7}, {}], "raw origin distinguishes equal remeasurement")
    require(len(c["returned_step_objects"]) == 4 and c["final_metrics"] == {"synthetic__value": 7}, "successful full start returned")
    require(c["outputs"][0]["metrics"] == c["outputs"][1]["metrics"] == c["outputs"][2]["metrics"], "file metric diffs cannot identify origin")
    cases.append(c)
    for name, gated, options, expected_ids in (
        ("gate-false", True, {}, []),
        ("explicit-skip", False, {"skip": ["Probe.Measure-1"]}, ["Probe.Measure", "Probe.Measure-2"]),
        ("from-skip", False, {"frm": "Probe.Measure-1"}, ["Probe.Measure-1", "Probe.Measure-2"]),
        ("to-skip", False, {"to": "Probe.Measure-1"}, ["Probe.Measure", "Probe.Measure-1"]),
        ("range-skip", False, {"frm": "Probe.Measure-1", "to": "Probe.Measure-1"}, ["Probe.Measure-1"]),
    ):
        c = run_case(config, pdk_root, name, [Measure] * 3, gated=gated, **options)
        entered = [e["occurrence"] for e in c["events"] if e["event"] == "body_entered"]
        require(entered == expected_ids and c["returned_step_objects"] == expected_ids, name + " actual skip behavior")
        c["skip_reason_observation"] = "unavailable from run hook/files; expectations come from test inputs, not observed decisions"
        cases.append(c)
    for name, cls, error, expected_events in (
        ("immediate", Immediate, FlowError, ["body_entered", "body_returned", "body_entered", "body_exception"]),
        ("deferred", Deferred, FlowError, ["body_entered", "body_returned", "body_entered", "body_exception", "body_entered", "body_returned"]),
        ("validation-after-body", Invalid, FlowException, ["body_entered", "body_returned", "body_entered", "body_returned"]),
        ("runtime-write-after-body", RuntimeWriteFault, IsADirectoryError, ["body_entered", "body_returned", "body_entered", "body_returned"]),
        ("injected-interruption", Interrupt, KeyboardInterrupt, ["body_entered", "body_returned", "body_entered", "body_exception"]),
    ):
        c = run_case(config, pdk_root, name, [Measure, cls, Inherit], expected=error)
        require([e["event"] for e in c["events"]] == expected_events, name + " body lifecycle")
        require(c["outputs"][0]["state_out_file"], "earlier output survives later failure")
        require(c["returned_step_objects"] == [], "outer failure does not publish local step_list")
        fault = c["outputs"][1]
        if cls is Invalid:
            require(fault["in_memory_state_out"] and not fault["state_out_file"], "validation fails after assignment, before write")
        elif cls is RuntimeWriteFault:
            require(fault["in_memory_state_out"] and fault["state_out_file"] and not fault["runtime_file"], "state_out exists although Step.start failed")
        else:
            require(not fault["in_memory_state_out"] and not fault["state_out_file"], "body failure has no output")
        if cls is Deferred:
            require("deferred errors" in c["outer_message"] and c["outputs"][2]["metrics"] == {"synthetic__value": 7}, "later step continues from earlier state then final failure")
        cases.append(c)
    signal.alarm(0)
    elapsed = time.monotonic() - started
    require(elapsed < 60, "sequencing exceeded bound")
    package = Path(inspect.getfile(librelane)).parent
    sources = {name: hashlib.sha256((package / name).read_bytes()).hexdigest() for name in (
        "flows/flow.py", "flows/sequential.py", "steps/step.py", "config/config.py",
        "config/flow.py", "state/state.py",
    )}
    report = {
        "designation": "SYNTHETIC Python sequencing, not physical/runtime-container acceptance",
        "runtime": {"python": platform.python_version(), "executable": sys.executable,
                    "prefix": sys.prefix, "base_prefix": sys.base_prefix,
                    "librelane": importlib.metadata.version("librelane"), "package": str(package),
                    "declared_python": "3.11", "mismatch": platform.python_version_tuple()[:2] != ("3", "11")},
        "command": "timeout --signal=TERM --kill-after=3s 60s " + shlex.join([sys.executable, "-B", *sys.argv]),
        "scratch": str(root), "elapsed_seconds_after_fixture": elapsed,
        "upstream_sha256": sources, "engine_methods_unmodified": True,
        "experiment_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__), Path(__file__).with_name("fixture.py"))},
        "cases": cases, "case_count": len(cases), "all_assertions": "passed",
        "source_observations": {
            "flows/flow.py:683-693": "start calls run; step_objects assigned only on success",
            "flows/sequential.py:352-411": "gate/skip outside start; direct step.start; deferred failures collected until final snapshot",
            "steps/step.py:1165-1199": "body return, metric merge, state assignment, validation, direct state write, direct runtime write, return",
            "config/config.py:306-329": "normal Step construction revalidates through PDK config",
        },
        "unsupported": ["precise full-Step completion event from run hook", "observed gate/skip decision and reason",
                        "durable atomic publication", "measurement origin from metric diffs alone",
                        "real signal/descendant cancellation (exception injected instead)",
                        "container visibility and declared Python 3.11 correctness", "full provider observation contract"],
    }
    (root / "evidence.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"case_count": len(cases), "all_assertions": "passed", "evidence": str(root / "evidence.json"), "seconds": elapsed}), flush=True)


def main():
    require(sys.flags.optimize == 0, "run without -O")
    root = Path(tempfile.mkdtemp(prefix="librelane-observation-", dir="/tmp/opencode"))
    print(f"SCRATCH={root}", flush=True)
    try:
        run_cases(root)
    except ModuleNotFoundError as exc:
        signal.alarm(0)
        # A missing Tcl prerequisite is a blocker, never a reason to bypass
        # Config.load, fake tkinter, or use a bare Config object.
        require(exc.name == "tkinter" and not EVENTS and not OBJECTS,
                "unexpected missing dependency or partial execution")
        package = Path(inspect.getfile(librelane)).parent
        report = {
            "status": "BLOCKED at official Flow constructor / Config.load",
            "designation": "SYNTHETIC fixture construction only; zero sequencing cases executed",
            "runtime": {"python": platform.python_version(), "executable": sys.executable,
                        "prefix": sys.prefix, "base_prefix": sys.base_prefix,
                        "librelane": importlib.metadata.version("librelane"),
                        "package": str(package), "declared_python": "3.11", "mismatch": True},
            "command": "timeout --signal=TERM --kill-after=3s 60s " + shlex.join([sys.executable, "-B", *sys.argv]),
            "exit_code": 2, "scratch": str(root), "sequencing_cases_executed": 0,
            "assertions_passed": ["Flow.start identity unchanged", "SequentialFlow.run identity unchanged",
                                  "all substituted Step.start identities unchanged",
                                  "missing module is tkinter", "no body callbacks/objects recorded"],
            "traceback": traceback.format_exc(),
            "upstream_sha256": {name: hashlib.sha256((package / name).read_bytes()).hexdigest() for name in (
                "flows/flow.py", "flows/sequential.py", "steps/step.py", "config/config.py",
                "config/flow.py", "common/tcl.py")},
            "experiment_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (
                Path(__file__), Path(__file__).with_name("fixture.py"))},
            "fixture_sha256": {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in sorted(root.rglob("*")) if p.is_file()},
            "source_observations_only": {
                "flows/flow.py:364-374,683-693": "constructor uses Config.load; start calls run and only assigns step_objects on success",
                "flows/sequential.py:352-411": "gates/skips outside start; direct step.start; deferred errors accumulated",
                "steps/step.py:1165-1199": "body return precedes merge, assignment, validation, direct state/runtime writes and return",
                "config/config.py:306-329,874-905": "Step revalidation reloads PDK config; PDK/SCL Tcl evaluated through TclUtils",
                "common/tcl.py:61": "Tcl evaluation requires tkinter; missing in this runtime",
            },
            "unexecuted_cases": ["success-live-origin", "gate-false", "explicit-skip", "from-skip",
                                 "to-skip", "range-skip", "immediate", "deferred", "validation-after-body",
                                 "runtime-write-after-body", "injected-interruption"],
        }
        (root / "evidence.json").write_text(json.dumps(report, indent=2) + "\n")
        print(report["traceback"], file=sys.stderr)
        print(f"BLOCKED evidence={root / 'evidence.json'}", flush=True)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
