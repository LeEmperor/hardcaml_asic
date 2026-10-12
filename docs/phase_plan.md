# hardcaml_asic phase plan

Current checkpoint: 2026-10-12 documentation consolidation and core review.
This is the **only active queue**. [Architecture](architecture.md) owns boundaries;
[P6 details](development/p6-implementation-plan.md) retain the detailed specification
and exact delivery evidence. Proposed new work below awaits design discussion.

## Start here

1. Review the [core assessment](architecture.md#9-core-review-and-development-specimen)
   and settle whether the proposed small boundary-hardening task precedes P6.5a.
2. Agree the controlled-FIFO behavior in `hardcaml_asic_example`, then scaffold
   that independent Dune consumer. It is currently empty; no provider pin is chosen.
3. Settle concrete run/operation/step/result examples and prove the LibreLane seam.
   Continue useful P6 identity/installation work with the dependencies below.

The earlier blanket "finish P6, then migrate scaf" queue is superseded. Do not
execute archived handoff prompts. No feature, source stamp, specimen, observation
contract or new test pass is claimed by this documentation-only checkpoint.

## Status and preserved history

| Track | Current status | Evidence / detail |
| --- | --- | --- |
| ASIC P0–P5, M1–M3 | Complete; retain the working lifecycle/resources/bundle/flow foundation | [Original tasks and completion records](archive/phase-plan-through-p6.4b.md) |
| ASIC P6.1/P6.2 | Complete: operation-aware acceptance and complete input preservation | [Original P6 records](archive/phase-plan-through-p6.4b.md#11-p6--shared-tooling-distribution), reporter/archive suites |
| ASIC P6.3 | Complete: shared dispatcher contract | [P6.3 completion](development/p6-implementation-plan.md#11-p63b-completion-evidence) |
| ASIC P6.4a/P6.4b | Complete: packaging, shared routing and installed-operation coverage | [P6.4a](development/p6-implementation-plan.md#12-p64a-completion-evidence), [P6.4b](development/p6-implementation-plan.md#13-p64b-completion-evidence) |
| ASIC P6.4 parent | Open only for source-access-denied installation evidence | ASIC P6.6a supplies it; do not redo packaging |
| ASIC P6.5a/b/c, P6.6a/b | Open | Scope and dependencies below |
| ASIC P7.1–P7.6 / M4 | Open historical migration; deferred from current queue | [Original tasks](archive/phase-plan-through-p6.4b.md#12-p7--consumer-migration-and-legacy-retirement), [backlog](backlog/README.md) |
| ASIC S.1/S.3 | Complete, with qualified S.3 interpretation | [SRAM index](sram/README.md) |
| ASIC S.2 | Open; S.2a complete, S.2b research partially resolved | [SRAM checkpoint](sram/sram-status.md) |
| ASIC S.4 | Gated, unimplemented | Requires S.2 capability gates |
| ASIC T.1 | Open, independent toolchain follow-up | Scope below |
| Provider observation | Proposed, not implemented | [Architecture](architecture.md#8-provider-observation-direction) |

The source-review baseline is clean ASIC `f6e8fd7` before these documentation
edits. Workbench has owner changes in its active architecture and construction
plan; those files are not modified here. Its P0–P7 numbering is independent.

Historical task text remains in the archive rather than being rewritten to match
new goals. For example, old P2/P3 records describe maximum-only I/O constraints;
current `Timing.Delay` and rendering support both minimum and maximum. The
[target reference](reference/target-reference.md) describes the implemented API.

## Core review before further implementation

Recommendation for discussion: **bounded hardening, not a P0–P5 rewrite**.

- Keep immutable project/build/bundle separation, explicit resource policy,
  deterministic identities, behavioral/flop conformance and ordinary CLI operation.
- Consider first adding `Resolved_build.mli` so only validation constructs a
  resolved build. Acceptance: an external consumer can inspect/use validated
  results but cannot forge them; existing bundle fixtures remain byte-identical
  for identical inputs, and invalid target/timing/override cases still fail.
- Define the optional generator identity and artifact inventory for ASIC P6.5a
  before coding it. Later internal file moves change an inventory digest normally;
  they do not make source stamping throwaway work.
- Refactor runner/collector publication boundaries with the observation slices,
  preserving the current CLI and report/archive acceptance tests. Do not first
  rewrite the whole runner or generalize every target/resource API.

The first item is a candidate small implementation task, not delivered work or
a new mandatory gate on historical M3. Agree this ordering before implementation.

## ASIC P6 — Shared tooling distribution

Keep existing IDs. The detailed acceptance matrix and original commands are in
[development/P6](development/p6-implementation-plan.md#7-ordered-bounded-implementation-units).

- [x] **P6.1** — Operation-aware reporting. Synthesis and full-flow policies remain
  distinct; missing/contradictory evidence cannot become a pass.
- [x] **P6.2** — Complete immutable-input archives with integrity and restoration.
- [x] **P6.3** — Shared installed-command contract and fixed execute semantics.
- [ ] **P6.4** — Installed CLI/runtime assets; **P6.4a/b delivered**, parent waits
  for P6.6a's filesystem source-denial check.
- [ ] **P6.5a — Source-artifact identity.** One deterministic validated source stamp
  embedded in OCaml and Python, Git-free source builds and additive bundle
  `generator_identity`. Test clean/dirty/untracked/unknown inputs, actual opam
  source/export behavior, tampered inventory, determinism, library/CLI equality
  and manifest coverage. No runtime Git guessing or version-as-revision shortcut.
- [ ] **P6.5b — Dependency and waiver records.** After P6.5a: explicit expectations,
  generator/executor comparison, recorded exceptions and historical-read behavior.
  Old analysis does not require matching the current executor's identity. Preserve
  existing records through archive/restoration.
- [ ] **P6.5c — Provisioning/data authority.** After delivered P6.4a: strict requested
  Python behavior, installed lock authority, explicit Docker/native scope and
  read-only/check/offline semantics. PDK-free stub tests prove no implicit network
  or writes in check mode; no baseline pin change is implied.
- [ ] **P6.6a — Independent installation acceptance.** After P6.4b and P6.5a/b/c:
  fresh prefix, unrelated consumer, source access denied, positive/negative
  validation/report/archive/restoration and exact artifact identity. PDK-free.
- [ ] **P6.6b — Documentation and recorded candidate.** After P6.6a: align operating
  commands, run applicable build/test/package checks and record the deliberately
  published candidate. Commit/publication/pin changes remain explicit owner actions.

**P6 exit:** one identified source artifact installs library and generic flow
tooling, works independently of the checkout and preserves P6.1/P6.2 guarantees.
This is still worthwhile when internal observation implementation evolves.

## Proposed provider sequence — not a new phase numbering scheme

After the core/specimen discussion, adopt bounded task IDs here rather than in
another planning document. Every provider slice must work without Workbench.

| Slice | ASIC deliverable and acceptance | Other repository ownership |
| --- | --- | --- |
| Contract and feasibility | Two-run examples with distinct operation/occurrence/attempt/result IDs, versions and capabilities; demonstrate an internal-step seam without copying the flow engine | Workbench decoder/reducer fixtures; example design/constraint selection |
| Durable catalog and outer observation | Explicit stores, list/inspect, early request correlation, stored operation outcomes, consistent snapshot/cursor and replay; late independent readers observe two runs | Workbench P1 adapter/P2 derived catalog and early run display |
| Internal step lifecycle | Actual starts/completions/failures/skips/interruption and repeated occurrences, including deferred errors; earlier steps visible while a later one runs | Workbench execution feature/views |
| Incremental results | Synthesis resources, then one intermediate timing result, then checks; origin/constraints/corner/units preserved and data complete before publication | Workbench timing/resources/check projections |
| Preservation and installed acceptance | History and referenced evidence survive later failure, archive/restore and scratch cleanup; independent readers, conflicting operations, duplicate/truncated updates and crash tests | Workbench restart/reconnect and cache invalidation |
| Real specimen handoff | Validate actual supported runtime/container and descendant cancellation; retain final-JSON compatibility and existing acceptance policy | Example pins deliberate provider revision, supplies real flow/test evidence; Workbench live acceptance |

The contract/probe must settle writer ownership/locking, ordering, snapshot/cursor
consistency, duplicate requests/updates, incomplete writes, stale producers and
preservation policy before durable implementation. There is no chosen interception
mechanism yet. Metric equality cannot establish measurement origin. Archive policy
must cover advertised evidence, not just final metrics. Failed-run diagnostics
need an explicit export contract separate from completed-run archives.

Example fixture: build B has runs R1/R2. R1 publishes synthesis and intermediate
timing, then fails routing; R2 skips a gated step and is interrupted at a later
occurrence. A later collection attempt revises R1 without rerunning implementation.
Include inherited timing and equal-valued new measurements with different origins.

## Dependency triage

| Milestone | Genuine blockers |
| --- | --- |
| Contract fixtures, Workbench reducers/window behavior | Agreed identity/state examples; not P6 completion or a real EDA environment |
| Example Dune/design/unit tests | FIFO behavior, installed OCaml dependencies and chosen development library resolution; no PDK required |
| Early discovery and coarse live progress | Catalog/correlation/durable outer observation |
| Truthful internal progress | Demonstrated LibreLane seam; file absence alone is insufficient |
| Intermediate timing/resources | Step-aware extraction, producer provenance and complete snapshot publication |
| Dependable installed provider release | Applicable P6.5/P6.6 gates plus new installed observation acceptance |
| Real-flow handoff | Usable supported runtime, example pin/constraints and real evidence; local Python 3.12 source inspection does not validate requested 3.11 execution |

ASIC P6.5a does not technically block observation prototypes. P6.5b needs its
identity, while P6.5c may progress independently. Old consumer migration, SRAM,
Nix environment redesign and unrelated tool fixes are not blanket prerequisites.

## ASIC P7, S and T — retained independent tracks

**P7.1–P7.6:** retain their original migration goals and M4 relationship in the
[historical definitions](archive/phase-plan-through-p6.4b.md#12-p7--consumer-migration-and-legacy-retirement).
P7.1 installs the consumer's recorded revision; P7.2 replaces vendored operations;
P7.3 migrates coverage before deletion; P7.4 makes adopted checks routine; P7.5
validates synthesis/full/restoration; P7.6 closes migration documentation.
They are deferred for that consumer, not renamed as the new example's tasks.

**S.1–S.4:** capability inventory, behavioral/target compatibility, bounded flow
feasibility, then a conditional exact backend. The [SRAM area](sram/README.md)
retains detailed gate status and all investigations. S.3's acceptance allows a
qualified feasibility or evidence-backed deferral decision; it is not signoff.

**T.1:** correct the upstream ABC driving-cell constraint boundary (cell name vs
OpenSTA-style cell/pin), with a focused regression, explicit corrected revision
and mapped-synthesis comparison. Historical area results retain their stated
qualification. It blocks only measurements demonstrably dependent on that defect;
no shared venv patch or silent baseline pin advance.

## Recording future work

Keep completed IDs and evidence links stable. Add acceptance to the owning task
when work lands; do not create another session handoff/status queue. Ordinary
tests stay PDK-free; physical acceptance is explicit and separately recorded.
New provider phases and the first example implementation await this design review.

### Consolidation verification

2026-10-12: read-only documentation audit checked local Markdown targets and
heading anchors, the presence of all 29 relocated originals, unchanged bytes of
both historical PDFs, and identical executable source content after excluding
comments/docstrings. The 17 unavailable external targets are historical scaf
references; no replacement evidence was invented. `git diff --check` passes.
No build, unit suite, provisioning or EDA flow was run for this documentation pass.
