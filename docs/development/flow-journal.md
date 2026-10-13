# Default flow journal and foreground readers

Status: **delivered; final independent review, fix and documentation closeout complete**,
2026-10-13. The initial audit added only this document; dated slice evidence and
the final tested scope are recorded below. Remaining limits are explicit.

Producer event timing follow-on: new writers now produce **journal schema 2** with
hash-protected `recorded_at` (canonical UTC) and `elapsed_seconds` (monotonic seconds
since attempt creation). New readers retain schema-1 facts/payloads without invented
times and reject mixed-version streams. CLI contract remains 4; inspect/read-updates/
watch responses match the stream version, while allocation/terminal/error delivery
envelopes remain schema 1. Human timed events display both producer values. See
[timing contract, controlled live tests and integration handoff](journal-event-timing.md).
The historical schema-1 evidence below remains a dated record; the timing feature's
private consumer refresh and real EDA verification are still pending independently.

**Slices 1–3 and independent review delivered (2026-10-13):** default
fresh/resumed CLI journaling, contract-4 allocation/terminal delivery, incremental
foreground reader/watch, ordinary consumer endpoint route, private installation
refresh and one real synthesis/watch/reconnect capture. The final review corrected
non-pipe reader stdout failure and refreshed the private installation once.

## Requested bounded feature

Make provider-owned progress available by default for new explicit-stage command
runs, with structured allocation, recorded progress and results, and an efficient
reconnectable foreground reader. Reuse the delivered journal rather than creating
a second execution/event engine. Terminal use must work without Workbench or a
daemon. Preserve truthful interruption and abrupt-exit behavior.

The minimum meaningful delta is:

1. `stages` automatically allocates the existing observation journal before recipe
   validation/preflight; its allocation tells humans and machine clients where to
   inspect/follow. Explicit store selection remains available.
2. `observation watch` follows that attempt in a separate foreground process,
   delivering validated events and reader status with stream/cursor reconnection.
3. The example's ordinary `project run` gains an explicit-stage route, so this
   feature is reachable without assembling the low-level provider command by hand.

Progress means coarse provider stage transitions, not percentage estimates, log
parsing, heartbeats or LibreLane backend-step lifecycle. Results mean the recorded
execution and checkpoint references; full external acceptance remains a separate
`finalize` operation. Default journaling is command composition owned by the
provider; independently callable adapters/runner do not silently choose stores.

### Selected scope

The current example `project run --stage synthesis|full` invokes Classic, not
explicit stages. This implementation adds the mutually exclusive `--endpoint`
route, keeps existing `--stage` semantics, and delivers default explicit-stage
journaling plus watch first.
Do not silently reinterpret Classic `full` as segmented signoff or claim that the
existing ordinary run already journals. If all existing Classic invocations must
journal, schedule the separate coarse adapter described below; that is additional
scope requiring confirmation, not an implicit schema redesign.

## Audited baseline before slice 1

Sources audited: workspace `../AGENTS.md`,
[execution boundary](workbench-execution-boundary.md),
[explicit-stage record](explicit-stage-refactor.md),
[human-output record](human-readable-flow-output.md), and actual provider modules
and tests listed below. Both provider and consumer Git status were clean at entry.

| Area | Delivered behavior and source |
| --- | --- |
| Journal contract | `flow/hardcaml_asic_flow/flow_observation.py`: `hardcaml-asic.stage-observation`, schema 1, one path-bound attempt. `Writer(root, workspace=..., checkpoint_store=..., request=...)`, `Writer.run(plan_factory, prepare, finalize=None)`, `describe`, `inspect`, `read_updates`. |
| Allocation | `Writer` takes nonblocking advisory workspace flock, calls `result_store.allocate`, holds a separate attempt activity flock, and atomically publishes `allocated`. CLI flushes the allocation receipt before validation/preparation. Store must be outside the workspace; the workspace parent must already exist for its lock file. |
| Events | Closed grammar: `allocated`, `planned`, `prepared`, `started`, `published`, `finished`, `outcome`. Records have stream identity, contiguous sequence, previous hash and canonical record hash. Request is an object; plan is strict `StagePlan` schema 2 or 3. |
| Sequencing | `runner.execute` owns the sequence. Lifecycle callback receives `(event, action, occurrence_dict, artifact_or_none)`. For segments, publication follows complete host/runtime validation and atomic checkpoint promotion; `published` still has a running occurrence, then `finished` establishes stage completion. |
| Preparation | `stages.prepare(..., preflight_output=...)` reuses `result_store.durable_preflight`; pending, failed and interrupted diagnostics are retained before a workspace exists. Successful preparation records the bound transport path. |
| Results | CLI publishes `workspace/execution-<stream_id>.json` before outer outcome. `inspect` reduces recorded occurrences/artifacts and reports separate physical completion, `acceptance: not_evaluated`, and `external_postcheck: not_evaluated`. Execution path is derivable from workspace/attempt ID; it is not a dedicated journal result-reference event. |
| Readers | `inspect` and `read_updates` are read-only, strict full-prefix replay. Wrong stream/out-of-range cursor is `RESET_REQUIRED`; corrupt promoted records, gaps, hash/transition violations fail closed. Hidden temporary tails are ignored. No watch command exists. |
| Ownership/liveness | Workspace flock coordinates observed writers across roots; per-attempt activity flock prevents a new attempt reviving an old stream. `writer_active` is true/false/null. No outcome plus absent/unknown lock is `writer_lost_or_unknown`, never invented interruption or success. |
| CLI | Contract 3. Human defaults; complete `--json`, including global/command/nested placements. Journal is opt-in via `stages --observation-store ROOT`. Observed stages emit allocation then execution JSONL; unobserved stages emit one execution object. No live progress output is emitted between these by the execution command. |
| Finalization | `finalization` has an independent schema-1 operation snapshot/receipt and inspector. It does not reopen a terminal stage journal. Fresh six-stage selection and acceptance are separate from physical endpoint completion. |
| Classic | `phase4.run` retains `run.json`, preflight, transport/cleanup evidence and logs. Coarse `runner.Plan`/`ServiceAdapter` sequences implementation/postcheck/collect/report/archive for `execute`; this is not a persistent stage journal. |

`result_store.save_json` uses a temporary file and `os.replace`. This establishes
atomic visibility and process-restart readability, not fsync/power-loss durability.
Published journals are immutable by convention under a local trusted owner.

### Existing failure evidence and concrete gaps

