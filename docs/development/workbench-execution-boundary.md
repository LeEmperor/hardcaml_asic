# ASIC execution, Workbench supervision, and interactive use

Discussion record: 2026-10-13. This records the architectural direction and user
preferences discussed after the explicit-stage implementation. Workbench integration
remains proposed. Human-default CLI rendering was subsequently delivered as
contract 3; see [completion evidence](human-readable-flow-output.md). The optional
journal and future-watch wording described that historical baseline. Contract 4
subsequently delivered default CLI-stage journaling and foreground incremental watch;
see [current feature closeout](flow-journal.md). Workbench cancellation and daemon
crash-survival behavior remain proposed, not supplied by the reader.

## Ownership boundary

`hardcaml_asic` remains usable from an ordinary terminal, without a daemon or
Workbench. The installed Python `hardcaml-asic-flow` command owns flow semantics,
backend invocation, checkpoint publication, and authoritative execution facts.
The OCaml library owns design declaration/elaboration, input emission, and typed
`Flow.Stage` / `Flow.Recipe` construction. There is not currently an OCaml
process-management/callback wrapper around physical execution.

Workbench should launch and supervise provider commands, follow their persisted
progress, and translate provider facts into its own live client notifications.
It must not reconstruct stage completion by parsing human console output or
implement a second version of ASIC sequencing and acceptance policy.

| Concern | Owner |
| --- | --- |
| Recipe, stage meanings, backend execution order | ASIC provider |
| Tool/container launch and cleanup | ASIC provider |
| Artifact validity, publication, measurements and acceptance | ASIC provider |
| Authoritative persisted stage lifecycle | ASIC provider |
| User job requests, command launch and process handles | Workbench when it launches the command |
| Forwarding cancellation and observing child exit | Workbench supervisor |
| UI subscriptions, notifications, presentation and rebuildable cache | Workbench |

An event sequence does not require a daemon. The distinction is between an
**ASIC execution journal** (persisted domain facts) and a **Workbench event
stream** (live delivery to clients, including Workbench-owned job/UI facts).
The default CLI-stage per-attempt observation journal is sufficient groundwork;
a larger service or event bus is not a prerequisite.

## Runs, attempts, and output locations

An explicit-stage execution through placement is conceptually a run, even though
the current Classic and segmented interfaces use different records:

- Classic `run`: run directory, `run.json`, collected `results.json`, `report`.
- Segmented `stages`: explicit workspace, execution-attempt JSON, published
  checkpoints, and default observation-attempt directory (`--no-observation` opts out).

Unifying user-facing run/report terminology is a desired follow-up, not a claim
that Classic `collect`/`report` accept segmented workspaces today. Keep an
observation `ATTEMPT` variable distinct from a Classic `RUN` variable.

The segmented caller supplies `--workspace`, `--checkpoint-store` (inside the
workspace), and optionally `--observation-store`.
The default observation root is `<resolved-workspace-parent>/observations`; the
workspace parent must exist. Example `project run --endpoint` creates only that
results parent and selects a unique nonexistent workspace; preparation creates it.
Classic `project run --stage` does not acquire the stage journal.

A typical consumer layout is:

```text
_flow_results/
  bundles/<identity>                  published input bundle
  <workspace>/
    project/                          staged inputs, bridge, backend working data
      candidates/                     not-yet-published outputs
    checkpoints/<boundary>-<id>/      validated handoffs
    execution-<attempt>.json          execution outcome and artifact references
    transport-<id>.json               binding and command records
    transport-<id>-preflight.json
    <segment>.log
  observations/<attempt>/             persisted lifecycle facts
  <finalization-operation-store>/     separately requested results/acceptance
```

The terminal JSON is not the only result: files and records are retained at these
explicit paths. Raw tool evidence, checkpoint state, execution outcome, progress
history, and final acceptance are distinct outputs. Checkpoints currently remain
path-bound to retained workspace/collateral; relocating or garbage-collecting
these roots is not supported by this contract.

The runner records stage start, invokes the backend, validates/publishes its
candidate, records publication, then records stage completion. Publication must
precede advertising readiness. Process completion, valid handoff, requested
endpoint completion, and full acceptance are different facts.

## Inspection and human output preference

The user prefers the existing `report` formatting: compact labeled fields,
stage/metric tables and explicit verdicts, rather than default JSON dumps.

Delivered presentation behavior (introduced in CLI contract 3, retained in 4):

```sh
hardcaml-asic-flow observation inspect "$ATTEMPT"          # human summary
hardcaml-asic-flow observation inspect "$ATTEMPT" --json   # machine representation
hardcaml-asic-flow observation watch "$ATTEMPT"           # foreground; reader Ctrl-C is safe
hardcaml-asic-flow observation watch "$ATTEMPT" --stream-id "$STREAM_ID" --after "$CURSOR" --json
hardcaml-asic-flow checkpoint-inspect "$PLACEMENT" --restart-to cts
hardcaml-asic-flow checkpoint-inspect "$PLACEMENT" --restart-to cts --json
```

