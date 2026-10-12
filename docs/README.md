# Documentation

## Returning to the project

1. **[Phase plan](phase_plan.md)** — current status, what is next, dependencies and
   links to completion evidence. This is the only active implementation queue.
2. **[Architecture](architecture.md)** — ownership, implemented boundaries and the
   proposed provider/refactoring direction. Read this before changing an interface.
3. **[User workflow](guides/usage.md)** — how to use the existing library and CLI.

Current checkpoint (2026-10-12): ASIC P0–P5/M3 and P6.1–P6.3/P6.4a/b have
evidence. P6.5/P6.6 remain open. Incremental provider observation is proposed,
not delivered; concrete provider observation contract examples are next work.
The owner's [development specimen](../../hardcaml_asic_example/README.md) now has
the fixed FIFO contract/core, independent scoreboard, TT wrapper/declaration,
bundle emitter and PDK-free generated-RTL acceptance. It remains unpinned and
does not establish independent installed-provider or physical acceptance; see
the [recorded evidence](phase_plan.md#controlled-fifo-development-specimen-evidence).
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
| `development/` | Coding conventions and detailed active work specifications | [Conventions](development/comment_guidelines.md), [P6 details](development/p6-implementation-plan.md) |
| `sram/` | Separate SRAM capability investigation and its evidence interpretations | [SRAM index](sram/README.md) |
| `backlog/` | Explicitly deferred scope and reactivation conditions | [Backlog](backlog/README.md) |
| `archive/` | Superseded plans, handoffs, original proposals and completion history | [Archive index](archive/README.md) |

### Operating guides

- [Installation](guides/consumer-installation.md): one pinned library/CLI artifact.
- [Memory example](guides/memory-example.md): PDK-free behavioral/flop checks.
- [Bundle emission](guides/bundle-emission.md): RTL, constraints and immutable inputs.
- [Toolchain setup](guides/bootstrap.md): explicit external provisioning.
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
