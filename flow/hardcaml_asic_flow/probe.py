"""Small stdlib-only readiness probe, executed by the interpreter being checked.

Call with -I -B, under a subprocess timeout. No pip, Tk window, or source imports.
Imports execute installed package code; this is a readiness check, not a sandbox.
"""

import importlib
import importlib.metadata
from pathlib import Path
import re
import sys


def tcl_ready():
    import tkinter
    import _tkinter

    if str(tkinter.Tcl().eval("expr {6 * 7}")) != "42":
        raise ValueError("Tcl expression failed")


def exact_requirements(path):
    pins = []
    for number, line in enumerate(Path(path).read_text().splitlines(), 1):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        match = re.fullmatch(r"([A-Za-z0-9][A-Za-z0-9_.-]*)==([A-Za-z0-9][A-Za-z0-9_.+!-]*)", line)
        if not match:
            raise ValueError(f"unsupported requirement at {path}:{number}: {line}; expected name==version")
        pins.append(match.groups())
    if not pins:
        raise ValueError(f"no exact-pinned requirements in {path}")
    return pins


def check_version(wanted):
    actual = ".".join(map(str, sys.version_info[:2]))
    if actual != wanted:
        raise ValueError(f"Python {actual}, requested {wanted}; explicitly repair/select the interpreter; environments are not recreated")


def check_metadata(name, wanted):
    actual = importlib.metadata.version(name)
    if actual != wanted:
        raise ValueError(f"{name} {actual}, requested {wanted}")


def main(argv):
    mode, wanted, *args = argv
    try:
        check_version(wanted)
        if mode == "base":
            import venv
            import ensurepip
            tcl_ready()
        elif mode == "tcl":
            tcl_ready()
        elif mode == "flow":
            check_metadata("librelane", args[0])
            importlib.import_module("librelane")
            tcl_ready()
        elif mode == "precheck":
            for name, version in exact_requirements(args[0]):
                check_metadata(name, version)
            importlib.import_module("klayout")
        elif mode == "requirements":
            exact_requirements(args[0])
        elif mode != "version":
            raise ValueError(f"unknown probe mode: {mode}")
    except Exception as exc:
        print(f"{mode} readiness: {exc}", file=sys.stderr)
        if mode in ("base", "tcl", "flow"):
            print("Host Python needs working tkinter/_tkinter and headless Tcl; pip cannot install missing system extensions. Base creation also needs venv and ensurepip.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
