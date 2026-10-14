# Explicit-stage quickstart

The explicitly selected stage provider runs six sequential boundaries: synthesis → floorplan
→ placement → cts → routing → signoff. The existing coarse `run`/`execute` path is
also supported. See [detailed OCaml/Python recipes](ocaml-stage-recipes.md) for typed
construction/composition and [flow contracts](flow.md) for complete reader schemas.

## Run and observe

The example consumer exposes fresh explicit stages through its ordinary command
after activating a contract-4 installation:

```sh
# From hardcaml_asic_example, with existing provisioned _flow_tools:
. .dev/asic/current/activate.sh
dune exec -j 20 bin/project.exe -- run --endpoint synthesis --json
```

Endpoints are synthesis, floorplan, placement, cts, routing and signoff. The
consumer emits/reuses a bundle, resolves source/results/tools using its existing
rules, selects a unique nonexistent workspace in results with checkpoints inside,
and execs provider `stages`. Default journals live in results/`observations`.
`--stage synthesis|full` remains Classic and is mutually exclusive with endpoint;
`--native`/`--runs` fail before emission for endpoints. `--bundle` bypasses emission,
and human/JSON provider output is forwarded unchanged, including early allocation.
Use that receipt with the watch commands below. See the
[consumer quickstart](../../../hardcaml_asic_example/README.md#explicit-stage-run-and-independent-progress-reader)
and [actual integration evidence](../development/flow-journal.md).

Use a published physical-capable bundle and provisioned tool roots. The candidate
library/CLI must be installed; activating an older consumer pin does not upgrade it.
Stages require Docker and the exact tested image
`sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a`.
Choose a **new** workspace whose parent exists, with checkpoints inside it and
observations outside it:

```sh
BUNDLE=/absolute/path/to/published/bundle
TT=/absolute/path/to/support-tools
PDK=/absolute/path/to/pdk
FLOW_PYTHON=/absolute/path/to/flow-venv/bin/python
WORKSPACE=/absolute/path/to/new-workspace
hardcaml-asic-flow stages "$BUNDLE" --endpoint signoff \
  --support-tools "$TT" --pdk-root "$PDK" --python "$FLOW_PYTHON" \
  --workspace "$WORKSPACE" --checkpoint-store "$WORKSPACE/checkpoints" \
  --timeout 7200
```

This is an explicit expensive implementation request. For a short first run, use
`--endpoint floorplan`. For declarative composition, replace `--endpoint signoff`
with `--plan RECIPE.json`, containing exactly:

```json
{"schema_version":3,"stages":["synthesis","floorplan","placement","cts","routing","signoff"],"initial_boundary":null}
```

Journaling defaults to `$(dirname "$WORKSPACE")/observations` after resolving the
workspace. Override with `--observation-store ROOT`, or opt out with the mutually
exclusive `--no-observation`. Fresh and resumed commands both allocate new streams.

Inspect retained results without running tools:

```sh
hardcaml-asic-flow report "$WORKSPACE"
hardcaml-asic-flow report "$CHECKPOINT" --verbose  # every retained Yosys cell type
hardcaml-asic-flow report "$WORKSPACE/execution-$ATTEMPT_ID.json" --json
```

Set `CHECKPOINT` to the published checkpoint directory. A workspace must contain
exactly one direct execution record; otherwise select the exact execution JSON.
The default cell table shows up to 10 rows; JSON contains the full inventory.
Retained Yosys statistics are supplementary, explicitly not checkpoint-inventoried;
missing statistics leave checkpoint metrics visible and invalid statistics produce
diagnostics. See [read-only reporting](flow.md#read-only-reporting).

The command flushes an early human allocation receipt, then a stage and
publication summary, and retains `WORKSPACE/execution-<attempt>.json`. Add `--json`
to the stages invocation for contract-4 allocation/terminal JSONL. Successful
terminal execution payloads are unchanged; caught preparation/storage/interruption
errors use the [defined terminal envelope](flow.md#default-persistent-stage-observation-schema-2-reads-schema-1).
Use the receipt's
explicit attempt path and stream ID; the readers below default to human reports:

```sh
hardcaml-asic-flow observation describe
hardcaml-asic-flow observation describe --json  # complete contract/schema
hardcaml-asic-flow observation inspect "$ATTEMPT"
hardcaml-asic-flow observation inspect "$ATTEMPT" --json  # machine readers
hardcaml-asic-flow observation watch "$ATTEMPT"  # foreground; Ctrl-C stops only this reader
hardcaml-asic-flow observation watch "$ATTEMPT" --stream-id "$STREAM_ID" --after "$CURSOR" --json
hardcaml-asic-flow observation read-updates "$ATTEMPT" --stream-id "$STREAM_ID" --after 0
hardcaml-asic-flow observation read-updates "$ATTEMPT" --stream-id "$STREAM_ID" --after 0 --json  # cursor polling clients
hardcaml-asic-flow checkpoint-inspect "$FLOORPLAN_CHECKPOINT" --restart-to placement
hardcaml-asic-flow checkpoint-inspect "$FLOORPLAN_CHECKPOINT" --restart-to placement --json
```

Save each completely processed updates cursor and reconnect with stream/cursor
together. Watch JSON is flushed `updates`/`status` JSONL, interval defaults to 0.5s;
query exit 0 means any recorded terminal (including failed), 3 unresolved writer
loss, 2 query/corruption errors and 130 reader Ctrl-C. See the
[complete watch protocol](flow.md#foreground-incremental-watch). Inspection reports
historical publication facts. `checkpoint-inspect` validates host closure only;
execution separately validates image-only closure and compatibility. Publication,
stage completion, outer outcome and acceptance are distinct facts.

## Resume an explicit publication

From a floorplan checkpoint, endpoint shorthand expands placement through signoff:

```sh
hardcaml-asic-flow stages "$BUNDLE" --endpoint signoff \
  --checkpoint "$FLOORPLAN_CHECKPOINT" \
  --support-tools "$TT" --pdk-root "$PDK" --python "$FLOW_PYTHON" \
  --workspace "$WORKSPACE" --checkpoint-store "$WORKSPACE/checkpoints" \
  --timeout 7200
```

Use the **retained original workspace**, bundle/tool/PDK roots and compatible
bridge/runtime. A schema-3 equivalent has stages `placement, cts, routing, signoff`
and `initial_boundary: "floorplan"`. Recipes never skip required boundaries.
Standalone restart targets are synthesis → floorplan/placement, floorplan →
placement, placement → cts, cts → routing and routing → signoff; signoff is terminal.
The direct synthesis → placement capability belongs to the standalone Python
segment API, not contiguous recipes. No newest-checkpoint lookup exists.

## Finalize separately

Only **one completed fresh six-stage execution** is currently eligible. A resumed
attempt or standalone signoff checkpoint cannot be finalized by stitching history.
Select its saved execution JSON explicitly:

```sh
hardcaml-asic-flow finalize "$EXECUTION_JSON" --operation-store "$OPERATIONS"
hardcaml-asic-flow finalize "$EXECUTION_JSON" --operation-store "$OPERATIONS" \
  --accept --support-tools "$TT" --precheck-python "$PRECHECK_PYTHON" \
  --testbench "$TESTBENCH" --testbench-top "$TESTBENCH_TOP" --replay-trace "$TRACE"
hardcaml-asic-flow finalization-inspect "$FINALIZATION_ATTEMPT"
hardcaml-asic-flow finalization-inspect "$FINALIZATION_ATTEMPT" --json  # complete receipt
```

Finalize flushes a human allocation receipt before validation and shows results/
acceptance afterwards. Parsing callers add `--json` for allocation/terminal JSONL.
The first command publishes results-only with acceptance `not_evaluated`; the
second allocates a separate operation for TT precheck, bound-image gate replay and
the existing full acceptance policy. `--replay-trace` is optional for self-contained
benches. Finalization validates/maps retained evidence without rerunning physical
implementation and never reopens the stage stream.

Retain observations, execution JSON, checkpoints, operation tree and original
path-bound input/support/PDK/bridge/image closure. No archive/GC, relocation,
native/macro support, arbitrary DAG/custom steps, per-stage settings, execution
recovery, store-wide idempotency/fsync or completed Workbench integration is promised.

## Evidence and checks

The [closeout](../phase_plan.md#explicit-stage-refactor-closeout) records forced
full checks, installed-package tests and isolated consumer linkage, distinct from
adopting a committed pin. Curated repo JSON retains
[six-stage physical evidence](../../evidence/librelane-observation/slice4-physical.json),
[actual observation](../../evidence/librelane-observation/slice5-observed.json) and
[successful postcheck/acceptance](../../evidence/librelane-observation/slice6-finalization.json).
The earlier [blocked probe](../../evidence/librelane-observation/blocked-local.json)
remains history; later successful evidence supersedes its feasibility limit.
