"""Contract-4 CLI lifecycle, real signals and failed output; no EDA."""
import contextlib
import io
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
from hardcaml_asic_flow import cli, flow_observation as obs, result_store, stages
import test_stages


def command(root):
    return ["stages", str(root / "bundle"), "--endpoint", "synthesis", "--json",
            "--workspace", str(root / "workspace"), "--checkpoint-store", str(root / "checkpoints"),
            "--support-tools", str(root / "tt"), "--pdk-root", str(root / "pdk"), "--python", sys.executable]


class DefaultJournalTest(unittest.TestCase):
    def setUp(self):
        self.fixture = test_stages.StagesTest()
        self.fixture.setUp()
        self.root = self.fixture.root

    def tearDown(self):
        self.fixture.tearDown()

    def invoke(self, args):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = cli.main(args)
        return code, [json.loads(line) for line in out.getvalue().splitlines()]

    def test_default_override_and_resume_new_stream_complete_outputs(self):
        (self.root / "workspace").mkdir()
        with patch.object(stages, "prepare", return_value=self.fixture.adapter()):
            code, (allocation, result) = self.invoke(command(self.root))
        self.assertEqual(code, 0)
        self.assertEqual(Path(allocation["attempt"]).parent, self.root / "observations")
        path = self.root / "workspace" / ("execution-" + result["attempt_id"] + ".json")
        self.assertEqual(result, json.loads(path.read_text()))
        initial = result["artifacts"][0]["path"]
        args = command(self.root)
        args[args.index("synthesis")] = "floorplan"
        with patch.object(stages, "prepare", return_value=self.fixture.adapter(initial=initial)):
            code, (resumed, execution) = self.invoke([*args, "--checkpoint", initial,
                                                    "--observation-store", str(self.root / "override")])
        self.assertEqual(code, 0)
        self.assertNotEqual(resumed["stream_id"], allocation["stream_id"])
        self.assertEqual(Path(resumed["attempt"]).parent, self.root / "override")
        self.assertEqual(execution["plan"]["initial_boundary"], "synthesis")
        self.assertFalse(obs.inspect(allocation["attempt"])["writer_active"])

    def test_preflight_error_and_invalid_plan_before_workspace(self):
        args = command(self.root)
        args[args.index("--checkpoint-store") + 1] = str(self.root / "workspace/checkpoints")
        with patch.object(stages.phase4, "preflight", return_value={"ready": False, "issues": ["fixture unavailable"]}):
            code, (allocation, terminal) = self.invoke(args)
        self.assertEqual(code, 2)
        self.assertEqual(terminal["observation"], obs.inspect(allocation["attempt"]))
        self.assertEqual(terminal["observation"]["state"]["outcome"]["status"], "failed")
        self.assertIsNone(terminal["execution_file"])
        self.assertFalse((self.root / "workspace").exists())
        report = Path(terminal["observation"]["state"]["preflight_record"])
        self.assertEqual(json.loads(report.read_text())["issues"], ["fixture unavailable"])
        recipe = self.root / "invalid.json"
        recipe.write_text("{}")
        args = command(self.root)
        index = args.index("--endpoint")
        args[index:index + 2] = ["--plan", str(recipe)]
        with patch.object(stages, "prepare") as prepare:
            code, (allocation, terminal) = self.invoke(args)
        prepare.assert_not_called()
        self.assertIsNone(terminal["observation"]["state"]["plan"])

    def test_allocation_storage_failure_and_missing_parent_no_identity(self):
        with patch.object(result_store, "allocate", side_effect=OSError("store unavailable")):
            code, (terminal,) = self.invoke(command(self.root))
        self.assertEqual(code, 2)
        for key in ("attempt", "stream_id", "execution_file", "observation"):
            self.assertIsNone(terminal[key])
        args = command(self.root)
        args[args.index("--workspace") + 1] = str(self.root / "missing" / "workspace")
        code, (terminal,) = self.invoke(args)
        self.assertEqual(code, 2)
        self.assertIsNone(terminal["attempt"])
        # The allocation failure released the workspace lock.
        with contextlib.closing(obs.Writer(self.root / "other", workspace=self.root / "workspace",
                                          checkpoint_store=self.root / "checkpoints", request={})):
            pass

    def test_busy_across_stores_and_mutually_exclusive_escape_hatch(self):
        with contextlib.closing(obs.Writer(self.root / "other", workspace=self.root / "workspace",
                                          checkpoint_store=self.root / "checkpoints", request={})):
            code, (terminal,) = self.invoke(command(self.root))
        self.assertEqual(terminal["error"]["code"], "BUSY")
        self.assertIsNone(terminal["attempt"])
        self.assertFalse((self.root / "observations").exists())
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            cli.main([*command(self.root), "--no-observation", "--observation-store", str(self.root)])
        (self.root / "workspace").mkdir()
        with patch.object(stages, "prepare", return_value=self.fixture.adapter()):
            code, (execution,) = self.invoke([*command(self.root), "--no-observation"])
        self.assertEqual(code, 0)
        self.assertIn("occurrences", execution)
        self.assertFalse((self.root / "observations").exists())

    def test_aggregate_and_journal_storage_failures_truthful(self):
        (self.root / "workspace").mkdir()
        original = result_store.save_json
        for mode in ("aggregate", "journal", "outcome"):
            def save(path, value):
                if ((mode == "aggregate" and Path(path).name.startswith("execution-"))
                        or (mode == "journal" and value.get("event") in ("finished", "outcome"))
                        or (mode == "outcome" and value.get("event") == "outcome")):
                    raise OSError("storage unavailable")
                original(path, value)
            with patch.object(result_store, "save_json", save), patch.object(stages, "prepare", return_value=self.fixture.adapter()):
                code, (allocation, terminal) = self.invoke(command(self.root))
            self.assertEqual(code, 2)
            if mode == "outcome":
                self.assertTrue(Path(terminal["execution_file"]).is_file())
                self.assertEqual(json.loads(Path(terminal["execution_file"]).read_text())["status"], "completed")
            else:
                self.assertIsNone(terminal["execution_file"])
            state = terminal["observation"]["state"]
            self.assertEqual(len(state["artifacts"]), 1)
            if mode == "aggregate":
                self.assertEqual(state["outcome"]["status"], "failed")
                self.assertEqual(state["occurrences"][0]["status"], "completed")
            else:
                self.assertIsNone(state["outcome"])
                self.assertEqual(state["occurrences"][0]["status"], "completed" if mode == "outcome" else "running")
                self.assertIsNotNone(terminal["recording_error"])

    def signal_case(self, mode, signum):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            child = subprocess.Popen([sys.executable, "-B", __file__, "--worker", temporary, mode],
                env=dict(os.environ, STAGE_TEST_PACKAGE_ROOT=PACKAGE_ROOT), stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True)
            try:
                deadline = time.monotonic() + 10
                while not (root / "ready").exists():
                    if time.monotonic() > deadline or child.poll() is not None:
                        self.fail("worker did not reach signal boundary")
                    time.sleep(.01)
                child.send_signal(signum)
                stdout, stderr = child.communicate(timeout=10)
                self.assertEqual(child.returncode, 128 + signum, stderr)
                terminal = json.loads(stdout.splitlines()[-1])
                self.assertEqual(terminal["status"], "interrupted")
                self.assertEqual(terminal["exit_code"], 128 + signum)
                self.assertIsNone(terminal["execution_file"])
                if mode == "allocation":
                    self.assertIsNone(terminal["attempt"])
                else:
                    self.assertFalse(terminal["observation"]["writer_active"])
                    self.assertEqual(terminal["observation"], obs.inspect(terminal["attempt"]))
                    self.assertEqual(terminal["observation"]["state"]["outcome"]["status"], "interrupted")
                    if mode == "prepare":
                        self.assertEqual(len(stdout.splitlines()), 2)
                        report = terminal["observation"]["state"]["preflight_record"]
                        self.assertEqual(json.loads(Path(report).read_text())["diagnostic"]["status"], "interrupted")
            finally:
                if child.poll() is None:
                    child.kill()
                    child.communicate()

    def test_real_sigterm_preparation_and_receipt_and_allocation(self):
        for mode in ("prepare", "receipt", "allocation"):
            self.signal_case(mode, signal.SIGTERM)

    def test_real_sigint_preparation(self):
        self.signal_case("prepare", signal.SIGINT)

    def test_terminal_flush_and_signal_handler_restoration(self):
        previous = {s: signal.getsignal(s) for s in (signal.SIGINT, signal.SIGTERM)}
        with patch.object(stages, "prepare", side_effect=RuntimeError("rejected")), patch("builtins.print") as output:
            self.assertEqual(cli.main(command(self.root)), 2)
        machine = [call for call in output.call_args_list if call.args and str(call.args[0]).startswith('{')]
        self.assertEqual(len(machine), 2)
        self.assertTrue(all(call.kwargs.get("flush") for call in machine))
        self.assertEqual(previous, {s: signal.getsignal(s) for s in previous})

    def test_broken_terminal_stdout_retains_recorded_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            child = subprocess.Popen([sys.executable, "-B", __file__, "--worker", temporary, "broken-terminal"],
                env=dict(os.environ, STAGE_TEST_PACKAGE_ROOT=PACKAGE_ROOT), stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True)
            try:
                allocation = json.loads(child.stdout.readline())
                child.stdout.close()
                (root / "proceed").touch()
                child.wait(timeout=10)
                self.assertEqual(child.returncode, 2)
                state = obs.inspect(allocation["attempt"])
                self.assertFalse(state["writer_active"])
                self.assertEqual(state["state"]["outcome"]["error"], "terminal fixture failure")
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait()
                child.stderr.close()

    def test_broken_allocation_stdout_releases_locks_without_preparing(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            read, write = os.pipe()
            os.close(read)
            try:
                child = subprocess.run([sys.executable, "-B", __file__, "--worker", temporary, "broken"],
                    env=dict(os.environ, STAGE_TEST_PACKAGE_ROOT=PACKAGE_ROOT), stdout=write,
                    stderr=subprocess.PIPE, text=True, timeout=10)
            finally:
                os.close(write)
            self.assertEqual(child.returncode, 2, child.stderr)
            attempt, = (root / "observations").iterdir()
            state = obs.inspect(attempt)
            self.assertFalse(state["writer_active"])
            self.assertEqual(state["state"]["outcome"]["status"], "failed")
            self.assertIsNone(state["state"]["plan"])
            self.assertFalse((root / "prepared").exists())
            with contextlib.closing(obs.Writer(root / "other", workspace=root / "workspace",
                                              checkpoint_store=root / "checkpoints", request={})):
                pass


def worker(root, mode):
    root = Path(root)
    def pause():
        (root / "ready").touch()
        time.sleep(60)
    def prepare(**kwargs):
        (root / "prepared").touch()
        if mode == "broken-terminal":
            while not (root / "proceed").exists():
                time.sleep(.01)
            raise ValueError("terminal fixture failure")
        checked = result_store.durable_preflight(root / "bundle", kwargs["preflight_output"], pause)
        if checked.status == "interrupted":
            raise result_store.FlowInterrupted(checked.exit_code - 128)
        raise AssertionError("unexpected preparation completion")
    original_print = print
    def output(*args, **kwargs):
        if mode == "receipt" and args and "observation_allocated" in str(args[0]):
            pause()
        original_print(*args, **kwargs)
    with patch.object(stages, "prepare", prepare), patch("builtins.print", output):
        if mode == "allocation":
            with patch.object(result_store, "allocate", side_effect=lambda _: pause()):
                return cli.main(command(root))
        return cli.main(command(root))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--worker":
        sys.exit(worker(sys.argv[2], sys.argv[3]))
    unittest.main()
