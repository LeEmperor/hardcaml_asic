"""Table-driven P6.3 command-boundary tests; no external tools are executed."""

import contextlib
import io
import json
from pathlib import Path
import subprocess
from types import SimpleNamespace
import sys
import tempfile
import unittest


sys.dont_write_bytecode = True
# The modules under test are the ones Dune installs: `flow/hardcaml_asic_flow/`
# is put on the path and imported as a regular package, so these suites cover the
# installed implementation rather than a checkout-only copy of it.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "flow"))
from hardcaml_asic_flow import cli as flow_cli  # noqa: E402


class Outcome(SimpleNamespace):
    def as_dict(self):
        return {name: str(value) if isinstance(value, Path) else value
                for name, value in vars(self).items()}


class FakeOperations:
    def __init__(self):
        self.calls = []
        self.codes = {}
        self.run_outcome = Outcome(
            run_id="run-1", run_dir=Path("/absolute/run-1"),
            run_record=Path("/absolute/run-1/run.json"), status="completed",
            exit_code=0)
        self.check_outcome = Outcome(
            check_id="check-1", check_dir=Path("/absolute/run-1/checks/check-1"),
            check_record=Path("/absolute/run-1/checks/check-1/postcheck.json"),
            status="completed", exit_code=0)

    def called(self, name):
        return [args for operation, args in self.calls if operation == name]

    def provision(self, args):
        self.calls.append(("provision", args))
        return self.codes.get("provision", 0)

    def preflight(self, args):
        self.calls.append(("preflight", args))
        return self.codes.get("preflight", 0)

    def run(self, args):
        self.calls.append(("run", args))
        return self.run_outcome

    def postcheck(self, args):
        self.calls.append(("postcheck", args))
        return self.check_outcome

    def collect(self, args):
        self.calls.append(("collect", args))
        return self.codes.get("collect", 0)

    def report(self, args):
        self.calls.append(("report", args))
        if not getattr(args, "diagnostics_only", False):
            print("human report")
        return self.codes.get("report", 0)

    def archive(self, args):
        self.calls.append(("archive", args))
        if not getattr(args, "quiet", False):
            print('{"archive": "operation output"}')
        return self.codes.get("archive", 0)


class FlowCliTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.cwd = Path(self.temporary.name)
        self.operations = FakeOperations()

    def invoke(self, argv, *, environ=None):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            try:
                code = flow_cli.main(argv, operations=self.operations,
                                     environ={} if environ is None else environ,
                                     cwd=self.cwd)
            except SystemExit as exc:
                code = exc.code
        return code, stdout.getvalue(), stderr.getvalue()

    def tool_args(self):
        return ["--toolchain", "tools"]

    def test_help_and_invalid_arguments_do_no_work(self):
        cases = (
            ([], 0, "usage:"),
            (["--help"], 0, "usage:"),
            (["bogus"], 2, ""),
            (["run", "bundle", "--runs", "runs"], 2, ""),
            (["run", "bundle", "--stage", "synthesis"], 2, ""),
        )
        before = list(self.cwd.iterdir())
        for argv, expected, text in cases:
            with self.subTest(argv=argv):
                code, stdout, _ = self.invoke(argv)
                self.assertEqual(code, expected)
                if text:
                    self.assertIn(text, stdout)
        self.assertEqual(self.operations.calls, [])
        self.assertEqual(list(self.cwd.iterdir()), before)

    def test_provision_and_check_forwarding_preserve_statuses(self):
        cases = (
            (["provision", "--toolchain", "managed", "--offline", "--no-container"],
             4, (False, True, True), self.cwd / "managed"),
            (["provision", "--check"], 5, (True, False, False), self.cwd / "from-env"),
        )
        for argv, status, flags, root in cases:
            with self.subTest(argv=argv):
                self.operations.codes["provision"] = status
                environment = {"TOOLCHAIN": "from-env"}
                code, _, _ = self.invoke(argv, environ=environment)
                self.assertEqual(code, status)
                args = self.operations.called("provision")[-1]
                self.assertEqual((args.check, args.offline, args.no_container), flags)
                self.assertEqual(args.toolchain, root.resolve())

        for status in (0, 2, 3, 4, 5, 7):
            with self.subTest(differentiated_status=status):
                self.operations.codes["provision"] = status
                code, _, _ = self.invoke(["provision", "--check"])
                self.assertEqual(code, status)

    def test_provision_has_only_its_documented_cwd_fallback(self):
        code, _, _ = self.invoke(["provision"])
        self.assertEqual(code, 0)
        self.assertEqual(self.operations.called("provision")[0].toolchain,
                         (self.cwd / ".toolchain").resolve())

    def test_tool_location_precedence_and_no_consumer_defaults(self):
        argv = ["preflight", "bundle", "--toolchain", "managed",
                "--support-tools", "explicit-tools"]
        code, _, _ = self.invoke(argv, environ={"TOOLCHAIN": "environment"})
        self.assertEqual(code, 0)
        args = self.operations.called("preflight")[0]
        self.assertEqual(args.support_tools, (self.cwd / "explicit-tools").resolve())
        self.assertEqual(args.pdk_root, (self.cwd / "managed/pdk").resolve())
        self.assertEqual(args.python, (self.cwd / "managed/.venv/bin/python").resolve())

        other = FakeOperations()
        self.operations = other
        code, _, stderr = self.invoke(["preflight", "bundle"], environ={
            "PROTEMU_TOOLCHAIN": "hidden", "RUN": "hidden", "KIND": "memory"})
        self.assertEqual(code, 2)
        self.assertIn("--support-tools", stderr)
        self.assertEqual(other.calls, [])

    def test_run_identity_is_json_for_recorded_failure_and_interruption(self):
        for status, exit_code in (("failed", 1), ("interrupted", 143)):
            with self.subTest(status=status):
                self.operations.run_outcome.status = status
                self.operations.run_outcome.exit_code = exit_code
                code, stdout, _ = self.invoke(
                    ["run", "bundle", "--runs", "runs", "--stage", "synthesis",
                     *self.tool_args()])
                self.assertEqual(code, exit_code)
                value = json.loads(stdout)
                self.assertEqual(value["status"], status)
                self.assertEqual(value["run_dir"], "/absolute/run-1")
                self.assertEqual(value["run_record"], "/absolute/run-1/run.json")
                self.assertFalse(self.operations.called("run")[-1].allow_python_mismatch)

    def test_public_preallocation_interrupt_keeps_signal_status_without_run(self):
        def interrupt(_args):
            raise flow_cli.ContractInterrupted(15)

        self.operations.run = interrupt
        code, stdout, stderr = self.invoke(
            ["run", "bundle", "--runs", "runs", "--stage", "synthesis",
             *self.tool_args()])
        self.assertEqual(code, 143)
        self.assertEqual(stdout, "")
        self.assertIn("signal 15", stderr)

    def test_native_full_and_full_argument_gaps_fail_before_launch(self):
        cases = (
            ["run", "bundle", "--runs", "runs", "--stage", "full", "--native",
             *self.tool_args()],
            ["execute", "bundle", "--runs", "runs", "--stage", "full",
             *self.tool_args()],
            ["execute", "bundle", "--runs", "runs", "--stage", "full",
             "--native", "--testbench", "tb.v", "--testbench-top", "tb",
             *self.tool_args()],
        )
        for argv in cases:
            with self.subTest(argv=argv):
                code, _, _ = self.invoke(argv)
                self.assertEqual(code, 2)
        self.assertEqual(self.operations.calls, [])

    def test_synthesis_rejects_postcheck_inputs_and_omits_postcheck(self):
        bad = ["execute", "bundle", "--runs", "runs", "--stage", "synthesis",
               "--testbench", "tb.v", "--testbench-top", "tb", *self.tool_args()]
        code, _, _ = self.invoke(bad)
        self.assertEqual(code, 2)
        self.assertEqual(self.operations.calls, [])

        good = ["execute", "bundle", "--runs", "runs", "--stage", "synthesis",
                "--archive", "evidence", *self.tool_args()]
        code, stdout, _ = self.invoke(good)
        self.assertEqual(code, 0)
        self.assertEqual([name for name, _ in self.operations.calls],
                         ["run", "collect", "report", "archive"])
        self.assertEqual(json.loads(stdout)["archive"], str((self.cwd / "evidence").resolve()))

    def test_full_execute_is_fixed_composition(self):
        argv = ["execute", "bundle", "--runs", "runs", "--stage", "full",
                "--testbench", "memory_tb.v", "--testbench-top", "memory_tb",
                "--archive", "evidence", "--force", *self.tool_args()]
        code, stdout, _ = self.invoke(argv)
        self.assertEqual(code, 0)
        self.assertEqual([name for name, _ in self.operations.calls],
                         ["run", "postcheck", "collect", "report", "archive"])
        postcheck = self.operations.called("postcheck")[0]
        self.assertEqual(postcheck.run_dir, Path("/absolute/run-1"))
        self.assertEqual(postcheck.testbench_top, "memory_tb")
        archive = self.operations.called("archive")[0]
        self.assertTrue(archive.force)
        self.assertEqual(json.loads(stdout)["status"], "completed")
        self.assertEqual(len(stdout.splitlines()), 1)

    def test_failure_or_interrupt_collects_best_effort_without_promotion(self):
        for status, exit_code in (("failed", 1), ("interrupted", 130)):
            with self.subTest(status=status):
                self.operations = FakeOperations()
                self.operations.run_outcome.status = status
                self.operations.run_outcome.exit_code = exit_code
                argv = ["execute", "bundle", "--runs", "runs", "--stage", "synthesis",
                        "--archive", "evidence", *self.tool_args()]
                code, stdout, _ = self.invoke(argv)
                self.assertEqual(code, exit_code)
                self.assertEqual([name for name, _ in self.operations.calls],
                                 ["run", "collect"])
                value = json.loads(stdout)
                self.assertEqual(value["status"], status)
                self.assertTrue(value["steps"][-1]["best_effort"])

    def test_postcheck_failure_prevents_report_and_archive(self):
        self.operations.check_outcome.status = "failed"
        self.operations.check_outcome.exit_code = 1
        argv = ["execute", "bundle", "--runs", "runs", "--stage", "full",
                "--testbench", "tb.v", "--testbench-top", "tb",
                "--archive", "evidence", *self.tool_args()]
        code, _, _ = self.invoke(argv)
        self.assertEqual(code, 1)
        self.assertEqual([name for name, _ in self.operations.calls],
                         ["run", "postcheck", "collect"])

    def test_downstream_exception_or_interrupt_keeps_final_run_identity(self):
        cases = (("postcheck", flow_cli.ContractError("missing input"), 2, "failed"),
                 ("postcheck", flow_cli.ContractInterrupted(2), 130, "interrupted"),
                 ("collect", ValueError("bad results"), 2, "failed"),
                 ("report", ValueError("bad record"), 2, "failed"),
                 ("archive", OSError("publication failed"), 2, "failed"))
        for operation, error, expected_code, expected_status in cases:
            with self.subTest(operation=operation, error=type(error).__name__):
                self.operations = FakeOperations()
                setattr(self.operations, operation,
                        lambda _args, error=error: (_ for _ in ()).throw(error))
                stage = "full" if operation == "postcheck" else "synthesis"
                argv = ["execute", "bundle", "--runs", "runs", "--stage", stage,
                        "--archive", "evidence", *self.tool_args()]
                if stage == "full":
                    argv += ["--testbench", "tb.v", "--testbench-top", "tb"]
                code, stdout, _ = self.invoke(argv)
                self.assertEqual(code, expected_code)
                value = json.loads(stdout)
                self.assertEqual(value["run_dir"], "/absolute/run-1")
                self.assertEqual(value["status"], expected_status)
                self.assertNotIn("archive", value)

    def test_collection_is_not_acceptance(self):
        self.operations.codes["report"] = 1
        argv = ["execute", "bundle", "--runs", "runs", "--stage", "synthesis",
                "--archive", "evidence", *self.tool_args()]
        code, stdout, _ = self.invoke(argv)
        self.assertEqual(code, 1)
        self.assertEqual([name for name, _ in self.operations.calls],
                         ["run", "collect", "report"])
        self.assertEqual(json.loads(stdout)["status"], "rejected")

    def test_resumed_commands_use_only_the_explicit_run(self):
        decoy = self.cwd / "runs/newest-decoy"
        decoy.mkdir(parents=True)
        explicit = self.cwd / "chosen-run"
        commands = (
            ["collect", "chosen-run"],
            ["report", "chosen-run", "--json"],
            ["archive", "chosen-run", "--list"],
            ["postcheck", "chosen-run", "--testbench", "tb.v",
             "--testbench-top", "tb", *self.tool_args()],
        )
        for argv in commands:
            with self.subTest(command=argv[0]):
                code, _, _ = self.invoke(argv)
                self.assertEqual(code, 0)
                args = self.operations.called(argv[0])[-1]
                self.assertEqual(args.run_dir, explicit.resolve())

    def test_archive_destination_force_list_and_exit_forwarding(self):
        self.operations.codes["archive"] = 2
        code, _, _ = self.invoke(["archive", "run", "--output", "evidence", "--force"])
        self.assertEqual(code, 2)
        args = self.operations.called("archive")[-1]
        self.assertEqual(args.output, (self.cwd / "evidence").resolve())
        self.assertTrue(args.force)

        self.operations.codes["archive"] = 0
        code, _, _ = self.invoke(["archive", "run", "--list"])
        self.assertEqual(code, 0)
        self.assertTrue(self.operations.called("archive")[-1].list)

        code, _, _ = self.invoke(["archive", "run", "--list", "--force"])
        self.assertEqual(code, 2)

    def test_identity_seam_is_forwarded_but_production_is_explicitly_deferred(self):
        argv = ["preflight", "bundle", "--dependency-lock", "consumer.lock",
                "--waiver", "python-version=fixture mismatch", *self.tool_args()]
        code, _, _ = self.invoke(argv)
        self.assertEqual(code, 0)
        args = self.operations.called("preflight")[0]
        self.assertEqual(args.dependency_lock, (self.cwd / "consumer.lock").resolve())
        self.assertEqual(args.waiver, ["python-version=fixture mismatch"])

        with self.assertRaises(flow_cli.ContractError):
            flow_cli.Operations.require_p6_5(args)
        code, _, _ = self.invoke([
            "preflight", "bundle", "--waiver", "unknown=reason", *self.tool_args()])
        self.assertEqual(code, 2)

    def test_malformed_top_level_record_maps_to_usage_error(self):
        run = self.cwd / "malformed-run"
        run.mkdir()
        (run / "run.json").write_text("[]\n")
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = flow_cli.main(["collect", str(run)], environ={}, cwd=self.cwd)
        self.assertEqual(code, 2)
        self.assertNotIn("Traceback", stderr.getvalue())


