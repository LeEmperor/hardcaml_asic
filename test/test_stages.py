"""Negative handoff/publication and lifecycle tests; no physical-tool claims."""

import json
import io
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, os.environ.get("STAGE_TEST_PACKAGE_ROOT",
                               str(Path(__file__).resolve().parents[1] / "flow")))
from hardcaml_asic_flow import checkpoint as cp, cli, execution_plan as plans, runner, stages, backend_protocol


EXPECTED_STAGE_SEQUENCE = ("synthesis", "floorplan", "placement", "cts", "routing", "timing", "signoff")


class StagesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.project = self.root / "project"
        self.project.mkdir()
        self.store = self.root / "checkpoints"
        self.store.mkdir()
        self.bridge = self.project / "bridge/librelane_bridge.py"
        self.bridge.parent.mkdir()
        shutil.copyfile(Path(stages.__file__).with_name("librelane_bridge.py"), self.bridge)
        shutil.copyfile(Path(stages.__file__).with_name("backend_protocol.py"),
                        self.bridge.with_name("backend_protocol.py"))
        self.constraints = self.project / "top.sdc"
        self.constraints.write_text("create_clock -period 10 [get_ports clk]")
        self.config = self.project / "config.json"
        self.config.write_text('{"CLOCK_PERIOD":10}')
        self.collateral = self.root / "technology.lef"
        self.collateral.write_text("VERSION 5.8 ;")
        self.compat = {"target": "fixture", "binding": {"image_identity": {"image_id": plans.TESTED_IMAGE}},
                       "bridge_sha256": cp.digest(self.bridge), "project": str(self.project)}
        self.launches = []

    def tearDown(self):
        for p in self.root.rglob("*"):
            p.chmod(0o755 if p.is_dir() else 0o644)
        self.tmp.cleanup()

    def candidate(self, path, boundary="synthesis", *, missing=False, status="completed"):
        path.mkdir(parents=True)
        output = self.root / (path.name + "-tool-output")
        output.mkdir()
        view = output / "same-name.v"
        view.write_text("module fixture; endmodule")
        other = output / "other"
        other.mkdir()
        (other / "same-name.v").write_text("header")
        state = {"nl": str(view), "json_h": str(other / "same-name.v"),
                 "metrics": {"backend_nonfinite": float("inf")},
                 "sdf": {"corner": [str(view), None]}}
        if boundary != "synthesis":
            state.update(odb=str(view), def_=str(view))
            state["def"] = state.pop("def_")
        if missing:
            state["nl"] = str(output / "absent.v")
        (path / "state.json").write_text(json.dumps(state))
        (path / "resolved.json").write_text('{"CLOCK_PERIOD":10}')
        (path / "closure.json").write_text(json.dumps({str(p): cp.file_record(p)
                                                       for p in (self.constraints, self.config, self.collateral)}))
        (path / "segment.json").write_text(json.dumps({
            "status": status, "boundary": boundary, "bridge_sha256": self.compat["bridge_sha256"],
            "metrics": {"backend_nonfinite": {"availability": "unavailable", "raw": "Infinity"}}}))
        return path

    def publish(self, boundary="synthesis"):
        candidate = self.candidate(self.root / "candidate", boundary)
        return cp.publish(candidate, self.store, compatibility=self.compat, boundary=boundary)

    def adapter(self, *, initial=None, code=0, missing=False):
        def launch(bridge, request, tag):
            self.launches.append(tag)
            raw = json.loads(request.read_text())
            backend_protocol.validate_request(raw)
            if raw["operation"] == "execute_segment":
                self.candidate(Path(raw["candidate"]), raw["boundary"], missing=missing)
            backend_protocol.write_reply(raw)
            return code
        return stages.SegmentAdapter(project=self.project, pdk_root=self.root,
                                     compatibility=self.compat, launch=launch,
                                     checkpoint_store=self.store, initial_checkpoint=initial)

    def test_recipe_roundtrip_and_capabilities(self):
        self.assertEqual(plans.STAGE_ORDER, EXPECTED_STAGE_SEQUENCE)
        for endpoint in plans.BOUNDARIES:
            plan = plans.resolve_stages(endpoint)
            self.assertEqual(plans.StagePlan.from_dict(plan.as_dict()), plan)
        caps = plans.boundary_capabilities()
        self.assertEqual(caps["placement"]["restart_targets"], ["cts"])
        self.assertEqual(caps["routing"]["restart_targets"], ["timing"])
        self.assertEqual(caps["timing"]["restart_targets"], ["signoff"])
        self.assertFalse(caps["signoff"]["restart_supported"])
        for raw in ({"endpoint": "unknown", "resume": False, "schema_version": 2},
                    {"endpoint": "synthesis", "resume": True, "schema_version": 2},
                    {"endpoint": [], "resume": False, "schema_version": 2},
                    {"endpoint": "placement", "resume": 1, "schema_version": 2},
                    {"endpoint": "placement", "resume": False, "schema_version": True}):
            with self.assertRaises(ValueError):
                plans.StagePlan.from_dict(raw)

    def test_publication_is_independent_readonly_complete_and_not_acceptance(self):
        artifact = self.publish()
        path = Path(artifact["path"])
        manifest = cp.validate(path, compatibility=self.compat, restart=True)
        self.assertEqual(manifest["acceptance"], "not_evaluated")
        self.assertFalse((path / "state.json").stat().st_mode & 0o222)
        state = json.loads((path / "state.json").read_text())
        self.assertNotEqual(state["nl"], state["json_h"])
        # Delete all original output paths, then validate copied nested views.
        shutil.rmtree(self.root / "candidate-tool-output")
        cp.validate(path, compatibility=self.compat, restart=True)
        json.dumps(manifest, allow_nan=False)

    def test_missing_views_publish_nothing(self):
        candidate = self.candidate(self.root / "candidate", missing=True)
        with self.assertRaises(ValueError):
            cp.publish(candidate, self.store, compatibility=self.compat, boundary="synthesis")
        self.assertEqual(list(self.store.iterdir()), [])

    def test_public_json_rejects_duplicate_keys_and_exponent_overflow(self):
        artifact = self.publish()
        manifest_path = Path(artifact["path"]) / "manifest.json"
        original = manifest_path.read_text()
        manifest_path.chmod(0o644)
        # Last-key-wins parsing used to accept these exact bytes as valid,
        # despite an ambiguous boundary declaration and unchanged identity.
        manifest_path.write_text('{"boundary":"signoff",' + original[1:])
        with self.assertRaisesRegex(cp.CheckpointError, "duplicate"):
            cp.validate(artifact["path"], compatibility=self.compat)
        for raw in ('{"metric":1e999}', '{"metric":NaN}'):
            manifest_path.write_text(raw)
            with self.assertRaisesRegex(cp.CheckpointError, "nonfinite"):
                cp.read(manifest_path)

    def test_cli_duplicate_recipe_rejected_before_preparation(self):
        recipe = self.root / "recipe.json"
        recipe.write_text('{"schema_version":3,"stages":["signoff"],'
                          '"stages":["synthesis"],"initial_boundary":null}')
        from hardcaml_asic_flow import ocaml_backend
        result = subprocess.run([str(ocaml_backend.binary("stages")), "--bundle", str(self.root / "bundle"), "--plan", str(recipe),
                              "--support-tools", str(self.root / "tt"), "--pdk-root", str(self.root / "pdk"),
                              "--python", sys.executable, "--workspace", str(self.root / "workspace"),
                              "--checkpoint-store", str(self.root / "workspace/checkpoints"),
                              "--evidence-root", str(self.root / "evidence"), "--json"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("duplicate", result.stderr)
        self.assertFalse((self.root / "workspace").exists())

    def test_failed_segment_cannot_publish(self):
        candidate = self.candidate(self.root / "candidate", status="failed")
        with self.assertRaises(ValueError):
            cp.publish(candidate, self.store, compatibility=self.compat, boundary="synthesis")
        self.assertEqual(list(self.store.iterdir()), [])

    def test_nonfinite_public_metric_is_rejected_without_ready_publication(self):
        candidate = self.candidate(self.root / "candidate")
        report_path = candidate / "segment.json"
        report = cp.read(report_path)
        report["metrics"]["invalid"] = {"availability": "available", "value": float("inf")}
        report_path.write_text(json.dumps(report))
        with self.assertRaises(ValueError):
            cp.publish(candidate, self.store, compatibility=self.compat, boundary="synthesis")
        self.assertEqual(list(self.store.iterdir()), [])

    def test_failed_atomic_promotion_leaves_no_ready_or_partial_checkpoint(self):
        candidate = self.candidate(self.root / "candidate")
        with patch.object(cp.os, "rename", side_effect=OSError("publication fault")):
            with self.assertRaises(OSError):
                cp.publish(candidate, self.store, compatibility=self.compat, boundary="synthesis")
        self.assertEqual(list(self.store.iterdir()), [])

    def test_publication_collision_preserves_existing_user_checkpoint(self):
        candidate = self.candidate(self.root / "candidate")
        existing = self.store / "synthesis-fixed"
        existing.mkdir()
        sentinel = existing / "user-work"
        sentinel.write_text("preserve")
        private = self.store / ".publishing-fixed"
        private.mkdir()
        with patch.object(cp.tempfile, "mkdtemp", return_value=str(private)):
            with self.assertRaises(ValueError):
                cp.publish(candidate, self.store, compatibility=self.compat, boundary="synthesis")
        self.assertEqual(sentinel.read_text(), "preserve")
        self.assertFalse(private.exists())

    def test_image_only_dependency_requires_successful_runtime_validation_before_ready(self):
        candidate = self.candidate(self.root / "candidate")
        closure_path = candidate / "closure.json"
        closure = cp.read(closure_path)
        closure["/nix/store/fixture/runtime.sdc"] = {"sha256": "0" * 64, "bytes": 5}
        closure_path.write_text(json.dumps(closure))
        with self.assertRaises(ValueError):
            cp.publish(candidate, self.store, compatibility=self.compat, boundary="synthesis")
        self.assertEqual(list(self.store.iterdir()), [])
        def reject(tmp):
            self.assertTrue(tmp.name.startswith(".publishing-"))
            self.assertFalse(any(p.name.startswith("synthesis-") for p in self.store.iterdir()))
            raise ValueError("runtime SDC hash mismatch")
        with self.assertRaises(ValueError):
            cp.publish(candidate, self.store, compatibility=self.compat, boundary="synthesis",
                       validate_runtime=reject)
        self.assertEqual(list(self.store.iterdir()), [])

    def test_corrupt_or_missing_every_metadata_and_view_is_rejected(self):
        artifact = self.publish()
        path = Path(artifact["path"])
        path.chmod(0o755)
        for directory in path.rglob("*"):
            if directory.is_dir():
                directory.chmod(0o755)
        for name in cp.read(path / "manifest.json")["files"]:
            child = path / name
            original = child.read_bytes()
            child.chmod(0o644)
            child.write_bytes(b"corrupt")
            with self.assertRaises(ValueError, msg=name):
                cp.validate(path, compatibility=self.compat)
            child.write_bytes(original)
            child.unlink()
            with self.assertRaises(ValueError, msg=name):
                cp.validate(path, compatibility=self.compat)
            child.write_bytes(original)

    def test_changed_constraint_rejected_before_any_launch(self):
        artifact = self.publish()
        self.constraints.write_text("different clock")
        adapter = self.adapter(initial=artifact["path"])
        with self.assertRaises(ValueError):
            runner.execute(plans.resolve_stages("placement", resume=True), adapter)
        self.assertEqual(self.launches, [])

    def test_missing_constraint_rejected(self):
        artifact = self.publish()
        self.constraints.unlink()
        with self.assertRaises(ValueError):
            cp.validate(artifact["path"], compatibility=self.compat)

    def test_changed_config_and_collateral_rejected_before_launch(self):
        artifact = self.publish()
        for dependency in (self.config, self.collateral):
            original = dependency.read_text()
            dependency.write_text("changed")
            with self.assertRaises(ValueError):
                self.adapter().run_segment("placement", checkpoint=artifact["path"])
            self.assertEqual(self.launches, [])
            dependency.write_text(original)

    def test_launch_exception_is_failed_and_has_no_ready_fact(self):
        adapter = self.adapter()
        adapter.launch = lambda *args: (_ for _ in ()).throw(OSError("transport failure"))
        result = runner.execute(plans.resolve_stages("floorplan"), adapter)
        self.assertEqual(result.exit_code, 2)
        self.assertEqual(result.artifacts, [])
        self.assertEqual([o.status for o in result.occurrences], ["failed", "unreached"])

    def test_incompatible_target_runtime_bridge_and_workspace(self):
        artifact = self.publish()
        for field in self.compat:
            compat = dict(self.compat, **{field: "changed"})
            with self.assertRaises(ValueError, msg=field):
                cp.validate(artifact["path"], compatibility=compat)

    def test_final_output_is_terminal_not_a_restart_capability(self):
        artifact = self.publish("signoff")
        cp.validate(artifact["path"], compatibility=self.compat)
        with self.assertRaises(ValueError):
            cp.validate(artifact["path"], compatibility=self.compat, restart=True)

    def test_manifest_identity_and_extra_files_are_rejected(self):
        artifact = self.publish()
        path = Path(artifact["path"])
        path.chmod(0o755)
        (path / "extra").write_text("untracked")
        with self.assertRaises(ValueError):
            cp.validate(path, compatibility=self.compat)
        (path / "extra").unlink()
        manifest = path / "manifest.json"
        raw = cp.read(manifest)
        raw["restart_supported"] = False
        manifest.chmod(0o644)
        manifest.write_text(json.dumps(raw))
        with self.assertRaises(ValueError):
            cp.validate(path, compatibility=self.compat)

    def test_shared_runner_composition_and_ready_callback_order(self):
        events = []
        def lifecycle(event, action, occurrence, artifact):
            if artifact:
                cp.validate(artifact["path"], compatibility=self.compat)
                self.assertEqual(occurrence["status"], "running" if event == "published" else "completed")
            events.append((event, artifact))
        result = runner.execute(plans.resolve_stages("placement"), self.adapter(), lifecycle=lifecycle)
        self.assertEqual(result.exit_code, 0)
        self.assertEqual(len(result.artifacts), 3)
        self.assertEqual([e[0] for e in events], ["started", "published", "finished"] * 3)
        self.assertEqual(len(self.launches), 3)
        self.assertNotIn("verdict", result.as_dict())

    def test_failed_process_with_success_looking_files_never_publishes(self):
        result = runner.execute(plans.resolve_stages("placement"), self.adapter(code=7))
        self.assertEqual(result.exit_code, 7)
        self.assertEqual([o.status for o in result.occurrences], ["failed", "unreached", "unreached"])
        self.assertEqual(result.artifacts, [])
        self.assertEqual(list(self.store.iterdir()), [])

    def test_publication_validator_requires_correlated_success_reply(self):
        for mutation in ("missing", "malformed", "mismatched", "version", "failed", "exit"):
            with self.subTest(mutation=mutation):
                def launch(bridge, request_path, tag):
                    raw = backend_protocol.validate_request(backend_protocol.loads(request_path.read_text()))
                    if raw["operation"] == "execute_segment":
                        candidate = self.candidate(Path(raw["candidate"]), raw["boundary"])
                        closure_path = candidate / "closure.json"
                        closure = cp.read(closure_path)
                        closure["/nix/store/fixture/runtime.sdc"] = {"sha256": "0" * 64, "bytes": 5}
                        closure_path.write_text(cp.canonical(closure))
                        backend_protocol.write_reply(raw)
                        return 0
                    reply = backend_protocol.reply(raw)
                    if mutation == "mismatched":
                        reply["request_id"] = "other-call"
                    elif mutation == "version":
                        reply["protocol_version"] = 2
                    elif mutation == "failed":
                        reply.update(outcome="failed", error="backend validation failed", artifacts={})
                    if mutation != "missing":
                        Path(raw["reply_path"]).write_text("{" if mutation == "malformed" else cp.canonical(reply))
                    return 7 if mutation == "exit" else 0
                adapter = self.adapter()
                adapter.launch = launch
                result = runner.execute(plans.resolve_stages("floorplan"), adapter)
                self.assertEqual(result.exit_code, 2)
                self.assertEqual(result.artifacts, [])
                self.assertEqual([o.status for o in result.occurrences], ["failed", "unreached"])
                self.assertEqual(list(self.store.iterdir()), [])

    def test_zero_exit_segment_requires_valid_reply_and_artifact_evidence(self):
        for mutation in ("missing", "malformed", "mismatched", "version", "failed", "evidence"):
            with self.subTest(mutation=mutation):
                adapter = self.adapter()
                original = adapter.launch
                def launch(bridge, request_path, tag):
                    code = original(bridge, request_path, tag)
                    raw = backend_protocol.loads(request_path.read_text())
                    reply_path = Path(raw["reply_path"])
                    reply = backend_protocol.loads(reply_path.read_text())
                    if mutation == "missing":
                        reply_path.unlink()
                    elif mutation == "malformed":
                        reply_path.write_text("{")
                    else:
                        if mutation == "mismatched":
                            reply["request_sha256"] = "0" * 64
                        elif mutation == "version":
                            reply["protocol_version"] = 2
                        elif mutation == "failed":
                            reply.update(outcome="failed", artifacts={}, error="backend failed")
                        else:
                            reply["artifacts"]["state.json"]["sha256"] = "0" * 64
                        reply_path.write_text(cp.canonical(reply))
                    return code
                adapter.launch = launch
                result = runner.execute(plans.resolve_stages("floorplan"), adapter)
                self.assertEqual(result.exit_code, 2)
                self.assertEqual(result.artifacts, [])
                self.assertEqual([o.status for o in result.occurrences], ["failed", "unreached"])
                self.assertEqual(list(self.store.iterdir()), [])

    def test_protocol_support_mutation_rejected_before_launch(self):
        self.bridge.with_name("backend_protocol.py").write_text("raise RuntimeError('changed')")
        result = runner.execute(plans.resolve_stages("synthesis"), self.adapter())
        self.assertEqual(result.exit_code, 2)
        self.assertEqual(self.launches, [])
        self.assertEqual(list(self.store.iterdir()), [])

    def test_interruption_preserves_signal_and_does_not_read_success_reply(self):
        from hardcaml_asic_flow import result_store
        adapter = self.adapter()
        original = adapter.launch
        def interrupt(*args):
            original(*args)  # even a valid completed reply cannot mask cancellation
            raise result_store.FlowInterrupted(15)
        adapter.launch = interrupt
        result = runner.execute(plans.resolve_stages("floorplan"), adapter)
        self.assertEqual(result.exit_code, 143)
        self.assertEqual(result.artifacts, [])
        self.assertEqual([o.status for o in result.occurrences], ["interrupted", "unreached"])
        self.assertEqual(list(self.store.iterdir()), [])

    def test_publication_failure_marks_occurrence_failed_blocks_successor(self):
        result = runner.execute(plans.resolve_stages("floorplan"), self.adapter(missing=True))
        self.assertEqual(result.exit_code, 2)
        self.assertEqual([o.status for o in result.occurrences], ["failed", "unreached"])
        self.assertEqual(len(self.launches), 1)
        self.assertEqual(result.artifacts, [])

    def test_standalone_api_does_not_publish_or_sequence(self):
        adapter = self.adapter()
        result = adapter.run_segment("synthesis")
        self.assertEqual(result.status, "completed")
        self.assertEqual(list(self.store.iterdir()), [])
        self.assertEqual(len(self.launches), 1)
        with self.assertRaises(ValueError):
            adapter.run_segment("placement")

    def test_standalone_resume_uses_shared_runner_and_explicit_handoff(self):
        artifact = self.publish()
        result = runner.execute(plans.resolve_stages("placement", resume=True),
                                self.adapter(initial=artifact["path"]))
        self.assertEqual(result.exit_code, 0)
        self.assertEqual(len(self.launches), 2)

    def test_bridge_mutation_rejected_before_launch(self):
        self.bridge.write_text("changed")
        result = runner.execute(plans.resolve_stages("synthesis"), self.adapter())
        self.assertEqual(result.exit_code, 2)
        self.assertEqual(self.launches, [])

    def test_explicit_sequence_rejects_skips_reordering_repeats_and_wrong_initial(self):
        for names, initial in ((["synthesis", "placement"], None), (["placement", "floorplan"], "floorplan"),
                               (["floorplan", "floorplan"], "synthesis"), (["cts"], "floorplan"),
                               (["signoff"], "signoff"), (["cts"], []), ([], None),
                               (["placement", "cts", "routing", "signoff"], "floorplan"),
                               (["signoff"], "routing")):
            with self.assertRaises(ValueError):
                plans.resolve_sequence(names, initial_boundary=initial)
        plan = plans.resolve_sequence(["placement", "cts", "routing", "timing", "signoff"], initial_boundary="floorplan")
        self.assertEqual(plans.StagePlan.from_dict(plan.as_dict()), plan)
        self.assertEqual(plan.actions[1].requires, ("implementation.placement",))
        self.assertEqual(plan.actions[0].inputs, ("floorplan_checkpoint",))
        self.assertEqual(plan.actions[3].requires, ("implementation.routing",))
        self.assertEqual(plan.actions[4].inputs, ("timing_checkpoint",))
        self.assertEqual(plans.resolve_stages("placement").sequence, ("synthesis", "floorplan", "placement"))
        for raw in ({"schema_version": 3.0, "stages": ["synthesis"], "initial_boundary": None},
                    {"schema_version": 3, "stages": "synthesis", "initial_boundary": None},
                    {"schema_version": 3, "stages": ["synthesis"], "initial_boundary": None, "skip": []}):
            with self.assertRaises(ValueError):
                plans.StagePlan.from_dict(raw)

    def test_only_tested_physical_transitions_can_launch(self):
        for boundary, target in (("floorplan", "cts"), ("placement", "routing"), ("cts", "signoff"),
                                 ("routing", "signoff")):
            candidate = self.candidate(self.root / ("candidate-" + boundary), boundary)
            artifact = cp.publish(candidate, self.store, compatibility=self.compat, boundary=boundary)
            with self.assertRaises(ValueError):
                self.adapter().run_segment(target, checkpoint=artifact["path"])
        self.assertEqual(self.launches, [])

    def test_full_explicit_sequence_and_physical_resume(self):
        execution = runner.execute(plans.resolve_sequence(EXPECTED_STAGE_SEQUENCE), self.adapter())
        self.assertEqual(execution.exit_code, 0)
        self.assertEqual([a["boundary"] for a in execution.artifacts], list(EXPECTED_STAGE_SEQUENCE))
        physical = execution.artifacts[2]
        plan = plans.resolve_sequence(["cts", "routing", "timing", "signoff"], initial_boundary="placement")
        result = runner.execute(plan, self.adapter(initial=physical["path"]))
        self.assertEqual(result.exit_code, 0)
        self.assertEqual([a["boundary"] for a in result.artifacts], ["cts", "routing", "timing", "signoff"])
        with self.assertRaises(ValueError):
            runner.execute(plans.resolve_stages("cts", resume=True), self.adapter(initial=physical["path"]))

    def test_checkpoint_capabilities_and_legacy_not_silently_upgraded(self):
        artifact = self.publish("floorplan")
        path = Path(artifact["path"])
        manifest = cp.validate(path, compatibility=self.compat, restart_to="placement")
        self.assertEqual(manifest["closure_scope"], "path_bound")
        self.assertEqual(manifest["restart_targets"], ["placement"])
        manifest["schema_version"] = 1
        manifest["restart_supported"] = False
        for field in ("restart_targets", "closure_scope", "tested_image_id", "identity"):
            del manifest[field]
        manifest["identity"] = cp.identity(manifest)
        (path / "manifest.json").chmod(0o644)
        (path / "manifest.json").write_text(cp.canonical(manifest))
        cp.validate(path, compatibility=self.compat)
        with self.assertRaises(ValueError):
            cp.validate(path, compatibility=self.compat, restart_to="placement")

    def test_restart_eligibility_is_exact_image_bound(self):
        self.compat["binding"]["image_identity"]["image_id"] = "sha256:untested"
        with self.assertRaises(ValueError):
            self.publish()
        self.assertEqual(list(self.store.iterdir()), [])

    def test_isolated_bridge_and_host_agree_on_boundary_contracts(self):
        import ast
        bridge = Path(stages.__file__).with_name("librelane_bridge.py")
        assignments = {node.targets[0].id: ast.literal_eval(node.value)
                       for node in ast.parse(bridge.read_text()).body
                       if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name)
                       and node.targets[0].id in ("ENDPOINTS", "SUCCESSORS", "RESTART_TARGETS")}
        self.assertEqual(assignments["ENDPOINTS"], plans.BOUNDARIES)
        self.assertEqual(assignments["SUCCESSORS"], plans.SUCCESSORS)
        self.assertEqual(assignments["RESTART_TARGETS"], {k: v for k, v in plans.RESTART_TARGETS.items() if v})


if __name__ == "__main__":
    unittest.main()
