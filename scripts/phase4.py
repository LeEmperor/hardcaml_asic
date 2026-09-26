#!/usr/bin/env python3
"""Development adapter: the runner/collector lives in `hardcaml_asic_flow`.

Installed as `hardcaml-asic-flow preflight|run|postcheck|collect`. See
`flow/hardcaml_asic_flow/phase4.py`; this file only keeps the in-checkout
command line, including the one-line `run.json` path `scripts/flow.sh` reads.
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

from hardcaml_asic_flow import phase4  # noqa: E402


if __name__ == "__main__":
    sys.exit(phase4.main())
