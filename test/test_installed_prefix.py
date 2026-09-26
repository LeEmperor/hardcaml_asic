"""Install into a throwaway prefix and check the command behaves like one.

Deliberately not part of `dune runtest`: it calls `dune build @install` and
`dune install`, and an alias that did that would make an ordinary test run
recursive. Run it explicitly:

    python3 test/test_installed_prefix.py

It builds and installs into a fresh temporary prefix, never into an opam switch
or any shared environment, and removes the prefix afterwards. It invokes no PDK,
container, EDA tool, provisioner or network; every operation it exercises is a
pure record operation over a synthetic fixture.

Scope note: this is P6.4a *packaging* evidence -- the installed command finds its
own modules and data and runs them. It is not P6.6's independent-installation
gate. The checks below deny the checkout through cwd, PATH and PYTHONPATH and
prove where imports actually came from, but they do not make the source tree
unreadable to the process; a filesystem sandbox is P6.6's job.
"""

import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest


sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "test"))
# The acceptance fixtures come from the reporter suite rather than being written
# again here, so the installed command is judged by the same records P6.1 is.
from test_report import FULL_RESULTS, synthesis_results  # noqa: E402
# The archive fixture is the P6.2 suite's own run and bundle, built here rather
# than copied, so the installed archiver is judged against the same inputs. The
# module is imported, not its TestCase: a name bound here would make this suite
# run the archive suite's own twenty tests a second time.
import test_archive  # noqa: E402


# -- deterministic stand-ins for the external processes ------------------
#
# Every external program the flow starts is answered here by a few lines of
# POSIX shell: git, docker, nix-shell, the LibreLane flow Python and the TT
# precheck Python. They reply to the exact probe the implementation makes and
# record what they were asked, so an installed operation can be driven to
# completion in milliseconds with no PDK, LibreLane, Docker, Nix, network or
# repository anywhere. They are fixtures for the flow's own logic and prove
# nothing whatever about the real tools.

STUB_REVISION = "1" * 40
STUB_LIBRELANE = "1.2.3"
STUB_PYTHON_MINOR = "3.11"
STUB_PYTHON_VERSION = "3.11.9"
STUB_KLAYOUT = "0.28.17"
STUB_NIXPKGS = "https://github.com/NixOS/nixpkgs/archive/fixture-revision.tar.gz"
TOP_MODULE = "fixture_top"

GIT_STUB = r"""#!/bin/sh
# Answers the two probes preflight makes, from a file beside the collateral
# root. There is no repository, no network and no real git.
directory=.
while [ $# -gt 0 ]; do
    case $1 in
        -C) directory=$2; shift 2 ;;
        rev-parse) cat "$directory/.stub-revision"; exit 0 ;;
        status)
            if [ -f "$directory/.stub-modified" ]; then echo " M fixture"; fi
            exit 0 ;;
        *) shift ;;
    esac
done
exit 0
"""

DOCKER_STUB = r"""#!/bin/sh
case "$*" in
    "info --format"*) echo "27.0.0-fixture"; exit 0 ;;
    "image inspect"*) echo "sha256:fixture-image"; exit 0 ;;
    *"--entrypoint python"*) echo "Python ${STUB_PYTHON_VERSION:-3.11.9}"; exit 0 ;;
    *"iverilog -V"*) echo "Icarus Verilog version 12.0 (fixture)"; exit 0 ;;
esac
output=
previous=
for argument in "$@"; do
    if [ "$previous" = -o ]; then output=$argument; fi
    previous=$argument
done
case "$*" in
    *iverilog*)
        if [ -n "$output" ]; then : > "$output"; fi
        exit "${STUB_COMPILE_STATUS:-0}" ;;
    *vvp*) exit "${STUB_SIMULATION_STATUS:-0}" ;;
esac
exit 0
"""

NIX_SHELL_STUB = r"""#!/bin/sh
# The NIX_PATH it was handed is the point of this one: the postcheck shell must
# take <nixpkgs> from the pinned default.nix rather than from a channel.
if [ -n "${STUB_NIX_PATH_LOG:-}" ]; then
    printf '%s\n' "${NIX_PATH-<unset>}" >> "$STUB_NIX_PATH_LOG"
fi
command=
while [ $# -gt 0 ]; do
    case $1 in
        --run) command=$2; shift 2 ;;
        *) shift ;;
    esac
done
case "$command" in
    "klayout -v") echo "KLayout ${STUB_KLAYOUT:-0.28.17}" ;;
    *)
        mkdir -p reports
        printf 'fixture check | pass\n' > reports/results.md
        exit "${STUB_PRECHECK_STATUS:-0}" ;;
esac
"""

