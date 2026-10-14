#!/usr/bin/env python3
"""Deprecated SOURCE-only P6.1 reporting reference command.

Imports the retained checkout oracle. Production `hardcaml-asic-flow report`
uses OCaml Report_service; this is not the same public implementation or installed API.
"""

import sys
from pathlib import Path

# Explicit checkout reference access; production never searches this source path.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "flow"))

from hardcaml_asic_flow import report  # noqa: E402


if __name__ == "__main__":
    sys.exit(report.run())
