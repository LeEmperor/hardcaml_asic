# hardcaml_asic

An OCaml/Hardcaml library and installed flow CLI for ASIC design resources,
reproducible implementation inputs and traceable results. The supported path is
Tiny Tapeout 6x4 / IHP CMOS5L / LibreLane, with behavioral and explicit flop memory.

## Start here

- **Developing:** [current phase plan](docs/phase_plan.md) and
  [architecture](docs/architecture.md).
- **Using the library/CLI:** [user workflow](docs/guides/usage.md),
  [installation](docs/guides/consumer-installation.md),
  [execution/results](docs/guides/flow.md).
- **Finding a document:** [documentation index](docs/README.md), including
  separate references, SRAM investigations, backlog and historical archives.

ASIC P0–P5/M3 and P6.1–P6.3/P6.4a/b have delivery evidence. One package installs
the OCaml library and `hardcaml-asic-flow`; repository scripts are development
adapters onto the same implementation. Source-artifact identity and remaining
independent-installation gates are open under ASIC P6.5/P6.6. Incremental provider
observation for Hardcaml Workbench is proposed, not implemented.

The owner-created sibling [hardcaml_asic_example](../hardcaml_asic_example/README.md)
now delivers the fixed 16×8 controlled-FIFO contract/core, independent scoreboard,
TT wrapper/declaration, bundle emitter and PDK-free generated-RTL acceptance.
It uses a recorded ASIC baseline plus an explicit development override through
consumer-owned refresh/activation. Both library and CLI install into isolated
generations; activated plain builds and real-checkout emission have passed.
See the [commands](docs/development/consumer-dependency-workflow.md#implemented-commands)
and [closeout evidence](docs/phase_plan.md#consumer-refresh-and-real-checkout-emitter-closeout).
The consumer record awaits owner commit; full environment locking, P6 source
stamping/source-denied installation and physical acceptance remain open.
Provider observation contract examples are next work. The historical scaf worktree
is absent and not a prerequisite.

## Existing workflow

The public CLI and explicit/coarse execution, result collection/reporting,
postcheck/finalization, archiving, checkpoints, journaling and watch now use OCaml.
Installed Python is limited to LibreLane adapter, probe and bootstrap resources;
retired Python service imports remain available only as source references.
Stage/operation definitions
are in `lib/flow/stages/`, backend mappings in `lib/flow/backends/librelane/`, and
execution services in `lib/execution/`. See the
[refactor progress](docs/development/flow-infrastructure-progress.md) for the
verified milestones and remaining finer-step execution work; project-owned
modularized flow files and profiles are later work.

The lifecycle is declaration → `Elaborated_project` (Hardcaml circuit, metadata,
intent and resources; no synthesis) → `Resolved_flow` (validated concrete
TT/LibreLane facts plus the elaborated project) → bundle → separate execution.
Runs have separate IDs and records; collection, reporting
and integrity-checked archiving work independently of Workbench. See the
[memory example](docs/guides/memory-example.md),
[bundle guide](docs/guides/bundle-emission.md),
[target reference](docs/reference/target-reference.md) and normative
[RAM contract](docs/reference/program-memory-contract.md).

The public API rename is source-breaking, with no aliases. See the
[migration and evidence](docs/phase_plan.md#public-api-rename-migration-and-evidence)
before adopting this development provider; `hardcaml_protemu` needs a separate migration.

`dune build` and `dune runtest` cover ordinary development. External tool/PDK setup
is explicit through `./bootstrap.sh`; see the [setup guide](docs/guides/bootstrap.md).
`scripts/flow.sh` prints help with no arguments and dispatches one operation, or
an explicit `execute` sequence. No physical SRAM backend, arbitrary target or
commercial adapter is claimed. Local historical [synthesis](evidence/p4/memory-synthesis/README.md)
and [physical](evidence/p4/observable-physical/README.md) evidence remains preserved.
