# Timing-intent all-corner and physical qualification

2026-10-29. Written before implementation. This follows the completed bounded PT.7
library/synthesis feature; [phase_plan.md](../phase_plan.md) is the only active queue.
The user explicitly authorized proceeding with physical qualification. Existing
ticket drafts, roadmap changes and all example histories remain preserved.

**Final status: bounded physical timing and portable-source acceptance complete.**
The original pre-implementation plan follows; the execution record below records
actual results, corrections and qualifications.

## Bounded implementation and acceptance target

Use the existing five-register timing specimen in `hardcaml_asic_example`. First
capture all configured standard-cell corners after synthesis, then run **one fresh
ordinary coarse full flow**, followed by linked extracted post-PNR STA and normal
physical/external postchecks. Coarse full is already implemented; named physical
admission remains deferred. Do not fabricate named provenance or restart SRAM work.

Keep source architecture/reset semantics, 20 ns clock, min/max I/O delays,
0.25 ns uncertainty, 0.15 ns transition, 0.95/1.05 derates and loads unchanged for
the baseline. The inherited uncertainty has weak physical justification; preserve
it rather than reduce it to obtain a pass. Record both its contribution to early
hold failures and actual propagated-clock/extracted-delay contributions later.
No analog metastability/MTBF or reset-protocol approval follows from STA closure.

Accepted physical repair may add known noninverting combinational buffers/delay
cells or supported cell sizing. It must not add registers, merge/clone stages,
change latency or reset behavior, or waive downstream timing. No blanket keep/
dont-touch on Q nets: that can obstruct the very hold repair being qualified.

## Exclusive slices and dependencies

| Owner | Files/scope | Acceptance |
| --- | --- | --- |
| A: physical endpoint contract | `lib/elaboration/timing_intent.*`, `timing_tcl.*`, minimal resolved/bundle/native producer additions, focused `test/timing_physical/` | Explicit identity-covered physical resolution policy; qualified bounded buffer/delay traces and stage sizing; checked endpoint map reusable by witnesses; no broadening |
| B: execution/evidence | Coarse full/service/runtime/linked reader, native audit/coverage/metrics, collect/report/archive/capability and postcheck worker enforcement; `test/timing_physical_flow/` | Stage-aware exact post-PNR State/netlist/SPEF association, all-corner process/results, closure verdict separate from coverage, old synthesis/named compatibility |
| C: independent example and EDA | New example physical timing consumer/scripts/docs/evidence, isolated `.dev/asic-timing-physical` / `_build_timing_physical` | Fresh all-corner synthesis, actual full flow, native controls/postchecks, immutable inputs and no added architectural state, explicit failures and qualified verdict |
| Coordinator | This plan, phase queue, guide, allocation, review/integration | Timely progress tracking, independent cross-review and final source/evidence checks |

A publishes `timing-physical-library-handoff.md` and B publishes
`timing-physical-flow-handoff.md` with concrete signatures/schema before dependent
integration. B owns root build/test declarations; prefer isolated test directories.
Preserve old resolution-policy and audit semantics. C uses public provider APIs,
not a replacement production timing parser or patched emitted SDC.

## Shared semantic contract

1. Architectural elaboration remains direct scalar chains. Physical resolution
   accepts only bounded explicitly qualified noninverting buffer/delay transformations
   between exact original roots and endpoints. Require unique drivers/stage cells,
   correct pins, no cycles/contending inputs, fixed justified depth and complete
   trace inventory. Unsupported transforms reject before applying exceptions.
2. Keep exceptions at first-stage D and enumerated RESET_B only. Export/reuse the
   checked native endpoint map for witness queries; no second immediate-driver
   resolver that disagrees after buffering. Qualify ODB-backed OpenROAD object APIs
   with native controls before full implementation.
3. Extend the emitted identity-covered contract explicitly for all-configured
   synthesis analysis and physical qualification. Old default-only synthesis
   captures keep their original meanings. Actual supported delay-cell pin/function
   and Liberty availability must be checked, not inferred from cell names.
4. A physical audit must identify `post_pnr` / extracted netlist scope, not masquerade
   as synthesis. Preserve native-v2 stored-scope/diagnostic data if unchanged; version
   outer audit/companion and resolution policy where semantics differ.
5. Run native STAPostPNR over the exact completed physical producer's **input State**,
   linked to routing/RCX producer evidence. Retain complete netlist, selected extracted
   SPEF and annotation report, actual ordered libraries, SDC, producer/helper/scripts,
   clock propagation evidence, configs, logs and process results. Each actual consumed
   path must map to the retained hash/bytes; merely archiving SPEFs is insufficient.
6. Preserve placement/CTS/routing/RCX producer/state chain. A CTS checkpoint precedes
   post-CTS repair; don't mislabel it as repaired. Only stages/corners actually analyzed
   get timing claims. A linked audit is a new analysis of the same implementation,
   not the original in-flow STA process.
