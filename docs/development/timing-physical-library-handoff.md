# Physical timing library handoff (A → B/C)

2026-10-29. Implementation contract, published before implementation. Native
qualification is pending C; API-model tests are not physical acceptance.

## Explicit opt-in and identity

Public API: `Elaboration.Bundle.render ?timing_physical_qualification:bool`
(default `false`), with all existing arguments unchanged. C passes `true` for
qualification synthesis and Hardening bundles. This does not change every Hardening
bundle or add a field to `Timing.t`. Admission requires nonempty timing stages,
no macros, and every architectural register declared as a timing stage. The latter
is checked natively by exact `all_registers -cells` inventory, not inferred from
the five-stage example. Architectural elaboration remains unchanged/direct.

Opt-in manifest `timing_intent.resolution_policy` is
`scalar-q-driver-cmos5l-physical-v2`; schema remains 1 (intent, not audit).
Stage preservation remains truthful `yosys_keep_1`, not physical dont-touch.
Additional identity-covered top-level member:

```json
{"timing_physical_qualification":{
  "schema_version":1,
  "resolution_policy":"scalar-q-driver-cmos5l-physical-v2",
  "analysis_corners":"all_configured",
  "analysis_stages":["synthesized_netlist","post_pnr"],
  "sequential_inventory":"exact_declared_stages",
  "max_buffer_hops":8,
  "endpoint_map":"::hc_pt7::checked_endpoints",
  "trace_inventory":"::hc_pt7::checked_traces"
}}
```

B consumes this explicit marker for all-configured synthesis + coarse full
qualification. Do not infer all-corner execution from a configured list. Native
coverage producer/profile stays `opensta-2.7-native-state-v2`; B versions physical
audit/companion provenance separately. Default marker absence, SDC and intent
remain v1. B owns readers accepting the new policy and top-level member.

## Checked Tcl seam (v2 only)

After successful generated SDC completion:

* `::hc_pt7::checked_endpoints` returns a dict keyed by stage ID. Each value is a
  dict with native objects `cell q data clock reset`, literal strings `anchor
  master chain`, and integer `index`. B queries witnesses via `dict get`, never
  by re-resolving immediate anchor drivers. Reset object is present for supported
  mapped masters; exception eligibility still follows declaration `has_async`.
* `::hc_pt7::checked_traces` returns ordered dict records with `label root sink
  nets hops`; root/sink/nets are full-name strings. Each hop has `cell master
  input output` full names (master is its exact reference name). Nets/hops run
  backwards from sink toward root. Direct paths have zero hops.
* Both accessors error before full resolution/application succeeds. Maps reset
  on each run; failed/repeated reads cannot expose stale checked data.
* Resolution events use `HC_ASIC_TIMING_V1` schema1 as before, with v2-only
  `trace` events carrying those records and `inventory` carrying exact sorted
  stage-cell names. B must admit these only under v2. Existing stage/resolved/
  applied events retain their fields. No exceptions apply before all topology,
  sources, inventory and endpoints validate. Application failure leaves maps
  unavailable (native commands are not transactional).

V2 accepts exact direct Q anchors or moved anchor nets reached through <=8
qualified noninverting hops backwards to one exact supported Q. Interstage D
traces terminate at the resolved predecessor Q; clock/capture/reset traces at
the exact declared input port internal net. Every net checks driver and top-input
contention, including the root. Cycles, wrong pins, inversion, constants, unknown
masters, disconnected nets, merged stages, extra sequential cells and depth>8
reject. Exceptions remain source→first D and source→enumerated RESET_B only.

## Qualified collateral table and native requirements

Buffers: exact `sg13cmos5l_buf_{1,2,4,8,16}`, A→X, function A.
Delay candidates: exact `sg13cmos5l_dlygate4sd{1,2,3}_1`; A verifies actual
Liberty pins/functions and fast/typical/slow presence before enabling them.
Flops remain exact `sg13cmos5l_dfrbp{,q}_{1,2}`, Q/D/CLK/RESET_B.
No guessed prefix matching or blanket net/instance dont-touch.

C must probe real standalone STA and ODB-backed OpenROAD using the **emitted**
SDC: `sta::get_port_pin` / top Pin.term / Term.net, `all_registers -cells`, exact
name queries, moved anchors, buffers/delay gates on all source and interstage
roles, supported sizing, root contention and unknown/inverted transforms.
Retain passing baselines beside intended negatives; check zero exceptions on
late resolution failure. Exercise both zero and eight hops and reject nine.
Verify map queried witnesses actually contain downstream min/max paths, and
full sequential inventory remains exactly the five original flops after native
repair. Preserve uncertainty .25ns, transition .15ns and .95/1.05 derates.

