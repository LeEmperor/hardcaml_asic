#!/usr/bin/env python3
"""Source-only P6.3 command-contract dispatcher; installation belongs to P6.4."""

import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys


SCRIPT_DIR = Path(__file__).resolve().parent
WAIVER_CODES = {
    "python-version",
    "tool-source",
    "dependency-revision",
    "generator-tool-mismatch",
    "legacy-generator-identity",
}


class ContractError(Exception):
    pass


def load_module(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPT_DIR / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Operations:
    """Delegation to the existing implementations, with no duplicated policy."""

    def __init__(self):
        self.phase4 = load_module("phase4")
        self.reporter = load_module("report")
        self.archiver = load_module("archive")

    @staticmethod
    def require_p6_5(args):
        if getattr(args, "dependency_lock", None) or getattr(args, "waiver", None):
            raise ContractError(
                "dependency identity and waiver production handling belongs to P6.5")

    def provision(self, args):
        environment = os.environ.copy()
        environment["TOOLCHAIN"] = str(args.toolchain)
        command = [str(SCRIPT_DIR / "toolchain.sh")]
        for option in ("check", "offline", "no_container"):
            if getattr(args, option):
                command.append("--" + option.replace("_", "-"))
        return subprocess.run(command, env=environment, check=False).returncode

    def preflight(self, args):
        self.require_p6_5(args)
        result = self.phase4.preflight(
            args.bundle, args.support_tools, args.pdk_root, args.python,
            False, args.native)
        print(json.dumps(result, indent=2, sort_keys=True))
        if args.output:
            self.phase4.save(args.output, result)
        return 0 if result["ready"] else 1

    def run(self, args):
        self.require_p6_5(args)
        return self.phase4.run(args)

    def postcheck(self, args):
        self.require_p6_5(args)
        return self.phase4.check(args)

    def collect(self, args):
        result = self.phase4.collect(args.run_dir)
        if args.stdout:
            print(json.dumps(result, indent=2, sort_keys=True))
        else:
            self.phase4.save(args.output, result)
        return 0

    def report(self, args):
        results, source = self.reporter.results_for(args.run_dir)
        output = print
        if args.json:
            output = lambda *values: print(*values, file=sys.stderr)
        status = self.reporter.report(args.run_dir, results, source, output=output)
        if args.json:
            print(json.dumps(results, indent=2, sort_keys=True))
        return status

    def archive(self, args):
        if args.list:
            self.archiver.list_archive(args.run_dir)
            return 0
        tarball, _, omitted = self.archiver.archive(
            args.run_dir, args.output, args.force)
        for name in omitted:
            print(f"archive: absent, not included: {name}", file=sys.stderr)
        print(json.dumps({"archive": str(args.output), "reports": str(tarball)},
                         sort_keys=True))
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


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command")

    provision = sub.add_parser("provision")
    provision.add_argument("--toolchain", type=Path)
    provision.add_argument("--check", action="store_true")
    provision.add_argument("--offline", action="store_true")
    provision.add_argument("--no-container", action="store_true")

    preflight = sub.add_parser("preflight")
    preflight.add_argument("bundle", type=Path)
    add_toolchain(preflight, flow_python=True)
    add_identity_seam(preflight)
    preflight.add_argument("--native", action="store_true")
    preflight.add_argument("--output", type=Path)

    run = sub.add_parser("run")
    run.add_argument("bundle", type=Path)
    run.add_argument("--runs", required=True, type=Path)
    run.add_argument("--stage", required=True, choices=("synthesis", "full"))
    add_toolchain(run, flow_python=True)
    add_identity_seam(run)
    run.add_argument("--native", action="store_true")

    postcheck = sub.add_parser("postcheck")
    postcheck.add_argument("run_dir", type=Path)
    postcheck.add_argument("--testbench", required=True, type=Path)
    postcheck.add_argument("--testbench-top", required=True)
    add_toolchain(postcheck, precheck_python=True)
    add_identity_seam(postcheck)

    collect = sub.add_parser("collect")
    collect.add_argument("run_dir", type=Path)
    destination = collect.add_mutually_exclusive_group()
    destination.add_argument("--output", type=Path)
    destination.add_argument("--stdout", action="store_true")

    report = sub.add_parser("report")
    report.add_argument("run_dir", type=Path)
    report.add_argument("--json", action="store_true")

    archive = sub.add_parser("archive")
    archive.add_argument("run_dir", type=Path)
    destination = archive.add_mutually_exclusive_group(required=True)
    destination.add_argument("--output", type=Path)
    destination.add_argument("--list", action="store_true")
    archive.add_argument("--force", action="store_true")

    execute = sub.add_parser("execute")
    execute.add_argument("bundle", type=Path)
    execute.add_argument("--runs", required=True, type=Path)
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


def validate_waivers(parser, args):
    for waiver in getattr(args, "waiver", []):
        code, separator, reason = waiver.partition("=")
        if not separator or code not in WAIVER_CODES or not reason.strip():
            parser.error("--waiver must be a recognized CODE=REASON with a nonempty reason")


def resolve_paths(parser, args, environ, cwd):
    for name in ("bundle", "run_dir", "runs", "output", "archive",
                 "testbench", "dependency_lock", "toolchain",
                 "support_tools", "pdk_root", "python", "precheck_python"):
        if hasattr(args, name):
            setattr(args, name, absolute(getattr(args, name), cwd))

    if args.command == "provision":
        root = args.toolchain or absolute(Path(environ.get("TOOLCHAIN", ".toolchain")), cwd)
        args.toolchain = root
        return

    required = {
        "preflight": ("support_tools", "pdk_root", "python"),
        "run": ("support_tools", "pdk_root", "python"),
        "postcheck": ("support_tools", "pdk_root", "precheck_python"),
        "execute": ("support_tools", "pdk_root", "python"),
    }.get(args.command, ())
    root = args.toolchain
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
            setattr(args, name, (root / defaults[name]).resolve())
        if getattr(args, name) is None:
            parser.error(f"--{name.replace('_', '-')} or --toolchain/TOOLCHAIN is required")
    if args.command == "execute" and args.stage == "full":
        if args.precheck_python is None and root is not None:
            args.precheck_python = (root / defaults["precheck_python"]).resolve()
        if args.precheck_python is None:
            parser.error("--precheck-python or --toolchain/TOOLCHAIN is required for full execution")

    if hasattr(args, "output") and args.output is None and args.command == "collect":
        args.output = args.run_dir / "results.json"


def validate_contract(parser, args):
    validate_waivers(parser, args)
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
    outcome = operations.run(args)
    steps.append({"operation": "run", "status": outcome.status,
                  "exit_code": outcome.exit_code})
    result = {"run_id": outcome.run_id, "run_dir": str(outcome.run_dir),
              "run_record": str(outcome.run_record), "steps": steps}

    if outcome.exit_code:
        try:
            collect_args = argparse.Namespace(run_dir=outcome.run_dir,
                                              output=outcome.run_dir / "results.json",
                                              stdout=False)
            collect_code = operations.collect(collect_args)
            steps.append({"operation": "collect", "status": "completed",
                          "exit_code": collect_code, "best_effort": True})
        except Exception as exc:
            steps.append({"operation": "collect", "status": "failed",
                          "exit_code": 2, "best_effort": True, "error": str(exc)})
        result.update(status=outcome.status, exit_code=outcome.exit_code)
        print(json.dumps(result, sort_keys=True))
        return outcome.exit_code

    if args.stage == "full":
        args.run_dir = outcome.run_dir
        check = operations.postcheck(args)
        steps.append({"operation": "postcheck", "status": check.status,
                      "exit_code": check.exit_code})
        if check.exit_code:
            try:
                collect_args = argparse.Namespace(run_dir=outcome.run_dir,
                                                  output=outcome.run_dir / "results.json",
                                                  stdout=False)
                collect_code = operations.collect(collect_args)
                steps.append({"operation": "collect", "status": "completed",
                              "exit_code": collect_code, "best_effort": True})
            except Exception as exc:
                steps.append({"operation": "collect", "status": "failed",
                              "exit_code": 2, "best_effort": True, "error": str(exc)})
            result.update(status=check.status, exit_code=check.exit_code)
            print(json.dumps(result, sort_keys=True))
            return check.exit_code

    collect_args = argparse.Namespace(run_dir=outcome.run_dir,
                                      output=outcome.run_dir / "results.json", stdout=False)
    code = operations.collect(collect_args)
    steps.append({"operation": "collect", "status": "completed" if code == 0 else "failed",
                  "exit_code": code})
    if code:
        result.update(status="failed", exit_code=code)
        print(json.dumps(result, sort_keys=True))
        return code

    report_args = argparse.Namespace(run_dir=outcome.run_dir, json=False)
    code = operations.report(report_args)
    steps.append({"operation": "report", "status": "accepted" if code == 0 else "rejected",
                  "exit_code": code})
    if code:
        result.update(status="rejected", exit_code=code)
        print(json.dumps(result, sort_keys=True))
        return code

    if args.archive:
        archive_args = argparse.Namespace(run_dir=outcome.run_dir, output=args.archive,
                                          list=False, force=args.force)
        code = operations.archive(archive_args)
        steps.append({"operation": "archive", "status": "completed" if code == 0 else "failed",
                      "exit_code": code})
        if code:
            result.update(status="failed", exit_code=code)
            print(json.dumps(result, sort_keys=True))
            return code
        result["archive"] = str(args.archive)

    result.update(status="completed", exit_code=0)
    print(json.dumps(result, sort_keys=True))
    return 0


def main(argv=None, operations=None, environ=None, cwd=None):
    parser = build_parser()
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        parser.print_help()
        return 0
    args = parser.parse_args(argv)
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
            return execute_sequence(args, operations)
        result = getattr(operations, args.command)(args)
        if args.command in ("run", "postcheck"):
            print(json.dumps(result.as_dict(), sort_keys=True))
            return result.exit_code
        return result
    except (ContractError, OSError, ValueError, KeyError) as exc:
        print(f"hardcaml-asic-flow: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