FLOW_PYTHON_STUB = r"""#!/bin/sh
# The venv interpreter named by --python: version probes, and LibreLane itself.
if [ -n "${STUB_LOG:-}" ]; then printf '%s\n' "$*" >> "$STUB_LOG"; fi
case "$1" in
    -c)
        case "$2" in
            *version_info*) echo "${STUB_PYTHON_VERSION:-3.11.9}" ;;
            *librelane*) echo "${STUB_LIBRELANE:-1.2.3}" ;;
            *) echo "fixture python: unexpected program" >&2; exit 1 ;;
        esac
        exit 0 ;;
    -m)
        if [ -n "${STUB_FLOW_SLEEP:-}" ]; then sleep "$STUB_FLOW_SLEEP"; fi
        top=$(sed -n 's/.*"top_module": "\([^"]*\)".*/\1/p' manifest.json | head -1)
        synthesis=runs/asic/06-yosys-synthesis
        mkdir -p "$synthesis/reports"
        printf '%s\n' '{"design": {"area": 123.5, "sequential_area": 40, "num_cells": 15, "num_cells_by_type": {"sg13cmos5l_dfrbpq_1": 5}}, "creator": "Yosys 0.47 (fixture)"}' \
            > "$synthesis/reports/stat.json"
        printf '{"metrics": {"design__instance_unmapped__count": 0, "synthesis__check_error__count": %s, "design__inferred_latch__count": 0}}\n' \
            "${STUB_SYNTHESIS_ERRORS:-0}" > "$synthesis/state_out.json"
        case "$*" in
            *Yosys.Synthesis*) ;;
            *)
                mkdir -p runs/asic/final/gds runs/asic/final/nl
                printf 'gds-bytes\n' > "runs/asic/final/gds/$top.gds"
                printf 'module %s; endmodule\n' "$top" > "runs/asic/final/nl/$top.nl.v"
                {
                    echo 'timing__setup__ws__corner:slow,0.3'
                    echo 'timing__hold__ws__corner:fast,0.1'
                    echo 'route__drc_errors,0'
                    echo 'magic__drc_error__count,0'
                    echo 'design__lvs_error__count,0'
                    echo 'antenna__violating__nets,0'
                    echo 'antenna__violating__pins,0'
                    echo 'design__instance__area__stdcell,100.0'
                    echo 'design__instance__utilization__stdcell,0.4'
                } > runs/asic/final/metrics.csv ;;
        esac
        exit "${STUB_FLOW_STATUS:-0}" ;;
esac
exit 0
"""

PRECHECK_PYTHON_STUB = r"""#!/bin/sh
case "$*" in
    *"version('klayout')"*) echo "${STUB_KLAYOUT:-0.28.17}" ;;
    *) exit 0 ;;
esac
"""


def executable(path, script):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(script)
    path.chmod(0o755)
    return path


def stub_toolchain(root):
    """Stub binaries plus the collateral layout preflight and postcheck read."""
    binaries = root / "bin"
    executable(binaries / "git", GIT_STUB)
    executable(binaries / "docker", DOCKER_STUB)
    executable(binaries / "nix-shell", NIX_SHELL_STUB)
    flow_python = executable(root / "flow-python", FLOW_PYTHON_STUB)
    precheck_python = executable(root / "precheck-python", PRECHECK_PYTHON_STUB)

    support = root / "support"
    (support / "precheck").mkdir(parents=True)
    # The pinned nixpkgs revision lives in the collateral, which is exactly the
    # authority the postcheck environment takes it from.
    (support / "precheck/default.nix").write_text(
        'let pkgs = import (fetchTarball "%s") {}; in pkgs.mkShell {}\n' % STUB_NIXPKGS)
    (support / "precheck/tool-versions.json").write_text(
        json.dumps({"klayout": STUB_KLAYOUT}) + "\n")
    (support / "precheck/precheck.py").write_text("# fixture\n")
    (support / "tech").mkdir()
    (support / ".stub-revision").write_text(STUB_REVISION + "\n")

    pdk = root / "pdk"
    cells = pdk / "ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog"
    cells.mkdir(parents=True)
    (cells / "sg13cmos5l_udp.v").write_text("// fixture\n")
    (cells / "sg13cmos5l_stdcell.v").write_text("// fixture\n")
    io_models = pdk / "ihp-sg13cmos5l/libs.ref/sg13cmos5l_io/verilog"
    io_models.mkdir(parents=True)
    (io_models / "sg13cmos5l_io.v").write_text("// fixture\n")
    (pdk / ".stub-revision").write_text(STUB_REVISION + "\n")

    return SimpleNamespace(bin=binaries, support=support, pdk=pdk,
                           flow_python=flow_python, precheck_python=precheck_python)


