#!/usr/bin/python3
"""Fixture engine for installed prepared-service composition, not real Docker."""
import json
import os
from pathlib import Path
import subprocess
import sys

args = sys.argv[1:]
root = Path(os.environ["SERVICE_ENGINE_ROOT"])
with (root / "engine-events.jsonl").open("a") as stream:
    stream.write(json.dumps(args) + "\n")
if args[:2] == ["rm", "-f"]:
    if os.environ.get("SERVICE_ENGINE_CLEANUP_FAIL"):
        print("fixture daemon cleanup failure", file=sys.stderr)
        sys.exit(23)
    print("No such container: " + args[2], file=sys.stderr)
    sys.exit(1)
assert args[0] == "run", args
image = next(i for i, arg in enumerate(args) if arg.startswith("sha256:"))
command = args[image + 1:]
flags = [a for a in command if a in ("-I", "-B")]
bridge, request = command[-2:]
operation = json.loads(Path(request).read_text())["operation"]
if operation == "validate_publication" and os.environ.get("SERVICE_VALIDATION_EXIT"):
    sys.exit(int(os.environ["SERVICE_VALIDATION_EXIT"]))
if operation == "execute_segment" and os.environ.get("SERVICE_EXECUTION_SLEEP"):
    import time
    time.sleep(float(os.environ["SERVICE_EXECUTION_SLEEP"]))
result = subprocess.run([sys.executable, *flags, os.environ["SERVICE_ENGINE_FIXTURE"], bridge, request])
sys.exit(result.returncode)
