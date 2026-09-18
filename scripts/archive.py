#!/usr/bin/env python3
"""Curated evidence archive for one finished TT/LibreLane run directory.

A run directory is ~235 MB, most of it intermediate stage state and redundant
layout formats (odb, mag, mag_gds) that nothing reads again. This copies the
immutable records out, tars the reports an acceptance decision is read from
together with the two final artifacts a resubmission or a re-check needs, and
verifies every hash those records already pin.

What is kept is an explicit list, not a size rule. What belongs in evidence is
decided by what a reader has to check; a size threshold would silently drop a new
report the first time a flow stage grew one, and silently admit a big one.

Deliberately NOT kept: the compiled gate-level simulator (checks/*/gate.out, 9 MB
of iverilog output) and every intermediate stage directory. Both are rebuildable
from what is kept plus the pinned toolchain, and neither is read by a check.

Careful: this does not write the README.md that sits beside the records in
evidence/p4/*. That note is the human account of what the run showed, and a
generated stand-in would read as though someone had checked the result.

Usage:
  scripts/archive.py RUN_DIR --output evidence/p4/observable-physical
  scripts/archive.py RUN_DIR --output DIR --force   # replace a populated DIR
  scripts/archive.py RUN_DIR --list                 # print the selection, write nothing
"""

import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tarfile


SCRIPT = Path(__file__).resolve()


