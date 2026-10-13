"""The `hardcaml-asic-flow` command: parsing, dispatch and the fixed sequence.

The dispatcher owns human/explicit-JSON presentation, result-store defaults,
argument parsing, path and tool-location precedence, exit
status mapping and the fixed `execute` composition; it owns no operation policy.
Every operation below delegates to the runner/collector, the P6.1 reporter, the
P6.2 archiver or the generic shell provisioner, all of which are siblings in this
package, so an installed command and a source checkout run the same code.

P6.4a packages that dispatcher. It does not add identity or waiver semantics:
`--dependency-lock` and `--waiver` still parse (so the option surface is settled
and testable) and are then rejected with an explicit P6.5 diagnostic, rather than
being silently accepted and ignored. `--version` reports the package version and
says plainly that source identity is unstamped; see `identity`.
"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from . import MINIMUM_PYTHON, archive as archiver, identity, paths, phase4, result_store
from . import report as reporter


PROGRAM = "hardcaml-asic-flow"
WAIVER_CODES = {
    "python-version",
    "tool-source",
    "dependency-revision",
    "generator-tool-mismatch",
    "legacy-generator-identity",
}


class ContractError(Exception):
    pass


class ContractInterrupted(Exception):
    def __init__(self, signum):
        super().__init__(f"interrupted by signal {signum}")
        self.signum = signum


class Operations:
    """Delegation to the existing implementations, with no duplicated policy."""

    def __init__(self):
        self.phase4 = phase4
        self.reporter = reporter
        self.archiver = archiver

    @staticmethod
    def require_p6_5(args):
        if getattr(args, "dependency_lock", None) or getattr(args, "waiver", None):
            raise ContractError(
                "dependency identity and waiver production handling belongs to P6.5")

    def provision(self, args):
        """Run the packaged provisioner against the packaged lock.

        `bash` is named explicitly rather than relying on the script's execute
        bit, so provisioning works from a read-only prefix and does not depend on
        which Dune install section placed the file. `--lock-file` is internal
        plumbing supplied here from `paths`: the public `provision` command has
        no option for it, so a caller cannot quietly point the flow at different
        target pins. Private `--host-python` retains this orchestration
        interpreter for the installed managed-runtime helper, including when
        the host runs a different minor from the venv base.
        """
        script = paths.require(paths.PROVISIONER, "the flow provisioner")
        lock = paths.require(paths.TOOLCHAIN_LOCK, "the toolchain lock")
        environment = os.environ.copy()
        environment["TOOLCHAIN"] = str(args.toolchain)
        command = ["bash", str(script), "--lock-file", str(lock),
                   "--host-python", sys.executable]
        if args.python is not None:
            command.extend(["--python", str(args.python)])
        for option in ("check", "offline", "no_container"):
            if getattr(args, option):
                command.append("--" + option.replace("_", "-"))
        return subprocess.run(command, env=environment, check=False).returncode

    def preflight(self, args):
        self.require_p6_5(args)
        outcome = result_store.preflight_operation(
            args.bundle, results_root=args.results_root, output=args.output,
            probe=lambda: self.phase4.preflight(
                args.bundle, args.support_tools, args.pdk_root, args.python,
                False, args.native))
        if args.json:
            print(json.dumps(outcome.result, indent=2, sort_keys=True))
            print(f"preflight: report {outcome.report_path}", file=sys.stderr)
        else:
            print(f"preflight: {outcome.status}")
            if outcome.receipt_path:
                print(f"operation: {outcome.receipt_path}")
            print(f"report: {outcome.report_path}")
        for issue in outcome.result["issues"]:
            print(f"preflight: {issue}", file=sys.stderr)
        if args.verbose:
            for name, value in outcome.result.items():
                if name not in ("ready", "issues"):
                    print(f"preflight {name}: {value}", file=sys.stderr)
        return outcome.exit_code

    def run(self, args):
        self.require_p6_5(args)
        try:
            with self.phase4.interruption_handlers():
                return self.phase4.run(args)
        except self.phase4.FlowInterrupted as exc:
            raise ContractInterrupted(exc.signum) from exc

    def postcheck(self, args):
        self.require_p6_5(args)
        try:
            with self.phase4.interruption_handlers():
                return self.phase4.check(args)
        except self.phase4.FlowInterrupted as exc:
            raise ContractInterrupted(exc.signum) from exc
        except self.phase4.PrerequisiteError as exc:
            raise ContractError(str(exc)) from exc

    def collect(self, args):
        result = self.phase4.collect(args.run_dir)
        if not args.stdout:
            self.phase4.save(args.output, result)
        if args.stdout or getattr(args, "json", False):
            print(json.dumps(result, indent=2, sort_keys=True))
        elif not getattr(args, "quiet", False):
            print(f"collect: results {args.output}")
        if getattr(args, "verbose", False):
            for name, value in result.items():
                print(f"collect {name}: {value}", file=sys.stderr)
        return 0

    def report(self, args):
        results, source = self.reporter.results_for(args.run_dir)
        output = print
        diagnostics_only = getattr(args, "diagnostics_only", False)
        diagnostics = []
        if args.json or diagnostics_only:
            output = lambda *values: print(*values, file=sys.stderr)
        if diagnostics_only:
            output = lambda *values: diagnostics.append(" ".join(map(str, values)))
        status = self.reporter.report(args.run_dir, results, source, output=output)
        if diagnostics_only and (status or getattr(args, "verbose", False)):
            for line in diagnostics:
                print(line, file=sys.stderr)
        if getattr(args, "verbose", False):
            print(f"report: run {args.run_dir}; result source {source}; acceptance exit {status}",
                  file=sys.stderr)
        if args.json and not diagnostics_only:
            print(json.dumps(results, indent=2, sort_keys=True))
        return status

    def archive(self, args):
        try:
            if args.list:
                self.archiver.list_archive(args.run_dir)
                return 0
            tarball, _, omitted = self.archiver.archive(
                args.run_dir, args.output, args.force)
        except self.archiver.phase4.PrerequisiteError as exc:
            raise ContractError(str(exc)) from exc
        for name in omitted:
            print(f"archive: absent, not included: {name}", file=sys.stderr)
        if not getattr(args, "quiet", False):
            if getattr(args, "json", False):
                print(json.dumps({"archive": str(args.output), "reports": str(tarball)},
                                 sort_keys=True))
            else:
                print(f"archive: created {args.output}")
                print(f"reports: {tarball}")
        if getattr(args, "verbose", False):
            print(f"archive: reports {tarball}; omitted {len(omitted)} files", file=sys.stderr)
        return 0


def add_toolchain(parser, *, flow_python=False, precheck_python=False):
    parser.add_argument("--toolchain", type=Path)
    parser.add_argument("--support-tools", type=Path)
    parser.add_argument("--pdk-root", type=Path)
    if flow_python:
        parser.add_argument("--python", type=Path)
    if precheck_python:
        parser.add_argument("--precheck-python", type=Path)


def add_identity_seam(parser):
    parser.add_argument("--dependency-lock", type=Path)
    parser.add_argument("--waiver", action="append", default=[], metavar="CODE=REASON")


def nonempty_path(value):
    if not value.strip():
        raise argparse.ArgumentTypeError("expected a nonempty path")
    return Path(value)


def add_presentation(parser):
    # SUPPRESS preserves a global flag when the command-local spelling is absent.
    parser.add_argument("--json", action="store_true", default=argparse.SUPPRESS,
                        help="print the machine-readable payload (default: human summary)")
    parser.add_argument("--verbose", action="store_true", default=argparse.SUPPRESS,
                        help="expanded diagnostics on stderr")


def add_results_root(parser):
    parser.add_argument("--results-root", type=nonempty_path,
                        help="result store root (default: caller cwd/_flow_results)")


def build_parser():
    # The program name is fixed rather than taken from argv[0]: the launcher
    # invokes this module through `python3 -I -c`, where argv[0] is "-c", and a
    # repository adapter should still print the installed command's usage.
    parser = argparse.ArgumentParser(
        prog=PROGRAM,
        description="Provision, validate, run, collect, report and archive "
                    "TT/LibreLane work from an emitted hardcaml_asic bundle.")
    parser.add_argument("--version", action="store_true",
                        help="package version and source-identity state")
    parser.add_argument("--json", action="store_true",
                        help="machine-readable --version or command payload")
    parser.add_argument("--verbose", action="store_true",
                        help="expanded diagnostics on stderr")
    sub = parser.add_subparsers(dest="command")

    provision = sub.add_parser("provision")
    provision.add_argument("--toolchain", type=Path)
    provision.add_argument("--python", type=nonempty_path,
                           help="external base for new venvs (default: pinned managed Python; must match the locked minor and provide venv, ensurepip and Tcl)")
    provision.add_argument("--check", action="store_true")
    provision.add_argument("--offline", action="store_true")
    provision.add_argument("--no-container", action="store_true")

    preflight = sub.add_parser("preflight")
    add_presentation(preflight)
    add_results_root(preflight)
    preflight.add_argument("bundle", type=nonempty_path)
    add_toolchain(preflight, flow_python=True)
    add_identity_seam(preflight)
    preflight.add_argument("--native", action="store_true")
    preflight.add_argument("--output", type=nonempty_path,
                           help="exact report file; parent must exist (no operation directory)")

    run = sub.add_parser("run")
    add_presentation(run)
    add_results_root(run)
    run.add_argument("bundle", type=nonempty_path)
    run.add_argument("--runs", type=nonempty_path,
                     help="override implementation store (default: results-root/runs)")
    run.add_argument("--stage", required=True, choices=("synthesis", "full"))
    add_toolchain(run, flow_python=True)
    add_identity_seam(run)
    run.add_argument("--native", action="store_true")

    postcheck = sub.add_parser("postcheck")
    add_presentation(postcheck)
    postcheck.add_argument("run_dir", type=Path)
    postcheck.add_argument("--testbench", required=True, type=Path)
    postcheck.add_argument("--testbench-top", required=True)
    add_toolchain(postcheck, precheck_python=True)
    add_identity_seam(postcheck)

    collect = sub.add_parser("collect")
    add_presentation(collect)
    collect.add_argument("run_dir", type=Path)
    destination = collect.add_mutually_exclusive_group()
    destination.add_argument("--output", type=Path)
    destination.add_argument("--stdout", action="store_true",
                             help="legacy read-only JSON output; does not write results.json")

    report = sub.add_parser("report")
    add_presentation(report)
    report.add_argument("run_dir", type=Path)

    archive = sub.add_parser("archive")
    add_presentation(archive)
    archive.add_argument("run_dir", type=Path)
    destination = archive.add_mutually_exclusive_group(required=True)
    destination.add_argument("--output", type=Path)
    destination.add_argument("--list", action="store_true")
    archive.add_argument("--force", action="store_true")

    execute = sub.add_parser("execute")
    add_presentation(execute)
    add_results_root(execute)
    execute.add_argument("bundle", type=nonempty_path)
    execute.add_argument("--runs", type=nonempty_path,
                         help="override implementation store (default: results-root/runs)")
    execute.add_argument("--stage", required=True, choices=("synthesis", "full"))
    add_toolchain(execute, flow_python=True, precheck_python=True)
    add_identity_seam(execute)
    execute.add_argument("--native", action="store_true")
    execute.add_argument("--testbench", type=Path)
    execute.add_argument("--testbench-top")
    execute.add_argument("--archive", type=Path)
    execute.add_argument("--force", action="store_true")
    return parser


def absolute(path, cwd):
    if path is None:
        return None
    return (path if path.is_absolute() else cwd / path).resolve()


def interpreter_absolute(path, cwd):
    """Anchor an interpreter without dereferencing its venv leaf or parents.

    Keep lexical ``..`` components too: collapsing them across a symlink can
    select a different environment. Directory arguments still use ``absolute``.
    """
    if path is None:
        return None
    return (path if path.is_absolute() else cwd / path).absolute()


def validate_waivers(parser, args):
    for waiver in getattr(args, "waiver", []):
        code, separator, reason = waiver.partition("=")
        if not separator or code not in WAIVER_CODES or not reason.strip():
            parser.error("--waiver must be a recognized CODE=REASON with a nonempty reason")


def resolve_paths(parser, args, environ, cwd):
    for name in ("bundle", "run_dir", "runs", "results_root", "output", "archive",
                 "testbench", "dependency_lock", "toolchain",
                  "support_tools", "pdk_root"):
        if hasattr(args, name):
            setattr(args, name, absolute(getattr(args, name), cwd))
    for name in ("python", "precheck_python"):
        if hasattr(args, name):
            setattr(args, name, interpreter_absolute(getattr(args, name), cwd))

    if args.command == "provision":
        root = args.toolchain or absolute(Path(environ.get("TOOLCHAIN", ".toolchain")), cwd)
        args.toolchain = root
        return

    if args.command in ("preflight", "run", "execute"):
        args.results_root = args.results_root or absolute(Path("_flow_results"), cwd)
        if args.command in ("run", "execute"):
            args.runs = args.runs or args.results_root / "runs"

    required = {
        "preflight": ("support_tools", "pdk_root", "python"),
        "run": ("support_tools", "pdk_root", "python"),
        "postcheck": ("support_tools", "pdk_root", "precheck_python"),
        "execute": ("support_tools", "pdk_root", "python"),
    }.get(args.command, ())
    root = getattr(args, "toolchain", None)
    if root is None and environ.get("TOOLCHAIN"):
        root = absolute(Path(environ["TOOLCHAIN"]), cwd)
    defaults = {
        "support_tools": "tt",
        "pdk_root": "pdk",
        "python": ".venv/bin/python",
        "precheck_python": ".venv-precheck/bin/python",
    }
    for name in required:
        if getattr(args, name) is None and root is not None:
            normalize = interpreter_absolute if name in ("python", "precheck_python") else absolute
            setattr(args, name, normalize(root / defaults[name], cwd))
        if getattr(args, name) is None:
            parser.error(f"--{name.replace('_', '-')} or --toolchain/TOOLCHAIN is required")
    if args.command == "execute" and args.stage == "full":
        if args.precheck_python is None and root is not None:
            args.precheck_python = interpreter_absolute(root / defaults["precheck_python"], cwd)
        if args.precheck_python is None:
            parser.error("--precheck-python or --toolchain/TOOLCHAIN is required for full execution")

    if hasattr(args, "output") and args.output is None and args.command == "collect":
        args.output = args.run_dir / "results.json"


def validate_contract(parser, args):
    validate_waivers(parser, args)
    if args.command == "provision" and (args.json or args.verbose):
        parser.error("provision uses bootstrap human output; --json/--verbose are unsupported")
    if args.command == "archive" and args.list and args.json:
        parser.error("--json with archive --list is unsupported; use human --list")
    if args.command in ("run", "execute"):
        args.allow_python_mismatch = False
    if getattr(args, "force", False) and not (
            args.command == "archive" and args.output
            or args.command == "execute" and args.archive):
        parser.error("--force requires an explicit archive destination")
    if args.command in ("run", "execute") and args.native and args.stage == "full":
        parser.error("native execution supports synthesis only")
    if args.command == "execute":
        postcheck_values = (args.testbench, args.testbench_top, args.precheck_python)
        if args.stage == "full" and not all(postcheck_values):
            parser.error("full execution requires --testbench, --testbench-top, and precheck Python")
        if args.stage == "synthesis" and any(postcheck_values):
            parser.error("synthesis execution rejects postcheck-only inputs")


def execute_sequence(args, operations):
    steps = []
    started = time.monotonic()
    outcome = operations.run(args)
    steps.append({"operation": "run", "status": outcome.status,
                  "exit_code": outcome.exit_code,
                  "duration_seconds": round(time.monotonic() - started, 6)})
    result = {"run_id": outcome.run_id, "run_dir": str(outcome.run_dir),
              "run_record": str(outcome.run_record), "steps": steps}

    def finish(status, exit_code):
        result.update(status=status, exit_code=exit_code)
        output = lambda text: print(text, file=sys.stderr if args.json else sys.stdout)
        for step in steps:
            output(f"execute: {step['operation']} {step['status']} "
                   f"({step.get('duration_seconds', 0):.3f}s)")
            if step.get("error"):
                print(f"execute: {step['operation']}: {step['error']}", file=sys.stderr)
        output(f"execute: {status}")
        if args.json:
            output(f"execute: run {outcome.run_dir}")
        else:
            summarize_outcome(outcome, "run", verbose=args.verbose)
        if result.get("archive"):
            output(f"execute: archive {result['archive']}")
        if args.json:
            outcome_diagnostics(outcome, "run", args.verbose)
            print(json.dumps(result, sort_keys=True))
        return exit_code

    def best_effort_collect():
        collect_started = time.monotonic()
        try:
            collect_args = argparse.Namespace(run_dir=outcome.run_dir,
                                              output=outcome.run_dir / "results.json",
                                              stdout=False, quiet=True, json=False,
                                              verbose=args.verbose)
            collect_code = operations.collect(collect_args)
            steps.append({"operation": "collect", "status": "completed",
                          "exit_code": collect_code, "best_effort": True,
                          "duration_seconds": round(
                              time.monotonic() - collect_started, 6)})
        except Exception as exc:
            steps.append({"operation": "collect", "status": "failed",
                          "exit_code": 2, "best_effort": True, "error": str(exc),
                          "duration_seconds": round(
                              time.monotonic() - collect_started, 6)})

    if outcome.exit_code:
        best_effort_collect()
        return finish(outcome.status, outcome.exit_code)

    if args.stage == "full":
        args.run_dir = outcome.run_dir
        check_started = time.monotonic()
        try:
            check = operations.postcheck(args)
        except ContractInterrupted as exc:
            steps.append({"operation": "postcheck", "status": "interrupted",
                          "exit_code": 128 + exc.signum,
                          "duration_seconds": round(time.monotonic() - check_started, 6)})
            best_effort_collect()
            return finish("interrupted", 128 + exc.signum)
        except Exception as exc:
            steps.append({"operation": "postcheck", "status": "failed",
                          "exit_code": 2, "error": str(exc),
                          "duration_seconds": round(time.monotonic() - check_started, 6)})
            best_effort_collect()
            return finish("failed", 2)
        steps.append({"operation": "postcheck", "status": check.status,
                       "exit_code": check.exit_code,
                       "duration_seconds": round(time.monotonic() - check_started, 6)})
        if args.json:
            outcome_diagnostics(check, "postcheck", args.verbose)
        else:
            summarize_outcome(check, "postcheck", args.verbose)
        if check.exit_code:
            best_effort_collect()
            return finish(check.status, check.exit_code)

    collect_args = argparse.Namespace(run_dir=outcome.run_dir,
                                      output=outcome.run_dir / "results.json", stdout=False,
                                      quiet=True, json=False, verbose=args.verbose)
    collect_started = time.monotonic()
    try:
        code = operations.collect(collect_args)
    except Exception as exc:
        signum = getattr(exc, "signum", None)
        steps.append({"operation": "collect", "status": "failed", "exit_code": 2,
                      "error": str(exc), "duration_seconds": round(
                          time.monotonic() - collect_started, 6)})
        if signum is not None:
            steps[-1].update(status="interrupted", exit_code=128 + signum)
            return finish("interrupted", 128 + signum)
        return finish("failed", 2)
    steps.append({"operation": "collect", "status": "completed" if code == 0 else "failed",
                  "exit_code": code, "duration_seconds": round(
                      time.monotonic() - collect_started, 6)})
    if code:
        return finish("failed", code)

    report_args = argparse.Namespace(run_dir=outcome.run_dir, json=False,
                                     diagnostics_only=True, verbose=args.verbose)
    report_started = time.monotonic()
    try:
        code = operations.report(report_args)
    except Exception as exc:
        signum = getattr(exc, "signum", None)
        steps.append({"operation": "report", "status": "failed", "exit_code": 2,
                      "error": str(exc), "duration_seconds": round(
                          time.monotonic() - report_started, 6)})
        if signum is not None:
            steps[-1].update(status="interrupted", exit_code=128 + signum)
            return finish("interrupted", 128 + signum)
        return finish("failed", 2)
    steps.append({"operation": "report", "status": "accepted" if code == 0 else "rejected",
                  "exit_code": code, "duration_seconds": round(
                      time.monotonic() - report_started, 6)})
    if code:
        return finish("rejected", code)

    if args.archive:
        archive_args = argparse.Namespace(run_dir=outcome.run_dir, output=args.archive,
                                          list=False, force=args.force, quiet=True)
        archive_started = time.monotonic()
        try:
            code = operations.archive(archive_args)
        except Exception as exc:
            signum = getattr(exc, "signum", None)
            steps.append({"operation": "archive", "status": "failed", "exit_code": 2,
                          "error": str(exc), "duration_seconds": round(
                              time.monotonic() - archive_started, 6)})
            if signum is not None:
                steps[-1].update(status="interrupted", exit_code=128 + signum)
                return finish("interrupted", 128 + signum)
            return finish("failed", 2)
        steps.append({"operation": "archive", "status": "completed" if code == 0 else "failed",
                      "exit_code": code, "duration_seconds": round(
                          time.monotonic() - archive_started, 6)})
        if code:
            return finish("failed", code)
        result["archive"] = str(args.archive)

    return finish("completed", 0)


def unsupported_python():
    """A diagnostic when the host interpreter predates what the flow modules use."""
    if sys.version_info >= MINIMUM_PYTHON:
        return None
    wanted = ".".join(str(part) for part in MINIMUM_PYTHON)
    running = ".".join(str(part) for part in sys.version_info[:3])
    return (f"{PROGRAM}: requires Python {wanted} or newer to run the flow "
            f"modules; this interpreter is {running} ({sys.executable})")


def outcome_diagnostics(outcome, operation, verbose=False):
    record = outcome.run_record if operation == "run" else outcome.check_record
    if Path(record).is_file():
        payload = phase4.read_json(record)
        if payload.get("error"):
            print(f"{operation}: {payload['error']}", file=sys.stderr)
        if verbose:
            for name, value in payload.items():
                if name != "error":
                    print(f"{operation} {name}: {value}", file=sys.stderr)


def summarize_outcome(outcome, operation, verbose=False):
    print(f"{operation}: {outcome.status} (exit {outcome.exit_code})")
    if operation == "run":
        print(f"run id: {outcome.run_id}")
        print(f"run: {outcome.run_dir}")
        print(f"record: {outcome.run_record}")
        for name in ("preflight.json", "results.json", "execution.log"):
            path = outcome.run_dir / name
            if path.is_file():
                print(f"{name}: {path}")
    else:
        print(f"check id: {outcome.check_id}")
        print(f"check: {outcome.check_dir}")
        print(f"record: {outcome.check_record}")
        log = outcome.check_dir / "postcheck.log"
        if log.is_file():
            print(f"log: {log}")
    outcome_diagnostics(outcome, operation, verbose)


def main(argv=None, operations=None, environ=None, cwd=None):
    unsupported = unsupported_python()
    if unsupported is not None:
        print(unsupported, file=sys.stderr)
        return 2
    parser = build_parser()
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        parser.print_help()
        return 0
    args = parser.parse_args(argv)
    # --version is answered before any path resolution or operation dispatch, so
    # it needs no bundle, toolchain, PDK, container or Git and touches nothing.
    if args.version:
        return identity.report(as_json=args.json)
    if args.command is None:
        parser.print_help()
        return 0
    environ = os.environ if environ is None else environ
    cwd = Path.cwd() if cwd is None else Path(cwd)
    resolve_paths(parser, args, environ, cwd)
    validate_contract(parser, args)
    operations = operations or Operations()
    try:
        if args.command == "execute":
            if isinstance(operations, Operations):
                with operations.phase4.interruption_handlers():
                    return execute_sequence(args, operations)
            return execute_sequence(args, operations)
        result = getattr(operations, args.command)(args)
        if args.command in ("run", "postcheck"):
            if args.json:
                print(json.dumps(result.as_dict(), sort_keys=True))
                outcome_diagnostics(result, args.command, args.verbose)
            else:
                summarize_outcome(result, args.command, args.verbose)
            return result.exit_code
        return result
    except (ContractError, OSError, ValueError, KeyError, TypeError,
            AttributeError) as exc:
        print(f"hardcaml-asic-flow: {exc}", file=sys.stderr)
        return 2
    except ContractInterrupted as exc:
        print(f"hardcaml-asic-flow: {exc}", file=sys.stderr)
        return 128 + exc.signum


if __name__ == "__main__":
    sys.exit(main())
