#!/usr/bin/env python3
"""External TT/LibreLane bundle preflight, execution, and result collection."""

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import sys
import uuid


class PrerequisiteError(Exception):
    pass


def now():
    return datetime.now(timezone.utc).isoformat()


def interrupt_on_terminate(_signum, _frame):
    raise KeyboardInterrupt


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def read_json(path):
    return json.loads(path.read_text())


def safe_child(root, relative):
    if not isinstance(relative, str) or not relative or Path(relative).is_absolute():
        raise PrerequisiteError(f"invalid relative path: {relative!r}")
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise PrerequisiteError(f"path escapes its root: {relative}")
    return path


def command_output(argv):
    result = subprocess.run(argv, capture_output=True, text=True, check=False)
    if result.returncode:
        raise PrerequisiteError(f"command failed: {argv!r}: {result.stderr.strip()}")
    return result.stdout.strip()


def preflight(bundle, support_tools, pdk_root, python, allow_python_mismatch=False,
              native=False):
    issues = []
    waivers = []
    manifest = read_json(bundle / "manifest.json")
    requested = manifest["requested_tools"]
    if manifest.get("schema_version") != 1 or manifest.get("adapter") != "LibreLane":
        issues.append("unsupported bundle schema or adapter")
    for entry in manifest["files"]:
        try:
            path = safe_child(bundle, entry["path"])
            if not path.is_file() or digest(path) != entry["sha256"]:
                issues.append(f"missing or changed bundle file: {entry['path']}")
        except (KeyError, PrerequisiteError) as exc:
            issues.append(str(exc))
    for root, expected, label in (
        (support_tools, requested["support_tools_revision"], "support tools"),
        (pdk_root, requested["pdk_revision"], "PDK"),
    ):
        try:
            actual = command_output(["git", "-C", str(root), "rev-parse", "HEAD"])
            if actual != expected:
                issues.append(f"{label} revision {actual}; requested {expected}")
        except PrerequisiteError as exc:
            issues.append(str(exc))
    references = []
    for ref in manifest["target"]["external_references"]:
        repo = support_tools if ref["source"] == "Support_tools" else pdk_root
        root = support_tools if ref["source"] == "Support_tools" else pdk_root / manifest["target"]["technology"]
        try:
            path = safe_child(root, ref["path"])
            if not path.is_file():
                issues.append(f"missing {ref['role']}: {path}")
            else:
                actual_hash = digest(path)
                references.append({"role": ref["role"], "path": str(path),
                                   "sha256": actual_hash})
                if ref.get("sha256") and actual_hash != ref["sha256"]:
                    issues.append(f"changed {ref['role']}: {path}")
                status = command_output(["git", "-C", str(repo), "status",
                                         "--porcelain", "--", str(path)])
                if status:
                    issues.append(f"modified {ref['role']}: {path}")
        except (KeyError, PrerequisiteError) as exc:
            issues.append(str(exc))
    versions = {}
    try:
        versions["python"] = command_output([str(python), "-c", "import sys; print('.'.join(map(str, sys.version_info[:3])))"])
        versions["librelane"] = command_output([str(python), "-c", "from importlib.metadata import version; print(version('librelane'))"])
        if versions["librelane"] != requested["librelane"]:
            issues.append(f"LibreLane {versions['librelane']}; requested {requested['librelane']}")
        if not versions["python"].startswith(requested["python"] + "."):
            mismatch = f"Python {versions['python']}; requested {requested['python']}"
            (waivers if allow_python_mismatch else issues).append(mismatch)
    except PrerequisiteError as exc:
        issues.append(str(exc))
    if not native:
        try:
            versions["docker_server"] = command_output(
                ["docker", "info", "--format", "{{.ServerVersion}}"])
            image = f"ghcr.io/librelane/librelane:{requested['librelane']}"
            versions["librelane_image"] = command_output(
                ["docker", "image", "inspect", "--format", "{{.Id}}", image])
            versions["container_python"] = command_output(
                ["docker", "run", "--rm", "--pull=never", "--entrypoint", "python",
                 image, "--version"]).removeprefix("Python ")
            if not versions["container_python"].startswith(requested["python"] + "."):
                mismatch = (f"container Python {versions['container_python']}; "
                            f"requested {requested['python']}")
                (waivers if allow_python_mismatch else issues).append(mismatch)
        except PrerequisiteError as exc:
            issues.append(str(exc))
    return {"ready": not issues, "issues": issues, "waivers": waivers,
            "references": references,
            "requested": requested,
            "actual": versions, "support_tools": str(support_tools.resolve()),
            "pdk_root": str(pdk_root.resolve()), "python": str(python.absolute())}