def write_bundle(bundle, librelane=STUB_LIBRELANE, python=STUB_PYTHON_MINOR):
    """A bundle with the shape `Bundle.write` emits: hashed files and pins."""
    contents = {"src/config.json": "{}\n",
                "src/fixture.v": f"module {TOP_MODULE}; endmodule\n",
                "simulation/fixture.v": "module fixture_sim; endmodule\n",
                "inputs/lib/design.ml": 'let design = "fixture"\n',
                "constraints/top.sdc": "create_clock -period 10 clk\n"}
    for relative, text in contents.items():
        path = bundle / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    manifest = {
        "schema_version": 1,
        "adapter": "LibreLane",
        "identity": "fixture-build-1",
        "top_module": TOP_MODULE,
        "files": [{"path": relative,
                   "sha256": hashlib.sha256((bundle / relative).read_bytes()).hexdigest()}
                  for relative in sorted(contents)],
        "requested_tools": {"support_tools_revision": STUB_REVISION,
                            "pdk_revision": STUB_REVISION,
                            "librelane": librelane, "python": python},
        "target": {"technology": "ihp-sg13cmos5l", "external_references": []},
        # The archive inventory rules: declared synthesis and simulation sources,
        # and one copied source input whose metadata must agree with the file
        # list. Keeping them here makes the fixture a complete emitted bundle, so
        # `execute --archive` exercises publication rather than tripping over a
        # bundle no emitter would have produced.
        "synthesis_sources": ["src/fixture.v"],
        "simulation_sources": ["simulation/fixture.v"],
        "source_inputs": [{
            "path": "lib/design.ml",
            "copy": "inputs/lib/design.ml",
            "sha256": hashlib.sha256(
                (bundle / "inputs/lib/design.ml").read_bytes()).hexdigest(),
            "git_status": "",
        }],
    }
    # indent=2 so the stub LibreLane can read top_module out of it with sed.
    (bundle / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def build_prefix(prefix):
    for command in (["dune", "build", "@install"],
                    ["dune", "install", "--prefix", str(prefix), "hardcaml_asic"]):
        subprocess.run(command, cwd=REPO, check=True)


class InstalledPrefixTest(unittest.TestCase):
    """One prefix for the whole class; installing it is the expensive part."""

    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="hardcaml-asic-p64a.")
        root = Path(cls.temporary.name)
        cls.prefix = root / "prefix"
        cls.elsewhere = root / "unrelated-cwd"
        cls.elsewhere.mkdir()
        build_prefix(cls.prefix)
        cls.command = cls.prefix / "bin/hardcaml-asic-flow"
        cls.package = cls.prefix / "lib/hardcaml_asic/flow/hardcaml_asic_flow"

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def invoke(self, *arguments, command=None, cwd=None, env=None, path=None):
        """Run the installed command from an unrelated cwd with a clean env.

        The environment is rebuilt rather than inherited: PYTHONPATH, PYTHONHOME
        and a PATH containing the checkout are exactly the contamination an
        installed command has to be immune to.
        """
        environment = {"HOME": str(self.elsewhere),
                       "PATH": path or "/usr/bin:/bin"}
        environment.update(env or {})
        return subprocess.run([str(command or self.command), *arguments],
                              cwd=str(cwd or self.elsewhere), env=environment,
                              text=True, capture_output=True, check=False)

    # -- discovery -------------------------------------------------------

    def test_no_argument_invocation_prints_help_and_does_nothing(self):
        before = sorted(path.name for path in self.elsewhere.iterdir())
        completed = self.invoke()
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("usage: hardcaml-asic-flow", completed.stdout)
        self.assertEqual(sorted(path.name for path in self.elsewhere.iterdir()),
                         before)

    def test_help_needs_no_git_ocaml_pdk_docker_or_provisioning(self):
        # An empty PATH leaves the process without git, docker, nix, dune or
        # opam; only the launcher's own python3 is provided.
        python3 = shutil.which("python3")
        completed = self.invoke("--help", path=str(Path(python3).parent))
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("usage: hardcaml-asic-flow", completed.stdout)

    def test_version_reports_the_package_and_its_prefix(self):
        completed = self.invoke("--version", "--json")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        described = json.loads(completed.stdout)
        self.assertEqual(described["package_version_source"],
                         "installed-package-metadata")
        self.assertEqual(Path(described["module_dir"]), self.package)
        self.assertEqual(Path(described["data_dir"]), self.package / "data")
        self.assertTrue(described["toolchain_lock_present"])

    def test_version_claims_no_source_identity_before_p6_5(self):
        described = json.loads(self.invoke("--version", "--json").stdout)
        self.assertEqual(
            described["source"],
            {"stamped": False, "revision": None, "state": "unknown",
             "inventory_digest": None, "library_artifact_match": None,
             "note": described["source"]["note"]})
        self.assertIn("P6.5", described["source"]["note"])

    def test_discovery_through_path_and_through_a_symlink(self):
        by_path = self.invoke("--version", "--json", command="hardcaml-asic-flow",
                              path=f"{self.prefix / 'bin'}:/usr/bin:/bin")
        self.assertEqual(by_path.returncode, 0, by_path.stderr)

        link_dir = Path(self.temporary.name) / "someones-bin"
        link_dir.mkdir(exist_ok=True)
        (link_dir / "asicflow").unlink(missing_ok=True)
        (link_dir / "asicflow").symlink_to(self.command)
        by_link = self.invoke("--version", "--json", command="asicflow",
                              path=f"{link_dir}:/usr/bin:/bin")
        self.assertEqual(by_link.returncode, 0, by_link.stderr)
        self.assertEqual(json.loads(by_link.stdout), json.loads(by_path.stdout))

    def test_imports_come_from_the_prefix_even_when_a_checkout_is_exported(self):
        # A decoy package on PYTHONPATH stands in for a source checkout the
        # caller happens to have exported. `python3 -I` must ignore it.
        decoy = Path(self.temporary.name) / "decoy/hardcaml_asic_flow"
        decoy.mkdir(parents=True, exist_ok=True)
        (decoy / "__init__.py").write_text(
            'raise SystemExit("decoy hardcaml_asic_flow was imported")\n')
        completed = self.invoke(
            "--version", "--json",
            env={"PYTHONPATH": f"{decoy.parent}:{REPO / 'flow'}"})
        self.assertEqual(completed.returncode, 0, completed.stderr)
        described = json.loads(completed.stdout)
        for key in ("module_dir", "data_dir", "toolchain_lock"):
            with self.subTest(key=key):
                self.assertTrue(Path(described[key]).is_relative_to(self.prefix))
                self.assertFalse(Path(described[key]).is_relative_to(REPO))

    def test_a_missing_installation_is_reported_not_worked_around(self):
        lonely = Path(self.temporary.name) / "lonely-prefix/bin"
        lonely.mkdir(parents=True, exist_ok=True)
        copy = lonely / "hardcaml-asic-flow"
        shutil.copy2(self.command, copy)
        completed = self.invoke("--version", command=copy)
        self.assertEqual(completed.returncode, 2)
        self.assertIn("installed flow modules are missing", completed.stderr)
        self.assertIn("no source checkout is searched", completed.stderr)

    # -- read-only prefix ------------------------------------------------

    def test_read_only_prefix_runs_and_gains_no_bytecode(self):
        modes = {}
        for path in sorted(self.prefix.rglob("*"), reverse=True):
            modes[path] = path.stat().st_mode
            path.chmod(path.stat().st_mode & ~0o222)
        try:
            completed = self.invoke("--version")
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(self.invoke("--help").returncode, 0)
            self.assertEqual(list(self.prefix.rglob("__pycache__")), [])
            self.assertEqual(list(self.prefix.rglob("*.pyc")), [])
        finally:
            for path, mode in modes.items():
                path.chmod(mode)

    # -- a real operation, on a fixture ----------------------------------

    def write_run(self, run, results):
        (run / "project/runs/asic").mkdir(parents=True, exist_ok=True)
        (run / "run.json").write_text(json.dumps({
            "schema_version": 1,
            "run_id": results["run_id"],
            "build_identity": results["build_identity"],
            "bundle": "/bundle",
            "status": results["process_status"],
            "requested_stage": results["requested_stage"],
            "completed_stage": results["completed_stage"],
            "outputs": {"flow": "project/runs/asic"},
        }))
        (run / "results.json").write_text(json.dumps(results))
        return run

    def test_installed_report_applies_the_real_acceptance_policy(self):
        """Past --help and the parser: this imports and runs P6.1's reporter."""
        scratch = Path(self.temporary.name) / "fixtures"
        scratch.mkdir(exist_ok=True)

        accepted = self.write_run(scratch / "synthesis-ok", synthesis_results())
        completed = self.invoke("report", str(accepted))
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("scope      synthesis-only acceptance", completed.stdout)
        self.assertIn("synthesis acceptance passed", completed.stdout)

        rejected_results = synthesis_results()
        rejected_results["synthesis_checks"]["synthesis_errors"]["value"] = 1.0
        rejected = self.write_run(scratch / "synthesis-bad", rejected_results)
        failed = self.invoke("report", str(rejected), "--json")
        self.assertEqual(failed.returncode, 1)
        self.assertEqual(json.loads(failed.stdout), rejected_results)
        self.assertIn("synthesis_errors = 1", failed.stderr)

        full = self.write_run(scratch / "full-ok", FULL_RESULTS)
        self.assertEqual(self.invoke("report", str(full)).returncode, 0)

    def test_installed_collect_reads_a_run_without_any_tools(self):
        scratch = Path(self.temporary.name) / "fixtures"
        scratch.mkdir(exist_ok=True)
        run = self.write_run(scratch / "collect", synthesis_results())
        completed = self.invoke("collect", str(run), "--stdout")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        collected = json.loads(completed.stdout)
        self.assertEqual(collected["schema_version"], 1)
        self.assertEqual(collected["run_id"], synthesis_results()["run_id"])
        # --stdout is the read-only alternative; it must not write the file.
        self.assertFalse((run / "results.json.new").exists())

    def test_unsupported_options_are_rejected_not_ignored(self):
        scratch = Path(self.temporary.name) / "fixtures"
        scratch.mkdir(exist_ok=True)
        run = self.write_run(scratch / "waiver", synthesis_results())
        completed = self.invoke("preflight", str(run), "--toolchain",
                                str(scratch / "none"), "--waiver",
                                "python-version=fixture")
        self.assertEqual(completed.returncode, 2)
        self.assertIn("P6.5", completed.stderr)

    # -- installed operations, on fixtures and stub processes ------------
    #
    # Everything below runs the installed command as a subprocess and lets the
    # real operation implementations do the work; only the external programs are
    # stubs. These are the per-operation regression tests P6.4 asks for, as
    # distinct from the injected-dispatcher cases in test_flow_cli.py, which
    # replace the operations themselves and therefore prove nothing about an
    # installed one.

    def stubbed(self, **bundle_arguments):
        """A scratch toolchain, bundle and run store for one test."""
        root = Path(tempfile.mkdtemp(dir=self.temporary.name, prefix="fixture."))
        tools = stub_toolchain(root)
        bundle = root / "bundle"
        write_bundle(bundle, **bundle_arguments)
        return SimpleNamespace(root=root, tools=tools, bundle=bundle,
                               runs=root / "runs", log=root / "stub.log",
                               nix_path_log=root / "nix-path.log")

    def flow(self, fixture, *arguments, env=None, cwd=None):
        environment = {"STUB_LOG": str(fixture.log),
                       "STUB_NIX_PATH_LOG": str(fixture.nix_path_log)}
        environment.update(env or {})
        return self.invoke(*arguments, env=environment, cwd=cwd,
                           path=f"{fixture.tools.bin}:/usr/bin:/bin")

    @staticmethod
    def locations(fixture, *, flow_python=True, precheck_python=False):
        arguments = ["--support-tools", str(fixture.tools.support),
                     "--pdk-root", str(fixture.tools.pdk)]
        if flow_python:
            arguments += ["--python", str(fixture.tools.flow_python)]
        if precheck_python:
            arguments += ["--precheck-python", str(fixture.tools.precheck_python)]
        return arguments

    def completed_run(self, fixture, stage="synthesis", env=None):
        """One installed `run`, returning its machine-readable identity."""
        arguments = ["run", str(fixture.bundle), "--runs", str(fixture.runs),
                     "--stage", stage, *self.locations(fixture)]
        if stage == "synthesis":
            # Native synthesis keeps the fixture free of container probes; the
            # full stage keeps them, because that is the only route it has.
            arguments.append("--native")
        completed = self.flow(fixture, *arguments, env=env)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(completed.stdout)

    # -- preflight -------------------------------------------------------

    def test_installed_preflight_validates_real_inputs_and_names_its_gaps(self):
        fixture = self.stubbed()
        output = fixture.root / "preflight.json"
        ready = self.flow(fixture, "preflight", str(fixture.bundle), "--native",
                          "--output", str(output), *self.locations(fixture))
        self.assertEqual(ready.returncode, 0, ready.stderr)
        described = json.loads(ready.stdout)
        self.assertTrue(described["ready"], described["issues"])
        self.assertEqual(described["issues"], [])
        self.assertEqual(described["actual"]["librelane"], STUB_LIBRELANE)
        # The saved report is the same evidence, not a summary of it.
        self.assertEqual(json.loads(output.read_text()), described)

        # A changed bundle file, a collateral revision that is not the requested
        # one, and a LibreLane that is not the requested one each fail, and the
        # failure is 1 (evaluated, not ready) rather than 2 (unusable input).
        changed = self.stubbed()
        (changed.bundle / "src/fixture.v").write_text("module other; endmodule\n")
        gaps = self.flow(changed, "preflight", str(changed.bundle), "--native",
                         *self.locations(changed))
        self.assertEqual(gaps.returncode, 1)
        self.assertIn("missing or changed bundle file: src/fixture.v",
                      json.loads(gaps.stdout)["issues"])

        moved = self.stubbed()
        (moved.tools.pdk / ".stub-revision").write_text("9" * 40 + "\n")
        collateral = self.flow(moved, "preflight", str(moved.bundle), "--native",
                               *self.locations(moved))
        self.assertEqual(collateral.returncode, 1)
        self.assertTrue(any("PDK revision" in issue
                            for issue in json.loads(collateral.stdout)["issues"]))

        other = self.stubbed()
        versions = self.flow(other, "preflight", str(other.bundle), "--native",
                             *self.locations(other),
                             env={"STUB_LIBRELANE": "9.9.9"})
        self.assertEqual(versions.returncode, 1)
        self.assertTrue(any("LibreLane 9.9.9" in issue
                            for issue in json.loads(versions.stdout)["issues"]))

    def test_installed_preflight_probes_the_container_unless_native(self):
        fixture = self.stubbed()
        contained = self.flow(fixture, "preflight", str(fixture.bundle),
                              *self.locations(fixture))
        self.assertEqual(contained.returncode, 0, contained.stderr)
        actual = json.loads(contained.stdout)["actual"]
        self.assertEqual(actual["docker_server"], "27.0.0-fixture")
        self.assertEqual(actual["container_python"], STUB_PYTHON_VERSION)

        native = self.flow(fixture, "preflight", str(fixture.bundle), "--native",
                           *self.locations(fixture))
        self.assertNotIn("docker_server", json.loads(native.stdout)["actual"])

    def test_installed_preflight_needs_explicit_tool_locations(self):
        fixture = self.stubbed()
        incomplete = self.flow(fixture, "preflight", str(fixture.bundle), "--native")
        self.assertEqual(incomplete.returncode, 2)
        self.assertIn("--support-tools", incomplete.stderr)

    # -- run -------------------------------------------------------------

    def test_installed_run_allocates_records_and_forwards_its_locations(self):
        fixture = self.stubbed()
        completed = self.flow(fixture, "run", str(fixture.bundle), "--runs",
                              str(fixture.runs), "--stage", "synthesis", "--native",
                              *self.locations(fixture))
        self.assertEqual(completed.returncode, 0, completed.stderr)
        identity = json.loads(completed.stdout)
        self.assertEqual(identity["status"], "completed")
        run_dir = Path(identity["run_dir"])
        self.assertTrue(run_dir.is_absolute())
        self.assertEqual(run_dir.parent, fixture.runs)
        self.assertEqual(Path(identity["run_record"]), run_dir / "run.json")
        record = json.loads((run_dir / "run.json").read_text())
        self.assertEqual(record["run_id"], identity["run_id"])
        self.assertEqual(record["completed_stage"], "synthesis")
        # The preflight that actually gated this attempt is kept in the run, not
        # copied in from an earlier standalone invocation.
        in_run = json.loads((run_dir / "preflight.json").read_text())
        self.assertTrue(in_run["ready"])
        self.assertEqual(record["environment"], in_run)
        self.assertTrue((run_dir / "project/manifest.json").is_file())

        invocations = fixture.log.read_text().splitlines()
        flow_command = [line for line in invocations if line.startswith("-m librelane")]
        self.assertEqual(len(flow_command), 1)
        self.assertIn(f"--pdk-root {fixture.tools.pdk}", flow_command[0])
        self.assertIn("--to Yosys.Synthesis", flow_command[0])
        self.assertNotIn("--dockerized", flow_command[0])

    def test_installed_run_records_a_failed_attempt_and_keeps_its_path(self):
        fixture = self.stubbed()
        failed = self.flow(fixture, "run", str(fixture.bundle), "--runs",
                           str(fixture.runs), "--stage", "synthesis", "--native",
                           *self.locations(fixture), env={"STUB_FLOW_STATUS": "1"})
        self.assertEqual(failed.returncode, 1)
        identity = json.loads(failed.stdout)
        self.assertEqual(identity["status"], "failed")
        record = json.loads(Path(identity["run_record"]).read_text())
        self.assertEqual(record["status"], "failed")
        self.assertIn("LibreLane failed", record["error"])

    def test_installed_run_fabricates_no_path_when_it_fails_before_allocation(self):
        fixture = self.stubbed()
        (fixture.bundle / "manifest.json").unlink()
        early = self.flow(fixture, "run", str(fixture.bundle), "--runs",
                          str(fixture.runs), "--stage", "synthesis", "--native",
                          *self.locations(fixture))
        self.assertEqual(early.returncode, 2)
        self.assertEqual(early.stdout, "")
        self.assertFalse(fixture.runs.exists())
        self.assertNotIn("Traceback", early.stderr)

    def test_installed_run_requires_an_explicit_expensive_scope(self):
        fixture = self.stubbed()
        cases = (
            # No stage, no run store, and the native full flow that is not offered.
            (["run", str(fixture.bundle), "--runs", str(fixture.runs)], 2),
            (["run", str(fixture.bundle), "--stage", "synthesis"], 2),
            (["run", str(fixture.bundle), "--runs", str(fixture.runs),
              "--stage", "full", "--native"], 2),
        )
        for arguments, expected in cases:
            with self.subTest(arguments=arguments):
                refused = self.flow(fixture, *arguments, *self.locations(fixture))
                self.assertEqual(refused.returncode, expected)
        self.assertFalse(fixture.runs.exists())
        self.assertFalse(fixture.log.exists())

    def test_installed_run_interrupted_keeps_its_signal_status_and_path(self):
        fixture = self.stubbed()
        environment = {"HOME": str(self.elsewhere),
                       "PATH": f"{fixture.tools.bin}:/usr/bin:/bin",
                       "STUB_LOG": str(fixture.log),
                       "STUB_FLOW_SLEEP": "20"}
        process = subprocess.Popen(
            [str(self.command), "run", str(fixture.bundle), "--runs",
             str(fixture.runs), "--stage", "synthesis", "--native",
             *self.locations(fixture)],
            cwd=str(self.elsewhere), env=environment, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline and not any(fixture.runs.glob("*/run.json")):
            time.sleep(0.05)
        process.send_signal(signal.SIGTERM)
        stdout, stderr = process.communicate(timeout=30)
        self.assertEqual(process.returncode, 143, stderr)
        identity = json.loads(stdout)
        self.assertEqual(identity["status"], "interrupted")
        record = json.loads(Path(identity["run_record"]).read_text())
        self.assertEqual(record["interrupted_by"], "SIGTERM")
        self.assertIsNotNone(record["ended_at"])

    # -- postcheck -------------------------------------------------------

    def full_run(self, fixture):
        identity = self.completed_run(fixture, "full")
        return Path(identity["run_dir"])

    def bench(self, fixture):
        path = fixture.root / "fixture_tb.v"
        path.write_text("module fixture_tb; endmodule\n")
        return path

    def test_installed_postcheck_requires_both_verification_inputs(self):
        fixture = self.stubbed()
        run_dir = self.full_run(fixture)
        bench = self.bench(fixture)
        cases = ([], ["--testbench", str(bench)], ["--testbench-top", "fixture_tb"])
        for arguments in cases:
            with self.subTest(arguments=arguments):
                refused = self.flow(fixture, "postcheck", str(run_dir), *arguments,
                                    *self.locations(fixture, flow_python=False,
                                                    precheck_python=True))
                self.assertEqual(refused.returncode, 2)
        self.assertFalse((run_dir / "checks").exists())

    def test_installed_postcheck_records_its_checks_under_the_pinned_nix_shell(self):
        fixture = self.stubbed()
        run_dir = self.full_run(fixture)
        bench = self.bench(fixture)
        completed = self.flow(fixture, "postcheck", str(run_dir),
                              "--testbench", str(bench),
                              "--testbench-top", "fixture_tb",
                              *self.locations(fixture, flow_python=False,
                                              precheck_python=True))
        self.assertEqual(completed.returncode, 0, completed.stderr)
        identity = json.loads(completed.stdout)
        self.assertEqual(identity["status"], "completed")
        check_dir = Path(identity["check_dir"])
        self.assertEqual(check_dir.parent, run_dir / "checks")
        self.assertEqual(Path(identity["check_record"]), check_dir / "postcheck.json")
        record = json.loads((check_dir / "postcheck.json").read_text())
        self.assertEqual(record["checks"], {"precheck": "pass", "gate_level": "pass"})
        self.assertEqual(record["inputs"]["testbench_top"], "fixture_tb")
        # The bench is copied into the check, with its hash recorded, so the
        # evidence does not depend on the caller's file surviving.
        self.assertEqual((check_dir / "testbench.v").read_text(), bench.read_text())
        self.assertEqual(record["tools"]["klayout"], f"KLayout {STUB_KLAYOUT}")

        # Both nix-shell invocations saw <nixpkgs> from the pinned default.nix
        # rather than from a channel: this is the ported environment fix, proven
        # through the installed command.
        seen = fixture.nix_path_log.read_text().split()
        self.assertEqual(len(seen), 2)
        self.assertEqual(set(seen), {f"nixpkgs={STUB_NIXPKGS}"})

    def test_installed_postcheck_refuses_a_run_that_is_not_a_completed_full_flow(self):
        fixture = self.stubbed()
        run_dir = Path(self.completed_run(fixture)["run_dir"])
        refused = self.flow(fixture, "postcheck", str(run_dir),
                            "--testbench", str(self.bench(fixture)),
                            "--testbench-top", "fixture_tb",
                            *self.locations(fixture, flow_python=False,
                                            precheck_python=True))
        self.assertEqual(refused.returncode, 2)
        self.assertIn("completed full flow", refused.stderr)
        self.assertFalse((run_dir / "checks").exists())

    # -- explicit run selection -----------------------------------------

    def test_installed_resumed_operations_use_only_the_run_they_are_given(self):
        fixture = self.stubbed()
        chosen = Path(self.completed_run(fixture)["run_dir"])
        # Two decoys, both newer than the chosen run, one of them the newest
        # directory under the run store by every ordering a lookup might use.
        decoys = []
        for name in ("zzz-newest-decoy", "another-decoy"):
            decoy = fixture.runs / name
            decoy.mkdir()
            shutil.copy2(chosen / "run.json", decoy / "run.json")
            os.utime(decoy, (time.time() + 60, time.time() + 60))
            decoys.append(decoy)

        self.assertEqual(self.flow(fixture, "collect", str(chosen)).returncode, 0)
        self.assertEqual(self.flow(fixture, "report", str(chosen)).returncode, 0)
        self.assertTrue((chosen / "results.json").is_file())
        for decoy in decoys:
            self.assertFalse((decoy / "results.json").exists())

        # And no operation invents a run when none is named.
        for operation in ("collect", "report", "archive"):
            with self.subTest(operation=operation):
                self.assertEqual(self.flow(fixture, operation).returncode, 2)

    def test_installed_commands_resolve_paths_against_the_callers_cwd(self):
        """Nothing depends on this repository's layout or working directory."""
        fixture = self.stubbed()
        chosen = Path(self.completed_run(fixture)["run_dir"])
        relative = self.flow(fixture, "report", chosen.name,
                             cwd=fixture.runs)
        self.assertEqual(relative.returncode, 0, relative.stderr)
        self.assertIn(str(chosen), relative.stdout)

    # -- collect, report and the difference between them -----------------

    def test_installed_collection_success_is_not_acceptance(self):
        fixture = self.stubbed()
        run_dir = Path(self.completed_run(
            fixture, env={"STUB_SYNTHESIS_ERRORS": "1"})["run_dir"])
        collected = self.flow(fixture, "collect", str(run_dir))
        self.assertEqual(collected.returncode, 0, collected.stderr)
        self.assertEqual(json.loads((run_dir / "results.json").read_text())
                         ["synthesis_checks"]["synthesis_errors"]["value"], 1.0)
        rejected = self.flow(fixture, "report", str(run_dir))
        self.assertEqual(rejected.returncode, 1)
        self.assertIn("synthesis_errors = 1", rejected.stdout)

    # -- archive ---------------------------------------------------------

    def archive_fixture(self):
        """The P6.2 suite's run/bundle fixture, driven from here.

        Built by calling that suite's own `setUp`, so the installed archiver is
        judged against exactly the inputs its policy tests use rather than a
        second fixture that could drift away from them.
        """
        fixture = test_archive.ArchiveTest("setUp")
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        return fixture

    def test_installed_archive_publishes_verified_immutable_inputs(self):
        fixture = self.archive_fixture()
        fixture.write_check()
        listing = self.invoke("archive", str(fixture.run), "--list")
        self.assertEqual(listing.returncode, 0, listing.stderr)
        self.assertIn("manifest.json", listing.stdout)
        self.assertFalse(fixture.output.exists())  # --list publishes nothing

        published = self.invoke("archive", str(fixture.run),
                                "--output", str(fixture.output))
        self.assertEqual(published.returncode, 0, published.stderr)
        self.assertEqual(json.loads(published.stdout)["archive"], str(fixture.output))
        names = {path.name for path in fixture.output.iterdir()}
        self.assertLessEqual({"archive.json", "reports.tar.gz", "input-bundle.tar.gz",
                              "input-bundle.sha256", "run.json", "postcheck.json"},
                             names)
        manifest = json.loads((fixture.output / "archive.json").read_text())
        self.assertEqual(manifest["run_id"], "attempt-1")
        digest = hashlib.sha256(
            (fixture.output / "input-bundle.tar.gz").read_bytes()).hexdigest()
        self.assertEqual(manifest["input_bundle"]["sha256"], digest)
        self.assertEqual((fixture.output / "input-bundle.sha256").read_text(),
                         f"{digest}  input-bundle.tar.gz\n")

    def test_installed_archive_replaces_nothing_without_an_explicit_force(self):
        fixture = self.archive_fixture()
        self.assertEqual(self.invoke("archive", str(fixture.run), "--output",
                                     str(fixture.output)).returncode, 0)
        first = (fixture.output / "archive.json").read_text()
        (fixture.output / "README.md").write_text("human account\n")

        refused = self.invoke("archive", str(fixture.run), "--output",
                              str(fixture.output))
        self.assertEqual(refused.returncode, 2)
        self.assertIn("--force", refused.stderr)
        self.assertEqual((fixture.output / "archive.json").read_text(), first)

        # --force is also rejected without a destination to replace, so it can
        # never be a default that quietly discards evidence.
        self.assertEqual(self.invoke("archive", str(fixture.run), "--list",
                                     "--force").returncode, 2)
        self.assertEqual(self.invoke("archive", str(fixture.run)).returncode, 2)

        replaced = self.invoke("archive", str(fixture.run), "--output",
                               str(fixture.output), "--force")
        self.assertEqual(replaced.returncode, 0, replaced.stderr)
        self.assertNotEqual((fixture.output / "archive.json").read_text(), first)
        self.assertEqual((fixture.output / "README.md").read_text(), "human account\n")

    def test_installed_archive_refuses_tampered_inputs_and_keeps_the_old_one(self):
        fixture = self.archive_fixture()
        self.assertEqual(self.invoke("archive", str(fixture.run), "--output",
                                     str(fixture.output)).returncode, 0)
        good = (fixture.output / "archive.json").read_text()
        for root in (fixture.bundle, fixture.run / "project"):
            (root / "src/fixture.v").write_text("tampered\n")
        tampered = self.invoke("archive", str(fixture.run), "--output",
                               str(fixture.output), "--force")
        self.assertEqual(tampered.returncode, 2)
        self.assertIn("changed bundle file", tampered.stderr)
        self.assertEqual((fixture.output / "archive.json").read_text(), good)
        self.assertEqual(list(fixture.output.parent.glob(".*archive-*")), [])

    def test_installed_archive_requires_a_completed_run(self):
        fixture = self.archive_fixture()
        fixture.write_run("failed")
        refused = self.invoke("archive", str(fixture.run), "--output",
                              str(fixture.output))
        self.assertEqual(refused.returncode, 2)
        self.assertIn("not completed", refused.stderr)
        self.assertFalse(fixture.output.exists())

    # -- the fixed execute composition -----------------------------------

    def test_installed_execute_runs_the_fixed_synthesis_sequence(self):
        fixture = self.stubbed()
        evidence = fixture.root / "evidence"
        completed = self.flow(fixture, "execute", str(fixture.bundle),
                              "--runs", str(fixture.runs), "--stage", "synthesis",
                              "--native", "--archive", str(evidence),
                              *self.locations(fixture))
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(len(completed.stdout.splitlines()), 1)
        outcome = json.loads(completed.stdout)
        self.assertEqual(outcome["status"], "completed")
        self.assertEqual([step["operation"] for step in outcome["steps"]],
                         ["run", "collect", "report", "archive"])
        run_dir = Path(outcome["run_dir"])
        self.assertTrue((run_dir / "results.json").is_file())
        self.assertEqual(outcome["archive"], str(evidence))
        self.assertTrue((evidence / "archive.json").is_file())
        # Synthesis composes no physical postcheck, and says so by not running it.
        self.assertFalse((run_dir / "checks").exists())
        self.assertIn("execute: run ", completed.stderr)

    def test_installed_execute_adds_postcheck_only_for_a_full_flow(self):
        fixture = self.stubbed()
        completed = self.flow(fixture, "execute", str(fixture.bundle),
                              "--runs", str(fixture.runs), "--stage", "full",
                              "--testbench", str(self.bench(fixture)),
                              "--testbench-top", "fixture_tb",
                              *self.locations(fixture, precheck_python=True))
        self.assertEqual(completed.returncode, 0, completed.stderr)
        outcome = json.loads(completed.stdout)
        self.assertEqual([step["operation"] for step in outcome["steps"]],
                         ["run", "postcheck", "collect", "report"])
        run_dir = Path(outcome["run_dir"])
        self.assertEqual(len(list((run_dir / "checks").glob("*/postcheck.json"))), 1)
        results = json.loads((run_dir / "results.json").read_text())
        self.assertEqual(results["postchecks"][0]["status"], "completed")

    def test_installed_execute_validates_its_whole_scope_before_starting(self):
        fixture = self.stubbed()
        common = ["execute", str(fixture.bundle), "--runs", str(fixture.runs)]
        cases = (
            # Full without the verification inputs, and synthesis with them.
            [*common, "--stage", "full", *self.locations(fixture)],
            [*common, "--stage", "synthesis", "--native", "--testbench",
             str(self.bench(fixture)), "--testbench-top", "fixture_tb",
             *self.locations(fixture)],
            [*common, "--stage", "synthesis", "--native", "--force",
             *self.locations(fixture)],
        )
        for arguments in cases:
            with self.subTest(arguments=arguments[3:6]):
                refused = self.flow(fixture, *arguments)
                self.assertEqual(refused.returncode, 2)
        self.assertFalse(fixture.runs.exists())

    def test_installed_execute_keeps_the_run_and_promotes_nothing_on_failure(self):
        fixture = self.stubbed()
        evidence = fixture.root / "evidence"
        rejected = self.flow(fixture, "execute", str(fixture.bundle),
                             "--runs", str(fixture.runs), "--stage", "synthesis",
                             "--native", "--archive", str(evidence),
                             *self.locations(fixture),
                             env={"STUB_SYNTHESIS_ERRORS": "1"})
        self.assertEqual(rejected.returncode, 1)
        outcome = json.loads(rejected.stdout)
        self.assertEqual(outcome["status"], "rejected")
        self.assertEqual([step["operation"] for step in outcome["steps"]],
                         ["run", "collect", "report"])
        self.assertNotIn("archive", outcome)
        self.assertFalse(evidence.exists())
        # The allocated run is still named, and still holds its evidence.
        run_dir = Path(outcome["run_dir"])
        self.assertTrue((run_dir / "run.json").is_file())
        self.assertTrue((run_dir / "results.json").is_file())

        failed = self.flow(fixture, "execute", str(fixture.bundle),
                           "--runs", str(fixture.runs), "--stage", "synthesis",
                           "--native", "--archive", str(evidence),
                           *self.locations(fixture), env={"STUB_FLOW_STATUS": "1"})
        self.assertEqual(failed.returncode, 1)
        outcome = json.loads(failed.stdout)
        self.assertEqual(outcome["status"], "failed")
        # Collection after a failed run is best effort, and is not acceptance.
        self.assertEqual([step["operation"] for step in outcome["steps"]],
                         ["run", "collect"])
        self.assertTrue(outcome["steps"][-1]["best_effort"])
        self.assertFalse(evidence.exists())

    # -- provisioning dispatch -------------------------------------------

    def test_installed_provision_dispatches_to_the_packaged_provisioner(self):
        """Plumbing only: which script, which lock, which root, which status.

        The provisioner itself is replaced by a stub `bash`, so no collateral is
        fetched, no venv is built and no host is probed. This says nothing about
        P6.5c's read-only, offline and exact-version provisioning semantics,
        which are not implemented yet.
        """
        root = Path(tempfile.mkdtemp(dir=self.temporary.name, prefix="provision."))
        log = root / "invocation.log"
        executable(root / "bin/bash", "#!/bin/sh\n"
                   'printf "%s\\n" "$*" >> "$STUB_PROVISION_LOG"\n'
                   'printf "TOOLCHAIN=%s\\n" "$TOOLCHAIN" >> "$STUB_PROVISION_LOG"\n'
                   'exit "${STUB_PROVISION_STATUS:-0}"\n')
        toolchain = root / "managed"

        dispatched = self.invoke("provision", "--toolchain", str(toolchain),
                                 "--check", "--offline", "--no-container",
                                 path=f"{root / 'bin'}:/usr/bin:/bin",
                                 env={"STUB_PROVISION_LOG": str(log)})
        self.assertEqual(dispatched.returncode, 0, dispatched.stderr)
        argv, environment = log.read_text().splitlines()
        self.assertTrue(argv.startswith(
            str(self.package / "data/toolchain.sh") + " "))
        self.assertIn(f"--lock-file {self.package / 'data/toolchain.lock'}", argv)
        for option in ("--check", "--offline", "--no-container"):
            self.assertIn(f" {option}", argv)
        self.assertEqual(environment, f"TOOLCHAIN={toolchain}")
        # Dispatch alone creates nothing, including the root it was given.
        self.assertFalse(toolchain.exists())

        # The provisioner's differentiated statuses reach the caller unflattened.
        for status in ("2", "3", "4", "5", "7"):
            with self.subTest(status=status):
                completed = self.invoke("provision", "--toolchain", str(toolchain),
                                        "--check",
                                        path=f"{root / 'bin'}:/usr/bin:/bin",
                                        env={"STUB_PROVISION_LOG": str(log),
                                             "STUB_PROVISION_STATUS": status})
                self.assertEqual(completed.returncode, int(status))

    def test_installed_provision_exposes_no_way_to_swap_the_shipped_lock(self):
        elsewhere = Path(tempfile.mkdtemp(dir=self.temporary.name, prefix="lock."))
        (elsewhere / "other.lock").write_text("pdk=someone-elses\n")
        refused = self.invoke("provision", "--lock-file", str(elsewhere / "other.lock"))
        self.assertEqual(refused.returncode, 2)
        self.assertIn("--lock-file", refused.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
