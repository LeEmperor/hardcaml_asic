"""Inspector output contracts using real journals and validated publications."""

import contextlib
import io
import json
import os
from pathlib import Path
import signal
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.environ.get("STAGE_TEST_PACKAGE_ROOT", str(Path(__file__).resolve().parents[1] / "flow")))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from hardcaml_asic_flow import cli, checkpoint, execution_plan, flow_observation
import test_stages


class InspectorPresentationTest(unittest.TestCase):
    def setUp(self):
        self.fixture = test_stages.StagesTest()
        self.fixture.setUp()
        self.writer = flow_observation.Writer(self.fixture.root / "observations",
            workspace=self.fixture.root / "workspace", checkpoint_store=self.fixture.store,
            request={"endpoint": "placement"})

    def tearDown(self):
        self.writer.close()
        self.fixture.tearDown()

    def invoke(self, *args):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            status = cli.main(list(args))
        return status, stdout.getvalue(), stderr.getvalue()

    def run_plan(self, **kwargs):
        return self.writer.run(lambda: execution_plan.resolve_stages("placement"),
                               lambda: self.fixture.adapter(**kwargs))

    def test_observation_json_all_flag_positions_complete_unchanged_payload(self):
        self.run_plan()
        path = str(self.writer.directory)
        expected = flow_observation.inspect(path)
        before = {p.name: p.read_bytes() for p in self.writer.directory.iterdir()}
        for args in (("--json", "observation", "inspect", path),
                     ("observation", "--json", "inspect", path),
                     ("observation", "inspect", "--json", path),
                     ("observation", "inspect", path, "--json"),
                     ("--json", "observation", "--json", "inspect", path, "--json")):
            with self.subTest(args=args):
                status, stdout, stderr = self.invoke(*args)
                self.assertEqual(status, 0)
                self.assertEqual(json.loads(stdout), expected)
                self.assertEqual(stderr, "")
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.writer.directory.iterdir()})

    def test_completed_placement_is_not_physical_or_acceptance(self):
        self.run_plan()
        status, stdout, stderr = self.invoke("observation", "inspect", str(self.writer.directory))
        self.assertEqual((status, stderr), (0, ""))
        for phrase in ("requested endpoint     placement", "completed (recorded outcome)",
                       "full physical flow     not_recorded", "acceptance             not_evaluated",
                       "implementation.placement", " s", "cursor", "identity", "historical publication"):
            self.assertIn(phrase, stdout)
        self.assertNotIn('"schema_version"', stdout)

    def test_explicit_plan_signoff_completion_still_not_acceptance(self):
        self.writer.run(lambda: execution_plan.resolve_sequence(execution_plan.STAGE_ORDER),
                        lambda: self.fixture.adapter())
        stdout = self.invoke("observation", "inspect", str(self.writer.directory))[1]
        self.assertIn("requested endpoint     signoff", stdout)
        self.assertIn("synthesis -> floorplan -> placement -> cts -> routing -> signoff", stdout)
        self.assertIn("full physical flow     completed", stdout)
        self.assertIn("acceptance             not_evaluated", stdout)

    def test_running_stage_is_not_a_finished_zero_duration(self):
        self.writer.append("planned", {"plan": execution_plan.resolve_stages("placement").as_dict()})
        self.writer.append("prepared", {"runtime_record": None})
        occurrence = dict(self.writer.state["occurrences"][0], status="running")
        self.writer.append("started", {"occurrence": occurrence, "artifact": None})
        stdout = self.invoke("observation", "inspect", str(self.writer.directory))[1]
        self.assertIn("running      n/a (no finished duration)", stdout)
        self.assertIn("runtime reference      not recorded", stdout)
        self.assertNotIn("0.000 s", stdout)

    def test_live_lost_and_unknown_writer_empty_prefix_honest(self):
        path = str(self.writer.directory)
        status, stdout, _ = self.invoke("observation", "inspect", path)
        self.assertEqual(status, 0)
        for phrase in ("nonterminal prefix", "none recorded", "writer active          yes", "observation status     live"):
            self.assertIn(phrase, stdout)
        self.writer.close()
        self.assertIn("writer_lost_or_unknown", self.invoke("observation", "inspect", path)[1])
        with patch.object(flow_observation, "writer_active", return_value=None):
            self.assertIn("writer active          unknown", self.invoke("observation", "inspect", path)[1])

    def test_failure_and_unreached_stages_do_not_invent_durations(self):
        self.run_plan(code=2)
        status, stdout, _ = self.invoke("observation", "inspect", str(self.writer.directory))
        self.assertEqual(status, 0)  # inspection succeeded, execution failed
        for phrase in ("outcome                failed", "execution exit         2", "unreached", "n/a (no finished duration)", "not established"):
            self.assertIn(phrase, stdout)

    def test_interrupted_prefix_with_publication_remains_incomplete(self):
        original = self.writer.lifecycle
        def interrupt(event, *args):
            original(event, *args)
            if event == "published":
                raise KeyboardInterrupt()
        self.writer.lifecycle = interrupt
        self.assertEqual(self.run_plan().status, "interrupted")
        stdout = self.invoke("observation", "inspect", str(self.writer.directory))[1]
        self.assertIn("outcome                interrupted", stdout)
        self.assertIn(f"execution exit         {128 + signal.SIGINT}", stdout)
        self.assertIn("historical publication", stdout)
        self.assertIn("not established", stdout)

    def test_checkpoint_json_positions_and_human_validation_scope(self):
        artifact = self.fixture.publish("placement")
        path = artifact["path"]
        expected = {"validation": "host_only", "runtime_closure_validated": False,
                    "compatibility_source": "recorded", "manifest": checkpoint.validate(path, compatibility=self.fixture.compat)}
        for args in (("--json", "checkpoint-inspect", path),
                     ("checkpoint-inspect", "--json", path),
                     ("checkpoint-inspect", path, "--json")):
            status, stdout, stderr = self.invoke(*args, "--restart-to", "cts")
            self.assertEqual((status, stderr), (0, ""))
            self.assertEqual(json.loads(stdout), expected)
        status, stdout, stderr = self.invoke("checkpoint-inspect", path, "--restart-to", "cts")
        self.assertEqual((status, stderr), (0, ""))
        for phrase in ("passed (host_only)", "runtime validated      no", "supported targets      cts",
                       "requested restart-to   cts", "no execution performed", "external dependencies  3",
                       "not fresh boundary measurements", "unavailable values     1", "reason not recorded", "not_evaluated"):
            self.assertIn(phrase, stdout)
        self.assertNotIn(str(self.fixture.collateral), stdout)
        self.assertNotIn("Infinity", stdout)

    def test_checkpoint_rejected_transition_preserves_json_error_and_exit(self):
        path = self.fixture.publish("placement")["path"]
        status, stdout, stderr = self.invoke("checkpoint-inspect", path, "--restart-to", "signoff", "--json")
        self.assertEqual(status, 2)
        self.assertEqual(set(json.loads(stdout)), {"validation", "error"})
        self.assertIn("untested restart transition", stderr)
        status, stdout, _ = self.invoke("checkpoint-inspect", path, "--restart-to", "signoff")
        self.assertEqual(status, 2)
        self.assertIn("inspection             failed", stdout)
        self.assertNotIn("host validation        passed", stdout)

    def test_corrupt_observation_prefix_remains_an_inspection_error(self):
        (self.writer.directory / "000000000002.json").write_text('{"incomplete":')
        command = ("observation", "inspect", str(self.writer.directory))
        status, stdout, stderr = self.invoke(*command)
        self.assertEqual(status, 2)
        self.assertIn("error code             INVALID_RECORD", stdout)
        self.assertNotIn("requested completion", stdout)
        self.assertTrue(stderr)
        self.assertEqual(json.loads(self.invoke(*command, "--json")[1])["error"]["code"], "INVALID_RECORD")

    def test_missing_inspections_clean_json_and_human_errors(self):
        missing = str(self.fixture.root / "missing")
        for command in (("observation", "inspect", missing), ("checkpoint-inspect", missing)):
            status, stdout, stderr = self.invoke(*command)
            self.assertEqual(status, 2)
            self.assertIn("inspection             failed", stdout)
            self.assertTrue(stderr)
            status, stdout, stderr = self.invoke(*command, "--json")
            self.assertEqual(status, 2)
            self.assertIn("error", json.loads(stdout))
            self.assertTrue(stderr)


if __name__ == "__main__":
    unittest.main()
