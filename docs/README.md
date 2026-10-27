# Documentation

Index of the `hardcaml_asic` docs. For an overview of the package, scope and
quick start, see the [repository README](../README.md).

## Start here

1. **[Phase plan](phase_plan.md)**: Protemu-focused SRAM, resource inspection,
   timing and configuration-study work (ASIC PT.0–PT.8), dependencies,
   and links to completion evidence. It is the **only** active implementation
   queue; other documents link back to it rather than tracking status
   themselves.
2. **[Architecture](architecture.md)**: ownership, dependency direction and the
   boundaries that are implemented versus proposed. Read it before changing an
   interface.
3. **[User workflow](guides/usage.md)**: the end-to-end path from a Hardcaml
   design to preserved evidence.

## Guides

How to use behavior that is implemented now.

| Guide | Covers |
| --- | --- |
| [User workflow](guides/usage.md) | Declare, simulate, emit, provision, run, collect, interpret and archive |
| [Consumer installation](guides/consumer-installation.md) | Pinning one library/CLI revision, the installed layout, CLI contract 4 migration, collateral resolution |
| [Bootstrapping](guides/bootstrap.md) | `bootstrap.sh` / `provision`, tool-root ownership, readiness checks, pins and troubleshooting |
| [Bundle emission](guides/bundle-emission.md) | The project-centered entry point, bundle layout, identity and provenance |
| [Memory example](guides/memory-example.md) | PDK-free behavioral and flop checks for `Single_port_ram` |
| [Resource preparation](guides/resource-preparation.md) | Project-owned durable Elaborate & Resolve operation, identities, cancellation and historical CLI inspection |
| [Resource realization](guides/resource-realization.md) | Bundle-owned expectations, read-only synthesis/physical reconciliation, resource-aware area/count semantics and acceptance |
| [Execution and results](guides/flow.md) | Command and storage defaults, run/postcheck/collect/report/archive, observation schemas, runtime policy, finalization |
| [Stage quickstart](guides/stage-quickstart.md) | Explicit six-stage runs, checkpoints, restart, live watch and reporting |
| [OCaml stage recipes](guides/ocaml-stage-recipes.md) | Typed `Flow.Stage` / `Flow.Recipe` declarations and schema-3 Python interoperability |
| [Named flows](guides/named-flows.md) | Project flow catalogs and parameter profiles: discover, describe, preview, run, observe, report |

## References

Normative contracts; guides link here rather than restating them.

- [TT/CMOS5L target](reference/target-reference.md): the accepted TT boundary,
  timing subset, protected settings and optional helpers.
- [Program memory contract](reference/program-memory-contract.md): the
  normative behavior of `Single_port_ram`.
- [Native historical methodology](reference/native-historical-methodology.md):
  the `methodology` payloads that `report` and `observation inspect` add for
  named executions.

## Design and development records

Detailed specifications and evidence for individual features. Each one defers
to the phase plan for current status.

**Flow infrastructure**

- [OCaml-first flow infrastructure](flow-infrastructure-refactor.md): the
  destination design for native execution and stage decomposition.
  [Implementation record](development/flow-infrastructure-progress.md).
- [Explicit stages and execution plans](development/explicit-stage-refactor.md)
- [Project flow catalog and named methodologies](development/project-flow-catalog.md).
  [Implementation record](development/project-flow-catalog-progress.md).
- [Checkpoint and stage reporting](development/checkpoint-reporting.md)

**Observation and output**

- [Default flow journal and foreground watch](development/flow-journal.md)
- [Journal event timing and live observation](development/journal-event-timing.md)
- [Human-readable flow output](development/human-readable-flow-output.md):
  contract 3 history, kept for reference.

**Consumers, packaging and Workbench**

- [Resource preparation implementation](development/resource-preparation.md):
  PT.4 operation/snapshot design, agent assignments, lifecycle review and CLI-only
  independent-consumer acceptance.
- [Resource realization implementation](development/resource-realization-plan.md):
  PT.5 design, bundle/execution handoffs, independent review corrections and retained
  example acceptance; outstanding measurement attribution remains in the phase plan.
- [SRAM physical integration](development/sram-example-physical.md): current
  accepted example, power/electrical/checker fixes, retained evidence and limits.
- [SRAM example integration](development/sram-example-integration.md): current
  production-style testbed work, architectural ownership, blog findings and
  agent-sized backend/flow/consumer assignments.
- [PT.0 implementation](development/pt0-implementation.md): agent-sized SRAM
  correction/testbed work, actual checks and remaining physical findings.
- [Consumer dependency workflow](development/consumer-dependency-workflow.md):
  how `hardcaml_asic_example` refreshes and activates a provider revision.
- [ASIC P6 implementation plan](development/p6-implementation-plan.md): the
  shared-tooling distribution spec and its open P6.5/P6.6 gates.
- [ASIC/Workbench execution boundary](development/workbench-execution-boundary.md):
  persisted journals versus live UI events, cancellation and daemon failure.
  Mostly proposed.

**Conventions**

- [Comment and formatting guidelines](development/comment_guidelines.md)

**Source layout**

- [`lib/` namespace reorganization](development/lib-namespace-reorganization.md):
  the move of `flow_domain/` and `execution/` to the repo root and the qualified
  `lib/` groups. Implemented 2026-10-15.

## Separate tracks

| Area | Purpose |
| --- | --- |
| [SRAM investigation](sram/README.md) | Capability evidence and known probe findings; production work is now in the active PT.0–PT.2 queue. |
| [Backlog](backlog/README.md) | Explicitly deferred scope and what would reactivate it |
| [Archive](archive/README.md) | Superseded plans, handoffs, original proposals and completion history |

[`guides/end_to_end_flow_explanation.md`](guides/end_to_end_flow_explanation.md)
is an unfinished conceptual draft and is not yet part of the guide set.

## Evidence

Curated run records live in [`../evidence/`](../evidence/), and the phase plan
links to them. The most relevant current records:

- [Native six-stage physical run and external acceptance](../evidence/librelane-observation/native-final-integration.json)
- [Reduced-install integration](../evidence/librelane-observation/reduced-install-real-integration.json)
- [Named-flow synthesis for two profiles](../evidence/namedflow/20261015-real-synthesis.json)
- [Managed Python/Tcl runtime](../evidence/managed-python/actual-runtime.json)
- Historical [P4 memory synthesis](../evidence/p4/memory-synthesis/README.md) and
  [observable physical](../evidence/p4/observable-physical/README.md) runs

## Documentation rules

- Record status and next work in `phase_plan.md`. Do not add another status or
  handoff document, or an `immediate_future` queue; detailed work specs link
  back to the plan.
- Architecture distinguishes implemented behavior, settled ownership and
  proposals.
- Preserve completed task IDs and evidence. Archive superseded instructions with
  a status banner. Historical commands and revisions are records, not current
  setup.
- Source-level rules go in references and commands go in guides. Link instead of
  duplicating content across plans.
- `scaf` links in historical evidence and contract rationale may not resolve
  locally. They preserve attribution and are not a development prerequisite.
- Workbench numbers its phases independently. Always write **ASIC P6** or
  **Workbench P6** when referring across repositories.
