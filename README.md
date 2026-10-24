# hardcaml_asic

An OCaml/Hardcaml library and installed flow CLI that takes a Hardcaml design to
a reproducible ASIC implementation input, runs it through an open-source flow,
and keeps traceable, integrity-checked results.

One opam package (`hardcaml_asic`, version 0.1.0) installs:

- the **hardware library** `hardcaml_asic`: project declaration, registered
  resources (memory), target/constraint resolution and bundle emission;
- the **flow domain** `hardcaml_asic.flow_domain`: stages, operations, named
  methodologies, typed parameter profiles and the checked LibreLane mapping;
- the **execution library** `hardcaml_asic.execution`: preflight, run, stage
  checkpoints, observation/journals, collection, reporting, finalization and
  archives;
- the **`hardcaml-asic-flow` command**, a native OCaml CLI over that execution
  library, plus a thin installed Python runtime used only for the LibreLane
  bridge, probes and provisioning.

A consumer pins one revision and gets the library and CLI together.

## Supported scope

The path is deliberately narrow:

| | Supported |
| --- | --- |
| Harness | Tiny Tapeout `6x4` |
| Technology | IHP `ihp-sg13cmos5l` (CMOS5L) |
| Flow | LibreLane Classic, through the pinned container image |
| Memory | `Single_port_ram` as a behavioral simulation model or explicit synthesizable flops |

