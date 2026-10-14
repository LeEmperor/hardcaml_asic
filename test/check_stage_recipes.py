"""Decode real OCaml recipes with the provider, optionally from an installed prefix.

No nested Dune or EDA. Build the emitter/install first with dune build -j 20.
--provider-prefix denies source imports and also checks the installed CLI.
--consumer-executable checks the independently linked specimen recipe command.
Flow.Stage.capability is the maintained semantic source. The planner's advertised
capabilities and the bridge's AST-extracted literal maps must agree with it.
"""
import argparse
import ast
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def strict(text):
    def reject(value):
        raise ValueError(value)
    return json.loads(text, parse_constant=reject)


BRIDGE_TABLES = ("ENDPOINTS", "SUCCESSORS", "RESTART_TARGETS")


def bridge_literals(text):
    """Read only top-level literal tables; never execute the runtime adapter."""
    tables = {}
    for node in ast.parse(text).body:
        if not isinstance(node, ast.Assign):
            continue
        for target in node.targets:
            if not isinstance(target, ast.Name) or target.id not in BRIDGE_TABLES:
                continue
            assert target.id not in tables, f"duplicate bridge table: {target.id}"
            assert isinstance(node.value, ast.Dict), f"nonliteral bridge table: {target.id}"
            keys = [ast.literal_eval(key) for key in node.value.keys]
            assert len(keys) == len(set(keys)), f"duplicate bridge key: {target.id}"
            tables[target.id] = ast.literal_eval(node.value)
    assert set(tables) == set(BRIDGE_TABLES), "missing bridge table"
    return tables


def check_capabilities(capabilities, order, planner, planner_order, bridge):
    assert list(capabilities) == order, "OCaml capability order drift"
    assert list(planner_order) == order, "OCaml/planner stage order drift"
    assert capabilities == planner, "OCaml/planner capability drift"
    endpoints = {name: c["endpoint"] for name, c in capabilities.items()}
    successors = {name: c["successor"] for name, c in capabilities.items()
                  if c["successor"] is not None}
    # Terminal signoff is deliberately absent from the bridge's restart tables.
    targets = {name: tuple(c["restart_targets"]) for name, c in capabilities.items()
               if c["restart_targets"]}
    for table, expected in zip(BRIDGE_TABLES, (endpoints, successors, targets)):
        assert bridge[table] == expected, f"OCaml/bridge {table} drift"
    assert list(bridge["ENDPOINTS"]) == order, "OCaml/bridge stage order drift"


