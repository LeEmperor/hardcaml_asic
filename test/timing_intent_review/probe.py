"""Independent corrected-library regression. Synthetic linked graph, no EDA.
Native Port/Pin/Term distinction from C's A-REAL-2, * / ? name semantics.
"""
import json
from pathlib import Path
import subprocess
import sys

exe = Path(sys.argv[1]).resolve()
objects = Path(sys.argv[2]).resolve()
sdc = subprocess.run([str(exe), "sdc"], check=True, text=True, capture_output=True).stdout
positives = ["good", "buffered_clock", "buffered_capture", "buffered_reset", "eight_buffers", "top_output_source", "top_output_buffer", "top_output_anchor"]
negatives = {
    "wrong_clock": "mapped clock for review1: mapped source differs",
    "wrong_capture_source": "mapped capture source for review0: mapped source differs",
    "wrong_reset_source": "mapped active-low reset source for review1: mapped source differs",
    "wrong_interstage": "mapped interstage data differs",
    "missing_reset_pin": "expected exactly one",
    "disconnected_clock": "expected exactly one",
    "null_clock": "disconnected/null net",
    "constant_clock": "unsupported/disconnected source driver",
    "disconnected_capture": "expected exactly one",
    "disconnected_reset": "expected exactly one",
    "shorted_inputs": "ambiguous mapped input driver",
    "source_internal_driver": "ambiguous mapped input driver",
    "nine_buffers": "exceeds eight buffer hops",
    "inverted_clock": "unsupported source transform",
    "inverted_capture": "unsupported source transform",
    "inverted_reset": "unsupported source transform",
    "unknown_logic": "unsupported source transform",
    "wrong_buffer_root": "mapped source differs from declared input",
    "multiple_drivers": "expected exactly one",
    "cycle": "cyclic mapped source trace",
    "missing_buffer_A": "expected exactly one",
    "null_buffer_A": "disconnected/null net",
    "multi_buffer_A": "expected exactly one",
    "wrong_buffer_output": "source buffer driver is not X",
    "buffered_interstage": "mapped interstage data differs",
    "null_port_pin": "input port has no scalar top pin",
    "empty_port_pin": "input port has no scalar top pin",
    "wrong_port_pin": "top pin differs from input port",
    "null_top_term": "input top pin has no internal Term",
    "empty_top_term": "top-pin Term: expected exactly one",
    "multiple_top_terms": "top-pin Term: expected exactly one",
    "null_term_net": "disconnected/null internal Term net",
    "empty_term_net": "internal Term net: expected exactly one",
    "multiple_term_nets": "internal Term net: expected exactly one",
}
for case in [*positives, *negatives]:
    assert "{" not in str(objects) and "}" not in str(objects)
    script = f"set case {case}\nsource {{{objects}}}\n"
    script += '''
# A fixture that treats Port as Pin would hide the native API bug.
if {![catch {get_nets -of_objects Port:clk} rejected] || ![string match *never*Port* $rejected]} { error "Port accepted as Pin" }
if {![catch {::sta::get_port_pin TopPin:clk} rejected]} { error "adapter accepted a Pin" }
if {[get_full_name Port:clk] ne [get_full_name [::sta::get_port_pin Port:clk]]} { error "Port/Pin full-name mismatch" }
if {[get_nets -of_objects TopPin:clk] ne "NULL" || [TopPin:clk net] ne "NULL"} { error "top Pin external net is not NULL" }
if {[get_full_name [[TopPin:clk term] net]] ne "clk_net"} { error "top Pin Term internal net missing" }
set queried {}
'''
    script += "set code [catch {\n" + sdc + "\n} message]\n"
    script += 'puts "RESULT\\t$code\\t[llength $applied]\\t$message"\n'
    script += 'puts "QUERIED\\t$queried"\n'
    if case == "good":
        script += '''
foreach literal [list {lit*} {question?} {name with space} {slash\\name}] {
    lappend ports $literal
    set found [::hc_pt7::exact get_ports $literal]
    if {[get_full_name $found] ne $literal} { error "literal mismatch" }
}
lappend ports lit_neighbor questionx
if {[get_full_name [::hc_pt7::exact get_ports {lit*}]] ne {lit*}} { error "wildcard neighbor selected" }
lappend ports {ui_in[0]}
if {![catch {::hc_pt7::exact get_ports {ui_in[0]}} rejected]} { error "ambiguous exact bus accepted" }
puts LITERAL_OK
'''
    p = subprocess.run(["tclsh"], input=script, text=True, capture_output=True, timeout=10)
    assert p.returncode == 0 and not p.stderr, (case, p)
    records = [json.loads(x.split("\t", 1)[1]) for x in p.stdout.splitlines() if x.startswith("HC_ASIC_TIMING_V1\t")]
    summary = next(x.split("\t", 3)[1:] for x in p.stdout.splitlines() if x.startswith("RESULT"))
    code, applied, message = int(summary[0]), int(summary[1]), summary[2]
    events = [r["event"] for r in records]
    queries = next(x for x in p.stdout.splitlines() if x.startswith("QUERIED"))
    assert "get_nets -of_objects TopPin:" not in queries and "top_pin net " not in queries
    if case in positives:
        assert code == 0 and applied == 2, (case, summary, events)
        assert events == ["begin", "stage", "stage", "resolved", "resolved", "validated", "applied", "applied", "complete"]
        assert records[3]["source"] == "ui_in[0]" and records[3]["targets"] == ["u0/D"]
        assert records[4]["targets"] == ["u0/RESET_B", "u1/RESET_B"]
        if case == "good":
            assert "LITERAL_OK" in p.stdout
            for pin in ["u1/CLK", "u0/D", "u1/RESET_B"]:
                assert f"get_nets -of_objects Pin:{pin}" in queries
            assert "port_to_pin Port:clk" in queries
            assert "top_pin term clk" in queries and "term net clk" in queries
        print("PASS", case)
    else:
        assert code == 1 and applied == 0 and not {"validated", "applied", "complete"}.intersection(events), (case, summary, events)
        expected = negatives[case]
        assert expected in message, (case, summary)
        print("REJECTED", case, message)
print(f"Independent corrected A regression: {len(positives)} positives, {len(negatives)} pre-application negatives, native Port/Pin/Term and literal-name controls; Q output tap now accepted.")
