#!/usr/bin/env python3
"""Human-readable summary of one TT/LibreLane run directory.

Replaces the ad hoc "cat | grep" and "python3 -c" one-liners around a finished
run: it reads the same results.json that phase4.py collect writes (computing it
in memory when it is missing), adds the per-corner timing table, the TT precheck
rows, and the resizer's own account of what it repaired, then exits nonzero when
anything is not a pass.

An unconstrained timing mode counts as a failure on purpose. A "-max" only SDC
leaves hold with no paths at all, which every individual check reports as fine.

Usage:
  scripts/report.py RUN_DIR
  scripts/report.py --runs RUNS_DIR     # the newest run under RUNS_DIR
  scripts/report.py RUN_DIR --json      # the collected record, unformatted
"""

import argparse
import csv
import importlib.util
import json
from pathlib import Path
import re
import sys


SCRIPT = Path(__file__).resolve()


def load_phase4():
    spec = importlib.util.spec_from_file_location("phase4", SCRIPT.parent / "phase4.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def newest_run(runs):
    candidates = [path for path in runs.iterdir() if (path / "run.json").is_file()]
    if not candidates:
        raise SystemExit(f"report: no run directory under {runs}")
    return max(candidates, key=lambda path: path.stat().st_mtime)


def results_for(run_dir):
    """The collected record; the stored one when present, else collected now."""
    stored = run_dir / "results.json"
    if stored.is_file():
        return json.loads(stored.read_text()), str(stored.relative_to(run_dir))
    return load_phase4().collect(run_dir), "collected in memory"


def flow_dir(run_dir, record):
    return run_dir / record.get("outputs", {}).get("flow", "project/runs/asic")


def corner_timing(metrics_csv):
    """Per-corner setup/hold worst slack and violation counts from metrics.csv.

    Hold slack is reported as 1e39 when STA found no hold path at all; that is
    kept as None here rather than printed as a number.
    """
    if not metrics_csv.is_file():
        return {}
    corners = {}
    pattern = re.compile(r"^timing__(setup|hold)__(ws|tns)__corner:(.+)$")
    counts = re.compile(r"^timing__(setup|hold)_vio__count__corner:(.+)$")
    with metrics_csv.open(newline="") as stream:
        for row in csv.reader(stream):
            if len(row) != 2:
                continue
            key, raw = row
            match = pattern.match(key) or counts.match(key)
            if not match:
                continue
            try:
                value = float(raw)
            except ValueError:
                continue
            if pattern.match(key):
                mode, field, corner = match.groups()
            else:
                mode, corner = match.groups()
                field = "vio"
            if field == "ws" and abs(value) > 1e30:
                value = None
            corners.setdefault(corner, {})[f"{mode}_{field}"] = value
    return corners


def precheck_rows(run_dir):
    """(check, result) pairs from every TT precheck results.md under the run."""
    rows = []
    for report in sorted(run_dir.glob("checks/*/tt/precheck/reports/results.md")):
        for line in report.read_text().splitlines():
            cells = [cell.strip() for cell in line.split("|")[1:-1]]
            if len(cells) == 2 and cells[0] not in ("Check", "") and "---" not in cells[1]:
                rows.append((cells[0], cells[1]))
    return rows


def hold_repair(run_dir, record):
    """What the post-CTS resizer said about hold; its log is the only account.

    "No hold violations found" means nothing was repaired, which is the right
    outcome only when the SDC actually constrained hold. See docs/target-reference.md.
    """
    lines = []
    for log in sorted(flow_dir(run_dir, record).glob("*resizer*/*.log")):
        for line in log.read_text().splitlines():
            if re.search(r"RSZ-00(33|98)|repair_timing .*-hold|Hold violation", line):
                lines.append((log.parent.name, line.strip()))
    return lines


def number(value, digits=3):
    return "n/a" if value is None else f"{value:.{digits}f}"


def report(run_dir, results, source):
    problems = []
    out = print

    record = json.loads((run_dir / "run.json").read_text())
    out(f"run        {results.get('run_id')}  ({run_dir})")
    out(f"bundle     {record.get('bundle')}")
    out(f"status     {results.get('process_status')}"
        f"   stage {results.get('completed_stage')} of {results.get('requested_stage')}"
        f"   source {source}")
    if results.get("process_status") != "completed":
        problems.append(f"process status {results.get('process_status')}")
    for error in results.get("errors") or []:
        problems.append(f"collection error: {error}")

    out("\nTIMING")
    goal = results.get("timing_goal")
    unconstrained = results.get("timing_unconstrained_modes") or []
    out(f"  goal {goal}")
    if goal != "pass":
        problems.append(f"timing goal {goal}")
    if unconstrained:
        out(f"  UNCONSTRAINED: {', '.join(unconstrained)}"
            "  (no constrained paths reported; the SDC does not check this mode)")
        problems.append(f"unconstrained timing modes: {', '.join(unconstrained)}")
    metrics = results.get("metrics") or {}
    for name in ("setup_slack", "hold_slack"):
        item = metrics.get(name) or {}
        reason = item.get("unavailable_reason")
        out(f"  {name:<12} {number(item.get('value')):>10} ns"
            f"   corner {item.get('corner') or '-'}"
            f"{'   ' + reason if reason else ''}")
    corners = corner_timing(flow_dir(run_dir, record) / "final/metrics.csv")
    if corners:
        out(f"  {'corner':<22}{'setup ws':>10}{'setup vio':>11}"
            f"{'hold ws':>10}{'hold vio':>10}")
        for corner, values in sorted(corners.items()):
            out(f"  {corner:<22}{number(values.get('setup_ws')):>10}"
                f"{number(values.get('setup_vio'), 0):>11}"
                f"{number(values.get('hold_ws')):>10}"
                f"{number(values.get('hold_vio'), 0):>10}")

    out("\nSIGNOFF CHECKS")
    for name, item in sorted((results.get("checks") or {}).items()):
        note = item.get("reason")
        status = f"{item.get('status'):<8}  {note}" if note else item.get("status")
        out(f"  {name:<10} {status}")
        if item.get("status") != "pass":
            problems.append(f"{name} {item.get('status')}")
    for name, item in sorted((results.get("synthesis_checks") or {}).items()):
        value = item.get("value")
        out(f"  {name:<22} {number(value, 0)}")
        if value:
            problems.append(f"{name} = {number(value, 0)}")

    postchecks = results.get("postchecks") or []
    out("\nPOSTCHECKS" if postchecks else "\nPOSTCHECKS  none recorded")
    for entry in postchecks:
        for name, status in sorted((entry.get("checks") or {}).items()):
            out(f"  {name:<12} {status}")
            if status != "pass":
                problems.append(f"{name} {status}")
    rows = precheck_rows(run_dir)
    for check, result in rows:
        out(f"    {check:<44} {result}")

    repair = hold_repair(run_dir, record)
    out("\nHOLD REPAIR (post-CTS resizer)" if repair else "\nHOLD REPAIR  no resizer log found")
    for step, line in repair:
        out(f"  [{step}] {line}")

    sdc = run_dir / "project/constraints/top.sdc"
    if sdc.is_file():
        out(f"\nCONSTRAINTS ({sdc.relative_to(run_dir)})")
        for line in sdc.read_text().splitlines():
            out(f"  {line}")

    out("")
    if problems:
        out("PROBLEMS")
        for problem in problems:
            out(f"  - {problem}")
        return 1
    out("all reported checks passed")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("run_dir", nargs="?", type=Path)
    parser.add_argument("--runs", type=Path, help="Report on the newest run under this directory")
    parser.add_argument("--json", action="store_true", help="Print the collected record instead")
    args = parser.parse_args()
    if bool(args.run_dir) == bool(args.runs):
        parser.error("give exactly one of RUN_DIR or --runs")
    run_dir = (args.run_dir or newest_run(args.runs.resolve())).resolve()
    if not (run_dir / "run.json").is_file():
        raise SystemExit(f"report: not a run directory (no run.json): {run_dir}")
    results, source = results_for(run_dir)
    if args.json:
        print(json.dumps(results, indent=2, sort_keys=True))
        return 0
    return report(run_dir, results, source)


if __name__ == "__main__":
    sys.exit(main())
