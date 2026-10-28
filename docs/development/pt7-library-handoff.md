# PT.7 slice A — library integration contract

2026-10-28. Published before implementation for B/C. This is the concrete target
contract; implementation/check status is recorded at the bottom as work proceeds.

## OCaml consumer API

All names below are under `Hardcaml_asic.Timing` (also `Platform.Timing`).

```ocaml
Port.input : string -> Port.t
Port.output : string -> Port.t
Port.bit : Port.t -> int -> Port.t
Stage.create : id:string -> chain:string -> index:int -> Stage.t
Exception.async_capture : id:string -> reason:string -> source:Port.t
  -> first_stage:Stage.t -> Exception.t
Exception.async_reset : id:string -> reason:string -> source:Port.t
  -> targets:Stage.t list -> Exception.t
create : ?input_delays:Delay.t list -> ?output_delays:Delay.t list
  -> ?stages:Stage.t list -> ?exceptions:Exception.t list -> unit -> t
```

Declare every scalar stage in `Timing.create ~stages`, including downstream
stages. Indices per chain must be contiguous from zero with at least two stages.
IDs/chains are restricted ASCII identifiers `[A-Za-z_][A-Za-z0-9_]*`. Ports are
literal top-level names; a bus source needs `Port.bit`. Exceptions require unique
IDs and nonblank reasons. `async_capture` always addresses the data pin of index
zero; `async_reset` explicitly enumerates asynchronous control pins, including
later stages where the circuit actually resets those stages asynchronously.

Inside `Design.create context inputs`, construct the same ordinary scalar
Hardcaml registers and register each immediately:

```ocaml
Elaboration.Context.register_timing_stage_exn context ~stage ~q
```

Registration accepts scalar registers only, adds a reserved Q name
`hc_pt7_<stage-id>` and Yosys `keep=1` RTL attribute. It does not create registers,
change clock/reset/data behavior, or promise placement/MTBF. Do not add a competing
reserved name. Keep stage Q values internal, not directly exported as port objects.
Simple downstream stages must take the previous scalar Q directly as data (wire
aliases are accepted); enable/clear logic is outside this first supported subset.
All stages use the declared primary clock. Reset-to-zero controls must be
externally active-low: a direct input with low-level reset, or its inversion with
high-level reset. Other declaration polarities are explicitly unsupported. The
backend verifies noninverting mapped connectivity to the active-low RESET_B pin.
Preservation is requested intent until real tools prove it.

`Timing.empty` remains available. Existing two-field timing record literals must
migrate to `Timing.create ~input_delays ~output_delays ()` (or record-update
`Timing.empty`); Delay.t is unchanged.

## Identity-covered bundle wire

New nonempty stage/exception declarations add manifest key `timing_intent`:

```json
{"contract":"hardcaml-asic.timing-intent","schema_version":1,
 "resolution_policy":"scalar-q-driver-cmos5l-v1",
 "stages":[{"id":"rx0","chain":"rx","index":0,
             "anchor":"hc_pt7_rx0","preservation":"yosys_keep_1"}],
 "exceptions":[{"id":"rx_capture","kind":"async_capture","reason":"...",
   "source":{"direction":"input","port":"ui_in","bit":0},
   "targets":["rx0"]}],
 "sdc":"constraints/top.sdc"}
```

Scalar source `bit` is null. `async_reset` has the same shape with kind
`async_reset` and the explicitly enumerated target IDs. Stages and exceptions sort
by ID, reset targets sort by ID. Anchor is actual legalized emitted RTL name.
The manifest object and SDC bytes are bundle-identity-covered. They are declaration
facts, never proof of mapped resolution or exception effect. Legacy bundles omit
the key. No bundle/execution schema bump is required for this optional object.

## Strict Tcl and audit wire (frozen schema 1)

SDC contains its own `::hc_pt7` helpers. It resolves exact input ports, exact Q nets,
unique sequential Q drivers, and only checked mapped pin roles. No wildcard or
empty/ambiguous fallback. All stages/endpoints resolve and distinct stage cells
are verified before any `set_false_path` is called. Data scope is `-from source
-to first-stage/D`; reset scope is `-from source -to enumerated-control`.

Supported initial cell roles (confirmed in provisioned CMOS5L typical Liberty;
C must exercise actual mapping): `sg13cmos5l_dfrbpq_1`, `_2`, and
`sg13cmos5l_dfrbp_1`, `_2`: Q/Q, data/D, clock/CLK, async/RESET_B.
Only their noninverting Q output is accepted. Latches, scan flops, inverted Q,
dual-control cells and unknown masters fail. There is no plain DFF or dedicated
set-only cell in this library inventory: do not rely on the initially anticipated
`dffq`/`dfsbpq` names. For a reset specimen use reset-to-zero scalar stages (the
consumer chooses that architecture); all asserted controls in this first mapping
are active-low RESET_B. An unused RESET_B on a data-only stage is not excepted.

