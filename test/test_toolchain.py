"""Bounded provider checks: synthetic collateral, no network or real provisioning."""

import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "flow"))
from hardcaml_asic_flow import probe

SCRIPT = REPO / "flow/hardcaml_asic_flow/data/toolchain.sh"
MINOR = f"{sys.version_info.major}.{sys.version_info.minor}"


def snapshot(root):
    return {str(p.relative_to(root)): (p.lstat().st_mtime_ns,
            p.read_bytes() if p.is_file() and not p.is_symlink() else None)
            for p in [root, *root.rglob("*")]}


class ToolchainTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="provider space's ")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.root = self.work / "_flow_tools"
        self.bin = self.work / "bin"
        self.bin.mkdir()
        self.log = self.work / "mutations"
        for tool in ("bash", "dirname", "sed", "head", "timeout", "stat", "id"):
            (self.bin / tool).symlink_to(shutil.which(tool))
        self.executable("git", '''case "$*" in
"rev-parse --git-dir") printf '%s\\n' "$GIT_DIR" ;;
"rev-parse HEAD") printf '%040d\\n' 0 ;;
"status --porcelain") test "$GIT_OPTIONAL_LOCKS" = 0 ;;
*) printf 'git %s\\n' "$*" >> "$MUTATIONS"; exit 99 ;;
esac
''')
        for tool in ("docker", "podman", "nix-shell", "nix-store", "curl", "wget", "pip", "mkdir", "rm"):
            self.executable(tool, f'printf "{tool} %s\\n" "$*" >> "$MUTATIONS"; exit 99\n')
        # Nix availability is historical/nonfatal, and its only allowed query is version.
        self.executable("nix-store", 'test "$*" = --version || exit 99; printf "nix fixture\\n"\n')
        lock = (REPO / "toolchain.lock").read_text()
        values = dict(line.split("=", 1) for line in lock.splitlines() if line and not line.startswith("#"))
        self.pdk = values["pdk"]
        self.ll = values["librelane_version"]
        for key in ("support_tools_revision", "pdk_revision"):
            lock = lock.replace(values[key], "0" * 40)
        lock = lock.replace("python=" + values["python"], "python=" + MINOR)
        self.lock = self.work / "fixture.lock"
        self.lock.write_text(lock)
        self.env = dict(os.environ, PATH=str(self.bin), TOOLCHAIN=str(self.root), MUTATIONS=str(self.log))

    def executable(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\n" + body)
        path.chmod(0o755)
        return path

    def venv(self, name):
        target = self.root / name
        subprocess.run([sys.executable, "-I", "-B", "-m", "venv", "--without-pip", str(target)], check=True)
        site = target / "lib" / ("python" + MINOR) / "site-packages"
        return site

    def ready(self):
        for part in ("tt/.git", "pdk/.git", "pdk/" + self.pdk,
                     "tt/tech/" + self.pdk + "/def", "tt/precheck"):
            (self.root / part).mkdir(parents=True, exist_ok=True)
        (self.root / "tt/tech" / self.pdk / "def/tt_block_6x4_pgvdd.def").touch()
        self.requirements = self.root / "tt/precheck/requirements.txt"
        self.requirements.write_text("klayout==0.28.0\n# exact pins\n")
        self.flow_site = self.venv(".venv")
        self.pre_site = self.venv(".venv-precheck")
        for site, name, version in ((self.flow_site, "librelane", self.ll), (self.pre_site, "klayout", "0.28.0")):
            (site / (name + ".py")).write_text("# synthetic import\n")
            metadata = site / (name + "-" + version + ".dist-info")
            metadata.mkdir()
            (metadata / "METADATA").write_text(f"Name: {name}\nVersion: {version}\n")
        (self.flow_site / "tkinter.py").write_text("class Tcl:\n    def eval(self, expression): return '42'\n")
        (self.flow_site / "_tkinter.py").write_text("# synthetic system extension\n")
        self.write_env()

    def write_env(self):
        values = dict(ASIC_TOOLCHAIN=self.root, TT=self.root / "tt", PDK=self.root / "pdk",
                      PDK_ROOT=self.root / "pdk", FLOW_PY=self.root / ".venv/bin/python",
                      PRECHECK_PY=self.root / ".venv-precheck/bin/python")
        # Previous generator's format remains valid for ordinary paths/apostrophes.
        (self.root / "toolchain-env.sh").write_text("\n".join(
            f': "${{{key}:={value}}}"' for key, value in values.items()) +
            "\nexport " + " ".join(values) + "\n")

    def run_check(self, *args, check=True):
        before = snapshot(self.root) if self.root.exists() else None
        completed = subprocess.run(["/bin/bash", str(SCRIPT), "--lock-file", str(self.lock),
                                    "--no-container", *(["--check"] if check else []), *args],
                                   env=self.env, text=True, capture_output=True, timeout=30)
        self.assertFalse(self.log.exists(), self.log.read_text() if self.log.exists() else "")
        if check:
            self.assertEqual(snapshot(self.root) if self.root.exists() else None, before)
        return completed.returncode, completed.stdout + completed.stderr

    def test_ready_without_named_base_and_read_only(self):
        self.ready()
        code, output = self.run_check()
        self.assertEqual(code, 0, output)
        self.assertFalse(list(self.root.rglob("*.pyc")))
        before = snapshot(self.root)
        code, output = self.run_check(check=False)
        self.assertEqual(code, 0, output)
        self.assertEqual(snapshot(self.root), before)

    def test_readiness_failures(self):
        self.ready()
        cases = [(self.flow_site / "tkinter.py", "raise ImportError('missing Tcl')", "missing Tcl"),
                 (self.requirements, "klayout==9.9\n", "requested 9.9"),
                 (self.requirements, "klayout>=0.28\n", "unsupported requirement"),
                 (self.pre_site / "klayout.py", "raise ImportError('broken klayout')", "broken klayout"),
                 (self.root / "toolchain-env.sh", "touch SHOULD_NOT_RUN\n", "stale environment")]
        for path, text, expected in cases:
            with self.subTest(expected=expected):
                old = path.read_text()
                path.write_text(text)
                code, output = self.run_check()
                self.assertEqual(code, 2, output)
                self.assertIn(expected, output)
                path.write_text(old)
        self.requirements.unlink()
        code, output = self.run_check()
        self.assertEqual(code, 2, output)
        self.assertIn("requirements not found", output)

    def test_absent_root_missing_and_wrong_base_stop_before_mutators(self):
        for check in (True, False):
            for args in ((), ("--python", "/missing/python")):
                code, output = self.run_check(*args, check=check)
                self.assertEqual(code, 2, output)
                self.assertFalse(self.root.exists())
        self.lock.write_text(self.lock.read_text().replace("python=" + MINOR, "python=0.1"))
        for check in (True, False):
            code, output = self.run_check("--python", sys.executable, check=check)
            self.assertEqual(code, 2, output)
            self.assertIn("requested 0.1", output)
            self.assertFalse(self.root.exists())

    def test_existing_wrong_python_never_recreated(self):
        self.ready()
        self.lock.write_text(self.lock.read_text().replace("python=" + MINOR, "python=0.1"))
        for check in (True, False):
            before = snapshot(self.root)
            code, output = self.run_check(check=check)
            self.assertEqual(code, 2, output)
            self.assertIn("explicitly repair", output)
            self.assertEqual(snapshot(self.root), before)

    def test_base_selection_matches_actual_minor_and_explicit_wins(self):
        self.ready()
        base = self.root / ".venv/bin/python"
        code, output = self.run_check("--python", str(base))
        self.assertEqual(code, 0, output)
        (self.bin / ("python" + MINOR)).symlink_to(base)
        code, output = self.run_check("--python", "/absent/explicit")
        self.assertEqual(code, 2, output)
        self.assertIn("/absent/explicit", output)
        # Force creation to be needed; python3 is acceptable only after its real version probe.
        shutil.rmtree(self.root / ".venv-precheck")
        (self.bin / ("python" + MINOR)).unlink()
        self.executable("python3", f'exec {shlex.quote(str(base))} "$@"\n')
        code, output = self.run_check()
        self.assertEqual(code, 2, output)
        self.assertNotIn("base readiness:", output)
        self.lock.write_text(self.lock.read_text().replace("python=" + MINOR, "python=0.1"))
        code, output = self.run_check()
        self.assertEqual(code, 2, output)
        self.assertIn("base readiness: Python", output)

    def test_missing_metadata_is_not_ready(self):
        self.ready()
        for metadata in self.pre_site.glob("*.dist-info"):
            shutil.rmtree(metadata)
        code, output = self.run_check()
        self.assertEqual(code, 2, output)
        self.assertIn("No package metadata", output)

    def test_explicit_base_tcl_failure_blocks_full_provision(self):
        self.ready()
        (self.flow_site / "tkinter.py").write_text("raise ImportError('system Tcl absent')\n")
        code, output = self.run_check("--python", str(self.root / ".venv/bin/python"), check=False)
        self.assertEqual(code, 2, output)
        self.assertIn("pip cannot", output)

    def test_selected_base_needs_venv_and_ensurepip_before_mutators(self):
        self.ready()
        for module in ("venv", "ensurepip"):
            with self.subTest(module=module):
                (self.flow_site / "host_probe_fixture.pth").write_text("import host_probe_fixture\n")
                (self.flow_site / "host_probe_fixture.py").write_text(
                    "import builtins\noriginal = builtins.__import__\n"
                    "def missing(name, *args, **kwargs):\n"
                    f"    if name == {module!r}: raise ImportError('host lacks {module}')\n"
                    "    return original(name, *args, **kwargs)\n"
                    "builtins.__import__ = missing\n")
                code, output = self.run_check("--python", str(self.root / ".venv/bin/python"), check=False)
                self.assertEqual(code, 2, output)
                self.assertIn("host lacks " + module, output)

    def test_env_generator_shell_roundtrip(self):
        # Extract definitions only; no provisioning body is run.
        source = SCRIPT.read_text()
        functions = source[source.index("env_assignments() {"):source.index("write_env_file() {")]
        root = str(self.work / "root space's $literal `text`")
        shell = (f'TOOLCHAIN={shlex.quote(root)}; tt_dir="$TOOLCHAIN/tt"; pdk_dir="$TOOLCHAIN/pdk"; '
                 'venv_dir="$TOOLCHAIN/.venv"; precheck_venv_dir="$TOOLCHAIN/.venv-precheck";\n' + functions +
                 '\nenv_assignments')
        generated = subprocess.check_output(["/bin/bash", "-c", shell], text=True)
        result = subprocess.check_output(["/bin/bash", "-c", generated + '\nprintf "%s\\n" "$ASIC_TOOLCHAIN" "$FLOW_PY"'],
                                         env={"PATH": str(self.bin)}, text=True)
        self.assertEqual(result.splitlines(), [root, root + "/.venv/bin/python"])

    def test_actual_host_tcl_probe_is_headless_and_reports_blocked(self):
        env = dict(os.environ)
        env.pop("DISPLAY", None)
        completed = subprocess.run([sys.executable, "-I", "-B", str(Path(probe.__file__)), "tcl", MINOR],
                                   env=env, text=True, capture_output=True, timeout=20)
        if completed.returncode:
            self.assertEqual(completed.returncode, 2)
            self.assertIn("pip cannot", completed.stderr)
        else:
            self.assertEqual(completed.stderr, "")

    def test_bootstrap_forwards_base_and_rejects_missing_value_before_layers(self):
        bootstrap = self.work / "bootstrap.sh"
        bootstrap.write_bytes((REPO / "bootstrap.sh").read_bytes())
        scripts = self.work / "scripts"
        scripts.mkdir()
        for name in ("ocaml-deps.sh", "toolchain.sh"):
            stub = scripts / name
            stub.write_text('#!/bin/bash\nprintf "%s\\n" "$@" >> "$LAYER_LOG"\n')
            stub.chmod(0o755)
        log = self.work / "layers"
        env = dict(self.env, LAYER_LOG=str(log))
        result = subprocess.run(["/bin/bash", str(bootstrap), "--check", "--no-container", "--python", "/base space's/python"],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--python\n/base space's/python\n", log.read_text())
        log.unlink()
        result = subprocess.run(["/bin/bash", str(bootstrap), "--python", "--check"],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertFalse(log.exists())


if __name__ == "__main__":
    unittest.main()