Already covered by `test/test_flow_observation.py` (16 cases): reconnecting
independent readers, SIGTERM during long preparation and execution, SIGTERM after
publication, SIGKILL between publication and completion, publication/store/final
aggregate failure, competing workspaces, released writers, cursor resets and
corruption. `test/test_stages.py` covers validation/publication-before-readiness;
`test/test_runner.py` covers coarse sequencing, skipped/unreached, best-effort
collection and acceptance separation. `test/test_phase4.py` and transport tests
cover interruption/owned cleanup; `test/test_result_store.py` covers allocation,
atomic replacement and durable diagnostics. Presentation and installed-prefix
tests cover exact JSON/JSONL, early allocation, flag positions and read-only queries.
These are existing tests inspected in this audit, not tests rerun here.

Concrete limitations to address in the next feature:

- `read_updates(after=...)` calls `load`, rereading, hashing and reducing every
  record before slicing the suffix. Repeated idle polling redoes all content work.
  This is correct stateless validation, but not an efficient persistent watch.
- `read_updates` itself carries no writer/outcome status for an empty suffix.
  A watch must report reader status separately without treating an idle stream as
  completion or calling full `inspect` on every poll.
- CLI interruption during observed preparation can emit only allocation on machine
  stdout and exit 130/143, even though `Writer.run` saved an interrupted outcome;
  the caught signal branch emits no terminal machine envelope. Fix this protocol
  gap, and explicitly flush terminal machine output (currently plain `print`).
- The workspace lock/allocation/receipt currently precede `Writer.run`'s scoped
  signal handlers. Default composition should bracket the owned command lifecycle
  and release locks even when receipt output fails. Do not promise a record before
  allocation succeeds or when storage itself fails.
- Failures writing the execution aggregate can leave completed stage facts but a
  failed outer outcome. Storage failure/SIGKILL can leave running facts and no
  outcome. These are truthful states, not bugs to repair by synthesizing success.
- Cleanup outcome lives in transport evidence, not journal occurrence fields.
  An interrupted outer outcome is not proof that containers or descendants stopped.
  `phase4.run_logged` records removed-or-absent versus failed container cleanup and
  client termination diagnostics; watch should retain the reference, not infer more.

### Consumer routing and installed state

`../hardcaml_asic_example/bin/project.ml` accepts only integer CLI contracts 2 or 3.
It validates provider compatibility before bundle emission, emits/reuses the
bundle, resolves source/results/tool roots, then `execv`s provider `run` with
`--stage synthesis|full`. It accepts no endpoint/recipe/workspace/checkpoint-store/
observation options. Adding default observation to provider `stages` alone will
not change that path. Routing evidence is in
`../hardcaml_asic_example/scripts/test_project_routing.py`; private installation
compatibility is also checked by `scripts/asic_dependency.py` and its tests.

The current private generation receipt names
`90770d6ce6f04696b3b0082fb3898944`, provider base
`ebdcfbfec88cc05f433bec8d289d98b7ad76d4cf`, captured snapshot
`be2db93d3f1b92a8b240167ebadd0b4c0a81484e78356c56cec867f5b19f8e4a`.
Recorded consumer pin remains `1714764859274f80a9f5ad207421a04601824e99`.
The installed launcher was activated and checked during this audit: contract 3,
package 0.1.0, unstamped. No refresh is needed for auditing current capabilities.

## Proposed interfaces, compatibility and ownership

### Default command composition

- Default observation root: `<resolved-workspace-parent>/observations`. This stays
  outside the fresh/retained workspace and matches the existing example layout.
  Require an existing workspace parent, as the existing lock/workspace APIs do;
  failure before allocation has diagnostics but no invented attempt identity.
- Keep `--observation-store ROOT` as an override. Add mutually exclusive
  `--no-observation` as the explicit legacy escape hatch. Default both fresh and
  resumed CLI stage attempts to observation; a resume gets a new stream and does
  not reopen the source attempt. Standalone adapter/runner APIs remain explicit.
- Retain schema-1 record grammar and existing `Writer.run`/runner sequencing.
  Allocation names the attempt and stream; terminal success/failure/interruption
  output identifies recorded facts and execution path when actually published.
  Do not advertise an execution file that failed to publish.
- Default machine `stages` output changes from one object to allocation/terminal
  JSONL. Declare **CLI contract 4**, update identity JSON-lines/capability metadata,
  docs and parsing callers, and review consumer gates before any later refresh.
  Persisted journal/checkpoint/execution schemas and old readers remain compatible.
  Define/test the caught-error/interruption envelope, including allocation failure;
  no successful result is fabricated to force exactly two lines after abrupt exit.
- Stage completion is not acceptance. Keep terminal stage streams immutable and
  finalization receipts separate. A finalization-watch feature or new durable result
  link event would need its own later contract, not a casual schema-1 extension.

### Foreground watch

Delivered public command (slice 2):

```sh
hardcaml-asic-flow observation watch ATTEMPT
hardcaml-asic-flow observation watch ATTEMPT --stream-id ID --after CURSOR --json
```

- Without a supplied stream/cursor, validate from allocation and follow from zero.
  For reconnect, require stream and cursor together, preserving `RESET_REQUIRED`
  semantics. Document a positive finite polling interval, default 0.5 seconds.
- Keep `inspect` and stateless `read_updates` payloads unchanged. Introduce an
  in-process incremental reader in `flow_observation.py`, sharing strict record
  validation/reduction with `load`; no reader state file, ack, lock ownership,
  catalog, daemon, repair or executor takeover.
- Validate the complete retained prefix once on attachment. Cache reduced state,
  last sequence/hash and file identities; subsequent polls validate/reduce only
  newly promoted records. Detect gaps, prefix deletion/replacement/change and stream
  mismatch; fail closed rather than resetting silently. Metadata checks on cached
  files are acceptable for this bounded local immutable-by-convention contract;
  do not claim hostile-owner tamper protection. Cold reconnect fully validates.
- Poll in-process, without repeatedly spawning the CLI or rereading full JSON.
  Prove no old record content is reparsed on idle polls. Check liveness even when
  no event arrives. When the activity lock is no longer held, drain/recheck the
  committed tail before concluding writer loss: final publication may race a poll.
- Human watch prints each delivered event chronologically, without the existing
  20-event summary elision. Machine watch emits flushed JSONL envelopes explicitly
  identified as reader delivery: `updates` with unchanged complete read-updates
  fields, and `status` with stream/cursor, writer activity, observation status,
  recorded outcome and derived final-results summary. These envelopes are a new
  CLI delivery protocol, not appended journal events. Suppress duplicate idle
  status; each updates envelope's cursor advances only across all delivered events.
- Emit a final status and stop on a recorded outer outcome, or on unresolved writer
  loss/unknown activity. Proposed reader exit codes: 0 for any recorded terminal
  outcome (same query semantics as inspect), 3 for lost/unknown without outcome,
   2 for record/cursor/query errors (also broken reader stdout), 130 for reader Ctrl-C. Record execution's exit
  code in output; never confuse it with the reader exit code.
