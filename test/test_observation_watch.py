"""Incremental content work and real foreground reader/producer isolation."""
import json
import contextlib
import io
import os
from pathlib import Path
import select
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
from hardcaml_asic_flow import flow_observation as obs, execution_plan, cli
import test_stages


class WatchTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.writer = obs.Writer(self.root / "obs", workspace=self.root / "work",
                                 checkpoint_store=self.root / "cp", request={})
        self.children = []

    def tearDown(self):
        self.writer.close()
        for child in self.children:
            if child.poll() is None:
                child.kill()
            child.communicate()
        self.temp.cleanup()

    def watch(self, *flags, attempt=None):
        # Isolated installed tests use exactly the same installed package root.
        code = "import sys; sys.path.insert(0, sys.argv.pop(1)); from hardcaml_asic_flow.cli import main; sys.exit(main())"
        child = subprocess.Popen([sys.executable, "-I", "-B", "-c", code, PACKAGE_ROOT,
                                  *flags, "observation", "watch", str(attempt or self.writer.directory),
                                  "--interval", "0.01"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.children.append(child)
        return child

    def line(self, child):
        self.assertTrue(select.select([child.stdout], [], [], 5)[0], "reader did not flush")
        return json.loads(child.stdout.readline())

    def finish(self):
        self.writer.append("outcome", {"status": "failed", "exit_code": 7, "error": "fixture failure"})
        self.writer.close()

    def test_idle_never_reparses_and_new_content_matches_stateless(self):
        with patch.object(obs, "strict_read", wraps=obs.strict_read) as read:
            reader = obs.IncrementalReader(self.writer.directory)
            self.assertEqual(read.call_count, 1)
            updates, status = reader.poll()
            self.assertEqual(updates, obs.read_updates(self.writer.directory, stream_id=self.writer.stream_id, after=0))
            count = read.call_count
            with patch.object(obs, "writer_active", wraps=obs.writer_active) as active:
                for _ in range(10):
                    self.assertEqual(reader.poll()[0]["events"], [])
                self.assertEqual(active.call_count, 10)
            self.assertEqual(read.call_count, count)
            self.finish()
            updates, status = reader.poll()
            self.assertEqual(read.call_count, count + 1)
            self.assertEqual(status["outcome"]["exit_code"], 7)
            self.assertEqual(updates["events"][0]["event"], "outcome")

    def test_changed_deleted_replaced_prefix(self):
        path = self.writer.directory / "000000000001.json"
        original = path.read_bytes()
        for mode in ("changed", "deleted", "replaced"):
            with self.subTest(mode=mode):
                path.write_bytes(original)
                reader = obs.IncrementalReader(self.writer.directory)
                if mode == "changed":
                    path.write_bytes(original + b" ")
                elif mode == "deleted":
                    path.unlink()
                else:
                    replacement = path.with_name(".replacement")
                    replacement.write_bytes(original)
                    os.replace(replacement, path)
                with self.assertRaises(obs.ObservationError):
                    reader.poll()

    def test_temp_truncated_gap_and_corrupt_tail(self):
        directory = self.writer.directory
        reader = obs.IncrementalReader(directory)
        (directory / ".000000000002.json.tmp").write_text("{")
        self.assertEqual(reader.poll()[0]["cursor"], 1)
        for name, raw in (("000000000003.json", "{}"), ("000000000002.json", "{"),
                          ("000000000002.json", '{"x":1,"x":2}'),
                          ("000000000002.json", '{"x":1e999}')):
            with self.subTest(raw=raw, name=name):
                path = directory / name
                path.write_text(raw)
                for call in (reader.poll, lambda: obs.load(directory)):
                    with self.assertRaises(obs.ObservationError):
                        call()
                child = self.watch("--json")
                stdout, stderr = child.communicate(timeout=5)
                self.assertEqual(child.returncode, 2, stderr)
                self.assertEqual(json.loads(stdout)["error"]["code"], "INVALID_RECORD")
                path.unlink()
        self.writer.append("planned", {"plan": execution_plan.resolve_stages("synthesis").as_dict()})
        path = directory / "000000000002.json"
        value = json.loads(path.read_text())
        value["previous_sha256"] = "0" * 64
        value["sha256"] = obs.digest({k: v for k, v in value.items() if k != "sha256"})
        path.write_text(json.dumps(value))
        with self.assertRaises(obs.ObservationError):
            reader.poll()

    def test_release_final_append_race_is_drained(self):
        reader = obs.IncrementalReader(self.writer.directory)
        def release(_):
            self.finish()
            return False
        with patch.object(obs, "writer_active", side_effect=release):
            updates, status = reader.poll()
        self.assertEqual(updates["cursor"], 2)
        self.assertEqual(status["observation_status"], "final")

    def test_cursor_rules(self):
        for kwargs in ({"after": 0}, {"stream_id": self.writer.stream_id},
                       {"stream_id": "wrong", "after": 0},
                       {"stream_id": self.writer.stream_id, "after": -1},
                       {"stream_id": self.writer.stream_id, "after": 2}):
            with self.assertRaises(obs.ObservationError) as error:
                obs.IncrementalReader(self.writer.directory, **kwargs)
            self.assertEqual(error.exception.code, "RESET_REQUIRED")

    def test_json_flag_positions_and_terminal_failed_query_success(self):
        self.finish()
        for flags in (("--json",), ()):  # nested placements below use the public parser directly
            child = self.watch(*flags)
            stdout, stderr = child.communicate(timeout=5)
            self.assertEqual(child.returncode, 0, stderr)
            if flags:
                lines = [json.loads(line) for line in stdout.splitlines()]
                self.assertEqual([v["event"] for v in lines], ["updates", "status"])
                self.assertEqual(len(lines[0]["events"]), 2)
                self.assertEqual(lines[-1]["outcome"]["exit_code"], 7)
            else:
                self.assertIn("execution exit code", stdout)
                self.assertIn("failed", stdout)
        for argv in (("--json", "observation", "watch"), ("observation", "--json", "watch"),
                     ("observation", "watch", "--json")):
            args = cli.build_parser().parse_args([*argv, str(self.writer.directory)])
            self.assertTrue(args.json)

    def test_writer_lost_unknown_and_cursor_cli_errors(self):
        self.writer.close()
        child = self.watch("--json")
        stdout, _ = child.communicate(timeout=5)
        self.assertEqual(child.returncode, 3)
        self.assertEqual(json.loads(stdout.splitlines()[-1])["observation_status"], "writer_lost_or_unknown")
        (self.writer.directory / "writer.lock").unlink()
        self.assertIsNone(obs.IncrementalReader(self.writer.directory).poll()[1]["writer_active"])
        for flags in (("--json", "--after", "0"), ("--json", "--stream-id", "wrong", "--after", "0")):
            # Reconnect flags belong after the watch subcommand.
            code = "import sys; sys.path.insert(0, sys.argv.pop(1)); from hardcaml_asic_flow.cli import main; sys.exit(main())"
            result = subprocess.run([sys.executable, "-I", "-B", "-c", code, PACKAGE_ROOT,
                                     "observation", "watch", str(self.writer.directory), *flags], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(json.loads(result.stdout)["error"]["code"], "RESET_REQUIRED")

    def test_interval_validation(self):
        for value in ("0", "-1", "nan", "inf", "1e999", "bad"):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                cli.build_parser().parse_args(["observation", "watch", str(self.writer.directory), "--interval", value])
            self.assertEqual(error.exception.code, 2)

    def test_human_delivers_all_twenty_two_events(self):
        fixture = test_stages.StagesTest()
        fixture.setUp()
        try:
            self.writer.run(lambda: execution_plan.resolve_stages("signoff"), lambda: fixture.adapter())
            self.writer.close()
            events = obs.load(self.writer.directory)[1]
            self.assertEqual(len(events), 22)
            child = self.watch()
            stdout, stderr = child.communicate(timeout=5)
            self.assertEqual(child.returncode, 0, stderr)
            self.assertNotIn("omitted", stdout)
            for event in events:
                self.assertIn(f"{event['sequence']:>4} {event['event']}", stdout)
        finally:
            fixture.tearDown()

    def test_subprocess_producer_reconnect_sigint_and_broken_pipe(self):
        # Producer blocks on a caller-owned gate; readers cannot signal or release it.
        code = code_producer()
        producer = subprocess.Popen([sys.executable, "-I", "-B", "-c", code, PACKAGE_ROOT, str(self.root)],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.children.append(producer)
        self.assertTrue(select.select([producer.stdout], [], [], 5)[0])
        attempt = Path(producer.stdout.readline().strip())
        first = self.watch("--json", attempt=attempt)
        updates = self.line(first)
        self.assertEqual(updates["cursor"], 1)
        first.send_signal(signal.SIGINT)
        stdout, stderr = first.communicate(timeout=5)
        self.assertEqual(first.returncode, 130, stderr)
        self.assertIsNone(producer.poll())
        broken = self.watch("--json", attempt=attempt)
        broken.stdout.close()
        broken.stdout = None
        broken.wait(timeout=5)
        self.assertEqual(broken.returncode, 2)
        self.assertNotIn("Traceback", broken.stderr.read())
        self.assertIsNone(producer.poll())
        # Non-pipe stdout failures (e.g. ENOSPC) are reader delivery failures too,
        # without a retry onto the failed output or a shutdown-flush exit 120.
        code = "import sys; sys.path.insert(0, sys.argv.pop(1)); from hardcaml_asic_flow.cli import main; sys.exit(main())"
        with open("/dev/full", "w") as full:
            for flags in ([], ["--json"]):
                failed_output = subprocess.run(
                    [sys.executable, "-I", "-B", "-c", code, PACKAGE_ROOT,
                     "observation", "watch", str(attempt), *flags],
                    stdout=full, stderr=subprocess.PIPE, text=True, timeout=5)
                self.assertEqual(failed_output.returncode, 2, failed_output.stderr)
                self.assertNotIn("Traceback", failed_output.stderr)
                self.assertNotIn("Exception ignored", failed_output.stderr)
                self.assertIsNone(producer.poll())
        # Attach at saved cursor through an independent CLI process.
        code = "import sys; sys.path.insert(0, sys.argv.pop(1)); from hardcaml_asic_flow.cli import main; sys.exit(main())"
        reconnect = subprocess.Popen([sys.executable, "-I", "-B", "-c", code, PACKAGE_ROOT,
                                      "observation", "watch", str(attempt), "--json", "--stream-id", updates["stream_id"],
                                      "--after", "1", "--interval", ".01"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.children.append(reconnect)
        status = self.line(reconnect)
        self.assertEqual(status["event"], "status")
        time.sleep(.05)
        self.assertFalse(select.select([reconnect.stdout], [], [], 0)[0], "duplicate idle status")
        (self.root / "go").touch()
        stdout, stderr = reconnect.communicate(timeout=5)
        self.assertEqual(reconnect.returncode, 0, stderr)
        lines = [json.loads(line) for line in stdout.splitlines()]
        self.assertEqual([v["event"] for v in lines], ["updates", "status"])
        self.assertEqual([e["event"] for e in lines[0]["events"]], ["outcome"])
        self.assertEqual(lines[-1]["outcome"]["exit_code"], 9)
        producer.communicate(timeout=5)
        self.assertEqual(producer.returncode, 0)
        # Abrupt producer death while a new foreground reader is live is unresolved,
        # never an invented execution interruption or successful terminal result.
        (self.root / "go").unlink()
        producer = subprocess.Popen([sys.executable, "-I", "-B", "-c", code_producer(), PACKAGE_ROOT, str(self.root)],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.children.append(producer)
        self.assertTrue(select.select([producer.stdout], [], [], 5)[0])
        lost_attempt = Path(producer.stdout.readline().strip())
        lost = self.watch("--json", attempt=lost_attempt)
        self.assertEqual(self.line(lost)["event"], "updates")
        producer.kill()
        producer.wait(timeout=5)
        stdout, stderr = lost.communicate(timeout=5)
        self.assertEqual(lost.returncode, 3, stderr)
        final = json.loads(stdout.splitlines()[-1])
        self.assertEqual(final["observation_status"], "writer_lost_or_unknown")
        self.assertIsNone(final["outcome"])


def code_producer():
    return '''import sys, time
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from hardcaml_asic_flow.flow_observation import Writer
root = Path(sys.argv[2])
w = Writer(root / "producer-obs", workspace=root / "producer-work", checkpoint_store=root / "cp", request={})
print(str(w.directory), flush=True)
while not (root / "go").exists(): time.sleep(.01)
w.append("outcome", {"status":"failed", "exit_code":9, "error":"producer finished"})
w.close()
'''


if __name__ == "__main__":
    unittest.main()
