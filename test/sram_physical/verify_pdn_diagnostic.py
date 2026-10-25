"""Independently compare a real PDN diagnostic's saved DEF/netlist with its JSON.

No EDA tool is invoked. Writes one fresh verification.json in the diagnostic dir.
"""
import hashlib
import json
from pathlib import Path
import re
import sys


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def intersection(a, b):
    return (min(a[2], b[2]) - max(a[0], b[0]), min(a[3], b[3]) - max(a[1], b[1]))


root = Path(sys.argv[1]).resolve()
commands = json.loads((root / "commands.json").read_text())
for path, expected in commands["input_sha256"].items():
    assert sha(Path(path)) == expected, f"changed diagnostic input: {path}"
input_odb = next(Path(p) for p in commands["input_sha256"] if p.endswith(".odb"))
state_path = input_odb.parent / "state_out.json"
assert Path(json.loads(state_path.read_text())["odb"]) == input_odb
report = json.loads((root / "macro-power-geometry.json").read_text())
inspection = json.loads((root / "inspection.json").read_text())
assert inspection["power_grid_checks"] == "passed_both_nets"
assert inspection["global_supplies"] == {"VDD!": "VPWR", "VDDARRAY!": "VPWR", "VSS!": "VGND"}
for net in ["VPWR", "VGND"]:
    assert not (root / f"{net}-grid-errors.rpt").read_text().strip()
log = (root / "openroad.log").read_text()
assert "Inserting grid: stdcell_grid" in log and "PDN-0233" not in log
assert all(f"All shapes on net {net} are connected." in log for net in ["VPWR", "VGND"])
assert "[ERROR" not in log
def_text = (root / "pdn.def").read_text()
assert re.search(r"UNITS DISTANCE MICRONS " + str(report["dbu_per_um"]) + r"\s*;", def_text)
special = def_text.split("SPECIALNETS 2 ;", 1)[1].split("END SPECIALNETS", 1)[0]
entries = list(re.finditer(r"^\s+- (\S+) ", special, re.M))
rects = {}
route = re.compile(r"(?:ROUTED|NEW) Metal4 (\d+) \+ SHAPE STRIPE\s+"
                   r"\( (-?\d+) (-?\d+) \) \( (-?\d+) (-?\d+) \)")
for index, entry in enumerate(entries):
    body = special[entry.end():entries[index + 1].start() if index + 1 < len(entries) else len(special)]
    found = set()
    for match in route.finditer(body):
        width, x0, y0, x1, y1 = map(int, match.groups())
        assert width % 2 == 0
        if x0 == x1:
            found.add((x0 - width // 2, min(y0, y1), x1 + width // 2, max(y0, y1)))
        elif y0 == y1:
            found.add((min(x0, x1), y0 - width // 2, max(x0, x1), y1 + width // 2))
    rects[entry.group(1)] = found
bridge_count = 0
netlist = (root / "pdn.pnl.v").read_text()
for macro in report["macros"]:
    assert macro["instance"] in netlist and macro["module"] in netlist
    assert {c["pin"] for c in macro["contacts"]} == {"VDD!", "VDDARRAY!", "VSS!"}
    for contact in macro["contacts"]:
        net = contact["net"]
        for key in ["neck_rect_dbu", "landing_rect_dbu", "grid_rect_dbu"]:
            assert tuple(contact[key]) in rects[net], f"missing saved DEF geometry: {key} {contact}"
        neck, landing = contact["neck_rect_dbu"], contact["landing_rect_dbu"]
        w, h = intersection(neck, contact["pin_rect_dbu"])
        assert w >= contact["minimum_contact_width_dbu"] and h >= contact["minimum_overlap_dbu"]
        assert min(intersection(landing, contact["grid_rect_dbu"])) >= contact["minimum_overlap_dbu"]
        assert min(intersection(neck, landing)) >= contact["minimum_overlap_dbu"]
        assert contact["measured_minimum_clearance_dbu"] >= contact["minimum_clearance_dbu"]
        assert f".\\{contact['pin']} ({net})" in netlist
        bridge_count += 2
pin_section = def_text.split("PINS 45 ;", 1)[1].split("END PINS", 1)[0]
for pin in report["public_pins"]:
    assert tuple(pin["rect_dbu"]) in rects[pin["net"]]
    entry = re.search(r"- " + re.escape(pin["net"]) + r" \+ NET.*?;", pin_section, re.S).group()
    match = re.search(r"LAYER Metal4 \( (-?\d+) (-?\d+) \) \( (-?\d+) (-?\d+) \).*?"
                      r"FIXED \( (-?\d+) (-?\d+) \) N", entry, re.S)
    x0, y0, x1, y1, dx, dy = map(int, match.groups())
    assert [x0 + dx, y0 + dy, x1 + dx, y1 + dy] == pin["rect_dbu"]
assert inspection["actual_public_pins"] == [{"net": p["net"], "rect_dbu": p["rect_dbu"]} for p in report["public_pins"]]
outputs = ["commands.json", "pdn.tcl", "env.tcl", "driver.tcl", "openroad.log", "metrics.json",
           "macro-power-geometry.json", "inspection.json", "pdn.odb", "pdn.def", "pdn.pnl.v",
           "pdn.nl.v", "pdn.sdc", "VPWR-grid-errors.rpt", "VGND-grid-errors.rpt"]
verification = {"macro_count": len(report["macros"]), "saved_bridge_rectangles": bridge_count,
                "saved_public_pins": len(report["public_pins"]), "all_supplies_bound": True,
                "both_power_grids_connected": True, "stage19_state_sha256": sha(state_path),
                "artifacts_sha256": {p: sha(root / p) for p in outputs}}
with (root / "verification.json").open("x") as channel:
    json.dump(verification, channel, indent=2)
    channel.write("\n")
print(json.dumps(verification, indent=2))