Every audit line is `HC_ASIC_TIMING_V1\t` followed by one JSON object. Common
fields: `schema_version:1`, `event`. Events in order:

1. `stage`: `id`, `anchor`, `cell`, `master`, `q_pin`, `data_pin`,
   `async_pin` (null when no asynchronous control was declared). Resolution fact,
   not application.
2. `resolved`: `id`, `kind`, `source` (exact tool port name), `targets`
   (exact full mapped pin names, sorted declaration order).
3. `validated`: `stage_count`, `exception_count`. All endpoints checked; no
   exception applied yet.
4. `applied`: `id`, `kind`, `source`, `targets`, emitted only after the
   corresponding `set_false_path` returns successfully.
5. `complete`: `stage_count`, `exception_count`.

On error Tcl raises and there is no `complete`; partial application is possible
only if the tool itself rejects a later `set_false_path`, never from unresolved
declarations. A/C must retain the entire raw log and process result. B must reject
truncated/reordered/duplicate/inconsistent records. Repeated SDC loads are separate
blocks, delimited by `begin` event (fields `stage_count`, `exception_count`) before
event 1 and `complete` after event 5. Do not merge records across loads/corners.

The audit contains no authenticated producer/build/corner identity: B/C bind it to
the exact tool invocation, bundle/SDC, netlist and libraries using their evidence
receipts. `applied` means only that the command returned, not native path-effect or
coverage proof. Native exception/coverage and downstream min/max reports remain
separate evidence. No EDA is run by A.

## Integration status

### Latest: A-REAL-2 / anchor-output R4 code fix ready; native acceptance REQUIRED

**C must recapture and rerun native acceptance. This is not fixture-only closure.**
The previous captured renderer failed native OpenSTA 2.7.0 and OpenROAD source
resolution because a top Pin's `.net` is the external side and NULL. C retained
the failing attempts and showed the actual connected internal Net on its Term;
see example `docs/pt7_timing_findings.md` A-REAL-2. No emitted SDC has been patched
to manufacture a positive.

The corrected single `port_net` helper now checks Port -> scalar top Pin,
matching full name, exactly one non-NULL Term, then exactly one non-NULL
`Term.net`. **Both** input-root caching and clock/data/reset source tracing use
this helper. There is no external Pin.net query, name-based net guess, NULL-root
omission or fallback. Invalid/empty/multiple Terms or internal Nets fail before
application. The Q-anchor loop now calls the same `outputs` filter as source
tracing, so top-level output sink Pins are excluded there too (review R4).

No OCaml API, manifest or audit-event schema changes. B's shared serializer replay
uses the new complete Tcl automatically. C must use a fresh captured provider,
freshly emitted complete SDC/manifest/new bundle identity and new native audit
attempts; do not reuse the failed bit-bundle's identity or rewrite its SDC. Native
clock/data/reset mutation negatives must fail on their intended graph change,
not a common source conversion failure. Confirm downstream min/max evidence and
retain all previous failed attempts. No native run was launched by A.

Focused verification (switch `5.2.0+ox`, shared build lock, explicit `-j6`):

```sh
flock /tmp/opencode/asic-pt7-build.lock opam exec --switch=5.2.0+ox -- \
  dune build -j6 @test/timing_intent/runtest
```

Passed: **34 library negatives**, **eight mapped-Tcl positives**, **41
resolve-before-apply negatives**, application-failure, JSON/literal-name checks.
The fixture now faithfully gives a top Pin external Net = NULL and a separate
Term with a connected internal Net. Explicit controls demonstrate that distinction
and assert **zero production external-net queries** in every case. New negatives
cover missing/wrong top Pin, NULL/empty/multiple Term and NULL/empty/multiple
internal Net; a new Q-net top-output tap is a positive alongside the existing
source-net output tap. Existing wrong-clock/capture/reset graph regressions still
reject with their intended diagnostics and zero exception calls. No broad ASIC
suite, B implementation/tests, example/provider selection, Workbench/Protemu or
Git state was changed by A in this correction.

**Exact final A source hashes for this recapture (SHA-256):**

