# Documentation

## Returning to the project

1. **[Phase plan](phase_plan.md)** — current status, what is next, dependencies and
   links to completion evidence. This is the only active implementation queue.
2. **[Architecture](architecture.md)** — ownership, implemented boundaries and the
   proposed provider/refactoring direction. Read this before changing an interface.
3. **[User workflow](guides/usage.md)** — how to use the existing library and CLI.

Current checkpoint (2026-10-12): ASIC P0–P5/M3 and P6.1–P6.3/P6.4a/b have
evidence. Lexical venv interpreter paths, bounded provisioning readiness,
`provision --python BASE` and thin example bootstrap are delivered
([current acceptance](phase_plan.md#tool-environment-closeout-acceptance)); broader
P6.5c and P6.5/P6.6 gates remain open. The provisional synthetic
[provider observation fixtures/model](../test/fixtures/provider_observation/v1/README.md)
are implemented: 50 focused tests and the full provider regression suite pass
([evidence](phase_plan.md#provider-observation-fixture-acceptance)). The subsequently
authorized [LibreLane feasibility probe](../experiments/librelane_observation/README.md)
is **BLOCKED**: the prior probe found missing Tcl/Tk support in local Python
3.12.3, and current readiness rejects the Python 3.11 mismatch first. Zero of eleven
authored cases executed; the synthetic configuration remains unvalidated
([evidence](../evidence/librelane-observation/blocked-local.json)). Next is
user-authorized Python/Tcl prerequisite resolution and a bounded rerun; matching
LibreLane source metadata does not validate the requested Python 3.11 environment.
Project run routing needs separate agreement. Live catalog, early correlation,
step updates and incremental result publication remain undelivered.
The owner's [development specimen](../../hardcaml_asic_example/README.md) now has
the fixed FIFO contract/core, independent scoreboard, TT wrapper/declaration,
project-centered `describe|emit` CLI and PDK-free generated-RTL acceptance.
The consumer owns `Fifo_asic.project ()`; the provider owns shared
`Project.emit_bundle`. Description is a local declaration S-expression, not a
Workbench protocol; runtime project `run`/`inspect` commands are not delivered.
See [entrypoint usage and regression coverage](guides/bundle-emission.md#project-centered-entry-point).
A recorded ASIC baseline
and explicit development override now support isolated library/CLI refresh,
activation, plain builds and real-checkout emitter acceptance; see the
[commands](development/consumer-dependency-workflow.md#implemented-commands) and
[project-entrypoint acceptance](phase_plan.md#project-centered-entrypoint-acceptance).
The recorded `171476...` baseline cannot supply the new API: current recorded
refresh is refused while development refresh works. A compatible committed
candidate must be adopted by the owner. Full environment locking, P6 source stamping,
source-access-denied installation and physical acceptance remain open.
The old scaf checkout is absent and not required.

The public lifecycle now uses `Elaborated_project` and `Resolved_flow`; see the
[source-breaking migration and acceptance](phase_plan.md#public-api-rename-migration-and-evidence).
Historical records retain their original API names and commands.

## Where things live

| Area | Purpose | Start here |
| --- | --- | --- |
| Root | Governing architecture and current queue | The two documents above |
| `guides/` | Operating instructions for implemented behavior | [Usage](guides/usage.md) |
| `reference/` | Normative resource/target contracts | [Memory](reference/program-memory-contract.md), [TT/CMOS5L](reference/target-reference.md) |
| `development/` | Coding conventions and detailed active work specifications | [Conventions](development/comment_guidelines.md), [Consumer dependency workflow](development/consumer-dependency-workflow.md), [P6 details](development/p6-implementation-plan.md) |
| `sram/` | Separate SRAM capability investigation and its evidence interpretations | [SRAM index](sram/README.md) |
| `backlog/` | Explicitly deferred scope and reactivation conditions | [Backlog](backlog/README.md) |
| `archive/` | Superseded plans, handoffs, original proposals and completion history | [Archive index](archive/README.md) |

### Operating guides

- [Installation](guides/consumer-installation.md): one pinned library/CLI artifact.
- [Memory example](guides/memory-example.md): PDK-free behavioral/flop checks.
- [Bundle emission](guides/bundle-emission.md): RTL, constraints and immutable inputs.
- [Toolchain setup](guides/bootstrap.md#tool-directory-ownership): configurable
  collateral root, separate provider/host/container/Nix/run storage, and dated
   local findings, plus [activate-then-check commands](guides/bootstrap.md#consumer-check).
- [Execution and results](guides/flow.md): run, postcheck, collect, report, archive.

## Documentation rules

- Update status and next work in `phase_plan.md`; do not add another status/handoff
  document or an `immediate_future` queue. Detailed work specs link back to it.
- Architecture distinguishes implemented behavior, settled ownership and proposals.
- Preserve completed task IDs and evidence. Archive superseded instructions with
  a status banner; historical commands/revisions are records, not current setup.
- Put source-level rules in references and commands in guides. Link rather than
  duplicate their content across plans.
- Existing `scaf` links in historical evidence and contract rationale may be
  unavailable locally. They preserve attribution, not a development prerequisite.
- Workbench has its own independent phase numbering. Always say **ASIC P6** or
  **Workbench P6** when referring across repositories.
