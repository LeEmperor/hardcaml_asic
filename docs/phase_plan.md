# hardcaml_asic phase plan

This is the **only active queue**: current status, next work and open gates.
[Architecture](architecture.md) owns boundaries; feature design and evidence
records under `development/` own the detail and link back here.

Status as of **2026-10-15**. The full text of this plan before it was condensed,
with every dated closeout, command and identity, is preserved in the
[2026-10-15 snapshot](archive/phase-plan-2026-10-15.md). P0–P5 and the original
P6/P7/S/T definitions are in the [earlier archive](archive/phase-plan-through-p6.4b.md).

## Current status

| Capability | State | Evidence / detail |
| --- | --- | --- |
| Lifecycle, resources, bundle emission (ASIC P0–P5, M1–M3) | Complete | [Original records](archive/phase-plan-through-p6.4b.md) |
| Operation-aware acceptance, input-preserving archives, shared CLI, packaging (P6.1–P6.3, P6.4a/b) | Complete | [P6 below](#asic-p6--shared-tooling-distribution), [P6 details](development/p6-implementation-plan.md) |
| Source identity, waivers, provisioning authority, independent installation (P6.4 parent, P6.5, P6.6) | **Open** | [P6 below](#asic-p6--shared-tooling-distribution) |
| Native OCaml CLI and execution services | Delivered 2026-10-14 | [OCaml-first infrastructure](#ocaml-first-flow-infrastructure) |
| Explicit stages, checkpoints, journals, live watch, finalization | Delivered 2026-10-13 | [Explicit-stage closeout](#explicit-stage-refactor-closeout), [journal closeout](#default-flow-journal-closeout) |
| Named flows and parameter profiles | Delivered 2026-10-15 | [Named flows](guides/named-flows.md), [implementation record](development/project-flow-catalog-progress.md) |
| Default result stores, CLI contract 4, human/`--json` output | Delivered 2026-10-13 | [Result-store closeout](#default-result-store-and-cli-2-closeout), [flow guide](guides/flow.md#default-result-store-and-cli-contract-4) |
| Managed Python/Tcl, runtime policy, thin bootstrap | Delivered 2026-10-12; P6.5c partly addressed | [Tool environment](#tool-environment-closeout-acceptance), [runtime policy](#hostcontainer-runtime-policy-closeout) |
| Project-centered entry point and FIFO specimen | Delivered | [Entry point](#project-centered-entrypoint-acceptance), [specimen](#controlled-fifo-development-specimen-evidence) |
| Consumer refresh/activation | Delivered; committed pin not yet adopted | [Refresh closeout](#consumer-refresh-and-real-checkout-emitter-closeout) |
| Hardcaml Workbench integration | **Next** | [Active queue](#active-queue) |
| SRAM (ASIC S.1–S.4) | S.1/S.3 complete; S.2 open; S.4 gated | [SRAM index](sram/README.md) |
| Consumer migration (ASIC P7, M4) | Deferred | [Other tracks](#asic-p7-s-and-t--retained-independent-tracks) |

Latest physical evidence: a fresh installed consumer completed all six physical
stages in 1,617.5 s, then external finalization in 677.3 s. DRC/LVS/antenna, TT
precheck and the 11,429-row gate replay passed
([record](../evidence/librelane-observation/native-final-integration.json)).
Named-flow synthesis passed for `balanced` (AREA 0, 673 cells) and
`synth_delay` (DELAY 1, 685 cells)
([record](../evidence/namedflow/20261015-real-synthesis.json)). Neither is a
timing-improvement claim or a named full-flow acceptance.

## Active queue

In dependency order. Run one bounded implementation owner per dependent slice;
independent read-only review may run alongside it. Serialize Dune builds with
`-j 20` and keep external-tool resource limits within the same budget.

1. **Workbench active-flow integration.** Integrate Workbench's project-scoped
   active-flow selection as a client of the delivered public
   catalog/preview/execution interfaces. The provider must not depend on
   Workbench. Expand typed parameters only with explicit backend contracts.
2. **Per-operation backend invocation**, when needed. Start with the validated
   placement sequence; prove physical equivalence and the required checks.
   Independent step checkpoints need separate evidence.
3. **Configuration-changing checkpoint reuse**, with explicit dependency rules and
   lineage-aware finalization. This is separate from fresh profile runs.
4. **Source organization.** Finish hardware/project/resource directory organization
   independently of behavior (see the planned
   [`lib/` namespace reorganization](development/lib-namespace-reorganization.md)).
   Cleaning up retained Python reference sources is optional. Cosmetic
   reorganization is not a Workbench gate.

In parallel, not blocked by the above:

- **ASIC P6.5/P6.6** identity and installation gates ([below](#asic-p6--shared-tooling-distribution)).
- **Committed-pin adoption.** The example's recorded provider pin
  (`1714764…`) predates the current `Project` API, so recorded refresh is refused
  and development refresh is used. The owner must commit and adopt a compatible
  candidate.
- **`hardcaml_protemu` migration.** It still uses `Build` and `simulation_build`
  and needs a source migration before adopting this provider
  ([rename notes](#public-api-rename-migration-and-evidence)).

## OCaml-first flow infrastructure

Authorized 2026-10-13. The [design](flow-infrastructure-refactor.md) gives the
destination and the [implementation record](development/flow-infrastructure-progress.md)
holds APIs, commands, review findings and verification.

**Delivered:**

- Separate installed `hardcaml_asic.flow_domain` and `hardcaml_asic.execution`
  libraries; the hardware library takes on no execution dependencies.
- Six-stage domain modules, shared analysis contracts and a checked LibreLane
  mapping covering all 80 Classic occurrences.
- Native OCaml typed plans, identity JSON, versioned backend protocol, process
  supervision, Docker transport, runtime policy, atomic records, checkpoints and the
  explicit-stage runner.
- Native public `hardcaml-asic-flow` parsing, routing and every service: preflight,
  coarse run/execute, collect, report/acceptance, postcheck orchestration,
  finalization, archive, observation and watch. LibreLane and TT tools remain
  external and unchanged.
- Reduced installation: nine Python backend/probe/bootstrap modules and four data
  files. Sixteen retired Python service modules remain only as source references,
  and their installed imports are a deliberate Python API break; CLI contract 4 is
  unchanged.
- Named fixed-recipe flows and typed profiles (2026-10-15): project-owned
  catalogs, discover/describe/preview/run, pre-bundle effective settings and
  provenance, expected-identity enforcement, frozen historical methodology and a
  standalone headless client. See the [design record](development/project-flow-catalog.md).

**Not delivered:** arbitrary operation sequences, configuration-changing
checkpoint branches and a general DAG scheduler. Those are queue items 2–3 above.

Verification at delivery: forced `dune runtest -j 20` and 57 installed-prefix
tests passed; the physical and reduced-install evidence is listed in
[Current status](#current-status). The original detailed delivery text is in the
[snapshot](archive/phase-plan-2026-10-15.md#ocaml-first-flow-infrastructure).

## ASIC P6 — Shared tooling distribution

Keep existing IDs. The detailed acceptance matrix and original commands are in
[development/P6](development/p6-implementation-plan.md#7-ordered-bounded-implementation-units).

- [x] **P6.1** — Operation-aware reporting. Synthesis and full-flow policies remain
  distinct; missing/contradictory evidence cannot become a pass.
- [x] **P6.2** — Complete immutable-input archives with integrity and restoration.
- [x] **P6.3** — Shared installed-command contract and fixed execute semantics.
- [ ] **P6.4** — Installed CLI/runtime assets; **P6.4a/b delivered**, parent waits
  for P6.6a's filesystem source-denial check. Do not redo packaging.
- [ ] **P6.5a — Source-artifact identity.** One deterministic validated source stamp
  embedded in OCaml and Python, Git-free source builds and additive bundle
  `generator_identity`. Test clean/dirty/untracked/unknown inputs, actual opam
  source/export behavior, tampered inventory, determinism, library/CLI equality
  and manifest coverage. No runtime Git guessing or version-as-revision shortcut.
- [ ] **P6.5b — Dependency and waiver records.** After P6.5a: explicit expectations,
  generator/executor comparison, recorded exceptions and historical-read behavior.
  Old analysis does not require matching the current executor's identity. Preserve
  existing records through archive/restoration.
- [ ] **P6.5c — Provisioning/data authority.** Strict requested Python behavior,
  installed lock authority, explicit Docker/native scope and read-only/check/offline
  semantics. PDK-free stub tests prove no implicit network or writes in check mode;
  no baseline pin change is implied. *Partly addressed* by managed Python/Tcl,
  lexical interpreter paths, bounded readiness and thin bootstrap
  ([acceptance](#tool-environment-closeout-acceptance)).
- [ ] **P6.6a — Independent installation acceptance.** After P6.4b and P6.5a/b/c:
  fresh prefix, unrelated consumer, source access denied, positive/negative
  validation/report/archive/restoration and exact artifact identity. PDK-free.
- [ ] **P6.6b — Documentation and recorded candidate.** After P6.6a: align operating
  commands, run applicable build/test/package checks and record the deliberately
  published candidate. Commit/publication/pin changes remain explicit owner actions.

**P6 exit:** one identified source artifact installs library and generic flow
tooling, works independently of the checkout and preserves P6.1/P6.2 guarantees.

P6.5a does not block observation or Workbench work. P6.5b needs P6.5a's identity;
P6.5c can progress independently. Until P6.5, `--version` reports no source
revision and does not verify that the linked library matches the command.

## Known open scope

Recorded limits of delivered work. None is in the active queue unless promoted there.

- **Observation:** no store-wide catalog, idempotency or fencing; no fsync or
  power-loss guarantee; no crashed-writer reconciliation or execution
  takeover/recovery; no backend-step progress. Journals assume a trusted local
  filesystem with advisory locks; retention and cursors are caller-owned.
- **Workbench:** cancellation, daemon-crash process survival and live application
  acceptance are proposed
  ([execution boundary](development/workbench-execution-boundary.md)).
- **Execution:** no segmented artifact archive/GC; no resumed-attempt or standalone
  signoff finalization; one tested container image; no native/macro/other-image
  relocation.
- **Evidence:** six disconnected pins and one max-fanout violation in the physical
  run remain raw evidence outside the existing acceptance gates.
- **Failed-run diagnostics** need an export contract separate from completed-run
  archives.

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

Deferred scope with reactivation conditions is in the [backlog](backlog/README.md).

## Delivered milestones

One entry per closeout. Each **full record** link goes to the original text in
the 2026-10-15 snapshot, which keeps the exact commands, test counts, generations
and identities. Later entries supersede earlier qualifications only where they
say so.

### Default flow journal closeout

2026-10-13. CLI `stages` journals by default, with early allocation and flushed
allocation/terminal JSONL (contract 4). Foreground watch validates incremental
updates, and readers can stop and reconnect without controlling execution. The
example's `project run --endpoint` route requires contract 4. Journal schema 2
later added producer UTC and monotonic timestamps
([event timing](development/journal-event-timing.md)).
[Feature record](development/flow-journal.md) ·
[full record](archive/phase-plan-2026-10-15.md#default-flow-journal-closeout)

### Explicit-stage refactor closeout

2026-10-13. Shared coarse/explicit runner; six sequential physical boundaries;
schema-3 OCaml/Python recipes; exact-runtime, path-bound checkpoint publication
and restarts; observation; separate finalization using the existing acceptance
policy. Actual evidence:

| Record | Proven scope |
| --- | --- |
| [Blocked local probe](../evidence/librelane-observation/blocked-local.json) | Historical missing Tcl/Tk; zero of eleven authored cases in that attempt |
| [Slice 2](../evidence/librelane-observation/slice2-real.json) | 12 official-API cases; real synthesis → fresh physical handoff and bounded cancellation |
| [Slice 3](../evidence/librelane-observation/slice3-production.json) | Production checkpoint publication/runtime closure and synthesis resume |
| [Slice 4](../evidence/librelane-observation/slice4-physical.json) | Full six-stage physical execution |
| [Slice 5](../evidence/librelane-observation/slice5-observed.json) | Real observed synthesis/floorplan with independent cursor audit |
| [Slice 6](../evidence/librelane-observation/slice6-finalization.json) | Accepted finalization: nine TT checks and 11,429-edge replay |

[Refactor record](development/explicit-stage-refactor.md) ·
[full record](archive/phase-plan-2026-10-15.md#explicit-stage-refactor-closeout)

### Default result store and CLI 2 closeout

2026-10-13. Default `_flow_results/{bundles,runs,operations}` with verified
immutable publication/reuse, human-default output, explicit `--json`, and project
`describe|emit|preflight|run`. Contract 2 was later superseded by 3 (human
output for all commands) and 4 (default journals).
[Command/storage matrix](guides/flow.md#default-result-store-and-cli-contract-4) ·
[full record](archive/phase-plan-2026-10-15.md#default-result-store-and-cli-2-closeout)

### Host/container runtime-policy closeout

2026-10-12. Role-specific host/container runtime policy, shared readiness checks,
and observed image/engine launch binding. Bundles emitted under older semantics
must be emitted again, never edited.
[Runtime policy guide](guides/flow.md#runtime-policy-and-launch-binding) ·
[full record](archive/phase-plan-2026-10-15.md#hostcontainer-runtime-policy-closeout)

### Tool-environment closeout acceptance

2026-10-12. Managed CPython 3.11.17 / Tcl 9.0.4 by default, bounded read-only
readiness checks, `provision --python BASE`, and the example's thin bootstrap
with no copied pins or source fallback.
[Managed-runtime evidence](../evidence/managed-python/actual-runtime.json) ·
[bootstrap guide](guides/bootstrap.md) ·
[full record](archive/phase-plan-2026-10-15.md#tool-environment-closeout-acceptance)

### Tool-environment ownership: first slice

2026-10-12. Settled tool-root ownership (the consumer owns `_flow_tools/`) and
lexical interpreter paths, so explicit venv selections are no longer resolved
away to the system Python.
[Ownership and commands](guides/bootstrap.md#tool-directory-ownership) ·
[full record](archive/phase-plan-2026-10-15.md#tool-environment-ownership-first-slice)

### Project-centered entrypoint acceptance

2026-10-12. `Project.create ?source_inputs`, declaration-only `Project.describe`,
and shared `Project.emit_bundle`. The FIFO consumer owns `Fifo_asic.project ()`
and its `bin/project.exe` CLI.
[Bundle guide](guides/bundle-emission.md#project-centered-entry-point) ·
[full record](archive/phase-plan-2026-10-15.md#project-centered-entrypoint-acceptance)

### Consumer refresh and real-checkout emitter closeout

2026-10-12. `scripts/asic_dependency.py` in the example installs the library and
CLI into isolated, atomically selected generations in recorded or development
mode. Real-checkout emission was accepted.
[Commands](development/consumer-dependency-workflow.md#implemented-commands) ·
[full record](archive/phase-plan-2026-10-15.md#consumer-refresh-and-real-checkout-emitter-closeout)

### Public API rename: migration and evidence

2026-10-12. Source-breaking, with **no compatibility aliases**:

| Previous OCaml API | Current OCaml API |
| --- | --- |
| `Build` | `Elaborated_project` |
| `Resolved_build` | `Resolved_flow` |
| Resolved record field `build` | `elaborated_project` |
| `Bundle.render ?simulation_build` | `Bundle.render ?simulation_project` |

`Project.elaborate`, `Project.elaborate_for_flow` and `Target.Resolved` keep
their names. Persisted identities, schemas and hashing are unchanged. Old and new
emitters produced byte-identical bundles. The current external checker is
`python3 test/check_resolved_flow_api.py --baseline-emitter PATH`.
`hardcaml_protemu` still needs its own migration.
[Full record](archive/phase-plan-2026-10-15.md#public-api-rename-migration-and-evidence)

### Controlled-FIFO development-specimen evidence

2026-10-12. The sibling example delivered the 16×8 controlled-FIFO contract/core,
an independent scoreboard, the TT wrapper/declaration and PDK-free generated-RTL
acceptance. Its early unpinned and manual-override qualifications were superseded
by the refresh closeout.
[Consumer README](../../hardcaml_asic_example/README.md) ·
[full record](archive/phase-plan-2026-10-15.md#controlled-fifo-development-specimen-evidence)

### Resolved-build boundary-hardening evidence

2026-10-12. Resolved results became private records that only resolution can
construct. Before/after emitters produced byte-identical bundles. The record
uses the pre-rename names.
[Full record](archive/phase-plan-2026-10-15.md#resolved-build-boundary-hardening-evidence)

### Provider observation fixture acceptance

2026-10-12. A provisional, test-only synthetic observation contract and
validator/replayer (50 tests). It adds no installed capability; live
per-attempt observation came later with explicit stages.
[Fixtures](../test/fixtures/provider_observation/v1/README.md) ·
[full record](archive/phase-plan-2026-10-15.md#provider-observation-fixture-acceptance)

### LibreLane feasibility probe review

2026-10-12. The first official-API probe was **BLOCKED** by missing Tcl/Tk in
local Python 3.12.3, so zero cases ran. That record is kept unchanged; later
managed runtimes and selected-image official cases succeeded.
[Experiment](../experiments/librelane_observation/README.md) ·
[full record](archive/phase-plan-2026-10-15.md#librelane-feasibility-probe-review)

## Recording future work

- Update this plan when work lands or priorities change. Do not create another
  status, handoff or `immediate_future` document.
- Keep completed task IDs and evidence links stable. Put detailed evidence (exact
  commands, counts, generations, identities) in the feature's `development/`
  record or `evidence/`. Add a short entry under
  [Delivered milestones](#delivered-milestones) that links to it.
- Ordinary tests stay PDK-free. Physical acceptance is explicit and recorded
  separately.
- When this plan is condensed again, archive the previous full text first, as
  with the [2026-10-15 snapshot](archive/phase-plan-2026-10-15.md).
- Workbench numbers its phases independently. Write **ASIC P6** or
  **Workbench P6** when referring across repositories.
