"""Linked typed runner vs actual Python runner, plus callback/storage failures."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace

sys.dont_write_bytecode = True


def verify(consumer):
    from hardcaml_asic_flow import execution_plan as plans, runner, result_store

    count = 0
    with tempfile.TemporaryDirectory(prefix="runner-cases-", dir="/tmp/opencode") as temporary:
        root = Path(temporary)

        def run(plan, **kw):
            nonlocal count
            count += 1
            directory = root / str(count)
            directory.mkdir()
            request = dict(plan=plan.as_dict(), directory=str(directory), **kw)
            completed = subprocess.run([str(consumer)], input=json.dumps(request) + "\n",
                                       text=True, capture_output=True, timeout=10)
            assert completed.returncode == 0, (request, completed.stderr)
            value = json.loads(completed.stdout)
            value["directory"] = directory
            return value

        def parity(plan, codes=None, failures=None, initial=None):
            codes, failures = codes or {}, failures or []
            value = run(plan, codes=codes, failures=failures, initial=initial)
            directory = value["directory"]

            class Outcome:
                def __init__(self, action):
                    self.exit_code = codes.get(action.key, 0)
                    self.status = ("interrupted" if self.exit_code == 143 else
                                   "failed" if self.exit_code else "completed")

                def as_dict(self):
                    return {"run_dir": str(directory / "run"), "status": self.status,
                            "exit_code": self.exit_code}

            class Adapter:
                args = SimpleNamespace(archive=directory / "archive")

                def validate(self, plan):
                    pass

                def fault(self, point, action):
                    for f in failures:
                        if f["point"] == point and f["key"] == action.key:
                            message = f.get("message", point + " fault")
                            if f.get("mode") == "cancel":
                                raise result_store.FlowInterrupted(15)
                            raise ValueError(message)

                def invoke(self, action, *, best_effort=False):
                    self.fault("invoke", action)
                    return Outcome(action) if action.operation in ("run", "postcheck", "segment") else codes.get(action.key, 0)

                def publish(self, action, outcome):
                    self.fault("publish", action)
                    return {"path": str(directory / action.stage), "identity": "a" * 64,
                            "boundary": action.stage, "acceptance": "not_evaluated",
                            **{k: plans.boundary_capabilities()[action.stage][k]
                               for k in ("restart_supported", "restart_targets", "closure_scope", "tested_image_id")}}

            ticks = iter(range(1, 100))
            py = runner._execute(plan, Adapter(), attempt_id="attempt", clock=lambda: float(next(ticks)))
            assert value["execution"] == py.as_dict(), (value, py.as_dict())
            assert value["steps"] == py.steps, (value["steps"], py.steps)
            assert json.loads((directory / "execution.json").read_text()) == py.as_dict()
            assert (directory / "execution.json").read_bytes() == (json.dumps(py.as_dict(), indent=2, sort_keys=True) + "\n").encode()
            return value

        coarse = [plans.resolve(endpoint, archive=archive)
                  for endpoint in ("synthesis", "full") for archive in (False, True)]
        for plan in coarse:
            parity(plan)
            for action in plan.actions:
                if action.enabled:
                    parity(plan, {action.key: 7})
                    if action.operation in ("run", "postcheck"):
                        parity(plan, {action.key: 143})
                    if action.operation != "run":
                        parity(plan, failures=[dict(point="invoke", key=action.key)])
            # A secondary collection failure never replaces implementation failure.
            parity(plan, {plan.actions[0].key: 9, plan.actions[2].key: 4})
            parity(plan, {plan.actions[0].key: 9}, [dict(point="invoke", key=plan.actions[2].key)])

        stage_plans = []
        for endpoint in plans.STAGE_ORDER:
            stage_plans.append((plans.resolve_stages(endpoint), None))
            if endpoint != "synthesis":
                stage_plans.append((plans.resolve_stages(endpoint, resume=True), "synthesis"))
        for start in range(6):
            initial = plans.STAGE_ORDER[start - 1] if start else None
            for end in range(start + 1, 7):
                stage_plans.append((plans.resolve_sequence(plans.STAGE_ORDER[start:end], initial_boundary=initial), initial))
        for plan, initial in stage_plans:
            v = parity(plan, initial=initial)
            trace = [(e["point"], e["key"]) for e in v["trace"]]
            for action in plan.actions:
                order = [trace.index((point, action.key)) for point in
                         ("started", "invoke", "publish", "published", "finished")]
                assert order == sorted(order)
                assert (v["directory"] / (action.stage + ".publication.json")).is_file()
                parity(plan, {action.key: 6}, initial=initial)
                for point in ("invoke", "publish"):
                    parity(plan, failures=[dict(point=point, key=action.key)], initial=initial)

        full = plans.resolve("full", archive=True)
        stages = plans.resolve_stages("signoff")
        # Inject ordinary, explicit and cancellation failures at every lifecycle
        # point of every action; no ready event without actual publication callback.
        for plan in (full, stages):
            for action in plan.actions:
                points = ["started", "invoke", "finished"]
                if action.operation == "segment":
                    points += ["publish", "published"]
                if action.operation == "postcheck":
                    points += ["observe"]
                for point in points:
                    for mode in ("error", "exception", "cancel"):
                        v = run(plan, failures=[dict(point=point, key=action.key, mode=mode)])
                        e, d = v["execution"], v["diagnostics"]
                        assert e["status"] == ("interrupted" if mode == "cancel" else "failed")
                        assert e["exit_code"] == (143 if mode == "cancel" else 2)
                        assert d["primary"]["point"] == point
                        assert d["primary"]["action_key"] == action.key
                        trace = [(x["point"], x["key"]) for x in v["trace"]]
                        assert ("finished", action.key) in trace
                        if point == "started":
                            assert ("invoke", action.key) not in trace
                        if action.operation == "segment":
                            n = list(plan.actions).index(action)
                            published = point in ("published", "finished")
                            assert len(e.get("artifacts", [])) == n + published
                            assert (("published", action.key) in trace) == published
                        if mode == "cancel":
                            later = plan.actions[list(plan.actions).index(action) + 1:]
                            assert not any(("invoke", a.key) in trace for a in later if a.operation != "collect")
                            collect = [o for a, o in zip(plan.actions, e["occurrences"]) if a.operation == "collect"]
                            if collect and collect[0]["status"] != "unreached" and any(a.operation == "collect" for a in later):
                                assert collect[0]["best_effort"] or action.operation == "collect"
                        assert json.loads((v["directory"] / "execution.json").read_text()) == e

        for point in ("validate",):
            for mode in ("error", "exception", "cancel"):
                v = run(stages, failures=[dict(point=point, key="", mode=mode)])
                assert not any(t["point"] == "invoke" for t in v["trace"])
                assert v["diagnostics"]["primary"]["point"] == point
        for plan, initial in stage_plans:
            wrong = "routing" if initial != "routing" else "synthesis"
            v = run(plan, initial=wrong)
            assert v["diagnostics"]["primary"]["point"] == "validate"
            assert not any(t["point"] == "invoke" for t in v["trace"])

        baseline = run(stages)
        assert baseline["snapshots"][0]["status"] == "running"
        assert all(o["status"] == "unreached" for o in baseline["snapshots"][0]["occurrences"])
        assert baseline["snapshots"][-1]["status"] == "completed"
        # Every save, cancellation poll and clock call is injectable.
        saves = sum(t["point"] == "persist" for t in baseline["trace"])
        for i in range(1, saves + 1):
            v = run(stages, failures=[dict(point="persist", key=str(i))])
            assert v["execution"]["status"] == "failed"
            assert v["diagnostics"]["primary"]["point"] == "persist"
            assert v["diagnostics"]["primary"]["error"] == "persist fault"
            if i == 1:
                assert not any(t["point"] == "invoke" for t in v["trace"])
            if i != saves:
                assert json.loads((v["directory"] / "execution.json").read_text()) == v["execution"]
            else:
                # Cannot manufacture a successful terminal write after a failed
                # write: returned failure and diagnostics are authoritative.
                assert json.loads((v["directory"] / "execution.json").read_text())["status"] == "running"
        for point, limit in (("clock", 12), ("cancel", 18)):
            for i in range(1, limit + 1):
                v = run(stages, failures=[dict(point=point, key=str(i), mode="cancel" if point == "cancel" else "error")])
                assert v["diagnostics"]["primary"]["point"] == point
                assert v["execution"]["status"] == ("interrupted" if point == "cancel" else "failed")

        # Primary implementation failure and secondary collection/hook failures.
        run_key, collect_key = full.actions[0].key, full.actions[2].key
        v = run(full, codes={run_key: 9}, failures=[dict(point="invoke", key=collect_key),
                                                   dict(point="finished", key=collect_key)])
        assert v["execution"]["exit_code"] == 9
        assert [x["point"] for x in v["diagnostics"]["secondary"]] == ["invoke", "finished"]
        assert v["execution"]["occurrences"][2]["best_effort"]
        assert v["execution"]["occurrences"][3]["status"] == "unreached"
        assert v["diagnostics"]["secondary"][0]["secondary"] == ["cleanup retained"]
        # Run callback exception is now a recorded failure with no run to collect.
        v = run(full, failures=[dict(point="invoke", key=run_key)])
        assert [x["key"] for x in v["trace"] if x["point"] == "invoke"] == [run_key]
        assert "run" not in v["execution"]
        for plan in coarse:
            v = run(plan)
            for a, o in zip(plan.actions, v["execution"]["occurrences"]):
                assert o["occurrence_id"] == "attempt/" + a.key
                if not a.enabled:
                    assert o["status"] == "skipped" and o["exit_code"] is None

        for plan in (full, stages):
            for action in plan.actions:
                v = run(plan, bad_completion=action.key)
                assert v["diagnostics"]["primary"]["point"] == "invoke"
                assert v["execution"]["status"] == "failed"
                if action.operation in ("run", "segment", "archive"):
                    v = run(plan, wrong_outcome=action.key)
                    assert v["diagnostics"]["primary"]["point"] == "invoke"
                    assert v["execution"]["status"] == "failed"
        v = run(stages, wrong_publication=stages.actions[0].key)
        assert v["diagnostics"]["primary"]["point"] == "publish"
        assert "artifacts" not in v["execution"]
        for setting, tick in (("nonfinite_clock", 1), ("nonfinite_clock", 2), ("backward_clock", 2)):
            v = run(stages, **{setting: tick})
            assert v["diagnostics"]["primary"]["point"] == "clock"
            assert v["execution"]["status"] == "failed"
        v = run(full, failures=[dict(point="invoke", key=run_key, message="")])
        assert v["execution"]["occurrences"][0]["status"] == "failed"
        assert v["execution"]["occurrences"][0]["error"] == ""
        v = run(full, codes={run_key: 9}, completion_error=run_key)
        assert v["execution"]["exit_code"] == 9
        assert v["execution"]["occurrences"][0]["error"] == "process failed"
        assert v["diagnostics"]["primary"]["secondary"] == ["owned cleanup failed"]
        assert v["execution"]["occurrences"][2]["best_effort"]
        assert v["execution"]["occurrences"][2]["status"] == "completed"
        v = run(full, completion_error=run_key)
        assert v["execution"]["status"] == "failed"  # success cannot carry failure evidence
        # Python decimal rounding of the exact binary64 duration, including
        # midpoint-adjacent values that double-rounded multiplication gets wrong.
        import math
        single = plans.resolve_stages("synthesis")
        durations = [0.0, 0.0000005, 0.0000015, 0.1234565, 1.2345675, 5e-324, 1e100, 1.7976931348623157e308]
        durations += [math.nextafter(x, direction) for x in durations[1:6] for direction in (0.0, math.inf)]
        for duration in durations:
            v = run(single, elapsed=duration)
            assert v["execution"]["occurrences"][0]["duration_seconds"] == round(duration, 6)
            assert v["execution"]["status"] == "completed"

        # Real failed IO (not just a synthetic persist exception) is recorded.
        directory = root / "io-failure"
        directory.mkdir()
        (directory / "execution.json").mkdir()
        (directory / "execution.json/retained").write_text("user work")
        completed = subprocess.run([str(consumer)], input=json.dumps(dict(plan=stages.as_dict(), directory=str(directory))) + "\n",
                                   text=True, capture_output=True, check=True, timeout=10)
        v = json.loads(completed.stdout)
        assert v["diagnostics"]["primary"]["point"] == "persist"
        assert v["execution"]["status"] == "failed"
        assert not any(t["point"] == "invoke" for t in v["trace"])
        assert (directory / "execution.json/retained").read_text() == "user work"
        assert not list(directory.glob(".execution.json.*"))

        # Invalid caller IDs fail before any callback or file write.
        for identity in ("", "x/y", "x\x00y"):
            directory = root / ("id-" + str(len(identity)))
            directory.mkdir(exist_ok=True)
            completed = subprocess.run([str(consumer)], input=json.dumps(dict(plan=stages.as_dict(), directory=str(directory), attempt_id=identity)) + "\n",
                                       text=True, capture_output=True, timeout=10)
            assert completed.returncode != 0 and not list(directory.iterdir())

    print(f"runner: {count} linked Python parity/lifecycle/cancellation/filesystem cases passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--consumer", type=Path)
    parser.add_argument("--installed", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    if not args.installed:
        sys.path.insert(0, str(repo / "flow"))
        verify(args.consumer.resolve())
        return
    with tempfile.TemporaryDirectory(prefix="installed-runner-", dir="/tmp/opencode") as temporary:
        root = Path(temporary)
        prefix, consumer = root / "prefix", root / "consumer"
        from reference_harness import installed_prefix
        installed_prefix(repo, prefix)
        consumer.mkdir()
        shutil.copyfile(repo / "test/runner_consumer.ml", consumer / "runner_consumer.ml")
        (consumer / "dune-project").write_text("(lang dune 3.17)\n(name installed_runner_consumer)\n")
        (consumer / "dune").write_text("(executable (name runner_consumer) (libraries hardcaml_asic.execution))\n")
        env = dict(os.environ)
        env["OCAMLPATH"] = str(prefix / "lib") + (":" + env["OCAMLPATH"] if env.get("OCAMLPATH") else "")
        subprocess.run(["dune", "build", "-j20", "runner_consumer.exe"], cwd=consumer, env=env, check=True)
        sys.path.insert(0, str(prefix / "lib/hardcaml_asic/flow"))
        previous = Path.cwd()
        os.chdir(root)
        auditing = True
        def audit(event, values):
            if auditing and event == "open" and isinstance(values[0], (str, bytes, os.PathLike)):
                if Path(os.fsdecode(values[0])).resolve().is_relative_to(repo):
                    raise AssertionError("checkout read in installed runner test")
        sys.addaudithook(audit)
        try:
            verify(consumer / "_build/default/runner_consumer.exe")
        finally:
            auditing = False
            os.chdir(previous)
        print("fresh installed runner consumer passed with Python checkout reads denied")


if __name__ == "__main__":
    main()
