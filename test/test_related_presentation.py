"""Related CLI presentation using real journals and synthetic operation results."""
import contextlib
import io
import json
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.environ.get("STAGE_TEST_PACKAGE_ROOT", str(Path(__file__).resolve().parents[1] / "flow")))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from hardcaml_asic_flow import cli, flow_observation, execution_plan, finalization, stages
import test_stages


class RelatedPresentationTest(unittest.TestCase):
    def setUp(self):
        self.fixture = test_stages.StagesTest()
        self.fixture.setUp()
        self.root = self.fixture.root

    def tearDown(self):
        self.fixture.tearDown()

    def invoke(self, args):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            try:
                code = cli.main(args)
            except SystemExit as exc:
                code = exc.code
        return code, stdout.getvalue(), stderr.getvalue()

    def positions(self, command):
        yield ["--json", *command]
        yield [command[0], "--json", *command[1:]]
        yield [*command, "--json"]
        if command[0] == "observation":
            yield [*command[:2], "--json", *command[2:]]
            yield ["--json", command[0], "--json", *command[1:], "--json"]

    def test_describe_full_json_and_human_all_positions(self):
        for args in self.positions(["observation", "describe"]):
            code, stdout, stderr = self.invoke(args)
            self.assertEqual((code, stderr), (0, ""))
            self.assertEqual(json.loads(stdout), flow_observation.describe())
        stdout = self.invoke(["observation", "describe"])[1]
        self.assertIn("CAPABILITIES", stdout)
        self.assertIn("reader_mutations", stdout)
        self.assertNotIn('"schemas"', stdout)

    def test_updates_full_payload_empty_reset_and_bounded_summary(self):
        with contextlib.closing(flow_observation.Writer(self.root / "observations", workspace=self.root / "work",
                checkpoint_store=self.fixture.store, request={})) as writer:
            writer.run(lambda: execution_plan.resolve_sequence(execution_plan.STAGE_ORDER),
                       lambda: self.fixture.adapter())
            command = ["observation", "read-updates", str(writer.directory),
                       "--stream-id", writer.stream_id, "--after", "0"]
            expected = flow_observation.read_updates(writer.directory, stream_id=writer.stream_id, after=0)
            for args in self.positions(command):
                code, stdout, stderr = self.invoke(args)
                self.assertEqual((code, stderr), (0, ""))
                self.assertEqual(json.loads(stdout), expected)
            human = self.invoke(command)[1]
            self.assertIn("events omitted", human)
            self.assertIn(f"cursor                 {expected['cursor']}", human)
            self.assertIn("published signoff:", human)
            self.assertLess(len(human.splitlines()), 55)
            empty = self.invoke([*command[:-1], str(expected["cursor"])])[1]
            self.assertIn("no new outcome is implied", empty)
            bad = [*command[:-1], "-1"]
            code, stdout, stderr = self.invoke(bad)
            self.assertEqual(code, 2)
            self.assertIn("RESET_REQUIRED", stdout)
            self.assertTrue(stderr)
            code, stdout, stderr = self.invoke([*bad, "--json"])
            self.assertEqual(json.loads(stdout)["error"]["code"], "RESET_REQUIRED")
            self.assertTrue(stderr)

    def test_stages_jsonl_equivalence_and_early_flush(self):
        (self.root / "workspace").mkdir()
        command = ["stages", str(self.root / "bundle"), "--endpoint", "placement",
                   "--workspace", str(self.root / "workspace"), "--checkpoint-store", str(self.fixture.store),
                   "--support-tools", str(self.root / "tt"), "--pdk-root", str(self.root / "pdk"),
                   "--python", sys.executable, "--observation-store", str(self.root / "observations")]
        for json_args in [None, *self.positions(command)]:
            captured = {}
            def prepare(**kwargs):
                captured["early"] = sys.stdout.getvalue()
                return self.fixture.adapter()
            with patch.object(stages, "prepare", side_effect=prepare):
                code, stdout, stderr = self.invoke(json_args or command)
            self.assertEqual((code, stderr), (0, ""))
            if json_args:
                allocation, result = [json.loads(line) for line in stdout.splitlines()]
                self.assertEqual(json.loads(captured["early"]), allocation)
                self.assertEqual(allocation["event"], "observation_allocated")
                persisted = json.loads((self.root / "workspace" / ("execution-" + result["attempt_id"] + ".json")).read_text())
                self.assertEqual(result, persisted)
            else:
                self.assertIn("allocation", captured["early"])
                for phrase in ("implementation.placement", "execution record", "acceptance             not_evaluated", "historical publication"):
                    self.assertIn(phrase, stdout)
        # Verify the allocation print explicitly requests a flush, before preparation.
        with patch.object(stages, "prepare", return_value=self.fixture.adapter()), patch("builtins.print") as output:
            cli.main([*command, "--json"])
        self.assertTrue(output.call_args_list[0].kwargs["flush"])

    def test_finalization_jsonl_exact_receipt_and_inspection_positions(self):
        command = ["finalize", str(self.root / "missing"), "--operation-store", str(self.root / "operations"), "--accept"]
        for args in self.positions(command):
            code, stdout, stderr = self.invoke(args)
            allocation, result = [json.loads(line) for line in stdout.splitlines()]
            self.assertEqual(code, 1)
            self.assertTrue(stderr)
            directory = Path(result.pop("attempt"))
            self.assertEqual(allocation["attempt"], str(directory))
            self.assertEqual(result, finalization.inspect(directory))
            for inspect_args in self.positions(["finalization-inspect", str(directory)]):
                self.assertEqual(json.loads(self.invoke(inspect_args)[1]), result)
            human = self.invoke(["finalization-inspect", str(directory)])[1]
            self.assertIn("acceptance requested   yes", human)
            self.assertIn("results                not published", human)
            self.assertIn("acceptance             not_evaluated", human)
        code, stdout, stderr = self.invoke(command)
        self.assertEqual(code, 1)
        self.assertIn("allocation", stdout)
        self.assertIn("status                 failed", stdout)
        self.assertTrue(stderr)

    def test_finalization_running_pass_rejection_interruption_summaries(self):
        for status, acceptance, exit_code in (("running", "not_evaluated", None),
                ("completed", "pass", 0), ("failed", "fail", 1), ("interrupted", "not_evaluated", 130)):
            value = {"status": status, "phase": "acceptance", "acceptance": acceptance,
                     "request": {"accept": True}, "external_postcheck": "not_evaluated",
                     "results": {"path": "/results.json"}}
            if exit_code is not None:
                value["exit_code"] = exit_code
            with patch.object(finalization, "inspect", return_value=value):
                human = self.invoke(["finalization-inspect", "/attempt"])[1]
                self.assertIn(status, human)
                self.assertIn(acceptance, human)
                self.assertIn("/results.json", human)
                if status == "running":
                    self.assertIn("nonterminal", human)

    def test_unobserved_stages_failed_and_interrupted_exact_json(self):
        (self.root / "workspace").mkdir()
        command = ["stages", str(self.root / "bundle"), "--endpoint", "placement",
                   "--workspace", str(self.root / "workspace"), "--checkpoint-store", str(self.fixture.store),
                   "--support-tools", str(self.root / "tt"), "--pdk-root", str(self.root / "pdk"),
                    "--python", sys.executable, "--no-observation"]
        for failure in (2, KeyboardInterrupt()):
            for machine in (False, True):
                adapter = self.fixture.adapter(code=2)
                if isinstance(failure, BaseException):
                    def interrupt(*args, **kwargs):
                        raise failure
                    adapter.run_segment = interrupt
                with patch.object(stages, "prepare", return_value=adapter):
                    code, stdout, stderr = self.invoke([*command, "--json"] if machine else command)
                self.assertNotEqual(code, 0)
                if machine:
                    result = json.loads(stdout)
                    self.assertEqual(result, json.loads((self.root / "workspace" /
                        ("execution-" + result["attempt_id"] + ".json")).read_text()))
                    self.assertEqual(result["status"], "interrupted" if isinstance(failure, BaseException) else "failed")
                else:
                    self.assertIn("not established", stdout)
                    self.assertIn("unreached", stdout)
                    self.assertIn("not_evaluated", stdout)
                    self.assertIn("n/a (no finished duration)", stdout)

    def test_finalize_early_flush_full_results_and_no_repeat_operation(self):
        directory = self.root / "operation"
        value = {"attempt_id": "attempt", "status": "completed", "phase": "collection", "exit_code": 0,
                 "acceptance": "not_evaluated", "external_postcheck": "not_evaluated",
                 "request": {"accept": False, "execution": "/execution"},
                 "results": {"path": "/operation/results.json"}, "commands": [list(range(500))]}
        command = ["finalize", "/execution", "--operation-store", str(self.root)]
        for args in [command, *self.positions(command)]:
            early = []
            def operation(**kwargs):
                kwargs["allocated"](directory, "attempt")
                early.append(sys.stdout.getvalue())
                return directory, value
            with patch.object(finalization, "finalize", side_effect=operation) as operation_mock:
                code, stdout, stderr = self.invoke(args)
            operation_mock.assert_called_once()
            self.assertEqual((code, stderr), (0, ""))
            if "--json" in args:
                allocation, result = [json.loads(line) for line in stdout.splitlines()]
                self.assertEqual(json.loads(early[0]), allocation)
                self.assertEqual(result, {"attempt": str(directory), **value})
            else:
                self.assertIn("allocation", early[0])
                self.assertIn("acceptance requested   no", stdout)
                self.assertIn("/operation/results.json", stdout)
                self.assertNotIn("499", stdout)
        def allocated_operation(**kwargs):
            kwargs["allocated"](directory, "attempt")
            return directory, value
        with patch.object(finalization, "finalize", side_effect=allocated_operation), patch("builtins.print") as output:
            cli.main([*command, "--json"])
        self.assertTrue(output.call_args_list[0].kwargs["flush"])

    def test_errors_rejected_combinations_and_single_operation(self):
        for command in (["finalization-inspect", str(self.root / "missing")],
                        ["observation", "read-updates", str(self.root / "missing"), "--stream-id", "x", "--after", "0"]):
            for args in (command, [*command, "--json"]):
                code, stdout, stderr = self.invoke(args)
                self.assertEqual(code, 2)
                self.assertTrue(stderr)
                if args[-1] == "--json":
                    self.assertIn("error", json.loads(stdout))
        for args in (["observation", "describe", "--after", "0"],
                     ["finalization-inspect", "/a", "--accept"],
                     ["observation", "read-updates", "/a", "--json"],
                     ["--json", "archive", "/a", "--list"]):
            self.assertEqual(self.invoke(args)[0], 2)
        with patch.object(flow_observation, "describe", wraps=flow_observation.describe) as describe:
            self.invoke(["observation", "describe"])
            describe.assert_called_once_with()
        with patch.object(finalization, "finalize", side_effect=ValueError("allocation unavailable")) as operation:
            code, stdout, stderr = self.invoke(["finalize", "/execution", "--operation-store", str(self.root), "--json"])
            self.assertEqual(code, 2)
            self.assertEqual(json.loads(stdout), {"contract": finalization.CONTRACT,
                "schema_version": 1, "error": "allocation unavailable"})
            self.assertTrue(stderr)
            operation.assert_called_once()
        command = ["stages", "/bundle", "--endpoint", "placement", "--workspace", str(self.root / "work"),
                   "--checkpoint-store", str(self.fixture.store), "--support-tools", "/tt", "--pdk-root", "/pdk",
                   "--python", sys.executable, "--observation-store", str(self.root / "observations")]
        with patch.object(stages, "prepare", side_effect=ValueError("preparation rejected")) as operation:
            code, stdout, stderr = self.invoke([*command, "--json"])
            allocation, error = [json.loads(line) for line in stdout.splitlines()]
            self.assertEqual(allocation["event"], "observation_allocated")
            self.assertEqual(error["error"], {"code": "EXECUTION_FAILED", "detail": "preparation rejected"})
            self.assertEqual(error["event"], "observation_terminal")
            self.assertEqual(error["attempt"], allocation["attempt"])
            self.assertIsNone(error["execution_file"])
            self.assertEqual(error["observation"], flow_observation.inspect(allocation["attempt"]))
            self.assertEqual(code, 2)
            self.assertTrue(stderr)
            operation.assert_called_once()
        self.assertEqual(self.invoke([*command, "--plan", "/recipe", "--json"])[0], 2)


if __name__ == "__main__":
    unittest.main()