Not provided: an SRAM macro backend, other targets or flows, and commercial tool
adapters. A completed process is **not** a signoff verdict; acceptance is a
separate, explicit check (see [interpreting results](docs/guides/usage.md#7-interpret-and-preserve-results)).

## How it fits together

```text
Project.create  ──►  Elaborated_project  ──►  Resolved_flow  ──►  bundle  ──►  execution  ──►  results / archive
 (declaration)       circuit, metadata,       validated TT/         immutable      separate run     collect, report,
                     intent, resources        LibreLane facts       inputs +       ID and records   finalize, archive
                     (no synthesis)                                 manifest
```

Elaboration and emission never invoke an EDA tool or read a PDK. The emitted
bundle is immutable and identity-addressed: if the configuration is wrong, fix
the declaration and emit again. Each flow attempt gets its own run ID, separate
from the bundle's build identity.

Execution comes in three forms, all through `hardcaml-asic-flow`:

- **Coarse runs**: `run`/`execute` with `--stage synthesis|full`.
- **Explicit stages**: `stages` with `--endpoint` across six sequential
  boundaries (synthesis → floorplan → placement → cts → routing → signoff), with
  checkpoints, restart and a journal you can watch live from another shell.
- **Named flows**: project-owned flow catalogs and parameter profiles (for
  example `standard/balanced` and `standard/synth_delay`), previewed to a plan
  identity and then run against that identity.

## Quick start

### Library only (no PDK, no Docker)

```sh
dune build
dune runtest

# PDK-free memory example: behavioral vs flop checks, optional RTL dump
dune exec examples/memory_example.exe
dune exec examples/memory_example.exe -- --rtl /tmp/memory_example.v

# Emit an immutable TT bundle (observable | memory) into a new directory
BUNDLE=$(mktemp -d)/bundle
dune exec examples/tt_bundle_example.exe -- memory "$BUNDLE"
```

Inspect `$BUNDLE/manifest.json`: it lists synthesis RTL (`src/`), separately
elaborated simulation RTL (`simulation/`), generated SDC and LibreLane config,
TT metadata, and copies of the declared source inputs.

### Provision the toolchain and run a flow

Provisioning is explicit and fetches substantial external collateral (PDK, TT
support tools, LibreLane image, managed Python/Tcl). It needs Bash, Git, Docker
and Nix on the host.

```sh
./bootstrap.sh            # opam check + .toolchain/ (a few minutes, ~1.5 GB)
./bootstrap.sh --check    # read-only readiness check
scripts/flow.sh           # prints help; starts nothing
scripts/flow.sh build
OUT=/tmp/p4-observable scripts/flow.sh emit
OUT=/tmp/p4-observable STAGE=synthesis scripts/flow.sh execute
```

`scripts/flow.sh` is a development driver for this repository's examples; after
emission it hands every operation to the same implementation the installed
`hardcaml-asic-flow` runs. `STAGE=full` adds place, route, signoff and the
postchecks, and is much more expensive. See [bootstrapping](docs/guides/bootstrap.md)
and [execution and results](docs/guides/flow.md).

### The installed command

```text
hardcaml-asic-flow <command> [options]

commands: provision, preflight, run, postcheck, collect, report, archive,
          execute, stages, finalize, finalization-inspect, checkpoint-inspect,
          observation
```

Output is a human summary by default; machine callers pass `--json` (CLI
contract 4). `--help`, `--version`, `collect`, `report` and `archive` need no
PDK, container or provisioning. Results default to `_flow_results/` under the
caller's working directory. See [consumer installation](docs/guides/consumer-installation.md)
for pinning, the installed layout and collateral resolution.

## Using it from another project

Pin a full commit and depend on the wrapped library:

```sh
opam pin add --no-action hardcaml_asic \
  "git+https://github.com/LeEmperor/hardcaml_asic.git#<full-commit-hash>"
opam install hardcaml_asic
```

```lisp
(executable
 (name asic_bundle)
 (libraries core hardcaml hardcaml_asic))
```

A design implements `Project.Design`; the project declares metadata, target,
flow, clocks, timing, pinout, source inputs and a mandatory resource policy, then
calls `Project.emit_bundle` or `Project.emit_bundle_to_store`. The
[user workflow](docs/guides/usage.md) walks through declaration, simulation,
emission, execution and archiving end to end.

The sibling [hardcaml_asic_example](../hardcaml_asic_example/README.md) is the
development specimen: a 16×8 controlled FIFO with an independent scoreboard, TT
wrapper, a project CLI (`describe | emit | preflight | run | flow plan | flow run`),
a declared `standard` flow catalog with two profiles, and a standalone headless
client. It consumes this repository through an isolated refresh/activation
workflow; see [consumer dependency workflow](docs/development/consumer-dependency-workflow.md).

## Repository layout

| Path | Contents |
| --- | --- |
| `lib/` | Hardware library `hardcaml_asic`: qualified groups `resource/`, `flow/` (project flow selection, `Stage`, `Recipe`, plan JSON), `platform/` (targets, `Tt_cmos5l`, pinout, clock, timing) and `elaboration/` (`Elaborated_project`, `Resolved_flow`, `Bundle`); root modules `Project`, `Methodology_plan`, `Single_port_ram`; `hardcaml_asic.ml` is the public surface |
| `flow_domain/` | Flow domain library: stage recipes (`stages/`), LibreLane mapping (`backends/librelane/`), catalog, methodology, profiles, parameters |
| `execution/` | Execution library: runner, runtime/process supervision, storage and checkpoints, observation, results, archive, LibreLane backend protocol |
| `bin/` | `hardcaml-asic-flow` and the `hardcaml-asic-experimental-*` service helpers it routes to |
| `flow/hardcaml_asic_flow/` | Installed Python runtime (LibreLane bridge, probes, managed Python, provisioning data); retired service modules are kept as source-only references |
| `examples/` | `memory_example` and `tt_bundle_example` |
| `scripts/` | Development adapters: `flow.sh`, `toolchain.sh`, `ocaml-deps.sh`, legacy Python entry points |
| `test/` | Expect tests, OCaml consumers driven by Python checks, provider observation fixtures, installed-prefix and packaging tests |
| `evidence/` | Curated records of real synthesis, physical, observation and SRAM-investigation runs |
| `experiments/` | Probes and feasibility work (LibreLane observation, SRAM, managed Python) |
| `docs/` | Plans, architecture, guides, references, and history |
| `bootstrap.sh`, `toolchain.lock` | Toolchain provisioning and its pinned revisions |

## Status

As of 2026-10-24:

- **Delivered:** project declaration through bundle emission; native OCaml CLI
  and execution services (coarse runs, explicit stages with checkpoints,
  default journals and live watch, collection, reporting, postcheck,
  finalization, archives); default result stores; managed Python/Tcl
  provisioning; and named flows/profiles with plan-identity enforcement.
- **Evidence:** a fresh installed consumer completed all six physical stages
  plus external acceptance (DRC/LVS/antenna, TT precheck, gate-level replay);
  the `balanced` and `synth_delay` profiles each passed real synthesis. See
  [`evidence/`](evidence/) and the [phase plan](docs/phase_plan.md).
- **Next:** Protemu-focused ASIC PT.0–PT.8: correct SRAM probe defects, deliver
  the exact SRAM backend and macro physical integration, validate the real
  consumer, expose selected/realized resource mappings to Workbench, then extend
  timing declarations and reproducible configuration studies. See the
  [active queue](docs/phase_plan.md#active-queue).
- **Open:** source-artifact stamping and independent-installation gates (ASIC
  P6.5/P6.6), committed-pin adoption by the example, and configuration-changing
  checkpoint reuse. These retain their historical status in the
  [previous plan](docs/archive/phase-plan-2026-10-24.md); they are not the current queue.

The public lifecycle was renamed to `Elaborated_project`/`Resolved_flow` with no
aliases; see the [migration notes](docs/phase_plan.md#public-api-rename-migration-and-evidence).
Installed Python service imports are retired; use the CLI or
`hardcaml_asic.execution` instead.

## Documentation

- [Documentation index](docs/README.md): where everything lives.
- [Phase plan](docs/phase_plan.md): the one active queue, status and evidence.
- [Architecture](docs/architecture.md): ownership and boundaries; read this
  before changing an interface.
- Guides: [user workflow](docs/guides/usage.md) ·
  [installation](docs/guides/consumer-installation.md) ·
  [bootstrapping](docs/guides/bootstrap.md) ·
  [bundle emission](docs/guides/bundle-emission.md) ·
  [execution and results](docs/guides/flow.md) ·
  [stage quickstart](docs/guides/stage-quickstart.md) ·
  [OCaml stage recipes](docs/guides/ocaml-stage-recipes.md) ·
  [named flows](docs/guides/named-flows.md) ·
  [memory example](docs/guides/memory-example.md)
- References: [TT/CMOS5L target](docs/reference/target-reference.md) ·
  [memory contract](docs/reference/program-memory-contract.md)
- [SRAM investigation](docs/sram/README.md) · [backlog](docs/backlog/README.md) ·
  [archive](docs/archive/README.md)