At this discussion's historical baseline both inspectors emitted JSON by default.
Both now support these examples, including global and nested `--json` placement.
Machine clients/tests must explicitly request JSON; observed stages and finalize
retain flushed allocation and terminal JSONL. Rendering consumes existing results
without new probes or persisted-schema changes.

- `observation inspect` reconstructs recorded state, including the requested plan,
  actual stage outcomes, published references, cursor, and outer completion. It
  is not just a manifest of intended work. Historical publication does not prove
  that referenced artifacts remain intact today.
- `checkpoint-inspect` validates saved manifest/artifact integrity and host-side
  dependencies. It does not execute tools or establish engineering acceptance.
- `--restart-to cts` adds validation that CTS is a supported consumer of this
  checkpoint. It does not restart execution. Runtime/image-only dependencies are
  checked separately by the execution path.
- `stages --checkpoint ...` performs actual continuation.

Useful human summaries should distinguish requested-endpoint completion from
full physical completion, and label host-only versus runtime validation clearly.
Avoid displaying accumulated checkpoint metrics as newly measured at that stage
without producer evidence. Large external dependency/hash inventories belong in
explicit machine/detail output.

## Cancellation and supervision

Proposed initial interaction:

```text
browser cancel request
  -> Workbench daemon selects its owned job/process handle
  -> sends SIGTERM to the ASIC command
  -> ASIC interruption handling stops owned tools/containers
  -> ASIC records interruption and cleanup outcome, then exits
  -> Workbench observes process exit and reads persisted outcome
```

Existing provider code supports interruption handling and owned process/container
cleanup. Workbench cancellation integration and a public run-ID-based `cancel`
command are not delivered by that fact. Docker's daemon owns container processes
at the OS level: killing the CLI's process tree alone does not prove that its
container stopped, so explicit provider-owned container cleanup remains essential.

No extra listener thread/process is necessary for local signal-based cancellation.
OS signals already deliver the request to the running provider. Workbench should
first signal the provider, allowing cleanup and records, rather than directly
kill EDA children. Forced termination is an escalation after a defined grace
period and may prevent final recording. Exit/cleanup observations must remain
honest if descendants cannot be confirmed stopped.

Retain process handles for live owned jobs. A persisted PID alone is insufficient
authority after restart because PIDs can be reused. Process exit is a supervisor
fact; ASIC completion is a domain fact. A missing/stale terminal record must not
be converted into invented stage completion or proof that tools stopped.

A richer request channel (for example, a per-run local socket) is a possible
later feature if reattachment/control, remote execution, or multiple commands
justify it. It could be served by the running ASIC command without a permanent
ASIC daemon. Such a feature needs explicit addressing/ownership, request
acknowledgment, cancellation semantics and crash/stale-endpoint handling; it is
not required for the initial Cancel button. Pause/resume within a running EDA
tool is not implied by checkpoint-based continuation.

## Workbench failure and reconnection

Persisted progress survives loss of a reader; process survival is a separate
supervision decision. Workbench launch/session/service-manager behavior determines
whether a job survives the daemon exiting. Do not claim the journal guarantees it.

Recommended requirements:

- Closing a browser tab or losing a reader never cancels or blocks the flow.
- Workbench can inspect terminal-launched runs and reconnect to persisted facts.
- Daemon-crash process survival and reattachment/control are explicitly specified
  and tested before advertised.
- Foreground `watch` now offers streaming delivery without becoming the source of
  truth or requiring a daemon. It emits separate reader updates/status, validates
  the retained prefix, drains final publication after lock release, and supports
  stream/cursor reconnection. Reader exit 0 includes failed/interrupted execution;
  it is not acceptance. Reader Ctrl-C and stdout failure never signal the writer.

## Related implementation and remaining work

See [explicit-stage implementation record](explicit-stage-refactor.md),
[architecture](../architecture.md), [stage quickstart](../guides/stage-quickstart.md),
and [flow interfaces](../guides/flow.md).

Delivered: human-default inspectors and related segmented execution/finalization
presentation, default CLI-stage journaling and foreground watch with explicit
complete machine output. Local trusted immutable-record metadata and advisory-lock
liveness are best-effort filesystem assumptions, not hostile-owner protection.
Follow-ups: typed Workbench
provider adapter; supervised cancellation tests;
explicit daemon-failure behavior. Existing observation is per-attempt and does
not promise store-wide subscriptions/idempotency, execution recovery, writer
takeover, or fsync/power-loss durability.
