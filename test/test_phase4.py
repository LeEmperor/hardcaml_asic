"""Runner and collection fixtures require no PDK or licensed tools."""

import contextlib
import io
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock


sys.dont_write_bytecode = True
# The modules under test are the ones Dune installs: `flow/hardcaml_asic_flow/`
# is put on the path and imported as a regular package, so these suites cover the
# installed implementation rather than a checkout-only copy of it.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "flow"))
from hardcaml_asic_flow import phase4  # noqa: E402


class RunnerTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bundle = self.root / "bundle"
        self.bundle.mkdir()
        (self.bundle / "src").mkdir()
        (self.bundle / "src/config.json").write_text("{}\n")
        self.manifest = {
            "schema_version": 1,
            "adapter": "LibreLane",
            "identity": "build-1",
            "top_module": "fixture_top",
            "files": [],
            "requested_tools": {"librelane": "1.2.3", "python": "3.11"},
            "target": {"technology": "ihp-sg13cmos5l", "external_references": []},
        }
        (self.bundle / "manifest.json").write_text(json.dumps(self.manifest))
        self.args = SimpleNamespace(
            bundle=self.bundle,
            runs=self.root / "runs",
            stage="synthesis",
            support_tools=self.root / "tools",
            pdk_root=self.root / "pdk",
            python=self.root / "venv/bin/python",
            allow_python_mismatch=False,
            native=True,
        )

    def ready(self):
        return {
            "ready": True,
            "issues": [],
            "waivers": [],
            "requested": self.manifest["requested_tools"],
            "actual": {"python": "3.11.9", "librelane": "1.2.3"},
        }

    def test_structured_outcome_and_actual_preflight_are_persisted(self):
        decision = self.ready()
        with mock.patch.object(phase4, "preflight", return_value=decision), \
             mock.patch.object(phase4, "run_logged", return_value=0):
            outcome = phase4.run(self.args)
        self.assertIsInstance(outcome, phase4.RunOutcome)
        self.assertTrue(outcome.run_dir.is_absolute())
        self.assertTrue(outcome.run_record.is_absolute())
        self.assertEqual(outcome.run_record, outcome.run_dir / "run.json")
        self.assertEqual((outcome.status, outcome.exit_code), ("completed", 0))
        record = phase4.read_json(outcome.run_record)
        self.assertEqual(phase4.read_json(outcome.run_dir / "preflight.json"), decision)
        self.assertEqual(record["environment"], decision)

    def test_missing_manifest_fails_before_allocation(self):
        (self.bundle / "manifest.json").unlink()
        with self.assertRaises(FileNotFoundError):
            phase4.run(self.args)
        self.assertFalse(self.args.runs.exists())

    def test_failed_and_interrupted_attempts_keep_machine_readable_identity(self):
        cases = (
            (RuntimeError("flow failed"), "failed", 1, None),
            (phase4.FlowInterrupted(signal.SIGINT), "interrupted", 130, "SIGINT"),
            (phase4.FlowInterrupted(signal.SIGTERM), "interrupted", 143, "SIGTERM"),
        )
        for error, status, code, interrupted_by in cases:
            with self.subTest(status=status, code=code):
                with mock.patch.object(phase4, "preflight", return_value=self.ready()), \
                     mock.patch.object(phase4, "run_logged", side_effect=error):
                    outcome = phase4.run(self.args)
                self.assertEqual((outcome.status, outcome.exit_code), (status, code))
                record = phase4.read_json(outcome.run_record)
                self.assertEqual(record["status"], status)
                if interrupted_by:
                    self.assertEqual(record["interrupted_by"], interrupted_by)

    def test_standalone_adapter_prints_only_the_run_record_path(self):
        with mock.patch.object(phase4, "preflight", return_value=self.ready()), \
             mock.patch.object(phase4, "run_logged", return_value=0):
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(phase4.execute(self.args), 0)
        lines = stdout.getvalue().splitlines()
        self.assertEqual(len(lines), 1)
        self.assertTrue(Path(lines[0]).is_file())

    def test_run_logged_terminates_and_waits_for_child_group(self):
        process = mock.MagicMock()
        process.pid = 4321
        process.wait.side_effect = [phase4.FlowInterrupted(signal.SIGTERM), 143]
        process.__enter__.return_value = process
        process.__exit__.return_value = False
        record = {"commands": []}
        record_path = self.root / "record.json"
        with mock.patch.object(phase4.subprocess, "Popen", return_value=process), \
             mock.patch.object(phase4.os, "killpg") as killpg:
            with self.assertRaises(phase4.FlowInterrupted):
                phase4.run_logged(["tool"], self.root, os.environ.copy(),
                                  self.root / "log", record, record_path)
        killpg.assert_called_once_with(4321, signal.SIGTERM)
        self.assertEqual(process.wait.call_count, 2)

    def test_atomic_save_preserves_existing_record_on_publication_failure(self):
        path = self.root / "results.json"
        path.write_text("old evidence\n")
        with mock.patch.object(phase4.os, "replace", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                phase4.save(path, {"new": "partial"})
        self.assertEqual(path.read_text(), "old evidence\n")
        self.assertEqual(list(self.root.glob(".results.json.*")), [])


class PostcheckTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.run_dir = self.root / "run"
        flow = self.run_dir / "project/runs/asic/final"
        (flow / "gds").mkdir(parents=True)
        (flow / "nl").mkdir()
        (flow / "gds/fixture_top.gds").write_text("gds\n")
        (flow / "nl/fixture_top.nl.v").write_text("module fixture_top; endmodule\n")
        (self.run_dir / "project/manifest.json").write_text(json.dumps({
            "top_module": "fixture_top",
        }))
        (self.run_dir / "run.json").write_text(json.dumps({
            "run_id": "attempt-1",
            "build_identity": "build-1",
            "status": "completed",
            "completed_stage": "full",
            "outputs": {"flow": "project/runs/asic"},
            "environment": {"requested": {"librelane": "1.2.3"}},
        }))
        self.support = self.root / "support"
        (self.support / "precheck").mkdir(parents=True)
        # The shape that matters is the pinned fetchTarball: postcheck reads the
        # nixpkgs revision out of this file rather than out of a channel.
        self.nixpkgs = "https://github.com/NixOS/nixpkgs/archive/fixture-revision.tar.gz"
        (self.support / "precheck/default.nix").write_text(
            'let pkgs = import (fetchTarball "%s") {}; in pkgs.mkShell {}\n'
            % self.nixpkgs)
        (self.support / "precheck/tool-versions.json").write_text(json.dumps({
            "klayout": "0.28.17",
        }))
        (self.support / "tech").mkdir()
        self.pdk = self.root / "pdk"
        cells = self.pdk / "ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog"
        cells.mkdir(parents=True)
        (cells / "sg13cmos5l_udp.v").write_text("\n")
        (cells / "sg13cmos5l_stdcell.v").write_text("\n")
        io_model = self.pdk / "ihp-sg13cmos5l/libs.ref/sg13cmos5l_io/verilog"
        io_model.mkdir(parents=True)
        (io_model / "sg13cmos5l_io.v").write_text("\n")
        self.testbench = self.root / "custom_tb.v"
        self.testbench.write_text("module memory_tb; endmodule\n")
        self.precheck_python = self.root / "precheck-python"
        self.precheck_python.write_text("\n")
        self.args = SimpleNamespace(
            run_dir=self.run_dir,
            support_tools=self.support,
            pdk_root=self.pdk,
            precheck_python=self.precheck_python,
            testbench=self.testbench,
            testbench_top="memory_tb",
        )
        self.probes = ["KLayout 0.28.17", "0.28.17", "image-id", "Icarus 12"]

    def test_missing_input_fails_before_check_allocation(self):
        self.testbench.unlink()
        with self.assertRaises(phase4.PrerequisiteError):
            phase4.check(self.args)
        self.assertFalse((self.run_dir / "checks").exists())

    def test_explicit_non_example_top_is_forwarded_and_recorded(self):
        with mock.patch.object(phase4, "command_output", side_effect=self.probes), \
             mock.patch.object(phase4, "run_logged", return_value=0) as run_logged:
            outcome = phase4.check(self.args)
        self.assertEqual(outcome.exit_code, 0)
        compile_command = run_logged.call_args_list[1].args[0]
        self.assertEqual(compile_command[compile_command.index("-s") + 1], "memory_tb")
        record_path = next((self.run_dir / "checks").glob("*/postcheck.json"))
        self.assertEqual(phase4.read_json(record_path)["inputs"]["testbench_top"],
                         "memory_tb")

    def test_nixpkgs_pin_comes_from_the_pinned_collateral_or_is_absent(self):
        pinned = self.support / "precheck/default.nix"
        self.assertEqual(phase4.nixpkgs_pin(pinned), f"nixpkgs={self.nixpkgs}")
        # No pin in the file means no search path: an empty NIX_PATH would be a
        # worse answer than nix's own diagnostic, so the caller leaves it alone.
        unpinned = self.root / "unpinned.nix"
        unpinned.write_text("{ pkgs ? import <nixpkgs> {} }: pkgs.mkShell {}\n")
        self.assertIsNone(phase4.nixpkgs_pin(unpinned))

    def test_precheck_shell_environment_carries_the_pinned_nixpkgs(self):
        """Both nix-shell invocations see <nixpkgs> from the copied default.nix."""
        probes = []

        def record(argv, cwd=None, env=None):
            probes.append((argv, env))
            return self.probes[len(probes) - 1]

        with mock.patch.object(phase4, "command_output", side_effect=record), \
             mock.patch.object(phase4, "run_logged", return_value=0) as run_logged:
            outcome = phase4.check(self.args)
        self.assertEqual(outcome.exit_code, 0)
        klayout_argv, klayout_env = probes[0]
        self.assertEqual(klayout_argv[0], "nix-shell")
        self.assertEqual(klayout_env["NIX_PATH"], f"nixpkgs={self.nixpkgs}")
        logged_nix_shell = [call for call in run_logged.call_args_list
                            if call.args[0][0] == "nix-shell"]
        self.assertEqual(len(logged_nix_shell), 1)
        self.assertEqual(logged_nix_shell[0].args[2]["NIX_PATH"],
                         f"nixpkgs={self.nixpkgs}")

    def test_an_unpinned_precheck_shell_leaves_nix_path_alone(self):
        (self.support / "precheck/default.nix").write_text(
            "{ pkgs ? import <nixpkgs> {} }: pkgs.mkShell {}\n")
        seen = []

        def record(argv, cwd=None, env=None):
            seen.append(env)
            return self.probes[len(seen) - 1]

        # A NIX_PATH the caller already exported is not this test's subject; the
        # claim is only that an unpinned shell adds none.
        environment = {name: value for name, value in os.environ.items()
                       if name != "NIX_PATH"}
        with mock.patch.object(phase4, "command_output", side_effect=record), \
             mock.patch.object(phase4, "run_logged", return_value=0), \
             mock.patch.dict(phase4.os.environ, environment, clear=True):
            phase4.check(self.args)
        self.assertNotIn("NIX_PATH", seen[0])

    def test_interrupted_postcheck_is_finalized_with_signal_status(self):
        with mock.patch.object(phase4, "command_output", side_effect=self.probes), \
             mock.patch.object(phase4, "run_logged",
                               side_effect=phase4.FlowInterrupted(signal.SIGTERM)):
            outcome = phase4.check(self.args)
        self.assertEqual(outcome.exit_code, 143)
        record_path = next((self.run_dir / "checks").glob("*/postcheck.json"))
        record = phase4.read_json(record_path)
        self.assertEqual(record["status"], "interrupted")
        self.assertEqual(record["interrupted_by"], "SIGTERM")
        self.assertIsNotNone(record["ended_at"])


class CollectorTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "project/runs/asic").mkdir(parents=True)
        (self.root / "run.json").write_text(json.dumps({
            "run_id": "attempt-1", "build_identity": "build-1", "status": "completed",
            "requested_stage": "full", "completed_stage": "full",
            "outputs": {"flow": "project/runs/asic"},
            "environment": {"actual": {"librelane": "3.1.0.dev3"}},
        }))

    def put(self, relative, text):
        path = self.root / "project/runs/asic" / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def test_complete(self):
        self.put("06-yosys-synthesis/reports/stat.json", json.dumps({
            "design": {"area": 123.5, "sequential_area": 40,
                       "num_cells": 15, "num_cells_by_type": {"sg13cmos5l_dfrbpq_1": 5}}
        }))
        self.put("final/metrics.csv", "timing__setup__ws__corner:slow,0.3\n"
                 "timing__hold__ws__corner:fast,0.1\nroute__drc_errors,0\n"
                 "design__lvs_error__count,0\nantenna__violating__nets,0\n"
                 "antenna__violating__pins,0\n")
        self.put("06-yosys-synthesis/state_out.json", json.dumps({
            "metrics": {"design__instance_unmapped__count": 0,
                        "synthesis__check_error__count": 0,
                        "design__inferred_latch__count": 0}}))
        result = phase4.collect(self.root)
        self.assertEqual(result["metrics"]["mapped_area"]["value"], 123.5)
        self.assertEqual(result["metrics"]["setup_slack"]["corner"], "slow")
        self.assertEqual(result["timing_goal"], "pass")
        self.assertEqual(result["checks"]["lvs"]["status"], "pass")
        self.assertEqual(result["mapped_cell_types"]["sg13cmos5l_dfrbpq_1"], 5)
        self.assertEqual(result["synthesis_checks"]["unmapped_instances"]["value"], 0)

    def test_partial_and_absent(self):
        self.put("06-yosys-synthesis/reports/stat.json", json.dumps({
            "design": {"area": 12, "num_cells": 2}}))
        partial = phase4.collect(self.root)
        self.assertEqual(partial["metrics"]["mapped_area"]["value"], 12)
        self.assertIsNone(partial["metrics"]["setup_slack"]["value"])
        self.assertEqual(partial["timing_goal"], "unknown")
        self.assertEqual(partial["checks"]["drc"]["status"], "unknown")
        (self.root / "project/runs/asic/06-yosys-synthesis/reports/stat.json").unlink()
        absent = phase4.collect(self.root)
        self.assertIn("absent", absent["metrics"]["mapped_area"]["unavailable_reason"])

    def test_unconstrained_hold_sentinel(self):
        self.put("final/metrics.csv", "timing__setup__ws__corner:slow,18.0\n"
                 "timing__hold__ws__corner:slow,1.0000000433293989E+39\n")
        result = phase4.collect(self.root)
        hold = result["metrics"]["hold_slack"]
        self.assertIsNone(hold["value"])
        self.assertEqual(hold["unavailable_reason"], "no constrained timing paths reported")
        self.assertEqual(result["timing_unconstrained_modes"], ["hold"])
        self.assertEqual(result["timing_goal"], "pass")
        self.put("final/metrics.csv", "timing__setup__ws__corner:slow,-0.5\n"
                 "timing__hold__ws__corner:slow,1.0000000433293989E+39\n")
        self.assertEqual(phase4.collect(self.root)["timing_goal"], "fail")

    def test_malformed_reports_and_failed_process(self):
        self.put("06-yosys-synthesis/reports/stat.json", "{bad")
        self.put("final/metrics.csv", "timing__setup__ws,not-a-number\ninvalid-row\n")
        record = json.loads((self.root / "run.json").read_text())
        record["status"] = "failed"
        (self.root / "run.json").write_text(json.dumps(record))
        result = phase4.collect(self.root)
        self.assertEqual(result["process_status"], "failed")
        self.assertIsNone(result["metrics"]["mapped_area"]["value"])
        self.assertEqual(len(result["errors"]), 2)


if __name__ == "__main__":
    unittest.main()
