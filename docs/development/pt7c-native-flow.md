# PT.7c — native constraint state and ordinary synthesis evidence

2026-10-28. Written before implementation. The [phase plan](../phase_plan.md)
remains the only active queue. **Bounded native-state/coarse-flow slice accepted**;
see the closeout below. The original plan follows, not a promise of exhaustive
timing-path coverage or physical closure.

## Findings and selected scope

The accepted OpenSTA 2.7.0 has no `report_exceptions`, but provides native
`write_sdc`, `sta::check_timing_cmd` (the engine behind `check_setup`), and
`sta::endpoints`. `report_checks -unconstrained` also reports constrained paths;
it is not an unconstrained-only census. Ranked `find_timing_paths` results cannot
establish exhaustive exception effect. False paths are not graph-edge disables.

Implement two separate coverage dimensions: **native stored exception scope**
compared with requested exact relations, and **complete returned native diagnostic
groups** for seven named check categories, plus native endpoint inventory. Preserve
bounded downstream min/max witnesses and native report bytes. Per-check analysis,
exhaustive exception effects, analog CDC adequacy and timing closure stay unavailable.
Graph/library-arc classification is deferred; it cannot fill those proof gaps.

Integrate a provider-owned linked pre-PNR STA analysis after **ordinary coarse
synthesis** for newly emitted timing-intent bundles. Use the exact completed
synthesis state/netlist, resolved runtime configuration, retained SDC and an
identity-covered producer member. Do not re-elaborate or rerender. Use native
LibreLane `OpenROAD.STAPrePNR` through its Step API, with an extra-corner producer
hook, in a separate analysis directory. Do not run Floorplan, alter the Classic
stage recipe, replace synthesis state/checkpoints or infer post-PNR provenance.
Named execution/checkpoint integration is explicitly a later scope, not implied
by this coarse-run acceptance. Ordinary legacy runs remain unchanged/unavailable.

## Shared interface and exclusive ownership

| Owner | Files | Dependencies / acceptance |
| --- | --- | --- |
| A, native producer + evidence | New `lib/elaboration/timing_coverage_tcl.*`, bundle member emission, `execution/results/timing_native_coverage.*`, existing `timing_intent_evidence.*`, isolated `test/timing_native_coverage/` | Emit/hash producer; strict nonexecuting native-SDC interpretation; exact relation matching; diagnostic groups/endpoint inventory; schema1 compatibility and schema2 extension; meaningful negatives |
| B, ordinary flow + public integration | New provider runtime helper and execution flow-evidence service; coarse-run service, collect/report/archive, CLI routing/capabilities/helper and packaging; isolated `test/timing_intent_flow/` | Exact synthesis-to-analysis association; bounded workers; source replay; failed/missing analysis explicit; read-only report/inspection; archive source closure |
| C, independent example | New example continuation scripts/docs/evidence, minimal timing emitter changes if needed; isolated `.dev/asic-pt7c` and `_build_pt7c` | Fresh coarse synthesis/STA, public report/inspect/archive, native scope/diagnostic negatives and truthful controls; preserve all r3 history |
| Coordinator | This plan, phase queue, guide, interface arbitration and review | Independent cross-review and evidence-based closeout |

A publishes concrete emitter/module signatures and native wire in
`pt7c-native-handoff.md` before implementation integration. B publishes execution,
audit layout and source association in `pt7c-flow-handoff.md`. Both agree schema2
producer/reader seams before writing conflicting consumers. Existing SDC resolution
wire remains schema1; old standalone audit schema1 must retain exact old semantics.
A owns `timing_intent_evidence`; B owns public wrapper/CLI and calls that module.
Root build files belong to B; prefer new isolated test directories. No shared edits.

Required contract semantics:

- New bundle producer `constraints/pt7-native-coverage.tcl` is identity-covered,
  generated from the same resolved intent. Native execution uses retained bytes.
- Audit schema2 adds native SDC, diagnostic/endpoint data and raw check reports.
  Keep existing request/resolution/application facts distinct from native stored
  constraint state. Evidence inspection must never execute retained Tcl.
- Parse only a qualified native `write_sdc` grammar; missing/extra/broad/transition-
  restricted/setup-only/hold-only relations and unsupported masking constructs
  cannot count as an exact match. Preserve complete raw native state.
- Diagnostics preserve all seven named categories, all returned groups/messages/
  details, explicit completion/counts and bounded native endpoint inventory.
  Empty complete groups mean no findings from that native algorithm, not exhaustive
  path coverage. Missing/truncated/exceeded limits never become zero findings.
- Overall exhaustive coverage remains unavailable even when supported dimensions
  match. Violated timing witnesses remain violations; process success is separate.
