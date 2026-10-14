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
import shutil
from unittest.mock import patch

PACKAGE_ROOT = os.environ.get("STAGE_TEST_PACKAGE_ROOT", str(Path(__file__).resolve().parents[1] / "flow"))
sys.path.insert(0, PACKAGE_ROOT)
sys.path.insert(0, str(Path(__file__).resolve().parent))
from hardcaml_asic_flow import flow_observation as obs, execution_plan, cli, presentation, ocaml_backend
import test_stages

NATIVE_ENTRY = '''import os, sys
from pathlib import Path
denied = os.environ.get("WATCH_DENY_CHECKOUT")
def audit(event, args):
    if event == "import" and args[0] == "hardcaml_asic_flow.flow_observation":
        raise RuntimeError("Python observation reader is forbidden on public watch")
    if denied and event == "open" and isinstance(args[0], (str, bytes, os.PathLike)):
        if Path(os.fsdecode(args[0])).resolve().is_relative_to(Path(denied)):
            raise RuntimeError("checkout read denied")
sys.addaudithook(audit)
sys.path.insert(0, sys.argv.pop(1))
from hardcaml_asic_flow.cli import main
sys.exit(main())
'''


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
        code = NATIVE_ENTRY
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
            code = NATIVE_ENTRY
            result = subprocess.run([sys.executable, "-I", "-B", "-c", code, PACKAGE_ROOT,
                                     "observation", "watch", str(self.writer.directory), *flags], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(json.loads(result.stdout)["error"]["code"], "RESET_REQUIRED")

    def test_interval_validation(self):
        for value in ("0", "-1", "nan", "inf", "1e999", "bad"):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                cli.build_parser().parse_args(["observation", "watch", str(self.writer.directory), "--interval", value])
            self.assertEqual(error.exception.code, 2)
        # A missing development helper fails without consulting PATH or falling
        # back to the installed Python incremental reader.
        with patch.object(ocaml_backend, "PACKAGE", self.root / "provider/flow/hardcaml_asic_flow"), \
                contextlib.redirect_stdout(io.StringIO()) as stdout, \
                contextlib.redirect_stderr(io.StringIO()) as stderr:
            self.assertEqual(cli.main(["observation", "watch", str(self.writer.directory), "--json"]), 2)
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("OCaml backend is missing", stderr.getvalue())
        self.assertIn("dune build -j20 @install", stderr.getvalue())

    def test_native_cold_replay_human_parity_and_no_mutation(self):
        self.finish()
        before = {p.name: p.read_bytes() for p in self.writer.directory.iterdir()}
        reader = obs.IncrementalReader(self.writer.directory)
        updates, status = reader.poll()
        expected = []
        presentation.observation_updates(updates, path=self.writer.directory, output=expected.append, elide=False)
        presentation.observation_status(status, output=expected.append)
        child = self.watch()
        stdout, stderr = child.communicate(timeout=5)
        self.assertEqual(child.returncode, 0, stderr)
        self.assertEqual(stdout, "\n".join(expected) + "\n")
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.writer.directory.iterdir()})
        # Direct helper invocation proves the foreground implementation is native.
        result = subprocess.run([str(ocaml_backend.binary("observation_read")), "watch",
                                 str(self.writer.directory), "--json", "--stream-id",
                                 self.writer.stream_id, "--after", "2"],
                                env={"PATH": "/unusable", "PYTHONPATH": "/unusable"},
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["event"], "status")

    def test_native_cursor_and_live_prefix_mutation(self):
        for flags in (("--stream-id", self.writer.stream_id), ("--after", "0"),
                      ("--stream-id", "foreign", "--after", "0"),
                      ("--stream-id", self.writer.stream_id, "--after", "-1"),
                      ("--stream-id", self.writer.stream_id, "--after", "2"),
                      ("--stream-id", self.writer.stream_id, "--after", "99999999999999999999999")):
            result = subprocess.run([str(ocaml_backend.binary("observation_read")), "watch",
                                     str(self.writer.directory), "--json", *flags],
                                    capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertEqual(json.loads(result.stdout)["error"]["code"], "RESET_REQUIRED")
        path = self.writer.directory / "000000000001.json"
        original = path.read_bytes()
        for mode in ("changed", "replaced", "deleted"):
            path.write_bytes(original)
            child = self.watch("--json")
            self.assertEqual(self.line(child)["event"], "updates")
            if mode == "deleted":
                path.unlink()
            elif mode == "replaced":
                replacement = path.with_name(".replacement")
                replacement.write_bytes(original)
                replacement.replace(path)
            else:
                path.write_bytes(original + b" ")
            stdout, stderr = child.communicate(timeout=5)
            self.assertEqual(child.returncode, 2, stderr)
            self.assertEqual(json.loads(stdout.splitlines()[-1])["error"]["code"], "INVALID_RECORD")
        path.write_bytes(original)

    def test_native_lock_release_terminal_race(self):
        # Pause the real flock probe after Reader.refresh, then commit the terminal
        # record and release the actual writer. No production test hooks are used.
        compiler = shutil.which("cc")
        self.assertIsNotNone(compiler, "C compiler required for deterministic syscall race")
        source = self.root / "gate.c"
        source.write_text(r'''#define _GNU_SOURCE
#include <dlfcn.h>
#include <sys/file.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
int flock(int fd, int op) {
  static int once = 0;
  int (*real_flock)(int,int) = dlsym(RTLD_NEXT, "flock");
  if (!once && (op & LOCK_NB)) {
    once = 1;
    int gate = open(getenv("WATCH_PROBE_READY"), O_CREAT|O_WRONLY, 0600);
    close(gate);
    while (access(getenv("WATCH_PROBE_GO"), F_OK)) usleep(1000);
  }
  return real_flock(fd, op);
}
''')
        library = self.root / "gate.so"
        subprocess.run([compiler, "-shared", "-fPIC", str(source), "-o", str(library), "-ldl"], check=True)
        ready, go = self.root / "ready", self.root / "go"
        child = subprocess.Popen([str(ocaml_backend.binary("observation_read")), "watch",
                                  str(self.writer.directory), "--json"],
                                 env={**os.environ, "LD_PRELOAD": str(library),
                                      "WATCH_PROBE_READY": str(ready), "WATCH_PROBE_GO": str(go)},
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.children.append(child)
        deadline = time.monotonic() + 5
        while not ready.exists():
            self.assertIsNone(child.poll())
            self.assertLess(time.monotonic(), deadline)
            time.sleep(.005)
        self.finish()
        go.touch()
        stdout, stderr = child.communicate(timeout=5)
        self.assertEqual(child.returncode, 0, stderr)
        lines = [json.loads(s) for s in stdout.splitlines()]
        self.assertEqual([e["event"] for e in lines[0]["events"]], ["allocated", "outcome"])
        self.assertEqual(lines[1]["observation_status"], "final")

    def test_native_idle_does_not_reopen_records(self):
        tracer = shutil.which("strace")
        self.assertIsNotNone(tracer, "strace required to verify native idle IO")
        trace = self.root / "watch.trace"
        child = subprocess.Popen([tracer, "-f", "-e", "trace=openat", "-o", str(trace),
                                  str(ocaml_backend.binary("observation_read")), "watch",
                                  str(self.writer.directory), "--json", "--interval", ".01"],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.children.append(child)
        self.assertEqual(self.line(child)["event"], "updates")
        time.sleep(.15)
        self.finish()
        stdout, stderr = child.communicate(timeout=5)
        self.assertEqual(child.returncode, 0, stderr)
        opens = trace.read_text().splitlines()
        for sequence in (1, 2):
            name = f"{sequence:012}.json"
            self.assertEqual(sum(name in line for line in opens), 1, name)

    def test_live_ocaml_writer_detach_reconnect_and_terminal(self):
        driver = Path(os.environ.get("WATCH_NATIVE_WRITER",
                      str(Path(__file__).resolve().parent / "observation_writer_consumer.exe")))
        if not driver.is_file():
            driver = Path(__file__).resolve().parents[1] / "_build/default/test/observation_writer_consumer.exe"
        producer = subprocess.Popen([str(driver), str(self.root / "native-observations"),
                                     str(self.root / "native-work")], stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.children.append(producer)
        receipt = self.line(producer)
        attempt = Path(receipt["attempt"])
        first = self.watch("--json", attempt=attempt)
        updates = self.line(first)
        self.assertEqual(updates["events"][0]["event"], "allocated")
        first.send_signal(signal.SIGINT)
        _, stderr = first.communicate(timeout=5)
        self.assertEqual(first.returncode, 130, stderr)
        self.assertIsNone(producer.poll(), "reader detach killed native producer")
        watcher = subprocess.Popen([sys.executable, "-I", "-B", "-c", NATIVE_ENTRY, PACKAGE_ROOT,
                                    "observation", "watch", str(attempt), "--json", "--interval", ".01",
                                    "--stream-id", updates["stream_id"], "--after", "1"],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.children.append(watcher)
        self.assertEqual(self.line(watcher)["event"], "status")
        producer.stdin.write(json.dumps({"event": "outcome", "data": {
            "status": "failed", "exit_code": 9, "error": "native fixture finished"}}) + "\n")
        producer.stdin.flush()
        self.assertTrue(select.select([producer.stdout], [], [], 5)[0])
        self.assertEqual(producer.stdout.readline().strip(), "ok")
        stdout, stderr = watcher.communicate(timeout=5)
        self.assertEqual(watcher.returncode, 0, stderr)
        lines = [json.loads(s) for s in stdout.splitlines()]
        self.assertEqual([e["event"] for e in lines[0]["events"]], ["outcome"])
        self.assertEqual(lines[-1]["outcome"]["exit_code"], 9)
        # Outcome, not writer shutdown, is the established stop condition.
        self.assertIsNone(producer.poll())
        producer.communicate("close\n", timeout=5)
        self.assertEqual(producer.returncode, 0)

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
                self.assertIn(f"recorded {event['recorded_at']}", stdout)
        finally:
            fixture.tearDown()

    def test_live_spaced_stage_events_delivered_before_terminal(self):
        # Each real producer append is atomically published, then blocks for a
        # reader-owned acknowledgement. A generous timeout bounds hangs, not latency.
        code = '''import sys, time
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, sys.argv[2])
from hardcaml_asic_flow import flow_observation as obs, execution_plan
import test_stages
fixture = test_stages.StagesTest()
fixture.setUp()
class GatedWriter(obs.Writer):
    def append(self, event, data):
        super().append(event, data)
        if event != "allocated":
            if sys.stdin.readline() != "next\\n": raise RuntimeError("lost test reader")
            time.sleep(.02)
w = GatedWriter(fixture.root / "obs", workspace=fixture.root / "work",
                checkpoint_store=fixture.store, request={})
adapter = fixture.adapter()
launch = adapter.launch
def marked_launch(*args):
    (fixture.root / "launched").touch()
    return launch(*args)
adapter.launch = marked_launch
print(w.directory, flush=True)
sys.stdin.readline()
w.run(lambda: execution_plan.resolve_stages("synthesis"), lambda: adapter)
w.close()
fixture.tearDown()
'''
        producer = subprocess.Popen([sys.executable, "-I", "-B", "-c", code, PACKAGE_ROOT,
                                     str(Path(__file__).resolve().parent)], stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.children.append(producer)
        self.assertTrue(select.select([producer.stdout], [], [], 10)[0])
        attempt = Path(producer.stdout.readline().strip())
        entry = NATIVE_ENTRY
        watcher = subprocess.Popen([sys.executable, "-I", "-B", "-c", entry, PACKAGE_ROOT,
                                    "observation", "watch", str(attempt), "--json", "--interval", ".01"],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.children.append(watcher)
        pending = b""
        def delivery():
            nonlocal pending
            while b"\n" not in pending:
                self.assertTrue(select.select([watcher.stdout], [], [], 10)[0], "watch delivery timed out")
                chunk = os.read(watcher.stdout.fileno(), 65536)
                self.assertTrue(chunk, "watch ended before requested event")
                pending += chunk
            line, pending = pending.split(b"\n", 1)
            return json.loads(line)
        received = []
        receipts = []  # Independent reader measurements, never persisted as facts.
        for expected in ("allocated", "planned", "prepared", "started", "published", "finished", "outcome"):
            while True:
                payload = delivery()
                if payload["event"] == "updates":
                    break
            self.assertEqual([e["event"] for e in payload["events"]], [expected])
            event = payload["events"][0]
            received.append(event)
            receipts.append(time.monotonic())
            self.assertEqual(payload["schema_version"], 2)
            self.assertIsNone(producer.poll(), "producer completed before intermediate delivery")
            if expected != "outcome":
                self.assertIsNone(obs.inspect(attempt)["state"]["outcome"])
            if expected == "started":
                self.assertFalse((attempt.parent.parent / "launched").exists(),
                                 "start was delivered only after the stage operation")
            if expected == "published":
                self.assertTrue((attempt.parent.parent / "launched").exists())
                checkpoint = Path(event["data"]["artifact"]["path"])
                manifest = test_stages.cp.read(checkpoint / "manifest.json")
                test_stages.cp.validate(checkpoint, compatibility=manifest["compatibility"])
            producer.stdin.write("next\n")
            producer.stdin.flush()
        final = delivery()
        self.assertEqual(final["event"], "status")
        self.assertEqual(final["outcome"]["status"], "completed")
        watcher.communicate(timeout=10)
        self.assertEqual(watcher.returncode, 0)
        _, stderr = producer.communicate(timeout=10)
        self.assertEqual(producer.returncode, 0, stderr)
        elapsed = [e["elapsed_seconds"] for e in received]
        self.assertEqual(elapsed, sorted(elapsed))
        self.assertEqual(receipts, sorted(receipts))

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
        code = NATIVE_ENTRY
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
        code = NATIVE_ENTRY
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