def load_phase4():
    spec = importlib.util.spec_from_file_location("phase4", SCRIPT.parent / "phase4.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


phase4 = load_phase4()

# Tar members, relative to the run directory. "{flow}" is run.json's outputs.flow
# rather than a literal "project/runs/asic", so a run whose flow directory moved
# still archives. A directory brings its whole subtree.
#
# The two synthesis and STA stage directories are taken whole (264 KB and 1.1 MB)
# instead of cherry-picked: at that size the risk of missing a report someone
# later needs costs more than the bytes.
KEEP = (
    "execution.log",
    "project/src/config.json",
    "{flow}/final/metrics.csv",
    "{flow}/final/metrics.json",
    "{flow}/final/sdc",
    "{flow}/final/gds",
    "{flow}/final/nl",
    "{flow}/06-yosys-synthesis",
    "{flow}/55-openroad-stapostpnr",
)

# Per postcheck attempt, relative to checks/<id>. gate.out is excluded here; see
# the module docstring.
KEEP_PER_CHECK = ("postcheck.log", "testbench.v", "tt/precheck/reports")

# Records copied beside the archive, uncompressed, so a reader can grep them
# without unpacking anything. manifest.json and postcheck.json are found rather
# than named: they live inside the run tree.
RECORDS = ("run.json", "results.json", "preflight.json")


def members(run_dir, flow):
    """Every path to archive, as (absolute path, name inside the tar).

    Missing entries are returned as omissions rather than raising: a synthesis
    only run has no final/gds and no checks, and that is a legitimate thing to
    archive. The caller decides which absences matter.
    """
    selected = []
    omitted = []
    candidates = [run_dir / entry.format(flow=flow) for entry in KEEP]
    for check in sorted((run_dir / "checks").glob("*/")):
        candidates += [check / entry for entry in KEEP_PER_CHECK]
    for path in candidates:
        name = str(path.relative_to(run_dir))
        if not path.exists():
            omitted.append(name)
        elif path.is_dir():
            # Sorted so the tar's member order does not depend on readdir order,
            # which is what makes two archives of one run compare equal.
            found = [(child, str(child.relative_to(run_dir)))
                     for child in sorted(path.rglob("*")) if child.is_file()]
            # An empty directory counts as absent, not as a satisfied entry. A
            # stage that ran but wrote nothing leaves one behind, and reporting it
            # as present would hide exactly the case worth noticing.
            selected += found
            if not found:
                omitted.append(name)
        else:
            selected.append((path, name))
    return selected, omitted


def verify(run_dir, record, checks):
    """Re-check every hash the run's own records already pin.

    The point of the archive is to be the thing someone trusts later, so it is
    built from bytes that still match what the run recorded consuming. Returns
    the verified digests; raises on the first disagreement.
    """
    verified = {}
    staged = run_dir / record["outputs"]["project"] / "manifest.json"
    digest = phase4.digest(staged)
    if digest != record["manifest_sha256"]:
        raise phase4.PrerequisiteError(
            "staged manifest does not match the run record; archive the run that "
            f"produced it, not a modified copy ({staged})")
    verified["manifest_sha256"] = digest

    # The GDS, netlist and testbench are hashed into postcheck.json when the
    # checks run. Verifying them here is what lets the archive stand in for the
    # run directory: the bytes it carries are provably the bytes that passed.
    flow = run_dir / record["outputs"]["flow"]
    top = phase4.read_json(run_dir / record["outputs"]["project"] / "manifest.json")
    top = top["top_module"]
    for check_dir, check in checks:
        inputs = check.get("inputs", {})
        for field, path in (
                ("gds_sha256", flow / "final/gds" / f"{top}.gds"),
                ("netlist_sha256", flow / "final/nl" / f"{top}.nl.v"),
                ("testbench_sha256", check_dir / "testbench.v")):
            expected = inputs.get(field)
            if expected is None or not path.is_file():
                continue
            if phase4.digest(path) != expected:
                raise phase4.PrerequisiteError(
                    f"{path.relative_to(run_dir)} does not match {field} in "
                    f"{(check_dir / 'postcheck.json').relative_to(run_dir)}; the run "
                    "directory was modified after the checks ran")
            verified[field] = expected
    return verified


def archive(run_dir, output, force):
    record = phase4.read_json(run_dir / "run.json")
    if record["status"] != "completed":
        raise phase4.PrerequisiteError(
            f"run status is {record['status']}, not completed; archive a finished run")
    flow = record["outputs"]["flow"]

    checks = [(path.parent, phase4.read_json(path))
              for path in sorted((run_dir / "checks").glob("*/postcheck.json"))]
    verified = verify(run_dir, record, checks)
    selected, omitted = members(run_dir, flow)

    if output.exists() and any(output.iterdir()) and not force:
        raise phase4.PrerequisiteError(
            f"{output} already has files; use --force to replace them")
    output.mkdir(parents=True, exist_ok=True)

    # Written before the tar, so a reader who finds a truncated archive still has
    # the records naming what it should have held.
    manifest_source = run_dir / record["outputs"]["project"] / "manifest.json"
    shutil.copy2(manifest_source, output / "manifest.json")
    for name in RECORDS:
        # An absent record is reported, never skipped quietly: runs from before
        # flow.sh saved preflight.json have none, and an evidence directory that
        # is missing one should say so rather than look complete.
        if (run_dir / name).is_file():
            shutil.copy2(run_dir / name, output / name)
        else:
            omitted.append(name)
    for check_dir, _ in checks:
        # One postcheck attempt keeps the plain name the README links; a rerun
        # gets its check id, so neither silently overwrites the other.
        name = "postcheck.json" if len(checks) == 1 else f"postcheck-{check_dir.name}.json"
        shutil.copy2(check_dir / "postcheck.json", output / name)

    tarball = output / "reports.tar.gz"
    with tarfile.open(tarball, "w:gz") as stream:
        for path, name in selected:
            stream.add(path, arcname=name)

    phase4.save(output / "archive.json", {
        "schema_version": 1,
        "run_id": record["run_id"],
        "build_identity": record["build_identity"],
        "created_at": phase4.now(),
        "source_run": str(run_dir),
        "archive": tarball.name,
        "archive_bytes": tarball.stat().st_size,
        "verified": verified,
        "members": sorted(name for _, name in selected),
        "omitted": sorted(omitted),
        "records": sorted(path.name for path in output.glob("*.json")
                          if path.name != "archive.json"),
    })
    return tarball, selected, omitted


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("run_dir", type=Path)
    parser.add_argument("--output", type=Path, help="Evidence directory to write")
    parser.add_argument("--force", action="store_true",
                        help="Replace files in a populated --output")
    parser.add_argument("--list", action="store_true",
                        help="Print the selection and write nothing")
    args = parser.parse_args()
    try:
        run_dir = args.run_dir.resolve()
        if args.list:
            record = phase4.read_json(run_dir / "run.json")
            selected, omitted = members(run_dir, record["outputs"]["flow"])
            total = sum(path.stat().st_size for path, _ in selected)
            for _, name in selected:
                print(name)
            for name in omitted:
                print(f"absent: {name}", file=sys.stderr)
            print(f"\n{len(selected)} files, {total / 1e6:.1f} MB uncompressed",
                  file=sys.stderr)
            return 0
        if not args.output:
            raise phase4.PrerequisiteError("--output is required unless --list is given")
        tarball, selected, omitted = archive(run_dir, args.output.resolve(), args.force)
        for name in omitted:
            print(f"archive: absent, not included: {name}", file=sys.stderr)
        print(f"archive: {len(selected)} files -> {tarball} "
              f"({tarball.stat().st_size / 1e6:.2f} MB)")
        return 0
    except (OSError, ValueError, KeyError, phase4.PrerequisiteError) as exc:
        print(f"archive: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
