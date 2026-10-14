"""Disposable POSIX children, never physical tools."""
import json
import os
from pathlib import Path
import signal
import sys
import threading
import time

mode = sys.argv[1]
if mode == "preserve":
    print(json.dumps({"cwd": os.getcwd(), "argv": sys.argv[2:],
                      "argv0": sys.orig_argv[0], "env": dict(os.environ)}))
elif mode == "nonzero":
    print("retained failure evidence", file=sys.stderr)
    sys.exit(17)
elif mode == "signaled":
    os.kill(os.getpid(), signal.SIGTERM)
elif mode == "volume":
    def write(fd, byte):
        for _ in range(128):
            os.write(fd, byte * 8192)
    threads = [threading.Thread(target=write, args=(1, b"O")),
               threading.Thread(target=write, args=(2, b"E"))]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
elif mode == "stdin":
    assert sys.stdin.read() == ""
    print("stdin-eof")
elif mode == "resistant":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    Path("ready").write_text(str(os.getpid()))
    while True:
        time.sleep(0.1)
elif mode in ("tree", "exit-tree", "interrupt"):
    child = os.fork()
    if child == 0:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        Path("descendant.pid").write_text(str(os.getpid()))
        while True:
            time.sleep(0.1)
    def interrupted(s, _):
        os.write(2, ("forwarded:" + str(s) + "\n").encode())
        sys.exit(0)
    if mode == "interrupt":
        signal.signal(signal.SIGINT, interrupted)
        signal.signal(signal.SIGTERM, interrupted)
    while not Path("descendant.pid").exists():
        time.sleep(0.005)
    Path("ready").write_text(str(os.getpid()))
    if mode == "exit-tree":
        sys.exit(0)
    while True:
        time.sleep(0.1)
else:
    raise AssertionError(mode)
