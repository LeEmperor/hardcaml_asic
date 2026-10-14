"""Explicit CLI4 delegation; OCaml owns execution and persisted-record validation.

Installed helpers are selected from this package's prefix, never PATH. Source
adapters use the Dune-built equivalents and fail actionably when not built.
"""
import json
import os
from pathlib import Path
import subprocess


PACKAGE = Path(__file__).resolve().parent


def binary(name):
    if PACKAGE.parent.name == "flow" and PACKAGE.parents[1].name == "hardcaml_asic" and PACKAGE.parents[2].name == "lib":
        path = PACKAGE.parents[3] / "bin" / ("hardcaml-asic-experimental-" + name.replace("_", "-"))
        remedy = "Reinstall hardcaml_asic into this prefix."
    else:
        path = PACKAGE.parents[1] / "_build/default/bin" / ("experimental_" + name + ".exe")
        # Dune test imports live in _build/default/flow already.
        if PACKAGE.parents[1].name == "default":
            path = PACKAGE.parents[1] / "bin" / ("experimental_" + name + ".exe")
        remedy = "Run dune build -j20 @install in the provider checkout."
    if not path.is_file() or not os.access(path, os.X_OK):
        raise OSError(f"OCaml backend is missing: {path}. {remedy}")
    return path


def query(name, arguments):
    result = subprocess.run([str(binary(name)), *map(str, arguments)],
                            capture_output=True, text=True, check=False)
    if result.returncode not in (0, 2):
        raise OSError(f"OCaml {name} exited {result.returncode}: {result.stderr.strip()}")
    try:
        value = json.loads(result.stdout)
    except ValueError as exc:
        raise OSError(f"OCaml {name} returned no valid payload: {result.stderr.strip()}") from exc
    return result.returncode, value


def stages(args, cwd, absolute, interpreter_absolute):
    executable = binary("stages")
    workspace = absolute(args.workspace, cwd)
    evidence_root = workspace.parent / "stage-preflight"
    if evidence_root == workspace:
        evidence_root = workspace.parent / "stage-preflight-evidence"
    command = [str(executable), "--public-cli4", "--bundle", str(absolute(args.bundle, cwd)),
               "--resources", str(PACKAGE), "--workspace", str(workspace),
               "--checkpoint-store", str(absolute(args.checkpoint_store, cwd)),
                "--evidence-root", str(evidence_root),
               "--support-tools", str(absolute(args.support_tools, cwd)),
               "--pdk-root", str(absolute(args.pdk_root, cwd)),
               "--python", str(interpreter_absolute(args.python, cwd)),
               "--timeout", str(args.timeout), "--request", json.dumps({"caller_cwd": str(cwd.resolve()),
                   **{k: str(v) if isinstance(v, Path) else v for k, v in vars(args).items()}}, allow_nan=False)]
    for name, flag in (("endpoint", "through"), ("plan", "plan"),
                       ("checkpoint", "checkpoint"), ("observation_store", "observation-store")):
        value = getattr(args, name)
        if value is not None:
            command += ["--" + flag, str(value if name == "endpoint" else absolute(value, cwd))]
    for name in ("json", "no_observation"):
        if getattr(args, name):
            command.append("--" + name.replace("_", "-"))
    # No supervising Python process: PID and signal delivery survive delegation.
    os.execv(str(executable), command)


def watch(args, directory):
    executable = binary("observation_read")
    command = [str(executable), "watch", str(directory), "--interval", str(args.interval)]
    if args.json:
        command.append("--json")
    for name, flag in (("stream_id", "--stream-id"), ("after", "--after")):
        value = getattr(args, name)
        if value is not None:
            command += [flag, str(value)]
    os.execv(str(executable), command)
