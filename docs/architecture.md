# hardcaml_asic architecture

Consolidated 2026-10-12; explicit-stage delivery reconciled 2026-10-13; native
explicit-stage ownership updated 2026-10-14.
This document owns system boundaries; the [phase plan](phase_plan.md) owns
status and sequencing. Default bundle/run/preflight storage and the bounded
explicit-stage runner, checkpoints, observation and finalization are implemented.
Start with the [stage quickstart](guides/stage-quickstart.md) or the detailed
[OCaml recipe guide](guides/ocaml-stage-recipes.md).
The [OCaml-first refactor record](development/flow-infrastructure-progress.md)
describes the delivered native stage execution path and stage-domain layout;
the [remaining queue](phase_plan.md#ocaml-first-flow-infrastructure) tracks the
broader migration. Named fixed-recipe catalogs/profiles and preview/run identity
enforcement are now delivered; see [named flows](guides/named-flows.md). These are
standalone project/provider interfaces. Workbench integration, arbitrary operation
composition and configuration-changing checkpoint reuse remain later work.
The [historical architecture](archive/architecture-2026-09.md) preserves the
original rationale; the [memory contract](reference/program-memory-contract.md)
remains normative for `Single_port_ram`.

## 1. Purpose and implemented scope

Help independent Hardcaml projects declare ASIC intent, emit reproducible inputs,
execute an implementation flow and inspect traceable results. The supported path
is Tiny Tapeout 6x4 / IHP CMOS5L / LibreLane, with behavioral and explicitly
selected flop memory. There is no production SRAM backend or general multi-flow
implementation. A successful process is not a signoff verdict.

Implemented: project declaration inspection and shared emission entry point,
project elaboration, target/constraint resolution, immutable bundles,
installed native OCaml CLI4 composition, separate execution IDs, `run.json`, `results.json`,
postcheck attempts, operation-aware acceptance and integrity-checked archives;
default result stores, standalone preflight receipts, human/explicit-JSON CLI 4,
and project preflight/implementation-run routing.
Explicit-stage delivery adds six sequential physical boundaries, schema-3 OCaml/Python
recipes, exact-runtime path-bound checkpoints, early per-attempt allocation and
stage inspect/cursor updates and foreground watch, plus separate terminal-results/acceptance operations.
CLI stages journal by default; independent runner/adapter APIs remain explicit.
Missing: store-wide catalog/idempotency, fine backend-step updates, execution
recovery and full Workbench application integration. Source-artifact stamping remains ASIC P6.5a.
The provisional synthetic [observation fixtures](../test/fixtures/provider_observation/v1/README.md)
and test-only validator/replayer are implemented and accepted; they add no installed
or live provider capability.

## 2. Responsibilities and dependency direction

**Settled tool-environment ownership:** the installed provider (OCaml library and
native OCaml CLI) operates independently of its source checkout. The consumer
owns a configurable tool root, with `_flow_tools/` as the adopted default, holding
the pinned managed Python/Tcl runtime, LibreLane/precheck venvs and PDK/support
collateral. External bootstrap/probe Python, explicit Python overrides, OS
libraries/certificates and Docker/Nix stores remain separate. A thin consumer bootstrap delegates to the
installed provider without copying its pins; provider refresh and tool provisioning
are separate operations. The example's thin bootstrap and bounded provisioning
readiness checks are implemented; no copied pins, source fallback or automatic
provider refresh is used. See the [current acceptance](phase_plan.md#hostcontainer-runtime-policy-closeout).

| Layer | Responsibility |
| --- | --- |
| OCaml hardware library (`lib/`) | Resource semantics, project declarations, validated design intent and input emission |
| OCaml flow domain (`lib/flow/`) | Stage/operation contracts, standard compositions and checked LibreLane mappings |
| OCaml execution library (`lib/execution/`) and native commands (`bin/`) | Public CLI4 parsing/defaults/identity/routing/rendering, all computation services, supervision, publication, records, observation and watch |
| Thin installed Python runtime (`flow/hardcaml_asic_flow/`) | Exactly nine runtime modules: `__init__`, `backend_protocol`, `librelane_bridge`, `stage_metadata_probe`, `probe`, `runtime_observation`, `runtime_contract`, `managed_python`, `paths`; four packaged data files; provision shell remains independently Python-dependent |
| Retired Python SOURCE references | Sixteen service/CLI/planner/reader modules retained only for deprecated checkout imports and test oracles; `execution_plan`, `flow_observation`, `IncrementalReader` and related installed imports are a Python API break. Native CLI/OCaml execution APIs replace them; optional `PYTHONPATH=checkout/flow` is not installed support |
| Hardware project | Design/wrapper semantics, testbench/regressions, declaration, dependency pin and chosen evidence stores |
| Workbench ASIC adapter | Consume the project's configured public provider interface and translate into feature data |
| Workbench application | Job supervision, derived catalog/cache, workspace/window/tile state and presentation |

Package 0.1.0 and CLI4 remain unchanged only because the native CLI contracts are
unchanged. They do not preserve the retired installed Python API.

### Current native execution source map

`lib/execution/dune` defines one public `hardcaml_asic.execution` library with
`(include_subdirs unqualified)`. Responsibility directories are source organization,
not new namespaces: all `Hardcaml_asic_execution.*` module names are retained.

| Source directory under `lib/execution/` | Modules / responsibility |
| --- | --- |
| Root | `Runner`, `Execution_plan`, `Coarse_execution_service`, `Coarse_run_service`: central planning and orchestration |
| `storage/` | `Checkpoint`, `Checkpoint_publisher`, `Result_store`: validation, publication and allocation |
| `observation/` | `Observation`, `Observation_writer`: persisted reader and writer |
| `results/` | `Collect_service`, `Evidence_json`, `Report_service`, `Postcheck_service`, `Finalization_record`, `Finalization_service`, `Run_record`: collection, evidence decoding, acceptance and records |
| `archive/` | `Archive_service`, `Archive_encoding`, `Evidence_tar`: archive selection and encoding |
| `runtime/` | `Identity_json`, `Runtime_contract`, `Runtime_evidence`, `Runtime_probe`, `Execution_transport`, `Process`, `Process_supervisor`, `Preflight_service`: identity, readiness, launch and supervision |
| `backends/librelane/` | `Backend_protocol`, `Backend_state`, `Classic_contract`, `Segment_report`, `Segment_service`, `Stage_preparation`: narrow native-backend integration |

The three C stubs remain at the library root beside the unchanged foreign-stub
stanza. Stage domains remain in `lib/flow/stages/`; the hardware library still has
no execution dependency. Installed resource paths and runtime output layouts are
unchanged by this source-only organization.

Dependencies remain one-way: hardware project → ASIC library/CLI; Workbench
adapter → configured project/provider entry point. ASIC never imports Workbench
application types and does not need a Workbench daemon. Ordinary Dune/tests and
project regressions need not route through ASIC. The hardware library does not
depend on the execution library. Versioned structured data can be decoded into
typed OCaml values by Workbench independently of the provider implementation language.

ASIC owns canonical bundles, runs, snapshots, raw evidence, check attempts and
archives. Workbench owns a rebuildable index, bounded caches, saved selections
and layouts; its daemon owns its process handles. Multiple readers of one run
are independent. Selection, tile lifetime and client detach never control a flow.
PD means **physical design**.

Current tool storage has separate owners: the provider library/CLI installation prefix,
the configurable collateral root (the example defaults to absolute `_flow_tools/`;
provider/development adapters retain their legacy `.toolchain/` fallback), host
prerequisites and Docker/Podman/Nix stores, and the
consumer's bundle/run/archive stores. Shared `provision --toolchain PATH` or
`TOOLCHAIN` selects managed `python`, `tt`, `pdk`, `.venv` and `.venv-precheck` children.
Normal provisioning selects the installed archive pin, verifies its digest before
extraction/execution, safely stages and probes it, and retains no-replace final
generations with a receipt after the relocated probe. Initial Linux glibc x86_64
>= 2.17 support requires kernel/filesystem `renameat2` support; this is not a
universal platform guarantee or P6.5 source/runtime attestation.
`provision --python BASE` explicitly overrides the managed base for
new venvs; execution `--python` chooses the flow venv interpreter, whose lexical
path is preserved. `--check` is bounded and read-only; normal provisioning may
write managed collateral. Preflight now checks host LibreLane and headless Tcl;
native EDA capability checks and Podman runner generalization remain open.
See [tool-directory ownership and local observations](guides/bootstrap.md#tool-directory-ownership).
ASIC P6.5c is partially addressed and remains open.

New schema-1 manifests add `requested_tools.runtime_policy`: host flow Python is
exact-minor 3.11, native execution uses that host runtime, and Dockerized
implementation uses the official LibreLane 3.1.0.dev3 image with distribution
Python 3.10..3.14 / `Requires-Python >=3.10`. Absent policy retains legacy strict
3.11 for both roles; malformed explicit policy fails closed. The pure contract
and structured observation modules are shared by provisioning/preflight, but
installed provisioning defaults never replace bundle authority.
Flat actual fields remain; structured `runtime_contract` and new run
`execution_binding` are additive. Docker transport binds the observed engine,
interpreter flags and immutable local image ID, separately from RepoDigests.
It mounts staged project RW / PDK RO, applies rootless-aware UID policy, removes
ambient image overrides and owns bounded cleanup. Direct transport is needed
because installed LibreLane `image_exists` rejects IDs/digests; the LibreLane
flow engine is unchanged. Postcheck verifies the saved image/engine and records
tool identity separately; historical records retain their fallback. This is an
attempt-local binding, not a cross-machine digest pin or runtime attestation.
See [policy and limits](guides/flow.md#runtime-policy-and-launch-binding).

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

The consumer owns `Fifo_asic.project ()` (in the FIFO specimen) and its declaration,
wrapper and source inventory. `Project.create ?source_inputs` defaults to `[]`;
the getter retains the declared list. `Project.describe` returns local declaration
facts as a S-expression without design construction, resolution or I/O. It is not
a Workbench observation protocol; the example's JSON description is a local wrapper
around those facts. Root/output paths are execution arguments, not
declaration fields.

`Project.emit_bundle ?inputs ?include_simulation t ~source_root ~output_dir` owns
the shared orchestration: reject empty inventory before design construction,
elaborate/resolve implementation, optionally elaborate Simulation, render, write.
Simulation defaults to true; false skips its construction and reuses synthesis
sources for simulation. No output is written before render succeeds; writing
retains Bundle's new/empty-directory requirement and non-atomic failure behavior.
`Project.emit_bundle_to_store` composes the same rendering with `Bundle.publish`:
verified complete private `.objects` data precedes exclusive public identity-symlink
publication, and reuse validates exact tree/bytes without changing metadata.
The library requires an explicit store. The project CLI selects
`ROOT/_flow_results/{bundles,runs,operations}`; the generic installed CLI defaults
to caller cwd `_flow_results` for runs/operations. `_flow_tools` remains separate.
Preflight pending/report/receipt and run records precede tool probes; failed or
interrupted readiness is saved where storage permits. These bounded diagnostics
are not a live journal, fsync guarantee or crash-recovery protocol. Required stage
validation precedes project work; project run is implementation only. Subsequent
collect/report select an explicit existing run, never newest or arbitrary resume.
See the [CLI 3 migration and command matrix](guides/flow.md#default-result-store-and-cli-contract-3).
Dependencies remain acyclic: Project composes Bundle and Resolved_flow, which use
Elaborated_project rather than calling back into Project. Private construction
boundaries remain intact. See the [entrypoint guide](guides/bundle-emission.md#project-centered-entry-point).

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

Explicit `Bundle.write` requires a new/empty destination and is not atomic.
`Bundle.publish` now supplies atomic visibility via exclusive identity symlinks,
verified immutable reuse and no-clobber concurrent publication on local POSIX
filesystems. Published objects must be retained; no GC, mutable current pointer,
NFS or power-loss durability is promised. This preserves the manifest/identity
and does not advertise partial input as ready; see
[publication details](guides/bundle-emission.md#identity-addressed-publication).

## 8. Provider observation direction

### Delivered bounded execution and readers

The current explicit-stage implementation uses `Hardcaml_asic_execution` and the
stage-oriented `Hardcaml_asic_flow_domain` library. The public native OCaml CLI
execs the installed native command for `stages` and delegates checkpoint/observation
queries and watch to native readers. There is no silent Python stage fallback.
The top-level CLI4 parser, paths/defaults and cold-query human views are native.
Coarse Classic `execute` uses the installed
native `Coarse_execution_service`, binding implementation, optional postcheck,
collection, acceptance and optional archive to the checked plan and shared `Runner`.
Coarse collection remains best-effort after failure
without replacing the primary failure. `Flow.Stage` / `Flow.Recipe` are pure typed
OCaml declarations; the native execution models and retained Python readers
validate the same schema-3 contract. Stage modules now describe all 80 Classic
occurrences and preparation checks the selected runtime's inventory/settings.
Recipes are contiguous, fresh from synthesis or resumed immediately after an
explicit source; no arbitrary DAG/custom steps or per-stage settings are exposed.

| Boundary | Classic endpoint | Standalone restart targets |
| --- | --- | --- |
| synthesis | `Yosys.Synthesis` | floorplan, placement |
| floorplan | `OpenROAD.Floorplan` | placement |
| placement | `OpenROAD.DetailedPlacement` | cts |
| cts | `OpenROAD.CTS` | routing |
| routing | `OpenROAD.DetailedRouting` | signoff |
| signoff | `Misc.ReportManufacturability` | none |

Composable recipes include every intervening boundary; direct synthesis → placement
is a standalone segment capability only. Official Classic successors/checkers and
configured gates are retained. CTS's later STA/repair belongs to routing; routing's
checkers/fill/extraction belong to signoff. Names are grouping boundaries, not a
license to skip checks or an acceptance verdict.

Native `stages` binds the exact tested Docker image/engine and rechecks it around
backend calls. A versioned request/reply protocol invokes `librelane_bridge`, which
uses official `State.loads` / `Flow.start` without copying backend orchestration.
Actual per-call transport records retain argv/resources/process/cleanup outcomes.
The OCaml checkpoint publisher copies all state views, configuration and hashed host/image-only closure, validates
in the bound runtime, removes write bits and atomically promotes a unique no-clobber
publication before announcing readiness. Schema-2 checkpoints declare exact restart
targets and path-bound compatibility. Retain original workspace/input/support/PDK
roots and bridge/image; copied views remove producer-run dependencies, not input-root
dependencies. `checkpoint-inspect` is host-only validation, not runtime readiness.
Older schema-1 physical checkpoints are not upgraded.

CLI `stages` composes `flow_observation` by default for fresh/resumed attempts at
`<resolved-workspace-parent>/observations`, outside the workspace. The parent must
exist; `--observation-store` overrides and `--no-observation` opts out. It supplies
early allocation, per-attempt hash-chained atomic records, advisory observed-writer
locks, `describe`, `inspect`, cursor `read-updates` and foreground incremental
`watch`. Warm polls reparse only new content but list/stat the whole prefix under a
trusted local immutable-record convention; liveness is best-effort filesystem/flock
evidence. Writer release triggers a final-tail drain. Publication precedes stage finish; physical completion, outer
outcome and acceptance remain distinct. Readers can reconnect after process exit;
writer loss leaves unresolved facts, never invented recovery/completion. This is
not the provisional store-wide fixture protocol, fsync durability, request
idempotency, takeover, raw step observation or completed Workbench integration.
Classic `run`/`execute` do not acquire this journal.

`finalization` allocates a separate operation snapshot selecting one completed fresh
six-stage execution. It maps actual synthesis/signoff evidence, validates retained
runtime closure without repeating implementation, and optionally invokes existing
TT precheck, gate replay and acceptance policy. Stage streams stay terminal and
checkpoints retain `acceptance: not_evaluated`. Resumed-attempt stitching or a
standalone signoff checkpoint is not eligible. No segmented artifact archive/GC,
native/macro/other-image support or cross-machine relocation is delivered.

The [implementation/review record](development/explicit-stage-refactor.md#final-independent-integration-review--2026-10-13)
records forced full checks, isolated installed-package verification and consumer
linkage. Curated repo evidence records [six physical stages](../evidence/librelane-observation/slice4-physical.json),
[actual observed execution](../evidence/librelane-observation/slice5-observed.json)
and [successful external acceptance](../evidence/librelane-observation/slice6-finalization.json).
The independent review re-audited retained evidence; it did not repeat EDA or adopt
a committed consumer pin. See the [phase closeout](phase_plan.md#explicit-stage-refactor-closeout).

### Provisional fixture/model boundary

The [v1 corpus and executable contract](../test/fixtures/provider_observation/v1/README.md)
model one immutable build/configuration, two executions, deferred checks, delayed
results, inherited versus equal-valued fresh timing, explicit skip/unreached/
interruption, later collection and prerequisite-rejected postcheck. Independent
acceptance covers six hand-authored snapshots, 13 queries, 15 replay cases and
21 recovery pairs; [test evidence](phase_plan.md#provider-observation-fixture-acceptance)
records the 50-test suite and full provider regression pass.

Store-wide cursor, request idempotency, BUSY ownership through outer outcome,
generation fencing, transitive readiness and history/evidence retention are
**provisional logical decisions**. Execute termination requires explicit terminal
implementation; completed implementation can still outer-fail. Collect success
requires its own publication. Recovery validates a full retained prefix separately
and restores the supplied snapshot for suffix replay. A snapshot file is not a
resumable checkpoint. Runtime locking, fsync/data durability, authentic persistent
history and producer liveness are unproven; deeper hierarchy is unmodeled. Silence
or reader disconnect never supplies interruption/completion facts.

The prior LibreLane observation probe remains historically **BLOCKED**. Later
selected-runtime official cases and real physical handoffs succeeded; see the
delivered contracts above. The synthetic fixture is not upgraded by that delivery.

### Domain facts and identities

Broader proposed contract: describe capabilities/versions; list/inspect explicit stores;
correlate a request with an early allocated operation/run; inspect step occurrences;
replay recorded updates; read versioned snapshots and evidence references.
Events describe allocation, lifecycle, publication and operation outcomes, never
UI refresh actions. CLI contract 4 requires explicit `--json` for machine payloads,
including additive stage/checkpoint/observation/finalization commands. Presentation
consumes existing results without new probes or policy changes; observed stages and
finalization preserve flushed allocation/terminal JSONL. Watch uses separate reader
`updates`/`status` envelopes; reader exit 0 means a recorded terminal outcome, not
flow acceptance. The example accepts exact integer contracts 2/3/4 for Classic,
requires 4 for `project run --endpoint`, validates modes before emission and selects
a unique workspace without precreating it. Store-wide reads and Workbench cancellation
remain separate scope. See [review and limits](development/flow-journal.md).

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

For the remaining store-wide protocol, choose one coordinated provider write path
for `execute` and standalone operations.
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

On 2026-10-12, the literal `.toolchain/.venv/bin/python` reported Python 3.12.3
and LibreLane `3.1.0.dev3`; bundles request Python 3.11. The authorized
[experiment](../experiments/librelane_observation/README.md) reached official
`Config.load` and failed at `TclUtils._eval_env` importing missing `tkinter`
([evidence](../evidence/librelane-observation/blocked-local.json), exit 2).
**Zero of eleven authored cases executed; synthetic PDK configuration is not
validated and no observation seam is demonstrated.** Targeted standard-location
checks found no compatible Python 3.12 Tcl/Tk module. This remains historical
evidence. The [actual managed-runtime acceptance](../evidence/managed-python/actual-runtime.json)
now proves Python 3.11.17, Tcl 9.0.4 and official LibreLane Tcl evaluation in a
disposable venv. Subsequently, all 12 official-API cases passed in the selected
image, and real consumer synthesis/physical continuation succeeded
([slice-2 evidence](../evidence/librelane-observation/slice2-real.json)). Later
production stages, observation and acceptance are recorded above. The blocked
probe and Tcl smoke remain earlier evidence, not the basis for those later claims.

Source inspection shows `SequentialFlow.run` calls `step.start` directly; `Step.start` is
final. Overriding `Flow.start_step` is not a demonstrated lifecycle hook.

Step substitutions and `Step.run` are extension points; the latter returns metric
updates before merging with inherited state, but does not cover gated steps or
failures before/after computation. Per-step state files are directly written and
do not expose every lifecycle fact. Prove supported hooks/structured observation
with stated limits, or propose narrow upstream instrumentation. Do not copy the
engine's orchestration. Full-flow acceptance must test the Dockerized path and
actual descendant cancellation, not only a local Python probe.

The bounded interpreter-path fix is delivered: CLI `resolve_paths` now anchors
interpreter paths lexically, retaining venv symlinks for explicit and inferred
flow/precheck selections. Real no-pip symlinked venv tests, including isolated
installed full-execute fixtures, pass; [evidence](phase_plan.md#tool-environment-ownership-first-slice)
does not establish live provider acceptance. The generated local tool environment
also retains stale `/home/wayne/devel/jane/asic` paths; the probe used the literal
current interpreter path without sourcing it.

## 9. Core review and development specimen

### Refactor review — bounded implementation delivered

**Keep the P0–P3 model; strengthen boundaries and refactor P4 internals in slices.**
The integration needs richer execution evidence, not a different RAM behavior or
project declaration lifecycle. Completed historical milestones remain complete;
they do not claim that future observation requirements have already been met.

| Area | Recommendation | Timing |
| --- | --- | --- |
| Project/context/Elaborated_project, resource semantics | Reuse with current tests | No rewrite prerequisite |
| `Resolved_flow` construction | Private interface enforces resolution-only construction; readers preserved | Implemented; evidence in phase plan |
| Bundle/manifest | Preserve format and determinism; additive provenance and declared-fact export | Coordinate with P6.5a and result contract |
| Runner/dispatcher | Shared coarse/stage runner behind existing entry points | Delivered bounded implementation |
| Collection/reporting | Canonical segmented evidence mapping and final aggregation; existing policy | Delivered for fresh six-stage finalization; fine step extraction remains open |
| Archives | Preserve snapshot/evidence closure at an explicit revision | Alongside snapshots, before scratch deletion is advertised |
| Resource matching, multi-target abstraction | Revisit on concrete resource/backend demand | Backlog, not pre-P6 gates |

For each refactor, state the invariant, keep existing positive/negative tests and
add the new acceptance case. Do not combine naming/package reshuffles, schema
changes and new observation behavior into one unreviewable rewrite.

### `hardcaml_asic_example`

The owner-created [sibling development specimen](../../hardcaml_asic_example/README.md)
now implements a fixed single-clock 16 × 8 controlled FIFO with explicit register
storage, a pure list-based scoreboard, directed/seeded regressions, a consumer-owned
TT wrapper/declaration and a project-centered `describe|emit|preflight|run` CLI. Its public facade
exposes `project ()` plus `Tt_wrapper`; shared emission belongs to the provider.
Project run requires Classic `--stage synthesis|full` or explicit-stage `--endpoint`
and invokes implementation only. The installed provider owns inspect/watch; no project
execute interface is delivered. Its source root is discovered or explicit,
not a required hardcoded sibling path. Owner initial ref
`8e4577f6c72cc689cbc92daeb5f8ae083cf970e0` now exists; it alone does not establish
a clean tree or a dependency pin. The specimen now has a recorded ASIC baseline
plus an explicit development override. The recorded `171476...` baseline lacks the
new Project API and is refused by current refresh validation. Development refresh
works; adopting a committed compatible candidate remains an owner action.

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
[project-entrypoint evidence](phase_plan.md#project-centered-entrypoint-acceptance).
Synthetic committed fixtures remain separate provenance tests. This does not
establish full environment locking, embedded source identity or source-access-denied
P6.6 acceptance. Later explicit-stage work proved actual specimen physical and
external acceptance, plus isolated linkage of the additive recipe executable;
it did not adopt a committed pin or close the broader ASIC P6 gates. Workbench
application integration remains separate from the delivered provider readers.