class RepositoryDriverTest(unittest.TestCase):
    """`scripts/flow.sh`: example build/emission, path selection, and routing.

    The driver keeps this repository's example, testbench and default paths and
    hands every flow operation to the shared dispatcher, so there is one
    implementation of sequencing, acceptance, run selection and archiving and it
    is the installed one. The generic orchestration assertions here -- help
    without any toolchain, an unknown command rejected before work, a resumed
    operation refusing to guess a run even with a decoy present, emission
    refusing a nonempty bundle, and removed spellings answered with the
    replacement -- were migrated from the consumer's
    `tinytapeout/scripts/check-flow.sh`, which made them about its own wrapper.
    Its thin argument forwarding and design-specific emitted-source checks stay
    with it.

    Nothing here builds, emits or provisions: `dune` is never reached, and the
    routing cases replace `python3` with a stub that only records its arguments.
    """

    REPO = Path(__file__).resolve().parents[1]
    DRIVER = REPO / "scripts/flow.sh"

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.log = self.root / "invocation.log"
        self.toolchain = self.root / "toolchain"
        for name in ("tt", "pdk"):
            (self.toolchain / name).mkdir(parents=True)
        self.flow_python = self.toolchain / ".venv/bin/python"
        self.flow_python.parent.mkdir(parents=True)
        self.flow_python.write_text("#!/bin/sh\nexit 0\n")
        self.flow_python.chmod(0o755)
        self.precheck_python = self.toolchain / ".venv-precheck/bin/python"
        self.precheck_python.parent.mkdir(parents=True)
        self.precheck_python.write_text("#!/bin/sh\nexit 0\n")
        self.precheck_python.chmod(0o755)
        self.out = self.root / "out"
        self.runs = self.out / "runs"
        # A stub python3 ahead of the real one: the driver's job is to invoke the
        # shared CLI with the right arguments, and that is all these record.
        stub = self.root / "bin"
        stub.mkdir()
        (stub / "python3").write_text(
            '#!/bin/sh\nprintf \'%s\\n\' "$*" >> "$FLOW_CLI_LOG"\n')
        (stub / "python3").chmod(0o755)
        self.stub_bin = stub

    def environment(self, *, stub_python=True, **extra):
        environment = {
            "HOME": str(self.root),
            "PATH": (f"{self.stub_bin}:/usr/bin:/bin" if stub_python
                     else "/usr/bin:/bin"),
            "FLOW_CLI_LOG": str(self.log),
            "TOOLCHAIN": str(self.toolchain),
            "OUT": str(self.out),
        }
        environment.update({name: str(value) for name, value in extra.items()})
        return environment

    def drive(self, *arguments, cwd=None, **environment):
        return subprocess.run(["bash", str(self.DRIVER), *arguments],
                              env=self.environment(**environment),
                              cwd=str(cwd or self.root), text=True,
                              capture_output=True, check=False)

    def routed(self):
        """The one shared-CLI invocation the driver made, as a single string."""
        lines = self.log.read_text().splitlines() if self.log.exists() else []
        self.assertEqual(len(lines), 1, lines)
        self.assertTrue(lines[0].startswith(
            f"{self.REPO / 'scripts/flow_cli.py'} "), lines[0])
        return lines[0]

    # -- help, arguments and removed spellings ---------------------------

    def test_help_works_with_no_toolchain_and_starts_nothing(self):
        for arguments in ([], ["--help"], ["-h"]):
            with self.subTest(arguments=arguments):
                completed = subprocess.run(
                    ["bash", str(self.DRIVER), *arguments],
                    env={"HOME": str(self.root), "PATH": "/usr/bin:/bin"},
                    cwd=str(self.root), text=True, capture_output=True, check=False)
                self.assertEqual(completed.returncode, 0, completed.stderr)
                self.assertIn("scripts/flow.sh COMMAND", completed.stdout)
                self.assertIn("execute", completed.stdout)
        self.assertFalse(self.log.exists())
        self.assertFalse(self.out.exists())

    def test_an_unknown_command_is_rejected_before_any_work(self):
        completed = self.drive("bogus")
        self.assertEqual(completed.returncode, 2)
        self.assertIn("unknown command: bogus", completed.stderr)
        self.assertFalse(self.log.exists())

    def test_the_old_step_list_names_its_replacement(self):
        completed = self.drive("preflight", "collect")
        self.assertEqual(completed.returncode, 2)
        self.assertIn("one command per invocation", completed.stderr)
        self.assertIn("execute", completed.stderr)
        self.assertFalse(self.log.exists())

    def test_the_removed_python_mismatch_waiver_names_its_replacement(self):
        completed = self.drive("preflight", ALLOW_PYTHON_MISMATCH="1")
        self.assertEqual(completed.returncode, 2)
        self.assertIn("ALLOW_PYTHON_MISMATCH is gone", completed.stderr)
        self.assertIn("waiver python-version", completed.stderr)
        self.assertFalse(self.log.exists())

    def test_expensive_commands_require_an_explicit_stage(self):
        for command in ("run", "execute"):
            with self.subTest(command=command):
                completed = self.drive(command)
                self.assertEqual(completed.returncode, 2)
                self.assertIn("STAGE", completed.stderr)
                completed = self.drive(command, STAGE="hardening")
                self.assertEqual(completed.returncode, 2)
                self.assertIn("synthesis or full", completed.stderr)
        self.assertFalse(self.log.exists())

    # -- run selection ---------------------------------------------------

    def test_a_resumed_command_refuses_to_guess_even_with_a_decoy_present(self):
        (self.runs / "newest-decoy").mkdir(parents=True)
        (self.runs / "newest-decoy/run.json").write_text("{}\n")
        for command in ("postcheck", "collect", "report", "archive"):
            with self.subTest(command=command):
                completed = self.drive(command)
                self.assertEqual(completed.returncode, 2)
                self.assertIn("set RUN=", completed.stderr)
                self.assertIn("never guessed", completed.stderr)
        self.assertFalse(self.log.exists())

        absent = self.drive("report", RUN=self.root / "not-a-run")
        self.assertEqual(absent.returncode, 2)
        self.assertIn("no run.json", absent.stderr)

    # -- emission --------------------------------------------------------

    def test_emission_refuses_a_bundle_that_already_has_files(self):
        bundle = self.out / "bundle"
        bundle.mkdir(parents=True)
        (bundle / "manifest.json").write_text("{}\n")
        completed = self.drive("emit")
        self.assertEqual(completed.returncode, 2)
        self.assertIn("already has files", completed.stderr)
        # The existing bundle is left exactly where it was.
        self.assertEqual((bundle / "manifest.json").read_text(), "{}\n")

    # -- routing ---------------------------------------------------------

    def test_every_operation_is_routed_to_the_shared_dispatcher(self):
        run = self.runs / "attempt"
        run.mkdir(parents=True)
        (run / "run.json").write_text("{}\n")
        bundle = self.out / "bundle"
        cases = {
            ("preflight",): [f"preflight {bundle}", f"--support-tools {self.toolchain}/tt",
                             f"--pdk-root {self.toolchain}/pdk",
                             f"--python {self.flow_python}"],
            ("run",): [f"run {bundle}", f"--runs {self.runs}", "--stage synthesis",
                       f"--python {self.flow_python}"],
            ("postcheck",): [f"postcheck {run}",
                             f"--precheck-python {self.precheck_python}",
                             "--testbench ", "--testbench-top tb_observable"],
            ("collect",): [f"collect {run}"],
            ("report", "--json"): [f"report {run}", "--json"],
            ("archive", "--output", "evidence"): [f"archive {run}",
                                                 "--output evidence"],
            ("execute",): [f"execute {bundle}", f"--runs {self.runs}",
                           "--stage synthesis"],
        }
        for arguments, expected in cases.items():
            with self.subTest(command=arguments[0]):
                self.log.unlink(missing_ok=True)
                completed = self.drive(*arguments, RUN=run, STAGE="synthesis")
                self.assertEqual(completed.returncode, 0, completed.stderr)
                routed = self.routed()
                for fragment in expected:
                    self.assertIn(fragment, routed)

        # Synthesis execution forwards no postcheck-only input, because the
        # shared command rejects that combination rather than implying a check.
        self.log.unlink(missing_ok=True)
        self.drive("execute", STAGE="synthesis")
        synthesis = self.routed()
        for absent in ("--testbench", "--precheck-python"):
            self.assertNotIn(absent, synthesis)
        self.log.unlink(missing_ok=True)
        self.drive("execute", STAGE="full")
        full = self.routed()
        for fragment in ("--stage full", "--testbench ", "--testbench-top",
                         "--precheck-python"):
            self.assertIn(fragment, full)

    def test_explicit_example_bench_and_paths_override_the_defaults(self):
        """Path and bench selection is what this driver keeps for itself."""
        run = self.runs / "attempt"
        run.mkdir(parents=True)
        (run / "run.json").write_text("{}\n")
        bench = self.root / "custom_tb.v"
        bench.write_text("module custom_tb; endmodule\n")
        completed = self.drive("postcheck", RUN=run, TESTBENCH=bench,
                               TESTBENCH_TOP="custom_tb")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        routed = self.routed()
        self.assertIn(f"--testbench {bench}", routed)
        self.assertIn("--testbench-top custom_tb", routed)

        self.log.unlink(missing_ok=True)
        elsewhere = self.root / "elsewhere"
        self.drive("preflight", BUNDLE=elsewhere / "emitted")
        self.assertIn(f"preflight {elsewhere / 'emitted'}", self.routed())

    def test_the_driver_holds_no_operation_implementation(self):
        """Structural: the removed duplicates must not creep back in."""
        text = self.DRIVER.read_text()
        for absent in ("scripts/phase4.py", "scripts/report.py", "ls -td",
                       "--allow-python-mismatch", "latest_run"):
            with self.subTest(absent=absent):
                self.assertNotIn(absent, text)

    def test_an_existing_run_is_reportable_with_no_ocaml_or_toolchain(self):
        """The real shared implementation, reached through the driver."""
        run = self.runs / "recorded"
        run.mkdir(parents=True)
        (run / "run.json").write_text(json.dumps({
            "schema_version": 1, "run_id": "stub", "build_identity": "stub-build",
            "status": "failed", "requested_stage": "synthesis",
            "completed_stage": None, "bundle": "/nowhere",
            "outputs": {"flow": "project/runs/asic", "project": "project"},
        }))
        completed = self.drive("report", RUN=run, stub_python=False)
        # Exit 1 is the reporter's verdict on an incomplete run, which is the
        # point: the driver reached P6.1's acceptance rather than its own.
        self.assertEqual(completed.returncode, 1, completed.stderr)
        self.assertIn("run        stub", completed.stdout)
        self.assertIn("PROBLEMS", completed.stdout)
        self.assertNotIn("set RUN=", completed.stderr)


if __name__ == "__main__":
    unittest.main()
