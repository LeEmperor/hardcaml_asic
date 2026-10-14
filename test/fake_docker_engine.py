#!/usr/bin/python3
"""Disposable engine/daemon protocol fixture, no Docker or EDA dependencies."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

root = Path(os.environ["FIXTURE_ROOT"])
mode = os.environ["FIXTURE_MODE"]

def event(kind, name):
    with (root / "events").open("a") as f:
        f.write(json.dumps({"kind": kind, "name": name, "argv": sys.argv[1:],
                            "cwd": os.getcwd(), "environment": dict(os.environ)}) + "\n")

if sys.argv[1] == "daemon":
    name = sys.argv[2]
    if mode in ("race", "race-nonzero"):
        time.sleep(0.18)
    (root / name).write_text(str(os.getpid()))
    event("created", name)
    while True:
        time.sleep(1)
elif sys.argv[1] == "run":
    name = sys.argv[sys.argv.index("--name") + 1]
    event("run", name)
    if mode not in ("nonzero", "signaled", "absent"):
        subprocess.Popen([sys.executable, __file__, "daemon", name], start_new_session=True,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if mode == "race":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
    if mode not in ("race", "race-nonzero", "nonzero", "signaled", "absent"):
        while not (root / name).exists():
            time.sleep(0.005)
    (root / "ready").write_text(str(os.getpid()))
    if mode in ("race", "interrupt"):
        time.sleep(60)
    if mode == "signaled":
        os.kill(os.getpid(), signal.SIGTERM)
    sys.exit(17 if mode in ("nonzero", "race-nonzero", "rmfail-primary") else 0)
elif sys.argv[1:3] == ["rm", "-f"]:
    name = sys.argv[3]
    event("rm", name)
    if mode.startswith("cleanup-sig") and not (root / "interrupted").exists():
        (root / "interrupted").touch()
        os.kill(os.getppid(), signal.SIGINT if mode == "cleanup-sigint" else signal.SIGTERM)
        time.sleep(60)
    if mode.startswith("rmfail"):
        print("daemon unavailable", file=sys.stderr)
        sys.exit(23)
    if mode == "transient" and not (root / "retried").exists():
        (root / "retried").touch()
        print("transient daemon error", file=sys.stderr)
        sys.exit(23)
    if mode == "rmhang":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        # A timeout must not be classified as absence based on text alone.
        print("No such container", file=sys.stderr, flush=True)
        time.sleep(60)
    path = root / name
    if not path.exists():
        event("absent", name)
        print("Error: No such container: " + name, file=sys.stderr)
        sys.exit(1)
    os.kill(int(path.read_text()), signal.SIGKILL)
    path.unlink()
    event("removed", name)
else:
    raise AssertionError(sys.argv)