- Reader disconnection, Ctrl-C, broken stdout or a slow reader affects only that
  foreground reader. It sends no execution signal and holds no execution lock.
  Reconnect delivery is cursor-based; callers persist their own cursor after
  processing. No exactly-once/idempotency promise is added.

### Ordinary example run and optional Classic coverage

Recommended consumer route: `project run --endpoint synthesis|floorplan|placement|
cts|routing|signoff`, mutually exclusive with existing `--stage`. Resolve tool paths
using the existing precedence and interpreter anchoring. Pass endpoint, a new
nonexistent uniquely named workspace under results, its checkpoint store, and
results/observations to installed `stages`. Selecting a unique workspace must not
precreate that workspace, because `stages.prepare` owns its creation. Reject
unsupported native/Classic-only flags before emission; forward human/JSON and
exit/signal behavior. Recipe files, consumer checkpoint continuation and acceptance
automation are not needed for this first usable route.

Schema 1 **cannot cover Classic unchanged**: its reducer requires `StagePlan`,
`implementation.boundary` identities, completed predecessors, successful checkpoint
publication before completion, no best-effort flag and no verdict. Classic has
coarse Plan actions, disabled/skipped actions, best-effort collection, report
accepted/rejected verdicts and no segment checkpoints. Inventing physical stages
or checkpoint publications would be false. If requested, a separate coarse
observation adapter must reuse `runner`/`phase4` lifecycle and retained run facts,
declare its own versioned grammar and inspect/watch projection, and test direct
`run` versus composed `execute` allocation and failure semantics. It is a separate
bounded feature, not required for the recommended explicit-stage route.

Out of scope: Workbench app/provider adapter, cancellation control service,
store-wide discovery/subscriptions/catalog/fencing/idempotency, fsync/power loss,
writer takeover/execution restart recovery, GC/archive/relocation, new stage
capabilities, backend-step events and re-running full physical/external acceptance.

## Sequential implementation assignments

Use **one general agent at a time, with no subagents**. The parent coordinates and
makes only small documentation edits. Each assignment completes and reports before
the next begins; these are future slices, not agents spawned by this audit.

1. **Default provider journal and protocol.** Change `cli.py` stages parser/branch,
   `identity.py`, presentation helpers as needed, and narrow `flow_observation.py`
   lifecycle handling only where evidenced. Preserve `runner.py`, `stages.py`,
   `phase4.py`, `result_store.py` execution semantics; changes there require a
   demonstrated journal boundary defect. Add meaningful default/override/opt-out,
   JSONL allocation-before-preflight and interrupted/error protocol regressions.
   Update provider guides and machine clients. Report contract-4 consumer blocker
   explicitly until slice 3 resolves it.
2. **Incremental reader and foreground watch.** Shared validator/cached reader in
   `flow_observation.py`; watch parser/loop in `cli.py` with separated presentation.
   Add focused subprocess reconnect/signal/liveness/storage tests and idle-read
   work-count assertions. Update describe/capability/CLI metadata and watch guide.
   Keep persisted schema 1 unchanged. Update `flow/dune` only if a new installed
   module is actually introduced; update `test/dune` and installed-prefix coverage.
3. **Sequential integration and consumer adoption.** Review both slices, implement
   the parent-approved ordinary run route in example `bin/project.ml`, update exact
   version gates in consumer dependency tooling/routing/setup tests, and document
   the route. Validate a fresh installed prefix before refreshing the private
   consumer installation; activation/refresh is later implementation work. Prove
   retained real reads plus a cheap new synthesis (or floorplan) attempt and watch
   reconnection. Reconcile this proposal with actual evidence and limits.

Preserve all tracked/untracked work. Never git add/commit/amend/push or add AI Git
attribution. Read-only Git is allowed. Every Dune build/test/exec/install invocation,
including wrappers and nested helpers, must include `-j20` (or `-j 20`).

## Evidence and verification plan

### Read-only evidence actually checked in this audit

After sourcing the current example activation script, installed `--version --json`
and human `observation inspect` succeeded for:

```text
/home/wayne/devel/jane/hardcaml_asic_example/_flow_results/observations/20261013T162352616479Z_f0ae62fe
stream f0ae62fea389408a809fe3be8486c7dc; cursor 13
```

It records synthesis/floorplan/placement completed in 4.633/4.447/10.882 seconds,
outer completed exit 0, inactive writer, final observation; physical completion is
`not_recorded` and acceptance/postcheck are `not_evaluated`. Read-updates after 9
returned exactly placement started/published/finished then outcome; after 13 with
`--json` returned no events and cursor 13. A first read with an incorrect full
stream ID returned `RESET_REQUIRED`, exit 2; retry with the inspector's actual
identity succeeded. Directory-name suffix is not the full stream identity.

Installed `checkpoint-inspect` of retained placement `placement-szaicr8h` with
`--restart-to cts` passed host-only validation: 14 checkpoint files, 1509 external
dependencies (1508 host, 1 image-only), 118 available and 6 unavailable metrics.
No execution or runtime validation was performed. Curated earlier real evidence
`evidence/librelane-observation/slice5-observed.json` records the separate ten-event
production synthesis/floorplan journal; slice 4 physical and slice 6 finalization
records remain historical evidence, not newly rerun verification.

Audit commands were public read-only provider queries. This audit makes no new
whole-tree hash-equality claim; the earlier human-output closeout records its own
531-file before/after check. No tests or Dune commands were run in this slice.

### Required implementation checks

- Default/root override/opt-out, fresh and resumed streams, workspace contention,
  invalid plan/preflight/publication/final aggregate/storage failures, and exact
  human versus complete JSONL with flushed allocation and terminal output.
- Incremental validation parity with cold replay; corruption/gap/replacement/
  deletion, wrong stream and bad cursors; hidden temporary tail; live idle polls
  parse no old record contents; simultaneous final append/lock release is drained.
- Independent watcher disconnect/reconnect at saved cursor; SIGTERM during long
  preparation/stage and after publication; SIGKILL retains unresolved running facts
  and historical artifact. Watcher Ctrl-C/broken pipe leaves producer alive and
  able to finish; lost/unknown activity cannot imply cleanup or completion.
- Installed CLI human/JSON flag placements, metadata and old retained schema-1
  inspect/read behavior; ordinary consumer routing, path precedence, version refusal
  before emission, valid explicit-stage forwarding and rejected mixed modes.
- Targeted provider Dune aliases: `@test/flow-observation`, `@test/stage-checkpoint`,
  `@test/coarse-runner`, `@test/result-store`, `@test/flow-cli`, inspector/related
  presentation and new watch alias if added, plus `@install`, all with `-j20`.
  Run installed-prefix tests separately; inspect their nested Dune bounds first.
  Consumer routing/setup checks use the same job bound wherever they invoke Dune.