```text
9c53a5b75313adacd979ea5b559fd17ad0c51d2961c4df6dc0a41813a88d25d2  lib/elaboration/timing_tcl.ml
514f4e47c8723fe770a098fa1996a5cfab928d7f917f535d1ae1ad806eded6bc  lib/elaboration/timing_intent.ml
b2c361c20dfafbf11bef83956be2e017597449bfdde6c1d5d05bb3e6decf9f13  test/timing_intent/fixtures.tcl
bc8974e4d05d3770cdaf4ec27550c654e12d930b95a3ae1da088b0fc7212ac4b  test/timing_intent/check.py
```

### Prior R1/R2/R3 correction round — native source assumption superseded above

**Ready for B/C recapture. No audit event or manifest schema changed.** B's shared
renderer replay picks up the changed Tcl bytes without new event parsing. New
SDC bytes produce a new bundle identity; do not reuse an old preview, provider
capture or failed audit. The old independent Tcl diagnostic alias intentionally
asserted the original defects and is a historical reproducer, not a current
regression acceptance alias; it was not edited by A.

Literal lookup now passes a safely serialized pattern-list to the native query,
filters every candidate by literal `get_full_name` equality, then requires exactly
one exact object. Brackets are not Tcl-glob-escaped. Native wildcards can select
neighbors, but cannot become endpoint matches; duplicate exact objects fail.
This addresses R3 / C's native-confirmed A-REAL-1 at the implementation/fixture
level. **Actual corrected OpenSTA 2.7.0 acceptance remains C's pending run.**

Mapped validation now checks every stage CLK, first-stage exception D and every
enumerated RESET_B against the exact input source before `validated` or any
application. Direct wiring or at most eight noninverting
`sg13cmos5l_buf_{1,2,4,8,16}` cells (A input / X output) are supported. The declared
primary `clk` must reach rising-edge mapped CLK without inversion/gating. Reset
must reach active-low RESET_B without inversion. Unknown logic, constants,
disconnected or ambiguous drivers, cycles, wrong inputs, wrong buffer roles,
inversion and excessive buffer depth fail clearly. Interstage Q-to-D remains
direct-only. The trace checks source/target connectivity, not native path-effect
coverage. It does not insert or alter hardware.

OpenSTA's `get_ports` returns a Port object, whereas `get_nets -of_objects`
accepts Pin objects. The renderer explicitly uses the native
`::sta::get_port_pin` adapter (now followed by checked Term.net conversion above)
before querying a port's connected internal net; no net-name
guessing or failure fallback. Object fixtures now distinguish Port from Pin and
reject the previously tempting unsupported direct query. Top-level output sink
pins are excluded from internal output-driver counts by their checked TT full
names, so a legal output tap does not create a false multidriver diagnosis.

The native API choices were source-inspected in upstream OpenSTA `sdc/Sdc.tcl`
and `tcl/CmdArgs.tcl`; this source inspection is not a receipt for C's pinned
binary. C must verify `sta::get_port_pin` and the source traces on that binary
while reading the unmodified emitted SDC.

To preserve a verifiable polarity contract without new unrecorded producer
facts, the declaration validator now rejects externally active-high reset
exceptions. Both supported elaboration spellings (direct/Low and inverted/High)
are tested. This is an explicit first-subset limitation, not an implicit reset
semantics conversion.

### Correction verification

All Dune calls below used switch `5.2.0+ox`, explicit `-j6`, and
`flock /tmp/opencode/asic-pt7-build.lock`. No EDA, Git mutation, B source/test
changes, example/provider selection changes, Workbench or Protemu changes.

- `dune build -j6 @test/timing_intent/runtest`: **passed**, now 34 library
  negatives plus lifecycle/identity/polarity positives; **seven** mapped-Tcl
  positives, **33** resolve-before-apply negatives, failed application, JSON
  escaping, literal bus/wildcard/question/space names and exact ambiguity rejection.
  Review R1/R2 changed-net connections are now negative regressions; clock
  disconnection/constant/inversion, capture/reset disconnection/inversion,
  constant reset, native NULL nets, unknown transform, multi-driver, cycle, buffer-depth overflow
  and source-input shorting are also covered. Each resolution failure asserts
  zero exception calls and no validated/applied/complete records.
- Existing library inline expect runner and `examples/tt_bundle_example.exe`
  rebuilt; inline runner passed.
- Fresh `test/timing_intent/check.exe -- bundle` in-memory emission passed the
  reason/manifest identity check with the corrected renderer.
- `dune exec -j6 test/timing_intent_review/probe.exe -- tests
  /home/wayne/devel/jane/hardcaml_asic`: **passed** unchanged independent OCaml
  probes: two original-register/alias positives, 11 negatives and three bundle
  identity/scope checks. The independent historical Tcl diagnostics were not
  relabelled as passing regressions.
