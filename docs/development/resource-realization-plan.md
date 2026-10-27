# PT.5 design and implementation handoff

2026-10-27 — **Reconciliation and headless acceptance delivered; richer measurement attribution remains limited.**
The [phase plan](../phase_plan.md#pt5--requested-versus-realized-resource-checks)
is the only active queue. This document specifies bounded work and acceptance,
not an additional queue or a completion claim. The other flow agent has finished.
The reviewed baseline includes example `project flow emit`, which publishes the
exact `Methodology_plan.Prepared.bundle` and returns plan/bundle identities.

## Authorized integration decisions

- PT.5 is cross-stage evidence, not another physical stage. Preparation selects;
  emission binds expectations; synthesis and physical validation check realization.
- Derive structured expectations from the same checked resolution used by bundle
  rendering. `Project.Rendered`/`Methodology_plan` validation must remain compatible.
- Linking a separate durable PT.4 attempt is optional and deferred unless verified;
  absence of that link does not prevent authoritative bundle-to-run reconciliation.
  `Methodology_plan.prepare` and `Project.prepare_resources` remain distinct APIs.
- Named-flow FIFO emission is a compatibility test, not a claim of named-flow macro
  or checkpoint support. Retained coarse SRAM runs remain the macro acceptance path.
- Historical records are never rewritten. New checks report unavailable evidence
  explicitly and do not treat it as passing required-macro retention.
- ASIC Dune operations use `flock /tmp/opencode/asic-pt5-build.lock` and explicit
  `-j6`; each of up to three agents has six jobs, with two reserved. No EDA allocated.

### Concrete initial ownership

A owns bundle structured inventory, resource snapshot changes if needed,
`methodology_plan.*` compatibility, and new library-focused tests. B owns the
resource evidence engine plus execution collection/report/inspection/archive and
CLI integration and its focused tests. C owns example acceptance/scripts/docs and
independent review of retained evidence. Coordinator owns planning/status docs.
Shared root test/build declarations belong to B; A should use a new test subdirectory.
The initial seam is an optional, identity-covered manifest `resource_snapshot`
containing the existing `Resource_snapshot.to_json (of_resolved resolution)` schema.
B supports historical manifests without it using the existing resource/macro
contract with explicit legacy coverage. No separate preparation identity is invented.
Agents must record exact execution API/wire choices in a handoff before C integrates.

## Objective and boundaries

Connect declared/selected logical resources to observations of synthesized and
physical instances through ASIC-owned library and CLI interfaces. Keep selected
facts distinct from realized measurements. Use `hardcaml_asic_example` as the
production-style acceptance consumer; Protemu adoption is independent.

Preparation remains an overall-workflow operation, not a physical stage. Reuse
the existing selector, physical checks, execution identities and result surfaces.
No new physical-stage enum, consumer-local reporting framework or Workbench
backend schema is proposed. Workbench and Protemu changes/testing are outside
this work. Existing SRAM physical qualification is not restarted.

## Findings from read-only inspection

- `lib/elaboration/resource_snapshot.*` already captures structured requests,
  policies, selected implementations, actual elaboration role and RTL-verified
  instance identities. RTL verification does not establish synthesis retention.
- `lib/elaboration/bundle.ml` identity-covers selected resources as S-expression
  strings and has a structured `macro_contract.macros` inventory. Implementation
  and simulation inventories are separate.
- `execution/runtime/macro_contract.ml` checks declaration/instance consistency;
  `flow/hardcaml_asic_flow/physical_runtime.py` checks powered-netlist identities,
  LVS macro inventory, final GDS and power geometry. Preserve these gates.
- `execution/results/collect_service.*`, `report_service.ml`,
  `stage_report_service.*`, `inspection_service.*` and `yosys_stat_evidence.*`
  are the current reporting seams. Generic per-resource realized evidence and a
  general required-macro acceptance gate are missing.
- Archive retention is explicit: putting a reference in `raw_artifacts` alone
  does not ensure that `execution/archive/archive_service.ml` retains its bytes.

These are inspection findings, not implementation verification. File ownership
and integration choices must be rebased on the concurrent flow work.

## Shared semantic and wire contract

Use one versioned ASIC-owned `resource_evidence` object shared by collection,
acceptance and public inspection. Proposed schema 1 shape:

```text
contract, schema_version
provenance:
  bundle/build identity, manifest digest
  preparation_link: verified | unavailable, reason, identities/verification scope
observations[]:
  stage, producer, run/attempt identity, evidence_refs[]
  resources[]:
    resource_id, requested_contract, selected_implementation
    expected: module, instance identities, count, retention requirement
    realized: observed instances and types, count or unavailable
    status, reason, evidence_refs[]
    area, timing_links, electrical_links, attribution
  unexpected_instances[]
  measurements
  check_outcomes
```

Field spellings and OCaml signatures are to be frozen in this document before
parallel implementation. The semantics below are mandatory regardless of the
final shape; do not create competing collection and inspector schemas.

### Selection, identity and provenance

1. New bundles should carry an identity-covered structured implementation
   inventory derived from `Resource_snapshot.of_resolved`. Keep simulation-role
   snapshots distinct. Historical bundles retain their identities and remain
   readable through an explicitly limited legacy adapter using existing inventory
   and macro contracts; do not rewrite or silently upgrade old manifests.
2. Preparation has no bundle identity. For new explicit preparation linkage,
   verify the preparation payload and compare the relevant effective configuration,
   actual implementation RTL/circuit and resource snapshot against the bundle's
   emission inputs. Retain the verification scope and preparation identity inside
   the identity-covered bundle payload. If existing APIs cannot establish those
   equalities, report linkage unavailable and keep that sub-slice open. Matching
   project names, resource lists or selected macro names is insufficient.
3. Historical retained runs can demonstrate bundle-to-realization checks without
   any preparation link. In particular, the later PT.4 preparation attempt must
   not be attached to the earlier SRAM runs by resemblance.
4. Each observation identifies its real producing stage, run/attempt and build,
   with exact artifact digests, formats and scope. A synthesis observation must
   not be labeled final physical merely because collection occurred after routing.
   Preserve stage producer identities when finalization maps checkpoint outputs.
5. Historical inspection is read-only and needs no current source, PDK discovery
   or EDA. Evidence integrity is not producer authentication or proof that observed
   source files compiled the constructor; P6 source stamping remains separate.

### Reconciliation outcomes

- `matched`: exact expected type/count/instance identities observed.
- `missing`: valid complete observation lacks a required instance.
- `unexpected`: extra observed macro instance or wrong type/identity. Keep these
  observations separately visible, including when no requested row owns them.
- `unresolved`: absent, corrupt, unsupported or insufficient observation, with
  a specific reason. Aggregate cell counts alone cannot prove instance identity.
- `optimized_away`: only with explicit producer evidence of elimination and its
  applicability to the logical resource. Absence alone is not optimization proof.

Report wrong-type, duplicate and renamed-instance details without allowing a
matching aggregate count to mask them. Required macro missing/unexpected/unresolved
outcomes fail the relevant implementation check; optimization is not an exemption
for required macro retention. Stage-not-reached and resource-not-applicable are
explicit availability states, not successful zero-instance observations.

Use mapped instance-level evidence (for example Yosys mapped JSON), cross-checked
with counts where present. Adapt the established final-netlist/physical checks
instead of replacing them or treating an unverified report assertion as proof.
Unknown macro classification must produce a coverage limitation rather than
claiming a complete inventory. Flop-resource mapping lost during optimization
means per-resource attribution unavailable, not zero area or missing macro.

### Measurement semantics

Every measurement carries value or explicit unavailable reason, unit, definition,
stage, inclusion scope and evidence references. Distinguish:

- Total mapped cell count, macro count and standard-cell count. Audit existing
  labels: totals including a macro must not remain labeled standard-cell counts.
- Synthesis standard-cell area and macro library area. Add them only when the
  producer's inclusion semantics and macro library binding are established.
  The result is a **combined cell-area estimate**, not placed/routed or die area.
- Physical standard-cell area, macro library area, physical macro footprint,
  core area and die area. Do not silently substitute one for another; count and
  area scopes must say whether fillers, decaps and other physical-only cells enter.
- Standard-cell utilization versus whole-design occupancy. State numerator,
  denominator and excluded regions; do not infer occupancy from a utilization
  percentage with unknown denominator or mix synthesis and physical numerators.
- Resource-linked timing/electrical paths only where observed endpoints identify
  that resource and retain corner, analysis type and producing artifact. Whole-chip
  worst slack or all-corner zero violations is not per-resource timing attribution.
  Unsupported attribution is explicitly unavailable; existing global checks remain.
- Sequential area/count is a whole-design measurement unless surviving mapping
  proves resource ownership. The example's original 16 staging flops must not be
  attributed to the SRAM implementation. Added delay/buffer cells are combinational.

Known acceptance numbers, to verify from retained artifacts rather than hard-code:
synthesis standard-cell area 2,182.7232 µm², macro Liberty area 28,127.104 µm²,
combined estimate 30,309.8272 µm²; final physical standard-cell area 4,793.64 µm².
The physical value is a separate-stage measurement, not the synthesis estimate.

## Bounded implementation assignments (after authorization)

| Slice / owner | Exclusive initial ownership | Dependencies | Acceptance |
| --- | --- | --- | --- |
| A — contract and realization engine; general agent, 6 jobs | New `execution/results/resource_evidence.*`; `lib/elaboration/resource_snapshot.*`, bundle inventory/linkage additions and focused new engine/library tests | Coordinator freezes schema and linkage API after concurrent-flow review | Deterministic strict decoding; explicit legacy/unavailable linkage; exact type/count/identity reconciliation; meaningful missing/wrong/duplicate/unresolved negatives; evidence-qualified optimized-away state; correct area/count scopes |
| B — execution integration and public inspection; general agent, 6 jobs | `collect_service`, `report_service`, `stage_report_service`, `inspection_service`, `yosys_stat_evidence`, finalization/archive integration; required CLI routing/capability files and their focused tests | A's frozen API; coordinator confirms no collision with flow agent | Required-macro checks fail closed; public library/CLI share schema; stage/producer identity retained; archive contains advertised evidence; historical inspection is nonmutating; existing SRAM checks preserved |
| C — example acceptance; general agent, 6 jobs | New example `scripts/check_resource_evidence.py`, `acceptance/resource-realization/` and example guide; minimal example CLI wiring only if needed | A/B public API available; dedicated captured provider | Retained synthesis and physical evidence inspected through public API/CLI; area/count oracle and negative fixtures; historical byte preservation; explicit unavailable attribution/linkage; isolated provider and reproducible receipt |
| Coordinator | This design, `docs/phase_plan.md`, public operating guide, interface agreement, orchestration/review and integration tests | All slices | No conflicting ownership; evidence-backed status; review schema/identity and acceptance false-positive risks |

Before delegation, enumerate exact shared build/export/test files and assign each
to one owner. A publishes its signatures and wire examples first; B may prepare
fixtures independently but integrates only against that contract. C may inventory
retained evidence before the provider is ready. Reassign a completed agent to
independent review rather than exceeding three concurrent agents.

Public inspection should reuse the execution inspection/collection route if the
new flow work provides a suitable seam. A dedicated resource command is a fallback
only if that route cannot represent coarse retained runs. Resolve this before B
starts; no command name/capability is promised by this plan.

## Acceptance sequence and retained evidence

1. Pure/fixture tests: no-resource success, explicit flops and fallback with
   unavailable cost attribution, exact macro, multiple distinct resources, same
   count/wrong identity, wrong type, extra/missing/duplicate instances, incomplete
   observation, unsupported parser and malformed/nonfinite measurement data.
   Test missing evidence separately from a valid empty inventory. Test stale or
   mismatched stage/build references and malformed explicit preparation linkage.
2. Integration tests: collection and report use the same verdict; synthesis and
   physical failures are independent; missing required evidence cannot pass.
   Verify archive closure and read-only historical inspection. Preserve existing
   physical policy, raw Magic and macro-boundary LVS semantics.
3. Example synthesis: use `acceptance/sram/8b48d7d0-functional/`, public run
   `8b48d7d0818d494f8a9c45000c2bcbbd`, bundle
   `4fe842a7c07b94ae9e8e0546210c9273d019fccdca2d5cbf84311948bde64d09`.
   Check `mapped.json`, `mapped.v`, `stat.json`, manifest and retained Liberty.
   Expect one `hc_resource_7_program`, 176 total mapped cells including that macro,
   16 original staging flops and the separately scoped areas above.
4. Example physical: use `acceptance/sram/physical-p4/`, accepted run
   `be961b2c95f74c81ad6af81ca4d2b269`, bundle
   `fa38d9064dffdf2ec1578c79c2e8890eba81bf704af460e85fcc6031b707d53c`.
   Read final netlist, physical checks and metrics through the public interface;
   preserve original run/postcheck verdicts. These are distinct builds/runs, not
   one joined synthesis-to-physical execution.
5. Mutate only disposable fixture copies for negative checks; retain command,
   exit, structured outcome and source artifact digests. Verify original evidence
   hashes before/after. A new report does not retroactively replace an old report.
6. New explicit preparation-to-bundle linkage needs a fresh example emission and
   public API checks, including mismatched configuration/circuit negatives. It can
   be tested without P&R. Do not claim retained old runs exercise the new linkage.
7. Run targeted aliases first, then appropriate broader ASIC/example suites after
   integration. Retain actual assertions, counts, skips and unavailable evidence;
   successful process exit alone is not acceptance.

Use a new example provider store such as `.dev/asic-pt5` and build directory
`_build_pt5`; preserve `.dev/asic-prepare`, SRAM and Workbench selections. Retain
provider capture receipt and exact executable/source identity alongside results.
No P&R rerun is anticipated. If retained evidence cannot support a claim, record
the limitation and decide explicitly whether any new bounded measurement is needed.

## Execution constraints and resume gate

- No git add/commit/amend/push or authorship/publication changes. Preserve all
  existing tracked and untracked example work and concurrent ASIC flow changes.
- Maximum 20 concurrent jobs, including nested builds and EDA workers. Default
  allocation is A/B/C at 6 each, leaving 2 reserved. Every Dune invocation has
  explicit `-j6` or lower while those allocations are active.
- Serialize **all** Dune operations within each checkout, including separate
  build directories. Agree one shared ASIC lock with the concurrent flow agent
  before building; a PT.5-only lock would not coordinate unrelated flow builds.
  Provider capture scripts' nested builds count against their owner's allocation.
- Physical EDA is not part of initial retained-evidence acceptance. Any later EDA
  needs an explicit allocation and tool/container thread limits in the same pool.
- Authorization received after flow work finished. Inspect statuses/instructions,
  preserve concurrent changes and finalize concrete execution signatures before
  dependent integration. Separate-preparation linkage is not a blocking deliverable.

## Original planning-session evidence and limitations

Only read-only inspection and this documentation were performed for PT.5.
The ASIC tree was clean at initial inspection; the example already contained
tracked CLI/documentation changes and untracked memory/preparation/SRAM evidence.
One general agent researched existing integration seams without modifying files
or running builds. No implementation, EDA, acceptance run or PT.5 completion is
claimed. Timing-link availability, exact legacy evidence completeness and the
final API compatibility with concurrent flow work remain to be verified on resume.

## Implementation and review closeout — 2026-10-27

The original planning record above is historical. The authorized implementation
and independent review are now complete for the bounded headless slice. The
[phase plan](../phase_plan.md#pt5--requested-versus-realized-resource-checks) owns
remaining PT.5 measurement work; neither this record nor the handoffs add a queue.

### Delivered interfaces and guarantees

- New bundle `resource_snapshot` derives from the exact rendering resolution;
  identity/schema/logical inventory/instance/physical-intent/collateral consistency
  are checked. Legacy snapshot absence remains readable. Methodology-plan FIFO
  emission compatibility is tested without enabling macro named-flow execution.
- `Hardcaml_asic_execution.Resource_evidence.inspect ~run_dir` and installed
  `hardcaml-asic-flow resources-inspect RUN_DIR [--json]` share schema 1. Required
  mismatches fail collection/report acceptance; historical reporting is read-only.
- Synthesis and final physical observations carry distinct producer/run/build
  provenance and hashed evidence. Missing, unexpected and unresolved instances
  are explicit. Unsupported hierarchy/parser coverage cannot produce a partial pass.
- Count and area semantics distinguish macros, standard cells and physical-only
  cells. Source-aware validation replays assertions; archives retain every advertised
  evidence source and permit genuine failed reconciliations.
- Separate PT.4-attempt linkage is unavailable, as agreed. Timing/electrical
  resource attribution, physical macro footprint/occupancy denominator, and
  optimized-flop costs remain unavailable rather than inferred from global metrics.

Concrete schema and tests: [bundle handoff](resource-realization-bundle-handoff.md),
[execution handoff](resource-realization-execution-handoff.md),
[operating guide](../guides/resource-realization.md).

### Independent review corrections

Initial passing fixture/consumer suites were followed by independent reviews.
Review found and corrected six consistency/false-positive issues:

1. Multi-instance Verilog declarations previously lost additional instances.
2. Standard-cell-like module names could hide nested hierarchy/macros.
3. Available mapped files could pass without a completed synthesis boundary.
4. Internally contradictory or coherent fabricated reports needed inventory/count
   consistency and full source-derived assertion replay, beyond hash checking.
5. A macro overlapping a standard-cell namespace could enter both area subtotals.
6. Resealed macro collateral contradictions needed role/corner/reference cross-checks.

An additional correction prevents root aliases rescuing an unrelated live flow.
Independent follow-up passed **89 assertions/command checks and 17 CLI observations**,
including genuine failed archive publication, every referenced archive byte,
coherent-forgery rejection and explicit-context replay. No unresolved finding
remains in that review scope. Probe/log receipts are
`/tmp/opencode/pt5_independent_corrections.py` and
`/tmp/opencode/pt5-a-independent-corrections-20261027.log`; durable regression
coverage is in `test/check_resource_evidence_review.py` and bundle tests.

### Final acceptance and provenance

Independent example evidence:
[`acceptance/resource-realization/`](../../../hardcaml_asic_example/acceptance/resource-realization/README.md).
Authoritative receipt: `installed-final/verified/receipt.json`; closeout:
`closeout-final.json`. Earlier `installed-04` and harness failures remain retained
and are explicitly superseded, not overwritten.

| Identity | Final corrected capture |
| --- | --- |
| Provider generation | `dd1ec9002cdc40f2936488cedd9eb0fe` |
| Captured source SHA-256 | `bc8b35619819beb0bbe20a4f0d7213864013ee4b05e9c2688e901dd1f6cb05f0` |
| Provider executable SHA-256 | `4773450d32c716b5126828fdb08683fca6e40e55e0670ea4cd98b93ca58c5b3f` |

The capture precedes coordinator-only documentation closeout; it identifies tested
implementation bytes, not a clean revision or P6 compiled-source stamp.

- **20** focused example tests, **76** installed API/CLI calls, and **41** closeout
  assertions passed; all **276** original historical evidence files unchanged.
- **5** standalone FIFO flow-emission tests passed. Fresh flop/fallback bundles
  used synthetic observations, not newly synthesized hardware.
- Synthesis: 176 total = 175 standard + one macro; area
  2182.7232 + 28127.104 = **30309.8272 µm²** combined estimate.
- Separate physical run: **4793.64 µm²** standard-cell area; 68,928 netlist
  non-macro instances include fillers/decaps, distinct from 389 native logical
  standard cells. Missing physical-snapshot synthesis-area inputs stay unavailable.
- Installed semantic negatives rebind disposable physical integrity chains before
  reconciliation; these are deliberately modified fixtures, not requalified geometry.

### Broader checks and execution limits

After review fixes, independent forced full ASIC regression passed in 648.256 s:

```sh
flock /tmp/opencode/asic-pt5-build.lock \
  opam exec --switch=5.2.0+ox -- dune runtest --force -j6 --display short
```

Receipt: `/tmp/opencode/pt5-a-correction-full-suite-20261027.log`, exit 0. Includes
**62** bundle assertions, **108** plan checks, **27** original CLI resource cases,
**19** corrective observations, **131** collection/**585** report differentials,
**16** archive/**26** finalization differentials and preparation/SRAM/runtime suites.
The earlier pre-fix full run is not the final receipt.

The example's corrected-provider full suite also passed:
`dune runtest --build-dir _build_pt5 -j6 --force .`, with installed routing enabled;
full command/build/test logs are retained in its acceptance directory.

Limitations: an optional older retained-finalization fixture was absent; the ASIC
observation corpus reported `historical: 0`. Standalone installed-prefix/corpus and
explicit retained-checkpoint aliases are outside default `runtest`; installed PT.5
acceptance above provides its own narrower public-consumer coverage.

All agent allocations were at most six jobs (maximum allocated 18), ASIC Dune
serialized under the shared lock, example builds serialized. No new physical EDA,
Workbench/Protemu changes or tests, Git staging/commits/pushes, provider-selection
changes or historical evidence edits were performed by this implementation.
