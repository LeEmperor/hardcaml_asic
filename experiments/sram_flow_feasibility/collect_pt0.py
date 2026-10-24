#!/usr/bin/env python3
"""Collect completed PT.0 evidence without EDA. Collection needs gdstk; verify is stdlib.

Use .toolchain/.venv-precheck/bin/python -B experiments/sram_flow_feasibility/collect_pt0.py
Verify: python3 -B experiments/sram_flow_feasibility/collect_pt0.py --verify ARCHIVE
"""
import argparse
from collections import defaultdict
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import tarfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "experiments/sram_flow_feasibility"
MACRO = "RM_IHPSG13_1P_256x16_c2_bm_bist"
TAGS = ("corrected-grid-02", "corners-01", "magic-01", "power-01")


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n").encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_sha(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def drc_summary(path):
    groups = defaultdict(list)
    category = None
    for line in path.read_text().splitlines()[2:]:
        match = re.fullmatch(r"\s*([-\d.]+)um\s+([-\d.]+)um\s+([-\d.]+)um\s+([-\d.]+)um", line)
        if match:
            groups[category].append(list(map(float, match.groups())))
        elif line and not line.startswith(("-", "[")):
            category = line
    return {name: {"count": len(boxes), "first_rectangle_um": boxes[0],
                   "bounds_um": [min(b[0] for b in boxes), min(b[1] for b in boxes),
                                 max(b[2] for b in boxes), max(b[3] for b in boxes)],
                   "outside_macro_bbox": sum(b[0] < 42 or b[1] < 81 or b[2] > 278.8 or b[3] > 199.78 for b in boxes),
                   **({"rectangles_um": boxes} if len(boxes) <= 20 else {})}
            for name, boxes in groups.items()}


def run_summary(tag, outer, run):
    status = outer / "status.json"
    result = {"status": json.loads(status.read_text()) if status.is_file() else None,
              "outer_exit_note": "recorded in status.json" if status.is_file() else
              "unavailable: shell timeout; do not infer outer success from completed stage",
              "corners": {}, "drc": {}}
    for stage in sorted(run.glob("*-openroad-stapostpnr")):
        metrics = json.loads((stage / "state_out.json").read_text())["metrics"]
        for corner in sorted(stage.glob("nom_*")):
            log = (corner / "sta.log").read_text()
            result["corners"][corner.name] = {
                "loaded_macro_liberties": re.findall(r"Reading cell library[^\n]+ at '([^']*/sg13cmos5l_sram/[^']+)'", log),
                "metrics": {k: v for k, v in metrics.items()
                            if k.endswith("__corner:" + corner.name) and
                            ("violation" in k or "_vio__" in k or "unannotated" in k or
                             any(f"__{s}__" in k for s in ("ws", "wns", "tns"))) and "r2r" not in k}}
    for report in sorted(run.glob("*-magic-drc/reports/drc.magic.rpt")):
        result["drc"] = drc_summary(report)
        runtime = report.parent.parent / "runtime.txt"
        result["magic_stage_runtime"] = runtime.read_text().strip()
    return result


