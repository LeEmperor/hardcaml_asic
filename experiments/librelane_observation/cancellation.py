"""Real owned-container timeout with an official-API SYNTHETIC subprocess step.

This proves scoped transport removal on this local Docker engine, not graceful
EDA cancellation, checkpoint recovery, or a backend interruption callback.
"""

import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time


def inside(project):
    from librelane.config import Variable
    from librelane.flows import SequentialFlow
    from librelane.steps import Step

    config = project / "fixture/config.json"
    pdk = project / "fixture/synthetic-pdks"

    class Hold(Step):
        id = "Probe.RealSubprocessHold"
        inputs = []
        outputs = []

        def run(self, state_in, **kwargs):
            (project / "body-entered").write_text(self.id)
            self.run_subprocess([sys.executable, "-I", "-B", "-c",
                                 "from pathlib import Path; import time,sys; "
                                 "Path(sys.argv[1]).write_text('ready'); time.sleep(120)",
                                 str(project / "child-ready")])
            (project / "body-returned").write_text(self.id)
            return {}, {}

    class HoldFlow(SequentialFlow):
        Steps = [Hold]
        config_vars = [Variable("OBS_ENABLE", bool, "Unused synthetic fixture setting", default=False)]

    HoldFlow(str(config), pdk_root=str(pdk)).start(tag="cancellation")


def outside():
    sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "flow"))
    from hardcaml_asic_flow import execution_transport as transport, phase4, runtime_observation

    root = Path(tempfile.mkdtemp(prefix="librelane-cancellation-", dir="/tmp/opencode"))
    print(f"SCRATCH={root}", flush=True)
    project = root / "project"
    project.mkdir()
    (project / "fixture").mkdir()
    for name in ("cancellation.py", "fixture.py"):
        shutil.copyfile(Path(__file__).with_name(name), project / name)
    spec = importlib.util.spec_from_file_location("fixture", project / "fixture.py")
    fixture = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fixture)
    fixture.build(project / "fixture")
    observation = runtime_observation.observe_container("ghcr.io/librelane/librelane:3.1.0.dev3")
    binding = transport.from_preflight({"runtime_contract": {
        "execution_mode": "dockerized", "observations": {"container": observation}}}, native=False)
    transport.verify_engine(binding)
    transport.verify_image(binding)
    name = transport.owned_name()
    record = {"designation": "REAL timeout/removal of SYNTHETIC official-API subprocess step",
              "binding": binding, "commands": [], "container_name": name,
              "bridge_sha256": hashlib.sha256((project / "cancellation.py").read_bytes()).hexdigest(),
              "host_processes": [], "observer_error": None}
    record_path = root / "evidence.json"

    def observe():
        try:
            deadline = time.monotonic() + 6
            while not (project / "child-ready").is_file():
                if time.monotonic() >= deadline:
                    raise RuntimeError("subprocess did not become ready before timeout")
                time.sleep(0.02)
            text = runtime_observation.output([binding["engine_identity"]["executable"],
                                               "top", name, "-eo", "pid"], timeout=2)
            for line in text.splitlines()[1:]:
                pid = int(line.strip())
                proc = Path(f"/proc/{pid}")
                record["host_processes"].append({"pid": pid,
                    "starttime": proc.joinpath("stat").read_text().split()[21],
                    "command": proc.joinpath("cmdline").read_bytes().replace(b"\0", b" ").decode()})
        except Exception as exc:
            record["observer_error"] = str(exc)

    observer = threading.Thread(target=observe, daemon=True)
    argv = transport.docker_command(binding, project, project / "fixture/synthetic-pdks", name=name)
    argv += [*binding["interpreter_flags"], str(project / "cancellation.py"), "--inside", str(project)]
    observer.start()
    try:
        code = phase4.run_logged(argv, project, transport.environment(), root / "execution.log",
                                record, record_path, timeout=8,
                                cleanup=lambda: transport.cleanup(binding, name))
        raise AssertionError(f"held subprocess unexpectedly exited {code}; see {root / 'execution.log'}")
    except subprocess.TimeoutExpired:
        record["transport_outcome"] = "TimeoutExpired"
    finally:
        observer.join(3)
        phase4.save(record_path, record)
    assert not observer.is_alive() and record["observer_error"] is None
    assert (project / "body-entered").is_file() and (project / "child-ready").is_file()
    assert len(record["host_processes"]) >= 2
    assert any("time.sleep(120)" in p["command"] for p in record["host_processes"])
    for process in record["host_processes"]:
        path = Path(f"/proc/{process['pid']}/stat")
        assert not path.exists() or path.read_text().split()[21] != process["starttime"]
    result = subprocess.run([binding["engine_identity"]["executable"], "inspect", name],
                            capture_output=True, text=True, timeout=5, env=transport.environment())
    assert result.returncode != 0 and "no such" in result.stderr.lower()
    assert not (project / "body-returned").exists()
    assert not list(project.glob("fixture/runs/**/state_out.json"))
    record.update(status="passed", container_absent=True, observed_host_processes_gone=True,
                  body_return_absent=True, state_out_absent=True,
                  limits=["synthetic child is Python sleep, not EDA", "forced removal, not graceful signal acknowledgement",
                          "no flow-level or per-step interruption callback returned", "local daemon /proc visibility required"])
    phase4.save(record_path, record)
    print(f"PASSED {record_path}")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--inside":
        inside(Path(sys.argv[2]))
    elif len(sys.argv) == 1:
        outside()
    else:
        raise SystemExit("usage: python3 -B cancellation.py")
