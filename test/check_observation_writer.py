"""Real live writer/reader subprocesses, cross-language immutable schema-2 IO."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import shutil
import os


def verify(driver, reader, package, root):
    sys.path.insert(0, str(package.parent))
    from hardcaml_asic_flow import flow_observation as fo, execution_plan as ep
    count = 0

    def start(name, workspace=None):
        workspace = workspace or root / name
        p = subprocess.Popen([str(driver), str(root / "journals"), str(workspace)],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        receipt = json.loads(p.stdout.readline())
        return p, receipt, workspace

    def send(p, event, data):
        p.stdin.write(json.dumps(dict(event=event, data=data)) + "\n")
        p.stdin.flush()
        return p.stdout.readline().strip()

    def finish(p):
        p.stdin.close()
        assert p.wait(timeout=5) == 0, p.stderr.read()

    p, receipt, workspace = start("live")
    directory = Path(receipt["attempt"])
    try:
        state, events = fo.load(directory)
        assert fo.inspect(directory)["writer_active"] is True
        native = subprocess.run([str(reader), "inspect", str(directory)], capture_output=True, text=True, check=True)
        assert json.loads(native.stdout) == fo.inspect(directory)
        busy = subprocess.run([str(driver), str(root / "journals"), str(workspace)], capture_output=True, text=True)
        assert busy.returncode == 2 and "Busy" in busy.stderr
        # Python writer shares the *same workspace flock*, not merely its activity lock.
        try:
            fo.Writer(root / "journals", workspace=workspace, checkpoint_store=workspace / "checkpoints", request={})
        except fo.ObservationError as e:
            assert e.code == "BUSY"
        else:
            raise AssertionError("Python writer acquired live OCaml workspace")
        plan = ep.resolve_stages("synthesis")
        assert send(p, "planned", {"plan": plan.as_dict()}) == "ok"
        assert send(p, "prepared", {"runtime_record": None}) == "ok"
        occurrence = dict(occurrence_id=receipt["stream_id"] + "/implementation.synthesis",
                          action_key="implementation.synthesis", status="running", exit_code=None,
                          duration_seconds=0.0, best_effort=False, error=None, verdict=None)
        assert send(p, "started", {"occurrence": occurrence, "artifact": None}) == "ok"
        occurrence.update(status="failed", exit_code=17, error="backend failed", duration_seconds=0.1250001)
        assert send(p, "finished", {"occurrence": occurrence, "artifact": None}) == "ok"
        assert send(p, "outcome", {"status": "failed", "exit_code": 17, "error": "backend failed"}) == "ok"
        state, events = fo.load(directory)
        assert [e["sequence"] for e in events] == list(range(1, 7))
        assert all(e["sha256"] == fo.digest({k: v for k, v in e.items() if k != "sha256"}) for e in events)
        assert all(e["schema_version"] == 2 for e in events)
        assert sorted(e["elapsed_seconds"] for e in events) == [e["elapsed_seconds"] for e in events]
        native = subprocess.run([str(reader), "inspect", str(directory)], capture_output=True, text=True, check=True)
        assert json.loads(native.stdout) == fo.inspect(directory)
        count += 8
    finally:
        finish(p)
    assert fo.inspect(directory)["writer_active"] is False
    # Opposite direction is real Python writer -> native cold reader, while live.
    with_workspace = root / "python"
    w = fo.Writer(root / "journals", workspace=with_workspace, checkpoint_store=with_workspace / "checkpoints", request={})
    try:
        native = subprocess.run([str(reader), "inspect", str(w.directory)], capture_output=True, text=True, check=True)
        assert json.loads(native.stdout) == fo.inspect(w.directory)
    finally:
        w.close()
    count += 2
    # Detach/kill never fabricates completion, and releasing locks permits a fresh attempt.
    p, receipt, workspace = start("lost")
    p.terminate()
    p.wait(timeout=5)
    assert fo.inspect(receipt["attempt"])["state"]["outcome"] is None
    assert fo.inspect(receipt["attempt"])["observation_status"] == "writer_lost_or_unknown"
    p, _, _ = start("replacement", workspace)
    finish(p)
    count += 3
    # Atomic no-replace conflict poisons without changing the committed prefix.
    p, receipt, _ = start("collision")
    directory = Path(receipt["attempt"])
    retained = (directory / "000000000001.json").read_bytes()
    collision = directory / "000000000002.json"
    collision.write_text("retained user data")
    assert send(p, "planned", {"plan": plan.as_dict()}).startswith("error:")
    assert collision.read_text() == "retained user data"
    assert (directory / "000000000001.json").read_bytes() == retained
    assert send(p, "outcome", {"status": "failed", "exit_code": 2, "error": "storage"}).startswith("error:")
    assert not list(directory.glob(".event*"))
    finish(p)
    count += 5
    process = subprocess.Popen([str(driver), str(root / "journals"), str(root / "timing"), "timing"],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    receipt = json.loads(process.stdout.readline())
    assert send(process, "planned", {"plan": plan.as_dict()}) == "ok"
    finish(process)
    _, events = fo.load(receipt["attempt"])
    assert [e["elapsed_seconds"] for e in events] == [0.125, 0.25]
    assert [e["recorded_at"] for e in events] == ["2023-11-14T22:13:19.875000Z", "2023-11-14T22:13:19.750000Z"]
    assert all(e["sha256"] == fo.digest({k: v for k, v in e.items() if k != "sha256"}) for e in events)
    count += 3
    print(f"observation writer: {count} live/cross-language/lock/no-replace checks passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--consumer", type=Path, default=Path("_build/default/test/observation_writer_consumer.exe"))
    parser.add_argument("--reader", type=Path, default=Path("_build/default/bin/experimental_observation_read.exe"))
    parser.add_argument("--installed", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="observation-writer-", dir="/tmp/opencode") as tmp:
        root = Path(tmp)
        if not args.installed:
            verify(args.consumer.resolve(), args.reader.resolve(), repo / "flow/hardcaml_asic_flow", root)
            return
        prefix = root / "prefix"
        subprocess.run(["dune", "install", "-j20", "--prefix", str(prefix)], cwd=repo, check=True, stdout=subprocess.DEVNULL)
        consumer = root / "consumer"
        consumer.mkdir()
        shutil.copyfile(repo / "test/observation_writer_consumer.ml", consumer / "observation_writer_consumer.ml")
        (consumer / "dune-project").write_text("(lang dune 3.17)\n(name installed_writer)\n")
        (consumer / "dune").write_text("(executable (name observation_writer_consumer) (libraries hardcaml_asic.execution unix))\n")
        env = dict(os.environ, OCAMLPATH=str(prefix / "lib") + ":" + os.environ.get("OCAMLPATH", ""))
        subprocess.run(["dune", "build", "-j20", "observation_writer_consumer.exe"], cwd=consumer, env=env, check=True)
        auditing = True
        def audit(event, values):
            if auditing and event == "open" and isinstance(values[0], (str, bytes, os.PathLike)):
                if Path(os.fsdecode(values[0])).resolve().is_relative_to(repo):
                    raise AssertionError("checkout read: " + str(values[0]))
        sys.addaudithook(audit)
        try:
            verify(consumer / "_build/default/observation_writer_consumer.exe",
                   prefix / "bin/hardcaml-asic-experimental-observation-read",
                   prefix / "lib/hardcaml_asic/flow/hardcaml_asic_flow", root)
        finally:
            auditing = False


if __name__ == "__main__":
    main()