7. Requested/configured/executed/equivalent/failed corners stay distinct. Initial
   physical acceptance requires fast, typical and slow each actually executed.
   Closure needs per-corner nonnegative setup/hold and zero violations with explicit
   units and matching native process/report/metric sources; aggregate inherited
   metrics or sampled witnesses alone cannot prove it.
8. Keep process completion, supported native coverage, timing closure and physical/
   external postcheck acceptance separate. Exhaustive exception-effect/per-check
   coverage remains unavailable. Never hide negative slack, annotation gaps or
   missing corners. Failed runtime or invalid required evidence blocks acceptance.
9. Public coarse inspection/report/collection/archive source-replay exact retained
   stage/corner sources; no renderer/current PDK lookup on historical reads. Preserve
   schema1/schema2 and existing coarse/named synthesis compatibility.

## Verification sequence and repair budget

1. Pure/library/API-model tests, real qualified cell collateral inspection, source
   and scope negatives. Native ODB/STA buffer/clock/anchor/interstage controls with
   successful baseline; no physical run before these critical interfaces work.
2. Fresh example all-corner synthesis, explain hold model and retain all failures.
   Verify corner/library association and native diagnostic/check availability.
3. One fresh coarse full attempt using emitted Hardening bundle, normal stages and
   existing checks. Preserve failures. One additional full repair attempt is allocated
   only after a specific diagnosis and recorded behavior-preserving change. Further
   full attempts require a documented plan/allocation revision, not blind retries.
4. Normal external TT/final-netlist functional postchecks and actual physical/electrical
   gates. Do not transfer SRAM-specific waivers to this design. Retain before/after
   repair inventory and all-corner data/clock timing contributions.
5. Source-rebound negatives: wrong/missing SPEF, wrong corner/library, missing process,
   duplicated producer, unsupported topology, exception widening, process failure after
   hook completion and cleanup failure. Archive/restore replay without original PDK.
6. Independent implementation review after initial suites and independent actual
   physical evidence review. Fix/retest findings, update actual outcome. If closure
   fails, deliver the retained failure and concrete blocker; do not call it qualified.

## Explicit allocation and preservation

Global maximum20 jobs: A<=6, B<=6, C<=6, two reserved. All Dune calls explicit
`-j6` or lower, switch `5.2.0+ox`, shared locks
`/tmp/opencode/asic-pt7-build.lock` and `/tmp/opencode/example-pt7-build.lock`.
Private capture builds count within owner allocation. No concurrent Dune operations
in one checkout, even different build directories.

**C is allocated six workers for bounded native diagnostics and physical EDA**
after confirming implemented end-to-end limits; builds and EDA within C serialize.
Flow/container/jobs/OpenROAD/KLayout/postcheck nested workers at most6; STA corners
serialized with native `-threads 1`. Explicit timeout/owned cleanup and input hashes
required. A/B run no EDA unless coordinator reallocates C's budget explicitly.
No provider selection/app config/daemon/Protemu/Workbench changes; no Git mutations.
Old evidence, uncertainty settings and PDK bytes are preserved.

## Execution and independent acceptance

Completed 2026-10-29. Contracts:
[library physical policy](timing-physical-library-handoff.md),
[runtime/evidence/postcheck](timing-physical-flow-handoff.md).
Independent reviews: [library](timing-physical-library-review.md),
[flow/reader](timing-physical-flow-review.md),
[actual routed products and portable closure](timing-physical-final-review.md).
No blocker remains within the supported coarse, macro-free, five-stage profile.

### Delivered and reviewed

- Explicit `Bundle.render ~timing_physical_qualification:true` selects a new
  identity-covered physical resolver and all-configured analysis contract. Default
  synthesis rendering retains its previous meaning. Architectural declarations
  stay direct; supported physical buffering is validated separately.
- Bounded traces admit exact qualified noninverting buffer/delay cells, moved
  anchors and supported flop sizing, with unique original stage roots and complete
  sequential inventory. No blanket net protection blocks native repair. Runtime
  witness queries reuse the checked endpoint map.
- Coarse companion2/audit3 distinguish extracted post-PNR analysis from synthesis.
  Native-v2 scope/diagnostics remain separate from per-corner timing closure.
  Actual original STA INPUT State, RCX/netlist/ODB/SPEF, ordered libraries, native
  annotation filter, propagated clock state, process results and producer order
  are source-verified. Missing/invalid required metrics cannot earn a timing pass.
- Public ordinary postcheck supports the reviewed macro-free used-cell functional
  model view. Unchanged supplied vendor/UDP sources, exact final netlist and
  derived models are bound; replay is digital/zero-delay only, not timed simulation.

Review found and fixed missing serialized-clock enforcement, mismatched actual
hook/filter pointers, unretained filter input, disconnected RCX/consumed ODB
provenance, noncausal producer ordering/dangling State views and malformed repeated
metrics being ignored. Genuine source-rebound negatives and truthful controls
passed after correction. The initial simulator model failed because Icarus left
vendor delayed timing-check signals undriven; the existing reviewed functional
adapter was generalized rather than modifying PDK or netlist bytes.

### Actual progression and repair

