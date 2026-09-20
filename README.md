# hardcaml_asic

An OCaml/Hardcaml library for ASIC design resources, technology bindings, and
reproducible implementation-flow inputs and results. The initial implemented
path is Tiny Tapeout `6x4` with IHP CMOS5L and LibreLane. The architecture keeps
harness, technology, and flow adapters separate to accommodate other open flows
and optional future Cadence/Synopsys integrations.

Start with the [initial user workflow](docs/usage.md). It covers exact-revision
installation, declaration, registered-memory simulation and implementation,
bundle emission, explicit environment setup, execution, result interpretation,
and evidence preservation. The [documentation index](docs/README.md) links the
specialist references and historical implementation evidence.

On a new machine, `./bootstrap.sh` checks the required opam packages and
provisions tt-support-tools, the IHP PDK, and the LibreLane/precheck environments
under `.toolchain/`; `--install-deps` opts in to installing missing opam packages,
and `--check` changes nothing. `scripts/flow.sh` then runs the implementation
flow end to end. The
[bootstrap guide](docs/bootstrap.md) has the options and the troubleshooting.

The [implementation phase plan](docs/phase_plan.md) breaks initial usage into
tasks, dependencies, and completion criteria.
The [program-memory contract](docs/program-memory-contract.md) specifies the
first resource, `Single_port_ram`.

The project lifecycle, registered single-port RAM, validated TT/CMOS5L
target and flow configuration, and deterministic bundle emission are implemented
and tested. The RAM has a diagnostic behavioral
model and explicitly selected synthesizable flop storage; run the
[memory example](docs/memory-example.md) without a PDK. The
[target reference](docs/target-reference.md) records the supported `6x4` pair,
wrapper boundary, and timing/configuration ownership. The
[bundle guide](docs/bundle-emission.md) emits TT/LibreLane inputs for observable
and registered-memory examples. The [flow execution guide](docs/flow.md)
provides external preflight, isolated LibreLane runs, structured result collection,
and postchecks; `./bootstrap.sh` provisions the pinned toolchain into `.toolchain/`,
`scripts/flow.sh` runs that sequence end to end,
`scripts/report.py` summarizes a finished run, and `scripts/archive.py` writes
one out as an evidence directory (`--help` on any of them). Both P4 gates have
evidence: [mapped synthesis](evidence/p4/memory-synthesis/README.md) for the
registered-memory example and the
[physical path](evidence/p4/observable-physical/README.md) for the observable
one, which closes P4's exit gate. The consumer's clean-staging adopted-design
reproduction also passes. P0–P5 and the initial M3 workflow are complete with
[linked evidence](docs/phase_plan.md#8-p5--reference-consumer-adoption-and-initial-usage).
The supported path remains deliberately limited: there is no SRAM macro backend,
broader target or commercial-flow adapter, or installed shared-tool CLI.