- Read retained example journal/checkpoint through source and installed APIs/CLI;
  compare complete payloads and hash retained files before/after. No new EDA is
  needed for those compatibility checks.
- For new live evidence, use the existing example bundle/tools/exact image in a
  unique new workspace. A synthesis endpoint is sufficient to prove automatic
  allocation, watch/read reconnection, validated publication, terminal output and
  persisted results; floorplan is an optional cheap two-stage ordering proof.
  Use the ordinary run route once delivered (`dune exec -j20 ... -- run --endpoint
  synthesis ...`). Record exact command/paths/stream/cursors/events/exit codes and
  cleanup references. Existing longer physical/acceptance evidence suffices for
  unchanged backend semantics. Do not refresh/provision or run EDA in this audit.

Implementation evidence for all three approved slices is recorded below. Their
handoffs describe the historical state at each slice, superseded by the final
independent review and closeout at the end of this record.

## Slice 1 — default provider journal and protocol, 2026-10-13

Delivered by one sequential general agent; no delegation, EDA, staging, commits or
sibling refresh. The existing untracked scope document was retained and extended.

### Delivered command and storage contract

`stages` now allocates Writer by default before recipe/checkpoint validation or
preflight, for fresh and resumed invocations. Root is
`<resolved-workspace-parent>/observations`; the parent must already exist.
`--observation-store ROOT` overrides the root; mutually exclusive
`--no-observation` retains explicit unobserved behavior and one execution JSON
object when execution returns. Each resume gets a new stream. Independent adapter,
runner and Writer APIs remain explicit, with no implicit API store selection.

Identity advertises CLI contract **4**, default human output, `stages` in
`json_lines_commands`, the default stage root/opt-out, flushed machine records and
the terminal error event. Package version and persisted journal schema 1, plan
schemas 2/3, execution/checkpoint/finalization formats are unchanged. Classic does
not use the stage journal.

Normal `stages --json` delivery is flushed allocation (`contract`,
`schema_version: 1`, `event: observation_allocated`, `stream_id`, absolute `attempt`)
then the complete existing execution object. Execution JSON is atomically published
at `<workspace>/execution-<attempt_id>.json` before journal outcome, preserving
publication-before-event and successful payload compatibility.

Caught errors/interruption deliver a flushed `observation_terminal` envelope with
`contract`, `schema_version`, `status`, `exit_code`, `attempt`, `stream_id`,
`execution_file`, complete `observation` inspector payload, `recording_error`, and
`error: {code, detail}`. Error codes include `BUSY`, `INTERRUPTED`,
`EXECUTION_FAILED` and existing observation errors. Failure exits 2; interruption
exits 130/143 for SIGINT/SIGTERM. Identity/paths/observation are null when Writer
allocation did not succeed; execution_file is non-null only after actual successful
publication. A result that published before an outcome-write failure is therefore
referenced truthfully. Parser failures remain argparse diagnostics.

Signal handlers now bracket the whole CLI-owned lifecycle, including allocation
and receipt/terminal delivery. Constructor failure releases locks; receipt failure
records an outcome when possible; terminal diagnostics release Writer before
inspection. Broken output releases ownership and returns 2 without a second stdout
flush changing exit status. Storage errors may leave a committed prefix with no
outcome; no attempt/result is fabricated. Abrupt exit/broken output cannot guarantee
two lines. A completed journal outcome can coexist with terminal delivery failure;
the command's delivery status and recorded execution facts remain distinct.

### Tests and installed/retained evidence

New `test/test_default_journal.py` / `@test/default-journal` has 10 focused tests:
default/override/resume identities and complete output, preflight/invalid plan,
allocation storage failure/missing parent, contention across roots and opt-out,
aggregate/journal/outcome publication failures, real SIGTERM during preparation,
receipt and allocation, real SIGINT during preparation, explicit terminal flush and
handler restoration, and real broken allocation/terminal pipes with lock release.
Existing observation signal/publication tests remain unchanged and passing.
Legacy unobserved presentation testing explicitly selects `--no-observation`.
Presentation error assertions and packaging/installed metadata gates use contract 4.
Installed-prefix tests run the new lifecycle suite from isolated installed modules
and prove public CLI default allocation, not just the explicit override.

Passed sequentially:

```sh
dune build -j20 @test/default-journal @test/flow-observation \
  @test/stage-checkpoint @test/coarse-runner @test/result-store @test/flow-cli \
  @test/inspector-presentation @test/related-presentation @install
dune install -j20 --prefix /tmp/opencode/flow-journal-slice1-prefix hardcaml_asic
python3 -B test/test_packaging.py
python3 -B test/test_installed_prefix.py
python3 -B /tmp/opencode/check-flow-journal-slice1-retained.py
```

Targeted suites: 10 default journal, 16 observation, 30 stage/checkpoint, 11 coarse
runner, 18 result store, 43 flow CLI, 11 inspector and 8 related presentation tests.
Packaging: 17 tests. Fresh installed-prefix suite: 54 tests, including isolated
stage/observation/default-journal suites; nested build/install invocations use
`-j 20`. No live external EDA was needed.

Source and fresh installed CLI/API read the retained schema-1 attempt
`../hardcaml_asic_example/_flow_results/observations/20261013T162352616479Z_f0ae62fe`
identically: stream `f0ae62fea389408a809fe3be8486c7dc`, cursor 13; after 9 gives
`started`, `published`, `finished`, `outcome`. Host-only placement checkpoint
validation for restart to cts also matched complete source/installed manifests at
`../hardcaml_asic_example/_flow_results/placement-20261013T162305/checkpoints/placement-szaicr8h`.
All 30 files in the retained attempt/checkpoint trees had equal before/after SHA256
hashes. This is a bounded read-only compatibility check, not whole-tree evidence.

### Next-agent handoff and consumer migration blocker

Slice 2 should implement shared strict incremental validation and foreground
`observation watch` as described above, preserving schema-1 grammar, read-updates
payloads, publication ordering and these allocation/terminal regressions. No daemon
or watch was introduced in slice 1. Record writer loss without inventing interruption
or cleanup, drain final append/lock-release races, and prove idle polls reparse no
old content. Add watch installed-prefix gates.

**Contract-4 consumer migration is required before refresh:** example
`bin/project.ml`, `scripts/asic_dependency.py` and their routing/dependency/setup
tests currently gate contracts 2/3. Slice 3 owns that migration plus the ordinary
`project run --endpoint` route and final refresh/activation. Provider slice 1
does not update or refresh the sibling. Current `project run --stage` remains
Classic and does not acquire this journal merely by installing contract 4.

## Slice 2 — incremental reader and foreground watch, 2026-10-13

