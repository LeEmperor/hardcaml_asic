"""Real child/group lifecycle checks, repeated against independent installed consumer."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time


def verify(consumer, fixture, root):
    # The test harness, not the library, adopts/reaps orphan fixtures on Linux.
    assert ctypes.CDLL(None).prctl(36, 1, 0, 0, 0) == 0
    serial = 0

    def run(child_mode="preserve", mode="normal", timeout=3, interrupt=None,
            prog=None, preexisting=False):
        nonlocal serial
        serial += 1
        cwd = root / f"case {serial}"
        cwd.mkdir()
        if preexisting:
            (cwd / "stdout.log").write_text("retained")
        argv = [str(consumer), str(cwd), mode, str(timeout),
                prog or sys.executable, "-I", "-B", str(fixture), child_mode,
                "a b", "", "$(touch forbidden)", "quote'\";", "λ"]
        p = subprocess.Popen(argv, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        completed = False
        try:
            if interrupt is not None:
                deadline = time.monotonic() + 5
                while not (cwd / "ready").exists():
                    assert p.poll() is None, p.communicate()
                    assert time.monotonic() < deadline
                    time.sleep(0.01)
                os.kill(p.pid, interrupt)
            out, err = p.communicate(timeout=8)
            assert p.returncode == 0, (out, err)
            lines = out.decode().splitlines()
            assert len(lines) == 6, (out, err)
            assert lines[1] == "1", lines  # cleanup exactly once
            if lines[4] != "none":
                try:
                    os.kill(int(lines[4]), 0)
                except ProcessLookupError:
                    pass
                else:
                    raise AssertionError("leader not reaped")
            if (cwd / "descendant.pid").exists():
                descendant = int((cwd / "descendant.pid").read_text())
                deadline = time.monotonic() + 2
                while True:
                    adopted, status = os.waitpid(descendant, os.WNOHANG)
                    if adopted:
                        assert os.WIFSIGNALED(status) and os.WTERMSIG(status) == signal.SIGKILL
                        break
                    assert time.monotonic() < deadline, "descendant survived"
                    time.sleep(0.01)
            completed = True
            return lines, cwd
        finally:
            if p.poll() is None:
                p.kill()
                p.wait()
            # Failure containment for disposable fixtures.
            for filename in (() if completed else ("descendant.pid", "ready")):
                if (cwd / filename).exists():
                    try:
                        os.kill(int((cwd / filename).read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    r, cwd = run()
    assert r[0] == "exit:0" and r[2:4] == ["true", "false"]
    evidence = json.loads((cwd / "stdout.log").read_text())
    assert evidence["cwd"] == str(cwd)
    assert evidence["argv"] == ["a b", "", "$(touch forbidden)", "quote'\";", "λ"]
    assert evidence["env"]["PRESERVED"] == "space = value; $(no shell)"
    assert evidence["env"]["ONLY_CHILD"] == "yes" and "PATH" not in evidence["env"]
    assert not (cwd / "forbidden").exists()
    r, cwd = run(mode="argv0")
    assert r[0] == "exit:0"
    assert json.loads((cwd / "stdout.log").read_text())["argv0"] == "custom argv zero"
    r, _ = run(mode="missing-cwd")
    assert r[0] == "failed" and r[4] == "none"
    r, cwd = run("nonzero")
    assert r[0] == "exit:17" and r[2] == "false"
    assert "retained failure evidence" in (cwd / "stderr.log").read_text()
    r, _ = run("signaled")
    assert r[0].startswith("signal:") and r[2] == "false"
    r, _ = run(prog="/nonexistent/disposable-executable")
    assert r[0] == "failed" and r[4] == "none"
    r, cwd = run(preexisting=True)
    assert r[0] == "failed" and (cwd / "stdout.log").read_text() == "retained"
    for mode in ("normal", "merged", "descriptor"):
        r, cwd = run("volume", mode=mode)
        assert r[0] == "exit:0"
        assert (cwd / "stdout.log").stat().st_size == (
            2 * 1048576 if mode == "merged" else 1048576 + (13 if mode == "descriptor" else 0))
        if mode != "merged":
            assert (cwd / "stderr.log").stat().st_size == 1048576
    r, _ = run("tree", timeout=0.4)
    assert r[0] == "timeout" and r[2] == "false" and float(r[5]) < 2
    r, _ = run("resistant", timeout=0.4)
    assert r[0] == "timeout" and r[2] == "false" and float(r[5]) < 2
    r, _ = run("exit-tree")
    assert r[0] == "exit:0"  # leader success with obligatory descendant cleanup
    for s in (signal.SIGINT, signal.SIGTERM):
        r, cwd = run("interrupt", interrupt=s)
        assert r[0].startswith("cancel:") and r[2] == "false"
        assert f"forwarded:{s}" in (cwd / "stderr.log").read_text()
    r, _ = run("tree", mode="cancel")
    assert r[0].startswith("cancel:") and r[2] == "false"
    r, _ = run("tree", mode="callback-failure")
    assert r[0] == "failed" and r[2] == "false"
    r, _ = run(mode="hook-failure")
    assert r[0] == "exit:0" and r[2:4] == ["false", "true"]
    r, _ = run(mode="hook-failure", prog="/nonexistent/disposable-executable")
    assert r[0] == "failed" and r[3] == "true"
    r, _ = run(mode="hook-signal")
    assert r[0].startswith("cancel:") and r[2] == "false"
    r, _ = run(mode="nested")
    assert r[0] == "exit:0" and r[2] == "true"
    r, cwd = run("stdin")
    assert r[0] == "exit:0" and (cwd / "stdout.log").read_text() == "stdin-eof\n"
    print(f"process supervisor: {serial} real launch cases passed; groups killed, leaders reaped, handlers restored")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--consumer", type=Path)
    parser.add_argument("--installed", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="process-supervisor-", dir="/tmp/opencode") as tmp:
        root = Path(tmp)
        fixture = Path(__file__).with_name("process_child_fixture.py").resolve()
        if not args.installed:
            verify(args.consumer.resolve(), fixture, root)
            return
        prefix = root / "prefix"
        subprocess.run(["dune", "install", "-j20", "--prefix", str(prefix)],
                       cwd=repo, check=True, stdout=subprocess.DEVNULL)
        consumer = root / "consumer"
        consumer.mkdir()
        shutil.copyfile(repo / "test/process_supervisor_consumer.ml", consumer / "process_supervisor_consumer.ml")
        (consumer / "dune-project").write_text("(lang dune 3.17)\n(name installed_process_consumer)\n")
        (consumer / "dune").write_text("(executable (name process_supervisor_consumer) (libraries hardcaml_asic.execution unix))\n")
        env = dict(os.environ)
        env["OCAMLPATH"] = str(prefix / "lib") + (":" + env["OCAMLPATH"] if env.get("OCAMLPATH") else "")
        subprocess.run(["dune", "build", "-j20", "process_supervisor_consumer.exe"],
                       cwd=consumer, env=env, check=True)
        copied_fixture = root / "process_child_fixture.py"
        shutil.copyfile(fixture, copied_fixture)
        meta = (prefix / "lib/hardcaml_asic/META").read_text()
        assert "spawn" in meta and "unix" in meta
        auditing = True
        def audit(event, values):
            if auditing and event == "open" and isinstance(values[0], (str, bytes, os.PathLike)):
                path = Path(os.fsdecode(values[0])).resolve()
                if path.is_relative_to(repo):
                    raise AssertionError("checkout read in installed process test: " + str(path))
        sys.addaudithook(audit)
        try:
            verify(consumer / "_build/default/process_supervisor_consumer.exe", copied_fixture, root)
        finally:
            auditing = False
        print("fresh independently installed process consumer passed outside checkout")


if __name__ == "__main__":
    main()
