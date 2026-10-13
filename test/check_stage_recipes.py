"""Decode real OCaml recipes with the provider, optionally from an installed prefix.

No nested Dune or EDA. Build the emitter/install first with dune build -j 20.
--provider-prefix denies source imports and also checks the installed CLI.
--consumer-executable checks the independently linked specimen recipe command.
"""
import argparse
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
    assert payload["capabilities"] == plans.boundary_capabilities(), "OCaml/backend capability drift"
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