def run_logged(argv, cwd, env, log, record, record_path):
    record["commands"].append(argv)
    save(record_path, record)
    with log.open("a") as stream:
        stream.write(f"\n$ {shlex.join(argv)}\n")
        stream.flush()
        with subprocess.Popen(argv, cwd=cwd, env=env, stdout=stream,
                              stderr=subprocess.STDOUT, start_new_session=True) as process:
            try:
                return process.wait()
            except KeyboardInterrupt:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait()
                raise


def execute(args):
    bundle = args.bundle.resolve()
    manifest = read_json(bundle / "manifest.json")
    run_id = uuid.uuid4().hex
    run_dir = args.runs.resolve() / run_id
    run_dir.mkdir(parents=True, exist_ok=False)
    record_path = run_dir / "run.json"
    record = {"schema_version": 1, "run_id": run_id,
              "build_identity": manifest["identity"], "bundle": str(bundle),
              "manifest_sha256": digest(bundle / "manifest.json"),
              "started_at": now(), "ended_at": None,
              "requested_stage": args.stage, "completed_stage": None,
              "status": "starting", "commands": [], "logs": ["execution.log"],
              "outputs": {"project": "project", "flow": "project/runs/asic"}}
    save(record_path, record)
    log = run_dir / "execution.log"
    try:
        check = preflight(bundle, args.support_tools, args.pdk_root, args.python,
                          args.allow_python_mismatch, args.native)
        record["environment"] = check
        if not check["ready"]:
            raise PrerequisiteError("; ".join(check["issues"]))
        project = run_dir / "project"
        shutil.copytree(bundle, project)
        for ref in manifest["target"]["external_references"]:
            if ref["source"] == "Support_tools":
                source = safe_child(args.support_tools.resolve(), ref["path"])
                destination = safe_child(project / "tt", ref["path"])
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)
        (project / "runs/asic").mkdir(parents=True)
        if digest(project / "manifest.json") != record["manifest_sha256"]:
            raise PrerequisiteError("staged manifest differs from original bundle")
        env = os.environ.copy()
        env["PATH"] = str(args.python.parent) + os.pathsep + env.get("PATH", "")
        env["PDK_ROOT"] = str(args.pdk_root.resolve())
        env["PDK"] = manifest["target"]["technology"]
        record["status"] = "running"
        save(record_path, record)
        # P3 already emitted the complete, resolved config. Calling TT's
        # create_user_config here would rewrite it and its WASM Yosys port probe
        # cannot read an absolute staged path. Run the exact emitted config.
        flow = [str(args.python), "-m", "librelane"]
        if not args.native:
            flow += ["--docker-no-tty", "--dockerized"]
        flow += ["--pdk-root", str(args.pdk_root.resolve()),
                "--pdk", manifest["target"]["technology"], "--manual-pdk",
                "--run-tag", "asic", "--force-run-dir", "runs/asic"]
        record["execution_mode"] = "native" if args.native else "dockerized"
        if args.stage == "synthesis":
            flow += ["--to", "Yosys.Synthesis"]
        flow += ["src/config.json"]
        if run_logged(flow, project, env, log, record, record_path):
            raise RuntimeError("LibreLane failed; see execution.log and project/runs/asic")
        if (digest(project / "manifest.json") != record["manifest_sha256"]
                or digest(bundle / "manifest.json") != record["manifest_sha256"]):
            raise RuntimeError("build manifest changed during execution")
        record["completed_stage"] = args.stage
        record["status"] = "completed"
    except KeyboardInterrupt:
        record["status"] = "interrupted"
        record["error"] = "interrupted by user"
    except Exception as exc:
        record["status"] = "failed"
        record["error"] = str(exc)
    finally:
        record["ended_at"] = now()
        save(record_path, record)
    print(record_path)
    if record["status"] != "completed":
        print(record["error"], file=sys.stderr)
        return 1
    return 0


