# PT.7 — bounded timing-intent implementation

2026-10-28. This plan precedes implementation. The [phase plan](../phase_plan.md)
is the only active queue. **First bounded slice accepted 2026-10-28**; the original
pre-implementation contract follows. See the closeout below for actual scope.

## First supported subset

Extend existing `Timing`, elaboration/resolution and bundle SDC ownership. Support
one primary clock, exact scalar/bit input references, scalar register Q anchors,
reasoned external asynchronous capture to the first stage's data pin, and explicit
external reset to enumerated asynchronous-control pins. Preserve downstream data
timing. Do not insert registers, change latency/reset behavior, infer CDC correctness,
or accept arbitrary wildcard/general false-path declarations. Unsupported cell/pin
roles and missing, ambiguous, merged or optimized-away anchors fail closed.

Use existing hardware registration/naming facilities where possible. Register
references identify preserved Q nets, never predicted anonymous Yosys cell names.
Preservation attributes are requested intent until real synthesis proves retention.
Reset exceptions explicitly waive timing only at the enumerated async-control pins;
they are not a general reset waiver. Consumer reset/protocol review remains pending.

## Shared contract and ownership

| Slice | Owner/files | Dependencies | Acceptance |
| --- | --- | --- | --- |
| A: declaration and emission | General implementation agent; `lib/` timing/context/elaboration/resolution/bundle, existing timing literal migrations in ASIC, isolated `test/timing_intent/` | Existing Timing pipeline | Typed exact references, reasons, validation, strict Tcl resolve-all-before-apply, identity-covered intent; positive/negative tests |
| B: evidence and CLI | General implementation agent; new `execution/results/timing_intent_evidence.*`, CLI routing/capability files, isolated `test/timing_intent_evidence/` | A's published manifest/Tcl wire handoff | Read-only public inspection, strict source/provenance validation, requested/resolved/applied separation, unavailable coverage never pass |
| C: independent example | General implementation agent; new example `timing/`, `acceptance/timing/`, isolated PT.7 provider/build, necessary example timing literal migrations | A/B public APIs | Fresh emitted specimen, mapped synthesis + bounded linked STA, downstream min/max paths, negative tool cases, exact input/producer receipts |
| Coordinator | This plan, phase queue, operating guide, integration/review | All slices | Independent review, actual evidence and limitations |

A publishes concrete OCaml signatures and generated wire format in
`pt7-library-handoff.md` before B/C integration. B publishes its exact evidence
schema/CLI in `pt7-evidence-handoff.md`. Changes to these seams must be coordinated.
Root test/dune belongs to A only if needed; prefer isolated subdirectories. B owns
bin/dune and preserves its existing modifications. No other shared-file editing.

Required wire semantics (schema 1, concrete spelling frozen by handoffs):

- Bundle timing intent is identity-covered and derived from the same resolution
  as SDC: IDs, reasons, exact endpoint references/anchors and exception kind.
- Tool records distinguish resolution from application. All endpoint cardinalities,
  exact names, mapped master/pin roles and exception scopes are checked before any
  application. A returned `set_false_path` alone is not path-effect verification.
- Evidence identifies exact build, run/audit attempt, stage, producer version and
  corner, with hash-bound SDC, netlist, libraries, raw resolution/application log,
  native exception/coverage reports and downstream path reports where supported.
- Unavailable native introspection remains explicitly unavailable. Missing reports,
  failed resolution or inconsistent provenance cannot become passing coverage.
  Native unconstrained diagnostics are retained; sampled paths are not exhaustive.
- Historical SRAM resource timing is not PT.7 evidence. No inferred association to
  preparation attempts, current source compilation or historical physical producers.

## Acceptance and limits

1. Library negatives: empty/ambiguous/invalid references, bad reasons, duplicate IDs,
   wrong pin roles, wrong port direction/bit, downstream capture scope and Tcl names.
2. Evidence negatives: missing/truncated data, changed hashes, mismatched producer,
   build/run/corner and coherent false claims; requested-only is never applied.
3. New example synthesis and linked OpenSTA/OpenROAD audit using the emitted SDC,
   retained exact inputs and real producer output. Verify original stage inventory
   and downstream setup/hold timing. No P&R is allocated initially.
4. Independent implementation review after initial tests, fix/retest findings, then
   appropriate existing library/CLI/example regression. Retain failures and skips.

