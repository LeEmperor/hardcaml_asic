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


def verify(cli, consumer, package, root, fixtures, installed=False, timing_only=False):
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

    if timing_only:
        report_cli = cli.with_name("experimental_report.exe")
        inspect_cli = cli.with_name("experimental_inspect.exe")
        finalizer = consumer.with_name("finalization_consumer.exe")
        def query(argv):
            p = subprocess.run([str(x) for x in argv], text=True, capture_output=True, timeout=30)
            assert p.returncode == 0, p.stderr
            return json.loads(p.stdout)
        # Real bridge + publisher: stop at routing, then execute only the two
        # adjacent continuations. No repeated STA in the signoff range.
        case, cfg, env, _ = fixture()
        env["STA_COMPLETION_MODE"] = "success"
        result = call(case, cfg, env, through="routing")
        assert result.returncode == 0, result.stderr
        routing = json.loads(result.stdout)
        cfg["checkpoint"] = routing["artifacts"][-1]["path"]
        # Historical routing metadata remains readable but cannot be adopted by
        # the new bridge. No new segment is launched on rejection.
        manifest_path = Path(cfg["checkpoint"]) / "manifest.json"
        original = manifest_path.read_bytes()
        old = json.loads(original)
        old["restart_targets"] = ["signoff"]
        old["compatibility"]["bridge_sha256"] = "e8dc9532c61010ae8699d3a6f27cdfd0d773ff3e24d06f9eefbe2d0f5b2da841"
        old["identity"] = cp.identity({k:v for k,v in old.items() if k != "identity"})
        manifest_path.chmod(0o600)
        manifest_path.write_text(json.dumps(old))
        cp.validate(cfg["checkpoint"], compatibility=old["compatibility"])
        rejected = call(case, cfg, env, through="timing")
        assert rejected.returncode != 0 and "incompatible" in rejected.stderr, rejected.stderr
        manifest_path.write_bytes(original)
        manifest_path.chmod(0o400)
        result = call(case, cfg, env, through="timing")
        assert result.returncode == 0, result.stderr
        timing = json.loads(result.stdout)
        assert [a["boundary"] for a in timing["artifacts"]] == ["timing"]
        segment = json.loads((Path(timing["artifacts"][0]["path"]) / "segment.json").read_text())
        assert segment["from"] == "Odb.RemoveRoutingObstructions"
        assert segment["returned_steps"] == ["Odb.RemoveRoutingObstructions", "OpenROAD.FillInsertion", "OpenROAD.RCX", "OpenROAD.STAPostPNR"]
        project = Path(cfg["workspace"]) / "project"
        assert not (project / "signoff-started").exists()
        cfg["checkpoint"] = timing["artifacts"][-1]["path"]
        result = call(case, cfg, env, through="signoff")
        assert result.returncode == 0, result.stderr
        signoff = json.loads(result.stdout)
        segment = json.loads((Path(signoff["artifacts"][0]["path"]) / "segment.json").read_text())
        assert segment["returned_steps"] == ["OpenROAD.IRDropReport", "Misc.ReportManufacturability"]
        # Both full success and downstream failure retain a frozen Timing source.
        for mode in ("success", "failure", "timing_failure"):
            case, cfg, env, _ = fixture()
            env["STA_COMPLETION_MODE"] = mode
            result = call(case, cfg, env, through="signoff")
            assert (result.returncode == 0) == (mode == "success"), result.stderr
            summary = json.loads(result.stdout)
            assert summary["plan"]["schema_version"] == 4
            assert len(summary["artifacts"]) == (7 if mode == "success" else 5 if mode == "timing_failure" else 6)
            execution = Path(cfg["workspace"]) / ("execution-" + summary["attempt_id"] + ".json")
            report = query([report_cli, "--target", execution, "--json"])
            analysis = report["timing_analysis"]
            assert analysis["stage"] == "timing" and analysis["status"] == "completed"
            assert analysis["duration"]["seconds"] == 1.575
            assert analysis["schema_version"] == 2
            assert analysis["enclosing_status"] == ("failed" if mode == "timing_failure" else "running")
            if mode != "timing_failure":
                assert Path(analysis["execution_file"]).read_bytes() != execution.read_bytes()
            index = query([inspect_cli, "--execution", execution, "--domain", "timing", "--stage", "timing", "--expected-digest", analysis["source_digest"], "--json"])
            assert index["rows"] and index["analysis_digest"] == analysis["source_digest"]
            public_index = query([cli.with_name("flow_cli.exe"), "inspect", execution, "--domain", "timing", "--stage", "timing", "--expected-digest", analysis["source_digest"], "--json"])
            assert public_index == index
            (case / "report.json").write_text(json.dumps(report, indent=2))
            if mode == "failure":
                saved = execution.read_bytes()
                changed = json.loads(saved)
                changed["occurrences"][-2]["duration_seconds"] += 1
                execution.write_text(json.dumps(changed))
                stale = subprocess.run([str(report_cli), "--target", str(execution), "--json"], capture_output=True, text=True)
                assert stale.returncode == 2 and "timing prefix source changed" in stale.stderr
                execution.write_bytes(saved)
                wrong_stage = subprocess.run([str(inspect_cli), "--execution", str(execution), "--domain", "timing", "--stage", "signoff", "--expected-digest", analysis["source_digest"], "--json"], capture_output=True, text=True)
                assert wrong_stage.returncode == 2
            if mode == "success":
                p = subprocess.run([str(finalizer), "select", str(execution)], text=True, capture_output=True)
                assert p.returncode == 0, p.stderr
            elif mode == "failure":
                assert summary["occurrences"][-2]["status"] == "completed"
                assert summary["occurrences"][-1]["status"] == "failed"
            else:
                assert summary["occurrences"][-2]["status"] == "failed"
                assert summary["occurrences"][-1]["status"] == "unreached"
        case, cfg, env, _ = fixture()
        env["STA_COMPLETION_MODE"] = "timeout"
        process = call(case, cfg, env, through="signoff", live=True, extra=("--timeout", "30"))
        deadline = time.monotonic() + 30
        while not (Path(cfg["workspace"]) / "project/signoff-started").exists():
            assert process.poll() is None and time.monotonic() < deadline
            time.sleep(.02)
        execution = next(p for p in Path(cfg["workspace"]).glob("execution-*.json") if ".json." not in p.name)
        report = query([report_cli, "--target", execution, "--json"])
        assert report["execution"]["status"] == "running"
        digest = report["timing_analysis"]["source_digest"]
        process.send_signal(signal.SIGTERM)
        stdout, stderr = process.communicate(timeout=20)
        assert process.returncode == 143, stderr
        assert query([report_cli, "--target", execution, "--json"])["timing_analysis"]["source_digest"] == digest
        case, cfg, env, _ = fixture()
        env["STA_COMPLETION_MODE"] = "success"
        result = call(case, cfg, env, through="timing")
        assert result.returncode == 0, result.stderr
        summary = json.loads(result.stdout)
        assert len(summary["occurrences"]) == len(summary["artifacts"]) == 6
        assert summary["plan"]["stages"][-1] == "timing"
        execution = Path(cfg["workspace"]) / ("execution-" + summary["attempt_id"] + ".json")
        report = query([report_cli, "--target", execution, "--json"])
        assert report["completion"]["requested"] == report["completion"]["physical"] == "timing"
        assert report["timing_analysis"]["stage"] == "timing" and report["timing_analysis"]["status"] == "completed"
        assert not (Path(cfg["workspace"]) / "project/signoff-started").exists()
        print("Executable Timing: stop-at-routing, Routing->Timing->Signoff, seven-stage selection, exact inspection, live signoff/cancellation and signoff-failure evidence passed")
        return
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
    for mode in ('synth_missing', 'synth_type', 'synth_default', 'synth_domain',
                 'synth_domain_missing', 'synth_bool_type', 'synth_bool_default'):
        rejected(mode)
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
    # Actual terminal transport cleanup -> persisted observation, independent of
    # publication. The bridge API is a fixture; provider/supervisor/journal are real.
    for sta_mode in ("success", "failure", "timeout", "cancel"):
        case, cfg, env, _ = fixture()
        env["STA_COMPLETION_MODE"] = "timeout" if sta_mode == "cancel" else sta_mode
        if sta_mode == "cancel":
            process = call(case, cfg, env, journal=True, through="signoff", live=True)
            deadline = time.monotonic() + 60
            while not (Path(cfg["workspace"]) / "project/signoff-started").exists():
                if process.poll() is not None:
                    stdout, stderr = process.communicate()
                    raise AssertionError(("STA cancellation fixture exited before marker", process.returncode, stdout, stderr))
                if time.monotonic() >= deadline:
                    process.terminate()
                    stdout, stderr = process.communicate(timeout=20)
                    raise AssertionError(("STA cancellation fixture marker deadline", stdout, stderr))
                time.sleep(.01)
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=20)
            result = subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)
            assert result.returncode == 143, result.stderr
        else:
            result = call(case, cfg, env, journal=True, through="signoff")
        assert (result.returncode == 0) == (sta_mode == "success"), result.stderr
        allocated = json.loads(result.stdout.splitlines()[0])
        state, _ = fo.load(allocated["attempt"])
        execution_path = Path(cfg["workspace"]) / ("execution-" + allocated["stream_id"] + ".json")
        summary = json.loads(execution_path.read_text())
        analysis_path = Path(str(execution_path) + ".timing-source.timing-analysis.json")
        assert analysis_path.is_file(), result.stderr
        analysis = json.loads(analysis_path.read_text())
        assert analysis["status"] == "completed" and analysis["duration"]["seconds"] == 1.575, analysis
        assert analysis["timing_goal"] == "pass" and analysis["attempt_id"] == summary["attempt_id"]
        assert analysis["stage"] == "timing" and analysis["enclosing_status"] == "running"
        assert summary["status"] == state["outcome"]["status"]
        assert len(summary["artifacts"]) == (7 if sta_mode == "success" else 6)
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