def postcheck(args):
    run_dir = args.run_dir.resolve()
    run = read_json(run_dir / "run.json")
    if run["status"] != "completed" or run["completed_stage"] != "full":
        raise PrerequisiteError("postcheck requires a completed full flow")
    flow = run_dir / run["outputs"]["flow"]
    top = read_json(run_dir / "project/manifest.json")["top_module"]
    gds = flow / "final/gds" / f"{top}.gds"
    netlist = flow / "final/nl" / f"{top}.nl.v"
    for path in (gds, netlist, args.testbench, args.precheck_python,
                 args.support_tools / "precheck/default.nix"):
        if not path.is_file():
            raise PrerequisiteError(f"missing postcheck input: {path}")
    check_dir = run_dir / "checks" / uuid.uuid4().hex
    check_dir.mkdir(parents=True)
    record_path = check_dir / "postcheck.json"
    record = {"schema_version": 1, "run_id": run["run_id"],
              "build_identity": run["build_identity"], "started_at": now(),
              "ended_at": None, "status": "running", "commands": [],
              "checks": {"precheck": "pending", "gate_level": "pending"},
              "inputs": {"gds_sha256": digest(gds), "netlist_sha256": digest(netlist),
                         "testbench_sha256": digest(args.testbench)},
              "logs": ["postcheck.log"], "tools": {}}
    save(record_path, record)
    log = check_dir / "postcheck.log"
    env = os.environ.copy()
    env["PDK_ROOT"] = str(args.pdk_root.resolve())
    env["PDK"] = "ihp-sg13cmos5l"
    work = check_dir / "tt"
    try:
        shutil.copytree(args.support_tools / "precheck", work / "precheck")
        (work / "tech").symlink_to((args.support_tools / "tech").resolve(),
                                   target_is_directory=True)
        pin = read_json(work / "precheck/tool-versions.json")["klayout"]
        native_klayout = command_output(
            ["nix-shell", "default.nix", "--run", "klayout -v"])
        record["tools"]["klayout"] = native_klayout
        record["tools"]["klayout_requested"] = pin
        if native_klayout != f"KLayout {pin}":
            raise PrerequisiteError(f"precheck KLayout {native_klayout}; requested {pin}")
        record["tools"]["precheck_python_klayout"] = command_output(
            [str(args.precheck_python.absolute()), "-c",
             "from importlib.metadata import version; print(version('klayout'))"])
        if not record["tools"]["precheck_python_klayout"].startswith("0.28."):
            raise PrerequisiteError("precheck Python KLayout package must be 0.28.x")
        record["tools"]["iverilog"] = command_output(["iverilog", "-V"]).splitlines()[0]
        save(record_path, record)
        precheck_command = ("exec env -u PYTHONPATH -u PYTHONHOME "
                            + " ".join(shlex.quote(x) for x in
                                       (str(args.precheck_python.absolute()), "precheck.py",
                                        "--gds", str(gds), "--tech", "ihp-sg13cmos5l")))
        code = run_logged(["nix-shell", "default.nix", "--run", precheck_command],
                          work / "precheck", env, log, record, record_path)
        record["checks"]["precheck"] = "pass" if code == 0 else "fail"
        save(record_path, record)
        models = [args.pdk_root / "ihp-sg13cmos5l/libs.ref/sg13cmos5l_io/verilog/sg13cmos5l_io.v",
                  args.pdk_root / "ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog/sg13cmos5l_stdcell.v"]
        if not all(path.is_file() for path in models):
            raise PrerequisiteError("missing gate-level PDK Verilog models")
        testbench = check_dir / "testbench.v"
        shutil.copy2(args.testbench, testbench)
        executable = check_dir / "gate.out"
        compile_command = ["iverilog", "-g2012", "-DFUNCTIONAL", "-DSIM",
                           "-s", "tb_observable", "-o", str(executable),
                           *(str(path) for path in models), str(netlist), str(testbench)]
        if run_logged(compile_command, check_dir, env, log, record, record_path):
            record["checks"]["gate_level"] = "fail"
        elif run_logged(["vvp", str(executable)], check_dir, env, log, record, record_path):
            record["checks"]["gate_level"] = "fail"
        else:
            record["checks"]["gate_level"] = "pass"
        record["status"] = "completed" if all(
            value == "pass" for value in record["checks"].values()) else "failed"
    except KeyboardInterrupt:
        record["status"] = "interrupted"
    except Exception as exc:
        record["status"] = "failed"
        record["error"] = str(exc)
    finally:
        record["reports"] = [str(path.relative_to(check_dir)) for path in
                             sorted((work / "precheck/reports").glob("*")) if path.is_file()]
        record["ended_at"] = now()
        save(record_path, record)
    print(record_path)
    return 0 if record["status"] == "completed" else 1


