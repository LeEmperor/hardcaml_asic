# TT/CMOS5L flow execution and results

Status: operating guide, reconciled 2026-10-13. P4.1–P4.5 and the consumer reproduction are
closed with evidence; see
[phase plan section 7](../archive/phase-plan-through-p6.4b.md#7-p4--execution-results-and-physical-integration)
for what each historical gate rests on. Explicit-stage scope and later checks are
recorded in the [current closeout](../phase_plan.md#explicit-stage-refactor-closeout).
This is the
standing account of how the flow is run and how a run becomes an evidence
directory, and the only documentation of `flow.sh`, `report.py` and
`archive.py`: [bootstrapping](bootstrap.md) ends where this begins, and
[bundle emission](bundle-emission.md) produces its input. The same sequence is
used for this repository's examples and consumer-owned adopted bundles.

Start with the [explicit-stage quickstart](stage-quickstart.md). For the typed
OCaml facade to the opt-in schema-3 stage provider, see
[OCaml stage declarations and recipes](ocaml-stage-recipes.md), including
composition, the specimen recipe command and read-only `checkpoint-inspect`.

The P3 bundle is immutable input. The native `hardcaml-asic-flow` is an external consumer:
it verifies the emitted file hashes and pinned target references, creates a
unique run directory for each attempt, executes LibreLane, and collects results
from either new or existing run directories. It does not install tools or change
`manifest.json`.

## Installed Python API retirement

The thin installation ships only `__init__`, `backend_protocol`, `librelane_bridge`,
`stage_metadata_probe`, `probe`, `runtime_observation`, `runtime_contract`,
`managed_python` and `paths`, plus the four existing runtime data files.
The installed Python planner, runner, checkpoint, observation reader, collector,
reporter and archiver APIs are retired. This is a **Python API break**, including
previously advertised `execution_plan`, `flow_observation` and `IncrementalReader`
imports. Package **0.1.0** and CLI contract **4** remain unchanged because the
native CLI contracts remain unchanged; those numbers do not promise Python API
compatibility.

Use `hardcaml-asic-flow` commands or the typed `hardcaml_asic.execution` OCaml
library (`Hardcaml_asic_execution.Execution_plan`, `Runner`, `Checkpoint`,
`Observation` / `Observation.Reader` and native service modules). Deprecated reference/oracle
sources remain available optionally with `PYTHONPATH=/path/to/checkout/flow`.
That is SOURCE-only access, not equivalent installed support.
`scripts/{phase4,report,archive}.py` invoke those source references; the public
native command has a separate OCaml implementation.

<a id="default-result-store-and-cli-contract-3"></a>
## Default result store and CLI contract 4

Current interface, 2026-10-13: the installed CLI defaults to concise human
output. **All machine callers request `--json`**; this intentional presentation
contract is advertised as `cli_contract.version = 4` by `--version --json`, separately
from package version 0.1.0 and record schema 1. JSON stdout is the command's raw
payload, with paths, issues and verbose diagnostics on stderr. `--verbose` expands
stderr diagnostics; it does not change the payload or enable execution.
The additive `stages`, `checkpoint-inspect`, `observation`, `finalize` and
`finalization-inspect` interfaces also default to human summaries. With `--json`,
stage execution and finalization emit allocation and terminal JSON lines, not
one aggregate object. Stage journaling is now the default for fresh and resumed
CLI attempts. Persisted schemas and successful execution payloads are unchanged.
Machine callers must parse JSONL or explicitly select `stages --no-observation`.
The example accepts exact integer contracts 2/3/4 for existing Classic operations;
`project run --endpoint` requires 4. Consumer migration/private refresh and independent
review are complete; see [journal closeout](../development/flow-journal.md).

`--json` works before the command, anywhere after the command, and at either
observation parser level. An omitted inner flag never resets an outer flag:

```sh
hardcaml-asic-flow --json observation describe
hardcaml-asic-flow observation --json read-updates "$ATTEMPT" --stream-id "$STREAM_ID" --after 0
hardcaml-asic-flow observation read-updates --json "$ATTEMPT" --stream-id "$STREAM_ID" --after 0
hardcaml-asic-flow observation read-updates "$ATTEMPT" --stream-id "$STREAM_ID" --after 0 --json
hardcaml-asic-flow finalization-inspect --json "$FINALIZATION_ATTEMPT"
# Parsing pipelines must opt in; read-updates returns one complete object:
hardcaml-asic-flow observation read-updates "$ATTEMPT" --stream-id "$STREAM_ID" --after 0 --json | jq '.cursor'
```

Observed `stages --json` and `finalize --json` are JSONL: parse each line separately,
retain the early allocation receipt, and handle either terminal results or errors.
`stages --no-observation --json` returns one execution object. Unsupported combinations
(for example `archive --list --json`, `provision --json`, `describe --after`, or
`finalization-inspect --accept`) remain parser errors. `--verbose` selects stderr
diagnostics, not an alternate payload.

From the example checkout, with the existing current installation activated:

```sh
source .dev/asic/current/activate.sh
dune exec -j 20 bin/project.exe -- emit
dune exec -j 20 bin/project.exe -- preflight
dune exec -j 20 bin/project.exe -- preflight --json
# Future explicit expensive implementation request:
dune exec -j 20 bin/project.exe -- run --stage synthesis
```

The project CLI owns root discovery and emission; the installed provider owns
readiness and implementation. It checks supported provider contracts 2/3/4 before automatic
emission for preflight/run, then dispatches with `execv`, preserving provider exits
and signals. Missing/invalid or mixed `--stage`/`--endpoint` is rejected before
emission or dispatch. The explicit-stage endpoint route requires contract 4, creates
only the results parent and selects a new workspace with checkpoints inside and
the default observation store outside; see [example commands](stage-quickstart.md#run-and-observe).
Project `run` is **implementation only**: no implicit collect, postcheck, report,
archive, full acceptance or project `execute` operation.

| Command | Default storage / output | Explicit selection |
| --- | --- | --- |
| Project `describe` | Local declaration S-expression, no storage | `--json` wraps the S-expression and project name; not Workbench data |
| Project `emit` | Verified immutable `ROOT/_flow_results/bundles/<identity>`; human created/reused path and identity | `--output-dir DIR` retains new/empty-directory writing; `--json` prints identity/output_dir |
| Project `preflight` | Emit/reuse current source bundle, save a separate operation and readiness report | `--bundle DIR` bypasses emission; `--output FILE` selects an exact report file (existing parent), with no operation receipt |
| Installed `preflight BUNDLE` | `<results-root>/operations/<UTC-timestamp>_<id-prefix>/{operation,preflight}.json` | `--results-root DIR`, `--output FILE`, `--json` |
| Project/installed `run` | New `<results-root>/runs/<UTC-timestamp>_<id-prefix>` with full random run ID in `run.json` | Required `--stage synthesis\|full`; `--runs DIR` overrides the run store |
| Installed `collect RUN` | Writes `RUN/results.json`, prints its path | `--output FILE`; `--json` still writes normally; legacy `--stdout` emits read-only JSON |
| Installed `report TARGET` | Read-only coarse acceptance or stage evidence summary | Coarse `--json` retains raw results and acceptance exit; stage `--json` emits one `hardcaml-asic.report` envelope |
| Installed `execute BUNDLE` | Existing fixed run → optional full postcheck → collect → report → optional archive | Required stage; `--json` selects the sequence payload; no project counterpart |
| Installed `archive RUN` | Explicit `--output DIR` creates archive, or human `--list` reads selection | `--json --output DIR` supported; `--json --list` explicitly unsupported |

Installed roots default to `<caller-cwd>/_flow_results`, never a guessed project
root. The project default is `ROOT/_flow_results`; its tool default is separately
`ROOT/_flow_tools`, selected by `--toolchain` > nonempty `TOOLCHAIN` > default.
`--results-root`, `--runs`, `--source-root`/`--project-root`, `--output-dir` and
explicit tool overrides remain available. Relative overrides mean caller cwd.
An explicit preflight report destination does not suppress project automatic bundle
emission; use `--bundle` to select an already emitted bundle.
Project discovery walks upward for `dune-project` plus `asic-dependency.json`,
checks declared inputs, and refuses automatic discovery in `_build`, `_flow_results`
or `.dev`; use an explicit root there. Explicit paths retain symlink-parent/`..`
traversal. Description needs no root.

Use an explicit existing `RUN` for later operations:

```sh
RUN=/absolute/path/to/the-recorded-run-directory
hardcaml-asic-flow collect "$RUN" --json
hardcaml-asic-flow report "$RUN" --json
```

No newest-run guessing, arbitrary resume, GC or command per reader is added.
Preflight operations are diagnostics, **not implementation runs**. Pending records
are saved before probes; caught probe exceptions become saved failed readiness
reports and exit 1, while usage/output-path errors exit 2. Scoped SIGINT/SIGTERM
save interrupted diagnostics where storage permits. Run records precede readiness
probes; failed readiness leaves no staged project or implementation commands.
Run status describes implementation, not report acceptance. Atomic JSON replacement
does not promise fsync or power-loss recovery. Classic commands have no live event
journal; default CLI-stage observation is a separate bounded interface below.

## Explicit sequential stages and checkpoints

### Read-only reporting

```sh
hardcaml-asic-flow report "$WORKSPACE"
hardcaml-asic-flow report "$CHECKPOINT"
hardcaml-asic-flow report "$CHECKPOINT" --verbose  # complete cell-type table
hardcaml-asic-flow report "$WORKSPACE/execution-ATTEMPT.json" --json
```

`report TARGET` accepts an existing coarse run, checkpoint directory, stage
workspace containing exactly one **direct** `execution-*.json`, or explicit
segmented Runner execution JSON (plan schema 2/3). Conflicting structural markers,
malformed selected evidence and multiple executions are errors; select an explicit
execution file for multi-attempt workspaces. Discovery never scans recursively or
chooses the newest record. Observation directories use `observation inspect`.

Stage reports validate checkpoint inventory, hashes and host closure without
tool calls or writes. Query success exits **0**, including recorded failed,
interrupted or incomplete executions; malformed targets or invalid checkpoint
evidence exit **2**. Acceptance and external postcheck remain `not_evaluated`.
Checkpoint-only reports have no invented attempt duration or requested completion.
Physical `full` requires a selected, completed signoff occurrence and its validated
publication; it does not imply acceptance or successful outer execution.

Stage `--json` emits one object with contract `hardcaml-asic.report`, schema 1,
target/selected record, original validated execution (or null), completion,
checkpoints, provenance, availability-wrapped metrics and diagnostics. Human
output goes to stderr in JSON mode, otherwise stdout. All public checkpoint
metrics are retained; unknown units stay unknown, invalid counts stay unavailable.
Metrics describe the accumulated boundary snapshot, not measurements necessarily
made in that stage. Recorded target/corner context is not measurement attribution.
The coarse run human output, raw-results JSON and acceptance exits **0/1/2** retain
their existing contract. See [slice notes](../development/checkpoint-reporting.md).

When the selected checkpoint's inventoried `segment.json.run_dir` retains
`06-yosys-synthesis/reports/stat.json`, the stage report also shows Yosys's actual
cell-type inventory and sequential cell area in µm². The default table shows the
10 largest counts (ties sorted by name), with type count and total; `--verbose`
shows every row and `--json` always includes the complete sorted map. Numbers use
grouped decimal formatting in the human summary. Cell names are not interpreted
as classes or sequential counts.

Each `supplementary` entry records `kind: yosys_stat`, exact path, raw-byte SHA-256,
creator/tool, area values/units and inventory, explicitly labelled **retained
producer report; not checkpoint-inventoried**. This does not extend checkpoint
validation or attribute a measurement corner. Missing retained reports are optional;
malformed, duplicate-key, nonfinite or inconsistent reports produce diagnostics
without replacing checkpoint metrics or failing a valid checkpoint query. No
producer/observation search, tool invocation or source refresh is performed.

The OCaml `Execution_plan` / `Runner` modules own the coarse Classic sequence
and also execute opt-in stage plans. Preflight binds runtime once; each stage runs
in a fresh owned process/toolbox and publishes a checkpoint before its occurrence
can complete. StagePlan schema 3 has exactly these fields:

```json
{"schema_version":3,"stages":["synthesis","floorplan","placement","cts","routing","signoff"],"initial_boundary":null}
```

Fresh sequences start at synthesis; resumed sequences start immediately after
`initial_boundary`. Empty, repeated, reordered, skipped stages, extra fields and
duplicate JSON keys are rejected. `--plan FILE` and `--endpoint STAGE` are mutually
exclusive; endpoint shorthand expands a contiguous sequence. With `--checkpoint`,
endpoint shorthand infers its source. Legacy schema-2 endpoint/resume JSON remains
readable, with resumed source synthesis. SOURCE-only Python references use
`execution_plan.resolve_sequence(stages, initial_boundary=...)`,
`resolve_stages(endpoint, ...)` or `StagePlan.from_dict`; OCaml callers use
[`Flow.Stage` / `Flow.Recipe`](ocaml-stage-recipes.md).

| Boundary | Endpoint | Immediate successor | Standalone restart targets |
| --- | --- | --- | --- |
| synthesis | `Yosys.Synthesis` | `Checker.YosysUnmappedCells` | floorplan, placement |
| floorplan | `OpenROAD.Floorplan` | `OpenROAD.DumpRCValues` | placement |
| placement | `OpenROAD.DetailedPlacement` | `OpenROAD.CTS` | cts |
| cts | `OpenROAD.CTS` | `OpenROAD.STAMidPNR-1` | routing |
| routing | `OpenROAD.DetailedRouting` | `Odb.RemoveRoutingObstructions` | signoff |
| signoff | `Misc.ReportManufacturability` | none | none |

The SOURCE-only `stages.SegmentAdapter.run_segment` reference supplies the standalone direct synthesis →
placement capability; recipes include floorplan. CTS's later STA/repair is in
routing; routing checkers/fill/extraction are in signoff. Official Classic gates
and successors remain intact. There is no arbitrary DAG/custom-step/settings API.

Stages require Docker and exact image
`sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a`.
`stages.prepare` takes explicit bundle, support, PDK, interpreter, workspace and
checkpoint store. Fresh workspaces must not exist and their parent must exist;
checkpoint storage is inside the mounted workspace. Retain the original workspace
for resume. Default `--timeout 600` bounds each launch; real signoff evidence used
7200 seconds. No native/macro/other-image or relocated handoff is supported.

`checkpoint.publish` copies official state, configuration, closure, segment metadata
and every non-null view; a hashed schema-2 manifest declares exact restart targets,
compatibility, file inventories and `acceptance: not_evaluated`. Host and image-only
closure are validated before write-bit removal and atomic no-clobber promotion.
Publication failure prevents successor readiness. Retain original input/support/PDK
paths and the bound bridge/image; copied views remove dependence on old producer
runs, not those external roots. This is path-bound visibility/integrity, not fsync
durability, execution recovery or archive/GC. Schema-1 physical publications are
not upgraded. `checkpoint-inspect CHECKPOINT --restart-to STAGE` checks host closure
and transition only; `--compatibility EXPECTED_JSON` checks a caller-supplied object.
It reports `host_only` and `runtime_closure_validated: false`; execution validates
image-only closure anew. Public finite metrics and explicit unavailable values are
cumulative evidence, not per-step origin or an acceptance verdict.

Bundle public paths are symlinks to verified `.objects/<identity>.<unique>` data.
Preflight/run canonicalize them, so saved records may name the backing path;
both refer to the same immutable bundle. Keep published objects. Exact verified
reuse, exclusive no-clobber publication and race behavior are documented in
[bundle publication](bundle-emission.md#identity-addressed-publication).
`provision` retains bootstrap human output and rejects `--json`/`--verbose`.
`scripts/phase4.py` retains its historical path-only run contract and development
preflight JSON spelling; it is not the installed CLI presentation contract.

### Default persistent stage observation (schema 2; reads schema 1)

The installed provider exposes a separate structured API for Workbench and other
machine readers. CLI `stages` journals by default; standalone Python adapters and
runner APIs still require explicit Writer composition. Classic `run`/`execute`
keeps its existing behavior. An explicit store override remains available:

```sh
hardcaml-asic-flow stages "$BUNDLE" --support-tools "$TT" --pdk-root "$PDK" --python "$FLOW_PYTHON" --workspace "$NEW_WORKSPACE" --checkpoint-store "$NEW_WORKSPACE/checkpoints" --endpoint floorplan --observation-store "$OBSERVATIONS"
hardcaml-asic-flow observation describe
hardcaml-asic-flow observation inspect "$ATTEMPT_DIRECTORY"
hardcaml-asic-flow observation inspect "$ATTEMPT_DIRECTORY" --json  # complete machine payload
hardcaml-asic-flow checkpoint-inspect "$CHECKPOINT" --restart-to cts
hardcaml-asic-flow checkpoint-inspect "$CHECKPOINT" --restart-to cts --json
hardcaml-asic-flow observation read-updates "$ATTEMPT_DIRECTORY" --stream-id "$STREAM_ID" --after 5
```

Default root: `<resolved-workspace-parent>/observations`, outside the workspace.
`--observation-store ROOT` overrides it; `--no-observation` disables journaling.
These options are mutually exclusive. `OBSERVATIONS` must be outside the workspace.
The workspace's parent must exist; it is not created to make allocation succeed.
Fresh execution still requires a new workspace; resumed execution requires the
original retained workspace and an explicit `--checkpoint`; `--plan` only supplies
the recipe and does not replace that checkpoint path.
Every resume allocates a new stream and never reopens the source attempt.
Each observation attempt is exclusively allocated under the chosen root. Before
recipe/checkpoint reading, preflight or tool execution, the observed `stages`
command flushes an early human allocation receipt. With `--json`, it flushes one
JSON-line receipt with `contract`, `schema_version`,
`event: observation_allocated`, `stream_id`, and absolute `attempt` directory.
With `--json`, when execution returns, the next line is the complete existing
execution JSON (also for runner-returned failure/interruption). Its execution file
is published before the journal outcome. Both stdout records are explicitly flushed.

Caught preparation/plan/storage/output failures use a CLI delivery envelope, not a
new journal event or persisted schema:

| Field | Meaning |
| --- | --- |
| `contract`, `schema_version` | `hardcaml-asic.stage-observation`, 1 |
| `event` | `observation_terminal` |
| `status`, `exit_code` | CLI `failed`, 2; or `interrupted`, `128 + signal` |
| `attempt`, `stream_id` | Allocated absolute path and full identity, or null if Writer allocation did not succeed |
| `execution_file` | Absolute execution JSON path only after successful publication, otherwise null |
| `observation` | Complete read-only inspector payload after releasing locks, or null if unavailable |
| `recording_error` | Additional journal publication/inspection error, or null |
| `error` | `{code, detail}`; `BUSY`, `INTERRUPTED`, `EXECUTION_FAILED`, or existing observation error code |

Allocation failure emits only this terminal envelope, without invented attempt or
result identity. Parser errors remain argparse diagnostics, not JSON envelopes.
After allocation, failures normally record an outer outcome even if delivering the
receipt fails. Storage failure can leave no outcome; completed/published stage facts
are preserved. Abrupt exit or broken stdout cannot promise a terminal line. Writer
locks and scoped signal handlers cover allocation, receipt, preparation, execution,
aggregate publication and terminal delivery. A recorded interruption does not prove
external cleanup; consult the referenced transport evidence.

All observation queries and `checkpoint-inspect` default to labeled plain-text
reports. Add `--json` for their complete unchanged machine payloads, including
structured errors. JSON may precede the command, follow `observation`, or appear
after `inspect`/`checkpoint-inspect` (before or after the path). Diagnostics go to
stderr. Inspection success remains exit 0 even for a recorded failed execution;
invalid/missing records or failed checkpoint validation remain exit 2.
`describe --json` and `read-updates --json` return their complete strict JSON.
Human updates show up to 20 chronological event summaries (first/last ten for larger
responses), publication paths, omitted count and an explicit complete-response cursor;
empty reads do not imply completion. These read commands
need no tools, a PDK, or original producer process. `describe` returns the contract
`hardcaml-asic.stage-observation`, `schema_version: 2`, `supported_schema_versions: [1, 2]`, capabilities, closed field
descriptions under `schemas`, writer and retention policies. Use native observation
commands or OCaml `Hardcaml_asic_execution.Observation` / `Observation.Reader`. The historical
`hardcaml_asic_flow.flow_observation.describe()`, `inspect(directory)` and
`read_updates(directory, stream_id=..., after=...)` are SOURCE-only references.
For an efficient
foreground follow use `observation watch` below. `inspect` supplies a consistent recorded prefix and
its cursor; concurrent later events can be fetched after that cursor. Reader calls
do not acknowledge execution, append events, repair records, or acquire ownership.

#### Foreground incremental watch

```sh
hardcaml-asic-flow observation watch "$ATTEMPT_DIRECTORY"
hardcaml-asic-flow observation watch "$ATTEMPT_DIRECTORY" --interval 0.5 --json
hardcaml-asic-flow observation watch "$ATTEMPT_DIRECTORY" --stream-id "$STREAM_ID" --after "$CURSOR" --json
```

This is a separate foreground reader process, with no daemon, provider subprocess,
reader state file or execution control. Human output prints **every** delivered
event chronologically (no 20-event elision), then labeled reader status and recorded
results. `--json` at the global, observation or watch level selects flushed JSONL;
each stdout line is one complete object. Diagnostics go to stderr.

| Envelope | Exact top-level fields |
| --- | --- |
| `updates` | `event: "updates"`, `contract`, `schema_version`, `stream_id`, `after`, `cursor`, `events` |
| `status` | `event: "status"`, `contract`, `schema_version`, `stream_id`, `cursor`, `writer_active`, `observation_status`, `outcome`, `final_results` |

The contract is `hardcaml-asic.stage-observation`; updates/status use the validated
stream's schema version (1 for legacy journals, 2 for new journals). `updates` contains
the unchanged complete `read_updates` payload plus its envelope discriminator;
`events` contains full journal records, including hashes and event-specific data.
It is emitted only for a nonempty suffix. `after` is the supplied cursor on first
delivery, then the last delivered cursor; `cursor` covers **all** delivered events.
`status` has boolean/null writer activity, `live|final|writer_lost_or_unknown`,
the recorded `{status, exit_code, error}` outcome or null, and the same
`final_results` summary as inspect. Status is emitted on attachment and changes,
including final status before stopping; identical idle status is suppressed.
These envelopes are reader delivery, never new journal events.

Without reconnect arguments the reader validates the full prefix and delivers
from zero. `--stream-id` and `--after` must be supplied **together**; wrong stream,
negative/noninteger or beyond-head cursor requires reset (query error 2;
`RESET_REQUIRED`, except argparse syntax errors). Cursor zero is valid; a cursor
at the current head delivers only status until more events arrive. A cold reconnect
still validates the entire retained prefix, including records before the cursor.
Persist your own stream/cursor only after processing an entire updates envelope;
delivery is cursor-based, without acknowledgements or an exactly-once promise.

`--interval` must be positive and finite, defaults to 0.5 seconds and controls idle
polling. The retired SOURCE-only Python reference is
`IncrementalReader(directory, *, stream_id=None, after=None)`;
`poll()` returns `(updates, status)` dictionaries **without** envelope `event`
fields. Each poll returns updates even when empty; the CLI suppresses empty updates.
The constructor fully validates once; polls stat the cached prefix and read/hash/
reduce only newly promoted records with the same strict validator as cold replay.
Retained deletion, replacement or metadata change, gaps, promoted truncation,
hash/stream/grammar corruption fail closed. Discard a failed reader and reconnect
explicitly. Hidden temporary tails are ignored. Idle polls still check the attempt
activity lock; after absent/unknown writer activity the reader drains the committed
tail again before deciding loss, avoiding the final-publication/release race.

Reader exit codes are **0 for any recorded terminal outcome**, **3** for unresolved
writer loss/unknown activity, **2** for corruption/cursor/query errors (also broken
stdout), and **130** for reader Ctrl-C. The recorded execution `outcome.exit_code`
is independent: a failed or interrupted execution is still a successful terminal
query. Disconnect, broken stdout, Ctrl-C and a slow reader affect only delivery;
they never cancel, write to, or take the workspace lock of the executor. Broken
stdout exits without a Python traceback. Lost writers imply neither cleanup nor
invented interruption; runtime cleanup evidence remains at its recorded reference.

Efficiency is bounded: polls list/stat O(prefix length) metadata and retain events/
reduced state in memory; only new content is parsed. Integrity metadata is device,
inode, size, nanosecond mtime/ctime under a trusted local immutable-file convention,
not hostile-owner tamper protection. Atomic visibility is not fsync/power-loss
durability. No store-wide subscription, heartbeat, relocation, repair, writer
takeover, backend-step lifecycle or execution recovery is introduced.

**Journal and lifecycle schema.** An attempt contains atomically promoted
`000000000001.json`, `000000000002.json`, … records plus `writer.lock` and, when
preflight is reached, `preflight.json`. Each record has exactly:

```text
contract, schema_version, stream_id, sequence, previous_sha256,
event, data, recorded_at, elapsed_seconds, sha256
```

New writers produce **schema 2**. The timing fields are included in the canonical
record hash, not reader delivery metadata:

| Field | Schema-2 meaning and strict validation |
| --- | --- |
| `recorded_at` | Producer recording time in UTC, exactly `YYYY-MM-DDTHH:MM:SS.ffffffZ`; valid calendar date/time, six fractional digits, no offsets or leap-second spelling |
| `elapsed_seconds` | Finite nonnegative JSON number (not boolean/string), monotonic seconds since attempt creation immediately before allocation after workspace ownership; nondecreasing across the stream |

Recording time is sampled during append **before atomic record promotion**; it is
not physical tool-start time, fsync/durable-write time, or reader receipt time.
Lifecycle callbacks append synchronously while execution runs: `started` precedes
the stage operation, `published` follows validated checkpoint promotion, and
`finished` follows the stage return. Records are not batched at execution end.
Sequence remains authoritative even when the UTC wall clock moves backward.
Elapsed time is independent of wall-clock adjustments and differs from each
occurrence's `duration_seconds`.

Schema-1 records have exactly the fields above **except** `recorded_at` and
`elapsed_seconds`. New readers retain their original facts, hashes and schema-1
inspect/read-updates/watch payloads without modifying historical files or inventing
times from mtimes. A stream must use one schema throughout; missing/extra timing,
invalid UTC, nonnumeric/nonfinite/negative or regressing elapsed values and mixed
schema streams fail closed. Human watch/read-updates append a succinct
`[recorded 2026-10-13T12:00:00.123456Z; +1.250s]` to timed events; legacy events
have no timing label. JSON retains the full precision of both fields.

CLI contract stays **4**, package **0.1.0**, identity schema **1**. Negotiate journal
support through `observation describe --json` (`supported_schema_versions`,
`producer_event_timestamps`, `monotonic_elapsed_seconds`) or identity capabilities
(`stage_observation_schemas: {write: 2, read: [1, 2]}` plus both timing flags).
Consumers of timed journals must accept schema 2 explicitly. The JSONL discriminators
and field sets are unchanged; inspect/read-updates/watch report the stream's schema.
Allocation/terminal/error CLI delivery envelopes keep their independent schema 1;
a terminal envelope's nested `observation` reports the stream's version. Identity's
generic `supported_record_schemas: [1]` still describes the existing coarse
runner/collector/reporter/archiver records, not the separately versioned journal.

Sequence starts at 1. `previous_sha256` is null at 1 and otherwise the preceding
record hash. `sha256` hashes UTF-8 JSON of the other fields with sorted keys,
compact separators and `allow_nan=False`. The stream/attempt ID is a fresh
32-character lowercase UUID hex value; occurrence IDs are stable
`STREAM_ID/implementation.STAGE`. Events are:

| Event | Exact `data` fields | Meaning |
| --- | --- | --- |
| `allocated` | `request`, `workspace`, `checkpoint_store`, `lock_path`, `preflight_record` | Intent and explicit path-bound references, before preflight |
| `planned` | `plan` | Validated StagePlan schema 2 or 3; all occurrences initially `unreached` |
| `prepared` | `runtime_record` | Staging/binding returned; runtime facts remain a separate referenced transport record |
| `started` | `occurrence`, `artifact` | Stage running; artifact null |
| `published` | `occurrence`, `artifact` | Validated atomic checkpoint publication returned; stage still running |
| `finished` | `occurrence`, `artifact` | Outer stage completed/failed/interrupted; completed requires its prior publication |
| `outcome` | `status`, `exit_code`, `error` | Final outer operation outcome, after execution-record publication |

Occurrence fields are exactly `occurrence_id`, `action_key`, `status`, `exit_code`,
`duration_seconds`, `best_effort`, `error`, `verdict`. Status is `unreached`,
`running`, `completed`, `failed`, or `interrupted`; unreached successors are never
inferred skipped. Here `best_effort` is false and `verdict` is null. Checkpoint
references have `path`, `identity`, `boundary`, `restart_supported`,
`restart_targets`, `closure_scope`, `tested_image_id`, `acceptance` (the existing
checkpoint schema-2 reference contract).

`inspect` returns `contract`, `schema_version`, `stream_id`, `cursor`, `state`,
`writer_active`, `observation_status`, `final_results`. `state` contains
`attempt_id`, all allocation fields, `phase`, `plan`, `occurrences`, `artifacts`,
`runtime_record`, and `outcome`. Phase is `preparing`, `executing`, or `finished`;
missing plan/runtime/outcome are null. Preflight errors preserve their diagnostic
report; preparation errors leave planned stages unreached. Stage failures block
successors. Final outer failure may coexist with already completed physical work.

`final_results` has `physical_completion` (`completed` only after a recorded
signoff-stage finish, otherwise `not_recorded`), explicit `checkpoint_refs`,
`acceptance: not_evaluated`, and `external_postcheck: not_evaluated`. A segmented
signoff checkpoint is not a fully accepted result. External postcheck/acceptance
is delivered as the [separate finalization operation](#segmented-terminal-results-and-external-acceptance-opt-in),
which never revises this terminal stage stream.

`read-updates` returns `contract`, `schema_version`, `stream_id`, `after`, `cursor`,
and `events` (complete journal records strictly after the requested cursor).
Wrong stream, negative/noninteger or beyond-head cursor produces `RESET_REQUIRED`.
Missing/malformed/gapped records, hash-chain failures, duplicate keys, nonfinite
JSON and invalid lifecycle transitions produce `INVALID_RECORD`; inspection fails
closed without returning a success snapshot. With `--json`, errors are JSON
`{contract,schema_version,error:{code,detail}}`, exit 2.

**Ownership, interruption and retention.** Observed writers hold a nonblocking
Linux/POSIX advisory workspace lock across allocation/preparation/execution, even
when using different observation roots. A per-attempt lock supplies best-effort
writer presence: `writer_active` is boolean, or null if it cannot be checked.
Unobserved Classic executions and external programs do not participate in this
lock. Released writers cannot append; another attempt does not revive the old
one. There is no writer takeover, execution recovery, or request idempotency.

SIGINT/SIGTERM are recorded when handling and storage succeed. SIGKILL/crashes or
failed journal writes leave the last committed prefix: `outcome` stays null and
`observation_status` becomes `writer_lost_or_unknown` when no writer is observed.
Do not interpret a stale `running` status as current liveness, or artifact publication
as stage/outer completion. Temporary hidden write files are ignored; incomplete
promoted records are errors. Atomic replacement is process-restart-readable, not
an fsync or power-loss durability guarantee. Hashes detect corruption, not hostile
owner mutation. Preserve the observation directory, workspace, checkpoints and
external input/support/PDK roots. Inspect reports historical publication facts; it
does not revalidate current checkpoint contents or promise ongoing artifact readiness.
This is a bounded per-attempt stage journal, not the full provisional provider
fixture contract, a store-wide catalog, or raw LibreLane step/body observation.

Observation delivers early per-attempt correlation and checkpoint publication
facts, not a store-wide catalog, fine internal-step observation or acceptance.
It is a public provider reader seam, not completed Workbench application integration.
See [current acceptance](../phase_plan.md#explicit-stage-refactor-closeout).

## Runtime policy and launch binding

Current source candidate, reviewed 2026-10-13: schema-1 bundles emitted now add
`requested_tools.runtime_policy`. The scalar `python=3.11` continues to request
the **host flow venv** minor, distinct from host CLI Python >=3.9. Native execution
uses that host runtime. Dockerized implementation requests the official
`ghcr.io/librelane/librelane:3.1.0.dev3` image, exact LibreLane version, and
distribution-supported Python **3.10..3.14** with `Requires-Python >=3.10`.
Host 3.11.17 / container 3.13.13 is therefore valid without a uniform pin bump
or waiver. Host LibreLane and headless Tcl must also be ready.

Absent policy means legacy exact-minor checks for **both** host and container.
Malformed/contradictory explicit policy fails closed; installed defaults cannot
replace bundle authority. The development adapter's `--allow-python-mismatch`
only applies to valid legacy Python mismatches. It cannot waive new policy,
malformed versions, LibreLane or metadata failures.

**Emit a fresh bundle to obtain new semantics; never edit an old manifest.** From
`hardcaml_asic_example`, with the current candidate already installed:

```sh
source .dev/asic/current/activate.sh
BUNDLE="$PWD/.dev/runtime-contract-checks/bundle-20261013-01" # new destination
dune exec -j 20 bin/project.exe -- emit --source-root "$PWD" --output-dir "$BUNDLE"
hardcaml-asic-flow preflight "$BUNDLE" --toolchain "$PWD/_flow_tools"
```

Choose another new destination if that one exists. Provider adoption still awaits
the owner; the recorded `171476...` pin has not advanced. Activation selects the
existing installation, not a refresh. [Acceptance](../phase_plan.md#hostcontainer-runtime-policy-closeout)
names the accepted generation and dated bundle snapshot.

Preflight preserves flat `actual` keys and adds structured `runtime_contract`
policy, role observations and comparisons. New `run.json` adds
`execution_binding`: observed local image ID, engine and interpreter flags.
RepoDigests are separate evidence, not interchangeable with image IDs; the
official tag remains mutable across machines. Direct Docker transport launches
that ID with the same flags, staged project RW / PDK RO, rootless-aware UID,
ambient image overrides removed and owned cleanup with a separate deadline.
This changes transport only, not LibreLane's flow engine. New postcheck verifies
the recorded image/engine and records simulator identity separately. Historical
records retain tag/engine fallback. Readiness and tiny transport smoke do not
establish synthesis or physical compatibility; no real ASIC flow was run in this
closeout. Later [explicit-stage physical evidence](../../evidence/librelane-observation/slice4-physical.json)
and [external acceptance](../../evidence/librelane-observation/slice6-finalization.json)
are separate successful experiments, not a reinterpretation of readiness checks.

## Running it

`scripts/flow.sh` fills in this repository's example, testbench and reference
paths and hands every flow operation to the shared dispatcher — the same
implementation the installed `hardcaml-asic-flow` command runs — so there is one
account of sequencing, acceptance, run selection and archiving. It takes one
command per invocation, and no argument prints its help rather than starting
anything:

```sh
scripts/flow.sh                      # help; nothing is built or run
scripts/flow.sh build                # dune build -j 20 && dune runtest -j 20
OUT=/tmp/try KIND=memory scripts/flow.sh emit
OUT=/tmp/try STAGE=synthesis scripts/flow.sh execute   # run -> collect -> report
OUT=/tmp/try RUN=/tmp/try/runs/<id> scripts/flow.sh report
scripts/report.py "$RUN"             # a specific run directory
scripts/report.py --runs "$RUNS"     # development only: newest run under a store
```

`execute` is the shared command's fixed sequence: run, then postcheck for a full
stage, then collect, then report, then an archive only if one was asked for. The
individual commands (`preflight`, `run`, `postcheck`, `collect`, `report`,
`archive`) are the same operations on their own, and any option the shared
command accepts can be passed straight through, for example
`scripts/flow.sh archive --output /tmp/evidence` or `scripts/flow.sh report
--json`.

Every path is an overridable environment variable (`TOOLCHAIN`, `TT`, `PDK`,
`FLOW_PY`, `PRECHECK_PY`, `OUT`, `BUNDLE`, `RUNS`, `KIND`, `STAGE`, `TESTBENCH`,
`TESTBENCH_TOP`, `RUN`). The defaults come from `.toolchain/toolchain-env.sh`,
which `./bootstrap.sh` writes and `flow.sh` sources; anything already set in the
environment wins over it, so `TT=... scripts/flow.sh preflight` still points the
run at another checkout. Two of them are required rather than defaulted, because
guessing either is how an expensive run or a misattributed record happens:
`STAGE` for `run` and `execute`, since there is no default stage, and `RUN` for
every resumed operation, since the newest directory under `$RUNS` is never
assumed to be the one you meant — run identities are independent random hex,
and installed `run`/`execute --json` print `run_dir` in their payload. New run
directories include a timestamp prefix, but selection is still explicit. `ALLOW_PYTHON_MISMATCH` is
gone: nothing waives the bundle's requested Python by default, and the driver
says so and stops if it is still set.
`report.py --runs "$RUNS"` selects newest by modification time; use an
explicit run path for durable evidence. `report.py` derives its acceptance scope
from the requested stage recorded consistently in `run.json` and `results.json`.
For a full run it prints timing per corner, signoff checks, the TT precheck rows,
and what the post-CTS resizer did about hold. It exits nonzero when required
evidence is missing or malformed, a required check fails, the requested stage
did not complete, the records contradict each other, or a full run leaves a
timing mode unconstrained. The `phase4.py` subcommands below remain a supported
development spelling of the same operations: `phase4.py`, `report.py` and
`archive.py` are adapters onto `flow/hardcaml_asic_flow/`, which is what the
installed `hardcaml-asic-flow` command runs, so there is one implementation under
all of them.

With `--json`, installed `execute` ends with one stderr line per step with its
status and duration, the absolute run directory, and the archive path when one
was published, followed by a single JSON object on stdout carrying the run
identity, per-step statuses and the final outcome. It prints that on failure and
on interruption too, so an attempt that stopped still names the run holding its
diagnostics. Without `--json` it prints human summaries and saved paths. A failed
step keeps its own status rather than being flattened
into the sequence's. For scale, the reference observable bundle is roughly 24
minutes to harden and 8 more to postcheck.

`$OUT` — one bundle and its runs — defaults to `../p4-$KIND`, **outside this
repository**, and should stay outside it. A completed `full` run directory is
around 235 MB of OpenROAD, Magic, and KLayout output: ODB and DEF snapshots per
step, fill insertion, GDS streamout, SPICE extraction. That is tool output, not
a result, and it does not belong in a git working tree. What belongs in the
repository is the curated record under [`evidence/`](../../evidence): the complete
immutable input bundle, manifest, preflight, run, postcheck, and results JSON,
plus the logs and signoff reports the acceptance criteria are actually read
from. The run store is scratch and can be deleted once `archive.py` has produced
and verified that complete evidence directory.

## Environment

`./bootstrap.sh` provisions everything the flow needs, pinned by
`toolchain.lock`, and nothing else on the machine:

```sh
./bootstrap.sh                  # converge both layers
./bootstrap.sh --check          # report the state of both, change nothing
./bootstrap.sh --install-deps   # also install missing packages into the opam switch
```

It provisions `.toolchain/{tt,pdk,.venv,.venv-precheck}` and the LibreLane
container image, and writes `.toolchain/toolchain-env.sh` for `flow.sh` to read.
The [bootstrap guide](bootstrap.md) covers the layers, the options, overriding
paths, and what to do when a check fails.

There is no dependency on a sibling checkout, in either direction. The pins are
this repository's own, in `lib/target.ml` and `lib/bundle.ml`; `toolchain.lock`
is a copy of them for the shell, and `test/check_bundle.py` fails `dune runtest -j 20`
if the two ever disagree.

Bootstrapping prepares an environment. It does not prove the design hardens,
meets timing, or passes precheck: those are the flow operations and their own
exit codes. `scripts/phase4.py preflight` then checks the particular emitted bundle
against the installed files, and never fetches or installs anything itself.

The runner uses Dockerized LibreLane by default and needs an accessible Docker
daemon; see [bootstrap troubleshooting](bootstrap.md#troubleshooting) when it is
installed but unreachable. The runner copies the pinned floorplan into its
per-run staging directory so the container can resolve `dir::../tt/...`. It reads
PDK views from `PDK_ROOT`.

From this repository root, after emitting a bundle as in
[bundle emission](bundle-emission.md):

```sh
SUPPORT_TOOLS=/absolute/path/to/tt-support-tools
PDK_ROOT=/absolute/path/to/IHP-Open-PDK
FLOW_PYTHON=/absolute/path/to/librelane-venv/bin/python
BUNDLE=/absolute/path/to/emitted-bundle
RUNS=/absolute/path/to/run-storage

python3 scripts/phase4.py preflight "$BUNDLE" \
  --support-tools "$SUPPORT_TOOLS" --pdk-root "$PDK_ROOT" \
  --python "$FLOW_PYTHON" --output "$RUNS/preflight.json"

python3 scripts/phase4.py run "$BUNDLE" \
  --support-tools "$SUPPORT_TOOLS" --pdk-root "$PDK_ROOT" \
  --python "$FLOW_PYTHON" --runs "$RUNS" --stage synthesis

python3 scripts/phase4.py collect "$RUNS/<printed-run-id>" \
  --output "$RUNS/<printed-run-id>/results.json"
```

Use `--stage full` for place and route and LibreLane physical checks. The
`--native` run option uses locally installed EDA executables, when their versions
and interfaces are compatible. Preflight enforces the bundle's
[role-specific runtime policy](#runtime-policy-and-launch-binding).
`scripts/phase4.py` retains `--allow-python-mismatch` for legacy-only development
compatibility; the installed command exposes no such option. A run prints its `run.json` path even
if it fails. Its `execution.log` and partial `project/runs/asic` contents remain
available, and retries receive distinct IDs.

The development `scripts/phase4.py preflight` prints JSON on stdout; installed
`preflight --json` selects JSON and saves the report by default. `--output` writes the same
report to a file. Use it: the report is the record of why a run was allowed to
start — every external file hash, the actual tool and container versions, and
any version waivers — and scrollback does not survive as evidence. A run no
longer needs that file copied into it: `run` performs its own preflight and
saves that one as the attempt's `preflight.json`, so the record in a run is the
one that actually gated it. The report is the same structure `run.json` stores
under `environment`.

After a completed full run, check TT's layout rules and simulate the final
gate-level netlist with the observable wrapper testbench:

```sh
python3 scripts/phase4.py postcheck "$RUNS/<printed-run-id>" \
  --support-tools "$SUPPORT_TOOLS" --pdk-root "$PDK_ROOT" \
  --precheck-python /absolute/path/to/precheck-venv/bin/python \
  --testbench test/tt_bundle_tb.v --testbench-top tb_observable

python3 scripts/phase4.py collect "$RUNS/<printed-run-id>" \
  --output "$RUNS/<printed-run-id>/results.json"
```

Postcheck uses the pinned support-tools `precheck/default.nix` and a separate
Python environment with its KLayout dependency. The gate-level simulation runs
Icarus from the run's pinned LibreLane image, because the CMOS5L flop models
depend on `$setuphold` delayed nets that Icarus 12 leaves undriven. It compiles
the PDK I/O, UDP, and standard-cell models with the final `nl` netlist. It
records the GDS, netlist, and testbench hashes, simulator image and version,
command log, and both verdicts under `checks/<id>/`.

The bundle's LibreLane settings must include the TT template's physical
settings, supplied as reasoned overrides. `Tt_cmos5l.overrides` supplies them, so
a declaration gets them by asking rather than by copying. Without
`FP_PDN_MULTILAYER=0` and the template's PDN and LEF-pin settings, LibreLane's
defaults put the power grid on `TopMetal1`, and TT precheck rejects the layout
even though LibreLane's own DRC, LVS, and antenna checks pass.

`run.json` records build identity, manifest hash, actual environment, command
arguments, requested/completed stage, status, timestamps, and output paths.
`results.json` separates process completion from timing goals and physical
checks. Synthesis area is mapped standard-cell area in µm², and the cell-type
inventory comes from Yosys `stat.json`. Setup and hold slack are in ns, reported
with the worst corner when available. Missing metrics have reasons. Raw reports
remain linked by paths relative to the run directory. The collector is a separate
command and also works on a failed or partially completed run.

A synthesis-only run passes `report.py` only when both records consistently say
that synthesis was requested and completed, collection has no errors, mapped
cell and area metrics are finite and valid, and unmapped instances, synthesis
errors, and inferred latches are all explicitly present and zero. Zero mapped
area or cells is valid evidence for a design that legitimately maps that way; it
is not rejected by a generic positive-area rule. Physical timing, antenna, DRC,
LVS, postchecks, and hold repair are reported as not evaluated and not required
for this operation, never rewritten as passes. The final verdict says
`synthesis acceptance passed` rather than claiming physical signoff.

A requested full run remains subject to the complete policy: both records must
show full completion; synthesis evidence must meet the same requirements; setup
and hold metrics must be finite, cornered, and constrained with a passing timing
goal; DRC, LVS, and antenna must each be present and pass; and a completed
postcheck must explicitly pass both TT precheck and gate-level verification. A
full request that stops after synthesis therefore fails rather than being
reclassified as synthesis-only. Unknown, missing, or contradictory stage fields
also fail with diagnostics. Missing metrics remain unavailable, not zero or
pass.

## Evidence and remaining acceptance

The [phase plan](../archive/phase-plan-through-p6.4b.md#7-p4--execution-results-and-physical-integration)
tracks which P4 gates have actual run evidence. Mapped synthesis requires zero
unmapped instances and synthesis errors, a standard-cell mapping inventory, and
the memory bundle's explicit flop selection. A completed full LibreLane run alone
does not close P4.5: retain the TT precheck and gate-level wrapper check alongside
the physical reports before marking that gate complete.

Both gates now have records:
[`evidence/p4/memory-synthesis`](../../evidence/p4/memory-synthesis/README.md) for
P4.4 and
[`evidence/p4/observable-physical`](../../evidence/p4/observable-physical/README.md)
for P4.5, which closes P4's exit gate. Each historical directory contains the
immutable records — manifest, preflight, run, postcheck, results — plus an
archive of the logs and reports its claims are read from, and a note stating the
result and any waivers. Archives made before complete-input preservation was
added may not contain `input-bundle.tar.gz` and cannot be reconstructed from
`reports.tar.gz`; do not infer otherwise. New archives use the complete shape
below. Note that the P4.5 run used this repository's own example: it proves the
physical path, and it is deliberately not reusable as P5.4 consumer-adoption
evidence.

### Building one

`scripts/archive.py` writes that shape from a finished run directory:

```sh
scripts/archive.py RUN_DIR --list                       # the selection, writes nothing
scripts/archive.py RUN_DIR --output evidence/p4/NAME    # records and both tarballs
```

It copies the immutable records out and writes two archives. `reports.tar.gz`
contains the logs and reports an acceptance decision is read from together with
`final/gds` and `final/nl`. `input-bundle.tar.gz` contains the original
`manifest.json` bytes plus exactly every path in `manifest.files`: copied source
inputs, synthesis and simulation RTL, configuration, constraints, and metadata.
`input-bundle.sha256` pins that tarball. `archive.json` names every member and
absence, records the bundle archive digest and size, and states whether the
verified bytes came from the original or staged bundle.

The final GDS and netlist are included on purpose. Everything else in the archive
is evidence that a check passed; those two are the run's actual output, the only
inputs to a precheck or gate-level rerun that cannot be regenerated without
hardening again, and together they cost about 500 KB compressed. The compiled
simulator (`checks/*/gate.out`) and the intermediate stage directories — `odb`,
`mag`, `mag_gds` — stay out: they are rebuildable and nothing reads them.

Every hash the run already pinned is re-checked on the way in: the staged
manifest against `run.json`, build identity against the manifest, every bundle
file against the manifest, source-input copies against both manifest inventories,
and the GDS, netlist and testbench against `postcheck.json`. Paths must be unique,
relative, contained regular files; symlinks and traversal are rejected. The
archiver prefers the original path in `run.json`. If that directory no longer
exists or is invalid, it accepts `RUN_DIR/project` only when that staged copy is
independently complete and valid. Added `tt/`, `runs/`, tool trees, and other
undeclared staging files are never included.

All validation and archive construction finish in a sibling temporary directory
before publication. A failure leaves an existing evidence directory unchanged.
`--force` replaces files owned by the archiver, including both input-bundle files,
while retaining `README.md` and other user-owned files. An absent reports input
is still reported rather than skipped, which is how a synthesis stage run
archives without pretending it has a layout. The input tarball uses stable member
ordering, timestamps, ownership, and modes, so unchanged input bytes produce the
same compressed archive digest.

The archiver does not write the `README.md` beside the records. That note is the
human account of what the run showed, and a generated stand-in would read as
though someone had checked the result.

Restore and verify the complete bundle using only the evidence directory:

```sh
EVIDENCE=/absolute/path/to/evidence-directory
RESTORE=$(mktemp -d)
(cd "$EVIDENCE" && sha256sum --check input-bundle.sha256)
tar -xzf "$EVIDENCE/input-bundle.tar.gz" -C "$RESTORE"
python3 - "$RESTORE/bundle" "$EVIDENCE/run.json" <<'PY'
import hashlib, json, pathlib, sys
bundle, run_path = map(pathlib.Path, sys.argv[1:])
manifest_bytes = (bundle / "manifest.json").read_bytes()
manifest = json.loads(manifest_bytes)
run = json.loads(run_path.read_text())
assert hashlib.sha256(manifest_bytes).hexdigest() == run["manifest_sha256"]
assert manifest["identity"] == run["build_identity"]
for entry in manifest["files"]:
    data = (bundle / entry["path"]).read_bytes()
    assert hashlib.sha256(data).hexdigest() == entry["sha256"], entry["path"]
print("verified", len(manifest["files"]), "bundle files for", run["run_id"])
PY
```

This verification needs no checkout, original bundle, run directory, PDK, or
opam switch. Re-executing or preflighting the restored design still requires the
separately recorded toolchain and external collateral. The consumer's historical
[clean-staging archive](../../../scaf/flow_results/20260920-081325-ccecd9ed/README.md#preservation-and-restoration)
demonstrates the earlier manual preservation procedure; its record is not
rewritten by this capability. Do not edit emitted inputs to make restoration or
preflight pass.

The pinned LibreLane flow has a known ABC timing-print limitation: its renderer
passes `cell/pin` where ABC expects a cell name. The consumer's
[analysis](../../../scaf/tinytapeout/reports/2026-09-20-p0.7-memory-synthesis.md#abc-diagnostics)
shows why that print is not timing evidence. It does not invalidate mapped
cell/area evidence or the independently reported post-route OpenSTA timing.

## Segmented terminal results and external acceptance (opt-in)

`finalize` selects the six published checkpoints from one completed fresh
six-stage execution JSON. It validates their identities, full host closure,
shared configuration and exact runtime binding, then rechecks the shared image-only
closure with the retained bound bridge in that image. This validation calls no
`Flow.start` and does not repeat implementation. Only this demonstrated schema-2
checkpoint composition is eligible; independently resumed execution stitching is
not yet supported by finalization.

```sh
hardcaml-asic-flow finalize WORKSPACE/execution-ATTEMPT.json --operation-store OPERATIONS
hardcaml-asic-flow finalize WORKSPACE/execution-ATTEMPT.json --operation-store OPERATIONS --accept --support-tools TT --precheck-python PRECHECK_PYTHON --testbench CONSUMER/acceptance/replay.v --testbench-top replay --replay-trace TRACE.txt
hardcaml-asic-flow finalization-inspect OPERATIONS/OPERATION_DIRECTORY
```

Paths are caller-cwd-relative or absolute; the operation store is explicit. The
source adapter is `PYTHONPATH=flow python3 -B -m hardcaml_asic_flow`. `--replay-trace`
is optional for self-contained benches; for the example's consumer replay it
copies the supplied reference trace into the check attempt and passes its retained
path as `+trace=...`. The consumer's `acceptance/export_trace.exe` produces that
oracle; record its command/hash when producing evidence. No Dune command is hidden
inside finalization.

Without `--accept`, this operation publishes results with external postcheck and
acceptance `not_evaluated`. With `--accept`, it invokes the **existing**
`phase4.check` and `report.report` services: TT precheck under its pinned Nix
environment, gate-level simulation in the implementation's exact bound container,
then the existing full acceptance policy. Missing/malformed synthesis, timing,
DRC/LVS/antenna evidence, unconstrained timing and failed external checks remain
failures. Classic `run`, `execute`, `postcheck`, `collect`, `report` and `archive`
keep their interfaces and default policy.

### Separate operation snapshot contract

Each invocation allocates a new `result_store` attempt and atomically updates its
`operation.json`, contract **`hardcaml-asic.segment-finalization`, schema 1**. The
CLI flushes an early allocation receipt and shows status, selected publication
paths, result path, requested acceptance versus actual verdict and external postchecks.
With `--json` it flushes an allocation JSON line (`contract`, `schema_version`, `event:
allocated`, `attempt`, `attempt_id`) before validation, and prints the final
receipt plus `attempt` afterwards. Exit 0 means the requested operation completed;
1 means failed validation/checks/acceptance; interruption uses 128 + signal.
Allocation/storage errors that prevent recording return 2 without inventing facts.

`finalization-inspect` strictly reads the receipt without writing; its human default
uses the same summary, and `--json` returns the complete receipt. A running receipt
has no terminal exit; failed validation does not imply acceptance rejection, while
`acceptance: fail` is an actual rejection. `interrupted` is cancellation/interruption.
This is a **separate versioned snapshot API**, not the stage journal/cursor API:
the terminal implementation stream is never reopened or rewritten. Required
receipt fields are:

- `contract`, `schema_version`, fresh `attempt_id`, `request` (execution path,
  accept flag, explicit later-check inputs), `started_at`, nullable `ended_at`;
- `status`: `running`, `completed`, `failed`, or `interrupted`; `phase`: last entered
  `validation`, `collection`, `external_postcheck`, or `acceptance`;
- `external_postcheck`: `not_evaluated`, `running`, `completed`, `failed`, or
  `interrupted`; `acceptance`: `not_evaluated`, `pass`, or `fail`;
- `commands` (actual runtime-validation argv), nullable `results` and `error`;
  terminal receipts additionally have `exit_code`.

As work progresses, optional evidence fields record `execution` (original path,
SHA256 and attempt ID), `binding`, `selected_checkpoints` (six path/identity/boundary
refs), `runtime_validation: completed`, `selected_evidence`, `mapped_files`
(bytes/SHA256 inventory), `adapter`, `evidence_context`, `postcheck_collateral`
(full selected TT precheck/tech file inventory), `postcheck_record` / `postcheck_sha256`
and `acceptance_report` (path/SHA256). Transport
may append `container_cleanup` diagnostics. `results` has an exact path/SHA256.
`phase` is diagnostic, not an independent success event. A `running` snapshot after
writer loss is unresolved; inspection makes no liveness, recovery or invented
completion claim. Atomic replacement provides process-readable snapshots, not
fsync durability, a journal, fencing, takeover or hostile-owner protection.

The adapter copies official synthesis/signoff states, final GDS/netlist/LEF,
manifest, constraints and TT metadata into the new attempt. It derives the metrics
CSV directly from cumulative official signoff metrics and retains all raw values.
Synthesis area/cell/check metrics come from the synthesis checkpoint, never from
inherited final counts or a fabricated Yosys report. Worst-slack selection still
includes all timing evidence; an equal-value tie prefers an actual corner over an
anonymous aggregate in this mapped adapter. Every public metric
or physical check adds `origin_boundary`; the results' `provenance` names the
adapter, operation and selected publications. Unavailable sequential-area/cell-type
details remain unavailable. No per-step remeasurement provenance is claimed.

The existing services receive an explicit canonical **in-memory evidence context**:
its `run_id` is the new operation ID and `full` denotes the selected six-stage
physical completion, not completion of an old classic run. That context and
provenance are saved in the operation receipt; **no synthetic `run.json` or
`stat.json` is written**. Real later-check records stay under this operation's
`checks/`; new mapped checks also carry an `evidence_origin` reference. Results
are published only after collection and consistency checks; failed acceptance
still retains collected evidence and the reporter's `acceptance.txt` diagnostics.

### Retention and current real verdict

Retain the operation directory, selected checkpoints, original path-bound
workspace/bundle/collateral/PDK roots and exact image for audit and reruns. Receipt
references report historical selection; they are not permanent readiness or an
automatic retention guarantee. Finalization checks readiness anew each time and
rechecks selected inputs after external checks. The copied evidence is a bounded
acceptance package, not a complete restart closure or a classic archive input.
The existing classic archiver continues to require its genuine run/bundle
contract; preserve the operation tree directly rather than fabricating that record.

The real consumer experiment is `experiments/finalization_smoke.py`, reusing
`/tmp/opencode/librelane-slice4-production` without another physical flow. Curated
verdict and retained operation paths are in
[`evidence/librelane-observation/slice6-finalization.json`](../../evidence/librelane-observation/slice6-finalization.json).
The real operation passed all nine applicable TT checks and the 11,429-edge
bound-image replay; shared full acceptance passed. Six disconnected pins and one
max-fanout violation remain visible in raw final metrics, outside the existing
acceptance gates. `experiments/verify_finalization.py OPERATION` audits retained
hashes and re-evaluates the current shared collector/reporter read-only.

The accepted operation took 675.606435 seconds: worst setup 11.67551954830797 ns
at `nom_slow_1p08V_125C`, hold 0.12502899069955042 ns at
`nom_fast_1p32V_m40C`; DRC/LVS/antenna passed. Earlier missing-metadata and timeout
attempts remain failures in the evidence. The final independent review reran
full software checks and audited retained physical/accepted evidence, without
repeating implementation or external checks. Exact commands and counts are in
the [review record](../development/explicit-stage-refactor.md#exact-successful-verification).
