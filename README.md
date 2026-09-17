# hardcaml_asic

An OCaml/Hardcaml library in early development for ASIC design resources,
technology bindings, and reproducible implementation-flow inputs and results.
Tiny Tapeout with LibreLane is the first planned path. The architecture keeps
harness, technology, and flow adapters separate to accommodate other open flows
and optional future Cadence/Synopsys integrations.

Start with the [documentation index](docs/README.md) and the
[architecture and implementation plan](docs/architecture.md).
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
and postchecks; `scripts/flow.sh` runs that sequence end to end and
`scripts/report.py` summarizes a finished run (`--help` on either). [Mapped synthesis evidence](evidence/p4/memory-synthesis/README.md)
exists for the registered-memory example; the full physical exit gate remains open.
Physical SRAM support requires
a separate capability investigation.
