"""Persistent lifecycle/reconnect evidence, including real local process signals."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

PACKAGE_ROOT = os.environ.get("STAGE_TEST_PACKAGE_ROOT", str(Path(__file__).resolve().parents[1] / "flow"))
sys.path.insert(0, PACKAGE_ROOT)
sys.path.insert(0, str(Path(__file__).resolve().parent))
from hardcaml_asic_flow import flow_observation as obs, execution_plan as plans, stages, result_store
import test_stages


class ObservationTest(unittest.TestCase):
    def setUp(self):
        self.fixture = test_stages.StagesTest()
        self.fixture.setUp()
        self.root = self.fixture.root
        self.writer = obs.Writer(self.root / "observations", workspace=self.root / "workspace",
                                 checkpoint_store=self.fixture.store, request={"fixture": True})

    def tearDown(self):
        self.writer.close()
        self.fixture.tearDown()

    def run_plan(self, endpoint="floorplan", **kwargs):
        return self.writer.run(lambda: plans.resolve_stages(endpoint), lambda: self.fixture.adapter(**kwargs))

    def test_publication_precedes_finished_and_replay_reconnect(self):
        result = self.run_plan()
        state, events = obs.load(self.writer.directory)
        self.assertEqual([e["event"] for e in events], ["allocated", "planned", "prepared"] + ["started", "published", "finished"] * 2 + ["outcome"])
        for event in events:
            if event["event"] == "published":
                self.assertEqual(event["data"]["occurrence"]["status"], "running")
                artifact = event["data"]["artifact"]
                test_stages.cp.validate(artifact["path"], compatibility=self.fixture.compat)
        for cursor in range(len(events) + 1):
            updates = obs.read_updates(self.writer.directory, stream_id=result.attempt_id, after=cursor)
            self.assertEqual(updates["events"], events[cursor:])
        self.assertEqual(state["artifacts"], result.artifacts)
        before = {p.name: p.read_bytes() for p in self.writer.directory.iterdir()}
        observation = obs.inspect(self.writer.directory)
        self.assertEqual(observation["final_results"]["acceptance"], "not_evaluated")
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.writer.directory.iterdir()})

    def test_six_stage_physical_completion_does_not_mean_acceptance(self):
        self.run_plan("signoff")
        final = obs.inspect(self.writer.directory)["final_results"]
        self.assertEqual(final["physical_completion"], "completed")
        self.assertEqual(len(final["checkpoint_refs"]), 6)
        self.assertEqual(final["external_postcheck"], "not_evaluated")

    def test_process_failure_and_publication_failure_preserve_unreached(self):
        result = self.run_plan(missing=True)
        self.assertEqual(result.exit_code, 2)
        state = obs.inspect(self.writer.directory)["state"]
        self.assertEqual([o["status"] for o in state["occurrences"]], ["failed", "unreached"])
        self.assertEqual(state["artifacts"], [])

    def test_preflight_failure_preserves_report_before_workspace_exists(self):
        def prepare():
            return stages.prepare(bundle=self.root / "bundle", support_tools=self.root / "tt", pdk_root=self.root / "pdk",
                                  python=sys.executable, workspace=self.root / "workspace", checkpoint_store=self.root / "workspace/checkpoints",
                                  preflight_output=self.writer.directory / "preflight.json")
        with patch.object(stages.phase4, "preflight", return_value={"ready": False, "issues": ["fixture unavailable"]}):
            with self.assertRaises(ValueError):
                self.writer.run(lambda: plans.resolve_stages("floorplan"), prepare)
        state = obs.inspect(self.writer.directory)["state"]
        self.assertEqual(state["outcome"]["status"], "failed")
        self.assertEqual([o["status"] for o in state["occurrences"]], ["unreached", "unreached"])
        self.assertEqual(json.loads(Path(state["preflight_record"]).read_text())["issues"], ["fixture unavailable"])
        self.assertFalse((self.root / "workspace").exists())

    def test_invalid_plan_and_adapter_validation_are_final_failures(self):
        with self.assertRaises(ValueError):
            self.writer.run(lambda: plans.resolve_stages("unknown"), lambda: None)
        self.assertIsNone(obs.inspect(self.writer.directory)["state"]["plan"])
        self.assertEqual(obs.inspect(self.writer.directory)["state"]["outcome"]["status"], "failed")

    def test_workspace_conflict_across_different_stores(self):
        with self.assertRaises(obs.ObservationError) as caught:
            obs.Writer(self.root / "other", workspace=self.root / "workspace", checkpoint_store=self.fixture.store, request={})
        self.assertEqual(caught.exception.code, "BUSY")
        self.assertFalse((self.root / "other").exists())

    def test_temporary_tail_ignored_promoted_corruption_and_gaps_rejected(self):
        (self.writer.directory / ".000000000002.json.incomplete").write_text('{"status":"completed"')
        self.assertEqual(obs.inspect(self.writer.directory)["cursor"], 1)
        bad = self.writer.directory / "000000000002.json"
        for raw in ('{"status":"completed"', '{"x":1,"x":2}', '{"x":NaN}'):
            bad.write_text(raw)
            with self.assertRaises(obs.ObservationError):
                obs.inspect(self.writer.directory)
        bad.unlink()
        (self.writer.directory / "000000000003.json").write_text("{}")
        with self.assertRaises(obs.ObservationError):
            obs.inspect(self.writer.directory)

    def test_cursor_and_hash_chain_reject_bad_records(self):
        self.run_plan()
        for stream, cursor in (("other", 0), (self.writer.stream_id, -1), (self.writer.stream_id, 100), (self.writer.stream_id, True)):
            with self.assertRaises(obs.ObservationError) as caught:
                obs.read_updates(self.writer.directory, stream_id=stream, after=cursor)
            self.assertEqual(caught.exception.code, "RESET_REQUIRED")
        path = self.writer.directory / "000000000004.json"
        value = json.loads(path.read_text())
        value["data"]["occurrence"]["status"] = "completed"
        path.write_text(json.dumps(value))
        with self.assertRaises(obs.ObservationError):
            obs.inspect(self.writer.directory)

    def test_transition_validation_rejects_rehashed_unearned_success(self):
        state = self.writer.state
        with self.assertRaises(obs.ObservationError):
            obs.reduce_event(state, "outcome", {"status": "completed", "exit_code": 0, "error": None}, self.writer.stream_id)

    def test_final_record_publication_failure_is_not_success(self):
        with self.assertRaises(OSError):
            self.writer.run(lambda: plans.resolve_stages("synthesis"), lambda: self.fixture.adapter(),
                            finalize=lambda _: (_ for _ in ()).throw(OSError("execution record unavailable")))
        state = obs.inspect(self.writer.directory)["state"]
        self.assertEqual(state["occurrences"][0]["status"], "completed")
        self.assertEqual(state["outcome"]["status"], "failed")

    def subprocess_case(self, mode, signum):
        with tempfile.TemporaryDirectory() as root:
            env = dict(os.environ, STAGE_TEST_PACKAGE_ROOT=PACKAGE_ROOT, PYTHONDONTWRITEBYTECODE="1")
            child = subprocess.Popen([sys.executable, "-B", __file__, "--worker", root, mode], env=env,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                attempt = Path(child.stdout.readline().strip())
                target = "published" if mode == "publication" else "started" if mode == "stage" else "planned"
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    state, events = obs.load(attempt)
                    if events[-1]["event"] == target and (mode != "preflight" or Path(state["preflight_record"]).exists()):
                        break
                    time.sleep(.02)
                else:
                    self.fail("child did not reach requested lifecycle boundary")
                prefix = len(events)
                stream = state["attempt_id"]
                # Reader disconnect/reattach occurs through an independent process.
                command = [sys.executable, "-B", "-m", "hardcaml_asic_flow", "observation", "inspect", str(attempt), "--json"]
                read_env = dict(env, PYTHONPATH=PACKAGE_ROOT)
                live = subprocess.run(command, env=read_env, text=True, capture_output=True, check=True)
                self.assertTrue(json.loads(live.stdout)["writer_active"])
                with self.assertRaises(obs.ObservationError) as conflict:
                    obs.Writer(Path(root) / "other-store", workspace=Path(root) / "workspace",
                               checkpoint_store=Path(root) / "checkpoints", request={})
                self.assertEqual(conflict.exception.code, "BUSY")
                child.send_signal(signum)
                child.communicate(timeout=10)
                reattached = json.loads(subprocess.run(command, env=read_env, text=True, capture_output=True, check=True).stdout)
                self.assertFalse(reattached["writer_active"])
                final = reattached["state"]
                if signum == signal.SIGKILL:
                    self.assertIsNone(final["outcome"])
                    self.assertEqual(reattached["observation_status"], "writer_lost_or_unknown")
                    self.assertEqual(final["occurrences"][0]["status"], "running")
                    self.assertEqual(len(final["artifacts"]), 1 if mode == "publication" else 0)
                else:
                    self.assertEqual(final["outcome"]["status"], "interrupted")
                    self.assertEqual(final["outcome"]["exit_code"], 128 + signum)
                    self.assertEqual(final["occurrences"][0]["status"], "unreached" if mode == "preflight" else "interrupted")
                    if mode == "preflight":
                        self.assertEqual(json.loads(Path(final["preflight_record"]).read_text())["diagnostic"]["status"], "interrupted")
                updates = obs.read_updates(attempt, stream_id=stream, after=prefix)
                self.assertEqual(updates["cursor"], reattached["cursor"])
                self.assertEqual(reattached["final_results"]["acceptance"], "not_evaluated")
            finally:
                if child.poll() is None:
                    child.kill()
                    child.communicate()
                for path in Path(root).rglob("*"):
                    path.chmod(0o755 if path.is_dir() else 0o644)

    def test_real_sigterm_stage_and_restart_reader(self):
        self.subprocess_case("stage", signal.SIGTERM)

    def test_real_sigterm_long_preparation_preserved(self):
        self.subprocess_case("preflight", signal.SIGTERM)

    def test_real_sigkill_after_publication_never_completes_stage(self):
        self.subprocess_case("publication", signal.SIGKILL)

    def test_real_sigterm_after_publication_retains_artifact_and_interruption(self):
        self.subprocess_case("publication", signal.SIGTERM)

    def test_atomic_write_failure_leaves_only_committed_prefix(self):
        original = result_store.save_json
        def save(path, value):
            if value.get("event") in ("finished", "outcome"):
                raise OSError("journal publication unavailable")
            original(path, value)
        with patch.object(result_store, "save_json", save):
            with self.assertRaises(OSError):
                self.run_plan()
        state, events = obs.load(self.writer.directory)
        self.assertEqual(events[-1]["event"], "published")
        self.assertEqual(state["occurrences"][0]["status"], "running")
        self.assertIsNone(state["outcome"])

    def test_released_writer_cannot_append_and_new_writer_does_not_revive_old(self):
        self.writer.close()
        with self.assertRaises(obs.ObservationError):
            self.writer.append("planned", {"plan": plans.resolve_stages("synthesis").as_dict()})
        other = obs.Writer(self.root / "other", workspace=self.root / "workspace", checkpoint_store=self.fixture.store, request={})
        try:
            self.assertFalse(obs.inspect(self.writer.directory)["writer_active"])
            self.assertTrue(obs.inspect(other.directory)["writer_active"])
        finally:
            other.close()


def worker(root, mode):
    fixture = test_stages.StagesTest()
    temporary_directory = tempfile.TemporaryDirectory
    with patch.object(test_stages.tempfile, "TemporaryDirectory", lambda: temporary_directory(dir=root)):
        fixture.setUp()
    writer = obs.Writer(Path(root) / "observations", workspace=Path(root) / "workspace",
                        checkpoint_store=fixture.store, request={"fixture": True})
    print(writer.directory, flush=True)
    def prepare():
        if mode == "preflight":
            checked = result_store.durable_preflight(Path(root) / "bundle", writer.directory / "preflight.json", lambda: time.sleep(60))
            if checked.status == "interrupted":
                raise result_store.FlowInterrupted(checked.exit_code - 128)
            return None
        adapter = fixture.adapter()
        if mode == "stage":
            adapter.launch = lambda *args: time.sleep(60)
        return adapter
    if mode == "publication":
        original = writer.lifecycle
        def lifecycle(event, *args):
            original(event, *args)
            if event == "published":
                time.sleep(60)
        writer.lifecycle = lifecycle
    try:
        writer.run(lambda: plans.resolve_stages("floorplan"), prepare)
    finally:
        writer.close()
        fixture.tearDown()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--worker":
        worker(sys.argv[2], sys.argv[3])
    else:
        unittest.main()
