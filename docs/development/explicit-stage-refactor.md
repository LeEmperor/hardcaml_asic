# Explicit flow stages and execution plans

Status: bounded implementation delivered and independently reviewed, 2026-10-13;
documentation reconciliation complete. See the [quickstart](../guides/stage-quickstart.md),
[recipe guide](../guides/ocaml-stage-recipes.md) and
[current phase closeout](../phase_plan.md#explicit-stage-refactor-closeout).

Delivered: shared coarse runner, six sequential physical boundaries, schema-3
OCaml/Python recipes, exact-runtime path-bound checkpoint publication/restarts,
opt-in per-attempt inspect/cursor observation, and separate fresh-six-stage
finalization using the existing acceptance policy. Implementation is modules in
the existing package, not a backend directory rewrite. Full checks, actual physical
and external acceptance evidence, and isolated installed consumer linkage passed.

Remaining scope: committed consumer-pin adoption, full Workbench application
integration, store-wide journal/catalog/idempotency/fsync, fine backend-step events,
arbitrary DAG/custom steps or per-stage settings, execution recovery, native/macros/
other images, relocation, resumed-attempt or standalone signoff finalization, and
segmented artifact archive/GC. Earlier blocked and slice-specific limits below are
dated history, superseded only where later evidence explicitly proves delivery.

## Goal

Make flow composition, ASIC stages, backend step occurrences, artifact handoffs,
and execution status explicit. Preserve the existing project/elaboration/resource
model and existing acceptance semantics while evolving the execution layer.

The intended architecture is:

```text
Project / frontend -> published bundle + recipe -> resolved execution plan
    -> runner (lifecycle, artifacts, results, observation)
    -> backend adapter -> execution transport -> selected tool runtime
```

A recipe describes requested composition. A plan resolves executable actions,
dependencies, gates, and endpoints. A stage groups ASIC work; a backend step is
an individual action; an occurrence identifies its execution in an attempt.
A displayed stage does not automatically promise an independently resumable
checkpoint. Process completion, valid handoff, and acceptance are separate facts.

## Pre-refactor foundations (historical baseline)

- `Project`, `Elaborated_project`, and `Resolved_flow` retain validated intent.
- `Bundle.publish` provides identity-addressed input publication in the current
  working tree; explicit-directory emission remains supported.
- `runtime_contract`, `runtime_observation`, and `execution_transport` separate
  requirements, environment observations, and concrete execution bindings.
- `result_store` supplies allocation and atomic JSON replacement, not a replayable
  observation journal or power-loss durability guarantee.
- The current dispatcher composes preflight/implementation/postcheck/collection/
  acceptance/archive, while LibreLane implementation remains a coarse subprocess.
- Existing provider-observation fixtures are synthetic contracts, not live status.

## Original sequential implementation plan (historical)

1. Introduce explicit coarse execution plans and a shared runner around existing
   behavior. Keep CLI presentation separate and retain historical record readers.
   Extract existing services rather than duplicating toolchain or lifecycle logic.
2. Prove LibreLane observation and handoff capabilities using the selected runtime
   and owned transport. Exercise actual supported APIs; record limitations of
   lifecycle hooks, gated steps, metric provenance, and cancellation. Identify how
   any provider bridge is supplied to and identified inside the container.
3. Add validated stage/checkpoint contracts for demonstrated boundaries and expose
   configurable composition. Preserve the default backend sequence and checks.
   Restart needs complete state/configuration/collateral, not merely a report JSON.
4. Integrate persistent occurrence status and artifact/result publication, with
   explicit standalone/composed-operation ownership. Extend observation contracts
   where needed; do not claim unsupported replay or crash recovery.
5. Exercise the consumer `hardcaml_asic_example`, including real backend runs where
   available. Update architectural and operating documentation with actual scope,
   evidence, and remaining work.

Each slice is delegated to one general agent, which completes and reports before
the next is started. Slice boundaries may be narrowed or adjusted in response to
backend evidence. This planning context performs only small documentation edits.

## Invariants and decisions

- Keep recipe identity separate from run identity and runtime binding. Bind the
  implementation runtime for the run; do not re-resolve mutable image tags per step.
- Stages consume declared inputs and return declared outputs. The runner owns
  publication and retention. Publish complete artifacts before announcing readiness.
- Keep immutable input bundles separate from mutable work directories. Physical
  checkpoint publication needs its own manifest and compatibility validation.
- Preserve metric origin; equal values cannot identify newly produced evidence.
- Distinguish skipped, unreached, failed, interrupted, and completed occurrences.
- A stage is not necessarily one process or one container. Prefer supported backend
  composition and instrumentation over copying LibreLane's orchestration engine.
- Workbench consumes provider facts and structured interfaces; it does not own flow
  execution semantics. Human CLI output is not a persistent observation protocol.
- Automatic physical-result caching, general DAG scheduling, additional EDA backends,
  and broad frontend rewrites are not prerequisites for this implementation.

## Execution constraints

- Preserve all pre-existing working-tree changes, including untracked files.
- Do not stage, commit, amend, push, or create AI-attributed Git history. Read-only
  Git inspection and fixture-local Git commands needed by tests are permitted, but
  must not attribute repository changes to AI authorship.
- Every Dune build/test/exec invocation must use `-j 20`; inspect wrappers and scripts
  before invoking them to ensure nested Dune commands respect this limit.
- Use `hardcaml_asic_example` as the consumer validation design. Long Python/backend
  experiments are permitted where needed to prove stage behavior.
- Record exact verification and blockers. Synthetic tests do not prove physical
  execution, and tool-runtime probes do not prove flow lifecycle observation.

## Implementation record

### Slice 1 implemented — 2026-10-13

- Added `execution_plan.Action`, `Plan`, `resolve(endpoint, archive=...)`, and
  strict version-1 JSON round-tripping. The bounded five-action service plan
  declares coarse stage groups, symbolic inputs/outputs, dependencies and gates.
  Synthesis/full and optional archive retain the existing composition; preflight
  and staging remain inside the single LibreLane implementation action.
- Added `runner.ServiceAdapter` and `execute(plan, adapter)`, returning an
  inspectable `Execution` with serializable occurrence facts. Semantic action keys
  are independent of display labels; occurrence IDs combine a fresh attempt ID
  with the action key. Disabled actions are skipped; gated actions not reached
  remain unreached. Process completion and acceptance verdicts are separate facts.
- The runner owns sequencing, scoped interruption handling and best-effort
  collection after run/postcheck failure or interruption. Collection errors cannot
  replace the primary failure. `cli.execute_sequence` now only adapts presentation
  and the historical JSON aggregate, including its legacy best-effort conventions.
  Existing services, runtime binding/transport and atomic result-store writes are
  reused; their implementations and historical record readers are unchanged.
- Packaging installs both new modules. `@test/coarse-runner` covers plan contracts,
  identities, sequencing, handoffs, errors, acceptance gates and real SIGTERM
  handling, including existing result services with synthetic external boundaries.
  The installed-prefix wrapper now builds with `-j 20`.
- Verification passed: `dune build -j 20 @test/coarse-runner @test/result-store
  @test/execution-transport @test/runtime-contract @test/runtime-observation
  @install` (new runner suite finally 11 tests; CLI 43; store 45; transport 10;
  runtime contract 8; observation 18). Direct phase4/report/archive/packaging suites
  passed (26/15/20/17 tests). Final `dune build -j 20 @test/coarse-runner @install`
  and `python3 -B test/test_installed_prefix.py` passed (47 installed-prefix tests).
  An initial concurrent installed-prefix build hit Dune's workspace lock before
  running tests; sequential retries passed.
- Next integration points: prove actual LibreLane hooks behind the coarse
  implementation action using `phase4` and `execution_transport`; extend the
  validated plan only for demonstrated boundaries; use occurrence action keys
  rather than labels for future persistent status. `Execution.as_dict()` is an
  in-memory snapshot, not a journal. Symbolic inputs/outputs are service handoff
  descriptions, not validated checkpoint/artifact manifests. No fine-stage hooks,
  configurable DAG, replay, restart, or crash-recovery claim is made. Errors before
  a run outcome exists propagate without inventing a collectable run directory.
  Verification used fixture external tools, not a physical backend run;
   `hardcaml_asic_example` was not modified or physically exercised in this slice.

### Slice 2 implemented — 2026-10-13

- Reused the existing consumer `_flow_tools` and official LibreLane image; no
  provisioning or consumer edits. Normal `phase4.preflight` passed without issues
  or waivers: host Python 3.11.17/Tcl ready; container Python 3.13.13/LibreLane
  3.1.0.dev3 under the bundle's supported-distribution policy. Docker 29.8.1,
  immutable local image ID
  `sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a`,
  `-I -B`, UID/GID 1000:1000, scratch project RW and consumer PDK RO. The bridge is
  copied explicitly into the mounted project and invoked by absolute script path;
  both host and container record its hash. Existing owned transport/cleanup and
  `phase4.run_logged` are reused. No orchestration engine was copied or overridden.
- Added bounded experiment helpers `run.py`, `backend_probe.py`, `verify.py` and
  `cancellation.py` under `experiments/librelane_observation/`. The normal Classic
  constructor and supported `Substitute`/`Step.run` extensions are used; final
  `Flow.start`/`Step.start` and `SequentialFlow.run` remain identical. Corrected the
  earlier synthetic probe for isolated sibling loading and actual validation
  behavior. All **12 synthetic official-API cases** passed in the selected image.
- **Real consumer boundary passed twice:** six synthesis occurrences through
  `Yosys.Synthesis`; copy header/netlist views plus official serialized state and
  resolved config; rename the original synthesis run so its absolute paths vanish;
  then a fresh container/process/toolbox starts with `State.loads` and
  `Flow.start(with_initial_state=state, frm="Checker.YosysUnmappedCells", to=...)`.
  Seven continuation steps reached `OpenROAD.Floorplan`; 28 reached
  `OpenROAD.DetailedPlacement`, producing real ODB/DEF. Configuration and bridge
  hashes match across each boundary. Immediate successor checkers and pre-PNR STA
  are preserved. These endpoints are supported segment limits; only synthesis →
  fresh physical was proved as a restart boundary.
- Raw stores: `/tmp/opencode/librelane-slice2-2c7gsbb8` (floorplan),
  `/tmp/opencode/librelane-slice2-cp1weqzt` (detailed placement),
  `/tmp/opencode/librelane-cancellation-tdf1qq17` (cancellation). Retain these for
  re-audit; no large raw EDA data was placed in the checkout. The concise evidence
  is `evidence/librelane-observation/slice2-real.json`; exact tools, hashes, files,
  failed development attempts and path dependencies are recorded in
  `experiments/librelane_observation/SLICE2.md`.
- Verification/reproduction from the provider root (all exited 0):

  ```sh
  python3 -B experiments/librelane_observation/run.py --consumer /home/wayne/devel/jane/hardcaml_asic_example --bundle /home/wayne/devel/jane/hardcaml_asic_example/_flow_results/bundles/bbbda7ff53ea33cabf0063f7b26509bf601420ad5ab46c07e511fc8e9ee79477
  python3 -B experiments/librelane_observation/run.py --consumer /home/wayne/devel/jane/hardcaml_asic_example --bundle /home/wayne/devel/jane/hardcaml_asic_example/_flow_results/bundles/bbbda7ff53ea33cabf0063f7b26509bf601420ad5ab46c07e511fc8e9ee79477 --physical-to OpenROAD.DetailedPlacement --timeout 600
  python3 -B experiments/librelane_observation/verify.py /tmp/opencode/librelane-slice2-2c7gsbb8
  python3 -B experiments/librelane_observation/verify.py /tmp/opencode/librelane-slice2-cp1weqzt
  python3 -B experiments/librelane_observation/cancellation.py
  dune build -j 20 @test/coarse-runner @test/execution-transport @test/runtime-observation
  ```

- Observation limits demonstrated: body return precedes validation/state/runtime
  writes; state-file presence can survive start failure; missing view paths can
  survive type validation and fail final snapshot; deferred errors permit later
  bodies before outer failure. Raw updates distinguish inheritance from equal-value
  remeasurement. Flow gates/skips remain outside body hooks; internal body no-ops
  can log “Skipping” while returning successful occurrences. Full-step lifecycle
  and skip-reason events need narrow upstream instrumentation, not a fabricated
  `Flow.start_step` hook or copied sequencing. Real metrics include nonfinite
  sentinels, so public extraction needs explicit unavailable-value semantics.
- The separate cancellation run proves real timeout/owned-container removal and
  disappearance of observed parent/child PID identities for an official synthetic
  subprocess body. It does not prove graceful EDA cancellation or a backend
  interruption callback. Full flow/CTS/routing/GDS/signoff/postcheck acceptance,
  cross-machine relocation, durable journal and crash recovery remain untested.
  The physical flow has **no environment blocker** at these demonstrated limits.
- Final checks passed: `git diff --check`, AST parsing of all six experiment Python
  modules, strict parsing of the concise evidence JSON; Docker showed no remaining
  containers. Consumer status stayed clean and its HEAD matched the published
  bundle's source revision. The targeted Dune selection passed; unchanged aliases
  may use already-current results, while transport 10/store dependency 45 tests
  visibly executed in this invocation.
- Recommended next bounded slice: add validated runner-owned segment/checkpoint
  contracts around this supported API; bind runtime once; preserve the default
  Classic sequence and checks; validate copied state views and configuration,
  SDC/template/collateral/runtime/bridge closure before fresh continuation. Use
  outer segment outcome for completion and body events for progress/metric origin.
  Checkpoint publication still needs a complete manifest and retention policy;
  this experiment-local path-bound helper is not that public contract. Keep the
  full persistent journal out of slice 3. All pre-existing dirty/untracked work
   was preserved; no staging or Git history changes were made.

### Slice 3 implemented — 2026-10-13

#### Bounded interfaces and composition

- `execution_plan.resolve_stages(endpoint, resume=False)` returns a validated,
  immutable `StagePlan` (strict schema 2 JSON: `schema_version`, `endpoint`,
  `resume`). Supported endpoints are `synthesis`, `floorplan`, `placement`.
  `StagePlan.from_dict` validates the recipe; `boundary_capabilities()` declares
  exact backend endpoints and restart support. Schema 1 coarse plans/readers and
  the default Classic `run`/`execute` CLI/acceptance path retain their behavior.
- A synthesis recipe is one segment. Floorplan/placement recipes are synthesis
  followed by a fresh physical segment from the synthesis checkpoint. A resumed
  recipe is one physical segment with an explicit synthesis checkpoint. Placement
  includes floorplan; **floorplan → placement restart is not advertised**.
  Arbitrary ranges/DAGs, macros, native segments, CTS/routing are outside this
  bounded recipe contract. Physical checkpoint publication does not assert resume
  capability or signoff acceptance.
- `stages.SegmentAdapter(project=..., pdk_root=..., compatibility=..., launch=...,
  checkpoint_store=..., initial_checkpoint=None)` takes caller-owned transport
  and store inputs. `run_segment(boundary, checkpoint=None) -> SegmentResult` is
  independently useful and returns a mutable candidate with segment outcome,
  **not readiness**. `checkpoint.publish(candidate, store, compatibility=...,
  boundary=..., validate_runtime=...)` publishes independently. The shared
  `runner.execute(StagePlan, adapter)` invokes segments and owns publication
  before marking their occurrences completed. There is no second sequence engine.
- `stages.prepare(bundle=..., support_tools=..., pdk_root=..., python=...,
  workspace=..., checkpoint_store=..., initial_checkpoint=None, timeout=600)` is
  the separate host staging/binding service. All locations are explicit. New
  recipes require a fresh workspace; resumed recipes retain the original
  path-bound workspace. The store must be inside the explicit workspace mount.
  Preflight binds the exact runtime once per run. Each owned launch verifies the
  bound engine/image identity rather than resolving a mutable image tag again.
- The installed `librelane_bridge.py` is explicitly copied to the project,
  SHA256-bound, and invoked by absolute path under `-I -B`. Official Classic
  construction, `Flow.start(to=..., frm=..., with_initial_state=...)` and
  `State.loads` are used without substitutions or orchestration overrides.
  Continuation derives and checks the immediate synthesis successor
  `Checker.YosysUnmappedCells`, preserving successor checkers and pre-PNR STA.

#### Checkpoint contract and lifecycle seam

- Checkpoints contain official `state.json`, resolved configuration,
  `closure.json`, strict public `segment.json`, all non-null views (including
  nested lists/corners, with collision-free names), and a schema 1 hashed manifest.
  The manifest declares target/tools/runtime/bridge/workspace compatibility,
  each file's bytes/hash, exact external dependencies, boundary capability,
  metric availability and `acceptance: not_evaluated`.
- Closure covers recursive typed configuration paths, **all** bundle inputs,
  copied support references, and the entire selected PDK target tree (conservative,
  intentionally not a minimal cache). Host dependencies are hashed before
  publication/continuation. Runtime-only `/nix/store` paths are included and must
  be validated inside the exact image before publication; publication without
  that explicit validator is rejected. The bridge re-resolves and compares full
  config/closure before continuation, before `Flow.start`, and after tool return.
  This catches missing/changed config, SDC, templates, PDK/corner files and views.
- Publication copies into a private store directory, validates the complete
  candidate on host and in the bound runtime, removes write bits, and atomically
  renames it to a unique final directory. Errors remove partial publication and
  prevent successor execution/readiness. No overwrite or implicit newest-run
  lookup exists. Immutable publications are distinct from mutable candidate/run
  directories. Owner write-bit removal plus hash validation is not protection
  against a privileged owner, a durable transaction or a retention policy.
- `checkpoint.validate(path, compatibility=..., restart=False)` verifies manifest,
  file closure, view containment, required boundary views and external host paths.
  Runtime-only closure is rechecked by the adapter's bridge before physical work;
  a host-only validation call cannot inspect image-only files. The manifest is
  deliberately **path-bound**: original staged inputs/collateral must be retained.
  View copies remove dependency on old backend run directories, not on input roots.
- Public metrics use finite numeric values or explicit `availability: unavailable`
  with raw diagnostic value/reason. Missing keys provide no evidence; consumers
  must not substitute zero. Official state preserves upstream nonfinite sentinels;
  strict public JSON does not. Metrics are cumulative final-state evidence, not
  per-step measurement provenance, a units contract or an acceptance verdict.
- `runner.execute(..., lifecycle=callback)` calls
  `callback(event, action, occurrence_dict, artifact_or_none)` for `started` and
  `finished`. Artifact readiness is supplied only after successful publication;
  failures/interruption produce occurrence facts and no artifact. Callbacks are
  synchronous; errors propagate. `Execution.artifacts` and `as_dict()` retain
  published identities. This is an in-memory lifecycle seam, not a journal,
  replay protocol or a complete backend-step observer.

#### CLI and reproduction

Installed opt-in command (all paths explicit; prints strict execution JSON and
retains `execution-<attempt>.json` in the workspace):

```sh
hardcaml-asic-flow stages BUNDLE --support-tools TT --pdk-root PDK --python FLOW_PYTHON --workspace NEW_WORKSPACE --checkpoint-store NEW_WORKSPACE/checkpoints --endpoint floorplan
hardcaml-asic-flow stages BUNDLE --support-tools TT --pdk-root PDK --python FLOW_PYTHON --workspace RETAINED_WORKSPACE --checkpoint-store RETAINED_WORKSPACE/checkpoints --endpoint placement --checkpoint SYNTHESIS_CHECKPOINT
hardcaml-asic-flow stages BUNDLE --support-tools TT --pdk-root PDK --python FLOW_PYTHON --workspace RETAINED_WORKSPACE --checkpoint-store RETAINED_WORKSPACE/checkpoints --plan RECIPE_JSON --checkpoint SYNTHESIS_CHECKPOINT
```

The last command's recipe is
`{"schema_version":2,"endpoint":"placement","resume":true}`. Fresh composed
recipes use `resume:false`. `--timeout` bounds each launch (default 600 seconds).
From this checkout, prefix commands with
`PYTHONPATH=flow python3 -B -m hardcaml_asic_flow` instead of the installed name.
The consumer reproducible smoke is:

```sh
python3 -B experiments/stage_checkpoint_smoke.py --consumer /home/wayne/devel/jane/hardcaml_asic_example --bundle /home/wayne/devel/jane/hardcaml_asic_example/_flow_results/bundles/bbbda7ff53ea33cabf0063f7b26509bf601420ad5ab46c07e511fc8e9ee79477 --workspace /tmp/opencode/librelane-slice3-reproduction
```

#### Verification and actual backend evidence

- Production smoke passed on the sibling controlled FIFO: six synthesis steps,
  seven successor-through-floorplan steps, then an independently composed resumed
  placement recipe with 28 successor-through-detailed-placement steps. The original
  synthesis run was renamed before placement. Fresh backend processes/toolboxes
  consumed copied checkpoint views, producing real ODB/DEF. One exact runtime
  binding covered all smoke segments and publication validators.
- Raw outputs remain external at
  `/tmp/opencode/librelane-slice3-validated-publication`. Curated evidence:
  `evidence/librelane-observation/slice3-production.json`. Config and all **1509**
  declared external file hashes match across the three segments; all published
  artifacts were validated. Public floorplan/placement metrics honestly mark
  **10/6** nonfinite/nonnumeric entries unavailable. The exact image is
  `sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a`;
  production bridge SHA256 is
  `6fa8090f10b594a91a381feaf07f5ebd1b241a790f04f1508190f63047878669`.
- Earlier successful development smokes remain at
  `/tmp/opencode/librelane-slice3-floorplan` and
  `/tmp/opencode/librelane-slice3-production`; the final smoke adds runtime-side
  closure validation before atomic publication. They are not the final contract's
  primary evidence. Consumer working tree stayed clean.
- Tests cover invalid recipes, missing/corrupt metadata/views, constraint/config/
  collateral changes, incompatible target/runtime/bridge/workspace, unsupported
  restart boundaries, image-only closure validator failure, atomic publication
  failure, transport/segment failure, standalone/composed APIs and callback readiness.
  Installed-prefix tests import installed modules/resource and run the same
  negative/composition suite against the installed package.
- The `--plan` CLI also passed a separate real placement resume against the final
  synthesis checkpoint, with `resume:true`. Its exact retained execution is
  `execution-beea2d40f21d43b390dc5e27fad66a21.json` in the final workspace.
- Verification: `dune build -j 20 @test/stage-checkpoint @test/coarse-runner
  @test/execution-transport @test/runtime-contract @test/runtime-observation
  @install`; `python3 -B test/test_installed_prefix.py`; `git diff --check`.
  The final stage suite contains 22 tests; installed-prefix contains 49 tests,
  including the same 22 stage tests executed against installed modules. Coarse
  runner/CLI/store/transport/runtime-contract suites passed (11/43/45/10/8).

#### Recommended next bounded slice

Add caller-owned standalone/composed-operation lifecycle persistence and artifact
retention around these runner callbacks/results, including preflight/allocation
failure and publication failure facts. Integrate workbench with those facts and
the explicit capability table. Keep detailed body/step observation as a separate
assignment: the adapter here deliberately emits only outer segment completion.
Additional restart boundaries need their own complete contract and real tests;
floorplan/placement terminal publications do not promise CTS/routing continuation.

### Backend-stage slice 4 implemented — 2026-10-13

This slice supersedes slice 3's endpoint/restart limits. It precedes the separate
persistent-observation assignment; the existing runner callbacks are sufficient.

#### Demonstrated physical handoffs

Before expanding production capabilities, `experiments/physical_restart_probe.py`
used the exact existing bound image and official Classic / `State.loads` /
`Flow.start(with_initial_state=..., frm=..., to=...)` APIs. Fresh processes and
toolboxes successfully consumed copied views with **every producer run renamed**.
Floorplan → placement, placement → CTS, CTS → routing, and routing → final physical
checks all passed. No provisioning or source-bundle/consumer edits were needed.
The pre-expansion probe's later private snapshots used the old publisher's physical
view contract under placement metadata, never advertised as restart capabilities;
its actual boundary/endpoint evidence is in the raw summary. The current probe
script uses the new production boundary metadata directly.

Then the production shared runner passed this complete explicit sequence:

| Stage | Immediate start | Endpoint | Returned step objects | Seconds including publication |
| --- | --- | --- | ---: | ---: |
| synthesis | Classic start | `Yosys.Synthesis` | 6 | 4.642430 |
| floorplan | `Checker.YosysUnmappedCells` | `OpenROAD.Floorplan` | 7 | 4.354740 |
| placement | `OpenROAD.DumpRCValues` | `OpenROAD.DetailedPlacement` | 21 | 10.807439 |
| CTS | `OpenROAD.CTS` | `OpenROAD.CTS` | 1 | 10.335365 |
| routing | `OpenROAD.STAMidPNR-1` | `OpenROAD.DetailedRouting` | 9 | 59.473922 |
| signoff / physical checks | `Odb.RemoveRoutingObstructions` | `Misc.ReportManufacturability` | 28 | 1460.502652 |

The sequence took 1550.116548 occurrence seconds (about 26 minutes). The initial
API proof took 1543.376 launch seconds. Each physical run used a 7200-second timeout.
CTS's post-CTS STA/resizer work is deliberately in the next segment. Likewise,
routing's antenna/DRC/disconnected-pin checkers and fill/extraction work remain at
the start of the final segment. These names group work; they never justify skipping
Classic successors or checks. A disabled endpoint cannot satisfy completion.

The final segment includes RCX, multi-corner STA, IR drop, Magic/KLayout stream-out,
Magic DRC/overlap, Netgen LVS, setup/hold/slew/capacitance checkers and manufacturability.
Final cumulative state reports zero route DRC, Magic DRC, LVS errors, setup/hold
violations, slew/cap violations and critical disconnected pins. It also reports
six disconnected pins and one max-fanout violation; those are retained, not erased
or interpreted as an acceptance verdict. Consumer gates disable KLayout DRC, XOR,
EQY, heuristic diode insertion and post-GRT design/timing repair. No gate was
changed. Successful physical execution is **not** external postcheck or acceptance.

#### Interfaces and strict composition

- `execution_plan.BOUNDARIES`, `STAGE_ORDER`, `SUCCESSORS`, `RESTART_TARGETS` and
  `boundary_capabilities()` describe the tested exact-image endpoints and immediate
  successors. Only synthesis → floorplan/placement, floorplan → placement,
  placement → CTS, CTS → routing and routing → signoff are supported standalone
  transitions. The earlier direct synthesis → placement segment remains available.
- `resolve_stages(endpoint, resume=False, initial_boundary=None)` expands an
  endpoint into a contiguous sequence. Legacy schema-2 endpoint/resume JSON is
  preserved; resumed schema-2 recipes assume synthesis. Fresh placement now means
  synthesis → floorplan → placement, and a resumed placement recipe from synthesis
  means floorplan → placement. The normal coarse/default Classic path is unchanged.
- `resolve_sequence(stages, initial_boundary=None)` and `StagePlan.from_dict`
  validate schema-3 composition. Example:
  `{"schema_version":3,"stages":["placement","cts","routing","signoff"],"initial_boundary":"floorplan"}`.
  Fresh recipes begin at synthesis; resumes begin immediately after the declared
  source. Empty, repeated, reordered, skipped or extra-field recipes are rejected.
  `StagePlan.sequence` / `.source_boundary` expose the resolved contracts; each
  action requires its actual predecessor and names its predecessor checkpoint.
- Existing `SegmentAdapter.run_segment(boundary, checkpoint=...)`, `publish`,
  `stages.prepare`, and `runner.execute` signatures remain available. Validation
  rejects unsupported transitions and a plan/checkpoint source mismatch before
  launch. The bridge independently checks the checkpoint source and the actual
  Classic successor before `Flow.start`; no orchestration engine is copied.
- CLI `stages --endpoint` now supports `cts`, `routing`, `signoff`; with a checkpoint
  it infers the declared source boundary, then validates it. `--plan` reads strict
  schema 2 or 3. A separate real schema-3 CLI placement → CTS resume passed in
  10.308375 seconds. Its execution record is listed in the concise evidence.

#### Checkpoint eligibility and provenance

New publications use **checkpoint schema 2**, adding `restart_targets`,
`tested_image_id` and `closure_scope: path_bound`. The boolean `restart_supported`
only summarizes the target list; it does not promise arbitrary resume.
`checkpoint.validate(..., restart_to=boundary)` checks the exact transition.
Signoff is terminal. Schema-1 readers retain their original synthesis-only restart
semantics; physical schema-1 artifacts are not upgraded. All compatibility hashes,
including the transported bridge hash, still have to match: existing artifacts
cannot be silently migrated across bridge revisions.

The opt-in staging service and new manifest validation require the exact tested
image `sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a`.
The production bridge hash is
`b24a5f46cdb1df0d9e742823b5e45570b273bccc73fe244c657d51b19bb442b8`.
All six checkpoints share identical resolved config and **1509** declared external
dependency hashes. They retain the path-bound config/input/support/PDK/image closure;
publication still validates image-only files in the runtime before atomic promotion.
All producer run directories were absent before their successors launched.

`segment.json` now records configured Classic gates alongside returned step IDs.
These are configuration facts and successful outer step objects, not exact skip
reasons or full-step/body events. Metrics remain cumulative final state, with no
per-step origin/units claim. Unavailable values remain explicit (0/10/6/6/6/6 per
stage). The final checkpoint copies 21 view leaves, including stream-out/extraction
and timing collateral, without depending on original backend run paths.

#### Evidence, verification and diagnostics

Raw physical output stays external:
`/tmp/opencode/librelane-slice4-api-proof` and
`/tmp/opencode/librelane-slice4-production`. Retain both workspaces and the consumer
tool/PDK roots for re-audit. Compact evidence and exact commands are in
`evidence/librelane-observation/slice4-physical.json`.

```sh
python3 -B experiments/physical_stage_smoke.py --consumer /home/wayne/devel/jane/hardcaml_asic_example --bundle /home/wayne/devel/jane/hardcaml_asic_example/_flow_results/bundles/bbbda7ff53ea33cabf0063f7b26509bf601420ad5ab46c07e511fc8e9ee79477 --workspace /tmp/opencode/librelane-slice4-production
python3 -B experiments/verify_physical_stages.py /tmp/opencode/librelane-slice4-production
dune build -j 20 @test/stage-checkpoint @test/coarse-runner @test/execution-transport @test/runtime-contract @test/runtime-observation @install
python3 -B test/test_installed_prefix.py
git diff --check
```

Use a **new** workspace for reproduction; the exact completed paths above are for
audit, not overwrite. The verifier rechecks manifests, full host closure, copied
views, identities, config consistency, source disappearance, ordered endpoints and
selected final cumulative metrics using the current production contracts.

Focused stage tests pass **28** cases, including contiguous recipes, exact-image
eligibility, source mismatch, forbidden physical skips, full six-stage composition,
physical resume, terminal signoff and schema-1 non-upgrade. Installed-prefix tests
pass **49** cases, including those same 28 tests against installed modules and the
bridge resource. The initial packaging run failed only on its stale `Ran 22 tests`
assertion; the installed stage suite itself had passed. Corrected assertion and
final rerun passed in 9.670 seconds. Targeted Dune verification passed; unchanged
runtime-observation results may be cached. Coarse runner/CLI/store/transport/runtime
contract suites passed (11/43/45/10/8). No physical environment blocker occurred.
Existing installation stanzas already include every changed production module.

#### Next agent

Own observation/lifecycle persistence around existing runner callbacks, including
validation/preflight failures before occurrences exist and publication failures.
Do not treat configured gates or returned step IDs as a durable occurrence journal.
Keep retention of path-bound roots explicit. Acceptance integration still needs an
explicit segmented-results/postcheck ownership contract; a signoff checkpoint alone
does not satisfy the historical full-flow postcheck/acceptance API. Native, macros,
relocation, other images and additional direct ranges need separate evidence.

All original dirty/untracked work was retained. Consumer status remained clean;
no Git staging/history operations, authorship annotations, toolchain rewrites,
subagents or additional Workbench/journal events were introduced.

### Persistent stage observation slice 5 — 2026-10-13

- Added installed `flow_observation` contract `hardcaml-asic.stage-observation`,
  schema 1: `Writer(root, workspace=..., checkpoint_store=..., request=...)`,
  `Writer.run(plan_factory, prepare, finalize=None)`, `describe()`,
  `inspect(directory)`, `read_updates(directory, stream_id=..., after=0)`.
  Opt-in CLI: `stages ... --observation-store ROOT`; read-only public commands
  `observation describe`, `observation inspect ATTEMPT`, and
  `observation read-updates ATTEMPT --stream-id ID --after CURSOR`. The CLI guide
  specifies every envelope/data/state field, capability and error response;
  `describe().schemas` installs the same closed field descriptions for discovery.
- Allocation uses `result_store.allocate`; journal records use its atomic JSON
  replacement primitive. A flushed JSON-line allocation receipt precedes recipe
  validation and long preflight. The journal references explicit workspace,
  checkpoint store, diagnostic preflight record and separate runtime/transport
  record. Observed preparation reuses `durable_preflight`, preserving pending,
  failed and interrupted reports. Invalid recipes/checkpoints, preparation and
  adapter validation failures remain final failed attempts, with planned stages
  unreached rather than fabricated completed/skipped stages.
- Runner lifecycle now emits `published` after validated checkpoint promotion and
  before `finished`: publication retains a running occurrence. The writer derives
  stage events from these shared callbacks, not Step.run body hooks or configured
  gates. Stable IDs are `attempt_id/implementation.boundary`. Final outer outcome
  follows optional execution-record publication. Physical completion, checkpoint
  refs, external postcheck and acceptance remain separate: segmented signoff
  returns `acceptance: not_evaluated`, not fully accepted.
- A nonblocking advisory workspace flock rejects observed competing writers with
  `BUSY`, including different observation roots. Per-attempt flock presence avoids
  a later attempt reviving an old stream. Released writers cannot append. Readers
  replay an immutable-by-convention atomic record prefix with sequence/hash-chain
  and closed transition validation. Temporary hidden tails are ignored; malformed
  promoted records, gaps, duplicate keys, nonfinite values and unearned completion
  fail closed. Wrong stream or out-of-prefix cursor returns `RESET_REQUIRED`.
  Reader calls never write/acknowledge/repair or terminate execution.
- Real local subprocess tests exercise SIGTERM in durable long preparation and
  runner execution, SIGTERM after checkpoint publication, and SIGKILL between
  publication and stage completion. Separate reader processes reconnect after
  producer exit. SIGKILL retains the publication and running fact with null outer
  outcome and `writer_lost_or_unknown`; no synthetic interruption/success is added.
  Tests also cover same-workspace conflicts, cursor suffixes, corruption/gaps,
  atomic write failure, final aggregate-write failure, six-stage physical-completion
  semantics and read-only queries. These are local fixture evidence, not graceful
  EDA interruption evidence.
- Actual `hardcaml_asic_example` production synthesis → floorplan passed in about
  nine occurrence seconds, including runtime validation/publication. Retained raw
  workspace: `/tmp/opencode/librelane-slice5-observed`; observation attempt:
  `/tmp/opencode/librelane-slice5-observations/20261013T051201323002Z_31ef91df`.
  Ten records end with completed outer outcome; an independent post-exit reader
  verified hash chain/order, suffix from cursor 5, ready preflight and both complete
  host checkpoint closures. Concise exact-command evidence:
  `evidence/librelane-observation/slice5-observed.json`. The bridge/backend sequence
  is unchanged; slice 4's complete six-stage physical evidence remains applicable,
  and the 26-minute run was not repeated.
- Verification: `dune build -j 20 @test/flow-observation @test/stage-checkpoint
  @test/coarse-runner @test/result-store @test/flow-cli @test/provider-observation
  @test/execution-transport @test/runtime-contract @test/runtime-observation @install`;
  `python3 -B test/test_installed_prefix.py`; `git diff --check`. Observation 16,
  stage 28, coarse runner 11, CLI 43, result-store 45, transport 10, runtime-contract
  8 and runtime-observation 18 tests pass; unchanged fixture aliases may be cached.
  Installed-prefix 50 tests pass, including the observation subprocess suite using
  installed modules and installed CLI describe/inspect/update/failure commands.
  An initial Dune invocation's tests passed but sandbox cleanup failed because a
  SIGKILL fixture left read-only checkpoint files outside its parent-owned temporary
  directory. The test now contains that fixture under parent ownership and cleans
  permissions; the subsequent Dune invocation passed.

#### Remaining contract and next agent

This is a bounded per-stage-attempt path-bound journal, not the provisional
fixture's store-wide catalog/fencing/idempotency/retention/result-slot protocol.
Atomic visibility gives process-restart readability, not fsync/power-loss guarantees.
Advisory locks only coordinate observed writers on the local POSIX filesystem;
Classic/unobserved/external writers do not participate. No writer takeover,
execution recovery, automatic retention, hostile-owner protection, blocking watch,
cross-machine relocation or full backend-step lifecycle is delivered. Inspection
reports historical publications; use checkpoint validation for current readiness.
SIGKILL or failed storage can leave unresolved running facts and no final outcome.
Allocation/argument errors before a record can be written have no invented identity.

Next agent: define segmented final-results/external-postcheck operation ownership,
then integrate the existing acceptance service with truthful physical/postcheck/
acceptance separation and persistent outer outcomes. Workbench can now consume
inspect/cursor updates without parsing human text. Store-wide catalog/idempotency
and detailed backend lifecycle need separate bounded contracts. Retain explicit
path-bound roots, reuse the runner/transport, and preserve Classic compatibility.
All pre-existing dirty/untracked work was preserved; no consumer frontend edits,
subagents, Git staging/history operations or attribution were introduced.

### Segmented final-results / external acceptance slice 6 — 2026-10-13

- Added installed `finalization.finalize(execution=..., store=..., accept=False,
  support_tools=..., precheck_python=..., testbench=..., testbench_top=...,
  replay_trace=None, allocated=None)` and read-only `finalization.inspect(directory)`.
  CLI: `finalize EXECUTION --operation-store ROOT [--accept ...]` and
  `finalization-inspect ATTEMPT`. This bounded adapter selects one completed fresh
  six-stage execution and all six schema-2 checkpoint identities; arbitrary
  resumed execution stitching is a future contract. Signoff alone does not
  establish synthesis evidence or a full selected composition.
- New separate snapshot contract `hardcaml-asic.segment-finalization`, schema 1,
  allocates an independent operation attempt before prerequisites. Atomic
  `operation.json` records validation/collection/external-postcheck/acceptance
  phases, running/completed/failed/interrupted outcome, exact binding, original
  execution path/hash/identity, six selected checkpoint refs, mapped evidence
  inventory and final results path/hash. CLI flushes allocation before work.
  Inspector rejects malformed lifecycle/unearned acceptance, never repairs state.
  Terminal stage observation streams, checkpoints and old run records are not
  reopened or altered. SIGKILL remains an unresolved running snapshot; this is
  deliberately not a second journal, liveness protocol or crash-recovery claim.
- Reuses checkpoint host validation and the **retained SHA256-bound bridge** for
  image-only closure validation in the exact historical image/engine. All selected
  resolved configs and closures must match. Runtime validation uses Classic
  construction without `Flow.start`, so it reuses the 26-minute implementation.
- A canonical in-memory evidence context allows small optional-input refactors to
  `phase4.collect`, `phase4.check` and `report.report`. Original defaults and Classic
  CLI behavior remain unchanged. Official synthesis-state area/count/check metrics
  retain synthesis origin; cumulative signoff state supplies physical metrics.
  The CSV is an explicitly declared derivation, with actual per-corner timing
  preferred only on equal-value anonymous aggregate ties in the mapped path;
  worst-slack selection still includes all evidence. GDS/netlist/LEF,
  TT metadata, constraints and manifest are copied with hashes. Every public metric
  or physical check adds `origin_boundary`, and results carry selected publication
  provenance. No synthetic Yosys report or legacy `run.json` is produced.
- `--accept` invokes the existing TT precheck, exact-bound-container Icarus replay
  and reporter acceptance policy. An optional retained/hash-recorded reference
  trace supports the consumer's existing `acceptance/replay.v`; no consumer or
  OCaml source changes are involved. Later-check collateral gets its own complete
  file inventory; selected execution, publications, copied inputs and collateral
  are rechecked after checks. New mapped postcheck records include operation
  evidence origin. Failed external checks/acceptance remain real failures with
  diagnostic records; results-only completion remains `not_evaluated` acceptance.
- Retention is caller-owned: keep the operation tree plus path-bound checkpoint,
  workspace/input/support/PDK roots and exact image. Mapped evidence is not a
  complete relocated restart package or a classic archive input. The existing
  archiver's genuine run/bundle contract is retained; no counterfeit archive
  eligibility record is emitted. The flow guide describes every receipt field,
  command, readiness distinction, retention limit and scope restriction.
- Verification passed: `dune build -j 20 @test/finalization @test/stage-checkpoint
  @test/flow-observation @test/coarse-runner @test/flow-cli @test/execution-transport
  @test/result-store @install`; `python3 -B test/test_installed_prefix.py`;
  direct phase4/report/archive/packaging suites; `git diff --check`.
  Finalization **15**, stage **28**, observation **16**, runner **11**, CLI **43**,
  store **45**, and runtime-observation dependency **18** cases passed. Transport's
  unchanged alias may be cached. Installed-prefix **51** cases pass, including
  the same finalization API/CLI success/failure/policy suite against installed
  modules, real installed allocation/inspection and read-only receipt behavior.
  Phase4/report/archive/packaging pass **26/15/20/17** cases. Negative coverage
  includes malformed/missing selection, duplicate JSON keys, corrupt views,
  mismatched identity, runtime failure, interruption, missing later-check inputs,
  failed precheck/compile, changed selection during checks, missing/nonfinite/
  unconstrained/negative timing, DRC/LVS/antenna violations and unearned acceptance.

#### Real consumer evidence

`experiments/finalization_smoke.py` uses the retained production execution,
consumer testbench and 11,429-edge reference trace, host TT precheck environment,
and exact implementation image. All operation attempts remain under
`/tmp/opencode/librelane-slice6-finalizations`. Curated evidence and the actual
terminal verdict are recorded in `evidence/librelane-observation/slice6-finalization.json`.
The initial development attempt passed gate replay but correctly failed TT
precheck for missing copied `info.yaml`; that led to complete metadata/LEF mapping.
A corrected attempt reached the real DRC deck but was interrupted by the tool's
600-second timeout, retaining interruption facts. A separate later attempt ran
the full checks independently; neither earlier failure was edited into success.

The later operation **completed and fully passed** in 675.606435 seconds:
`20261013T053638859111Z_5059094a`. All nine applicable TT checks, including the
full SG13CMOS5L KLayout DRC deck and pin/boundary/layer checks, passed. Exact-image
Icarus 13.0 replay passed all 11,429 consumer oracle rows. The shared reporter
returned 0 with worst setup **11.67551954830797 ns** at `nom_slow_1p08V_125C` and
hold **0.12502899069955042 ns** at `nom_fast_1p32V_m40C`; DRC/LVS/antenna passed.
The known six disconnected pins and one max-fanout violation remain in copied
raw cumulative state/CSV. They are outside the existing acceptance gates; no
new incompatible acceptance policy was added to reinterpret them.

`experiments/verify_finalization.py` revalidated all selected publications, original
execution hash, mapped evidence/collateral hashes, exact postcheck binding and
input hashes. It reran the **current** collector and reporter read-only and proved
the saved metric/check evidence and full acceptance verdict identical. The live
attempt had loaded code before later optional receipt metadata and equal-value-only
timing tie refinement; its actual receipt is preserved, with that provenance
noted in the curated evidence. Current-production results-only validation also
passed at `20261013T054935417567Z_b0103346`. No implementation was repeated and no
physical/external environment blocker remains.

#### Next owner

The next agent owns the OCaml recipe facade. This slice changes no OCaml. Keep
the canonical evidence adapter and existing acceptance policy as the shared seam.
Resumed multi-attempt composition, standalone terminal-checkpoint selection,
native/macro/other-image eligibility, operation archive packaging, store-wide
catalog/idempotency, fine backend-step observation and durable takeover remain
separate contracts. All original dirty/untracked work and consumer source were
preserved; no staging/commits/push, attribution or subagents were used.

### OCaml-facing stage/recipe slice 7 — 2026-10-13

#### Delivered API and boundary

- Added public `Flow.Stage` / `Flow.Recipe` aliases of signature-constrained
  `Flow_stage` / `Flow_recipe`. Stage constructors are `Synthesis`, `Floorplan`,
  `Placement`, `Cts`, `Routing`, `Signoff`; string parsing accepts the provider's
  exact lowercase names. Typed static capabilities expose endpoint, immediate
  successor, standalone restart targets, tested image ID, `Path_bound` closure
  and `Not_evaluated` acceptance. They match the implemented Python table,
  including standalone synthesis -> placement and terminal signoff.
- Abstract recipes provide `create ?initial_boundary stages`, endpoint expansion
  `through ?initial_boundary endpoint`, and `compose first second`. Construction
  rejects empty/repeated/reordered/skipped sequences and terminal/backwards
  resumes. Composition requires the second source to equal the first endpoint,
  preserves the first source and revalidates the combined declaration. Fresh
  sequences start at synthesis; resumes start immediately after their source.
  Recipes never use the standalone-only synthesis -> placement skip.
- Accessors expose stages/source/endpoint and typed external input plus ordered
  `declarations` of stage/input/output-checkpoint boundaries. `to_yojson` and
  `to_string` emit exactly schema-3 `schema_version`, `stages`, `initial_boundary`.
  No arbitrary backend JSON, new project setting, phantom checkpoint readiness,
  OCaml process/lifecycle hook or runtime dependency was introduced. Additional
  per-stage settings remain a future extension requiring backend support.
- `Project.create`, existing flow operation/settings, bundle schemas/identity,
  elaboration/resources and default run/execute retain their implementation.
  Project signature documentation points to the separate recipe/provider seam;
  `lib/dune` needs no change because the current library automatically includes
  the new modules and already depends on Core/Yojson.
- Added read-only installed `checkpoint-inspect CHECKPOINT [--compatibility
  EXPECTED_JSON] [--restart-to STAGE]`. It reuses `checkpoint.validate` for manifest,
  view/file identity, host external closure and exact transition checking. Success
  reports `validation: host_only`, `runtime_closure_validated: false`, compatibility
  source (`recorded`/`expected`) and manifest. Caught errors emit JSON and exit 2.
  This command does not launch a runtime validator or claim current execution
  compatibility when expected compatibility is omitted. Existing observation
  describe/inspect/read-updates and finalization-inspect remain the reader seam.
- Added module signatures and `docs/guides/ocaml-stage-recipes.md` with runnable
  typed construction, schema-3 examples, composition, specimen command, execution,
  resume, inspection, retention and installed contract verification instructions;
  linked it from the existing flow guide.

#### Consumer and verification evidence

The only sibling source additions are
`hardcaml_asic_example/bin/stage_recipe/dune` and
`hardcaml_asic_example/bin/stage_recipe/stage_recipe.ml`. This pure companion CLI
renders endpoint/source recipes and rejects invalid input with exit 2. Existing
specimen project/frontend/source inventory and commands are untouched. Both this
executable and the existing `bin/project.exe` compiled separately against the
temporary installed OCaml library; existing `project describe --json` returned the
controlled FIFO declaration, including the original source inventory and flow.

Commands executed successfully (provider cwd unless noted):

```sh
dune build -j 20 lib/hardcaml_asic.cma
dune build -j 20 @test/ocaml-stage-recipes @test/stage-checkpoint @test/flow-cli @install
dune install -j 20 --prefix /tmp/opencode/stage-facade-prefix
# sibling cwd; fresh external build directory proves independent installed linkage:
OCAMLPATH="/tmp/opencode/stage-facade-prefix/lib${OCAMLPATH:+:$OCAMLPATH}" dune build -j 20 --build-dir /tmp/opencode/stage-facade-consumer-build bin/stage_recipe/stage_recipe.exe bin/project.exe
python3 -B test/check_stage_recipes.py --emitter _build/default/test/stage_recipe_contract.exe --provider-prefix /tmp/opencode/stage-facade-prefix --consumer-executable /tmp/opencode/stage-facade-consumer-build/default/bin/stage_recipe/stage_recipe.exe
/tmp/opencode/stage-facade-consumer-build/default/bin/project.exe describe --json
python3 -B test/test_installed_prefix.py
git diff --check
```

- New `stage_recipe_contract.ml` emits actual OCaml recipes, declaration facts,
  rendered JSON and capabilities. `check_stage_recipes.py` decodes with
  `StagePlan.from_dict`, checks complete contract equality and rejects drift. The
  Dune alias `@test/ocaml-stage-recipes` covers **36 accepted / 1819 rejected**
  explicit/endpoint cases (all candidate lists of lengths 0–3 across seven source
  choices, plus all 42 endpoint/source pairs), long endpoint expansions and 16
  composed recipes. It compares every capability and action input/output.
- The explicit installed-prefix invocation confirms imports originate in the
  installed provider, validates OCaml recipes there, checks standalone-only skip
  and extra-field rejection, and tests installed checkpoint-inspect success,
  expected-compatibility mismatch, forbidden transition and changed host closure.
  Successful and failed reader calls preserve publication bytes. All **42**
  independently linked specimen endpoint/source combinations agree with Python.
- Existing stage tests **28**, CLI tests **43**, and installed-prefix packaging
  suite **51** pass. The latter includes installed finalization/observation/stage
  suites and legacy run/execute checks. No nested build/test/exec was invoked
  without `-j 20`. No physical EDA or external acceptance was repeated: the runtime
  contract is unchanged and prior physical evidence remains the backend basis.

#### Limitations and final independent integration review

Execution stays application-owned at the installed CLI boundary. There is no
OCaml runtime/process API or checkpoint decoder; use provider reader commands
and validate runtime closure during execution. Checkpoint schema-1 eligibility is
not upgraded by static stage capabilities. Exact tested Docker image and retained
path-bound workspace/input/support/PDK/bridge closure remain required. Native,
macros, relocation, other images, DAGs, execution recovery and fine step events
remain outside this facade. A resumed recipe is useful for execution but does not
make resumed multi-attempt evidence eligible for current finalization. Signoff
alone still implies neither external postcheck nor acceptance.

Final review should independently check the public naming/signatures and schema-3
contract test against the assembled provider; review the explicit host-only reader
wording and expected-compatibility behavior; reconcile the flow guide's older
slice-specific status wording with the complete refactor record; and validate
installation/adoption through the consumer's normal pinned activation workflow.
The temporary prefix proves packaging/linkage, not adoption of a committed pin.
Retain the new contract alias and installed-prefix invocation as drift checks when
backend tables or schemas change. All pre-existing dirty/untracked work was
preserved; the sole agent made no staging/history changes or attribution.

### Final independent integration review — 2026-10-13

The documentation handoff in this review is preserved as history; the final
documentation slice below completes its reconciliation.

The assembled implementation passes the bounded integration review after the fixes
below. Documentation reconciliation remains with the parent owner. This review used
one sequential general agent, with no delegation. The inherited dirty/untracked
provider files and sibling `bin/stage_recipe/` addition were preserved.

#### Defects reproduced and fixed

- Public checkpoint JSON used Python's last-key-wins decoder. A manifest with an
  inserted contradictory `boundary` key still validated against its unchanged
  canonical identity. Public exponent overflow (`1e999`) also bypassed the
  `parse_constant` rejection. `checkpoint.read` now rejects duplicate keys at every
  object depth and nonfinite decoded public values. Official opaque `state.json`
  continues to support backend nonfinite sentinels through its separate decoder.
- `stages --plan` likewise silently accepted duplicate recipe keys and could enter
  preparation/preflight for an ambiguous recipe. It now uses the existing strict
  observation JSON decoder before `StagePlan.from_dict`. A regression asserts that
  preparation is never called for duplicate `stages` declarations.
- `@test/finalization` existed but was absent from `runtest`. The alias is now a
  dependency of `runtest`, so comprehensive testing includes the delivered evidence
  mapping, external-check and unchanged acceptance-policy suite.
- Remaining unbounded Dune commands in provider test wrappers and the example
  driver were changed to `-j 20`: Project/resolved-flow API consumers, package
  consumer smoke, RTL simulation, `scripts/flow.sh`, and the installed-prefix
  wrapper's install command. The installed stage-suite count assertion is now 30.

The two new regressions were independently run with the old last-key-wins parsing
behavior substituted in memory, without reverting or editing delivered files.
Both failed as intended: checkpoint validation raised no error, and CLI preparation
was called once. The reproduction command itself exited 0 after asserting exactly
those two failures. Their fixed versions pass in both checkout and installed suites.
No ordinary verification suite failed. Two initial Docker format inspection
commands had shell quoting errors; corrected `docker ps -a` succeeded and was empty.

#### Reviewed contracts and tested scope

- Coarse schema-1 plans retain the shared runner's default sequence, best-effort
  collection and primary-failure preservation. Stage schema-2 endpoint/resume
  expansion and schema-3 contiguous source/sequence declarations remain separate
  validated contracts on that same runner. The OCaml facade and Python actions,
  capabilities, immediate successors and checkpoint input/output declarations agree.
- Exact-image eligibility, retained bridge/configuration/host closure, image-only
  validation before publication, copied view containment, no-clobber promotion and
  read-only publication are covered by the stage/transport/installed regressions.
  This review changed no bridge, endpoint, EDA sequence or acceptance policy.
- Observation tests cover publication-before-finish ordering, prefix/hash/cursor
  validation, promoted corruption, failure facts, storage faults, competing writers,
  real local SIGTERM and SIGKILL, reconnect and read-only queries. A separate installed
  reader rechecked the retained real ten-record synthesis/floorplan stream and its
  five-event cursor-5 suffix, preserving every attempt-directory file's bytes.
- Finalization mapping and policy negatives run in `runtest` and the installed
  suite. The retained real accepted operation was independently audited against
  the current collector/reporter: execution/publication/mapped/collateral hashes,
  exact postcheck binding, copied oracle inputs and saved metric/check values match.
  Setup/hold remain 11.67551954830797 ns / 0.12502899069955042 ns at their recorded
  corners. Six disconnected pins and one fanout violation remain in raw evidence;
  they are outside existing acceptance gates, not newly hidden or reinterpreted.

#### Exact successful verification

Commands below ran from the provider root unless a sibling cwd is stated. All
invoked Dune build/test/exec commands, including nested API consumers, used `-j 20`.

```sh
dune runtest -j 20 --force
dune build -j 20 @install test/stage_recipe_contract.exe
dune install -j 20 --prefix /tmp/opencode/final-integration-prefix hardcaml_asic
# sibling cwd; independent installed OCaml provider, fresh external build directory:
OCAMLPATH="/tmp/opencode/final-integration-prefix/lib${OCAMLPATH:+:$OCAMLPATH}" dune build -j 20 --build-dir /tmp/opencode/final-integration-consumer-build bin/stage_recipe/stage_recipe.exe bin/project.exe
python3 -B test/check_stage_recipes.py --emitter _build/default/test/stage_recipe_contract.exe --provider-prefix /tmp/opencode/final-integration-prefix --consumer-executable /tmp/opencode/final-integration-consumer-build/default/bin/stage_recipe/stage_recipe.exe
# sibling cwd:
/tmp/opencode/final-integration-consumer-build/default/bin/project.exe describe --json
python3 -B test/test_installed_prefix.py
python3 -B test/check_resolved_flow_api.py
python3 -B test/check_project_api.py
python3 -B experiments/verify_physical_stages.py /tmp/opencode/librelane-slice4-production
python3 -B experiments/verify_physical_stages.py /tmp/opencode/librelane-slice4-production --evidence evidence/librelane-observation/slice4-physical.json
python3 -B experiments/verify_finalization.py /tmp/opencode/librelane-slice6-finalizations/20261013T053638859111Z_5059094a
bash -n scripts/flow.sh test/package_consumer_smoke.sh test/run_rtl_sim.sh
git diff --check
docker ps -a
```

The forced full run passed OCaml inline/bundle checks plus Python suites:
stage 30, finalization 15, observation 16, runner 11, CLI 43, store 45,
transport 10, runtime contract 8, runtime observation 18, phase4 26, report 15,
archive 20, packaging 17, managed Python 48, toolchain 25, provider fixture 50.
The OCaml recipe checker passed 36 accepted / 1819 rejected cases, capabilities,
handoffs and composition. Installed-prefix passed 51 top-level cases including
the installed stage/finalization/observation suites. Independent sibling linkage
passed all 42 endpoint/source combinations and installed host-only checkpoint
inspection success/compatibility/transition/changed-closure checks. Project and
resolved-flow external API tests passed whole-bundle equivalence, publication
race/no-clobber behavior and private-constructor rejection. Project tests use
disposable fixture-local Git history as permitted by the execution constraints;
neither provider nor sibling Git index/history was changed.

The separate retained-stream audit used `python3 -I -B -c` with the sole package
path `/tmp/opencode/final-integration-prefix/lib/hardcaml_asic/flow`, invoking
`inspect` and `read_updates(after=5)` on
`/tmp/opencode/librelane-slice5-observations/20261013T051201323002Z_31ef91df`.
It asserted final/completed outcome, cursor 10, suffix length 5 and byte-identical
directory contents before/after. It passed. Physical compact evidence matches all
six retained publications, ordered endpoints/successors and disappeared producer
run paths. The accepted operation's current-code read-only audit also passed.

#### Scope limits and documentation handoff

No costly physical implementation or external TT/DRC/replay run was repeated:
strict public decoding and test wiring do not change their runtime inputs or
backend/acceptance semantics. Existing full physical and postcheck evidence was
re-audited, not represented as a fresh EDA run. Runtime-only closure's current
contents were not reprobed in a newly launched container by this review. Local
signal tests do not add graceful real-EDA cancellation evidence. Other images,
native/macro stages, relocation, general DAGs, resumed-attempt finalization,
store-wide catalog/idempotency, takeover/recovery and fine backend-step events
remain outside the delivered bounded contracts. The independent prefix proves
packaging and consumer API linkage; it does not activate or adopt a new committed
consumer dependency pin. No sibling source/configuration changes were made here.

Reconcile these stale current-tense documentation claims in the next small
documentation-only assignment, retaining slice entries as historical evidence:

- This record's opening `implementation in progress` and initial foundations
  describe the pre-refactor baseline; the later implementation and review now exist.
- `docs/architecture.md` section 8 still says official cases have not run / the
  probe remains blocked, and describes early correlation/incremental publication
  and read interfaces as undelivered. Distinguish the delivered bounded stage
  journal/checkpoint/finalization APIs from still-undelivered store-wide and fine
  backend-step protocols; do not upgrade the historical synthetic fixture.
- `docs/guides/flow.md` retains its September status/header and a blanket
  machine-callers-must-use-`--json` statement. The additive stage/observation/
  checkpoint/finalization commands have their documented strict JSON interfaces.
  Its older no-live-journal wording needs explicit Classic versus opt-in scope;
  sample Dune commands should use the required job bound for reproduction here.
- Earlier slice-3 endpoint/restart limits and slice-5 no-finalization statements
  are historical and superseded by slices 4/6; current summaries should link the
  actual contracts without implying all checkpoints or resumes are finalizable.
- The consumer remains a candidate additive recipe command validated via an
  isolated install, not a newly activated committed provider pin.

Review-owned edits are limited to `flow/hardcaml_asic_flow/checkpoint.py`,
`flow/hardcaml_asic_flow/cli.py`, `test/test_stages.py`, `test/dune`,
`test/test_installed_prefix.py`, `test/check_project_api.py`,
`test/check_resolved_flow_api.py`, `test/package_consumer_smoke.sh`,
`test/run_rtl_sim.sh`, `scripts/flow.sh`, and this implementation record.
All other inherited changes were preserved. The new install and consumer build
are isolated under `/tmp/opencode/final-integration-{prefix,consumer-build}`;
retained prior evidence was only read. No owned containers remain. No repository
staging, commits, amendments, pushes or attribution were introduced.

## End implementation summary — 2026-10-13

Slices 1–7 and the independent review deliver the bounded interfaces described at
the opening. Schema-1 coarse plans and historical readers retain compatibility;
schema-2 stage recipes remain readable and schema-3 OCaml/Python declarations agree.
Six physical checkpoints use exact-image schema-2 restart capabilities, with
publication preceding readiness. Opt-in stage observation is a per-attempt journal;
finalization is a separate operation snapshot selecting one fresh six-stage run.
Neither represents the complete provisional store-wide model or Workbench adoption.

Evidence retained in the repository, independently of raw `/tmp` workspaces:

- [Historical blocked probe](../../evidence/librelane-observation/blocked-local.json).
- [Slice 2 official/runtime handoff proof](../../evidence/librelane-observation/slice2-real.json)
  and [slice 3 production publication](../../evidence/librelane-observation/slice3-production.json).
- [Slice 4 full physical execution](../../evidence/librelane-observation/slice4-physical.json):
  all six stages, fresh successors with producer runs absent, copied views and matching
  config/1509 external dependency hashes; about 26 minutes.
- [Slice 5 actual observation](../../evidence/librelane-observation/slice5-observed.json):
  ten-record synthesis/floorplan stream with independent post-exit cursor reading.
- [Slice 6 external acceptance](../../evidence/librelane-observation/slice6-finalization.json):
  nine TT checks, 11,429-edge replay, passing existing timing/DRC/LVS/antenna policy;
  earlier failed/interrupted attempts preserved and raw fanout/disconnected-pin facts retained.

The [exact full review checks](#exact-successful-verification) passed forced
`dune runtest -j 20 --force`, build/install, OCaml/Python contract comparison,
51 installed-prefix cases, all 42 independently linked consumer endpoint/source
combinations and external Project/resolved-flow API checks. Retained physical,
observation and accepted-operation evidence was re-audited read-only, not rerun as
new EDA. Isolated prefix linkage does not advance the consumer's committed pin.

The final documentation-only reconciliation updated architecture, index, flow,
recipe guide and phase status, adding the linked quickstart. Bootstrap's direct
stale probe claim was also reconciled. Checks passed: eight docs / 219 local links
with no invalid anchors (two unavailable historical scaf links retained), three
fenced recipes decoded by `StagePlan.from_dict`, 24 installed CLI examples parsed
without execution, source/read-only help checks and operating-guide Dune job-bound
checks. `git diff --check` passed; no production code was changed.
The remaining scope in the opening is explicit and has no implied completion claim.
