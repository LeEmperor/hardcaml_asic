# PT.7 slice A — independent library review

2026-10-28. Reviewer: slice B agent, **not the implementer of A**. Reviewed actual
library implementation and A's fixtures; added separate diagnostic fixtures under
`test/timing_intent_review/`. No A source/test files were edited. No EDA was run.
Existing dirty/untracked work was preserved. This review does **not** establish
mapped synthesis/STA acceptance; C owns the real-tool run.

## Final re-review status (2026-10-28)

**Latest qualification:** C's actual A-REAL-2 probe disproved the prior independent
fixture's top Pin net model. The previous fixture passes below are not native
closure. A now uses checked Port -> top Pin -> Term -> internal Net, and the
independent model has been corrected to return NULL for every top Pin direct-net
query. Eight positives / 34 pre-application negatives now pass on the corrected
model; native recapture remains pending with C. The prior R4 Q-output-tap rejection
is also fixed in A's current source and is now an independent positive. See the
latest correction section at the end for receipts and limitations.

Original **R1/R2/R3 are closed at corrected-code / independent no-EDA fixture
level**. This does not qualify C's pinned native binary or exception/path effects.
The original review and source receipt below are retained as historical findings;
they no longer describe the corrected implementation's R1/R2/R3 behavior.

Historical **R4 — P2, fail-closed false rejection** (now fixed): prior corrected
`timing_tcl.ml:137-142` still counts top-level output sink pins as Q drivers when
resolving a stage anchor. The new source-trace `outputs` helper filters such
sinks, but this separate anchor loop does not use it. Independent
`top_output_anchor` adds only a top-level `uo_out[0]` sink to `hc_pt7_review0`;
the one actual driver remains `u0/Q`. Actual result: `Q driver for review0:
expected exactly one object, got 2`, zero exception calls. This is not an unsafe
acceptance, but rejects an otherwise valid internal Q with an ordinary output tap
and is inconsistent with the advertised top-output-sink handling. No A source
was edited; fix coordination belongs to A. Its regression currently preserves
and clearly labels this known false rejection, rather than treating it as native
acceptance. Final verification details and broad-suite outcomes are appended below.

## Original verdict (superseded for R1/R2/R3 by re-review above)

**Changes required before accepting strict mapped validation.** The OCaml checks
and identity coverage are materially stronger than the mapped Tcl checks. The
Tcl can emit `validated`, both `applied` records, and `complete` for a mapped graph
whose clock, capture source, or reset source differs from the checked hardware.
There is also a first-subset bus-name compatibility defect in the emitted query
relative to the examined upstream OpenSTA semantics; C must verify its exact
runtime before claiming the bus-bit positive.

Severity: P1 = first-subset correctness/acceptance blocker; P2 = narrower gap.
Findings below do not claim native exception effect: `applied` still means only
successful command return, as correctly stated by A's handoff.

## Findings (ordered by severity)

### R1 — P1: mapped stage clock connectivity is never validated

**Location:** `lib/elaboration/timing_tcl.ml:75-80,85-98,126-132`.

The code resolves `cell/CLK` and checks its direction, assigns it to `clk`, then
never uses it. It neither resolves the primary clock source nor checks that each
mapped stage is clocked by that source with supported edge/polarity. The only
mapped topology check compares predecessor Q net to downstream D net.

**Repro:** independent graph `wrong_clock` changes only `u1/CLK` from `clk_net`
to `ena_net`. All names, masters, Q anchors and interstage data remain valid.
Run the diagnostic alias listed below. Actual output:

```
tcl good RESULT                 0  2
tcl wrong_clock RESULT          0  2
FINDING accepted changed connectivity wrong_clock
```

Here `0` is Tcl catch status and `2` the number of exception commands. Both
`validated` and `complete` are emitted. The fixture records all queries and
confirms there is no `get_nets -of_objects u1/CLK` or equivalent clock-fanin query.
This is a code-level counterexample, not a claim of a real mapped runtime run.

**Impact:** a disconnected, constant, wrong-source, or unsupported transformed
clock is not fail-closed. Correct OCaml rising-primary-clock checks at
`timing_intent.ml:55-57` do not establish that synthesis retained that connection.
Downstream min/max timing can be missing/meaningless for the wrong clock even
though the SDC audit block says all endpoints validated.