def metric(value, unit, definition, stage, source, corner=None, reason=None):
    return {"value": value, "unit": unit, "definition": definition,
            "stage": stage, "corner": corner, "source": source,
            "unavailable_reason": reason if value is None else None}


def collect(run_dir):
    record = read_json(run_dir / "run.json")
    flow = run_dir / record["outputs"]["flow"]
    synth = flow / "06-yosys-synthesis/reports/stat.json"
    synth_state = flow / "06-yosys-synthesis/state_out.json"
    metrics = flow / "final/metrics.csv"
    values = {}
    errors = []
    if metrics.is_file():
        try:
            with metrics.open(newline="") as stream:
                for row in csv.reader(stream):
                    if len(row) != 2:
                        raise ValueError(f"expected two columns, got {row!r}")
                    values[row[0]] = row[1]
        except (OSError, ValueError) as exc:
            errors.append(f"{metrics.relative_to(run_dir)}: {exc}")
            values = {}
    stats = None
    synth_creator = None
    if synth.is_file():
        try:
            report = read_json(synth)
            stats = report["design"]
            synth_creator = report.get("creator")
            if not isinstance(stats, dict):
                raise TypeError("design must be an object")
        except (ValueError, KeyError, TypeError) as exc:
            errors.append(f"{synth.relative_to(run_dir)}: {exc}")
            stats = None
    state_metrics = {}
    if synth_state.is_file():
        try:
            state_metrics = read_json(synth_state)["metrics"]
        except (ValueError, KeyError, TypeError) as exc:
            errors.append(f"{synth_state.relative_to(run_dir)}: {exc}")
    def number(raw, label):
        if raw is None:
            return None, "report absent or metric missing"
        try:
            value = float(raw)
            if not math.isfinite(value):
                raise ValueError("nonfinite")
            return value, None
        except (TypeError, ValueError):
            errors.append(f"malformed {label}: {raw!r}")
            return None, "malformed metric"
    output = {}
    for name, field, unit, definition in (
        ("mapped_area", "area", "um^2", "sum of mapped standard-cell areas"),
        ("sequential_area", "sequential_area", "um^2", "mapped sequential-cell area"),
        ("mapped_cells", "num_cells", "cells", "mapped standard-cell instance count"),
    ):
        value, reason = number(stats.get(field) if stats else None, name)
        output[name] = metric(value, unit, definition, "Yosys.Synthesis",
                              str(synth.relative_to(run_dir)), reason=reason)
    for name, prefix in (("setup_slack", "timing__setup__ws"),
                         ("hold_slack", "timing__hold__ws")):
        matches = [(key, raw) for key, raw in values.items() if key.startswith(prefix)]
        parsed = [(key, *number(raw, key)) for key, raw in matches]
        valid = [(key, value) for key, value, _ in parsed if value is not None]
        key, value = min(valid, key=lambda item: item[1]) if valid else (None, None)
        corner = key.split("corner:", 1)[1] if key and "corner:" in key else None
        output[name] = metric(value, "ns", "worst slack across reported corners",
                              "final", str(metrics.relative_to(run_dir)), corner,
                              None if value is not None else "report absent or metric missing")
    for name, field, unit, definition in (
        ("final_standard_cell_area", "design__instance__area__stdcell", "um^2",
         "standard-cell area after the completed physical flow"),
        ("final_utilization", "design__instance__utilization__stdcell", "fraction",
         "standard-cell area divided by placement area"),
    ):
        value, reason = number(values.get(field), name)
        output[name] = metric(value, unit, definition, "final",
                              str(metrics.relative_to(run_dir)), reason=reason)
    checks = {}
    for name, keys in (("drc", ("route__drc_errors", "magic__drc_error__count")),
                       ("lvs", ("design__lvs_error__count",)),
                       ("antenna", ("antenna__violating__nets", "antenna__violating__pins"))):
        matches = {key: values[key] for key in keys if key in values}
        numeric = {key: number(raw, key)[0] for key, raw in matches.items()}
        if len(matches) != len(keys):
            status, reason = "unknown", "metric missing"
        elif any(value is None for value in numeric.values()):
            status, reason = "unknown", "malformed metric"
        else:
            status = "pass" if all(value == 0 for value in numeric.values()) else "fail"
            reason = None
        checks[name] = {"status": status, "source": str(metrics.relative_to(run_dir)),
                        "raw": matches, "reason": reason}
    setup = output["setup_slack"]["value"]
    hold = output["hold_slack"]["value"]
    timing_goal = "unknown" if setup is None or hold is None else (
        "pass" if setup >= 0 and hold >= 0 else "fail")
    cells = stats.get("num_cells_by_type") if stats else None
    synthesis_checks = {}
    for label, field in (("unmapped_instances", "design__instance_unmapped__count"),
                         ("synthesis_errors", "synthesis__check_error__count"),
                         ("inferred_latches", "design__inferred_latch__count")):
        value, reason = number(state_metrics.get(field), label)
        synthesis_checks[label] = metric(value, "count", field, "Yosys.Synthesis",
                                         str(synth_state.relative_to(run_dir)), reason=reason)
    manifest = read_json(run_dir / "project/manifest.json") if (
        run_dir / "project/manifest.json").is_file() else {}
    librelane_tool = {"name": "LibreLane", "version": record.get(
        "environment", {}).get("actual", {}).get("librelane")}
    yosys_tool = {"name": "Yosys", "version": synth_creator}
    for name, item in checks.items():
        item.update({"definition": f"reported {name} violation counts are zero",
                     "unit": "count", "stage": "final", "corner": None,
                     "tool": librelane_tool})
    for name, item in output.items():
        synthesis = item["stage"] == "Yosys.Synthesis"
        item["tool"] = yosys_tool if synthesis else librelane_tool
        item["mode"] = "synthesis" if synthesis else (
            "setup" if name == "setup_slack" else "hold" if name == "hold_slack"
            else "physical")
        if synthesis:
            item["corner"] = manifest.get("target", {}).get("corner")
    for item in synthesis_checks.values():
        item["tool"] = yosys_tool
        item["mode"] = "synthesis"
        item["corner"] = manifest.get("target", {}).get("corner")
    result = {"schema_version": 1, "run_id": record["run_id"],
              "build_identity": record["build_identity"], "process_status": record["status"],
              "requested_stage": record["requested_stage"],
              "completed_stage": record["completed_stage"],
              "tool": librelane_tool,
              "mode": "nominal and reported corners", "metrics": output, "checks": checks,
              "timing_goal": timing_goal,
              "mapped_cell_types": cells,
              "synthesis_checks": synthesis_checks,
              "raw_artifacts": sorted(str(path.relative_to(run_dir)) for path in
                                      set((synth, metrics, synth_state,
                                           flow / "final/metrics.json")
                                          + tuple(flow.glob("*/reports/*.rpt"))
                                          + tuple(flow.glob("*/reports/*.json"))
                                          + tuple((flow / "final/gds").glob("*.gds"))
                                          + tuple((flow / "final/nl").glob("*.v")))
                                      if path.is_file()),
              "errors": errors}
    result["postchecks"] = [read_json(path) for path in
                            sorted((run_dir / "checks").glob("*/postcheck.json"))]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    for name in ("preflight", "run"):
        p = sub.add_parser(name)
        p.add_argument("bundle", type=Path)
        p.add_argument("--support-tools", required=True, type=Path)
        p.add_argument("--pdk-root", required=True, type=Path)
        p.add_argument("--python", required=True, type=Path)
        p.add_argument("--allow-python-mismatch", action="store_true")
        p.add_argument("--native", action="store_true", help="Use locally installed EDA tools")
        if name == "run":
            p.add_argument("--runs", required=True, type=Path)
            p.add_argument("--stage", choices=("synthesis", "full"), default="synthesis")
    p = sub.add_parser("collect")
    p.add_argument("run_dir", type=Path)
    p.add_argument("--output", type=Path)
    p = sub.add_parser("postcheck")
    p.add_argument("run_dir", type=Path)
    p.add_argument("--support-tools", required=True, type=Path)
    p.add_argument("--pdk-root", required=True, type=Path)
    p.add_argument("--precheck-python", required=True, type=Path)
    p.add_argument("--testbench", required=True, type=Path)
    args = parser.parse_args()
    try:
        if args.action == "preflight":
            result = preflight(args.bundle.resolve(), args.support_tools, args.pdk_root,
                               args.python, args.allow_python_mismatch, args.native)
            print(json.dumps(result, indent=2, sort_keys=True))
            return 0 if result["ready"] else 1
        if args.action == "run":
            signal.signal(signal.SIGTERM, interrupt_on_terminate)
            return execute(args)
        if args.action == "postcheck":
            return postcheck(args)
        result = collect(args.run_dir.resolve())
        if args.output:
            save(args.output, result)
        else:
            print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except (OSError, ValueError, KeyError, PrerequisiteError) as exc:
        print(f"phase4: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