- Coarse-run companion binds exact run/build, analysis attempt, synthesis producer,
  state/netlist, effective config/delta, actual per-corner producer version/process,
  SDC/producer/libraries/log/reports and runtime/image identity. A hook completion
  marker alone cannot establish completion of the enclosing native step.
- Requested corners are distinct from executed/deduplicated/failed corners.
  A typical-only analysis, if needed, must be explicit, not all-corner evidence.
- Collection/report/archive source replay uses retained sources and explicit
  association, no recency-based directory guessing and no current-source rerender.
  Corrupt advertised evidence rejects; absent historical evidence is unavailable.

## Acceptance sequence

1. Pure emitter/parser tests: deterministic identity, exact scalar/bit scopes,
   native supported grammar, split/merged relation equivalence, missing/extra/broad
   constraints, wrong setup/hold scope, unsupported masking commands; bounded counts,
   all diagnostics preserved, no English-message inference of coverage.
2. Runtime/service tests: exact synthesis inputs, retained producer, explicit worker
   limits, completed hook followed by failed process, absent/unexecuted corners,
   cancellation/timeout/publication as applicable; no ordinary recipe changes.
3. Fresh real coarse synthesis plus linked STA of an example specimen. No P&R.
   Verify five stages, exact native stored relations, native diagnostic categories,
   downstream timing including negative hold, tool/corner/input provenance, public
   collect/report/inspection and retained-source archive/restore.
4. Native diagnostic counterfactuals with positive baseline: remove/broaden exceptions,
   setup-only relation, add masking constraint; omit input/output delays or clock;
   compare exact external capture witnesses with/without its exception. These are
   diagnostic attempts, never edits to immutable emitted bundles. Claim only observed
   witness suppression, not exhaustive effect. Unsupported reset-effect checks stay
   explicit. Native structured output is cross-checked against raw reports.
5. Independent cross-review after passing suites, fix/retest findings, appropriate
   regression and truthful docs. Keep all original failures and identities.

## Resource and preservation policy

No Git mutations/publication, Protemu/Workbench changes, old provider/configuration/
daemon changes or historical-evidence edits. Initial ASIC status clean; example
has untracked `_build_pt7` and prior acceptance directories. Preserve them.
A/B/C allocations at most six concurrent jobs each, two reserved (20 global).
Every Dune command explicit `-j6` or lower, switch `5.2.0+ox`, shared checkout
locks `/tmp/opencode/asic-pt7-build.lock` and
`/tmp/opencode/example-pt7-build.lock`, including separate build directories.
C's bounded synthesis/STA shares its six-job allocation, with explicit container/
worker limits and STA serialized (one thread). P&R allocation is zero.

## Implementation and acceptance closeout

Implemented and independently reviewed 2026-10-28. Exact contracts:
[native producer/reader](pt7c-native-handoff.md),
[coarse execution/source association](pt7c-flow-handoff.md).
The [operating guide](../guides/timing-intent.md) describes public commands,
compatibility, supported dimensions and exit meanings.

### Delivered boundary

New bundles identity-cover the native producer. Macro-free ordinary coarse
synthesis automatically launches a separate, single-threaded genuine LibreLane
STAPrePNR Step with the exact synthesis state, resolved configuration and retained
SDC/producer. The linked analysis explicitly selects only the default corner.
Collection, report, explicit coarse inspection and archive validate/replay the
same retained source closure, including actual loaded library associations,
helper/driver/hook pointers, native process results and transport cleanup truth.
No stage recipe, named checkpoint or physical implementation was substituted.

Native profile2 (outer audit schema2) exposes exact stored exception relations,
verified native design, complete returned groups for seven named diagnostics, and
native endpoint inventory. Structured diagnostic categories are bound to framed
raw native reports. Parsing is bounded, nonexecuting and LF-only. Missing,
extra, broad, restricted, masked or unsupported native state rejects. Source
replay does not rerender a schema2 design/producer or read current PDK inputs.

Overall coverage stays unavailable: stored scope does not prove every exception
effect; native diagnostics are not a complete per-check path census. Original
standalone audit schema1 retains its original semantics. Intermediate native-v1
captures are explicitly unsupported by the corrected reader, but remain historical
products inspectable with their frozen providers; they are not upgraded/relabelled.

### Findings and corrections

Initial suites and a first native run were followed by independent reviews:

- Actual native writer continuation/derate/current-design grammar differed from
  modeled syntax; qualified native excerpts became durable regression fixtures.
- The linked wrapper accessed its receipt before LibreLane loaded `_TCL_ENV_IN`;
  startup is now protected and receipt/SDC/report/process ordering is tested.
