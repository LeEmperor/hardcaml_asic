# hardcaml_asic phase plan

**Current queue, adopted 2026-10-24: make the ASIC flow usable for
`hardcaml_protemu`'s SRAM-backed implementation and resource studies.**

This is the only active implementation queue. [Architecture](architecture.md)
owns boundaries; the [memory contract](reference/program-memory-contract.md)
owns RAM semantics. Detailed designs and evidence belong in `development/`,
`sram/`, and `evidence/`, linked from the relevant item here.

**Revised direction, 2026-10-24:** ongoing SRAM acceptance belongs in
`hardcaml_asic_example` through public APIs. The old Verilog probe remains a
diagnostic/history artifact. Do not add architectural registers or change latency
implicitly; permit recorded behavior-preserving physical optimization. The
[example integration plan](development/sram-example-integration.md) records the
agent assignments and blog-backed KLayout/CDL checking approach.

The previous plan is preserved in the [2026-10-24 archive](archive/phase-plan-2026-10-24.md),
including completed milestones, open P6 gates, and the former next steps.
Archiving an open item does not complete it. New work uses **ASIC PT.0–PT.8**
to avoid renumbering historical ASIC P/S tasks or Protemu's own phases.

## Current baseline

- Project/resource declaration, behavioral and flop RAM implementations, immutable
  bundles, execution/reporting/acceptance, explicit stages, and named flow profiles
  are delivered. Their evidence remains in the archives.
- Protemu's `bin/asic_bundle.ml` registers `program` as 256×16, 1RW, latency one,
  currently with explicit `Flops` policy. Its emitter still uses
  `Bundle.render ~simulation_build`; current ASIC uses `~simulation_project`.
- CMOS5L now has an exact 256×16 SRAM mapping, role-complete collateral and fresh
  synthesis/full support. The independent example passes physical/electrical
  acceptance, TT precheck and final-gate functional replay while retaining one SRAM
  and its original 16 staging flops. Macro checkpoints and timed-model conformance
  remain open.
