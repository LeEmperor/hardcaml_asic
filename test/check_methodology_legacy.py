"""No-methodology byte regression against the pre-seam provider implementation.

Run after dune build -j20 @install. Builds only a disposable copy, sequentially
with -j20; reads Git objects in the live checkout without modifying its state.
Both emitters observe identical current source bytes and Git state. No EDA.
"""

import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-ref", default="0d04baeb5c6538412e3dfb173422b4aa5e174544")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="asic-methodology-legacy-") as temporary:
        baseline = Path(temporary)
        for name in ("lib", "examples"):
            shutil.copytree(repo / name, baseline / name)
        shutil.copy2(repo / "dune-project", baseline / "dune-project")
        # Freeze the original Project/settings boundary, retaining the accumulated
        # pure domain slice and the rest of the provider as the build environment.
        for name in ("project.ml", "project.mli", "resolved_flow.ml", "resolved_flow.mli"):
            data = subprocess.check_output(
                ["git", "show", f"{args.baseline_ref}:lib/{name}"], cwd=repo)
            (baseline / "lib" / name).write_bytes(data)
        # The new plan API explicitly depends on the checked render/merge seam
        # being replaced above. Exclude only that additive module in the fixture
        # build; keep Bundle and its unchanged identity/rendering implementation.
        dune = baseline / "lib/dune"
        text = dune.read_text()
        assert text.count("(name hardcaml_asic)") == 1
        dune.write_text(text.replace("(name hardcaml_asic)",
            "(name hardcaml_asic)\n (modules (:standard \\ methodology_plan))"))
        subprocess.run(["dune", "build", "-j20", "--root", str(baseline),
                        "examples/tt_bundle_example.exe"], cwd=baseline, check=True)
        subprocess.run(["python3", "-B", "test/check_resolved_flow_api.py",
                        "--baseline-emitter",
                        str(baseline / "_build/default/examples/tt_bundle_example.exe")],
                       cwd=repo, check=True)


if __name__ == "__main__":
    main()