Implemented by one sequential general agent without subagents. All pre-existing
tracked/untracked slice-1 work was retained. No staging, commits, amendment, push,
Git attribution, external EDA or sibling installation refresh was performed.

### Delivered API, validation and ownership

`flow_observation.IncrementalReader(directory, *, stream_id=None, after=None)`
validates the complete existing prefix on construction. Either omit both reconnect
arguments (delivery after zero) or supply both. Stream must equal the allocation's
full 32-character lowercase identity; cursor must be an integer in `[0, head]`.
Wrong stream, missing counterpart or out-of-range/noninteger API cursor raises
`ObservationError("RESET_REQUIRED", ...)`. CLI noninteger syntax is argparse exit 2.
A head cursor is valid and can deliver status with no updates.

`reader.poll()` returns `(updates, status)` without CLI `event` discriminators.
Updates always has the unchanged stateless read-updates fields, including empty
`events`; its `after` is the initial supplied cursor or previous poll's cursor.
Poll advances the in-process delivery cursor only over the complete returned
suffix. Callers decide when to persist a cursor after processing, and must discard
a reader that failed validation. A cold reconnect fully validates the prefix again.

`validate_record(value, *, sequence, stream, previous, state)` now provides the
shared strict record/chain/transition validation used by `load` and the incremental
reader; `reduce_event` and schema-1 grammar are unchanged. `load`, `inspect` and
stateless `read_updates` retain their payloads and full-prefix validation.
`observation_snapshot(state, cursor, active)` shares inspect/result reduction with
the incremental status projection. Writer publication/execution semantics remain
those delivered in slice 1.

Warm polls list promoted numeric JSON records, check exact contiguous names, and
stat all cached records; only newly promoted content is read, JSON parsed, hashed
and reduced. File fingerprints are `(st_dev, st_ino, st_size, st_mtime_ns,
st_ctime_ns)` from lstat; regular non-symlink records are required. Deletion,
metadata change and replacement fail closed, as do promoted truncation, gaps,
duplicate/nonfinite JSON, hash/stream/transition corruption. Metadata is checked
before/after each new content read. Hidden temporary tails are ignored.

Liveness is checked even when idle. If the attempt activity lock is inactive or
unknown, the reader refreshes/drains the committed tail **after** that check before
concluding writer loss. A final publication between the first listing and lock
release therefore wins over unresolved-loss status. This is the existing read-only
best-effort activity probe, not acquisition of the executor's workspace lock.
No provider subprocess, daemon, state file, journal write, acknowledgement, repair,
execution signal or ownership takeover is introduced. Reader Ctrl-C, disconnection,
broken output and slow consumption affect only the reader.

### CLI delivery protocol and capabilities

```sh
hardcaml-asic-flow observation watch ATTEMPT
hardcaml-asic-flow observation watch ATTEMPT --interval 0.5 --json
hardcaml-asic-flow observation watch ATTEMPT --stream-id ID --after CURSOR --json
```

`--interval` accepts only positive finite seconds; default is **0.5**. Global,
observation-level and watch-level `--json` placements all work, before/after path
where argparse allows. Every machine envelope is one complete flushed JSONL
object; stdout has no diagnostics. Exact envelope fields:

| Event | Top-level fields |
| --- | --- |
| `updates` | `event`, `contract`, `schema_version`, `stream_id`, `after`, `cursor`, `events` |
| `status` | `event`, `contract`, `schema_version`, `stream_id`, `cursor`, `writer_active`, `observation_status`, `outcome`, `final_results` |

`contract` remains `hardcaml-asic.stage-observation`, `schema_version` remains 1.
An updates envelope is the full unchanged `read_updates` response with
`event: "updates"`: complete records and hashes, strictly after its `after`,
with `cursor` covering every delivered event. Empty updates are suppressed by CLI.
A status envelope has `event: "status"`; activity is true/false/null;
observation status is `live`, `final`, or `writer_lost_or_unknown`; `outcome` is
null or the recorded `{status, exit_code, error}` object. `final_results` is exactly
the inspector's `{physical_completion, checkpoint_refs, acceptance,
external_postcheck}` summary, with acceptance/postcheck still `not_evaluated`.
These are delivery envelopes, not persisted journal events.

The reader emits initial status, changed status and final status before stopping;
identical idle statuses are suppressed. Human updates reuse the renderer with
elision disabled, displaying every event chronologically plus publication paths
and errors. Human status labels execution exit code separately from reader status
and shows physical/acceptance/postcheck summary and recorded checkpoint paths.

| Reader exit | Meaning |
| --- | --- |
| 0 | Any recorded terminal outcome, including failed/interrupted execution |
| 3 | No outcome and inactive/unknown writer after final-tail drain |
| 2 | Corruption/cursor/query errors or broken stdout |
| 130 | Reader Ctrl-C |

The recorded execution exit code is `status.outcome.exit_code`, never the reader
query verdict. Record/cursor errors retain the existing
`{contract, schema_version, error: {code, detail}}` query envelope and stderr
diagnostic. Broken stdout returns 2 without a full traceback or interpreter
shutdown-flush diagnostic. Parser errors remain argparse diagnostics.

`observation describe --json` advertises `watch` and `incremental_reader`, exact
envelope schemas, interval/reconnect/idle/release/fingerprint policies and exits.
Identity remains CLI contract **4** and advertises `observation watch` in both
`json_commands` and `json_lines_commands`, plus the incremental/flushed envelope,
interval, reconnect and exit capabilities. No package/schema bump or new installed
module was needed; `flow/dune` is unchanged.

### Tests and retained/installed evidence

New `test/test_observation_watch.py` / `@test/observation-watch`: **10 tests** cover
idle content-read counts and liveness checks; parity with stateless payloads;
changed/deleted/byte-identical replaced prefix; hidden temporary, gapped, truncated,
duplicate-key, nonfinite and hash-corrupt records; cursor pairing/reset;
deterministic append-at-lock-release race; finite interval rejection; terminal
failed query exit 0; human delivery of all **22** six-stage events; query errors;
and concurrent subprocess producers/readers. The concurrent test proves flushed
allocation delivery, reader SIGINT exit 130 while producer stays alive, broken pipe
exit 2 without traceback while producer stays alive, reconnect after cursor 1,
duplicate-idle-status suppression, terminal suffix and successful query of execution
exit 9, plus SIGKILL producer loss observed as exit 3 with null outcome.

Installed-prefix coverage runs the new suite using isolated installed modules,
checks the actual installed launcher at all three JSON flag placements, compares
complete update payloads to stateless reads, and verifies human terminal output
and describe capabilities. Existing signal/publication/default-journal regression
tests remain passing.

Commands completed sequentially (every direct/nested Dune command uses `-j20` or
`-j 20`):

```sh
dune build -j20 @test/observation-watch
dune build -j20 @test/observation-watch @test/default-journal \
  @test/flow-observation @test/stage-checkpoint @test/coarse-runner \
  @test/result-store @test/flow-cli @test/inspector-presentation \
  @test/related-presentation @install