- SRAM S.1 inventory, S.2a functional-model tests, and qualified S.3 physical
  feasibility have evidence. The [October 23 checkpoint](sram/sram-status.md#2026-10-23-update)
  resolves eligibility and records the support-tools marker fix. Production
  physical support is demonstrated for the exact example profile; timed-model
  conformance remains open. Earlier authority-gate wording
  in historical records is superseded by that update.
- Workbench already has flow integration, synthesis cell tables, timing and
  physical inspection. The new work is logical-resource mapping and its connection
  to implementation evidence; see its [current overview](../../hardcaml_workbench/README.md).

Current implementation evidence is in the [physical closeout](development/sram-example-physical.md#implementation--execution-record)
and [earlier synthesis record](development/sram-example-integration.md#evidence).

## Ownership

| Owner | Responsibility |
| --- | --- |
| `hardcaml_asic` | Resource contracts and selection, macro wrappers/collateral, physical and timing intent validation, backend rendering, mapping evidence, public inspection interfaces |
| `hardcaml_protemu` | Hardware parameters, program packing, loading/fetch validity, synchronization architecture, project policy/placement/constraints, workloads and whole-system verification |
| `hardcaml_workbench` | Discovery and presentation of ASIC-owned data; resource browsing, comparison and user controls through public provider interfaces |

ASIC must remain usable headlessly and must not depend on Workbench. Cross-repo
items below are coordination deliverables; their implementation lives with the
named owner and does not reuse that repository's phase IDs.

## Active queue

| Order | Item | Dependencies | State |
| --- | --- | --- | --- |
| 1 | PT.0 — Repair and refresh SRAM feasibility evidence | Existing S.3 records | Complete in revised example-centered scope; historical probe qualifications retained |
| 2 | PT.1 — Exact production SRAM backend | PT.0 corrected power/corner findings | PT.1a–c complete; timed-model conformance open |
| 3 | PT.2 — Macro collateral and physical controls | PT.1 mapping/wrapper contract | Complete for stock 256×16/R0 fresh full profile; example acceptance passed |
| 4 | PT.3 — Macro-backed Protemu acceptance | PT.1–PT.2; consumer API migration | Pending |
| 5 | PT.4 — Resource-mapping inspection API | Existing records; PT.1–PT.2 for macro fields | Pending |
| 6 | PT.5 — Requested-versus-realized resource checks | PT.2, PT.4 | Pending |
| 7 | PT.6 — Workbench resource inspector | PT.4; PT.5 for realized evidence | Pending |
| 8 | PT.7 — Synchronizer/reset-aware timing declarations | Endpoint reference design and Protemu timing review | Pending |
| 9 | PT.8 — Reproducible design-variant comparisons | PT.3–PT.5; PT.7 for final physical selection | Pending |

This is the preferred execution order, not a requirement to serialize design
work. PT.4 can begin against existing flop records; PT.7 can begin independently.
PT.3 can establish functional integration before PT.7, but final Protemu physical
selection requires reviewed timing constraints. Workbench is optional for all
headless acceptance. Serialize Dune builds with `-j 20` and keep external-tool
resource use within the same shared budget.

## PT.0 — Repair and refresh SRAM feasibility evidence

**Owner: ASIC. First bounded task: correct the S.3 power bridges and corner map.**

Implementation started 2026-10-24; see the [agent-sized implementation plan](development/pt0-implementation.md)
for assignments, the `hardcaml_asic_example` testbed, resource limits and evidence.

- [x] **PT.0a — Power access.** Correct the two misplaced VPWR bridge rectangles;
  re-extract and verify adequate contact to both positive supply pins and ground.
  Completed 2026-10-24: emitted GDS/DEF show 1.95 µm positive-pin contact and
  0.28 µm adjacent-ground clearance; zero extraction overlap and correct extracted
  supplies. The first proposed shift exposed a real spacing defect, corrected by
  narrowing both bridges. [Evidence](../evidence/sram-pt0/README.md).
- [x] **PT.0b — Corner binding.** Replace ambiguous corner globs with validated
  mappings. Record the actual macro Liberty loaded in every STA corner, including
  the standard-cell/macro fast-corner temperature difference; rerun affected STA.
  Completed 2026-10-24: exact single-match libraries confirmed in corner-only and
  fresh physical STA; setup/hold pass in every corner. Fast −40/−55 °C model
  difference remains explicit. [Evidence](../evidence/sram-pt0/README.md#corners-and-timing).
- [x] **PT.0c — Residuals and retained evidence.** Reassess macro-boundary slew/cap
  violations with correct corners and buffer/resize as necessary. Recheck the
  LEF-obstruction DRC finding against real GDS. Preserve routed DEF, P&R netlist,
  extracted SPICE, reports, exact inputs and restoration instructions in a new
  evidence set; retain the original archive and digest unchanged.
  Partial 2026-10-24: a verified/restored 8.38 MB evidence archive now retains the
  required physical views and attribution runs; all nine current TT prechecks
  pass. Fresh flow exits 2 on three abstract Magic M3.f markers. Slew violations
  remain (fast/slow/typical: 12/25/21), with 12 capacitance violations per corner.
  Retained-GDS Magic reports 29,294 macro-internal findings requiring a deck/model
  disposition in that historical probe. **Closed 2026-10-25 in the revised public
  example scope:** all-corner slew/cap pass without changed limits or registers;
  real-GDS KLayout is clean; three abstract Magic markers have exact layer-control
  disposition; power/LVS and external TT/gate checks pass. The original probe is
  not relabeled as clean. [Closeout and retained evidence](development/sram-example-physical.md).

The [example's registered-memory specimen](../../hardcaml_asic_example/memory/README.md)
now exercises public Exact selection, actual vendor-functional RTL and the
technology-mapped and routed netlists. Unsupported shapes still fail explicitly.
Physical acceptance now applies to its exact stock R0 profile, not arbitrary memories.

**Exit:** the known probe defects have corrected, reproducible evidence, with
remaining findings explicitly dispositioned. This supplements S.3's qualified
closure; it does not relabel that historical probe as production acceptance.
Use the [S.3 disposition](sram/sram-s3-disposition.md) for technical detail and
the October 23 checkpoint for current authority/pin context.

## PT.1 — Exact production SRAM backend

**Owner: ASIC. Implements the production mapping portion of historical S.4.**

- [x] **PT.1a — Mapping and wrapper.** Map the existing 256×16 latency-one 1RW
  request exactly to `RM_IHPSG13_1P_256x16_c2_bm_bist`. Implement enables,
  whole-word mask and BIST/test tie-offs, with stable wrapper/instance names.
- [x] **PT.1b — Contract conformance.** Run the shared contract suite against the
  behavioral, flop and actual macro functional models. Compare only defined
  results; check each backend's own hold behavior after writes and disabled cycles.
  Preserve no reset, no initialization, and simulation-only poison behavior.
- [x] **PT.1c — Selection diagnostics.** Exercise `Exact`, explicit `Flops`, and
  explicitly permitted fallback. Unsupported contracts fail under `Exact`;
  fallback records its reason. No silent dimension rounding or macro composition.
  PT.1a–c completed 2026-10-24: canonical request, injective resource names,
  direct macro instantiation without new registers, three-backend contract replay
  (2,307 edges each), unsupported-shape/fallback diagnostics, independent example
  RTL and mapped-netlist replay. [Record](development/sram-example-integration.md#evidence).
- [ ] **PT.1d — Timed-model conformance.** Establish a simulator path that executes
  the macro's delayed timing checks, with positive and intentional-violation
  cases. Keep this evidence separate from functional tests and Liberty STA.

**Exit:** supported exact requests elaborate to the production wrapper and pass
backend conformance, including the timed-model obligation. Functional-only support
may be recorded as partial progress, not completion. PT.2 engineering can proceed
while PT.1d remains open. Update the memory reference's stale capability/status
wording when adopting the backend, without changing its settled semantics.

## PT.2 — Macro collateral and physical controls

**Owner: ASIC; project settings supplied by Protemu.**

- [x] **PT.2a — Collateral lifecycle.** Register, resolve, validate and identify
  synthesis black boxes, functional/timed models, Liberty corners, LEF, GDS and
  CDL/SPICE. Keep simulation and synthesis source roles distinct. Resolve PDK
  files at the appropriate execution/preflight boundary, not ordinary elaboration.
  Completed 2026-10-24: generated synthesis stub, separate behavioral/functional/
  timed roles, exact corners and PDK-file identity checked at preflight and after
  execution. Runtime resource/instance consistency and mutation negatives pass.
- [x] **PT.2b — LibreLane integration.** Derive `MACROS`, corner bindings, layout
  assembly and macro-aware LVS inputs from registered resources. Connect
  `VDD!`/`VDDARRAY!` to `VPWR` and ground to `VGND` through the supported target
  integration. Record the accepted target assumptions and actual connectivity.
  Completed 2026-10-25: placement-aware edge power access verified in final GDS;
  exact corners, real-GDS KLayout and actual schematic CDL consumption verified.
  LVS scope is abstract macro-boundary/interconnect, not internal-device LVS.
- [x] **PT.2c — Placement intent.** Add resource-ID-keyed position, orientation,
  halo/clearance and supported power-grid controls. Validate target bounds,
  overlap, legal orientations and unknown resource references. Support multiple
  explicitly declared instances with distinct identities; start with manual placement.
  Completed for R0 with a common halo and the checked Metal4 edge-access strategy.
  Dynamic pin/grid/OBS validation rejects unsupported geometry. Multi-resource
  generation/negative fixtures pass; actual physical acceptance is one example macro.
- [x] **PT.2d — Physical acceptance.** Run a normal emitted macro bundle through
  synthesis, physical implementation, required checks and TT precheck using the
  current pinned support tools. Verify actual corner binding, power access,
  macro-boundary electrical limits and CDL-backed LVS. Preserve complete evidence.
  Completed 2026-10-25: run `be961b2c95f74c81ad6af81ca4d2b269`, external postcheck
  `0553f6d19c8f42d28c057fc65ed23510`, consumer audit and restored replay pass.
  Worst setup/hold: **11.246561 / 0.223533 ns**. Raw Magic=3, narrowly dispositioned;
  routing/KLayout/overlap/electrical/LVS/antenna checks pass. [Physical record](development/sram-example-physical.md).

**Exit:** the normal library/CLI path implements the exact macro reproducibly
without hand-editing emitted bundles or borrowing experimental configuration.
Missing collateral, ambiguous corners and invalid placement produce actionable errors.

## PT.3 — Macro-backed Protemu acceptance

**Owners: Protemu for adoption/system checks; ASIC for backend defects and evidence.**

- [ ] **PT.3a — Consumer adoption.** Migrate Protemu's emitter to the current public
  API and deliberately adopt a compatible dependency/toolchain revision. Preserve
  an explicit flop configuration and add an exact-SRAM configuration for `program`.
- [ ] **PT.3b — Real system regression.** Exercise the loader/core/program-store
  path: load, readback, fetch, stalls, reset/disable, image validity, rejected host
  accesses during execution, and independence from unspecified memory outputs.
  Verify both emitted source roles with the applicable models.
- [ ] **PT.3c — Implemented-design replay.** Run the actual macro-backed system
  through the adopted flow and replay its final netlist with the macro model.
  Record timing/check outcomes and any provisional constraint assumptions;
  an RTL-only fixture is not final-netlist evidence.

**Exit:** the actual Protemu system works with the selected SRAM and has linked
consumer/backend/run evidence. Final physical selection additionally requires
PT.7's reviewed constraints and PT.8's configuration decision. Historical small
observable-top and flop-memory measurements do not substitute for this gate.

## PT.4 — Resource-mapping inspection API

**Owner: ASIC. Extend existing records rather than introduce another selector.**

- [ ] **PT.4a — Pre-run inventory.** Expose a versioned, machine-readable
  CLI/provider view available without EDA: resource ID, requested contract,
  matched policy, selected implementation, fallback/rejection explanation,
  and actual elaboration role (behavioral versus selected implementation).
- [ ] **PT.4b — Physical linkage.** Include generated wrapper/macro instance
  identities, required collateral and corners, placement and supply intent.
  Distinguish unresolved references from validated files and measured facts.
- [ ] **PT.4c — Stable provenance.** Bind inspection to exact project/bundle
  identities; support deterministic output and historical inspection. Verify
  flop, macro, fallback and unsupported-selection cases headlessly.

**Exit:** a client can answer “what will `program` become, and why?” without
parsing RTL or running synthesis. Simulation inventory cannot be mistaken for
the implementation selected for fabrication.

## PT.5 — Requested-versus-realized resource checks

**Owner: ASIC; Workbench consumes the results.**

- [ ] **PT.5a — Reconciliation.** Check expected macro type/count/identity against
  synthesis and final physical instances. Report missing, unexpected, unresolved
  and optimized-away instances distinctly, retaining stage and producer identity.
- [ ] **PT.5b — Resource evidence.** Report macro versus standard-cell area,
  utilization and links to macro-boundary timing paths. Attribute flop-resource
  costs only where the mapping survives synthesis; otherwise report unavailable.
- [ ] **PT.5c — Acceptance integration.** Make required-macro mismatches fail the
  relevant implementation checks, with negative fixtures and actual-run evidence.

**Exit:** selected mapping and verified implementation are separate inspectable
facts. A declaration alone cannot establish that a run retained its SRAM.

## PT.6 — Workbench resource inspector

**Owner: Workbench; ASIC owns and tests the public data contract.**

- [ ] **PT.6a — Resource table.** Display resource identity, shape/contract, policy,
  implementation and selection reason, distinguishing explicit flops from fallback.
- [ ] **PT.6b — Drilldown.** Link a logical resource to its hierarchy, collateral,
  placement and realized-mapping/timing evidence; show unavailable or pending data.
- [ ] **PT.6c — Controls and comparison.** Compare two configurations/runs and
  expose project-supported selection controls through public preview/new-build
  interfaces. Do not mutate immutable bundles or duplicate selection logic in UI.

**Exit:** selecting `program` shows its contract, selected macro and whether the
chosen run actually retained it. The same facts remain available headlessly.

## PT.7 — Synchronizer/reset-aware timing declarations

**Owners: ASIC for validation/rendering; Protemu for circuit intent and review.**

- [ ] **PT.7a — Endpoint references.** Define stable port/register-pin references
  and verify their resolution after synthesis. Diagnose empty or ambiguous matches.
- [ ] **PT.7b — Narrow timing intent.** Support reasoned asynchronous-capture and
  reset exceptions plus supported synchronizer preservation attributes. Keep
  downstream synchronizer stages timed normally; no blanket chain false paths.
- [ ] **PT.7c — Reviewable evidence.** Emit the resolved exceptions and unconstrained
  path coverage. Review Protemu's protocol inputs, sampled host link, reset and
  board/pad I/O assumptions, then rerun affected physical checks.

**Exit:** Protemu's final implementation uses reviewed, traceable constraints,
not just the provisional blanket min/max I/O delays. Digital phase-sweep tests
and STA do not by themselves establish analog metastability reliability.

## PT.8 — Reproducible design-variant comparisons

**Owners: Protemu for variants/workloads; ASIC for identities/results;
Workbench for optional launch and comparison views.**

- [ ] **PT.8a — Variant declarations.** Parameterize supported memory shapes,
  packing/encoding, FIFO depths, engine configuration and clocks in Protemu.
  Record hardware parameters separately from resource policy and flow profiles.
  Reject unsupported exact mappings; larger/multiple-macro mappings require their
  own explicit capability and conformance work.
- [ ] **PT.8b — Comparable results.** Link firmware size, fetch counts, latency and
  throughput to the exact variant, bundle, flow profile and run. Compare mapped
  and physical area, slack, utilization and acceptance with consistent workloads;
  keep estimates, synthesis evidence and physical evidence distinct.
- [ ] **PT.8c — Selection gate.** Run promising candidates with PT.7 constraints,
  record resource/timing margin and choose the Protemu configuration. Rerun
  affected regressions and preserve reproducible inputs/results for that choice.

**Exit:** Protemu's P5 studies can compare explicit flops and supported SRAM
configurations without ad hoc edits or ambiguous provenance. Existing named-flow
profiles are reused rather than rebuilt as a second experiment system.

## Milestones

1. **Usable macro path:** PT.0–PT.3 complete; real Protemu requests and implements
   an exact SRAM through the ordinary flow, with backend/system acceptance.
2. **Inspectable mappings:** PT.4–PT.6 complete; Workbench and headless clients
   show requested, selected and realized resources with provenance.
3. **Physical selection ready:** PT.7–PT.8 complete; reviewed constraints and
   comparable workload/physical evidence support the selected configuration.

Automatic banking/shape adaptation, automatic floorplan optimization, SRAM-backed
tiny FIFOs/register files, new targets and general flow scheduling are outside this
queue unless a concrete consumer requirement promotes them.

## Previous work and retained obligations

The [archived queue](archive/phase-plan-2026-10-24.md#active-queue) retains
per-operation invocation, configuration-changing checkpoint reuse, consumer pin
adoption and source cleanup. These are deferred, not completion claims. Promote
only a concrete dependency of the PT work; record that decision here.

<a id="asic-p6--shared-tooling-distribution"></a>

**ASIC P6:** source-artifact identity, waiver/provisioning authority and independent
installation gates remain open at their [recorded status](archive/phase-plan-2026-10-24.md#asic-p6--shared-tooling-distribution).
Keep P6 IDs when resuming them. Packaging already delivered is not new PT work.

**ASIC P7/S/T:** [historical definitions and disposition](archive/phase-plan-2026-10-24.md#asic-p7-s-and-t--retained-independent-tracks)
remain available. PT.0 supplements S.3; PT.1–PT.2 deliver S.4's production work
without claiming the remaining S.2 timed-model gate passed. Reassess the ABC issue
only for measurements affected by it. See also the [backlog](backlog/README.md).

### Historical evidence links

Stable anchors below preserve incoming links from guides and sibling repositories;
each routes to the archived record rather than a second active queue.

<a id="ocaml-first-flow-infrastructure"></a>
<a id="explicit-stage-refactor-closeout"></a>
<a id="default-flow-journal-closeout"></a>
<a id="default-result-store-and-cli-2-closeout"></a>

- [Native execution and stage delivery](archive/phase-plan-2026-10-24.md#ocaml-first-flow-infrastructure),
  [stage closeout](archive/phase-plan-2026-10-24.md#explicit-stage-refactor-closeout),
  [journals](archive/phase-plan-2026-10-24.md#default-flow-journal-closeout),
  [result stores](archive/phase-plan-2026-10-24.md#default-result-store-and-cli-2-closeout).

<a id="hostcontainer-runtime-policy-closeout"></a>
<a id="tool-environment-closeout-acceptance"></a>
<a id="tool-environment-ownership-first-slice"></a>

- [Runtime policy](archive/phase-plan-2026-10-24.md#hostcontainer-runtime-policy-closeout),
  [tool environment](archive/phase-plan-2026-10-24.md#tool-environment-closeout-acceptance),
  [tool ownership](archive/phase-plan-2026-10-24.md#tool-environment-ownership-first-slice).

<a id="project-centered-entrypoint-acceptance"></a>
<a id="consumer-refresh-and-real-checkout-emitter-closeout"></a>
<a id="public-api-rename-migration-and-evidence"></a>
<a id="controlled-fifo-development-specimen-evidence"></a>

- [Project entry point](archive/phase-plan-2026-10-24.md#project-centered-entrypoint-acceptance),
  [consumer refresh](archive/phase-plan-2026-10-24.md#consumer-refresh-and-real-checkout-emitter-closeout),
  [API migration](archive/phase-plan-2026-10-24.md#public-api-rename-migration-and-evidence),
  [FIFO specimen](archive/phase-plan-2026-10-24.md#controlled-fifo-development-specimen-evidence).

<a id="resolved-build-boundary-hardening-evidence"></a>
<a id="provider-observation-fixture-acceptance"></a>
<a id="librelane-feasibility-probe-review"></a>

- [Resolved-build boundary](archive/phase-plan-2026-10-24.md#resolved-build-boundary-hardening-evidence),
  [observation fixture](archive/phase-plan-2026-10-24.md#provider-observation-fixture-acceptance),
  [initial LibreLane probe](archive/phase-plan-2026-10-24.md#librelane-feasibility-probe-review).

## Recording progress

- Mark an item complete only with its stated evidence; distinguish partial
  implementation, functional verification, physical execution and acceptance.
- Add dated evidence links beside completed PT items. Keep detailed commands,
  tool/source identities and findings in the relevant feature record.
- Keep ordinary tests PDK-free; run physical/model-tool acceptance explicitly.
- Preserve historical IDs and archived evidence. Update this queue when priorities
  change, and archive it before the next substantial replacement.
