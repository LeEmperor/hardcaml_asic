"""Independent A-library review. Only Tcl API models and read-only Liberty work.

No A fixtures, tests, resolver implementation or collateral checker are imported.
The resolver under test is public production emission from review_emit.exe.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def call(args, data=None):
    result = subprocess.run(list(map(str, args)), input=data, text=True, capture_output=True, timeout=30)
    assert result.returncode == 0, (args, result.returncode, result.stdout, result.stderr)
    return result.stdout


def graph_probe(work, model, sdc, label, mutation="", reject_application=0, repeated=False):
    # The full bundle/identity is reviewed separately. Run its exact resolver
    # suffix here, without pretending the inert graph implements clock timing.
    sdc = sdc[sdc.index("# Generated exact scalar timing intent"):]
    script = "source " + tcl_literal(str(model)) + "\n" + mutation + "\n"
    emitted = work / (label + ".sdc")
    emitted.write_text(sdc)
    if repeated:
        script += "source " + tcl_literal(str(emitted)) + "\n"
        script += "set apply_attempts 0; set apply_successes 0; set applied_scopes {}; set map_during_apply {}\n"
        script += "dict set connections rx1/CLK nena\nputs REVIEW_REPEAT_BEGIN\n"
    script += f"set reject_application {reject_application}\n"
    script += "set code [catch {source " + tcl_literal(str(emitted)) + "} message]\n"
    script += r'''
set map_code [catch {::hc_pt7::checked_endpoints} endpoint_map]
set traces_code [catch {::hc_pt7::checked_traces} checked_traces]
set maps {}
if {!$map_code} {
    dict for {id row} $endpoint_map {
        set fields {}
        dict for {key value} $row { lappend fields "[::hc_pt7::json_string $key]:[::hc_pt7::json_string $value]" }
        lappend maps "[::hc_pt7::json_string $id]:\{[join $fields ,]\}"
    }
}
set scopes {}
foreach args $applied_scopes {
    set source [lindex $args 1]; set targets [lindex $args 3]
    lappend scopes "\{\"source\":[::hc_pt7::json_string $source],\"targets\":[::hc_pt7::array_json $targets]\}"
}
puts "REVIEW_RESULT\t\{\"code\":$code,\"attempts\":$apply_attempts,\"successes\":$apply_successes,\"message\":[::hc_pt7::json_string $message],\"map_code\":$map_code,\"traces_code\":$traces_code,\"map\":\{[join $maps ,]\},\"during_apply\":\[[join $map_during_apply ,]\],\"scopes\":\[[join $scopes ,]\]\}"
'''
    path = work / (label + ".tcl")
    path.write_text(script)
    result = subprocess.run(["tclsh", str(path)], text=True, capture_output=True, timeout=15)
    (work / (label + ".stdout")).write_text(result.stdout)
    (work / (label + ".stderr")).write_text(result.stderr)
    assert result.returncode == 0 and not result.stderr, (label, result.returncode, result.stdout, result.stderr)
    output = result.stdout.split("REVIEW_REPEAT_BEGIN\n")[-1]
    lines = output.splitlines()
    summary = json.loads(next(line.split("\t", 1)[1] for line in lines if line.startswith("REVIEW_RESULT\t")))
    events = [(i, json.loads(line.split("\t", 1)[1])) for i, line in enumerate(lines) if line.startswith("HC_ASIC_TIMING_V1\t")]
    applications = [i for i, line in enumerate(lines) if line.startswith("REVIEW_APPLY\t")]
    if applications:
        validated = [i for i, event in events if event["event"] == "validated"]
        assert len(validated) == 1 and validated[0] < min(applications), (label, output)
        assert summary["during_apply"] == [1] * summary["attempts"], (label, summary)
    summary["events"] = [event for _, event in events]
    return summary


def tcl_literal(value):
    return '"' + ''.join({"\\": "\\\\", '"': '\\"', "$": "\\$", "[": "\\[", "]": "\\]", "\n": "\\n"}.get(c, c) for c in value) + '"'


def liberty_tokens(raw):
    # Quoted strings and comments are lexical tokens, so braces/keywords inside
    # either cannot create a cell, pin, or timing group.
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|/\*.*?\*/|//[^\n]*|[{}():;,]|[^\s{}():;,]+', raw.decode("latin1"), re.S)
    return [token for token in tokens if not token.startswith(("/*", "//"))]


def groups(tokens, kind):
    result = []
    for i in range(len(tokens) - 4):
        if tokens[i:i+2] != [kind, "("]:
            continue
        close = i + 2
        while tokens[close] != ")":
            close += 1
        if tokens[close+1] != "{":
            continue
        depth, end = 1, close + 2
        while depth:
            depth += (tokens[end] == "{") - (tokens[end] == "}")
            end += 1
        args = [literal(t) for t in tokens[i+2:close] if t != ","]
        result.append((args, tokens[close+2:end-1]))
    return result


def literal(token):
    return token[1:-1] if token.startswith('"') else token


def attrs(tokens):
    result, depth, i = {}, 0, 0
    while i < len(tokens):
        if tokens[i] == "{": depth += 1
        elif tokens[i] == "}": depth -= 1
        elif depth == 0 and i + 1 < len(tokens) and tokens[i+1] == ":":
            end = i + 2
            while tokens[end] != ";": end += 1
            assert tokens[i] not in result, (tokens[i], "duplicate attribute")
            result[tokens[i]] = "".join(literal(t) for t in tokens[i+2:end])
            i = end
        i += 1
    return result


def one_group(tokens, kind, name):
    found = [body for args, body in groups(tokens, kind) if args == [name]]
    assert len(found) == 1, (kind, name, len(found))
    return found[0]


def inspect_libraries(pdk, supported):
    rows = []
    for corner in ("fast_1p32V_m40C", "typ_1p20V_25C", "slow_1p08V_125C"):
        path = pdk / "ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/lib" / ("sg13cmos5l_stdcell_" + corner + ".lib")
        before = digest(path)
        tokens = liberty_tokens(path.read_bytes())
        cells = {}
        for name in supported:
            body = one_group(tokens, "cell", name)
            pins = {args[0]: data for args, data in groups(body, "pin")}
            assert set(pins) == {"A", "X"}, (corner, name, list(pins))
            a, x = attrs(pins["A"]), attrs(pins["X"])
            assert a["direction"] == "input" and x["direction"] == "output" and x["function"] == "A", (corner, name, a, x)
            assert all(not groups(body, kind) for kind in ("ff", "latch", "statetable")), (corner, name, "sequential")
            arcs = [attrs(data) for _, data in groups(pins["X"], "timing")]
            assert arcs and all(arc.get("related_pin") == "A" and arc.get("timing_sense") == "positive_unate" for arc in arcs), (corner, name, arcs)
            cells[name] = dict(input="A", output="X", function=x["function"], arcs=arcs)
        flops = {}
        for name in ("sg13cmos5l_dfrbpq_1", "sg13cmos5l_dfrbpq_2", "sg13cmos5l_dfrbp_1", "sg13cmos5l_dfrbp_2"):
            body = one_group(tokens, "cell", name)
            ff = groups(body, "ff")
            assert len(ff) == 1, (corner, name, "ff")
            state_names, ff_body = ff[0]
            semantics = attrs(ff_body)
            assert semantics["clocked_on"].strip("() ") == "CLK" and semantics["next_state"].strip("() ") == "D", (corner, name, semantics)
            assert semantics["clear"].replace(" ", "").strip("()") == "!RESET_B" and "preset" not in semantics, (corner, name, semantics)
            q = attrs(one_group(body, "pin", "Q"))
            assert q["direction"] == "output" and q["function"] == state_names[0], (corner, name, q, state_names)
            for pin in ("D", "CLK", "RESET_B"):
                assert attrs(one_group(body, "pin", pin))["direction"] == "input"
            flops[name] = semantics
        inv = one_group(tokens, "cell", "sg13cmos5l_inv_1")
        inv_y = one_group(inv, "pin", "Y")
        assert attrs(inv_y)["function"].replace(" ", "").replace("(", "").replace(")", "") == "!A"
        assert any(attrs(data).get("timing_sense") == "negative_unate" for _, data in groups(inv_y, "timing"))
        assert digest(path) == before
        rows.append(dict(corner=corner, path=str(path.resolve()), sha256=before, cells=cells, flops=flops,
                         inverter_control="Y=!A/negative_unate, not admitted by the physical table"))
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--asic", type=Path, required=True)
    parser.add_argument("--pdk", type=Path, required=True)
    args = parser.parse_args()
    asic, pdk = args.asic.resolve(), args.pdk.resolve()
    owned = [asic / p for p in ("lib/elaboration/timing_tcl.ml", "lib/elaboration/timing_intent.ml", "lib/elaboration/timing_intent.mli",
             "lib/elaboration/bundle.ml", "lib/elaboration/bundle.mli", "lib/elaboration/context.ml")]
    before = {str(path): digest(path) for path in owned}
    work = Path(tempfile.mkdtemp(prefix="timing-library-independent-review-", dir="/tmp/opencode"))
    emitter = asic / "_build/default/test/timing_physical_library_review/review_emit.exe"
    model = Path(__file__).with_name("model.tcl").resolve()
    emitted = json.loads(call([emitter, "emit", "good", asic]))
    (work / "emission.json").write_text(json.dumps(emitted, indent=2))
    plain, false, physical = (emitted[name] for name in ("default", "false", "physical"))
    assert all(x["status"] == "emitted" for x in (plain, false, physical))
    assert plain == false and plain["rtl"] == physical["rtl"] and plain["native"] == physical["native"]
    assert plain["manifest"]["identity"] != physical["manifest"]["identity"]
    assert "timing_physical_qualification" not in plain["manifest"]
    assert physical["manifest"]["timing_physical_qualification"]["endpoint_map"] == "::hc_pt7::checked_endpoints"
    assert plain["manifest"]["timing_intent"]["resolution_policy"] == "scalar-q-driver-cmos5l-v1"
    assert physical["manifest"]["timing_intent"]["resolution_policy"] == "scalar-q-driver-cmos5l-physical-v2"
    def verify(manifest): return json.loads(call([emitter, "verify"], json.dumps(manifest)))["valid"]
    assert verify(plain["manifest"]) and verify(physical["manifest"])
    for key in ("max_buffer_hops", "endpoint_map", "analysis_corners"):
        changed = copy.deepcopy(physical["manifest"])
        changed["timing_physical_qualification"][key] = "independent substitution"
        assert not verify(changed)
    changed = copy.deepcopy(physical["manifest"]); changed.pop("timing_physical_qualification")
    assert not verify(changed)
    changed = copy.deepcopy(physical["manifest"]); changed["timing_intent"]["resolution_policy"] = "scalar-q-driver-cmos5l-v1"
    assert not verify(changed)
    for item in (plain, physical):
        record = next(row for row in item["manifest"]["files"] if row["path"] == "constraints/top.sdc")
        assert record["sha256"] == hashlib.sha256(item["sdc"].encode()).hexdigest()
    # Compare the frozen legacy primitive Tcl block with the checkout's HEAD,
    # using Git read-only, independently of A's current render-equality test.
    historical = call(["git", "-C", asic, "show", "HEAD:lib/elaboration/timing_tcl.ml"])
    legacy = historical.split("let helpers = {tcl|", 1)[1].split("|tcl}", 1)[0]
    assert plain["sdc"].count(legacy) == 1

    supported = [f"sg13cmos5l_buf_{n}" for n in (1, 2, 4, 8, 16)] + [f"sg13cmos5l_dlygate4sd{n}_1" for n in (1, 2, 3)]
    # These are actual graph mutations, not mutations of the generated resolver.
    positive = {"direct": "", "inventory-order": "set registers {rx1 rr0 rx0 rr1}",
        "shared-clock-fanout": "buffer shared nclk clock_branch; foreach s $registers {dict set connections $s/CLK clock_branch}",
        "top-output-sink": "dict set connections out hc_pt7_rx0"}
    for master in supported:
        for role, source, sink in (("clock", "nclk", "rx1/CLK"), ("capture", "ndata", "rx0/D"),
                                   ("reset", "nrst", "rx1/RESET_B"), ("interstage", "hc_pt7_rx0", "rx1/D")):
            positive[master + "-" + role] = f"chain reviewed {source} {sink} 1 {master}"
    for role, source, sink in (("clock", "nclk", "rx1/CLK"), ("capture", "ndata", "rx0/D"),
                               ("reset", "nrst", "rx1/RESET_B"), ("interstage", "hc_pt7_rx0", "rx1/D")):
        positive[role + "-eight"] = f"chain deep {source} {sink} 8 sg13cmos5l_dlygate4sd3_1"
    positive["moved-anchor-eight"] = "dict set connections rx0/Q original_q; chain moved original_q rx1/D 8; dict set connections moved_7/X hc_pt7_rx0; dict set connections rx1/D hc_pt7_rx0"
    positive["supported-sizing"] = "dict set masters rr0 sg13cmos5l_dfrbp_1; dict set masters rr1 sg13cmos5l_dfrbp_2; dict set masters rx1 sg13cmos5l_dfrbpq_2"

    negative = {
        "wrong-predecessor-direct": "dict set connections rx1/D hc_pt7_rr0",
        "wrong-predecessor-buffered": "chain wrong hc_pt7_rr0 rx1/D 2",
        "wrong-stage-root-alias": "dict set connections rx0/Q abandoned; buffer alias hc_pt7_rr0 hc_pt7_rx0",
        "alias-two-inputs": "dict set connections ena ndata",
        "alias-clock-input": "dict set connections ena nclk",
        "alias-q-input": "dict set connections ena hc_pt7_rx0",
        "intermediate-input-contention": "chain cap ndata rx0/D 2; dict set connections ena cap_net_0",
        "q-driver-contention": "buffer extra nena hc_pt7_rx0",
        "merged-anchors": "dict set connections rx1/Q abandoned; buffer merge hc_pt7_rx0 hc_pt7_rx1",
        "anchor-cycle": "buffer ring hc_pt7_rx0 ringnet; buffer ring2 ringnet hc_pt7_rx0; dict set connections rx0/Q abandoned",
        "source-self-cycle": "buffer self selfnet selfnet; dict set connections rx0/D selfnet",
        "interstage-cycle": "buffer a cycle_b cycle_a; buffer b cycle_a cycle_b; dict set connections rx1/D cycle_a",
        "clock-inversion": "chain inv nclk rx1/CLK 1 sg13cmos5l_inv_1",
        "double-clock-inversion-not-guessed": "chain inv nclk rx1/CLK 2 sg13cmos5l_inv_1",
        "reset-inversion": "chain inv nrst rx1/RESET_B 1 sg13cmos5l_inv_1",
        "unqualified-delay-prefix": "chain bad hc_pt7_rx0 rx1/D 1 sg13cmos5l_dlygate4sd4_1",
        "unqualified-buffer-prefix": "chain bad hc_pt7_rx0 rx1/D 1 sg13cmos5l_buf_32",
        "wrong-buffer-input-direction": "chain bad ndata rx0/D 1; dict set directions bad_0/A output",
        "wrong-buffer-output-pin": "chain bad ndata rx0/D 1; dict set directions bad_0/X input",
        "wrong-reset-direction": "dict set directions rx1/RESET_B output",
        "inverted-Q-anchor": "dict set connections rx0/Q abandoned; dict set directions rx0/Q_N output; dict set owners rx0/Q_N rx0; dict set connections rx0/Q_N hc_pt7_rx0",
        "unsupported-stage-master": "dict set masters rx1 sg13cmos5l_dfrbpq_4",
        "inventory-extra-flop": "lappend registers hidden_ff",
        "inventory-extra-latch": "lappend registers hidden_latch",
        "inventory-missing": "set registers {rr0 rr1 rx0}",
        "inventory-duplicate": "lappend registers rx0",
        "late-enumerated-reset-mismatch": "dict set connections rx1/RESET_B nena",
        "late-disconnected-reset": "dict unset connections rx1/RESET_B",
        "ambiguous-exact-anchor": "lappend net_names hc_pt7_rx1",
    }
    for role, source, sink in (("clock", "nclk", "rx1/CLK"), ("capture", "ndata", "rx0/D"),
                               ("reset", "nrst", "rx1/RESET_B"), ("interstage", "hc_pt7_rx0", "rx1/D")):
        negative[role + "-nine"] = f"chain deep {source} {sink} 9"
    negative["moved-anchor-nine"] = "dict set connections rx0/Q original_q; chain moved original_q rx1/D 9; dict set connections moved_8/X hc_pt7_rx0; dict set connections rx1/D hc_pt7_rx0"
    observations = []
    for label, mutation in positive.items():
        result = graph_probe(work, model, physical["sdc"], label, mutation)
        assert result["code"] == 0 and result["attempts"] == result["successes"] == 2 and result["map_code"] == result["traces_code"] == 0, (label, result)
        assert len(result["map"]) == 4
        for stage, row in result["map"].items():
            assert row["cell"] == stage and row["q"] == stage + "/Q" and row["data"] == stage + "/D"
        assert result["scopes"] == [dict(source="ui_in[0]", targets=["rx0/D"]), dict(source="rst_n", targets=["rr0/RESET_B", "rr1/RESET_B", "rx0/RESET_B", "rx1/RESET_B"])]
        observations.append(dict(label=label, expectation="valid narrow scope", **result))
    for label, mutation in negative.items():
        result = graph_probe(work, model, physical["sdc"], label, mutation)
        assert result["code"] == 1 and result["attempts"] == 0 and result["map_code"] == result["traces_code"] == 1, (label, result)
        assert not any(event["event"] in ("validated", "applied", "complete") for event in result["events"])
        observations.append(dict(label=label, expectation="reject before applying", **result))
    for reject in (1, 2):
        label = f"application-failure-{reject}"
        result = graph_probe(work, model, physical["sdc"], label, reject_application=reject)
        assert result["code"] == 1 and result["attempts"] == reject and result["successes"] == reject - 1
        assert result["map_code"] == result["traces_code"] == 1
        assert not any(event["event"] == "complete" for event in result["events"])
        observations.append(dict(label=label, expectation="failed application, no checked map", **result))
    result = graph_probe(work, model, physical["sdc"], "failed-reload-invalidates-map", repeated=True)
    assert result["code"] == 1 and result["attempts"] == 0 and result["map_code"] == result["traces_code"] == 1
    observations.append(dict(label="failed-reload-invalidates-map", **result))
    for label, mutation in (("old-synth-rejects-interstage-buffer", "chain old hc_pt7_rx0 rx1/D 1"),
                            ("old-synth-rejects-delay", "chain old ndata rx0/D 1 sg13cmos5l_dlygate4sd1_1"),
                            ("old-synth-rejects-moved-anchor", positive["moved-anchor-eight"])):
        result = graph_probe(work, model, plain["sdc"], label, mutation)
        assert result["code"] == 1 and result["attempts"] == 0
        observations.append(dict(label=label, expectation="old policy unchanged", **result))
    api = {}
    for variant in ("empty", "same_q", "reserved_anchor", "wrong_architectural_predecessor", "partial"):
        result = json.loads(call([emitter, "emit", variant, asic]))
        api[variant] = result
        if variant == "partial":
            assert result["physical"]["status"] == "emitted"
            rejection = graph_probe(work, model, result["physical"]["sdc"], "partial-declaration-inventory")
            assert rejection["code"] == 1 and rejection["attempts"] == 0 and "inventory" in rejection["message"]
            observations.append(dict(label="partial-declaration-inventory", **rejection))
        elif variant == "empty":
            assert result["physical"]["status"] == "rejected"
        else:
            assert result["status"] == "rejected", (variant, result)
    libraries = inspect_libraries(pdk, supported)
    assert {str(path): digest(path) for path in owned} == before
    report = dict(verdict="no blockers found in bounded source/API-model/collateral review", directory=str(work),
        source_sha256=before, graph_observations=observations, api_controls=api,
        emission_identity_checks="default=false, physical distinct, marker/SDC identity mutations reject, unchanged RTL/native producer",
        legacy_helper_sha256=hashlib.sha256(legacy.encode()).hexdigest(), liberty=libraries,
        scope="No EDA or native qualification; C's198 controls and current full execution are separate evidence")
    (work / "results.json").write_text(json.dumps(report, indent=2))
    print(json.dumps(dict(directory=str(work), graph_observations=len(observations), positives=len(positive), topology_negatives=len(negative),
        libraries=[dict(corner=row["corner"], sha256=row["sha256"]) for row in libraries], verdict=report["verdict"]), indent=2))


if __name__ == "__main__":
    main()
