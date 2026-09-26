#!/usr/bin/env python3
"""Development adapter for the installed `hardcaml-asic-flow` command.

The dispatcher is `flow/hardcaml_asic_flow/cli.py`. Reaching it through this file
uses the checkout's modules and data -- including
`flow/hardcaml_asic_flow/data/toolchain.lock`, a symlink to the repository's own
`toolchain.lock` -- without the `python3 -I -B` isolation the installed launcher
applies. For anything that must behave exactly like an installation, install into
a prefix and run `$PREFIX/bin/hardcaml-asic-flow`.
"""

import sys
from pathlib import Path

# These repository scripts are development entry points and hold no
# implementation: each imports the same module the installed
# `hardcaml-asic-flow` command imports, so a checkout and a prefix run one
# implementation rather than two. This checkout-relative path is the only one of
# its kind left; the installed launcher resolves its own prefix and never
# searches for a source tree.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "flow"))

from hardcaml_asic_flow import cli  # noqa: E402


if __name__ == "__main__":
    sys.exit(cli.main())
