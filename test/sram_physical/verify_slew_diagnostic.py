"""Verify all-corner bounded electrical evidence and buffer-only netlist change."""
import hashlib
import json
from pathlib import Path
import re
import sys
from slew_evidence import verify_buffer_only, path_values

baseline, repair = map(lambda p: Path(p).resolve(), sys.argv[1:3])
corners = ["nom_fast_1p32V_m40C", "nom_slow_1p08V_125C", "nom_typ_1p20V_25C"]
results = {}
for corner in corners:
    row = {}
    for root, phase in [(baseline, "extracted"), (repair, "before"), (repair, "after")]:
        directory = root / phase
        checks = (directory / (corner + "-checks.rpt")).read_text()
        if phase == "after":
            assert "VIOLATED" not in checks, corner + " electrical violation"
        measurements = {}
        for pin in ["hc_resource_7_program/A_DIN[9]", "_150_/Y"]:
            label = pin.translate(str.maketrans({"/": "_", "[": "_", "]": "_"}))
            measurements[pin] = {}
            for edge in ["rise", "fall"]:
                for delay in ["min", "max"]:
                    text = (directory / f"{corner}-{label}-{edge}-{delay}.rpt").read_text()
                    measurements[pin][edge + "_" + delay] = path_values(text, pin)
        row[phase] = {"electrical_violation_rows": checks.count("VIOLATED"), "pins": measurements}
    for delay in ["min", "max"]:
        text = (repair / "after" / f"{corner}-global-{delay}.rpt").read_text()
        slacks = [float(x) for x in re.findall(r"([-+\d.]+)\s+slack \(", text)]
        assert slacks and min(slacks) >= 0, (corner, delay, slacks)
        row["estimated_" + ("hold" if delay == "min" else "setup") + "_worst_ns"] = min(slacks)
    results[corner] = row

annotation = (repair / "after/annotation.rpt").read_text()
assert "Found 0 partially unannotated drivers." in annotation
assert "Found 5 unannotated drivers." in annotation
assert {line.strip() for line in annotation.splitlines() if line.startswith(" ")} == {f"ui_in[{i}]" for i in range(3, 8)}
commands = json.loads((repair / "commands.json").read_text())
for path, digest in commands["inputs_sha256"].items():
    assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest
source_odb = next(Path(p) for p in commands["inputs_sha256"] if p.endswith(".odb"))
state = json.loads((source_odb.parent / "state_out.json").read_text())
original = Path(state["nl"])
added = verify_buffer_only(original.read_text(), (repair / "candidate.nl.v").read_text())
assert added == 99
hashes = {str(p.relative_to(repair)): hashlib.sha256(p.read_bytes()).hexdigest()
          for p in sorted(repair.rglob("*")) if p.is_file() and p.name != "verification.json"}
record = {"all_corners": results, "added_noninverting_buffers": added,
          "original_cells_and_connectivity_preserved_after_buffer_contraction": True,
          "new_unannotated_or_partial_drivers": 0, "original_netlist_sha256": hashlib.sha256(original.read_bytes()).hexdigest(),
          "annotation_scope": "global_route_estimates_after_repair_not_final_extracted_signoff",
          "artifacts_sha256": hashes}
with (repair / "verification.json").open("x") as channel:
    json.dump(record, channel, indent=2)
    channel.write("\n")
print(json.dumps({"added_buffers": added, "corners": {k: {x: y for x, y in v.items() if x.startswith("estimated_")} for k, v in results.items()},
                  "new_unannotated_or_partial_drivers": 0}, indent=2))
