"""Public emission + actual emitted Tcl geometry, without PDK or EDA tools."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from mock_odb import fixture
from slew_evidence import verify_buffer_only, path_values


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs)


exe = str(Path(sys.argv[1]).resolve())
geometry_tests = Path(sys.argv[2]).read_text()
original_logic = """
  sg13cmos5l_dfrbp_1 reg0 (.D(d), .Q(q), .CLK(clk));
  RM_IHPSG13_1P_256x16_c2_bm_bist ram (.A_DIN(q), .A_DOUT(r));
  sg13cmos5l_nor3_1 gate0 (.A(r), .B(en), .C(z), .Y(out));
"""
buffered_logic = original_logic.replace(".A_DIN(q)", ".A_DIN(buffered)").replace(".Y(out)", ".Y(local)") + """
  sg13cmos5l_buf_2 split0 (.A(q), .X(buffered));
  sg13cmos5l_buf_1 split1 (.A(local), .X(out));
"""
assert verify_buffer_only(original_logic, buffered_logic) == 2
for bad in [buffered_logic.replace(".A_DIN(buffered)", ".A_DIN(wrong)"),
            buffered_logic.replace("sg13cmos5l_buf_2 split0", "sg13cmos5l_inv_2 split0"),
            buffered_logic + "sg13cmos5l_dfrbp_1 extra (.D(q), .Q(extra_q), .CLK(clk));",
            buffered_logic.replace(".A(q), .X(buffered)", ".A(buffered), .X(buffered)")]:
    try:
        verify_buffer_only(original_logic, bad)
    except ValueError:
        pass
    else:
        raise AssertionError("non-equivalent/architectural change accepted")
sample = "3 0.125086 0.796462 1.248723 3.674181 ^ hold128/X (sg13cmos5l_dlygate4sd3_1)\n1.064665 0.034803 3.708985 ^ hc_resource_7_program/A_DIN[9] (macro)"
assert path_values(sample, "hold128/X")[0]["load_pf"] == 0.125086
assert path_values(sample, "hc_resource_7_program/A_DIN[9]")[0]["slew_ns"] == 1.064665
try:
    path_values("No paths found.", "hc_resource_7_program/A_DIN[9]")
except ValueError:
    pass
else:
    raise AssertionError("missing timing evidence accepted")
print("electrical regression: buffer contraction preserves logic; changed pins/registers/inverters/loops and missing timing evidence reject")
with tempfile.TemporaryDirectory(prefix="asic-sram-physical-") as tmp:
    root = Path(run("git", "rev-parse", "--show-toplevel").stdout.strip())
    physical, synthesis = Path(tmp) / "physical", Path(tmp) / "synthesis"
    run(exe, str(root), str(physical), "physical")
    run(exe, str(root), str(synthesis), "synthesis")
    manifest = json.loads((physical / "manifest.json").read_text())
    config = json.loads((physical / "src/config.json").read_text())
    contract = manifest["macro_contract"]
    plan = json.loads((physical / "physical/macro-plan.json").read_text())
    assert contract["schema_version"] == 2 and contract["execution"] == "fresh_full"
    assert contract["physical_plan"] == plan
    assert plan["strategy"] == "cmos5l_m4_edge_access_v1"
    assert plan["checking_profile"] == "cmos5l_real_gds_v1"
    assert plan["lvs_scope"] == "abstract_macro_boundary_with_schematic_cdl"
    assert [m["resource"] for m in plan["macros"]] == ["left", "right"]
    for m in plan["macros"]:
        assert m["instance"] == f'hc_resource_{len(m["resource"])}_{m["resource"]}'
        assert m["orientation"] == "R0" and m["halo_um"] == 2.0
        assert m["supplies"] == {"VDD!": "VPWR", "VDDARRAY!": "VPWR", "VSS!": "VGND"}
        assert config["MACROS"][m["module"]]["instances"][m["instance"]]["location"] == m["location_um"]
    assert config["PDN_CFG"] == "dir::../physical/pdn.tcl"
    assert len(config["PDN_MACRO_CONNECTIONS"]) == 4
    assert config["PDN_CONNECT_MACROS_TO_GRID"] is True, "global macro supply binding must remain enabled"
    assert config["RUN_POST_GRT_DESIGN_REPAIR"] is True
    assert config["GRT_DESIGN_REPAIR_RUN_GRT"] is True
    assert config["GRT_DESIGN_REPAIR_MAX_WIRE_LENGTH"] == 200.0
    assert config["GRT_DESIGN_REPAIR_MAX_SLEW_PCT"] == 20
    assert config["GRT_DESIGN_REPAIR_MAX_CAP_PCT"] == 20
    assert config["RSZ_CORNERS"] == config["STA_CORNERS"]
    assert config["RUN_KLAYOUT_STREAMOUT"] is True
    assert config["PRIMARY_GDSII_STREAMOUT_TOOL"] == "klayout"
    assert config["RUN_KLAYOUT_DRC"] is True
    assert config["RUN_MAGIC_DRC"] is True and config["ERROR_ON_ILLEGAL_OVERLAPS"] is True
    assert config["KLAYOUT_DRC_OPTIONS"]["log"] == "drc-klayout.log"
    assert config["KLAYOUT_DRC_OPTIONS"]["threads"] == 6
    assert all(v == "false" for k, v in config["KLAYOUT_DRC_OPTIONS"].items() if k not in {"log", "threads"})
    assert config["EXTRA_SPICE_MODELS"] == config["MACROS"][plan["macros"][0]["module"]]["spice"]
    assert len(config["ROUTING_OBSTRUCTIONS"]) == 2
    assert all(x.startswith("Metal4 ") for x in config["ROUTING_OBSTRUCTIONS"])
    for entry in manifest["files"]:
        assert hashlib.sha256((physical / entry["path"]).read_bytes()).hexdigest() == entry["sha256"]
    keys = [x["key"] for x in manifest["resolved_settings"]]
    assert not set(keys) & set(manifest["generated_settings"]), "duplicate configuration ownership"
    old = json.loads((synthesis / "manifest.json").read_text())
    assert old["macro_contract"]["schema_version"] == 1
    assert old["macro_contract"]["execution"] == "synthesis_only"
    assert "physical_plan" not in old["macro_contract"]
    assert not (synthesis / "physical").exists()
    assert (physical / "src/tt_um_physical_sram.v").read_bytes() == (synthesis / "src/tt_um_physical_sram.v").read_bytes(), "physical policy changed architectural RTL"
    tcl = (physical / "physical/pdn.tcl").read_text()
    regenerated = Path(tmp) / "regenerated-pdn.tcl"
    run(exe, "generate-pdn", str(physical / "physical/macro-plan.json"), str(regenerated))
    assert regenerated.read_text() == tcl, "diagnostic did not use the actual library generator"
    generated_settings = Path(tmp) / "regenerated-settings.json"
    run(exe, "generate-settings", str(physical / "physical/macro-plan.json"), str(generated_settings))
    assert all(config[k] == v for k, v in json.loads(generated_settings.read_text()).items())
    library = tcl.split("# Begin runtime: OpenDB adapter", 1)[0]
    # tclsh stdin mode may return zero on a top-level error; use a real script
    # with explicit exception handling so every geometry failure is fatal.
    checked = "if {[catch {\n" + library + "\n" + geometry_tests + "\n} message options]} {puts stderr $message; exit 1}\n"
    result = run("tclsh", input=checked)
    print(result.stdout.strip())
    for variant in ["ok", "wrong_net", "orientation", "size", "no_grid", "native_error", "via_collision", "empty_macro_grid"]:
        output = Path(tmp) / ("runtime-" + variant)
        output.mkdir()
        invoke = r'''
set code [catch {pdngen -skip_trim} message options]
if {[llength [info commands ::hc_pdn::native_pdngen]] != 0} { error "native wrapper was not restored" }
if {[llength [info commands ::pdngen]] != 1} { error "original pdngen lost" }
if {$code} { puts stderr $message; exit 1 }
if {[llength $::fixture::additions] != 12} { error "missing supply bridges" }
'''
        regression = "\ndefine_pdn_grid -macro -default -name macro -halo {0 0}\n" if variant == "empty_macro_grid" else ""
        program = fixture(str(output), variant) + tcl + regression + invoke
        # Full Tcl source is evaluated under catch so adapter errors cannot be
        # swallowed by tclsh's interactive-stdin semantics.
        program = "if {[catch {\n" + program + "\n} message options]} {puts stderr $message; exit 1}\n"
        outcome = subprocess.run(["tclsh"], input=program, text=True, capture_output=True)
        if variant == "ok":
            assert outcome.returncode == 0, outcome.stderr
            report = json.loads((output / "macro-power-geometry.json").read_text())
            assert report["dbu_per_um"] == 1000 and report["manufacturing_grid_dbu"] == 5
            assert [m["resource"] for m in report["macros"]] == ["left", "right"]
            for m in report["macros"]:
                assert {c["pin"] for c in m["contacts"]} == {"VDD!", "VDDARRAY!", "VSS!"}
                assert all(c["minimum_clearance_dbu"] == 600 for c in m["contacts"])
                assert all(c["measured_minimum_clearance_dbu"] >= 600 for c in m["contacts"])
            assert {p["net"] for p in report["public_pins"]} == {"VPWR", "VGND"}
        else:
            assert outcome.returncode != 0, f"{variant} was accepted"
            assert not (output / "macro-power-geometry.json").exists()
            expected = {"wrong_net": "incorrect net", "orientation": "fixed R0", "size": "placement/size",
                        "no_grid": "no legal edge contact", "native_error": "synthetic native failure",
                        "via_collision": "no legal edge contact", "empty_macro_grid": "PDN-0233"}[variant]
            assert expected in outcome.stderr, outcome.stderr
    print("strict OpenDB adapter: two-resource construction/report + seven failures, empty macro-grid regression, via enclosures and hook restoration passed")
    print("physical declaration/emission: schema1 compatibility, schema2 identity, settings and two-resource inventory passed")
