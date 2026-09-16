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

The project lifecycle (declaration, elaboration context, resource registration and
implementation selection policy, immutable build) is implemented and tested
([phase plan P0](docs/phase_plan.md#3-p0--project-and-elaboration-foundations)).
`Single_port_ram.create` is still a stub; memory implementations, target
resolution, and flow adapters are planned. The first complete path will use
explicitly selected flop storage; physical SRAM support requires a separate
capability investigation.
