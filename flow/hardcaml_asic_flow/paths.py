"""Where the installed runtime data lives, resolved from this package alone.

The one rule: every path below is derived from `__file__`. Nothing here looks at
the caller's working directory, `sys.argv[0]`, a `.git` directory, an
environment variable naming a checkout, or a sibling `hardcaml_asic` clone. An
installed command therefore finds its data under its own prefix, and a source
checkout finds the same files under `flow/`, without either one being able to
silently borrow the other's copy.

`toolchain.lock` has exactly one maintained source: the repository root file that
`test/check_bundle.py` asserts against the emitted manifest. In the source tree
`data/toolchain.lock` is a symlink to it; Dune installs the symlink's contents as
a regular file into the prefix. There is no second handwritten lock to drift.
"""

from pathlib import Path


PACKAGE_DIR = Path(__file__).resolve().parent
DATA_DIR = PACKAGE_DIR / "data"

#: Generic shell provisioner. Executed through `bash`, so it works from a
#: read-only prefix and does not depend on an install-time permission bit.
PROVISIONER = DATA_DIR / "toolchain.sh"

#: Pinned external collateral for provisioning before a bundle exists. Once a
#: bundle exists its own `requested_tools` are authoritative; see preflight.
TOOLCHAIN_LOCK = DATA_DIR / "toolchain.lock"


class MissingRuntimeData(Exception):
    """A shipped data file is absent from the location this package occupies."""


def require(path, what):
    """`path`, or an error naming where the installation was expected to put it.

    Deliberately no fallback search: if an installation is incomplete the caller
    is told which file is missing from which prefix, rather than being silently
    served a file from whatever source checkout happens to be nearby.
    """
    if not path.is_file():
        raise MissingRuntimeData(
            f"{what} is missing from this installation: expected {path}. "
            "Reinstall the hardcaml_asic package; no source checkout is searched.")
    return path
