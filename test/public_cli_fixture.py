"""External-process fixture for the real public parser -> OCaml -> bridge route."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

PACKAGE_ROOT = Path(os.environ.get("STAGE_TEST_PACKAGE_ROOT", str(Path(__file__).resolve().parents[1] / "flow")))
sys.path.insert(0, str(PACKAGE_ROOT))
from hardcaml_asic_flow import checkpoint as cp, runtime_contract as rc, execution_plan as ep
from hardcaml_asic_flow.ocaml_backend import binary


class Fixture:
    def __init__(self, root, mode="success"):
        self.root = Path(root)
        self.workspace = self.root / "workspace with spaces"
        self.store = self.workspace / "checkpoints"
        requested = {"python": "3.11", "librelane": "3.1.0.dev3"}
        policy = rc.policy_from_requested(requested)
        policy.pop("source")
        policy.pop("librelane")
        policy["implementation"]["dockerized"].update(
            policy="official-librelane-image", python={"policy": "distribution-supported", "requires_python": rc.REQUIRES_PYTHON,
                                                      "supported_minors": list(rc.SUPPORTED_MINORS)})
        requested.update(runtime_policy=policy, support_tools_revision="revision", pdk_revision="revision")
        (self.root / "tt").mkdir()
        (self.root / "tt/floorplan.def").write_text("fixture")
        (self.root / "pdk/fixture").mkdir(parents=True)
        (self.root / "bundle/src").mkdir(parents=True)
        (self.root / "bundle/src/config.json").write_text('{"CLOCK_PERIOD":10}')
        manifest = {"identity": "a" * 64, "schema_version": 1, "adapter": "LibreLane", "requested_tools": requested,
                    "target": {"technology": "fixture", "external_references": [
                        {"source": "Support_tools", "path": "floorplan.def", "role": "floorplan"}]},
                    "files": [{"path": "src/config.json", "sha256": cp.digest(self.root / "bundle/src/config.json")}]}
        (self.root / "bundle/manifest.json").write_text(json.dumps(manifest))
        fixtures = Path(__file__).resolve().parent
        (self.root / "bin").mkdir()
        for name in ("python", "docker", "git"):
            shutil.copyfile(fixtures / "stage_preparation_engine.py", self.root / "bin" / name)
            (self.root / "bin" / name).chmod(0o700)
        shutil.copyfile(fixtures / "segment_service_engine.py", self.root / "bin/segment_service_engine.py")
        discovery = json.loads(subprocess.run([str(binary("plan_inspect"))],
            input=json.dumps(ep.resolve_stages("signoff").as_dict()), text=True,
            capture_output=True, check=True).stdout)
        (self.root / "classic-inventory.json").write_text(json.dumps([o["backend"] for o in discovery["operation_sequence"]]))
        (self.root / "classic-settings.json").write_text(json.dumps({
            o["backend"]["implementation"]: o["settings"] for o in discovery["operation_sequence"] if o["settings"]}))
        self.env = dict(os.environ, SERVICE_ENGINE_ROOT=str(self.root),
                        SERVICE_ENGINE_FIXTURE=str(fixtures / "segment_service_fixture.py"),
                         PREPARATION_IMAGE=ep.TESTED_IMAGE, PREPARATION_MODE=mode,
                        PATH=str(self.root / "bin") + os.pathsep + os.environ["PATH"])

    def command(self, endpoint="synthesis"):
        return ["stages", "bundle", "--endpoint", endpoint, "--workspace", self.workspace.name,
                "--checkpoint-store", str(self.store), "--support-tools", "tt", "--pdk-root", "pdk",
                "--python", "bin/python", "--timeout", "2"]

    def invoke(self, arguments, live=False, **kwargs):
        launcher = os.environ.get("PUBLIC_FLOW_CLI")
        if os.environ.get("FLOW_TEST_RUNTIME_ROOT") and not launcher:
            raise ValueError("installed public tests require PUBLIC_FLOW_CLI")
        argv = ([launcher] if launcher else [sys.executable, "-I", "-B", "-c",
            "import sys;sys.path.insert(0,sys.argv[1]);from hardcaml_asic_flow.cli import main;sys.exit(main(sys.argv[2:]))",
            str(PACKAGE_ROOT)]) + arguments
        options = dict(cwd=self.root, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        options.update(kwargs)
        return subprocess.Popen(argv, **options) if live else subprocess.run(argv, timeout=100, **options)
