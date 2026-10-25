"""Opt-in six-worker OpenROAD electrical diagnosis/repair, never full P&R.

final: preserved final ODB + actual extracted SPEF, all three timing corners.
repair: preserved post-GRT ODB, native global-route parasitics before/after native
repair_design and legalization/re-GRT. The candidate is not routed signoff proof.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import uuid


def word(value):
    text = str(value)
    for a, b in [("\\", "\\\\"), ('"', '\\"'), ("$", "\\$"), ("[", "\\["), ("]", "\\]"), ("\n", "\\n"), ("\r", "\\r")]:
        text = text.replace(a, b)
    return '"' + text + '"'


def scalar(value):
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, dict):
        return " ".join(atom(x) for pair in value.items() if pair[1] is not None for x in (pair[0], scalar(pair[1])))
    if isinstance(value, list):
        return " ".join(atom(scalar(v)) for v in value)
    return str(value)


def atom(value):
    text = str(value)
    return text if re.fullmatch(r'[^\s{}\[\]$"\\;]+', text) else word(text)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--run", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--mode", choices=["final", "repair"], required=True)
parser.add_argument("--slew-margin", type=int, default=20)
parser.add_argument("--max-wire-length", type=int, default=0)
parser.add_argument("--generated-settings", type=Path)
args = parser.parse_args()
run = args.run.resolve()
out = args.output.absolute()
config_path = run / "resolved.json"
config = json.loads(config_path.read_text())
config.pop("meta", None)
if args.generated_settings:
    config.update(json.loads(args.generated_settings.read_text()))
    args.slew_margin = config["GRT_DESIGN_REPAIR_MAX_SLEW_PCT"]
    args.max_wire_length = config["GRT_DESIGN_REPAIR_MAX_WIRE_LENGTH"]
stage = run / ("53-odb-cellfrequencytables" if args.mode == "final" else "39-openroad-globalrouting")
state_path = stage / "state_out.json"
state = json.loads(state_path.read_text())
odb = Path(state["odb"])
assert not out.exists(), "use a fresh diagnostic directory"
out.mkdir()
env = "".join(f"set ::env({k}) {word(scalar(v))}\n" for k, v in config.items() if v is not None)
env += f"set ::env(CURRENT_ODB) {word(odb)}\nset ::env(STEP_DIR) {word(out)}\n"
for key, suffix in [("SAVE_ODB", "odb"), ("SAVE_DEF", "def"), ("SAVE_NL", "nl.v"), ("SAVE_PNL", "pnl.v"), ("SAVE_SDC", "sdc")]:
    env += f"set ::env({key}) {word(out / ('candidate.' + suffix))}\n"
env += r'''
set i 0
foreach corner $::env(STA_CORNERS) {
    set libs [dict get $::env(CELL_LIBS) $corner]
    dict for {name macro} $::env(MACROS) { lappend libs {*}[dict get $macro lib $corner] }
    set ::env(_LIB_CORNER_$i) [concat [list $corner] $libs]
    incr i
}
set ::env(_SDC_IN) $::env(PNR_SDC_FILE)
set file [open $::env(PNR_EXCLUDED_CELL_FILE) r]
set excluded {}
foreach line [split [read $file] \n] {
    set line [string trim [lindex [split $line #] 0]]
    if {$line ne {}} { lappend excluded {*}$line }
}
close $file
set ::env(_PNR_EXCLUDED_CELLS) $excluded
set ::env(OPENROAD_THREADS) 6
'''
(out / "env.tcl").write_text(env)
reports = r'''
proc diagnostic_reports {phase} {
    set directory [file join $::env(STEP_DIR) $phase]
    file mkdir $directory
    foreach corner $::env(STA_CORNERS) {
        report_check_types -corner $corner -max_slew -max_capacitance -max_fanout -violators -digits 6 > [file join $directory $corner-checks.rpt]
        foreach delay {min max} {
            report_checks -corner $corner -path_delay $delay -format full_clock_expanded \
                -fields {slew cap fanout input_pin net} -digits 6 -group_path_count 5 -endpoint_path_count 5 \
                > [file join $directory $corner-global-$delay.rpt]
        }
        foreach endpoint {{hc_resource_7_program/A_DIN[9]} {_150_/Y}} {
            set label [string map {/ _ [ _ ] _} $endpoint]
            set pin [get_pins [list $endpoint]]
            foreach edge {rise fall} {
                foreach delay {min max} {
                    report_checks -corner $corner -${edge}_through $pin -path_delay $delay -format full_clock_expanded \
                        -fields {slew cap fanout input_pin net} -digits 6 -group_path_count 8 -endpoint_path_count 8 \
                        > [file join $directory $corner-$label-$edge-$delay.rpt]
                }
            }
        }
    }
    report_parasitic_annotation -report_unannotated > [file join $directory annotation.rpt]
    set trace [open [file join $directory macro-nets.tsv] w]
    set inst [[ord::get_db_block] findInst hc_resource_7_program]
    set number 0
    foreach pin [$inst getITerms] {
        set net [$pin getNet]
        if {$net eq "NULL" || [$net getSigType] in {POWER GROUND}} { continue }
        set drivers {}
        foreach other [$net getITerms] {
            if {[$other getIoType] eq "OUTPUT"} {
                set driver [$other getInst]
                lappend drivers [list [$driver getName] [[$driver getMaster] getName] [[$other getMTerm] getName]]
            }
        }
        puts $trace "hc_resource_7_program/[[$pin getMTerm] getName]\t[$net getName]\t$drivers"
        report_net -connections -verbose -digits 6 [$net getName] > [file join $directory net-[incr number].rpt]
    }
    close $trace
    foreach name {net128 {uo_out[2]}} {
        report_net -connections -verbose -digits 6 $name > [file join $directory [string map {[ _ ] _} $name]-net.rpt]
    }
}
'''
driver = "source $::env(_TCL_ENV_IN)\nsource $::env(SCRIPTS_DIR)/openroad/common/io.tcl\nread_current_odb\nset_propagated_clock [all_clocks]\n" + reports
inputs = [config_path, state_path, odb, Path(config["PNR_SDC_FILE"])]
if args.generated_settings:
    inputs.append(args.generated_settings.resolve())
if args.mode == "final":
    spef = run / "54-openroad-rcx/nom/tt_um_program_memory.nom.spef"
    inputs.append(spef)
    driver += "foreach corner $::env(STA_CORNERS) { read_spef -corner $corner " + word(spef) + " }\ndiagnostic_reports extracted\n"
else:
    driver += r'''
source $::env(SCRIPTS_DIR)/openroad/common/resizer.tcl
set_dont_touch_objects
source $::env(SCRIPTS_DIR)/openroad/common/set_rc.tcl
source $::env(SCRIPTS_DIR)/openroad/common/grt.tcl
estimate_parasitics -global_routing
diagnostic_reports before
'''
    driver += f"repair_design -verbose -slew_margin {args.slew_margin} -cap_margin {config.get('GRT_DESIGN_REPAIR_MAX_CAP_PCT', 20) if args.generated_settings else 20} -max_wire_length {args.max_wire_length}\n"
    driver += r'''
source $::env(SCRIPTS_DIR)/openroad/common/dpl.tcl
unset_dont_touch_objects
source $::env(SCRIPTS_DIR)/openroad/common/grt.tcl
estimate_parasitics -global_routing
diagnostic_reports after
write_views
'''
(out / "driver.tcl").write_text("if {[catch {\n" + driver + "\n} message options]} {puts stderr $message; puts stderr [dict get $options -errorinfo]; exit 1}\n")
scripts = "/nix/store/6a08ghhhzl5a07nr0ly762yh1ah6m5bj-python3-3.13.13-env/lib/python3.13/site-packages/librelane/scripts"
image = "sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a"
name = "asic-slew-diagnostic-" + uuid.uuid4().hex[:12]
command = ["docker", "run", "--rm", "--name", name, "--network", "none", "--cpus", "6",
           "--user", f"{os.getuid()}:{os.getgid()}", "-v", "/home/wayne/devel/jane:/home/wayne/devel/jane:ro",
           "-v", f"{out}:{out}:rw", "-w", str(out), "-e", "OMP_NUM_THREADS=6", "-e", "OPENROAD_THREADS=6",
           "-e", f"_TCL_ENV_IN={out / 'env.tcl'}", "-e", f"SCRIPTS_DIR={scripts}", image,
           "openroad", "-exit", "-no_splash", "-threads", "6", "-metrics", str(out / "metrics.json"), str(out / "driver.tcl")]
hashes = {str(p): sha(p) for p in inputs}
(out / "commands.json").write_text(json.dumps({"command": command, "mode": args.mode, "inputs_sha256": hashes, "timeout_seconds": 300}, indent=2) + "\n")
try:
    with (out / "openroad.log").open("w") as channel:
        result = subprocess.run(command, stdout=channel, stderr=subprocess.STDOUT, timeout=300)
except subprocess.TimeoutExpired:
    subprocess.run(["docker", "stop", "--time", "5", name], check=False)
    raise
assert all(sha(Path(p)) == digest for p, digest in hashes.items()), "preserved input changed"
print(f"exit={result.returncode} artifacts={out}")
raise SystemExit(result.returncode)