**Required fix/test:** before any false path, validate each mapped clock against
the declared primary source and supported polarity/edge. Use a bounded trace for
explicitly supported clock transformations or reject them. Add negative mapped
fixtures for wrong input, constant/disconnected clock and unsupported inversion;
C should exercise a separate changed-netlist negative.

### R2 — P1: capture/reset source-to-target connectivity is not checked after mapping

**Location:** `lib/elaboration/timing_tcl.ml:99-124`, especially `102-115`;
`lib/elaboration/timing_intent.ml:93-100,117-131` for the stronger elaboration check.

The backend confirms the source is one exact input and selects a target by its
known master/pin name. It does not inspect the first stage D net or any targeted
RESET_B net. `has_async` is the elaboration-time Boolean from `Option.is_some
r.register.reset`, not a mapped connection/active-control observation.

**Repros:** independent graph variations:

- `wrong_capture_source`: `u0/D` changes from `async_data` (driven by `ui_in[0]`)
  to unrelated `ena_net`. The source port still exists and is an input.
- `wrong_reset_source`: only `u1/RESET_B` changes from the inverted-reset network
  to unrelated `ena_net`. The declared reset still targets both stages.

Both return `RESULT 0 2`, emit `validated`/`complete`, and apply the same exceptions
as the good graph. The query trace confirms no connection query for `u0/D` or
`u1/RESET_B`. For contrast, changing `u1/D` **does** return `RESULT 1 0` with
`mapped interstage data differs`, and removing the reset pin also returns `1 0`.
Thus these repros isolate missing connectivity checks rather than a mock that
accepts every graph or ignores cardinality.

**Impact:** an optimized-away/rewired capture source or asynchronous control can
be reported as successfully resolved. A reset pin merely existing on the allowed
master does not establish that the declared external reset reaches it with a
supported control polarity. Successful `set_false_path` may have no relevant
path effect; it must not rescue this inconsistent resolution.

**Required fix/test:** validate the mapped first-stage data connection and every
enumerated reset-control connection, including the bounded inversion/polarity
case admitted by the declaration API. Reject constants, unrelated signals and
unsupported logic before the first exception. Preserve the existing narrow D /
RESET_B scopes; do not replace these checks with whole-cell/wildcard exceptions.

### R3 — P1 candidate, native confirmation pending: Tcl-glob escaping differs from OpenSTA

**Location:** `lib/elaboration/timing_tcl.ml:35-45,141-142`;
`test/timing_intent/fixtures.tcl:7-16` and `check.py:68`.

The production `pattern` helper turns the supported bit source `ui_in[0]` into
`ui_in\[0\]`. A's object fixture uses **Tcl `string match`**, where those escapes
are appropriate. That fixture therefore does not verify native OpenSTA query
semantics. Reviewed upstream OpenSTA implementation on 2026-10-28:

