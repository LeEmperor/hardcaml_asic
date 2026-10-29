"""Read-only qualification table inspection, explicitly invoked with a PDK root.

Not in runtest: ordinary library tests must not discover or require a PDK.
This small balanced-group reader inspects real Liberty, never infers a cell's
function from its prefix. It is not a replacement timing/Liberty parser.
"""
import hashlib
import json
from pathlib import Path
import re
import sys

def group(text, kind, name):
    matches = list(re.finditer(r"\b" + kind + r"\s*\(\s*\"?" + re.escape(name) + r"\"?\s*\)\s*\{", text))
    assert len(matches) == 1, (kind, name, len(matches))
    start = matches[0].end()
    depth, pos, quoted, escaped = 1, start, False, False
    while depth:
        c = text[pos]
        if quoted:
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"':
                quoted = False
        elif c == '"':
            quoted = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        pos += 1
    return text[start:pos-1]

def attribute(body, key):
    values = re.findall(r"\b" + key + r'\s*:\s*(?:"([^"]*)"|([^;\s]+))\s*;', body)
    assert len(values) == 1, (key, values)
    return values[0][0] or values[0][1]

root = Path(sys.argv[1]) / "libs.ref/sg13cmos5l_stdcell/lib"
corners = ["fast_1p32V_m40C", "typ_1p20V_25C", "slow_1p08V_125C"]
cells = [f"sg13cmos5l_buf_{n}" for n in (1, 2, 4, 8, 16)]
cells += [f"sg13cmos5l_dlygate4sd{n}_1" for n in (1, 2, 3)]
rows = []
for corner in corners:
    path = root / f"sg13cmos5l_stdcell_{corner}.lib"
    raw = path.read_bytes()
    # PDK comments include non-UTF8 characters; syntax/identifiers are ASCII.
    text = raw.decode("latin1")
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    for name in cells:
        cell = group(text, "cell", name)
        a, x = group(cell, "pin", "A"), group(cell, "pin", "X")
        assert attribute(a, "direction") == "input", (corner, name, "A")
        assert attribute(x, "direction") == "output", (corner, name, "X")
        assert attribute(x, "function") == "A", (corner, name, "function")
        assert not re.search(r"\b(?:ff|latch|statetable)\s*\(", cell), (corner, name, "sequential")
        assert re.search(r'\brelated_pin\s*:\s*"A"\s*;', x), (corner, name, "A timing arc")
    rows.append(dict(corner=corner, path=str(path.resolve()), sha256=hashlib.sha256(raw).hexdigest(),
                     cells=cells, input="A", output="X", function="A"))
print(json.dumps(dict(contract="physical-v2-qualified-combinational-table", libraries=rows), indent=2))