python3 -B test/test_packaging.py
python3 -B test/test_installed_prefix.py
dune install -j20 --prefix /tmp/opencode/flow-journal-slice2-prefix hardcaml_asic
python3 -B /tmp/opencode/check-flow-journal-slice2-retained.py
# After adding abrupt-producer-loss/corruption assertions and checkpoint status text:
dune build -j20 @test/observation-watch @test/inspector-presentation \
  @test/related-presentation @install
python3 -B test/test_installed_prefix.py
dune install -j20 --prefix /tmp/opencode/flow-journal-slice2-prefix hardcaml_asic
python3 -B /tmp/opencode/check-flow-journal-slice2-retained.py
git diff --check
```

All passed: 10 watch, 10 default journal, 16 observation, 30 stage/checkpoint,
11 coarse runner, 18 result store, 43 flow CLI, 11 inspector presentation,
8 related presentation; packaging **17**, fresh installed-prefix **55**.

The actual retained placement attempt
`../hardcaml_asic_example/_flow_results/observations/20261013T162352616479Z_f0ae62fe`
was read through source and fresh installed API/CLI, including human/JSON watch.
Stream `f0ae62fea389408a809fe3be8486c7dc`, head 13, outer completed exit 0.
Full watches delivered 13 records then final status identically; reconnect after 9
delivered `started`, `published`, `finished`, `outcome`; reconnect at 13 delivered
only final status. Existing inspect/read-updates complete payloads and host-only
placement checkpoint restart-to-cts manifest also matched. SHA256 hashes of all
**30** retained journal/checkpoint files were unchanged before/after the bounded
read-only check. No external EDA was run or needed.

### Limits and next consumer-agent handoff

This reader optimizes content work, not all filesystem work: each poll still
lists/stats O(prefix length), and cached events/state occupy memory. Fingerprints
rely on a trusted local immutable-record convention; they are not hostile-owner
tamper protection. Atomic promotion is not fsync/power-loss durability. Liveness
is best-effort advisory-lock evidence, without heartbeats or cleanup inference.
Cursor delivery has no ack or exactly-once guarantee. No store-wide discovery,
backend-step progress, executor recovery/takeover, relocation or finalization watch.

Changed files in this slice: `flow/hardcaml_asic_flow/{flow_observation,cli,identity,
presentation}.py`, `test/{test_observation_watch.py,test_installed_prefix.py,dune}`,
`docs/guides/{flow,stage-quickstart,ocaml-stage-recipes}.md`, and this feature record.

Slice 3 should review both provider slices, migrate example exact contract gates
(`bin/project.ml`, `scripts/asic_dependency.py`, routing/dependency/setup tests) to
contract 4 **before refresh**, and implement the selected mutually exclusive
ordinary `project run --endpoint` explicit-stage route. Preserve Classic `--stage`
semantics, default journaling and allocation/terminal JSONL. Parse watch as reader
updates/status rather than an execution verdict; persist stream/cursor after the
entire updates envelope. Use a fresh installed prefix first, then perform the final
approved consumer installation refresh/activation and cheap synthesis live evidence
with reconnection. All Dune calls including nested helpers require `-j20`.
The example installation has not been refreshed in this slice; current contract-2/3
consumer gates remain the integration blocker. Full feature completion still needs
slice 3.

## Slice 3 — consumer integration and real evidence, 2026-10-13

One sequential general agent, no subagents. Preserved the provider's existing
tracked/untracked work and all consumer work. No repository staging, commits,
amendment, push or attribution. All direct/nested Dune operations used `-j20` or
`-j 20`; private refresh did not change the dependency record or global opam package.

### Ordinary route and compatibility

```sh
# From hardcaml_asic_example, after activation and with existing tools:
. .dev/asic/current/activate.sh
dune exec -j 20 bin/project.exe -- run --endpoint synthesis --json
```

`--endpoint synthesis|floorplan|placement|cts|routing|signoff` is mutually exclusive
with existing Classic `--stage synthesis|full`. Classic dispatch remains `run`,
with its existing flags/path resolution. Endpoints exec installed `stages`, after
emitting/reusing the bundle (or directly using explicit `--bundle`). They resolve
source/results/tool roots using existing precedence and anchor Python without
canonicalizing venv/symlink aliases. Required stage tool arguments use explicit
per-tool overrides or the selected tool root's `tt`, `pdk`, `.venv/bin/python`.

Each endpoint request creates only the results parent when necessary and selects
a nonexistent workspace name there (endpoint, process ID and randomized suffix).
It does not precreate the workspace: preparation owns creation. Checkpoints are
inside it. No observation override is forwarded, so the provider selects resolved
results/`observations` outside the workspace. Human default and complete `--json`
allocation/terminal output flow directly through exec, including exits/signals.
`--native`, `--runs`, mixed modes, invalid endpoints and unknown options fail before
provider dispatch or bundle emission. Recipe/resume routing was not added.

Consumer project/dependency gates now accept exactly integer **2/3/4** for existing
Classic-compatible operations; endpoints require **4**. Unknown future versions,
strings, booleans, floats and null fail before emission/publication. Routing tests
cover all six endpoints, human/complete two-record JSONL forwarding, same-endpoint
workspace uniqueness/non-precreation, default/explicit results, paths with spaces,
tool precedence/overrides, explicit bundle with missing source input proving no
re-emission, conflicts/errors-before-emission and preserved exit/signal behavior.
Dependency setup tests cover contract 4 and refusal preserving existing selection.

### Verification and private generation

Passed:

```sh
# Initial consumer checks against the previous compatible library installation:
. .dev/asic/current/activate.sh
dune runtest . -j20
# Provider fresh isolated installed command/API/reader checks, before refresh:
python3 -B test/test_installed_prefix.py
# From consumer (build/install/link probe internally all -j 20):
python3 -B scripts/asic_dependency.py refresh \
  --source /home/wayne/devel/jane/hardcaml_asic --mode development
