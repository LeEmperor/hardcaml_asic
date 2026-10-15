"""No EDA: real disposable Git inputs and independently installed API checks.

In-tree: dune build -j20 @test/plan_contract/runtest
Installed (after @install): python3 -B test/plan_contract/check.py --installed
All Dune invocations are sequential -j20. Git writes only temporary fixtures.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def run(*args, cwd=None, env=None):
    result = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"{args}:\n{result.stdout}{result.stderr}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--consumer", type=Path)
    parser.add_argument("--installed", action="store_true")
    args = parser.parse_args()
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
               GIT_AUTHOR_NAME="Plan fixture", GIT_COMMITTER_NAME="Plan fixture",
               GIT_AUTHOR_EMAIL="plan@test.invalid", GIT_COMMITTER_EMAIL="plan@test.invalid",
               GIT_CONFIG_COUNT="3", GIT_CONFIG_KEY_0="commit.gpgSign", GIT_CONFIG_VALUE_0="false",
               GIT_CONFIG_KEY_1="core.hooksPath", GIT_CONFIG_VALUE_1=os.devnull,
               GIT_CONFIG_KEY_2="init.templateDir", GIT_CONFIG_VALUE_2="")
    with tempfile.TemporaryDirectory(prefix="asic-plan-contract-") as temporary:
        root = Path(temporary)
        executable = args.consumer.resolve() if args.consumer else None
        if args.installed:
            repo = Path(__file__).resolve().parents[2]
            public_lib = repo / "_build/install/default/lib"
            assert (public_lib / "hardcaml_asic").is_dir(), "build @install first"
            env["OCAMLPATH"] = str(public_lib) + (os.pathsep + env["OCAMLPATH"] if env.get("OCAMLPATH") else "")
            consumer = root / "independent consumer"
            consumer.mkdir()
            (consumer / "dune-project").write_text("(lang dune 3.17)\n")
            (consumer / "dune").write_text(
                "(executable (name consumer) (libraries core hardcaml hardcaml_asic yojson) "
                "(preprocess (pps ppx_jane)))\n")
            shutil.copy2(repo / "test/plan_contract/consumer.ml", consumer / "consumer.ml")
            run("dune", "build", "-j20", "--root", str(consumer), "consumer.exe", cwd=consumer, env=env)
            executable = consumer / "_build/default/consumer.exe"
        assert executable
        source = root / "source with spaces"
        source.mkdir()
        (source / "design.ml").write_text("(* source inventory *)\n")
        (source / "catalog.ml").write_text("(* consumer-owned catalog inventory *)\n")
        run("git", "init", "-q", str(source), env=env)
        run("git", "add", ".", cwd=source, env=env)
        run("git", "commit", "-qm", "baseline", cwd=source, env=env)
        baseline_tree = sorted(str(p.relative_to(root)) for p in root.rglob("*"))
        result = json.loads(run(str(executable), str(source), env=env))
        assert result["checks"] >= 70, result["checks"]
        plan = result["plan"]
        # Focused independent differential: known ASCII/integer/bool catalog and
        # methodology fixture only. Do not claim general Python float compatibility.
        def independent_hash(contract, payload):
            wrapped = dict(contract=contract, schema_version=1, payload=payload)
            data = json.dumps(wrapped, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
            return hashlib.sha256(data).hexdigest()
        assert independent_hash("hardcaml-asic.methodology-hash", plan["methodology"]) == plan["methodology_hash"]
        assert result["canonical_probe"] == '{"a":"λ","z":1.25}'
        # Plan identity wraps strings containing the exact OCaml configuration/
        # manifest bytes; float formatting inside those strings is never reencoded.
        unsigned = {k: v for k, v in plan.items() if k != "plan_identity"}
        assert independent_hash("hardcaml-asic.plan-identity", unsigned) == plan["plan_identity"]
        assert sorted(str(p.relative_to(root)) for p in root.rglob("*")) == baseline_tree, "preview wrote paths"
        expected = plan["plan_identity"]
        def preview(path=source, expected=None):
            argv = [str(executable), str(path), "preview"]
            if expected:
                argv.append(expected)
            return subprocess.run(argv, env=env, text=True, capture_output=True)
        matched = preview(expected=expected)
        assert matched.returncode == 0, matched.stderr
        assert json.loads(matched.stdout)["plan_identity"] == expected
        # Physical root relocation doesn't enter identity, nor do cwd/workspace.
        moved = root / "relocated source"
        shutil.copytree(source, moved)
        observed = preview(moved)
        assert observed.returncode == 0, observed.stderr
        assert json.loads(observed.stdout)["plan_identity"] == expected
        for input_file in ("design.ml", "catalog.ml"):
            path = source / input_file
            original = path.read_bytes()
            path.write_bytes(original + b"(* changed *)\n")
            before = sorted(str(p.relative_to(root)) for p in root.rglob("*"))
            stale = preview(expected=expected)
            assert stale.returncode != 0 and "stale methodology plan identity" in stale.stderr
            assert sorted(str(p.relative_to(root)) for p in root.rglob("*")) == before
            changed = json.loads(preview().stdout)
            assert changed["plan_identity"] != expected
            assert changed["bundle_identity"] != plan["bundle_identity"]
            assert changed["methodology_hash"] == plan["methodology_hash"]
            path.write_bytes(original)
        # Revision changes independently of declared source bytes.
        run("git", "commit", "--allow-empty", "-qm", "new revision", cwd=source, env=env)
        stale = preview(expected=expected)
        assert stale.returncode != 0 and "stale methodology plan identity" in stale.stderr
        new_revision = json.loads(preview().stdout)
        assert new_revision["bundle_identity"] != plan["bundle_identity"]
        assert new_revision["methodology_hash"] == plan["methodology_hash"]
        store = root / "uncreated output" / "bundles"
        failed_publish = subprocess.run(
            [str(executable), str(source), "publish", expected, str(store)], env=env,
            text=True, capture_output=True)
        assert failed_publish.returncode != 0 and "stale methodology plan identity" in failed_publish.stderr
        assert not store.parent.exists(), "mismatched expected plan created output directories"
        original_source = (source / "design.ml").read_bytes()
        published = json.loads(run(str(executable), str(source), "publish",
                                   new_revision["plan_identity"], str(store), env=env))
        assert published["elaborations"] == 1
        destination = Path(published["directory"])
        assert destination.name == new_revision["bundle_identity"]
        assert published["plan"] == new_revision
        assert (destination / "inputs/design.ml").read_bytes() == original_source
        assert (source / "design.ml").read_bytes() != original_source
        assert (destination / "src/config.json").read_text() == new_revision["configuration_bytes"]
        if args.installed:
            # Abstract prepared/render pair and plan construction cannot be forged.
            for snippet in (
                'let forge : Project.Rendered.t = { resolution = Obj.magic (); bundle = Obj.magic () }',
                'let forge : Methodology_plan.Prepared.t = { plan = Obj.magic (); bundle = Obj.magic () }',
                'let forge : Methodology_plan.t = { plan_identity = "asserted" }',
            ):
                (consumer / "consumer.ml").write_text("open Hardcaml_asic\n" + snippet + "\n")
                rejected = subprocess.run(["dune", "build", "-j20", "--root", str(consumer), "consumer.exe"],
                                          cwd=consumer, env=env, text=True, capture_output=True)
                assert rejected.returncode != 0, "forged abstract contract compiled"
                assert "Unbound record field" in rejected.stderr, rejected.stderr
        print(f"plan contract: {result['checks']} domain/wire/render checks; independent hashes; "
              "source/catalog/revision stale comparisons; relocation; no preview writes; same-bundle publication" +
              ("; installed API and abstract-constructor negatives" if args.installed else ""))


if __name__ == "__main__":
    main()
