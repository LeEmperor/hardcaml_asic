# Documentation

## Returning to the project

1. **[Phase plan](phase_plan.md)** — current status, what is next, dependencies and
   links to completion evidence. This is the only active implementation queue.
2. **[Architecture](architecture.md)** — ownership, implemented boundaries and the
   delivered provider boundaries and remaining scope. Read this before changing an interface.
3. **[User workflow](guides/usage.md)** — how to use the existing library and CLI.

Current checkpoint (2026-10-13): default result store and CLI contract **4**,
human-default/explicit-JSON output and project `describe|emit|preflight|run` are
delivered; see [current closeout](phase_plan.md#default-result-store-and-cli-2-closeout)
and the [command/storage matrix](guides/flow.md#default-result-store-and-cli-contract-3).
All machine callers request `--json`, including additive stage/checkpoint/observation/
finalization commands; stages journal by default and emit allocation/terminal JSONL.
Foreground watch delivers reader updates/status JSONL. Independent review and consumer
integration are complete; see [flow journal closeout](development/flow-journal.md)
and the historical [contract-3 presentation slices](development/human-readable-flow-output.md).
Role-specific host/container runtime policy,
shared readiness checks and observed image/engine launch binding passed final
2026-10-12 acceptance; see [closeout evidence](phase_plan.md#hostcontainer-runtime-policy-closeout)
and [fresh-emission requirements](guides/flow.md#runtime-policy-and-launch-binding).
ASIC P0–P5/M3 and P6.1–P6.3/P6.4a/b have
evidence. Lexical venv interpreter paths, bounded provisioning readiness,
managed Python/Tcl default, explicit `provision --python BASE` and thin example bootstrap are delivered
([current acceptance](phase_plan.md#tool-environment-closeout-acceptance)); broader
P6.5c and P6.5/P6.6 gates remain open. The provisional synthetic
[provider observation fixtures/model](../test/fixtures/provider_observation/v1/README.md)
are implemented: 50 focused tests and the full provider regression suite pass
([evidence](phase_plan.md#provider-observation-fixture-acceptance)). The subsequently
authorized [LibreLane feasibility probe](../experiments/librelane_observation/README.md)
was **historically BLOCKED** by missing Tcl/Tk in local Python 3.12.3. Zero of
eleven official cases executed in that attempt
([unchanged evidence](../evidence/librelane-observation/blocked-local.json)).
The [actual managed-runtime evidence](../evidence/managed-python/actual-runtime.json)
now proves Python 3.11.17/Tcl 9.0.4 and LibreLane Tcl smoke in a disposable venv.
Later selected-image official cases and production physical execution succeeded;
see the explicit-stage closeout below. The final actual read-only bootstrap check,
including container metadata, exits 0; the earlier five-gap check remains dated
historical evidence.
Project run requires mutually exclusive Classic `--stage` or explicit-stage `--endpoint`.
The explicit-stage route delivers default early allocation, checkpoints, per-attempt
inspect/cursor updates and foreground watch; Classic has no stage journal.
Store-wide catalog and fine backend-step updates remain open.
The owner's [development specimen](../../hardcaml_asic_example/README.md) now has
the fixed FIFO contract/core, independent scoreboard, TT wrapper/declaration,
project-centered `describe|emit|preflight|run` CLI and PDK-free generated-RTL acceptance.
The consumer owns `Fifo_asic.project ()`; the provider owns shared
`Project.emit_bundle` / `emit_bundle_to_store`. Description is local S-expression
or a JSON wrapper, not a Workbench protocol. Project run is implementation only;
existing-run collection/reporting remain separate installed operations.
See [entrypoint usage and regression coverage](guides/bundle-emission.md#project-centered-entry-point).
A recorded ASIC baseline
and explicit development override now support isolated library/CLI refresh,
activation, plain builds and real-checkout emitter acceptance; see the
[commands](development/consumer-dependency-workflow.md#implemented-commands) and
[project-entrypoint acceptance](phase_plan.md#project-centered-entrypoint-acceptance).
The recorded `171476...` baseline cannot supply the new API: current recorded
refresh is refused while development refresh works. A compatible committed
candidate must be adopted by the owner. Full environment locking, P6 source stamping,
source-access-denied installation remain open. Later specimen physical/external
acceptance is recorded separately from committed-pin adoption.
The old scaf checkout is absent and not required.

**Explicit-stage delivery (2026-10-13):** start with the concise
[stage quickstart](guides/stage-quickstart.md), then the detailed
[OCaml/Python recipes guide](guides/ocaml-stage-recipes.md) and
[execution/reader/finalization contracts](guides/flow.md). The shared coarse runner,
six sequential physical boundaries, schema-3 recipes, exact-runtime path-bound
publication/restarts, opt-in observation and separate existing-policy finalization
passed [full independent checks](phase_plan.md#explicit-stage-refactor-closeout).
Subsequent [default journal/foreground watch closeout](phase_plan.md#default-flow-journal-closeout)
adds contract 4, consumer endpoint routing and real synthesis/watch/reconnect evidence.
Curated repo JSON records [physical execution](../evidence/librelane-observation/slice4-physical.json),
[observed execution](../evidence/librelane-observation/slice5-observed.json) and
[external acceptance](../evidence/librelane-observation/slice6-finalization.json).
Isolated installed consumer linkage is verified; an adopted committed pin and full
Workbench application integration are separate remaining work.

For the subsequent ownership and utilization discussion, see
[ASIC/Workbench execution boundary](development/workbench-execution-boundary.md):
persisted journals versus live UI events, output locations, human inspector
formatting preferences, cancellation, and daemon-failure behavior. It distinguishes
current capabilities from proposed follow-ups.

The [human-readable flow output feature](development/human-readable-flow-output.md)
records the implementation of readable command summaries and explicit `--json`
machine output, including consumer migration and verification.

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
- [Stage quickstart](guides/stage-quickstart.md): explicit stages, observation,
  restart and separate finalization.
- [OCaml stage recipes](guides/ocaml-stage-recipes.md): typed declarations,
  schema-3 Python interoperability and installed contract verification.

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
