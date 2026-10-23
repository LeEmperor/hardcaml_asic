"""Deterministic production bridge lifecycle; optional persistent handoff fixture."""
import argparse
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_stage_preparation import verify

parser = argparse.ArgumentParser()
parser.add_argument("--retain", type=Path)
parser.add_argument("--cli", type=Path)
parser.add_argument("--consumer", type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
def run(root):
    verify(args.cli.resolve() if args.cli else repo / "_build/default/bin/experimental_stages.exe",
           args.consumer.resolve() if args.consumer else repo / "_build/default/test/stage_preparation_consumer.exe",
           repo / "flow/hardcaml_asic_flow", root, repo / "test", timing_only=True)
if args.retain:
    args.retain.mkdir()
    run(args.retain.resolve())
else:
    with tempfile.TemporaryDirectory(prefix="executable-timing-", dir="/tmp/opencode") as tmp:
        run(Path(tmp))