B's counterpart is `timing-physical-flow-handoff.md`; any incompatibility should
be resolved against this explicit opt-in/map contract before C launches EDA.

## Implemented A slice and coordination

A has read B's initial flow handoff. Its requested explicit marker/map matches
the contract above; no execution/readers are changed by A. In particular B must
accept v2-only trace/inventory events (trace events precede each stage event),
and use `checked_endpoints` after successful SDC execution. B's all-configured
synthesis audits may retain audit2 while admitting physical-v2 intent; native
coverage producer/profile2 is unchanged. Physical outer provenance belongs to B.

Implementation is in `timing_tcl.ml`, `timing_intent.{ml,mli}` and
`bundle.{ml,mli}`; no Resolved or architectural Timing changes were needed.
Explicit false/default Hardening render identically and lack the new marker.

Real collateral inspection completed (no EDA): exact A input / X output,
function `"A"`, no ff/latch/statetable and A-related output timing arcs for all
five buffers and all three delay gates, at each of:

| Standard-cell Liberty corner | SHA256 |
| --- | --- |
| fast_1p32V_m40C | af12d75a72d19648fa690027d29843fbae550aa91f4e40dd3339c7116d6e425d |
| typ_1p20V_25C | 34163f3e7de9f854afac57332ba06f1739b78e7ac35660a8a5ddd39c570124ad |
| slow_1p08V_125C | 3ee222c580ba33acb2131ac2bf224ff8ee9700751835b73aaec72b670bb31d3c |

Reproduce read-only inspection:

```sh
python3 -B test/timing_physical/check_collateral.py "$PDK_ROOT/ihp-sg13cmos5l"
```

`test/timing_physical/native_probe.tcl` is supplied for C, **not executed by A**.
After loading an exact native design and libraries in a fresh process, set
`hc_physical_sdc` to the emitted SDC and `hc_physical_output` to a fresh existing
directory, then source that script. It reads the emitted SDC, exercises the
checked-map seam, retains endpoint/trace Tcl lists and native serialized SDC,
and reports each interstage min/max path through the map. Run in both STA and
ODB-backed OpenROAD. C must verify nonempty native paths, actual object API
behavior, effects/negative diagnostics and full process success; the script's
completion marker is not qualification. C supplies native buffering/repair
controls on disposable copies and never patches emitted SDC.

A's focused tests: explicit identity opt-in, old policy/default bytes, unchanged
native metadata; zero/eight-hop paths, moved anchors, delay gates on each role,
supported flop sizing, root contention, wrong predecessor/input/reset/clock,
inversion/unqualified cells/wrong pins, cycle/depth, missing/extra/duplicate
sequential inventory, zero exceptions on late failure, unavailable maps after
application failure and stale-map invalidation. Native object and repair behavior
remain pending C; no placement/CTS/routed/closure claim is made by these tests.

### Signatures and verification result

`Timing_intent.{to_json,sdc}` take optional `?physical:bool` (default false).
`Timing_tcl.render ~stages ~exceptions` retains its original signature and bytes;
the new explicit low-level entry is `Timing_tcl.render_physical ~stages
~exceptions`. Historical serializer replay callers must keep using `render`.
No change to `Timing_coverage_tcl.manifest/render` was necessary.

Completed, switch `5.2.0+ox`, lock and allocation enforced:

```sh
flock /tmp/opencode/asic-pt7-build.lock opam exec --switch=5.2.0+ox -- \
  dune runtest -j6 test/timing_physical test/timing_intent \
  test/timing_intent_evidence test/timing_native_coverage
```

Passed: v2 19 positive/25 resolve-before-apply negatives, supplied native-probe
map integration under the Tcl API model, explicit bundle identity/opt-in and
stale-map/application-failure controls; historical intent 34 library negatives
and 8 positive/41 Tcl negatives; 54 evidence checks, 154 native-coverage pure
checks, 27 independent evidence-reader regression cases. The real Liberty
inspection above also passed. No EDA was run by A.

Remaining C blockers before native qualification: demonstrate actual ODB and
standalone object conversion/complete sequential inventory; native moved-anchor
and delay/buffer traces with exact loaded Liberty association at all three
corners; nonempty timed downstream min/max witnesses; paired graph/effect
negatives with zero exceptions on late failure; real repair/sizing inventories.
B remains responsible for physical admission, reader/version/event acceptance,
all-corner execution, exact extracted-State/SPEF linkage and closure/postchecks.
