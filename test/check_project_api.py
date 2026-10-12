"""External Project consumer and optional provider suite, with disposable Git fixtures.

Run: python3 test/check_project_api.py --provider-checks
Or, after dune build @install: python3 test/check_project_api.py
No installation, dependency downloads, provisioning or physical/synthesis EDA.
Provider checks retain normal PATH tool selection, including available RTL simulators.
Git mutations are confined to temporary fixtures; all commits use Bundle test identity.
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from check_resolved_flow_api import inventory


def checked(*args, cwd=None, env=None):
    subprocess.run(args, cwd=cwd, env=env, check=True)


def isolated_environment():
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
               GIT_AUTHOR_NAME="Bundle test", GIT_COMMITTER_NAME="Bundle test",
               GIT_AUTHOR_EMAIL="bundle@test.invalid",
               GIT_COMMITTER_EMAIL="bundle@test.invalid",
               GIT_CONFIG_COUNT="3", GIT_CONFIG_KEY_0="commit.gpgSign",
               GIT_CONFIG_VALUE_0="false", GIT_CONFIG_KEY_1="core.hooksPath",
               GIT_CONFIG_VALUE_1=os.devnull, GIT_CONFIG_KEY_2="init.templateDir",
               GIT_CONFIG_VALUE_2="")
    return env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--provider-checks", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="asic-project-api-") as temporary:
        root = Path(temporary)
        env = isolated_environment()
        if args.provider_checks:
            checked("dune", "build", "@install", cwd=repo, env=env)
            checked("dune", "runtest", "--force", cwd=repo, env=env)
            checked("python3", "test/check_resolved_flow_api.py", cwd=repo, env=env)
        public_lib = repo / "_build/install/default/lib"
        assert (public_lib / "hardcaml_asic").is_dir(), "run dune build @install first"
        env["OCAMLPATH"] = str(public_lib) + (
            os.pathsep + env["OCAMLPATH"] if env.get("OCAMLPATH") else "")
        source = root / "source"
        source.mkdir()
        for name in ("lib", "examples"):
            shutil.copytree(repo / name, source / name)
        shutil.copy2(repo / "dune-project", source / "dune-project")
        checked("git", "init", "-q", str(source), env=env)
        checked("git", "add", ".", cwd=source, env=env)
        checked("git", "commit", "-qm", "baseline", cwd=source, env=env)
        consumer = root / "consumer"
        consumer.mkdir()
        (consumer / "dune-project").write_text("(lang dune 3.17)\n")
        (consumer / "dune").write_text(
            "(executable (name main) (libraries core hardcaml hardcaml_asic))\n")
        # Preserve the in-tree low-level oracle. Only this disposable copy gains
        # declaration injection points; the design, policy and timing stay exact.
        oracle = (repo / "examples/tt_bundle_example.ml").read_text().split("let () =\n")[0]
        for old, new in [
            ("let project kind =", "let project ?source_inputs ?design_override ?target_override kind ="),
            ("  Project.create\n", "  Project.create ?source_inputs\n"),
            ("    ~design\n", "    ~design:(Option.value design_override ~default:design)\n"),
            ("    ~target:\n", "    ~target:(Option.value target_override ~default:\n"),
            ("{ harness = Tiny_tapeout", "{ Target.harness = Tiny_tapeout"),
            ("technology = Technology.ihp_sg13cmos5l\n      }",
             "technology = Technology.ihp_sg13cmos5l\n      })"),
        ]:
            assert oracle.count(old) == 1, old
            oracle = oracle.replace(old, new)
        (consumer / "oracle.ml").write_text(oracle)
        shutil.copy2(repo / "test/project_api_consumer.ml", consumer / "main.ml")
        checked("dune", "build", "--root", str(consumer), "main.exe", cwd=consumer, env=env)
        outputs = root / "outputs"
        outputs.mkdir()
        checked(str(consumer / "_build/default/main.exe"), str(source), str(outputs), env=env)
        for kind in ("observable", "memory"):
            for simulation in ("true", "false"):
                suffix = kind + simulation
                assert inventory(outputs / ("high-" + suffix)) == inventory(outputs / ("manual-" + suffix))
        print("external Project consumer: four complete on-disk bundles byte-identical")


if __name__ == "__main__":
    main()
