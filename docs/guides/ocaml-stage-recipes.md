# OCaml stage declarations and recipes

Delivered and independently reviewed 2026-10-13. For a short execution path, see
the [stage quickstart](stage-quickstart.md); [current closeout](../phase_plan.md#explicit-stage-refactor-closeout)
links full checks and actual physical/postcheck evidence.

The public `Hardcaml_asic.Flow.Stage` and `Flow.Recipe` modules describe the
provider's opt-in explicit-stage execution contract. The same modules are also
available as `Flow_stage` and `Flow_recipe`; their `.mli` files are the API
reference. Construction and JSON rendering are pure and require no toolchain.

`Project.create ~flow:(Flow.librelane Hardening)` still selects project adapter
settings and technology views. Emit/publish the input bundle with the existing
Project API, and supply a **separate recipe file** to `hardcaml-asic-flow stages
--plan`. The recipe does not enter the bundle manifest or bundle identity. Existing
`Synthesis`/`Hardening`, overrides, bundle schemas, `run` and `execute` retain their
contracts. A recipe does not change project settings or make a synthesis-only
bundle suitable for physical implementation.

## Typed declarations

```ocaml
open Core
open Hardcaml_asic

let recipe =
  Flow.Recipe.create
    ~initial_boundary:Flow.Stage.Floorplan
    [ Flow.Stage.Placement; Cts; Routing; Signoff ]
  |> Or_error.ok_exn

let () = printf "%s\n" (Flow.Recipe.to_string recipe)
```

This renders exactly schema 3:

```json
{"schema_version":3,"stages":["placement","cts","routing","signoff"],"initial_boundary":"floorplan"}
```

- `Flow.Stage.t`: `Synthesis | Floorplan | Placement | Cts | Routing | Signoff`.
  `all`, `to_string`, and strict lowercase `of_string` support command frontends.
- `Flow.Stage.capability`: exact backend endpoint, immediate successor,
  standalone restart targets, tested image ID, typed `Path_bound` closure scope
  and `Not_evaluated` acceptance. These are static demonstrated capabilities;
  actual readiness is provider-owned.
- `Flow.Recipe.create ?initial_boundary stages`: nonempty contiguous composition.
  A fresh recipe begins at synthesis. A resume begins immediately after its
  declared source. Repeats, reversal and omissions return `Or_error` before I/O.
- `Flow.Recipe.through ?initial_boundary endpoint`: endpoint shorthand, expanded
  to the same schema-3 sequence. `through Signoff` includes all six stages;
  `through ~initial_boundary:Floorplan Placement` includes placement only.
  Endpoints at/before the source and terminal sources return errors.
- `Flow.Recipe.compose first second`: joins declarations when the second source
  equals the first endpoint, retaining the first source. For example,
  `through Floorplan` composed with `through ~initial_boundary:Floorplan Signoff`
  gives the fresh six-stage recipe. This does not stitch historical executions.
- `stages`, `initial_boundary`, `endpoint`, `required_input`, `declarations` expose
  typed facts. Inputs are `Input.Bundle` or `Input.Checkpoint stage`; each ordered
  declaration names its stage, predecessor input and output checkpoint boundary.
  A boundary requirement does not prove readiness of any checkpoint directory.
- `to_yojson` and `to_string` emit only the three strict schema-3 fields. Recipes
  are abstract: callers cannot forge an unchecked record. There is no raw backend
   JSON argument or per-stage settings API.

The installed Python counterpart is `hardcaml_asic_flow.execution_plan`:

```python
from hardcaml_asic_flow.execution_plan import StagePlan, resolve_sequence

recipe = resolve_sequence(["placement", "cts", "routing", "signoff"],
                          initial_boundary="floorplan")
assert StagePlan.from_dict(recipe.as_dict()) == recipe
```

`resolve_stages(endpoint, initial_boundary=...)` expands endpoint shorthand;
schema-2 endpoint/resume readers remain compatible. Schema 3 has exactly
`schema_version`, `stages`, `initial_boundary`, with null source for fresh recipes.

The standalone Python segment API can resume synthesis directly through placement.
Composable recipes deliberately include floorplan, matching the provider's
contiguous schema-3 contract. Backend successor checkers remain included: CTS ends
at `OpenROAD.CTS`, its later STA/repair work begins routing; routing ends at
detailed routing, its checkers/fill/extraction begin signoff.

## Runnable consumer example

The sibling `hardcaml_asic_example` supplies an additive pure companion executable.
It and the existing project CLI were independently linked against an isolated
installed candidate. This proves consumer linkage, not adoption of a committed
dependency pin. With that candidate library/CLI installed and activated, run from
that checkout:

```sh
dune exec -j 20 bin/stage_recipe/stage_recipe.exe -- --endpoint floorplan > /tmp/floorplan-recipe.json
dune exec -j 20 bin/stage_recipe/stage_recipe.exe -- --initial-boundary floorplan --endpoint signoff > /tmp/resume-recipe.json
dune exec -j 20 bin/project.exe -- describe --json
```

The recipe command writes JSON to stdout and rejects invalid declarations with
exit 2. It needs no project root, bundle, PDK or Docker. It is separate from the
specimen's declared design source inventory and existing `project` commands.
For a fresh implementation, select an existing published bundle and explicit
toolchain roots, then request a new workspace whose parent already exists.
CLI journaling defaults to `<resolved-workspace-parent>/observations`. Keep an
explicit override outside that workspace; `--no-observation` is a mutually
exclusive single-object-output escape hatch. Python adapter/runner APIs still
choose no store implicitly:

```sh
BUNDLE=/absolute/path/to/published/bundle
TT=/absolute/path/to/support-tools
PDK=/absolute/path/to/pdk
FLOW_PYTHON=/absolute/path/to/flow-venv/bin/python
WORKSPACE=/absolute/path/to/new-workspace
OBSERVATIONS=/absolute/path/to/observation-store
hardcaml-asic-flow stages "$BUNDLE" --plan /tmp/floorplan-recipe.json \
  --support-tools "$TT" --pdk-root "$PDK" --python "$FLOW_PYTHON" \
  --workspace "$WORKSPACE" --checkpoint-store "$WORKSPACE/checkpoints" \
  --observation-store "$OBSERVATIONS"
```

Execution prints a flushed allocation receipt and human stage/publication summary
(add `--json` for allocation/terminal JSONL) and retains an
`execution-<attempt>.json`. Use the receipt's explicit attempt path for inspection:

```sh
hardcaml-asic-flow observation describe
hardcaml-asic-flow observation describe --json
hardcaml-asic-flow observation inspect /absolute/path/to/observation-attempt
hardcaml-asic-flow observation inspect /absolute/path/to/observation-attempt --json
hardcaml-asic-flow observation watch /absolute/path/to/observation-attempt
hardcaml-asic-flow observation watch /absolute/path/to/observation-attempt --stream-id STREAM_ID --after CURSOR --json
hardcaml-asic-flow observation read-updates /absolute/path/to/observation-attempt --stream-id STREAM_ID --after 0
hardcaml-asic-flow observation read-updates /absolute/path/to/observation-attempt --stream-id STREAM_ID --after 0 --json
hardcaml-asic-flow checkpoint-inspect /absolute/path/to/floorplan-checkpoint --restart-to placement
hardcaml-asic-flow checkpoint-inspect /absolute/path/to/floorplan-checkpoint --restart-to placement --json
```

Watch follows in-process and read-only; reconnect stream/cursor must be supplied
together. Machine delivery is complete flushed updates/status JSONL; reader Ctrl-C
does not interrupt execution. See [envelopes, exits and limits](flow.md#foreground-incremental-watch).
Both inspectors default to readable plain-text reports; machine readers must add
`--json` for the full unchanged payload. With `--json`, checkpoint success (exit 0) returns
`validation: "host_only"`, `runtime_closure_validated: false`,
`compatibility_source: "recorded"`, and the validated manifest. It checks manifest
identity/location, all copied files/views, host external closure and requested
restart eligibility. `--compatibility EXPECTED_JSON` compares against the caller's
expected compatibility object instead of the recorded object, and reports
`compatibility_source: "expected"`. Failures return exit 2 and, with `--json`, a JSON
`error` string. Diagnostics use stderr. `--restart-to` validates a transition only;
it does not resume execution. Observation endpoint completion is distinct from
full physical completion and acceptance; checkpoint metrics are accumulated evidence.
Reading does not publish, mutate, allocate, launch containers or validate image-only
files. The execution adapter validates runtime closure and current compatibility
before physical work; host inspection is not a substitute.

To resume, pass `/tmp/resume-recipe.json` as `--plan`, the floorplan publication as
`--checkpoint`, and **the retained original workspace and checkpoint-store paths**
to the same `stages` command. Supply the same bundle/tool roots. The provider
checks the publication's actual source against the recipe and validates complete
runtime/bridge/configuration compatibility. It never chooses a newest checkpoint.

## Execution boundary and limits

This library does not start Python or Docker. Application-owned command execution
is the boundary: write recipe JSON, invoke the installed CLI using argument arrays
in the application's runtime, consume structured receipts/results and preserve
exit/signal semantics. There are no fabricated OCaml lifecycle callbacks, async
handles or phantom checkpoint types. The provider's separate observation reader
CLI supplies inspection and cursor updates; see [flow guide](flow.md) for schemas.

The stage service requires Docker and the exact tested image
`sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a`.
Keep path-bound workspace, inputs, support tools, PDK roots and bridge/image
closure. Native/macro/relocated/other-image handoffs, arbitrary DAGs/ranges,
per-stage configuration and recovered execution are future contracts.
Static capabilities do not upgrade older schema-1 checkpoints.

Signoff completion/publication has `acceptance: not_evaluated`. External checks
and acceptance use the separate `finalize` operation. Currently finalization
requires one completed fresh six-stage execution; composed declarations are
supported, stitching resumed multi-attempt evidence for finalization is not.

## Contract verification

From the provider root:

```sh
dune build -j 20 @test/ocaml-stage-recipes @test/stage-checkpoint @test/flow-cli @install
dune install -j 20 --prefix /tmp/asic-recipe-prefix
```

From the sibling checkout, compile against that installed library:

```sh
OCAMLPATH="/tmp/asic-recipe-prefix/lib${OCAMLPATH:+:$OCAMLPATH}" dune build -j 20 --build-dir /tmp/asic-recipe-consumer-build bin/stage_recipe/stage_recipe.exe bin/project.exe
```

Back in the provider checkout, validate against the installed Python package:

```sh
python3 -B test/check_stage_recipes.py --emitter _build/default/test/stage_recipe_contract.exe \
  --provider-prefix /tmp/asic-recipe-prefix \
  --consumer-executable /tmp/asic-recipe-consumer-build/default/bin/stage_recipe/stage_recipe.exe
```

The test decodes actual OCaml output in the installed Python provider, compares
capabilities and ordered handoffs, checks all length-0-through-3 candidate sequences
for every source, all endpoint expansions (including long sequences), composition,
provider mismatch rejection, installed checkpoint inspection and independently
linked specimen output. It exercises no physical EDA. Use a new private prefix for
reproduction; the independently linked specimen requires the same current library.

Final independent verification passed 36 accepted / 1819 rejected recipe cases,
all 42 consumer endpoint/source combinations, capability/handoff/composition
equality and installed host-only reader success/failure checks. The forced full
suite and 51-case installed-prefix suite also passed; stage regressions total 30.
These are API/packaging checks. Actual six-stage physical execution, observed
execution and existing-policy external acceptance are separately recorded in
[slice 4](../../evidence/librelane-observation/slice4-physical.json),
[slice 5](../../evidence/librelane-observation/slice5-observed.json) and
[slice 6](../../evidence/librelane-observation/slice6-finalization.json).
Full Workbench integration, store-wide journal/idempotency/fsync, execution recovery
and segmented artifact archive/GC remain outside this API.
