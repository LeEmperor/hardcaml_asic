"""Library and production-emitted Tcl checks; deliberately no EDA or Git mutations."""
import json
import pathlib
import subprocess
import sys

exe = str(pathlib.Path(sys.argv[1]).resolve())
fixture = str(pathlib.Path(sys.argv[2]).resolve())


def command(*args):
    return subprocess.run([exe, *args], check=True, text=True, capture_output=True).stdout


print(command(), end="")
sdc = command("sdc")
intent = json.loads(command("json"))
assert intent["contract"] == "hardcaml-asic.timing-intent"
assert [s["id"] for s in intent["stages"]] == ["rr0", "rr1", "rx0", "rx1"]
assert intent["exceptions"][1]["targets"] == ["rr0", "rr1"]
rtl = command("rtl")
assert rtl.count("keep=1") == 4, rtl
for stage in intent["stages"]:
    assert stage["anchor"] in rtl

negatives = {
    "empty_anchor": "expected exactly one",
    "ambiguous_anchor": "expected exactly one",
    "nonexact_anchor": "expected exactly one",
    "empty_driver": "expected exactly one",
    "ambiguous_driver": "expected exactly one",
    "inverted_q": "not noninverting Q",
    "unknown_master": "unsupported mapped master",
    "wrong_pin_direction": "wrong pin direction",
    "wrong_data_net": "interstage data differs",
    "wrong_source_direction": "source is not input",
    "late_missing_port": "expected exactly one",
    "merged": "not noninverting Q",
    "wrong_clock": "mapped clock for rx1: mapped source differs",
    "disconnected_clock": "mapped clock for rx1 net: expected exactly one",
    "null_clock": "mapped clock for rx1: disconnected/null net",
    "constant_clock": "unsupported/disconnected source driver",
    "inverted_clock": "unsupported source transform",
    "wrong_capture_source": "mapped capture source for rx0: mapped source differs",
    "disconnected_capture": "mapped capture source for rx0 net: expected exactly one",
    "null_capture": "mapped capture source for rx0: disconnected/null net",
    "wrong_reset_source": "mapped active-low reset source for rr1: mapped source differs",
    "disconnected_reset": "mapped active-low reset source for rr1 net: expected exactly one",
    "null_reset": "mapped active-low reset source for rr1: disconnected/null net",
    "constant_reset": "unsupported source transform",
    "inverted_capture": "unsupported source transform",
    "inverted_reset": "unsupported source transform",
    "unknown_transform": "unsupported source transform",
    "wrong_buffer_pin": "source buffer driver is not X",
    "multi_driver": "expected exactly one",
    "buffer_cycle": "cyclic mapped source trace",
    "nine_buffers": "exceeds eight buffer hops",
    "shorted_inputs": "ambiguous mapped input driver",
    "missing_reset_pin": "expected exactly one",
    "null_top_pin": "input port has no scalar top pin",
    "wrong_top_pin": "top pin differs from input port",
    "null_top_term": "input top pin has no internal Term",
    "empty_top_term": "top-pin Term: expected exactly one",
    "multiple_top_terms": "top-pin Term: expected exactly one",
    "null_internal_net": "disconnected/null internal Term net",
    "empty_internal_net": "internal Term net: expected exactly one",
    "multiple_internal_nets": "internal Term net: expected exactly one",
}
positives = ["good", "dual_q_master", "buffered_clock", "buffered_capture", "buffered_reset", "eight_buffers", "top_output_sink", "q_output_sink"]
for case in [*positives, *negatives, "apply_failure"]:
    # Tcl source paths are passed as argv data, never interpolated into code.
    # Set literal safe case and fixture through Tcl-list serialization with a
    # simple restricted path.
    assert "}" not in fixture and "{" not in fixture
    script = f"set case {{{case}}}\nsource {{{fixture}}}\n"
    script += "set code [catch {\n" + sdc + "\n} message]\n"
    script += 'puts "FIXTURE_RESULT\\t$code\\t$applied_count\\t$message"\n'
    script += 'puts "EXTERNAL_NET_READS\\t$external_net_reads"\n'
    script += 'puts [::hc_pt7::json_string "quote\\\" slash\\\\ tab\\t newline\\n"]\n'
    result = subprocess.run(["tclsh"], input=script, text=True, capture_output=True, timeout=10)
    assert result.returncode == 0 and not result.stderr, (case, result)
    lines = result.stdout.splitlines()
    records = [json.loads(line.split("\t", 1)[1]) for line in lines if line.startswith("HC_ASIC_TIMING_V1\t")]
    summary = next(line.split("\t", 3)[1:] for line in lines if line.startswith("FIXTURE_RESULT\t"))
    code, applied, message = int(summary[0]), int(summary[1]), summary[2]
    assert "EXTERNAL_NET_READS\t0" in lines, (case, result.stdout)
    assert json.loads(lines[-1]) == 'quote" slash\\ tab\t newline\n'
    assert records[0]["event"] == "begin"
    assert all(r["schema_version"] == 1 for r in records)
    events = [r["event"] for r in records]
    if case in negatives:
        assert code == 1 and applied == 0 and negatives[case] in message, (case, summary, events)
        assert "validated" not in events and "applied" not in events and "complete" not in events
    elif case == "apply_failure":
        assert code == 1 and applied == 2
        assert events.count("applied") == 1 and "validated" in events and "complete" not in events
    else:
        assert code == 0 and applied == 2, (case, summary)
        assert events == ["begin", *(["stage"] * 4), "resolved", "resolved", "validated", "applied", "applied", "complete"]
        assert records[5]["source"] == "ui_in[0]"
        assert records[5]["targets"] == ["rx0/D"]
        assert records[6]["targets"] == ["rr0/RESET_B", "rr1/RESET_B"]
print(f"emitted Tcl: {len(positives)} positives, {len(negatives)} resolve-before-apply negatives, application-failure and JSON escaping passed")

# Literal lookup probes use OpenSTA's native wildcard model: brackets are literal;
# candidate patterns may match other names but exact full-name filtering must
# neither choose a wildcard neighbor nor discard duplicate exact objects.
script = f"set case good\nsource {{{fixture}}}\n"
script += r'''
set p [::sta::get_port_pin clk]
if {[get_nets -of_objects $p] ne "NULL"} { error "fixture lost native NULL external Pin net" }
set term [$p term]
if {$term eq "NULL" || [$term net] ne "clk_net"} { error "fixture lost connected internal Term net" }
'''
script += sdc + "\n"
script += r'''
if {$external_net_reads != 1} { error "production queried external Pin net instead of internal Term" }
lappend ports {lit*} lit_neighbor {question?} questionx {name with space}
foreach literal [list {ui_in[0]} {lit*} {question?} {name with space}] {
    set found [::hc_pt7::exact get_ports $literal]
    if {$found ne $literal} { error "nonliteral lookup: $literal -> $found" }
}
lappend ports {ui_in[0]}
if {![catch {::hc_pt7::exact get_ports {ui_in[0]}} error]} { error "duplicate exact bus objects accepted" }
puts LITERAL_LOOKUP_OK
'''
result = subprocess.run(["tclsh"], input=script, text=True, capture_output=True, timeout=10)
assert result.returncode == 0 and not result.stderr and "LITERAL_LOOKUP_OK" in result.stdout, result
print("native-pattern fixture: literal bus/wildcard/question/space names and exact ambiguity rejection passed")
print("native-boundary fixture: top Pin external net NULL, connected Term internal net, zero production external-net queries passed")