def check_drift_negatives(capabilities, order, planner, planner_order, bridge, text):
    """Prove each checked representation can fail, including sparse terminal maps."""
    count = 0

    def rejects(label, operation):
        nonlocal count
        try:
            operation()
        except (AssertionError, ValueError, TypeError):
            count += 1
        else:
            raise AssertionError(f"contract accepted deliberate drift: {label}")

    def verify(p=planner, po=planner_order, b=bridge):
        check_capabilities(capabilities, order, p, po, b)

    for field in capabilities[order[0]]:
        changed = copy.deepcopy(planner)
        changed[order[0]][field] = "deliberate drift"
        rejects(f"planner {field}", lambda: verify(p=changed))
    rejects("planner order", lambda: verify(po=tuple(reversed(planner_order))))
    for table in BRIDGE_TABLES:
        for mutation in ("value", "missing", "extra"):
            changed = copy.deepcopy(bridge)
            key = next(iter(changed[table]))
            if mutation == "value":
                changed[table][key] = "deliberate drift"
            elif mutation == "missing":
                del changed[table][key]
            else:
                changed[table]["unknown"] = "deliberate drift"
            rejects(f"bridge {table} {mutation}", lambda: verify(b=changed))
    changed = copy.deepcopy(bridge)
    changed["ENDPOINTS"] = dict(reversed(list(changed["ENDPOINTS"].items())))
    rejects("bridge order", lambda: verify(b=changed))
    for table, value in (("SUCCESSORS", None), ("RESTART_TARGETS", ())):
        changed = copy.deepcopy(bridge)
        changed[table]["signoff"] = value
        rejects(f"bridge terminal {table}", lambda: verify(b=changed))
    changed = copy.deepcopy(bridge)
    changed["RESTART_TARGETS"]["synthesis"] = ("floorplan",)
    rejects("standalone synthesis -> placement", lambda: verify(b=changed))
    for table in BRIDGE_TABLES:
        rejects(f"duplicate {table}", lambda: bridge_literals(text + f"\n{table} = {{}}\n"))
        for literal in ("dict()", "{'synthesis': 'a', 'synthesis': 'b'}"):
            bad = "\n".join(f"{name} = {literal if name == table else '{}'}"
                            for name in BRIDGE_TABLES)
            rejects(f"nonliteral/duplicate key {table}", lambda: bridge_literals(bad))
        bad = "\n".join(f"{name} = {{}}" for name in BRIDGE_TABLES if name != table)
        rejects(f"missing {table}", lambda: bridge_literals(bad))
    # Import and execution poison must be inert under AST-only extraction.
    assert bridge_literals(text + '\nraise RuntimeError("bridge executed")\n') == bridge
    assert "hardcaml_asic_flow.librelane_bridge" not in sys.modules
    assert not any(name == "librelane" or name.startswith("librelane.") for name in sys.modules)
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emitter", required=True, type=Path)
    parser.add_argument("--provider-prefix", type=Path)
    parser.add_argument("--consumer-executable", type=Path)
    args = parser.parse_args()
    package_root = (args.provider_prefix.resolve() / "lib/hardcaml_asic/flow" if args.provider_prefix
                    else Path(__file__).resolve().parents[1] / "flow")
    sys.path.insert(0, str(package_root))
    from hardcaml_asic_flow import execution_plan as plans
    assert Path(plans.__file__).resolve().is_relative_to(package_root.resolve())
    payload = strict(subprocess.check_output([str(args.emitter.resolve())], text=True))
    bridge_path = Path(plans.__file__).with_name("librelane_bridge.py")
    assert bridge_path.resolve().is_relative_to(package_root.resolve())
    bridge_text = bridge_path.read_text()
    bridge = bridge_literals(bridge_text)
    check_capabilities(payload["capabilities"], payload["stage_order"],
                       plans.boundary_capabilities(), plans.STAGE_ORDER, bridge)
    negatives = check_drift_negatives(payload["capabilities"], payload["stage_order"],
                                     plans.boundary_capabilities(), plans.STAGE_ORDER,
                                     bridge, bridge_text)
    print(f"Stage capabilities: OCaml/planner/bridge agree; {negatives} deliberate drift negatives rejected (AST only)")
    accepted = rejected = 0

    def verify(result, expected):
        actual = plans.StagePlan.from_dict(result["recipe"])
        assert actual.as_dict() == expected.as_dict() == strict(result["rendered"])
        assert actual.endpoint == result["endpoint"] and actual.source_boundary == result["source"]
        assert [a.stage for a in actual.actions] == list(actual.sequence)
        assert result["required_input"] == actual.actions[0].inputs[0]
        assert result["declarations"] == [dict(stage=a.stage, input=a.inputs[0], output=a.outputs[0])
                                           for a in actual.actions]

    for case in payload["cases"]:
        raw = dict(schema_version=3, stages=case["requested"], initial_boundary=case["source"])
        try:
            expected = plans.StagePlan.from_dict(raw)
        except ValueError:
            assert case["result"] is None, f"OCaml accepted invalid backend sequence: {raw}"
            rejected += 1
        else:
            assert case["result"] is not None, f"OCaml rejected supported backend sequence: {raw}"
            verify(case["result"], expected)
            accepted += 1
    for case in payload["through"]:
        start = 0 if case["source"] is None else plans.STAGE_ORDER.index(case["source"]) + 1
        names = plans.STAGE_ORDER[start:plans.STAGE_ORDER.index(case["endpoint"]) + 1]
        try:
            expected = plans.resolve_sequence(names, initial_boundary=case["source"])
        except ValueError:
            assert case["result"] is None
            rejected += 1
        else:
            verify(case["result"], expected)
            accepted += 1
    for result in payload["composed"]:
        verify(result, plans.resolve_sequence(result["recipe"]["stages"], initial_boundary=result["source"]))
    # Strict provider field and sequence rejection, including the standalone-only skip.
    for raw in [dict(schema_version=3, stages=["synthesis", "placement"], initial_boundary=None),
                dict(schema_version=3, stages=["placement"], initial_boundary="synthesis"),
                dict(payload["composed"][0]["recipe"], extra=True)]:
        try:
            plans.StagePlan.from_dict(raw)
        except ValueError:
            pass
        else:
            raise AssertionError(f"provider accepted mismatch: {raw}")

    if args.consumer_executable:
        for source in [None, *plans.STAGE_ORDER]:
            for endpoint in plans.STAGE_ORDER:
                command = [str(args.consumer_executable.resolve()), "--endpoint", endpoint]
                if source is not None:
                    command += ["--initial-boundary", source]
                result = subprocess.run(command, capture_output=True, text=True)
                start = 0 if source is None else plans.STAGE_ORDER.index(source) + 1
                names = plans.STAGE_ORDER[start:plans.STAGE_ORDER.index(endpoint) + 1]
                assert (result.returncode == 0) == bool(names), result.stderr
                if names:
                    actual = plans.StagePlan.from_dict(strict(result.stdout))
                    assert actual == plans.resolve_sequence(names, initial_boundary=source)
        print("Independent specimen: all 42 endpoint/source combinations agree")

    if args.provider_prefix:
        # Use the same synthetic publication fixture as the backend suite, with
        # its production imports explicitly directed to the installed package.
        os.environ["STAGE_TEST_PACKAGE_ROOT"] = str(package_root)
        from test_stages import StagesTest
        fixture = StagesTest()
        fixture.setUp()
        try:
            path = Path(fixture.publish()["path"])
            cli = args.provider_prefix.resolve() / "bin/hardcaml-asic-flow"
            env = dict(os.environ, PYTHONPATH="", PYTHONDONTWRITEBYTECODE="1")
            with tempfile.TemporaryDirectory(prefix="recipe-contract-") as cwd:
                def inspect(*extra, success=True):
                    result = subprocess.run([str(cli), "checkpoint-inspect", str(path), "--json", *extra],
                                            cwd=cwd, env=env, text=True, capture_output=True)
                    assert (result.returncode == 0) == success, result.stdout + result.stderr
                    return strict(result.stdout)
                before = {str(p): p.read_bytes() for p in path.rglob("*") if p.is_file()}
                value = inspect("--restart-to", "floorplan")
                assert value["manifest"]["boundary"] == "synthesis"
                assert value["validation"] == "host_only" and not value["runtime_closure_validated"]
                assert value["compatibility_source"] == "recorded"
                expected = Path(cwd) / "compatibility.json"
                expected.write_text(json.dumps(fixture.compat))
                assert inspect("--compatibility", str(expected))["compatibility_source"] == "expected"
                expected.write_text("{}")
                assert "error" in inspect("--compatibility", str(expected), success=False)
                assert "error" in inspect("--restart-to", "cts", success=False)
                assert before == {str(p): p.read_bytes() for p in path.rglob("*") if p.is_file()}
                fixture.constraints.write_text("changed")
                assert "error" in inspect(success=False)
        finally:
            fixture.tearDown()
        print("Installed checkpoint-inspect: read-only success, compatibility/transition/closure rejection")
    print(f"Recipe contract: {accepted} accepted, {rejected} rejected; capabilities, handoffs and composition agree")


if __name__ == "__main__":
    main()
