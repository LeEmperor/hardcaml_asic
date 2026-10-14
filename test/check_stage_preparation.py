"""OCaml-owned preparation and actual transported bridge, source/installed modes."""
import argparse
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import signal


def verify(cli, consumer, package, root, fixtures, installed=False):
    sys.path.insert(0, str(package.parent))
    from hardcaml_asic_flow import runtime_contract as rc, execution_plan as ep, checkpoint as cp, flow_observation as fo
    count = 0
    serial = 0
    requested = {"python": "3.11", "librelane": "3.1.0.dev3"}
    requested["runtime_policy"] = rc.policy_from_requested(requested)
    # The normalized policy has a source field; persisted explicit policy does not.
    requested["runtime_policy"].pop("source")
    requested["runtime_policy"].pop("librelane")
    requested["runtime_policy"]["implementation"]["dockerized"].update(
        policy="official-librelane-image", python={"policy": "distribution-supported", "requires_python": rc.REQUIRES_PYTHON,
                                                   "supported_minors": list(rc.SUPPORTED_MINORS)})
    requested.update(support_tools_revision="revision", pdk_revision="revision")
    from hardcaml_asic_flow.ocaml_backend import binary
    discovery = json.loads(subprocess.run([str(binary("plan_inspect"))],
        input=json.dumps(ep.resolve_stages("signoff").as_dict()), text=True,
        capture_output=True, check=True).stdout)
    inventory = [o["backend"] for o in discovery["operation_sequence"]]

    def fixture(mode="success"):
        nonlocal serial
        serial += 1
        case = root / f"case-{serial}"
        case.mkdir()
        (case / "classic-inventory.json").write_text(json.dumps(inventory))
        (case / "classic-settings.json").write_text(json.dumps({
            o["backend"]["implementation"]: o["settings"] for o in discovery["operation_sequence"] if o["settings"]}))
        toolchain = case / "toolchain"
        (toolchain / "tt").mkdir(parents=True)
        (toolchain / "pdk/fixture").mkdir(parents=True)
        (toolchain / "tt/floorplan.def").write_text("floorplan fixture")
        bundle = case / "bundle"
        (bundle / "src").mkdir(parents=True)
        (bundle / "src/config.json").write_text('{"CLOCK_PERIOD":10}')
        manifest = {"identity": "a" * 64, "schema_version": 1, "adapter": "LibreLane",
                    "requested_tools": copy.deepcopy(requested), "target": {"technology": "fixture",
                    "external_references": [{"source": "Support_tools", "path": "floorplan.def", "role": "floorplan"}]},
                    "files": [{"path": "src/config.json", "sha256": cp.digest(bundle / "src/config.json")}]}
        (bundle / "manifest.json").write_text(json.dumps(manifest))
        executables = case / "bin"
        executables.mkdir()
        for name in ("python", "docker", "git"):
            shutil.copyfile(fixtures / "stage_preparation_engine.py", executables / name)
            (executables / name).chmod(0o700)
        shutil.copyfile(fixtures / "segment_service_engine.py", executables / "segment_service_engine.py")
        env = dict(os.environ, SERVICE_ENGINE_ROOT=str(case), SERVICE_ENGINE_FIXTURE=str(fixtures / "segment_service_fixture.py"),
                   PREPARATION_IMAGE=ep.TESTED_IMAGE, PREPARATION_MODE=mode)
        cfg = {"bundle": str(bundle), "support_tools": str(toolchain / "tt"), "pdk_root": str(toolchain / "pdk"),
               "python": str(executables / "python"), "docker": str(executables / "docker"), "git": str(executables / "git"),
               "resources": str(package), "workspace": str(case / "workspace with spaces"),
               "checkpoint_store": str(case / "workspace with spaces/checkpoints"), "evidence_root": str(case / "evidence"),
               "environment": [k + "=" + v for k, v in env.items()], "checkpoint": None,
               "plan": ep.resolve_stages("synthesis").as_dict()}
        return case, cfg, env, manifest

    def call(case, cfg, env, api=False, through="synthesis", journal=False, human=False, extra=(), live=False):
        if api:
            config_path = case / "config.json"
            config_path.write_text(json.dumps(cfg))
            argv = [str(consumer), str(config_path)]
        else:
            argv = [str(cli), "--no-observation", "--json", "--bundle", cfg["bundle"], "--support-tools", cfg["support_tools"],
                    "--pdk-root", cfg["pdk_root"], "--python", cfg["python"], "--docker", cfg["docker"], "--git", cfg["git"],
                    "--workspace", cfg["workspace"], "--checkpoint-store", cfg["checkpoint_store"],
                    "--evidence-root", cfg["evidence_root"], "--timeout", "2", "--probe-timeout", "2", "--through", through]
            if not installed:
                argv += ["--resources", cfg["resources"]]
            if cfg["checkpoint"]:
                argv += ["--checkpoint", cfg["checkpoint"]]
            if journal:
                argv.remove("--no-observation")
            if human:
                argv.remove("--json")
            argv += list(extra)
        if live:
            return subprocess.Popen(argv, env=env, cwd=case, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return subprocess.run(argv, env=env, cwd=case, capture_output=True, text=True, timeout=100)

    def rejected(mode="success", mutate=None, api=False, expected_code=None):
        nonlocal count
        case, cfg, env, manifest = fixture(mode)
        if mutate:
            mutate(case, cfg, env, manifest)
        result = call(case, cfg, env, api=api)
        assert result.returncode != 0, result.stdout
        if expected_code:
            assert result.returncode == expected_code, result.stderr
        reports = list(Path(cfg["evidence_root"]).glob("operations/*/preflight.json"))
        assert len(reports) == 1, result.stderr
        report = json.loads(reports[0].read_text())
        assert report["ready"] is False and report["issues"], report
        receipt = json.loads(reports[0].with_name("operation.json").read_text())
        assert receipt["status"] in ("failed", "interrupted"), receipt
        assert not list(Path(cfg["workspace"]).glob("project/*-request.json"))
        count += 1

    case, cfg, env, _ = fixture()
    result = call(case, cfg, env, through="floorplan")
    assert result.returncode == 0, result.stderr
    summary = json.loads(result.stdout)
    assert [a["boundary"] for a in summary["artifacts"]] == ["synthesis", "floorplan"]
    for artifact in summary["artifacts"]:
        manifest = cp.validate(artifact["path"], compatibility=cp.read(Path(artifact["path"]) / "manifest.json")["compatibility"])
        assert manifest["compatibility"]["project"] == cfg["workspace"] + "/project"
    project = Path(cfg["workspace"]) / "project"
    assert (project / "tt/floorplan.def").read_text() == "floorplan fixture"
    assert cp.digest(project / "bridge/librelane_bridge.py") == cp.digest(package / "librelane_bridge.py")
    reqs = list(project.glob("*-request.json"))
    assert len(reqs) == 2
    count += 1
    # Existing workspace is never adopted, even after successful preparation.
    preserved = (project / "manifest.json").read_bytes()
    retry = call(case, cfg, env)
    assert retry.returncode != 0 and (project / "manifest.json").read_bytes() == preserved
    assert len(list(project.glob("*-request.json"))) == 2
    count += 1
    # Exact path-bound resume uses the same staged bridge and actual publication.
    cfg["checkpoint"] = summary["artifacts"][-1]["path"]
    cfg["plan"] = ep.resolve_sequence(["placement"], initial_boundary="floorplan").as_dict()
    resumed = call(case, cfg, env, api=True)
    assert resumed.returncode == 0, resumed.stderr
    assert json.loads(resumed.stdout)["artifacts"][0]["boundary"] == "placement"
    assert len(list(project.glob("*-request.json"))) == 3
    count += 1
    retained_checkpoint = cfg["checkpoint"]
    cfg["checkpoint"] = json.loads(resumed.stdout)["artifacts"][0]["path"]
    cli_resume = call(case, cfg, env, through="cts")
    assert cli_resume.returncode == 0, cli_resume.stderr
    assert json.loads(cli_resume.stdout)["artifacts"][0]["boundary"] == "cts"
    cfg["checkpoint"] = retained_checkpoint
    count += 1
    # Relocation and changed compatibility fail without any new backend call.
    cfg["pdk_root"] = str(case / "other-pdk")
    Path(cfg["pdk_root"]).mkdir()
    mismatch = call(case, cfg, env, api=True)
    assert mismatch.returncode != 0 and len(list(project.glob("*-request.json"))) == 4
    count += 1
    cfg["pdk_root"] = str(case / "toolchain/pdk")
    (project / "tt/floorplan.def").write_text("changed staged support")
    changed_support = call(case, cfg, env, api=True)
    assert changed_support.returncode != 0 and len(list(project.glob("*-request.json"))) == 4
    count += 1
    (project / "tt/floorplan.def").write_text("floorplan fixture")
    (project / "bridge/librelane_bridge.py").write_text("changed transported bridge")
    changed_bridge = call(case, cfg, env, api=True)
    assert changed_bridge.returncode != 0 and len(list(project.glob("*-request.json"))) == 4
    count += 1
    for mode in ("classic_settings_drift", "classic_drift", "classic_missing", "tcl_failure", "host_mismatch", "protocol_version", "wrong_image", "dirty", "engine_changed", "probe_failure", "probe_timeout"):
        rejected(mode, expected_code={"probe_failure": 17, "probe_timeout": 124}.get(mode))
    for mode in ("fallback",):
        case, cfg, env, _ = fixture(mode)
        result = call(case, cfg, env, api=True)
        assert result.returncode == 0, result.stderr
        compat = cp.read(Path(json.loads(result.stdout)["artifacts"][0]["path"]) / "manifest.json")["compatibility"]
        assert compat["binding"]["interpreter_flags"] == ["-B"]
        count += 1
    def edit_manifest(change):
        def mutate(case, cfg, env, manifest):
            change(manifest)
            (Path(cfg["bundle"]) / "manifest.json").write_text(json.dumps(manifest))
        return mutate
    rejected(mutate=edit_manifest(lambda m: m.update(schema_version=2)))
    rejected(mutate=edit_manifest(lambda m: m.update(identity="bad")))
    rejected(mutate=edit_manifest(lambda m: m["requested_tools"].update(support_tools_revision="wrong")))
    rejected(mutate=edit_manifest(lambda m: m["requested_tools"]["runtime_policy"].update(schema_version=True)))
    rejected(mutate=edit_manifest(lambda m: m["files"][0].update(path="../escape")))
    rejected(mutate=edit_manifest(lambda m: m["target"].update(technology="..")))
    rejected(mutate=lambda c, cfg, e, m: (Path(cfg["bundle"]) / "src/config.json").write_text("changed"))
    rejected(mutate=lambda c, cfg, e, m: cfg.update(pdk_root=str(c / "missing")))
    rejected(mutate=lambda c, cfg, e, m: cfg.update(docker=str(c / "missing-engine")))
    rejected(mutate=lambda c, cfg, e, m: cfg.update(python=str(c / "missing-python")))
    rejected(mutate=lambda c, cfg, e, m: cfg.update(checkpoint_store=str(c / "outside")))
    rejected(mutate=lambda c, cfg, e, m: Path(cfg["workspace"]).mkdir())
    rejected(mutate=lambda c, cfg, e, m: cfg.update(resources=str(c / "missing-resources")), api=True)
    def missing_resource(case, cfg, env, manifest):
        resource = case / "resources"
        resource.mkdir()
        shutil.copyfile(package / "librelane_bridge.py", resource / "librelane_bridge.py")
        cfg["resources"] = str(resource)
    rejected(mutate=missing_resource, api=True)
    def changed_resource(case, cfg, env, manifest):
        resource = case / "resources"
        resource.mkdir()
        for name in ("librelane_bridge.py", "backend_protocol.py", "stage_metadata_probe.py"):
            shutil.copyfile(package / name, resource / name)
        (resource / "backend_protocol.py").write_text("tampered")
        cfg["resources"] = str(resource)
    rejected(mutate=changed_resource, api=True)
    rejected(mutate=lambda c, cfg, e, m: cfg.update(plan=ep.resolve("synthesis").as_dict()), api=True)
    # Runtime failures override apparent readiness and retain runner diagnostics.
    for runtime_mode in ("exit17", "missing_reply", "engine_changed_after_execute"):
        case, cfg, env, _ = fixture(runtime_mode if runtime_mode.startswith("engine_") else "success")
        env["SERVICE_FIXTURE_MODE"] = runtime_mode
        result = call(case, cfg, env)
        assert result.returncode != 0 and not list(Path(cfg["checkpoint_store"]).iterdir()), result.stderr
        assert json.loads(next(Path(cfg["workspace"]).glob("diagnostics-*.json")).read_text())["primary"]
        count += 1
    # Full installed preparation/runner/publisher/journal chain: no Python writer.
    def check_report_references(cfg, state, status):
        receipts = list(Path(cfg["evidence_root"]).glob("operations/*/operation.json"))
        assert len(receipts) == 1
        receipt = json.loads(receipts[0].read_text())
        assert receipt["status"] == status, receipt
        local = receipts[0].parent / receipt["report"]
        journal = Path(state["preflight_record"])
        assert local.is_file() and journal.is_file(), (local, journal)
        assert local.read_bytes() == journal.read_bytes()

    for through in ("synthesis", "floorplan"):
        case, cfg, env, _ = fixture()
        env["ASSERT_JOURNAL_BEFORE_PROBE"] = "1"
        result = call(case, cfg, env, journal=True, through=through)
        assert result.returncode == 0, result.stderr
        allocated, summary = [json.loads(line) for line in result.stdout.splitlines()]
        assert allocated["event"] == "observation_allocated"
        state, events = fo.load(allocated["attempt"])
        assert state["attempt_id"] == summary["attempt_id"] == allocated["stream_id"]
        assert state["outcome"]["status"] == "completed"
        assert state["artifacts"] == summary["artifacts"]
        assert Path(state["preflight_record"]).is_file()
        check_report_references(cfg, state, "ready")
        assert not fo.inspect(allocated["attempt"])["writer_active"]
        names = [e["event"] for e in events]
        assert names == ["allocated", "planned", "prepared"] + ["started", "published", "finished"] * len(summary["artifacts"]) + ["outcome"]
        execution_path = Path(cfg["workspace"]) / ("execution-" + summary["attempt_id"] + ".json")
        assert json.loads(execution_path.read_text()) == summary
        assert execution_path.stat().st_mtime <= Path(allocated["attempt"], f"{len(events):012d}.json").stat().st_mtime
        count += 1
    # Explicit store and human mode follow the same lifecycle, without JSONL.
    case, cfg, env, _ = fixture()
    result = call(case, cfg, env, journal=True, human=True, extra=("--observation-store", str(case / "explicit")))
    assert result.returncode == 0 and "Stage execution: completed" in result.stdout and not result.stdout.startswith("{"), result.stderr
    assert len(list((case / "explicit").glob("*/000000000001.json"))) == 1
    count += 1
    for mode, extra in (("host_mismatch", ()), ("success", ("--through", "invalid-stage")),
                        ("success", ("--checkpoint", str(root / "missing-checkpoint")))):
        case, cfg, env, _ = fixture(mode)
        result = call(case, cfg, env, journal=True, extra=extra)
        assert result.returncode == 2, result.stderr
        allocated, terminal = [json.loads(line) for line in result.stdout.splitlines()]
        assert terminal["event"] == "observation_terminal" and terminal["recording_error"] is None
        state, _ = fo.load(allocated["attempt"])
        assert state["outcome"]["status"] == "failed" and Path(state["preflight_record"]).is_file()
        if extra:
            assert not (case / "preparation-events.jsonl").exists()
        else:
            check_report_references(cfg, state, "failed")
        count += 1
    # Receipt is flushed before a deliberately blocked probe; real SIGTERM survives.
    case, cfg, env, _ = fixture("probe_timeout")
    process = call(case, cfg, env, journal=True, live=True)
    allocation = json.loads(process.stdout.readline())
    assert fo.inspect(allocation["attempt"])["writer_active"] is True
    deadline = time.monotonic() + 5
    while not (case / "preparation-events.jsonl").exists():
        assert time.monotonic() < deadline
        time.sleep(0.01)
    process.send_signal(signal.SIGTERM)
    stdout, stderr = process.communicate(timeout=15)
    assert process.returncode == 143, stderr
    state, _ = fo.load(allocation["attempt"])
    assert state["outcome"]["status"] == "interrupted" and not fo.inspect(allocation["attempt"])["writer_active"]
    check_report_references(cfg, state, "interrupted")
    count += 1
    # Published checkpoint survives a journal promotion conflict; no unearned finish.
    case, cfg, env, _ = fixture()
    env["JOURNAL_COLLISION"] = "1"
    result = call(case, cfg, env, journal=True)
    assert result.returncode == 2, result.stderr
    allocated, terminal = [json.loads(line) for line in result.stdout.splitlines()]
    assert terminal["recording_error"] and terminal["execution_file"]
    summary = json.loads(Path(terminal["execution_file"]).read_text())
    assert summary["status"] == "failed" and len(summary["artifacts"]) == 1
    directory = Path(allocated["attempt"])
    assert (directory / "000000000005.json").read_text() == "retained conflict"
    assert not (directory / "000000000006.json").exists()
    diagnostics = json.loads(next(Path(cfg["workspace"]).glob("diagnostics-*.json")).read_text())
    assert diagnostics["primary"]["point"] == "published", diagnostics
    count += 1
    case, cfg, env, _ = fixture()
    env.update(JOURNAL_COLLISION="1", SERVICE_FIXTURE_MODE="exit17")
    result = call(case, cfg, env, journal=True)
    assert result.returncode == 17, result.stderr
    allocated, terminal = [json.loads(line) for line in result.stdout.splitlines()]
    assert terminal["exit_code"] == 17 and terminal["recording_error"]
    summary = json.loads(Path(terminal["execution_file"]).read_text())
    assert summary["exit_code"] == 17 and not summary.get("artifacts")
    count += 1
    for fault in ("PUBLICATION_STORAGE_FAULT", "EXECUTION_STORAGE_FAULT"):
        case, cfg, env, _ = fixture()
        env[fault] = "1"
        result = call(case, cfg, env, journal=True)
        assert result.returncode == 2, result.stderr
        allocated, terminal = [json.loads(line) for line in result.stdout.splitlines()]
        state, events = fo.load(allocated["attempt"])
        assert state["outcome"]["status"] == "failed" and not fo.inspect(allocated["attempt"])["writer_active"]
        diagnostics = json.loads(Path(allocated["attempt"], "diagnostics.json").read_text())
        if fault == "PUBLICATION_STORAGE_FAULT":
            assert not state["artifacts"] and all(e["event"] != "published" for e in events)
            assert diagnostics["primary"]["point"] == "publish", diagnostics
            assert Path(cfg["checkpoint_store"]).read_text() == "retained storage obstruction"
        else:
            assert terminal["event"] == "observation_terminal" and terminal["execution_file"] is None
            assert diagnostics["primary"]["point"] == "persist", diagnostics
        count += 1
    result = subprocess.run([str(cli), "--help"], capture_output=True, text=True)
    assert result.returncode == 0 and "journal" in result.stdout.lower()
    result = subprocess.run([str(cli)], capture_output=True, text=True)
    assert result.returncode == 2 and "--bundle" in result.stderr
    count += 2
    print(f"stage preparation: {count} source/installed API and pipeline checks passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--installed", action="store_true")
    parser.add_argument("--cli", type=Path, default=Path("_build/default/bin/experimental_stages.exe"))
    parser.add_argument("--consumer", type=Path, default=Path("_build/default/test/stage_preparation_consumer.exe"))
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="stage-preparation-", dir="/tmp/opencode") as tmp:
        root = Path(tmp)
        fixtures = root / "fixtures"
        fixtures.mkdir()
        for name in ("stage_preparation_engine.py", "segment_service_engine.py", "segment_service_fixture.py", "bridge_protocol_fixture.py"):
            shutil.copyfile(repo / "test" / name, fixtures / name)
        if not args.installed:
            verify(args.cli.resolve(), args.consumer.resolve(), repo / "flow/hardcaml_asic_flow", root, fixtures)
            return
        prefix = root / "prefix"
        from reference_harness import installed_prefix
        installed_prefix(repo, prefix)
        consumer = root / "consumer"
        consumer.mkdir()
        shutil.copyfile(repo / "test/stage_preparation_consumer.ml", consumer / "stage_preparation_consumer.ml")
        (consumer / "dune-project").write_text("(lang dune 3.17)\n(name installed_preparation_consumer)\n")
        (consumer / "dune").write_text("(executable (name stage_preparation_consumer) (libraries hardcaml_asic.execution unix))\n")
        env = dict(os.environ, OCAMLPATH=str(prefix / "lib") + ":" + os.environ.get("OCAMLPATH", ""))
        subprocess.run(["dune", "build", "-j20", "stage_preparation_consumer.exe"], cwd=consumer, env=env, check=True)
        auditing = True
        def audit(event, values):
            if auditing and event == "open" and isinstance(values[0], (str, bytes, os.PathLike)):
                path = Path(os.fsdecode(values[0])).resolve()
                if path.is_relative_to(repo):
                    raise AssertionError("checkout read: " + str(path))
        sys.addaudithook(audit)
        try:
            verify(prefix / "bin/hardcaml-asic-experimental-stages", consumer / "_build/default/stage_preparation_consumer.exe",
                   prefix / "lib/hardcaml_asic/flow/hardcaml_asic_flow", root, fixtures, installed=True)
        finally:
            auditing = False
        print("installed prefix discovery and independently linked preparation consumer passed with checkout reads denied")


if __name__ == "__main__":
    main()