- [`sdc/Sdc.tcl`, `get_ports`](https://github.com/The-OpenROAD-Project/OpenSTA/blob/master/sdc/Sdc.tcl)
  preserves backslashes through its `foreach` over patterns.
- [`util/PatternMatch.cc`, `patternMatch` / `patternWildcards`](https://github.com/The-OpenROAD-Project/OpenSTA/blob/master/util/PatternMatch.cc)
  recognizes `*` and `?`; it does not implement Tcl bracket classes or remove
  backslash escapes from an exact pattern.
- [`network/ParseBus.cc`, `parseBusName`](https://github.com/The-OpenROAD-Project/OpenSTA/blob/master/network/ParseBus.cc)
  explicitly treats an escaped final bracket as **not a bus**.
- [`network/Network.cc`, `findPortsMatching`](https://github.com/The-OpenROAD-Project/OpenSTA/blob/master/network/Network.cc)
  uses that bus parser and the native matcher.
- [`network/SdcNetwork.cc`, `findPortsMatching` / `escapeBrackets`](https://github.com/The-OpenROAD-Project/OpenSTA/blob/master/network/SdcNetwork.cc)
  retries escaped names but does not turn an already bracket-escaped name back
  into the ordinary declared bus-bit name; `escapeChars` preserves prior escapes.

**No-EDA repro:** the independent `sta_literal` mode executes the actual emitted
Tcl against the native exact-pattern branch (no wildcard in this query), rather
than Tcl's matcher. The ordinary `ui_in[0]` object is present:

```
sta_literal good RESULT  1  0  ... get_ports ui_in[0]: expected exactly one object, got 0
```

The same graph with the Tcl matcher completes and applies both exceptions. This
is a **source-semantics/model repro**, not a test of C's pinned binary. OpenSTA's
bus/name adapter has version-specific details; these unpinned upstream sources
are supporting evidence, not a receipt for the provisioned runtime.

**Required C check:** in its already allocated native run, compare unmodified
emitted query resolution with literal bus resolution, without rewriting the
published SDC to manufacture a positive:

```tcl
get_ports -quiet {ui_in[0]}
get_ports -quiet [::hc_pt7::pattern {ui_in[0]}]
```

Retain both exact arguments/results and the native producer version. Fix library
query serialization for the qualified native API, preserving exact cardinality
and full-name equality. Use the native implementation/semantics in non-EDA
fixtures; keep Tcl-injection/JSON escaping tests separately. This failure is
fail-closed (no exception applied), but blocks the advertised exact-bit subset.

## Reviewed invariants that held

### Registration and elaboration hardware checks

Read `context.ml`, `elaborated_project.ml`, `project.ml`, `resolved.ml`,
`timing_intent.ml`, and their new signatures, not just the test labels.

- `register_timing_stage_exn` checks actual scalar Reg Q, rejects duplicate ID/Q
  across shared scope views and conflicting reserved-name / keep ownership, adds
  only name/attribute metadata, and poisons the context on a swallowed error.
  `check_open` remains outside the exception handler, preserving closed-state
  behavior. Metadata is carried from finalized context into the elaborated project.
- Resolution checks declared/registered inventory, graph membership, rising
  primary clock by UID after wire unwrapping, absence of enable/clear, surviving
  keep=1 and unmangled reserved Q anchors against Hardcaml's RTL name assignment.
- Chain indices must be contiguous from zero and have at least two stages. The
  actual downstream D must equal preceding Q after wire unwrapping.
- Exception sources are actual nonclock inputs with correct scalar/bit width.
  Capture is exactly one index-zero stage and must match actual D. Reset targets
  must have real asynchronous reset, constant reset-to-zero, and control matching
  the source or its direct inversion. Duplicate IDs, targets and overlapping
  kind/target scope are rejected. These are declaration/elaboration facts only.

Independent ordinary-project probes accepted `good` and `alias` (wire aliases on
clock and interstage data), each with exactly **two original registers** and
unchanged Q UIDs at registration. They rejected 11 cases: wrong clock, falling
clock edge, wrong reset source, wrong capture bit, wrong interstage data, detached
registered Q, swallowed duplicate-Q error, swallowed duplicate-ID error through a
child scope view, preexisting keep, preexisting reserved name, and colliding anchor.
No new hardware insertion, latency change, or broad reset waiver was observed.

### Tcl naming, ordering, unsupported behavior and downstream scope

- Literal Tcl word serialization escapes command/variable substitutions; generated
  code does not eval declaration text. Full-name equality and exact-one checks
  stop nonexact/multiple query results. This is useful despite R3's matcher gap.
- Allowed mapped master table is bounded to the four documented CMOS5L resettable
  flop names. Q must be noninverting Q, directions must agree, and stage cells must
  be distinct. Missing/unsupported/inverted/buffer anchors fail before application.
  The table relies on the qualified technology's cell semantics; it does not
  independently validate arbitrary Liberty function definitions.
- All stage and exception resolution, including interstage topology, precedes the
  first `set_false_path`. A tool rejection during a later command can leave a
  partial application, but no `complete`; A documents this correctly.
- The good independent trace selects exactly `u0/D` for capture and exactly
  `u0/RESET_B`, `u1/RESET_B` for reset. It does not cut from `u0/Q`, through a whole
  register, or to `u1/D`. This structurally preserves the intended downstream data
  timing scope. Actual setup/hold path presence/effect remains C's native check,
  especially given R1. Sampled min/max reports are not exhaustive coverage.

### Bundle and identity coverage

`Resolved.resolve` invokes timing-intent validation after clock/I/O validation;
`Bundle.sdc` appends the renderer from that same resolved value.
`Bundle.render` includes `timing_intent` in the payload and the generated SDC in
the hashed files inventory. Empty intent has no new manifest/SDC extension.

Independent in-memory `Bundle.render` probes verified:

1. Changing only exception reason changes bundle identity while leaving SDC equal.
2. Changing the enumerated reset scope changes both SDC and bundle identity.
3. Replacing manifest timing intent without updating identity is rejected by
   `Bundle.verify_manifest_identity`.

No identity-coverage defect was found. This checks retained declaration identity,
not compiled-source authenticity or proof of synthesis/tool application. The
manifest's public identity verifier is not a strict timing-intent schema decoder;
B's evidence reader separately validates that wire schema.

## Executed checks and reproducible commands

All Dune calls used switch `5.2.0+ox`, explicit `-j6`, shared ASIC lock. No EDA,
provider/config changes, Git mutations, or edits to A-owned files.

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/timing_intent_review test/timing_intent

opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune exec -j6 test/timing_intent_review/probe.exe -- tests \
  /home/wayne/devel/jane/hardcaml_asic
```

- A suite passed: 32 library negatives; two Tcl positives, 12 resolve-before-apply
  negatives, application-failure and escaping checks. Those results do not cover
  the independent counterexamples above.
- Independent Tcl diagnostics executed seven graph/matcher combinations: good,
  three accepted bad-connection graphs, two rejected structural negatives, and
  the rejected native-literal-pattern model. The diagnostic alias returns zero
  when it successfully reproduces these observations; **zero is not review pass**.
- Independent OCaml command passed two positives, 11 negatives, original register
  inventory/UID assertions, and the three bundle identity/scope assertions.
- `git diff --check` passed; final rehash of `timing_intent.ml` and `timing_tcl.ml`
  still matched the reviewed source receipt below.
- These are synthetic object fixtures, not mapped evidence. Real native query
  compatibility, post-map preservation, min/max path effects and native coverage
  are not qualified by this review.

## Reviewed source receipt (SHA-256)

Mutable worktree snapshot, not Git commit identity. Subsequent A changes require
re-review/retest of the affected findings.

```
0750fa731d12d5e73796b79c9dc10e373e32ba1adb4801d39efd7f6f3b4d898d  lib/platform/timing.ml
4e724b485123ba12f536cabd4b87ae61d75186a760d470b3cd4c2380ebf76ce2  lib/platform/timing.mli
b2fcaeea35b03e2bcb2d0d7b55bc295a31b42940fc6dae0d720c6a64986b088a  lib/elaboration/timing_intent.ml
58e77796b804275a1ecd9deefddc9cb1a6f08690e2572f07a953ec006646258b  lib/elaboration/timing_tcl.ml
a6738335934c8161ac05db00d00284c7461a319723af2d230d4ad1b54adf6722  lib/elaboration/context.ml
46ca9710924bd6771cb3f2cd5e726eca5496a30684509789f34b7f26f431e941  lib/elaboration/elaborated_project.ml
b9792a822c81aacc3007aa96636a7c1b24dbace2fdf9a75b43a01ee638dd67c4  lib/elaboration/resolved.ml
5b79d7ebb5c53b0f7becfdac93d51a9350a2cc83e262dda694cc639aea707f06  lib/elaboration/bundle.ml
d4257483394a3dd5daa273332e36953f3b3a40f174d4ec0ef2442316de0921a1  lib/project.ml
9f92a28d7dd879e15facaa5f7416be6f7e18017834107219337ac8ac686d53bb  test/timing_intent/check.ml
c896ef6e2aa73725ff5ab33e9bd64f3b0ee8a71f11c681ce4b33c3f06910f322  test/timing_intent/fixtures.tcl
494b6d80f2a76bed2221e62fce11f786a2601a810d677f0548ef80f41765f5dc  test/timing_intent/check.py
```

## Corrected-code independent re-review and regression (2026-10-28)

### Closure reasoning from actual implementation

- **R1 closed at library/fixture level:** `trace_input` is called for every mapped
  CLK before stage emission completes. It obtains the declared primary input's
  real top Pin through `::sta::get_port_pin`, requires one non-NULL connected net,
  and traces only supported noninverting buffers to that exact source. Wrong,
  disconnected, constant and inverted clocks reject before `validated` or any
  exception call. The previously accepted wrong-clock graph now rejects with
  `mapped clock for review1: mapped source differs from declared input`.
- **R2 closed at library/fixture level:** first-stage D and each enumerated
  RESET_B now use the same bounded source trace. The previously accepted capture
  and reset counterexamples reject with their respective `mapped ... source
  differs` diagnostics and zero exception calls. Downstream Q-to-D validation
  remains direct-only; inserting even a supported buffer on that connection
  rejects before application. The exception commands remain pin-scoped.
- **R3 closed at library/fixture level:** `exact` passes `[list $name]` to native
  query parsing, then retains only literal full-name matches and requires exactly
  one. It no longer adds Tcl-glob bracket escapes. The independent * / ? matcher
  treats brackets and backslashes literally; the actual emitted bus-bit query
  now succeeds. Literal wildcard, question-mark, space and backslash names,
  wildcard neighbors, and duplicate exact full names are separately checked.
  C's earlier A-REAL-1 native failure and corrected native acceptance are C-owned
  evidence; this review did not run or infer a native acceptance result.

### Buffer traversal / bypass review

Read every branch of corrected `trace_input`, not just A's new tests. Each
intermediate net must have no external-input driver and exactly one internal
output driver. That driver's master must be one of the explicit noninverting
`sg13cmos5l_buf_{1,2,4,8,16}` cells and the actual driver must be its X output;
the A pin must have exactly one non-NULL upstream net. At the declared source net
the external-input list must be exactly the selected source and there must be
no internal output driver. Seen-net detection prevents cycles, and exactly eight
buffer hops are accepted while a ninth rejects. There is no fallback from failed
Port conversion, connectivity, unknown master, or driver ambiguity to acceptance.

Independent cases confirmed correct clock/data/reset buffering and the eight-hop
boundary, and rejected wrong roots, source input shorting, an extra internal
driver on the source itself, multiple intermediate drivers, cycles, inverter /
unknown logic, wrong output role, missing/null/multiple A nets, and nine hops.
**No acceptance bypass was found in those reviewed/probed branches.** This relies
on the qualified CMOS5L allowlist's cell semantics; it is not arbitrary-Liberty
functional verification. Intermediate output taps are supported in the source
trace; the separate anchor-loop R4 false rejection remains open.

### Native-object fidelity and reset polarity

The new independent fixtures use distinct typed handles `Port:...`, `TopPin:...`,
`Pin:...`, `Net:...`, `Cell:...`; a Port and its top Pin share a full name but are
not interchangeable objects. `get_nets -of_objects Port:clk` deliberately errors;
the native adapter accepts a Port and returns a top Pin, and rejects being passed
a Pin. Null/empty adapters are separate pre-application negatives. Net pin
iteration includes top source and output sink Pins. Every graph case checks
these stub controls; successful production traces demonstrate use of the adapter
instead of the unsupported direct Port query.

Supporting upstream source inspection:
[`network/Network.i`](https://github.com/The-OpenROAD-Project/OpenSTA/blob/master/network/Network.i)
shows `find_ports_matching` expands bus/bundle members into scalar Port results,
and `get_port_pin` finds the corresponding top-instance Pin.
[`tcl/CmdArgs.tcl`](https://github.com/The-OpenROAD-Project/OpenSTA/blob/master/tcl/CmdArgs.tcl)
distinguishes those object classes in argument parsing. The fixture's scalar bus
member enumeration models that expansion; it does not pretend aggregate Port
objects are scalar Pins. These are unpinned source references, not a receipt for
C's exact runtime.

Reset limits are coherent for the supported subset: the actual declaration's
reset-to value must be constant zero; direct source with `reset_level=Low` and
inverted source with `reset_level=High` are externally active-low and accepted.
Direct/High and inverted/Low are rejected explicitly as unsupported polarity.
Mapped RESET_B must then trace noninverting to that same external input. This
does not change user hardware or infer a reset-protocol/metastability result.
Independent ordinary-project tests now cover all four polarity combinations.

### Updated owned fixtures and targeted results

`test/timing_intent_review/{objects.tcl,probe.py,probe.ml,dune}` were updated;
no A-owned source/test files were edited. The old diagnostic alias no longer
expects R1/R2/R3 defects. Its `runtest` now runs both independent Tcl regression
and ordinary OCaml project/bundle assertions:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/timing_intent_review test/timing_intent test/timing_intent_evidence
```

**Passed:** seven independent mapped-Tcl positives, 27 pre-application negatives,
native Port/Pin and literal-name controls; three ordinary-project positives,
13 ordinary-project negatives, original register-count/UID assertions and the
three identity/scope assertions. The additional R4 case deliberately reports the
one known fail-closed Q-output-tap false rejection; it is not counted as positive
acceptance. Current A focused suite and B's 54 checks / 13 independent evidence
review regressions also passed (Dune may reuse valid cached successes).

Two initial test-source compile iterations used an unconstrained edge constructor
and then a non-existent `reset_edge` label; the installed Hardcaml API requires
`reset_level`. Those fixture mistakes were fixed before the completed passing
run above. They were not tool/production failures.

### Broad ASIC regression actually run

Selected the broad **no-EDA** named aliases, not the entire root runtest alias:
the latter also offers optional Icarus RTL simulations, and installed-prefix
scripts have separately documented nested `-j20` builds. Those were not launched.
All 42 named root aliases below and six isolated suites completed with **exit 0**
under one explicit six-job Dune invocation, with a 1,200-second tool allowance.
It completed normally; no timeout is being reported as a test pass.

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock dune build -j6 \
  @test/{resource-evidence,resource-physical-evidence,preparation,inspection,ocaml-stage-report,ocaml-coarse-execution,ocaml-archive,ocaml-archive-encoding,ocaml-finalization,ocaml-postcheck,ocaml-report,ocaml-collect,ocaml-coarse-run,ocaml-preflight,stage-domain,ocaml-observation,ocaml-runner,observation-watch,default-journal,related-presentation,inspector-presentation,finalization,result-store,managed-python,flow-cli,flow-packaging,provider-observation,runtime-contract,runtime-observation,execution-transport,ocaml-execution-transport,coarse-runner,stage-checkpoint,flow-observation,ocaml-stage-recipes,execution-identity,execution-plans,backend-protocol,process-supervisor,ocaml-runtime-contract,ocaml-result-store,ocaml-observation-writer} \
  @test/{resource_inspection,resource_timing,timing_analysis,timing_intent,timing_intent_evidence,timing_intent_review}/runtest \
  test/.hardcaml_asic_test.inline-tests/inline-test-runner.exe examples/tt_bundle_example.exe
```

This includes lifecycle/transport/runtime/parity, CLI/packaging, archive,
preflight/run/collection/report, observation and process supervision, resource
evidence/inspection, and timing parser/collector regressions. Notable completed
outputs: identity parity **62,221 accepted / 55 rejected**; recipe contract
**46 / 3,210**; execution plans **168 / 6,737**; resource timing **73 tests, zero
failures**; resource inspection **51 checks**; timing analysis **18 native-grammar
fixture cases**. Native-grammar means retained report parsing, not a new STA run.

The accepted historical finalization fixture
`/tmp/opencode/native-final-integration/finalizations/20261014T040711301534Z_913453bd`
was unavailable and that optional retained-data check was explicitly skipped by
its suite. The `finalize: missing native helper` output is an exercised negative
case, not an unreported suite failure. No genuine retained fixture was invented.

The library's existing inline expect runner was then executed separately, under
the same lock/switch, from `_build/default/test`; it completed with **exit 0**:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  .hardcaml_asic_test.inline-tests/inline-test-runner.exe \
  inline-test-runner hardcaml_asic_test -source-tree-root .
```

`git diff --check` passed. No source, provider/configuration or Git mutation was
performed for A; no EDA was allocated/launched by this reviewer. C's separate
real-tool run, downstream setup/hold paths, native exception effects/coverage,
and exact-runtime API compatibility remain outside these fixture results.

### Final reviewed correction receipt

These digests still matched after the broad run:

```text
55349fe8b06c11111bdb0027a90b1949b03c732a9baa618a7bbe895220a98902  lib/elaboration/timing_tcl.ml
514f4e47c8723fe770a098fa1996a5cfab928d7f917f535d1ae1ad806eded6bc  lib/elaboration/timing_intent.ml
cec4a102050908caf98535b3e5b7043ca72e7098bb15e7ef4b128b81d865145f  test/timing_intent_review/objects.tcl
1cd11ce7569c26e833101daec676cdce2dfb8a67d2bc0c78b2edb8365d7bcb80  test/timing_intent_review/probe.py
388796a94e2c727f2271b83a061d720972c22aa27baad8b811a0051a7cb6811b  test/timing_intent_review/probe.ml
```

## A-REAL-2: native disproof of earlier model, and corrected independent fixtures

2026-10-28. **Earlier fixture-based source conversion qualification is superseded.**
C's actual OpenSTA 2.7.0 and OpenROAD probe found that top `Pin.net` and
`get_nets -of_objects` return NULL on the top-instance external boundary, while
the Pin's Term carries the connected internal Net. The previous independent stub
incorrectly made `get_nets TopPin` return an internal Net. Its successful model
result did not establish real runtime compatibility; C's bit/scalar native
attempts failed before application and remain failed evidence.

Read C's actual `hardcaml_asic_example/timing/probe_port_net.py` and
`docs/pt7_timing_findings.md` A-REAL-2, then read A's published latest correction
handoff and actual `port_net` / input-root cache / anchor-driver code. The new
helper checks matching Port/top-Pin full names, exactly one non-NULL Term, and
exactly one non-NULL internal Term Net. Both the cache and all three source trace
kinds use it. No external-Pin net fallback, guessed net name or dropped failed
root remains in the inspected code. A's anchor loop now uses the same internal
`outputs` filter, closing the earlier R4 Q-output-tap false rejection in source.

Updated **owned independent fixtures only** to implement the observed distinction:

- `Port:*` and `TopPin:*` remain different handles sharing a full name.
- A top Pin is a Tcl object command: `$pin net` returns NULL, `$pin term` returns
  a distinct `Term:*` command, and only `$term net` exposes the internal Net.
- `get_nets -of_objects TopPin:*` returns NULL; direct Port use still errors.
- Every case first checks these controls, clears their query trace, then asserts
  **zero production external top-Pin net queries**, including on failing paths.
- Added wrong-Pin, NULL/empty/multiple Term and NULL/empty/multiple internal-Net
  negatives. These fail before `validated`, application or completion.
- The legal anchor Q output tap is now an eighth positive. Original wrong
  clock/capture/reset cases still fail for their intended connection changes,
  rather than a common conversion error. Buffer and polarity regressions remain.

Focused command completed with exit 0 (shared flock, switch `5.2.0+ox`, `-j6`):

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock dune build -j6 \
  @test/timing_intent_evidence/runtest @test/timing_intent_review/runtest \
  @test/timing_intent/runtest @test/runtime-contract @test/ocaml-runtime-contract
```

Independent review fixtures: **8 Tcl positives / 34 pre-application negatives**,
native Port/Pin/Term/name controls, three ordinary OCaml positives / 13 negatives,
register/identity assertions. B evidence: **54 checks / 27 independent repro
cases** after its R5/R6 fixes. Shared runtime policy corpus: **2,961 accepted /
1,253 rejected**. `git diff --check` passed. No broad suite was repeated for this
bounded correction; the earlier broad result belongs to its earlier receipt.

No A source edits or EDA were made by this reviewer. **A-REAL-2 is not natively
closed by these fixtures**: C must recapture/re-emit and obtain an actual baseline
success before qualifying mutation negatives and downstream path reports. The
new native result is pending, and unsupported coverage remains unavailable.
No new A schema/API changes were required for B's shared serializer replay.

Latest source/model receipt:

```text
9c53a5b75313adacd979ea5b559fd17ad0c51d2961c4df6dc0a41813a88d25d2  lib/elaboration/timing_tcl.ml
514f4e47c8723fe770a098fa1996a5cfab928d7f917f535d1ae1ad806eded6bc  lib/elaboration/timing_intent.ml
ebeac3f0cc619d12ea5c10602b50da23b14edae70b7d068309c205a4871e36a3  test/timing_intent_review/objects.tcl
410d03327fbdf0bc2ea5534263ee4ef8417b57ca38e333b069ca72acd23f7e32  test/timing_intent_review/probe.py
```
