"""Production-rendered v2 API-model controls. No native acceptance inferred."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

exe, old_fixture, fixture, root, probe = map(lambda p: str(Path(p).resolve()), sys.argv[1:])
def emit(*args):
    return subprocess.run([exe, *args], check=True, text=True, capture_output=True).stdout

v1, v2 = emit("v1"), emit("v2")
old, new = json.loads(emit("bundle", root))
assert old["timing_intent"]["resolution_policy"] == "scalar-q-driver-cmos5l-v1"
assert new["timing_intent"]["resolution_policy"] == "scalar-q-driver-cmos5l-physical-v2"
assert new["timing_physical_qualification"]["analysis_corners"] == "all_configured"
assert old["timing_native_coverage"] == new["timing_native_coverage"]
assert "checked_endpoints" not in v1
assert v1.split("\n::hc_pt7::run")[0] == v2.split("\n# scalar-q-driver-cmos5l-physical-v2")[0]

positives = ["good", "dual_q_master", "buffered_clock", "buffered_capture", "buffered_reset",
             "eight_buffers", "interstage", "delay_interstage", "delay_clock", "delay_capture",
             "delay_reset", "moved_anchor", "interstage_eight", "q_output_sink",
             "anchor_eight", "buffer4", "buffer8", "buffer16", "sized_flops"]
negatives = {
    "wrong_predecessor": "unqualified", "interstage_inversion": "unqualified",
    "unknown_delay": "unqualified", "interstage_nine": "exceeds eight", "anchor_nine": "exceeds eight",
    "root_contention": "exactly one", "input_contention": "ambiguous physical input",
    "q_input_contention": "contending input", "shifted_input": "contending input",
    "anchor_inversion": "unqualified", "merged_anchor": "merged timing stage",
    "extra_register": "sequential inventory", "missing_register": "sequential inventory",
    "duplicate_register": "sequential inventory", "buffer_cycle": "cyclic physical",
    "nine_buffers": "exceeds eight", "wrong_buffer_pin": "transform driver is not X",
    "multi_driver": "exactly one", "wrong_reset_source": "contending input",
    "wrong_clock": "contending input", "empty_anchor": "exactly one",
    "ambiguous_anchor": "exactly one", "nonexact_anchor": "exactly one",
    "wrong_pin_direction": "wrong pin direction", "constant_reset": "unqualified",
}
def run(case, sdc):
    prefix = f"set case {{{case}}}\nsource {{{old_fixture}}}\nsource {{{fixture}}}\n"
    script = prefix + "set code [catch {\n" + sdc + "\n} message]\n"
    script += '''
puts "RESULT\\t$code\\t$applied_count\\t$message"
set map_code [catch {::hc_pt7::checked_endpoints} endpoints]
puts "MAP\\t$map_code"
if {!$map_code} {
    if {[dict get $endpoints rx0 q] ne "rx0/Q" || [dict get $endpoints rx1 data] ne "rx1/D"} {error "wrong checked endpoints"}
    puts "TRACES\\t[llength [::hc_pt7::checked_traces]]"
    # A subsequent failed invocation must invalidate the map, never publish stale success.
    catch {::hc_pt7::run [list [list missing no_anchor 0 chain 0]] {}}
    puts "STALE\\t[catch {::hc_pt7::checked_endpoints}]"
}
'''
    p = subprocess.run(["tclsh"], input=script, text=True, capture_output=True, timeout=10)
    assert p.returncode == 0 and not p.stderr, (case, p.stdout, p.stderr)
    lines = p.stdout.splitlines()
    events = [json.loads(x.split("\t", 1)[1]) for x in lines if x.startswith("HC_ASIC_TIMING_V1\t")]
    result = next(x.split("\t", 3)[1:] for x in lines if x.startswith("RESULT\t"))
    return lines, events, (int(result[0]), int(result[1]), result[2])

for case in positives + list(negatives) + ["apply_failure"]:
    lines, events, (code, applied, message) = run(case, v2)
    if case in negatives:
        assert code == 1 and applied == 0 and negatives[case] in message, (case, message)
        assert not any(e["event"] in ("validated", "applied", "complete") for e in events)
        assert "MAP\t1" in lines
    elif case == "apply_failure":
        assert code == 1 and applied == 2 and "MAP\t1" in lines
    else:
        assert code == 0 and applied == 2 and "MAP\t0" in lines and "STALE\t1" in lines, (case, message)
        traces = [e for e in events if e["event"] == "trace"]
        assert len(traces) == 13, (case, traces)
        for trace in traces:
            assert len(trace["nets"]) == len(trace["hops"]) + 1
            assert set(trace) == {"schema_version", "event", "label", "root", "sink", "nets", "hops"}
            for hop in trace["hops"]:
                assert set(hop) == {"cell", "master", "input", "output"}
        if case == "moved_anchor":
            assert next(t for t in traces if t["label"] == "anchor for rx0")["root"] == "rx0/Q"
        if case == "interstage_eight":
            assert len(next(t for t in traces if t["label"] == "interstage for rx1")["hops"]) == 8

# V1 still rejects physical transforms rather than receiving the new semantics.
for case in ("interstage", "moved_anchor", "delay_capture"):
    _, _, (code, applied, _) = run(case, v1)
    assert code == 1 and applied == 0

# Exercise the supplied C probe's map integration with a moved anchor. The model
# records witness arguments; native path existence/effect is still C's control.
with tempfile.TemporaryDirectory(prefix="physical-probe-", dir="/tmp/opencode") as directory:
    sdc = Path(directory) / "emitted.sdc"
    sdc.write_text(v2)
    script = f"set case moved_anchor\nsource {{{old_fixture}}}\nsource {{{fixture}}}\n"
    script += f"set hc_physical_sdc {{{sdc}}}\nset hc_physical_output {{{directory}}}\n"
    script += '''
proc read_sdc {path} { uplevel #0 [list source $path] }
proc write_sdc {args} {set f [open [lindex $args end] w]; close $f}
set witness_calls {}
proc report_checks {args} { lappend ::witness_calls $args }
'''
    script += f"source {{{probe}}}\n"
    script += '''
if {[llength $witness_calls] != 4} {error "missing mapped witnesses"}
foreach args $witness_calls {
    set source [lindex $args 1]
    set target [lindex $args 3]
    if {[list $source $target] ni {{rx0/Q rx1/D} {rr0/Q rr1/D}}} {error "probe bypassed endpoint map"}
}
puts PROBE_MAP_MODEL_OK
'''
    p = subprocess.run(["tclsh"], input=script, text=True, capture_output=True, timeout=10)
    assert p.returncode == 0 and not p.stderr and "PROBE_MAP_MODEL_OK" in p.stdout, (p.stdout, p.stderr)
print(f"physical v2: {len(positives)} positives, {len(negatives)} resolve-before-apply negatives; checked maps, traces, application failure, stale-map rejection and explicit bundle identity passed")
