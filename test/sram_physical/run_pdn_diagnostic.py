"""Opt-in, bounded real PDN replay. Never part of the ordinary runtest alias.

Regenerates Tcl through the rebuilt library, reads preserved stage-19 inputs,
and writes every output to a new directory. Historical paths are read-only mounts.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import uuid


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def quote(path):
    text = str(path)
    if any(c in text for c in "{}\n\r"):
        raise ValueError("unsupported Tcl path")
    return "{" + text + "}"


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--project", type=Path, required=True)
parser.add_argument("--generator", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
project, output = args.project.resolve(), args.output.absolute()
stage = project / "runs/asic/21-openroad-generatepdn"
plan = project / "physical/macro-plan.json"
odb = project / "runs/asic/19-openroad-tapendcapinsertion/tt_um_program_memory.odb"
assert stage.joinpath("_env.tcl").is_file() and plan.is_file() and odb.is_file()
assert not output.exists(), "diagnostic requires a new output directory"
assert not subprocess.check_output(["docker", "ps", "-q"], text=True).strip(), "another container is running; coordinate EDA first"
output.mkdir()
generated = output / "pdn.tcl"
generation = [str(args.generator.resolve()), "generate-pdn", str(plan), str(generated)]
subprocess.run(generation, check=True)
scripts = "/nix/store/6a08ghhhzl5a07nr0ly762yh1ah6m5bj-python3-3.13.13-env/lib/python3.13/site-packages/librelane/scripts"
env = "source " + quote(stage / "_env.tcl") + "\n"
env += "set ::env(STEP_DIR) " + quote(output) + "\n"
env += "set ::env(PDN_CFG) " + quote(generated) + "\n"
env += "set ::env(OPENROAD_THREADS) 6\n"
env += r'''
# LibreLane's per-process private variables are not included in _env.tcl.
# Reconstruct the nominal PDN timing inputs from the retained public config.
set corner $::env(DEFAULT_CORNER)
set libs [dict get $::env(CELL_LIBS) $corner]
set macro_libs {}
dict for {name macro} $::env(MACROS) {
    lappend macro_libs {*}[dict get $macro lib $corner]
}
set ::env(_LIB_CORNER_0) [concat [list $corner] $libs $macro_libs]
set ::env(_PNR_LIBS) [concat $libs $macro_libs]
set ::env(_MACRO_LIBS) $macro_libs
set ::env(_SDC_IN) $::env(PNR_SDC_FILE)
set ch [open $::env(PNR_EXCLUDED_CELL_FILE) r]
set excluded {}
foreach line [split [read $ch] \n] {
    set line [string trim [lindex [split $line #] 0]]
    if {$line ne {}} { lappend excluded {*}$line }
}
close $ch
set ::env(_PNR_EXCLUDED_CELLS) $excluded
'''
for key, suffix in [("SAVE_ODB", "odb"), ("SAVE_DEF", "def"), ("SAVE_SDC", "sdc"),
                    ("SAVE_NL", "nl.v"), ("SAVE_PNL", "pnl.v")]:
    env += f"set ::env({key}) " + quote(output / ("pdn." + suffix)) + "\n"
(output / "env.tcl").write_text(env)
driver = r'''
if {[catch {
    source $::env(_TCL_ENV_IN)
    source $::env(SCRIPTS_DIR)/openroad/pdn.tcl
    set block [ord::get_db_block]
    set inst [$block findInst hc_resource_7_program]
    set powers {}
    foreach pin {VDD! VDDARRAY! VSS!} {
        set actual [[[$inst findITerm $pin] getNet] getName]
        set expected [expr {$pin eq "VSS!" ? "VGND" : "VPWR"}]
        if {$actual ne $expected} { error "supply identity mismatch $pin $actual" }
        lappend powers "[::hc_pdn::json_string $pin]:[::hc_pdn::json_string $actual]"
    }
    set pins {}
    foreach net {VPWR VGND} {
        check_power_grid -net $net -error_file [file join $::env(STEP_DIR) $net-verified-grid.rpt]
        set term [$block findBTerm $net]
        foreach pin [$term getBPins] {
            foreach box [$pin getBoxes] {
                lappend pins "{\"net\":[::hc_pdn::json_string $net],\"rect_dbu\":[::hc_pdn::json_rect [::hc_pdn::rect $box]]}"
            }
        }
    }
    set ch [open [file join $::env(STEP_DIR) inspection.json] {WRONLY CREAT EXCL}]
    puts $ch "{\"global_supplies\":{[join $powers ,]},\"actual_public_pins\":\[[join $pins ,]\],\"power_grid_checks\":\"passed_both_nets\"}"
    close $ch
} message options]} {
    puts stderr $message
    puts stderr [dict get $options -errorinfo]
    exit 1
}
'''
(output / "driver.tcl").write_text(driver)
image = "sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a"
name = "asic-pdn-diagnostic-" + uuid.uuid4().hex[:12]
command = ["docker", "run", "--rm", "--name", name, "--network", "none", "--cpus", "6",
           "--user", f"{os.getuid()}:{os.getgid()}",
           "-v", "/home/wayne/devel/jane:/home/wayne/devel/jane:ro",
           "-v", f"{output}:{output}:rw", "-w", str(output),
           "-e", "OMP_NUM_THREADS=6", "-e", "OPENROAD_THREADS=6",
           "-e", f"_TCL_ENV_IN={output / 'env.tcl'}", "-e", f"SCRIPTS_DIR={scripts}",
           image, "openroad", "-exit", "-threads", "6", "-no_splash",
           "-metrics", str(output / "metrics.json"), str(output / "driver.tcl")]
inputs = {str(p): digest(p) for p in [plan, odb, stage / "_env.tcl", generated]}
(output / "commands.json").write_text(json.dumps({"generation": generation, "openroad": command,
    "input_sha256": inputs, "timeout_seconds": 300}, indent=2) + "\n")
try:
    with (output / "openroad.log").open("w") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=300)
except subprocess.TimeoutExpired:
    subprocess.run(["docker", "stop", "--time", "5", name], check=False)
    raise
assert all(digest(Path(p)) == sha for p, sha in inputs.items()), "input changed during diagnostic"
print(f"exit={result.returncode} artifacts={output}")
raise SystemExit(result.returncode)