- An initial new-fixture iteration changed a shared-net D-pin direction, causing
  the stricter Q-driver cardinality check to reject earlier than that test's
  expected message. The test now isolates a wrong RESET_B direction; all final
  regressions pass. No real-tool failure was hidden or patched around.

Prior-round A source receipt (superseded by A-REAL-2 hashes above):

```text
55349fe8b06c11111bdb0027a90b1949b03c732a9baa618a7bbe895220a98902  lib/elaboration/timing_tcl.ml
514f4e47c8723fe770a098fa1996a5cfab928d7f917f535d1ae1ad806eded6bc  lib/elaboration/timing_intent.ml
```

Library API, manifest and Tcl wire are implemented and available to B/C. The
checked intent is exposed as `Resolved_flow.timing_intent :
Elaboration.Timing_intent.t option`; `Timing_intent.to_json` and `Timing_intent.sdc`
are pure read-only renderers. Ordinary `Project.elaborate_for_flow` and
`Bundle.render`/project bundle emission integrate them automatically. Empty legacy
timing declarations produce no manifest extension or extra SDC bytes. Empty
stage/exception lists are also omitted from legacy timing S-expression output.

The scalar registration names are global within one elaboration, even across
scope views: use distinct stage IDs. The context still checks that `in_scope`
views belong to the same elaboration. Registered signals are retained internally
in `Elaborated_project`; registration metadata never claims synthesis happened.

### Completed A verification (no EDA)

All Dune invocations used `opam exec --switch=5.2.0+ox -- dune ... -j6` under
`flock /tmp/opencode/asic-pt7-build.lock`.

- `dune build -j6 lib/hardcaml_asic.cma`: passed.
- `dune build -j6 @test/timing_intent/runtest`: passed; 32 library negatives,
  positive elaboration/lifecycle, four emitted keep attributes and anchors;
  production-emitted Tcl against deterministic object API fixtures: two positive
  mapped-master forms, 12 resolution-before-application negatives, failed second
  application (no complete record), exact bus-bit pattern and JSON escaping.
- `dune build -j6 test/.hardcaml_asic_test.inline-tests/inline-test-runner.exe
  examples/tt_bundle_example.exe`, followed by the locked native inline runner:
  passed existing library expect tests, including clock/delay/protected-setting
  validation and lifecycle tests. No broad execution suite was launched.
- `dune exec -j6 test/timing_intent/check.exe -- bundle
  /home/wayne/devel/jane/hardcaml_asic`: passed real in-memory Bundle.render check;
  changed reason changes bundle identity, and manifest includes timing intent.
  This reads declared sources/Git; it writes no bundle or Git state.

Initial build iterations found installed-API differences (`Char.is_ascii`,
`Rtl_name` exposure, constant extraction) and test-fixture formatting/liveness
mistakes; all were corrected before the passing checks above. No failed EDA or
real mapped retention result is being hidden by those fixture checks.

### C real-tool route and remaining qualification

Use ordinary project declaration/emission and named synthesis flow. Keep each Q
as an explicit scalar `Signal.reg`, register it once, and include downstream
stages in `Timing.create ~stages`. A reset-to-zero release chain can shift a one
through its asynchronously cleared stages; do not use a first-stage D constant
equal to its reset value, which can legitimately collapse to a constant. This is
a consumer architecture choice, not a library-inserted register or reset change.

Retain the exact emitted `constraints/top.sdc`, manifest, RTL, mapped netlist/JSON,
linked CMOS5L Liberty, native producer/version and invocation. Link that netlist
in the selected STA runtime and read the **unmodified** emitted SDC; it is
self-contained. The current supported role table is the four `dfrbp[q]` cells
listed above, not a promise that arbitrary synthesis profiles map to them.
Strict audit deliberately rejects lost/merged anchors, a buffer/inverted output
driving the anchor, unknown masters, and buffer-altered interstage connections.
Preservation across mapping and exact tool-command compatibility still require
C's actual synthesis/STA run. No P&R, analog reliability, exhaustive exception
effect, or unconstrained coverage is qualified by A.

Capture complete native min/max paths from each stage-0 Q to stage-1 D and native
exception/unconstrained diagnostics separately. The `applied` wire event records
command completion only. Follow B's `pt7-evidence-handoff.md` for the standalone
retained-audit receipt and source-role schema; the producer/build/corner binding
is outside this generated Tcl. For negative real-tool cases mutate diagnostic
netlists/audit inputs in a separate evidence attempt, never an emitted published
bundle: missing Q anchor, wrong mapped master/role and changed interstage net must
fail before the first applied record.