def geometry(run):
    import gdstk
    path = run / "final/gds/tt_um_sram_probe.gds"
    lib = gdstk.read_gds(str(path))
    top = next(c for c in lib.cells if c.name == "tt_um_sram_probe")
    refs = [r for r in top.references if r.cell_name == MACRO]
    assert len(refs) == 1 and refs[0].origin == (42., 81.) and not refs[0].rotation and not refs[0].x_reflection
    polys = [p for p in top.polygons if (p.layer, p.datatype) == (50, 0)]
    polys += [p for q in top.paths for p in q.to_polygons() if (p.layer, p.datatype) == (50, 0)]
    boxes = [tuple(round(v, 6) for xy in p.bounding_box() for v in xy) for p in polys if len(p.points) == 4]
    bridges = [(113.7, 79.52, 115.65, 81.), (113.7, 197.66, 115.65, 201.31), (64.4, 79.52, 68.03, 81.)]
    ground = [(115.93, 3.56, 118.03, 80.52), (115.93, 200.26, 118.03, 707.08)]
    assert all(b in boxes for b in bridges + ground), "actual emitted GDS geometry differs"
    deftext = (run / "53-odb-cellfrequencytables/tt_um_sram_probe.def").read_text()
    assert len(re.findall(r"- memory\.sram " + MACRO + r" \+ FIXED \( 42000 81000 \) N", deftext)) == 1
    assert "( 113700 80260 ) ( 115650 80260 )" in deftext
    assert "Metal4 1950 + SHAPE STRIPE ( 114675 197660 ) ( 114675 201310 )" in deftext
    spice = re.sub(r"\n\+\s*", " ", (run / "64-magic-spiceextraction/tt_um_sram_probe.spice").read_text())
    ports = re.search(r"(?m)^\.subckt " + MACRO + r" (.+)$", spice)[1].split()
    instances = re.findall(r"(?m)^Xmemory\.sram (.+)$", spice)
    assert len(instances) == 1
    args = instances[0].split()
    supplies = {pin: args[i] for i, pin in enumerate(ports) if pin in ("VSS", "VDD", "VDDARRAY")}
    assert supplies == {"VSS": "VGND", "VDD": "VPWR", "VDDARRAY": "VPWR"}
    feedback = ET.parse(run / "64-magic-spiceextraction/feedback.xml")
    assert len(feedback.findall(".//items/item")) == 0
    lvs = (run / "66-netgen-lvs/reports/lvs.netgen.rpt").read_text()
    assert "Final result: Circuits match uniquely." in lvs
    return {"macro_count_gds_def_spice": [1, 1, 1], "placement_um": [42, 81],
            "orientation": "R0", "gds_unit_m": lib.unit, "gds_precision_m": lib.precision,
            "bridges_um": bridges, "adjacent_vgnd_stripes_um": ground,
            "vpwr_to_vgnd_clearance_um": 0.280, "positive_pin_contact_width_um": 1.950,
            "ground_pin_contact_width_um": 1.530, "extracted_supplies": supplies,
            "extraction_feedback_items": 0, "lvs": "unique match; abstract/black-box macro"}


def verify(archive):
    with tarfile.open(archive, "r:gz") as tar:
        inventory = json.load(tar.extractfile("inventory.json"))
        members = tar.getmembers()
        assert len({m.name for m in members}) == len(members), "duplicate members"
        assert {m.name for m in members} == set(inventory["files"]) | {"inventory.json"}
        for name, entry in inventory["files"].items():
            assert not Path(name).is_absolute() and ".." not in Path(name).parts
            member = tar.getmember(name)
            assert member.isfile(), "archive must contain regular files only"
            data = tar.extractfile(member).read()
            assert len(data) == entry["size"] and sha(data) == entry["sha256"], name
    print(f"verified {len(inventory['files'])} payloads; sha256={file_sha(archive)}")


