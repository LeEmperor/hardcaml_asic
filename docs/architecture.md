# hardcaml_asic architecture

Consolidated 2026-10-12 from the implemented source and prior architecture.
This document owns system boundaries; the [phase plan](phase_plan.md) owns
status and sequencing. Provider storage details and the refactoring sequence
below are **proposals for discussion**, not implemented interfaces.
The [historical architecture](archive/architecture-2026-09.md) preserves the
original rationale; the [memory contract](reference/program-memory-contract.md)
remains normative for `Single_port_ram`.

## 1. Purpose and implemented scope

Help independent Hardcaml projects declare ASIC intent, emit reproducible inputs,
execute an implementation flow and inspect traceable results. The supported path
is Tiny Tapeout 6x4 / IHP CMOS5L / LibreLane, with behavioral and explicitly
selected flop memory. There is no production SRAM backend or general multi-flow
implementation. A successful process is not a signoff verdict.

Implemented: project elaboration, target/constraint resolution, immutable bundles,
installed Python dispatcher, separate execution IDs, `run.json`, `results.json`,
postcheck attempts, operation-aware acceptance and integrity-checked archives.
Missing: public catalog, early request correlation, durable operation/step updates
and incremental result snapshots. Source-artifact stamping remains ASIC P6.5a.

## 2. Responsibilities and dependency direction

| Layer | Responsibility |
| --- | --- |
| OCaml library (`lib/`) | Resource semantics, project declarations, validated design intent and input emission |
| Installed flow package (`flow/hardcaml_asic_flow/`) | Flow routing, execution records, tool-specific interpretation, acceptance and preservation |
| Hardware project | Design/wrapper semantics, testbench/regressions, declaration, dependency pin and chosen evidence stores |
| Workbench ASIC adapter | Consume the project's configured public provider interface and translate into feature data |
| Workbench application | Job supervision, derived catalog/cache, workspace/window/tile state and presentation |

Dependencies remain one-way: hardware project → ASIC library/CLI; Workbench
adapter → configured project/provider entry point. ASIC never imports Workbench
application types and does not need a Workbench daemon. Ordinary Dune/tests and
project regressions need not route through ASIC. Python remains a suitable runner;
versioned structured data can be decoded into typed OCaml values by Workbench.

ASIC owns canonical bundles, runs, snapshots, raw evidence, check attempts and
archives. Workbench owns a rebuildable index, bounded caches, saved selections
and layouts; its daemon owns its process handles. Multiple readers of one run
are independent. Selection, tile lifetime and client detach never control a flow.
PD means **physical design**.

The active [Workbench architecture](../../hardcaml_workbench/docs/hardcaml_workbench_architecture.md)
and [Workbench construction plan](../../hardcaml_workbench/docs/construction_phase_plan.md)
own feature, window and tile behavior. These workspace links are for navigation,
not runtime path requirements.

## 3. Target and flow selection

Keep harness, technology and flow separate. The harness specifies the interface,
geometry and submission constraints; technology supplies cells/collateral; the
flow adapter validates compatibility and renders/invokes the selected tools.

Current resolution and rendering are deliberately TT/LibreLane-specific. Preserve
that honest scope; extracting a general adapter framework is not required for
observation. Another real backend should drive future extraction. See the
[target reference](reference/target-reference.md) for exact supported facts.

## 4. Project lifecycle

```text
Project declaration
  → fresh Elaboration_context for one elaboration
  → construct/register resources and validate policy
  → finalize abstract Elaborated_project (circuit + metadata/intent/resources)
  → resolve concrete TT/LibreLane facts into Resolved_flow
  → Bundle.render / Bundle.write
  → separate execution(s), observations and results
```

Elaboration constructs a Hardcaml circuit, not a synthesis result. `Project.elaborate`
returns `Elaborated_project.t`; `Project.elaborate_for_flow` adds validation and
returns `Resolved_flow.t`, retaining that project in `elaborated_project`.
`Bundle.render ?simulation_project` can include a separate simulation elaboration.
Rendering emits inputs; execution invokes tools separately.

Contexts close on success or failure; registration cannot leak into another elaboration.
Resource identities use explicit names and scope paths. Inventories are sorted.
Simulation and implementation elaboration remain separate; bundle source sets
must not mix behavioral models and implementation definitions accidentally.

**Boundary hardening implemented (2026-10-12):** `Resolved_flow.mli` exposes a
private result record, constructed only by `resolve` (also used by
`Project.elaborate_for_flow`). Existing field reads and pattern matching remain
available; construction and record updates are compiler errors. Settings and
converted delays are private records too. Their JSON/list/scalar contents are
immutable; copying an exposed target or clock cannot replace the stored value.
There is no unchecked constructor or deserializer for a resolved flow.

