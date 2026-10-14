"""Existing consumer endpoint route into the installed CLI4 OCaml pipeline.

Uses an explicit synthetic bundle and external-process fixtures. No emission,
Git mutation or physical tools; invokes from a nested source directory to check
consumer project-root inference and public path anchoring.
"""
import argparse
import json
from pathlib import Path
import os
import subprocess
import tempfile

from public_cli_fixture import Fixture


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--consumer", required=True, type=Path)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--prefix", required=True, type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="public-consumer-", dir="/tmp/opencode") as tmp:
        fixture = Fixture(tmp)
        env = dict(fixture.env, PATH=str(args.prefix.resolve() / "bin") + os.pathsep + fixture.env["PATH"])
        result = subprocess.run([str(args.consumer.resolve()), "run", "--endpoint", "floorplan",
            "--bundle", str(fixture.root / "bundle"), "--results-root", str(fixture.root / "results"),
            "--support-tools", str(fixture.root / "tt"), "--pdk-root", str(fixture.root / "pdk"),
            "--python", str(fixture.root / "bin/python"), "--json"],
            cwd=args.source.resolve() / "asic", env=env, capture_output=True, text=True, timeout=100)
        assert result.returncode == 0, result.stderr
        allocation, execution = map(json.loads, result.stdout.splitlines())
        assert [a["boundary"] for a in execution["artifacts"]] == ["synthesis", "floorplan"]
        attempt = Path(allocation["attempt"])
        assert attempt.parent == fixture.root / "results/observations"
        inspect = subprocess.run([str(args.prefix.resolve() / "bin/hardcaml-asic-flow"),
            "observation", "inspect", str(attempt), "--json"], cwd=fixture.root, env=env,
            capture_output=True, text=True, check=True)
        state = json.loads(inspect.stdout)
        assert state["state"]["request"]["caller_cwd"] == str(args.source.resolve() / "asic")
        assert state["state"]["outcome"]["status"] == "completed" and not state["writer_active"]
        workspace = Path(state["state"]["workspace"])
        assert workspace.parent == fixture.root / "results" and workspace.name.startswith("floorplan-")
        assert json.loads((workspace / ("execution-" + execution["attempt_id"] + ".json")).read_text()) == execution
        print("consumer nested-root endpoint route -> installed public CLI -> OCaml preparation/runner/publication/journal passed")


if __name__ == "__main__":
    main()
