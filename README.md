# hardcaml_asic

An OCaml/Hardcaml library in early development for ASIC design resources,
technology bindings, and reproducible implementation-flow inputs and results.
Tiny Tapeout with LibreLane is the first planned path. The architecture keeps
harness, technology, and flow adapters separate to accommodate other open flows
and optional future Cadence/Synopsys integrations.

Start with the [documentation index](docs/README.md) and the
[architecture and implementation plan](docs/architecture.md).

On a new machine, `./bootstrap.sh` provisions the pinned toolchain (opam packages,
tt-support-tools, the IHP PDK, the LibreLane and precheck environments) into
`.toolchain/`; `./bootstrap.sh --check` reports what is missing without changing
anything. `scripts/flow.sh` then runs the implementation flow end to end. The
[bootstrap guide](docs/bootstrap.md) has the options and the troubleshooting.

The [implementation phase plan](docs/phase_plan.md) breaks initial usage into
tasks, dependencies, and completion criteria.
The [program-memory contract](docs/program-memory-contract.md) specifies the
first resource, `Single_port_ram`.

The project lifecycle, registered single-port RAM, validated TT/CMOS5L
target and flow configuration, and deterministic bundle emission are implemented
and tested ([phase plan P0–P3](docs/phase_plan.md)). The RAM has a diagnostic behavioral
model and explicitly selected synthesizable flop storage; run the
[memory example](docs/memory-example.md) without a PDK. The
[target reference](docs/target-reference.md) records the supported `6x4` pair,
wrapper boundary, and timing/configuration ownership. The
[bundle guide](docs/bundle-emission.md) emits TT/LibreLane inputs for observable
and registered-memory examples. The [Phase 4 execution guide](docs/phase4-execution.md)
provides external preflight, isolated LibreLane runs, structured result collection,
and postchecks; `./bootstrap.sh` provisions the pinned toolchain into `.toolchain/`,
`scripts/flow.sh` runs that sequence end to end,
`scripts/report.py` summarizes a finished run, and `scripts/archive.py` writes
one out as an evidence directory (`--help` on any of them). Both P4 gates have
evidence: [mapped synthesis](evidence/p4/memory-synthesis/README.md) for the
registered-memory example and the
[physical path](evidence/p4/observable-physical/README.md) for the observable
one, which closes P4's exit gate. That physical run used this repository's own
example, so reproducing it from the consumer's adopted design remains open as
[P5.4](docs/phase_plan.md#8-p5--reference-consumer-adoption-and-initial-usage).
Physical SRAM support requires a separate capability investigation.
