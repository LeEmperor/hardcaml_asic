"""Tiny SYNTHETIC config scaffold; none of these files is physical technology."""

import json


def build(root):
    pdk_root = root / "synthetic-pdks"
    tech = pdk_root / "observation_dummy" / "libs.tech" / "librelane"
    scl = tech / "dummy_cells"
    scl.mkdir(parents=True)
    placeholder = root / "SYNTHETIC-NOT-TECHNOLOGY.txt"
    placeholder.write_text("SYNTHETIC placeholder, not LEF/GDS/liberty/SDC.\n")
    pdk_values = {
        "STD_CELL_LIBRARY": "dummy_cells", "VDD_PIN": "VDD", "GND_PIN": "VSS",
        "TECH_LEFS": f"dummy {placeholder}",
        "PRIMARY_GDSII_STREAMOUT_TOOL": "none", "DEFAULT_CORNER": "dummy",
        "STA_CORNERS": "dummy", "RT_MIN_LAYER": "m1", "RT_MAX_LAYER": "m1",
    }
    scl_values = {
        "SCL_GROUND_PINS": "VSS", "SCL_POWER_PINS": "VDD",
        "FILL_CELLS": "dummy", "DECAP_CELLS": "dummy",
        "CELL_LIBS": f"dummy {placeholder}", "CELL_LEFS": str(placeholder),
        "CELL_GDS": str(placeholder), "SYNTH_EXCLUDED_CELL_FILE": str(placeholder),
        "PNR_EXCLUDED_CELL_FILE": str(placeholder), "OUTPUT_CAP_LOAD": "1",
        "MAX_FANOUT_CONSTRAINT": "1", "CLOCK_UNCERTAINTY_CONSTRAINT": "0",
        "CLOCK_TRANSITION_CONSTRAINT": "0", "TIME_DERATING_CONSTRAINT": "0",
        "IO_DELAY_CONSTRAINT": "0", "SYNTH_DRIVING_CELL": "dummy/Y",
        "SYNTH_TIEHI_CELL": "dummy/Y", "SYNTH_TIELO_CELL": "dummy/Y",
        "SYNTH_BUFFER_CELL": "dummy/A/Y", "PLACE_SITE": "dummy",
        "CELL_PAD_EXCLUDE": "dummy",
    }
    for path, values in ((tech / "config.tcl", pdk_values), (scl / "config.tcl", scl_values)):
        path.write_text("# SYNTHETIC; NOT USABLE PHYSICAL TECHNOLOGY\n" + "".join(
            f"set ::env({key}) {{{value}}}\n" for key, value in values.items()
        ))
    config = root / "config.json"
    config.write_text(json.dumps({
        "meta": {"version": 2}, "DESIGN_NAME": "observation_dummy",
        "PDK": "observation_dummy", "STD_CELL_LIBRARY": "dummy_cells",
        "FALLBACK_SDC": str(placeholder), "OBS_ENABLE": False,
    }, indent=2) + "\n")
    return config, pdk_root