This enforces the resolution boundary, not deep immutability of Hardcaml circuit
internals or a redesign of the existing `Elaborated_project.Private.create` convention.
Resolution still relies on declaration/elaboration invariants. External target
files are still references, not verified physical evidence. Independent-consumer
compiler checks and pre-/post-hardening bundle byte comparisons are recorded in
the [phase plan](phase_plan.md#resolved-build-boundary-hardening-evidence).
The subsequent [source-breaking rename](phase_plan.md#public-api-rename-migration-and-evidence)
preserves that boundary, `Target.Resolved`, and persisted build/bundle/run identities.
Workbench build/run identity types describe different concepts and are unchanged.

## 5. Resources and policies

Retain the existing behavioral/flop RAM contract and independent conformance
tests. Selection is explicit: exact mapping, flops, or an explicitly permitted
fallback. Never silently change shape, latency or behavior to fit hardware.

`Resource_request.contract` currently uses structural S-expression equality;
field order affects matching. This merits a typed/canonical representation before
broader backend authoring, but does not obstruct the current flop specimen or
run observation. No SRAM or public macro framework is a blanket prerequisite.

## 6. Configuration ownership and constraints

The project declaration owns target, clock, resources and supported timing intent.
Derived source lists, target geometry, clock facts, SDC and resource collateral
are protected from conflicting overrides. LibreLane escape-hatch values carry
nonempty reasons. `Tt_cmos5l` supplies overridable template defaults with provenance;
the consumer still owns reset, enable, pin arbitration and testbench behavior.

Current timing supports one primary `clk` and optional **minimum and maximum**
I/O delays. Resolved target constraints include drive/load and timing margins.
Expose those facts and emitted constraint identity to observers rather than
creating a second editable configuration in Workbench. Generated-clock and CTS
analytics are later capabilities. CTS means clock-tree synthesis, which constructs
the physical clock distribution network.

## 7. Build artifacts and provenance

Keep immutable build identity separate from execution, operation and UI job IDs.
Bundle identity covers generated files, copied declared sources and their Git
state, target references, settings and requested tool pins. The current hash uses
an ordered manifest representation; arbitrary field reordering changes identity.
Old manifests and archived evidence must remain readable without rewriting them.

ASIC P6.5a adds generator/source-artifact identity to new bundles. It identifies
the library/tooling source, not the hardware design alone. File moves change an
artifact inventory naturally; they do not invalidate the stamping architecture.
Define the inventory and optional field before implementation; P6.5b adds actual
generator/executor/expectation comparisons and waiver records afterward.

The example's consumer-owned `asic-dependency.json` selects a recorded ASIC
revision; explicit development refresh captures local edits without changing that
record. `scripts/asic_dependency.py` installs library and CLI into an isolated
generation, validates resolution/linking, then atomically publishes its selection.
Shell activation names that generation directly; re-source after refresh to adopt
the new selection. The receipt describes refresh-time inputs, not today's provider
checkout. Its checksum is local bookkeeping, not an embedded source stamp.
The emitter copies the dependency record as a source expectation, not proof of
linked-library identity. See the [workflow](development/consumer-dependency-workflow.md).

Bundle writing currently requires an empty destination and is not atomic. Preserve
the input-publication boundary: an incomplete bundle must not be advertised as
ready. Atomic bundle-directory publication is a possible later hardening slice,
not a reason to discard the current manifest or rewrite elaboration.

## 8. Provider observation direction

### Domain facts and identities

Proposed contract: describe capabilities/versions; list/inspect explicit stores;
correlate a request with an early allocated operation/run; inspect step occurrences;
replay recorded updates; read versioned snapshots and evidence references.
Events describe allocation, lifecycle, publication and operation outcomes, never
UI refresh actions. CLI final-JSON stdout stays compatible; read/watch is separate.

One build may have two runs. Each run has identified operation attempts and step
occurrences; display names or numbered directories are not identities. Collecting
or postchecking a run creates another operation attempt/revision, not a new
implementation run. Rerunning implementation normally creates a new run.

Preserve legacy `run.json.status`: implementation can be completed before
postcheck/report finishes. Add requested-operation outcome separately. A step
finishing and its results being published are distinct facts. Earlier results
remain available after a later failure. A result snapshot is evidence, not a
promise of a resumable physical checkpoint.

### Durable publication and evidence

Choose one coordinated provider write path for `execute` and standalone operations.
Before implementation, settle per-run ordering, writer locks/conflict behavior,
snapshot-to-cursor consistency, request retry/idempotency semantics, duplicate
updates, incomplete writes and stale/crashed-producer behavior. Current atomic
JSON replacement is useful but does not provide transactions or writer locking.
Prefer serialized conflicting mutations initially, not a new scheduler. Disconnected
readers cannot block execution. Storage failure must be visible rather than
fabricating completion; stale observation does not prove a tool/container stopped.

Publish complete snapshots/evidence before advertising them. Measurements retain
producer step/attempt, actual tool, stage, corner, units, constraints and raw source.
LibreLane metrics accumulate: unchanged numbers cannot tell inherited evidence
from a new equal-valued measurement. Keep origin explicit. Archive policy must
preserve published history and its referenced evidence; current archives select
only some intermediate files and require completed runs. Failed-run diagnostic
export needs an explicit separate contract.

### LibreLane feasibility gate

Local source metadata is `3.1.0.dev3`, matching the declared pin, under a Python
3.12 environment; bundles request 3.11. This is source inspection, not runtime
validation. `SequentialFlow.run` calls `step.start` directly; `Step.start` is
final. Overriding `Flow.start_step` is not a demonstrated lifecycle hook.

Step substitutions and `Step.run` are extension points; the latter returns metric
updates before merging with inherited state, but does not cover gated steps or
failures before/after computation. Per-step state files are directly written and
do not expose every lifecycle fact. Prove supported hooks/structured observation
with stated limits, or propose narrow upstream instrumentation. Do not copy the
engine's orchestration. Full-flow acceptance must test the Dockerized path and
actual descendant cancellation, not only a local Python probe.

## 9. Core review and development specimen

### Review recommendation — discuss before implementation

**Keep the P0–P3 model; strengthen boundaries and refactor P4 internals in slices.**
The integration needs richer execution evidence, not a different RAM behavior or
project declaration lifecycle. Completed historical milestones remain complete;
they do not claim that future observation requirements have already been met.

| Area | Recommendation | Timing |
| --- | --- | --- |
| Project/context/Elaborated_project, resource semantics | Reuse with current tests | No rewrite prerequisite |
| `Resolved_flow` construction | Private interface enforces resolution-only construction; readers preserved | Implemented; evidence in phase plan |
| Bundle/manifest | Preserve format and determinism; additive provenance and declared-fact export | Coordinate with P6.5a and result contract |
| Runner/dispatcher | Extract operation/publication logic behind existing entry points | As durable observation is added |
| Collection/reporting | Step-aware extractors plus final aggregation; retain existing acceptance policy | Before incremental result publication |
| Archives | Preserve snapshot/evidence closure at an explicit revision | Alongside snapshots, before scratch deletion is advertised |
| Resource matching, multi-target abstraction | Revisit on concrete resource/backend demand | Backlog, not pre-P6 gates |

For each refactor, state the invariant, keep existing positive/negative tests and
add the new acceptance case. Do not combine naming/package reshuffles, schema
changes and new observation behavior into one unreviewable rewrite.

### `hardcaml_asic_example`

The owner-created [sibling development specimen](../../hardcaml_asic_example/README.md)
now implements a fixed single-clock 16 × 8 controlled FIFO with explicit register
storage, a pure list-based scoreboard, directed/seeded regressions, a consumer-owned
TT wrapper/declaration and a standalone bundle emitter. Its source root is explicit,
not a required hardcoded sibling path. Owner initial ref
`8e4577f6c72cc689cbc92daeb5f8ae083cf970e0` now exists; it alone does not establish
a clean tree or a dependency pin. The specimen now has a recorded ASIC baseline
plus an explicit development override; the consumer record awaits owner commit.

The delivered contract provides synchronous clear with priority over disable,
registered pop responses, occupancy/full/empty and pre-edge acceptance decisions.
Empty simultaneous requests accept only push (no bypass); full simultaneous
requests accept both and return the old head. Registers support these concurrent
operations without changing the library's 1RW RAM contract. The TT wrapper owns
pin mapping and combinational output/OE masking separately from synchronous reset.

The example owns Dune files, design, scoreboard, seeded regression, emitter and
ordinary commands. ASIC owns flow/report semantics; Workbench owns adaptation
and window/tile behavior. PDK-free bundle and separately compiled emitted
synthesis/simulation RTL checks pass after isolated dependency activation. Genuine
example-root emission also passes complete bundle equality, copied-input hashes,
actual revision/dirty-input provenance and RTL replay; see the
[closeout evidence](phase_plan.md#consumer-refresh-and-real-checkout-emitter-closeout).
Synthetic committed fixtures remain separate provenance tests. This does not
establish full environment locking, embedded source identity, source-access-denied
P6.6 acceptance or physical acceptance. Concrete provider observation identity/state
examples remain next work; FIFO delivery does not implement that provider contract
or close ASIC P6 gates.