def collect(output):
    assert output.parent.is_dir(), "output parent must already exist"
    assert not output.exists(), "refusing to replace existing evidence"
    payloads = {}
    def add(path):
        assert path.is_file(), f"missing selected evidence: {path}"
        payloads[path.relative_to(ROOT).as_posix()] = path.read_bytes()
    def add_tree(path, excluded=()):
        for p in sorted(path.rglob("*")):
            if p.is_file() and not any(part in excluded for part in p.relative_to(path).parts):
                add(p)
    summaries = {}
    dependencies = set()
    for tag in TAGS:
        outer = HERE / "runs" / ("pt0-" + tag)
        run = outer / "inputs/runs" / tag
        assert run.is_dir()
        for name in ("manifest.json", "status.json", "flow.log", "precheck.log"):
            if (outer / name).is_file():
                add(outer / name)
        for p in sorted((outer / "inputs").iterdir()):
            if p.is_file():
                add(p)
        for name in ("flow.log", "error.log", "warning.log", "resolved.json"):
            add(run / name)
        for stage in sorted(p for p in run.iterdir() if p.is_dir() and re.match(r"\d+-", p.name)):
            for name in ("COMMANDS", "config.json", "state_in.json", "state_out.json", "runtime.txt", "_env.tcl"):
                if (stage / name).is_file():
                    add(stage / name)
        for stage in sorted(run.glob("*-openroad-stapostpnr")):
            add_tree(stage)  # compact timing logs/reports/models, no databases
        for pattern in ("*-magic-drc", "*-magic-spiceextraction", "*-netgen-lvs", "*-misc-reportmanufacturability"):
            for stage in sorted(run.glob(pattern)):
                for p in sorted(stage.rglob("*")):
                    if p.is_file() and p.suffix in (".rpt", ".lyrdb", ".log", ".json", ".xml", ".txt", ".lvs", ".spice") and not any(part in ("extraction", "views") for part in p.relative_to(stage).parts):
                        add(p)
        if tag == "corrected-grid-02":
            add_tree(run / "final", excluded=("odb", "mag", "render"))
            for stage_name, extension in (("44-openroad-detailedrouting", ".def"),
                                          ("52-openroad-fillinsertion", ".nl.v"),
                                          ("52-openroad-fillinsertion", ".pnl.v"),
                                          ("53-odb-cellfrequencytables", ".def")):
                add(run / stage_name / ("tt_um_sram_probe" + extension))
            add_tree(run / "54-openroad-rcx", excluded=("nom",))
            # RCX may contain ODB: only explicit SPEF and small metadata are needed.
            for name in list(payloads):
                if "/54-openroad-rcx/" in name and Path(name).suffix in (".odb", ".def", ".v"):
                    del payloads[name]
            add_tree(run / "54-openroad-rcx/nom")
            add_tree(outer / "tt", excluded=("__pycache__",))
            add_tree(outer / "bin")
        elif tag in ("corners-01", "magic-01"):
            # Minimal retained replay views; do not collect historical databases.
            state = json.loads((outer / "inputs/state.json").read_text())
            needed = [state["nl"], *state["spef"].values()] if tag == "corners-01" else [state["gds"]]
            for value in needed:
                add(Path(value))
        summaries[tag] = run_summary(tag, outer, run)
        resolved = json.loads((run / "resolved.json").read_text())
        def external(value):
            if isinstance(value, dict):
                for v in value.values(): external(v)
            elif isinstance(value, list):
                for v in value: external(v)
            elif isinstance(value, str) and value.startswith(str(ROOT / ".toolchain")) and Path(value).is_file():
                dependencies.add(Path(value))
        external(resolved)
    corrected = HERE / "runs/pt0-corrected-grid-02/inputs/runs/corrected-grid-02"
    summaries["corrected-grid-02"]["geometry_and_supplies"] = geometry(corrected)
    reports = HERE / "runs/pt0-corrected-grid-02/tt/precheck/reports"
    summaries["corrected-grid-02"]["precheck_report_items"] = {
        p.name: len(ET.parse(p).findall(".//items/item")) for p in sorted(reports.glob("drc_*.xml"))}
    for path in (Path(__file__).resolve(), ROOT / "toolchain.lock", ROOT / "test/test_pt0_probe.py", ROOT / "test/test_pt0_runner.py"):
        add(path)
    payloads["review/summary.json"] = encoded(summaries)
    payloads["review/external-dependencies.json"] = encoded({
        str(p.relative_to(ROOT)): {"sha256": file_sha(p), "size": p.stat().st_size} for p in sorted(dependencies)})
    original = ROOT / "evidence/sram-flow-feasibility/attempt-005-artifacts.tar.gz"
    original_hash = file_sha(original)
    assert original_hash == "de16cf3d8a584e2bace6ec999651e4c73f2c2adfe28a0b042f531835e9843d43"
    payloads["review/original-archive.json"] = encoded({"path": str(original.relative_to(ROOT)), "sha256": original_hash})
    inventory = {"format": 1, "source_root": str(ROOT),
                 "files": {name: {"sha256": sha(data), "size": len(data)} for name, data in sorted(payloads.items())}}
    payloads["inventory.json"] = encoded(inventory)
    # Normalize ordering, tar metadata and gzip header; no wall-clock timestamps.
    output.mkdir()
    archive = output / "pt0-artifacts.tar.gz"
    with archive.open("xb") as raw, gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0, compresslevel=9) as zipped:
        with tarfile.open(fileobj=zipped, mode="w", format=tarfile.PAX_FORMAT) as tar:
            for name, data in sorted(payloads.items()):
                member = tarfile.TarInfo(name)
                member.size, member.mode, member.mtime = len(data), 0o644, 0
                tar.addfile(member, io.BytesIO(data))
    assert archive.stat().st_size < 20 * 1024 * 1024, "archive exceeds 20 MiB budget"
    (output / "inventory.json").write_bytes(payloads["inventory.json"])
    (output / "summary.json").write_bytes(payloads["review/summary.json"])
    (output / "external-dependencies.json").write_bytes(payloads["review/external-dependencies.json"])
    (output / "SHA256SUMS").write_text("".join(f"{file_sha(p)}  {p.name}\n" for p in sorted(output.iterdir()) if p.is_file()))
    verify(archive)
    print(f"archive_bytes={archive.stat().st_size}; original archive unchanged={original_hash}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "evidence/sram-pt0")
    parser.add_argument("--verify", type=Path)
    args = parser.parse_args()
    if args.verify:
        verify(args.verify)
    else:
        collect(args.output.resolve())


if __name__ == "__main__":
    main()
