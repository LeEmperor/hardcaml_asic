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

The owner-created sibling `hardcaml_asic_example` is the new development specimen
repository. Its controlled-FIFO design is being discussed; it is not implemented
yet. The historical scaf worktree is absent and not a prerequisite.

## Existing workflow

The library declares projects/resources, validates target and timing intent, and
emits immutable bundles. Runs have separate IDs and records; collection, reporting
and integrity-checked archiving work independently of Workbench. See the
[memory example](docs/guides/memory-example.md),
[bundle guide](docs/guides/bundle-emission.md),
[target reference](docs/reference/target-reference.md) and normative
[RAM contract](docs/reference/program-memory-contract.md).

`dune build` and `dune runtest` cover ordinary development. External tool/PDK setup
is explicit through `./bootstrap.sh`; see the [setup guide](docs/guides/bootstrap.md).
`scripts/flow.sh` prints help with no arguments and dispatches one operation, or
an explicit `execute` sequence. No physical SRAM backend, arbitrary target or
commercial adapter is claimed. Local historical [synthesis](evidence/p4/memory-synthesis/README.md)
and [physical](evidence/p4/observable-physical/README.md) evidence remains preserved.