198 native controls passed across fast/typical/slow libraries in standalone STA
and ODB-backed OpenROAD. They cover exact topology, qualified delay/buffer chains,
sizing, depth/driver/extra-state rejection and endpoint-map behavior. 512 RTL
observations and four supported-flop native functional-model positives/intentional
negatives separately qualified the replay setup.

Fresh all-corner synthesis retained real hold failures: worst fast/typical/slow
**−0.250147 / −0.243063 / −0.234722 ns**. Setup and slew/cap passed. Native path
decompositions retain the 0.25 ns uncertainty contribution; the budget was not reduced.

The **first full physical attempt** completed in 1477.77 seconds. Lineage:
placement28 → CTS35 → ordinary post-CTS repair37 → detailed routing44 → RCX54 →
original STAPostPNR55, followed by separately identified linked extracted analysis.
Five original reset flops remain. Ordinary repair inserted **nine qualified delay
cells**, no architectural state, and all three downstream links stay timed. Actual
trace depth is at most2 against the supported bound8. CTS35 is pre-repair.

| Cell-PVT corner, nominal RC | Worst setup ns | Worst hold ns | Setup/hold/slew/cap violations |
| --- | ---: | ---: | --- |
| Fast | +16.058595 | +0.102353 | All zero |
| Typical | +15.729074 | +0.276686 | All zero |
| Slow | +15.113664 | +0.590927 | All zero |

The three cell-PVT corners use **one nominal RC extraction**, not three RC
extremes. Original/linked native log/State metrics agree; reports retain full clock
and data contributions. Connected-net annotation filtering passes with exact source
proof; not every raw unannotated-driver line is promoted to complete annotation.
Routing/Magic DRC, antenna and LVS are clean. All nine TT checks (including actual
CMOS5L KLayout DRC) and 512 final-netlist functional observations pass.

Run `23a6954b852d4205b542d3815634d772`; build
`ac513e0e7e9cfa935f73d697caebca8f601aeeb4ea62c2a2ccf61c10a10789cd`.
Executed provider `4856e6af993642988c18c07f47a8c689`, source snapshot
`4a821a382619f33eda6be911cb1bddc9d71345a882e97c5fb5b5de68979153a3`.
[Detailed native receipt](../../../hardcaml_asic_example/docs/timing_physical_full_result.md).

### Portable evidence and resource-accounting corrections

Initial archive restoration omitted seven advertised antenna/DRC/LVS reports.
The bounded verified native-report inventory now retains them. A separate corrected
archiver `1ba205c2a11c4904b03d98b0e7a3f616` republished from the same unchanged
run; no second P&R or postcheck. All **449 archive members**, **423 raw artifacts**
and exact inspect/collect/report results restore with original run/PDK/source hidden.
The **4269-file** portable package verifies independently; all1196 original run
files and16,377 historical files/selectors remain unchanged. Original failed archive
attempts and pre-correction documentation snapshots are retained.

Package: example `.dev/asic-timing-physical/evidence/portable-package-01/physical-timing-portable.tar.gz`.
SHA256: `500d31c84ca8bfd6eb5599a4e449a5ab9952cee2cea54179d5b02317e64d5782`.
These identities are local development-byte provenance, not P6 compiled-source or
cryptographic producer authentication. Documentation closeout postdates captures.

The initial blanket STA-one-thread description was too strong. Actual dedicated
all-corner and linked STA used1; mid-PNR OpenROAD steps36/38/43 requested6 (step31
requested1), within the explicitly allocated6 workers. No global job-budget excess
is observed. Coordinator accepts that recorded accounting without repeating P&R.
A forward runtime fix now covers occurrence-alias subclasses so future dedicated
STA steps request1 while repair steps retain6. Its command-construction tests pass;
it was **not executed in this physical run** and is not retroactively attributed.

### Regression and remaining scope

Library tests include19 positives/25 negatives, historical34 declaration negatives
and8/41 Tcl controls; independent library review adds83 graph observations and actual
Liberty pin/function/arc checks. Final runtime/archive suite has223 checks plus
11 model-adapter and14 existing physical-runtime checks, with affected install,
coarse/named synthesis, native-v2, report/postcheck/archive compatibility suites.
Independent flow repros38 plus10 follow-ups pass; actual routed review records1720
heterogeneous consistency assertions, followed by independent portable validation.
An optional historical finalization fixture remains unavailable. These are separate
groups, not one additive test total or a claim of a final full-repository rerun.

Coordinator packaging test initially failed1/17 because its exact installed-module
list omitted the new `timing_physical_runtime` helper. Updating the test inventory
made all17 pass. This test-only and documentation change does not alter executed
runtime bytes or require another provider capture.

No additional full attempt/repair rerun was needed. Named physical execution,
arbitrary macros/designs, other RC views, exhaustive per-check/exception effects,
analog metastability/MTBF, safe reset release, timed gate simulation and Protemu
adoption remain outside qualification. The accepted claim is physical timing and
ordinary physical/functional checks for this exact example/profile and assumptions.