. .dev/asic/current/activate.sh
dune runtest . -j20
python3 -B scripts/asic_dependency.py status --json
ocamlfind query hardcaml_asic
# External capture/check scripts run in that activated consumer shell:
python3 -B /tmp/opencode/flow-journal-slice3-live.py
python3 -B /tmp/opencode/flow-journal-slice3-retained.py
python3 -B /tmp/opencode/flow-journal-slice3-check-evidence.py
# Both repositories:
git diff --check
```

Consumer: **14 routing**, **18 dependency setup**, declaration checks, existing
bundle and RTL acceptance (11,429 edges; negative oracle checks). Installed-prefix:
**55 tests**, including installed default journal and incremental watch lifecycle
suites. The post-refresh exact consumer runtest succeeded; unaffected setup aliases
were cached on that invocation. No acceptance flow was replaced or silently altered.

Published/activated generation **`f4c4ae2efeec4e34951102587149f4bc`**:
observed provider base `31ad2441ac12ce57123a1f37ed5e2bbf5f508d6c`, captured snapshot
SHA256 `33468cfda8fb0845310df2ab7409495b324939cf3a51026d5592f3c9fe8f84da`.
Status confirmed `active_is_published` and `active_library_path_is_first`; ocamlfind
selected that generation's library. CLI reports contract 4, package 0.1.0, unstamped.
Recorded pin remains **`1714764859274f80a9f5ad207421a04601824e99`**. Receipt describes
captured dirty bytes, not an atomic/clean source snapshot or release stamp. This
section and curated evidence were added after capture; no executable provider code
changed after refresh. Re-source `.dev/asic/current/activate.sh` in each user shell.

### Actual single cheap synthesis and stopped/reconnected watch

Curated evidence: [flow-journal-slice3.json](../../evidence/librelane-observation/flow-journal-slice3.json).
Actual full output, source hash manifests, installed identity/receipt/activation,
human inspection, raw watch/producer JSONL and SHA256 manifest are external at
`/tmp/opencode/flow-journal-slice3-live`. The workspaces/bundle/journal remain in the
consumer's ignored `_flow_results`. Capture ran exactly **one** real ordinary
`dune exec -j 20 bin/project.exe -- run --endpoint synthesis --json`; no tool-script
modification, extra EDA request or full physical/acceptance rerun.

- Attempt: `../hardcaml_asic_example/_flow_results/observations/20261013T184318828201Z_45fec45f`.
- Full stream: **`45fec45f50b5498192de35d79423b9b8`**, head **7**.
- Workspace: `../hardcaml_asic_example/_flow_results/synthesis-969831-090ea6d20023f853048209ef3e81fcff`.
- Bundle: `_flow_results/bundles/c64e88d8894c7b5c7b5d19267a462eff0dc0c32bd2c1eecf15771da8fdd6b2db`.
- Execution: workspace/`execution-45fec45f50b5498192de35d79423b9b8.json`.
- Synthesis checkpoint: workspace/`checkpoints/synthesis-umwhryio`, identity
  `99475d0a248187eb520e8dc2869e8f7150a6e887bd4085952d84ca60112f549a`.

Producer flushed allocation before preparation. Installed watch attached while
preparing: initial prefix `allocated, planned`, cursor **2**, active writer, null
outcome. Reader SIGINT returned **130**; producer was still alive before and after
reader termination. Reconnect with the full stream and `--after 2` returned exactly
`prepared, started, published, finished, outcome`, matching the stateless suffix.
Reader exit **0**, final inactive writer and completed execution exit **0**. Head
reconnect `--after 7` delivered only final status. This used real existing preflight
timing, without artificially delaying/modifying tools.

Seven-event chain validated; last hash
`1711195f6356b5c63a1db699f6e3dc52404f47984dfee6ce4ddf87c5f4f40893`.
Terminal stdout exactly equals persisted execution JSON. Final watch outcome/results
equal inspection. Synthesis duration **4.704859s**; preflight ready; exact image
`sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a`.
Transport `transport-c6a868b7d3834fb185c1ac616fb13115.json` records two
`removed-or-absent` cleanup results. Installed checkpoint inspector successfully
validated host closure for restart to floorplan and matched the recorded identity.
Full physical completion is `not_recorded`; acceptance/postcheck are `not_evaluated`.

Before/after live-run hashes matched for **39 consumer source**, **271 provider
source** and **150 global opam package** files; pin equality checked separately.
These cover Git-listed tracked/nonignored untracked source files and the installed
package tree, not every file on disk. Evidence/docs were added after that bounded
check, so this is a live-command nonmutation claim, not final whole-tree equality.

Retained real placement attempt `20261013T162352616479Z_f0ae62fe` also matched source
and newly activated installed CLI/API inspect/watch/read-updates. Stream
`f0ae62fea389408a809fe3be8486c7dc`, head 13; after 9 returned exactly placement
started/published/finished and outcome. Host checkpoint restart-to-cts validation
matched; **30 retained journal/checkpoint files** had identical before/after SHA256.

### Independent review handoff

Changed consumer files: `bin/project.ml`, `scripts/{asic_dependency.py,
test_asic_dependency.py,test_project_routing.py}`, `README.md`,
`docs/dependency_commands.md`. Provider changes for slice 3: this record,
`docs/guides/stage-quickstart.md`, and curated `evidence/librelane-observation/flow-journal-slice3.json`.
All earlier provider changes remain present.

Parent should independently review consumer mode/contract gates, path/venv
resolution and workspace non-precreation, then reconcile final docs. Endpoints
beyond synthesis have recorder routing coverage and historical provider evidence,
not new real EDA coverage here. Explicit results/path-space routes have recorder
coverage; the actual EDA request used default results/tools. No Classic journal,
Workbench integration, recipe/resume consumer route or new acceptance run is claimed.

## Final independent review and closeout

2026-10-13: one sequential general agent, no subagents. Read workspace `AGENTS.md`,
this entire feature record (all slices), actual provider Writer/reducer/incremental
reader/CLI/presentation/identity, runner and preparation boundaries, consumer
`bin/project.ml`, private refresh gates and relevant tests. Existing dirty/untracked
work was preserved. No repository staging, commit, amendment, push or Git attribution
was performed. Recorded provider base revisions belong to existing owner history,
not commits made by this review.

### Review findings and consequential fix

- Cached-prefix validation checks every retained promoted filename and fingerprint;
  deletion, replacement, modification, gaps and malformed tails fail closed. Cold
  attachment validates all hashes/transitions; idle warm polls parse no old content.
  Terminal publication racing the first listing wins because inactive/unknown lock
  detection is followed by a second tail refresh before writer-loss status.
- Default allocation precedes recipe validation/preflight for fresh/resumed CLI
  stages. Scoped signals include allocation/receipt/terminal delivery; storage failure
  can leave unresolved committed facts. Publication-before-finish and execution
  aggregate-before-outcome remain truthful; no synthetic success/cleanup is inferred.
- Human watch delivers every chronological event; machine output is complete flushed
  reader `updates`/`status` JSONL. Its query exit 0 includes failed/interrupted recorded
  execution, and means neither physical success nor accepted flow. Inspect and
  stateless read-updates retain their existing schema-1 payloads.
- Consumer exact integer contract gates, endpoint/stage conflicts, Classic-only flags
  and malformed modes are rejected before emission. Endpoints require contract 4;
  Classic accepts 2/3/4. Relative paths/tool precedence and lexical interpreter
  anchoring are retained. The results parent may be created; the unique fresh
  workspace is deliberately not precreated. Provider default observations remain
  outside the workspace, and a directly supplied workspace parent must exist.
- **Fixed:** watch previously caught `BrokenPipeError`, but a different stdout
  `OSError` (for example ENOSPC) entered query-error reporting, retried the failed
  stdout and could escape with traceback/shutdown-flush failure. The local output
  boundary now classifies all stdout `OSError`s as reader delivery failure, redirects
  the failed descriptor where possible, and returns 2. Filesystem/query errors still
  use query envelopes. Real `/dev/full` subprocess regressions cover human and JSON
  delivery while independently proving the producer remains alive; existing pipe,
  Ctrl-C, reconnect and producer-loss tests also passed. No execution or journal
  writer semantics changed, so the recorded real EDA/watch evidence remains valid.

### Exact final validation and installed generation

All commands below passed, sequentially. Every direct/nested Dune build/test/install
used `-j20` or `-j 20`; installed-prefix and refresh wrappers were inspected first.

```sh
# Provider root:
dune runtest -j 20 --force
python3 -B test/test_installed_prefix.py
# Example root; one production-code refresh after the fix/tests settled:
python3 -B scripts/asic_dependency.py refresh \
  --source /home/wayne/devel/jane/hardcaml_asic --mode development