- Native parser comment continuation could fabricate relations; raw CR could hide
  extra false paths, disables and a second design selection. Qualified continued
  comments and all CR bytes now reject before ambiguous interpretation. Actual
  `tclsh` source-channel counterexamples substantiate the failures and fixes.
- Unframed native reports could misassign diagnostic groups to categories. Native
  profile2 now frames category boundaries, rejects marker spoofing and binds top.
- Coarse proof admitted unrelated loaded-library lists, mismatched executed source
  paths, cleanup contradictions and duplicate CPU flags. It now validates ordered
  actual library/copy/hash associations, historical execution roots, terminal
  shapes/cleanup and the complete qualified transport argv.
- Archive could ignore a run's producer-expectation marker; it now uses the same
  required-evidence rule as inspection and rejects downgrade before publication.

[Native review](pt7c-native-review.md) and [flow review](pt7c-flow-review.md) record
all repros, corrected controls and final source hashes. No reviewed blocker remains
for the stated bounded slice. Earlier failures and native-v1 success remain intact.

### Actual native acceptance and final reader

Native-v2 run: `83a02bdcb4b34f22bbc03b0ec5223b41`.
Bundle: `9d01f5c006c697dd103762c04038fd73e8322d3b546f2bf56dfcad0de19cc8c6`.
Execution provider: `4d4316e3a33942c2a577d6f55acaa34a`, source snapshot
`8d3fa9270712a47473c22615c2a7005d975b361db5f569dfbe8e911055ccbe89`.
Actual LibreLane 3.1.0.dev3 / OpenSTA 2.7.0, typical CMOS5L corner. Five original
stages, six exact relations, seven category-bound diagnostics and 12 native endpoints
were checked. Eleven real diagnostic executions demonstrate scope changes,
missing delay/clock findings and bounded capture-witness suppression.

The final CR correction is **reader-only**. Corrected inspector generation
`4c9ae1a7a50444179c8ab69469443c19`, source snapshot
`5a6bd3664828e0d28c9b0ad3d7eb084486fad45c41251c08136c59b45a3ed033`, replays the
unchanged executed artifacts. No new synthesis/STA is attributed to that reader.
It passed 70 public CR/LF/semantic assertions and original/restored/standalone
inspection, collection, report and fresh archive/hidden-source restore replay.
Original provider/current selections are distinct from this isolated reader store.

[Native acceptance](../../../hardcaml_asic_example/docs/pt7c_native_v2_final.md),
[reader correction](../../../hardcaml_asic_example/docs/pt7c_reader_r1b_final.md),
[independent final review](pt7c-final-review.md).
Final review independently checked raw native products, all eleven controls,
source/process/library associations, original run bytes, both installed provider
inventories and hidden-source archive replay. Three evolving example documentation
paths changed after the earlier closeout; their original snapshots remain and match
the original hashes. Do not call those three current paths unchanged. Native inputs,
reports, histories and old provider/app selections remain preserved.

### Verification and remaining limits

Focused final groups include 154 native reader checks and 17 Tcl language controls,
256 independent native probes, 150 flow orchestration/source/archive checks and
11 real-Tcl startup checks, plus existing schema1/timing-intent regression.
One forced install/integration regression passed after native-v2 integration and
before the later CR finding: collection/report/archive/CLI/coarse/preflight and
new timing suites. Affected focused/review/public replay checks were rerun for the
reader-only fix; the earlier broad run is not relabelled as a later full suite.
An optional historical retained-finalization fixture remained unavailable.
These are heterogeneous check groups, not an additive total.

Coordinator packaging review found a stale exact installed-module inventory:
`python3 -B test/test_packaging.py` initially failed 1/17 because the new
`timing_intent_runtime` helper was absent from the expected set. Updating that
test's inventory to the actual twelve-module package made all **17 tests pass**.
This test-only correction and documentation closeout postdate the captures;
executed runtime/producer/reader implementation bytes did not change, so no native
rerun or provider recapture was required.

Real sampled setup is +19.432287 ns. All three declared downstream hold witnesses
remain **−0.044244 ns**, and broader min-report samples reach **−0.243063 ns**.
Ordinary synthesis report success is not timing closure. Reset-effect/adequacy,
exhaustive exception effects/per-check coverage, named execution integration,
other-corner/post-PNR qualification and Protemu review remain open in the phase plan.

No P&R, Workbench/Protemu changes, old provider/app configuration changes, daemon
actions or Git mutations occurred. Explicit six-job allocations, checkout Dune
locks and serialized single-thread STA stayed within the 20-job pool. This
documentation closeout follows the tested captures without replacing their identities.