This first slice does not qualify post-PNR preservation, analog metastability,
MTBF, bus coherence, generated clocks, arbitrary tools/cells or Protemu constraints.
Protemu-specific protocol/reset/I/O review remains explicitly pending, independent
of generic library acceptance. Existing SRAM qualifications remain unchanged.

## Execution policy

Preserve initial dirty/untracked PT.5/PT.6 work. No Git mutations/publication,
Protemu/Workbench edits, historical-evidence rewrites, provider selection/config
changes or daemon actions. Use new `.dev/asic-pt7` and `_build_pt7` if needed.
Each agent has at most six concurrent jobs including nested builds (18 total,
two reserved). Every Dune invocation has explicit `-j6` or lower, with ASIC lock
`/tmp/opencode/asic-pt7-build.lock` and example lock
`/tmp/opencode/example-pt7-build.lock`, including separate build directories.
Bounded synthesis/STA, when launched by C, shares C's six-job allocation, with
explicit tool/container/thread limits and serialized STA. Physical P&R allocation
is zero. Existing opam switch: `5.2.0+ox`.

## First-slice closeout — 2026-10-28

Implemented the existing Timing pipeline extension and standalone read-only audit
inspection. Concrete contracts: [library](pt7-library-handoff.md),
[evidence](pt7-evidence-handoff.md), [operating guide](../guides/timing-intent.md).
No normal-flow collection/archive integration or exhaustive coverage completion is
claimed. PT.7c and consumer-specific obligations stay in the phase plan.

Independent reviews found meaningful defects after initial tests passed:

- Missing mapped clock/data/reset source checks; now validated before application.
- Tcl/native literal matcher differences for bit names and top Pin external versus
  Term internal net semantics; two failed provider captures retained before actual
  corrected native acceptance. Fixture models were corrected from real-tool probes.
- Top-level output sinks incorrectly counted as Q drivers; native tap controls pass.
- Order-sensitive JSON receipt comparisons, weak manifest envelope/whole-SDC binding,
  log memory amplification, fatal-line handling and selected envelope cross-links;
  corrected with semantic negatives and independent repeat probes.

[Library review](pt7-library-review.md), [evidence review](pt7-evidence-review.md)
and [final retained-evidence review](pt7-final-review.md) record findings, fixes,
commands and qualifications. No blocker remains for the stated first slice.

Final example provider generation: `74e9a52b43a14c69bff2763325b39522`; captured source
SHA-256: `a6723afb6a88bce6152d7b05662ea614a6e1a75352b870b4e20391e7c2d3f684`.
The [example r3 report](../../../hardcaml_asic_example/docs/pt7_timing_final.md)
records exact bit/scalar bundle identities, raw synthesis/STA inputs, typical-corner
models, commands and all earlier failures. Final review verified 2,141 retained
files, original closeout inventories, protected files and provider pointers.
This documentation closeout postdates the tested development capture; it does not
replace the source snapshot or claim P6 compiled-source attestation.

Verification included 34 library negatives, 8 production-Tcl positives / 41
pre-application negatives, 54 evidence checks / 27 additional repro regressions,
and independent modeled checks. Broader ASIC testing passed 42 named root aliases
and six isolated suites, plus inline library tests; one optional historical
finalization fixture was unavailable. Later bounded corrections reran affected
suites rather than relabeling that earlier broad run as a final forced full suite.
Existing example core/wrapper/memory/catalog and five public emission compatibility
checks passed. Final native acceptance verifies both source forms, five retained
stages, 34 connectivity cases, six taps and five additional negatives. Independent
final review made 44 fresh public inspections, including 36 intended rejections.
These are heterogeneous check groups, not one additive test count.

Every baseline retains three setup and three hold samples; hold remains violated
at −0.044244 ns. OpenSTA 2.7.0 lacks native exception enumeration; raw unconstrained
and downstream reports are retained but the generic reader does not interpret
coverage. Valid inspections therefore return unavailable/exit 1. No full physical
flow, other-corner, post-PNR, metastability/MTBF, reset-protocol or Protemu acceptance.
Maximum allocations remained 18 jobs with shared Dune locks and explicit limits;
native tools were serialized single-thread/one-CPU within C's allocation. P&R zero.
Existing histories/app configuration/providers and Workbench/Protemu were preserved.
