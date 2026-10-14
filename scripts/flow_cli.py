#!/usr/bin/env python3
"""Compatibility development adapter; the built native CLI owns execution."""
import os
from pathlib import Path
import sys

if __name__ == "__main__":
    binary = Path(__file__).resolve().parents[1] / "_build/default/bin/flow_cli.exe"
    try:
        os.execv(binary, [str(binary), *sys.argv[1:]])
    except OSError as exc:
        print(f"hardcaml-asic-flow: {exc}. Run dune build -j20 @install.", file=sys.stderr)
        sys.exit(2)
