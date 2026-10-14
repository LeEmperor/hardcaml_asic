# OCaml-first flow infrastructure and stage decomposition

**Status:** implementation in progress. Native public CLI, explicit/coarse
execution, results/acceptance/archive services, thin Python runtime installation,
and responsibility-oriented source organization are delivered as of 2026-10-14.
Physical and installed-service verification are recorded separately. Finer
per-operation execution and modularized flows remain later work. Written 2026-10-13.

See the [implementation record](development/flow-infrastructure-progress.md) and
[active queue](phase_plan.md#ocaml-first-flow-infrastructure) for delivered
boundaries, verification, and remaining work. Section 2 preserves the historical
starting-point inventory; section 5 records delivered destination status alongside
the original sketch.

**Purpose:** reorganize the provider around explicit stages, backend integration,
and OCaml-owned execution infrastructure. This builds much of the foundation for
the later **modularized flow** feature: project-owned flow definitions and
configuration profiles that compose implementation methodologies.

Modularized flow-file support is a later feature, not a deliverable claimed by
this infrastructure refactor. The [phase plan](phase_plan.md) remains the active
implementation queue; the slices below describe dependencies and acceptance
criteria rather than a second queue. The
[architecture](architecture.md) describes current ownership and capabilities.

## 1. Motivation and intended outcome

The current provider has individually callable physical segments, but their
structure is difficult to discover. Six stage names map to cut points in
LibreLane Classic; most execution, checkpoint, observation, and result logic
lives in a relatively flat Python package. There are no corresponding standalone
placement, CTS, or routing implementations in the repository.

The intended refactor should make it straightforward to answer:

- What operations belong to a stage?
- What inputs, outputs, and configuration does each operation require?
- Which parts are provider policy, and which are LibreLane integration?
- Which component owns execution, persistence, and observation?
- Where would a new placement operation or CTS configuration be implemented?

The preferred language direction is OCaml for provider-owned models and control
logic, with a small Python adapter for LibreLane's native APIs. Physical stages
should be visible in the source layout without forcing cross-cutting execution
and storage code into stage directories.

## 2. Current implementation: where the boundaries are

### Six cut points, one upstream flow

The current stage declarations and execution mapping live in:

| File | Responsibility |
| --- | --- |
| [`lib/flow_stage.ml`](../lib/flow_stage.ml) | OCaml stage names and advertised capabilities |
| [`lib/flow_recipe.ml`](../lib/flow_recipe.ml) | Pure, contiguous stage recipes and serialization |
| [`flow/hardcaml_asic_flow/execution_plan.py`](../flow/hardcaml_asic_flow/execution_plan.py) | Python stage order, endpoints, restart targets, and plan validation |
| [`flow/hardcaml_asic_flow/stages.py`](../flow/hardcaml_asic_flow/stages.py) | Segment execution requests and checkpoint publication |
| [`flow/hardcaml_asic_flow/librelane_bridge.py`](../flow/hardcaml_asic_flow/librelane_bridge.py) | Native LibreLane configuration/state loading and segment invocation |

The endpoints are:

| Provider boundary | LibreLane Classic endpoint |
| --- | --- |
| Synthesis | `Yosys.Synthesis` |
| Floorplan | `OpenROAD.Floorplan` |
| Placement | `OpenROAD.DetailedPlacement` |
| CTS | `OpenROAD.CTS` |
| Routing | `OpenROAD.DetailedRouting` |
| Signoff | `Misc.ReportManufacturability` |

The bridge selects Classic and calls `Flow.start` with an initial state and a
`frm`/`to` range. Continuations start at the immediate successor of the previous
endpoint, retaining intervening checks and configured gates.

These are grouping boundaries, not six self-contained domain implementations.
For example, the placement segment includes power-network and other setup after
the floorplan endpoint. Post-CTS STA/repair is currently part of the routing
segment; post-routing checks, fill, and extraction are part of signoff.

Boundary mappings are repeated across the OCaml API, Python planner, and runtime
bridge. The refactor should establish one maintained capability definition, with
generated representations or explicit cross-language contract checks where needed.
Static advertised capabilities must remain distinct from actual runtime readiness.

See the [recipe guide](guides/ocaml-stage-recipes.md) for the delivered API.

### What `lib/` and `flow/` mean today

`lib/` is the OCaml library linked into consumer projects. It owns resource
semantics, declarations, elaboration, target/timing resolution, bundle emission,
and pure recipe declarations. It does not execute physical implementation.

`flow/` contains the installed `hardcaml-asic-flow` executable and its Python
implementation. It owns execution planning, runtime checks, process/container
invocation, checkpoints, observation, collection, acceptance, and archiving.
[`flow/dune`](../flow/dune) packages these files alongside the OCaml library in
the same installation artifact.

```text
Consumer OCaml application
  -> Hardcaml_asic library
  -> RTL/configuration/manifest bundle and recipe data
  -> installed execution CLI
  -> LibreLane
  -> physical implementation tools
```

Files and process invocation form the application boundary; there is no embedded
OCaml/Python runtime binding. Separation between input generation and execution
remains valuable, but does not require those responsibilities to use different
languages.

### Ownership of the Python code

The modules under `flow/hardcaml_asic_flow/` are provider-maintained code, not a
vendored Tiny Tapeout implementation. Repository scripts mostly provide
development entry points into that package. Tests and experiments are also
provider-maintained code.

LibreLane is an external Python flow engine. Tiny Tapeout support tools and
precheck are separately provisioned external dependencies, currently represented
in the local toolchain by the TT checkout. Our code invokes them and interprets
their outputs. Provider orchestration and external tool implementation must stay
clearly distinguishable in the new layout.

## 3. Target responsibility and language boundaries

```text
OCaml provider
  project/resource semantics and input emission
  stage/step declarations and configuration
  plan validation and backend resolution
  run orchestration and process supervision
  storage, checkpoint publication, observation
  result models, finalization, reporting
                    |
          versioned request/result protocol
                    |
Small Python LibreLane adapter
  load native LibreLane configuration and State
  validate backend-specific state/configuration
  invoke supported LibreLane APIs
  return artifacts and backend evidence
                    |
LibreLane -> Yosys / OpenROAD / other implementation tools
```

OCaml owns the provider's execution plan and run lifecycle. LibreLane owns
execution of the backend steps delegated to it. The adapter should not become
a second provider scheduler, and the OCaml runner should not reproduce
LibreLane's internal tool orchestration.

Process execution, Docker invocation, hashing, JSON decoding, atomic publication,
and journaling do not inherently require Python. The strongest reason to retain
Python is direct access to LibreLane's configuration, state, and flow APIs.
OpenROAD itself does not require the outer provider to be written in Python.

The bridge protocol should explicitly identify its version, requested operation,
input state/configuration, expected backend capabilities, output locations, and
returned outcome/artifact evidence. Process exit and cancellation behavior must
be specified alongside the data format. Provider publication should occur only
after the returned candidate has passed the required validation.

Backend-specific probes or helpers may remain in Python where they require that
runtime. The objective is clear ownership, not a numerical Python-line target.

## 4. Stages, steps, analysis, and checkpoints

### Two levels of structure

A **stage** is a meaningful implementation phase and a useful grouping for users,
results, and observation. A **step** is an operation within a stage that can
eventually be configured or composed independently.

```text
placement
  global placement
  design repair
  detailed placement
  analysis
```

LibreLane already exposes finer operations. Inspection of the locally installed
Classic source found `OpenROAD.GlobalPlacement`, `OpenROAD.RepairDesignPostGPL`,
`OpenROAD.DetailedPlacement`, and `OpenROAD.STAMidPNR`, as well as IO placement,
checks, and other supporting steps. Post-CTS timing optimization is exposed as
`OpenROAD.ResizerTimingPostCTS`.

This establishes a useful decomposition opportunity, not provider support for
arbitrary sequences. Exact availability, ordering, gates, and state requirements
must be verified against the selected execution runtime. Design repair should
not be presented as interchangeable with every form of timing repair.

### Contracts for executable operations

Each supported operation should have explicit:

- Required input artifacts and design-state preconditions.
- Produced artifacts and design-state postconditions.
- Configuration types, units, defaults, and validation.
- Backend implementation and runtime requirements.
- Transformation versus read-only analysis behavior.
- Result/evidence interpretation and observation identity.

Analysis operations such as timing analysis can be reused by several stage
recipes. Their shared implementation need not be duplicated under placement,
CTS, and routing.

An operation definition also differs from an occurrence of that operation in a
plan: repeated timing analyses need distinct occurrence identities. A display
name or stage name alone is insufficient to correlate their results.

### Execution granularity is not checkpoint granularity

A step may be selectable in a plan without having a supported durable restart
checkpoint after it. Fine-grained decomposition should not automatically promise
restartability, portable state, or acceptance after every operation.

Initially preserve the existing six checkpoint boundaries while introducing
clearer internal operation contracts. Any regrouping of Classic steps must be
an explicit semantic change with evidence that checks and prerequisites survive;
directory moves alone must not redefine persisted boundary names.

## 5. Proposed hybrid source layout

Organize top-level code by responsibility, with stage-specific modules inside
the flow layer. The following is the original destination sketch, not a current
file inventory.

**Delivered destination status (2026-10-14):** stage domains, shared analysis and
LibreLane mapping are under `lib/flow/{stages,analysis,backends/librelane}`. Native
execution is now organized under `lib/execution/{storage,observation,results,archive,runtime,backends/librelane}`,
with runner, execution plan and coarse orchestration at its root. A single public
`hardcaml_asic.execution` library uses unqualified subdirectories, preserving all
`Hardcaml_asic_execution.*` names. C stubs remain at that library root. See the
[current module map](architecture.md#current-native-execution-source-map).
Hardware/project/resource reorganization, retired Python SOURCE relocation and
flow definition/profile authoring remain later work. The sketch's top-level
storage/results/backend directories and illustrative module names were not
adopted as new public libraries or namespaces.

```text
lib/
  project/
  resources/
  bundle/

  flow/
    definition.ml
    profile.ml
    execution_plan.ml
    stages/
      synthesis/
      floorplan/
      placement/
        config.ml
        global_placement.ml
        design_repair.ml
        detailed_placement.ml
        recipe.ml
      cts/
      routing/
      signoff/
    analysis/
      timing.ml

  execution/
    runner.ml
    transport.ml
  storage/
    checkpoint.ml
    result_store.ml
    archive.ml
  observation/
  results/
  backends/
    librelane/
      adapter.ml
      config.ml
      capabilities.ml

bin/
  hardcaml_asic_flow.ml

backend_runtime/
  librelane/
    bridge.py

scripts/
```

`definition.ml` and `profile.ml` denote eventual homes for flow authoring concepts;
their presence in this sketch does not bring the later user feature into scope.
Directories should appear when they have actual responsibilities and contents.

Stage modules own domain contracts, typed settings, and reusable stage recipes.
Backend modules map those contracts onto LibreLane. Execution owns lifecycle and
process handling. Storage owns publication and retention. Results owns shared
aggregation and acceptance, while stage-specific interpretation can live beside
the stage.

Dependencies should flow from declarations toward resolution and execution:
domain declarations do not import the CLI or invoke tools; a composition layer
selects backend implementations and supplies storage/transport services.

Use internal OCaml libraries or qualified module layouts as appropriate to avoid
collisions among names such as `Config` and `Recipe`. Keep hardware-only consumers
from acquiring unnecessary execution dependencies. Source paths, public module
names, package boundaries, and installed runtime-data paths are separate decisions.

## 6. Foundation for the later modularized flow feature

The future feature will allow a consumer such as `hardcaml_asic_example` to own
flow definitions and configuration profiles, then request executions of those
methodologies. Its conceptual model is:

| Concept | Meaning |
| --- | --- |
| Project | Hardware, target, clocks, constraints, resources |
| Flow definition | Selected operations and their composition |
| Configuration profile | Named implementation choices |
| Resolved execution plan | Expanded, validated operations and effective settings |
| Run | One execution against specific inputs |

OCaml authoring compiled by the consumer's Dune build, emitting a versioned
declarative specification, is the preferred direction. A `flow.ml` would be an
ordinary compiled module, not an OCaml file dynamically loaded by Python. A
custom `.flow` language is not an infrastructure prerequisite.

Existing `Resolved_flow` describes validated project/target configuration. An
execution-level plan should have a distinct name and responsibility.

### Configuration ownership and identity

Preserve the distinction between:

- Project/target facts: ports, geometry, clocks, constraints, and resource intent.
- Methodology settings: supported placement, CTS, and routing choices.
- Execution settings: workspaces, tool roots, transport, and resource limits.

Effective settings need explicit precedence and provenance. Backend defaults,
flow defaults, a selected profile, and explicit overrides must resolve into a
saved concrete configuration rather than leaving only a mutable preset name.

Current bundles already contain implementation settings, while recipes are
separate from bundle identity. Before introducing profiles, decide whether their
settings participate in bundle generation or produce a separately identified
derived execution configuration. Neither path permits silent mutation of a
published bundle. Record behavior-relevant execution settings as well.

### CTS variants and checkpoint reuse

Fresh runs with different CTS settings are simpler than branching from a retained
placement checkpoint. The current bridge requires exact resolved-configuration
and dependency-closure agreement before continuation; changing a profile is not
currently a supported checkpoint operation.

Later reuse requires proving whether a changed setting could have affected the
checkpoint's production. Supported settings should identify their actual backend
consumers and earliest affected operation, rather than deriving compatibility
solely from the directory or profile section that contains them.

```text
synthesis -> floorplan -> placement checkpoint
                             |-> CTS profile A -> routing -> signoff
                             |-> CTS profile B -> routing -> signoff
```

This becomes valid only for explicitly supported downstream changes. Unknown
backend overrides should conservatively require a fresh run until their effects
are classified. Existing path/runtime restrictions also continue to apply.

Branching needs preserved checkpoint lineage, effective configuration, and
inherited evidence. Current finalization requires a completed fresh six-stage
execution; accepting a resumed branch will require a new lineage-aware
aggregation/finalization contract.

### Deferred user-facing capabilities

The following are later modularized-flow work:

- Named project-owned flow files and selectable methodology profiles.
- Arbitrary supported composition and custom operation insertion.
- Step substitution and alternative stage implementations.
- Configuration-changing checkpoint branches and inherited-run finalization.
- Parameter sweeps, generalized DAG scheduling, and automatic artifact reuse.

The infrastructure refactor should make these extensions possible without
claiming them or building a general scheduler in advance.

## 7. Proposed migration slices

### Slice 1: inventory and make current boundaries explicit

Map existing modules, public interfaces, installed files, schemas, and tests to
their target responsibilities. Establish the maintained stage/capability source
and make the current Classic segment contents discoverable.

**Acceptance:** the same plans resolve to the same supported endpoints and
successors; cross-language representations agree; installed consumers can inspect
capabilities without relying on a source checkout.

### Slice 2: define the backend adapter contract

Isolate LibreLane-native operations behind a versioned request/result protocol.
Separate backend execution and validation from provider publication and lifecycle
policy. The existing Python runner can initially consume this interface.

**Acceptance:** representative success, backend failure, incompatible state,
malformed response, and interruption cases have explicit outcomes; candidates
cannot be mistaken for published checkpoints.

### Slice 3: establish OCaml models and stage-oriented modules

Introduce typed execution/operation models and stage-specific configuration
contracts. Extract backend mappings and shared analysis definitions. Resolve the
Dune/public-namespace design before moving substantial source trees.

**Acceptance:** existing supported recipes round-trip and preserve their meaning;
invalid transitions/configurations are rejected; consumer compilation and bundle
emission retain their documented behavior.

### Slice 4: migrate provider control logic incrementally

Move cohesive responsibilities from Python into OCaml: plan handling, orchestration,
storage/publication, observation, results, and CLI composition. Choose and record
an order based on actual dependencies. Each slice has one authoritative owner;
temporary delegation is explicit and does not create competing writers.

**Acceptance:** preserve command contracts, exit/signal behavior, process cleanup,
run/checkpoint identities, journal ordering, reader compatibility, publication
invariants, and acceptance distinctions. Test through the installed executable,
not only in-process OCaml functions.

### Slice 5: expose bounded finer-grained execution

Use placement as the first decomposition specimen. Map supported global
placement, repair, detailed placement, and analysis operations to upstream APIs,
retaining required setup/check steps and configured gates. Continue to offer the
existing coarse recipe as a standard composition.

**Acceptance:** selected-runtime execution proves the intended sequence and
artifact handoffs, with meaningful comparison against the existing coarse path.
Any new restart boundaries require their own evidence. Backend step observation
must distinguish genuinely observed facts from inferred plan progress.

### Slice 6: close out infrastructure readiness

Verify package installation, source-checkout independence, consumer integration,
documentation, and representative physical execution. Remove replaced Python
implementations only after their responsibilities and contracts are covered.

**Acceptance:** the installed OCaml CLI can execute the supported standard flow
through the isolated backend adapter, publish and inspect checkpoints, expose
observations, and finalize results under the existing supported policy. Stage
modules and backend boundaries are discoverable, and remaining limitations are
explicit. This is readiness for later modularized-flow development, not delivery
of that feature.

## 8. Refactor invariants and verification

Throughout the migration:

- Preserve project elaboration/resource semantics and separation from execution.
- Preserve immutable published inputs and explicit selection of existing runs.
- Keep physical completion, checkpoint readiness, process outcome, and acceptance
  as distinct facts.
- Retain required Classic successor checks and gates.
- Preserve readable historical records or introduce explicit versioned readers.
- Keep checkpoint runtime/path compatibility honest; decomposition does not imply
  relocation or recovery support.
- Keep provider records authoritative and independent of Workbench presentation.
- Package the CLI and backend runtime so installed operation does not depend on
  this source checkout.

Use existing regression suites as the baseline, add contract tests at changed
boundaries, and perform actual selected-runtime execution for new backend handoffs.
An OCaml type check or mocked adapter test does not establish a physical restart
capability. Consumer verification should include the independently installed
`hardcaml_asic_example` path.

Separate mechanical moves, schema/API changes, and execution-semantic changes
into reviewable slices. File moves can also affect source-artifact inventories,
installed resource lookup, and bridge identity; account for those effects rather
than treating every move as operationally invisible.

## 9. Decisions to settle before implementation

1. Internal Dune library boundaries and public OCaml namespaces.
2. The maintained source of backend capabilities and how other runtimes consume it.
3. Adapter protocol versions, process lifecycle, and error representation.
4. Migration order and compatibility policy for CLI and persisted records.
5. Exact placement decomposition under the supported LibreLane runtime.
6. Whether any existing stage grouping should change, with explicit identity and
   compatibility consequences.
7. Configuration identity and ownership before later profile support.

The architectural direction is: **make the domain stages visible, put provider
policy and orchestration in OCaml, retain a focused LibreLane adapter, and build
explicit contracts that later project-owned modularized flows can compose.**