. .dev/asic/current/activate.sh
dune runtest . -j20
python3 -B scripts/test_project_routing.py \
  _build/default/bin/project.exe _build/default/acceptance/export_trace.exe .
python3 -B scripts/test_asic_dependency.py
python3 -B /tmp/opencode/flow-journal-final-review.py
python3 -B scripts/asic_dependency.py status --json
ocamlfind query hardcaml_asic
# Provider docs: added/feature local destinations and available Markdown anchors:
python3 -B /tmp/opencode/check-flow-journal-final-links.py
# Each repository:
git diff --check
```

Forced provider scope: OCaml inline/bundle/RTL checks, recipe agreement (**36 accepted,
1,819 rejected**), and Python suites: watch 10, default journal 10, observation 16,
stage/checkpoint 30, finalization 15, coarse runner 11, flow CLI 43, result store 45,
inspector presentation 11, related presentation 8, runtime contract 8, runtime
observation 18, transport 10, phase4 26, report 15, archive 20, packaging 17,
managed Python 48, toolchain 25 and provisional observation fixtures 50.
Fresh isolated installed-prefix: **55 top-level tests**, including installed lifecycle,
watch and schema compatibility. Exact example `dune runtest . -j20` passed with cached
results; explicit fresh consumer routing **14** and dependency setup **18** passed.
This review did not newly rerun real EDA, full external acceptance or daemon supervision.
Documentation check: **27 local links/anchors across 14 documents** passed; both
repository whitespace checks passed. Final status retained every initial dirty/untracked
path and added only the reviewed documentation paths; no accidental work deletion.

Published/activated private generation: **`4c09a4b421c84782bc8916ede976ca02`**;
observed existing provider base `31ad2441ac12ce57123a1f37ed5e2bbf5f508d6c`, snapshot
SHA256 **`10e1c9d499013fbf7d6cc78e65ca6dc62b4467ae22c18e6fd36d804424a672c8`**.
Status verified `active_is_published` / `active_library_path_is_first`; ocamlfind
selected that generation. Installed CLI is contract 4 / 0.1.0 unstamped. Recorded pin
**`1714764859274f80a9f5ad207421a04601824e99`** is unchanged. All **150** global opam
package files match the slice-3 pre-run SHA256 manifest. The receipt describes captured
dirty bytes, not a clean release or atomic checkout; final documentation was reconciled
after capture. No further executable changes or refresh were needed.

Current source and activated installed API/CLI `inspect`, `read_updates`, human watch,
JSON reconnect and head-only watch matched for both retained schema-1 attempts:

| Attempt | Head / reconnect | Compared facts |
| --- | --- | --- |
| `20261013T184318828201Z_45fec45f` | 7 / after 2 | Recorded synthesis execution ID, occurrences, artifacts, status and exit match inspection; final watch outcome/results match; suffix is prepared/started/published/finished/outcome |
| `20261013T162352616479Z_f0ae62fe` | 13 / after 9 | Older placement execution agrees identically; suffix is started/published/finished/outcome |

The read-only helper verified all **9 + 15 attempt files** unchanged by SHA256 and
both saved execution JSON files byte-unchanged. This is bounded retained-read evidence,
not whole-tree equality. Slice-3 real synthesis/reader Ctrl-C/reconnect and historical
checkpoint/physical/acceptance evidence are preserved, not rewritten or rerun.

### Delivered boundary and remaining limits

Default journaling applies only to the explicit-stage CLI route, including example
`project run --endpoint`; Classic `--stage`/`run`/`execute` do not acquire it.
Independent APIs still require explicit composition. Reader delivery is separate from
writer execution: stopping/breaking a reader never signals or locks execution; an
execution command's own stdout failure can stop that owned command. No default
live progress is interleaved into execution stdout; use a separate watch.

The retained journal is a local trusted-owner, path-bound immutable-record convention.
Warm polls use O(prefix) listing/stat work and retain events/state in memory; metadata
fingerprints are not hostile-owner tamper protection. Advisory filesystem/flock
liveness is best-effort, with true/false/unknown activity, no heartbeat or proof that
tools/containers stopped. Final-tail drain resolves the normal writer-release race,
not arbitrary external mutation or unsupported filesystem behavior.
Atomic visibility/process-restart readability is **not fsync or power-loss durability**.
Caller owns retention and persisted cursors after processing complete updates;
no acknowledgements/exactly-once, catalog/subscriptions, relocation/GC, backend-step
events, execution takeover/recovery or finalization watch. **Future Workbench
cancellation is not implemented**, and no daemon-crash survival is claimed.
Checkpoint publication, endpoint completion, full physical completion, external
postcheck and acceptance remain separate; **reader exit 0 does not mean flow accepted**.

Review edits: `flow/hardcaml_asic_flow/cli.py`, `test/test_observation_watch.py`,
`docs/{README,architecture,phase_plan}.md`, `docs/development/{flow-journal,
workbench-execution-boundary,human-readable-flow-output,consumer-dependency-workflow,
explicit-stage-refactor,p6-implementation-plan}.md`,
and `docs/guides/{flow,stage-quickstart}.md`. Consumer source was reviewed without
further edits; its existing six changed files and all previous provider slice work
remain present. Current guides/index/architecture/plan point to the delivered contract;
the human-output document keeps its dated contract-3 evidence intact.
