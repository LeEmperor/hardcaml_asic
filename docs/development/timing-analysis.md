# Terminal post-PNR timing observation (WB-069)

The CLI4 capability `timing_analysis1: true` advertises a versioned, additive
`timing_analysis` object in `hardcaml-asic.report` schema 1. The execution record,
backend reply and six physical execution stages are unchanged. This is a
supplementary observation, not a checkpoint, launch endpoint or acceptance result.

## Delivery and retention

`Stage_preparation.execute` collects after the Runner has persisted its terminal
execution, including nonzero exit, timeout and cancellation, and after transport
cleanup. Collection precedes the caller's observation outcome. It does not depend
on the bridge returning or handling a Python exception. A supplementary capture
failure is diagnosed on stderr and cannot replace the implementation outcome.

The immutable sidecar is `EXECUTION.json.timing-analysis.json`. Publication uses
a fresh temporary file and a no-replace hard link; an existing observation is
never overwritten. Readers do not publish, repair, rerun or harvest anything.
The sidecar contains the exact execution byte hash, attempt and signoff occurrence,
request ID/hash and an inventory of captured source path/hashes. Publication
rechecks all captured bytes. This is the existing trusted-local immutable-file
model, not authenticated storage or fsync durability.

The launcher records the exact `project/src/runs/<request.tag>` path as
`fresh_run_dir` only if absent before invocation. The collector accepts that exact
run under the supported image, rejects symlinks and duplicate post-PNR producers,
and validates the numbered producer's metadata. It does not search for a newest
run. Legacy transport records without this freshness evidence cannot earn timing
completion.

Only recipes requesting signoff publish this extension. Missing extension means
no terminal observation was published (legacy provider/record, not yet observed,
or capture failure); it is never a pass. Consumers can use the capability and
explicit recipe to distinguish unsupported, not requested and not yet observed.

## Native grammar actually checked

The following was inspected directly, using read-only Python introspection with
no EDA, in the supported image:

```text
sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a
LibreLane 3.1.0.dev3
```

`Step.start` executes the body, merges metric updates with incoming metrics,
validates the resulting state, writes `state_out.json`, and only then writes
`runtime.txt`. Both valid records, the exact producer metadata and the fresh
request-bound invocation are required. Directory/config/report existence alone
cannot establish completion. The runtime grammar is `HH:MM:SS.mmm`, with at least
two hour digits, minutes/seconds below 60. Zero is valid. It is derived from
`time.time()` and truncated to milliseconds, **not a monotonic Runner duration**.

Image introspection SHA-256 of `inspect.getsource` for the relevant methods:

| Method | SHA-256 |
| --- | --- |
| `Step.start` | `e7ad4a942fbc52e13f5b284e1194117d64bc4b4a0293cdff68a88bfd0a0d46bd` |
| `MultiCornerSTA.run` | `3ea950db9f273cb2dcbf8ebe4f29cb785bdcc6c813faaa4d1e18fd2fcefc3370` |
| `STAPostPNR.run_corner` | `c92b2acc7fdafad3fa51bfc7a77dc9b0771051aa0d5e42b74c1b5ff42b2de033` |
| `format_elapsed_time` | `203eb09baf7362ba53139a07cc643a1218bfd73c1b9e4037e367b6aabf0571fd` |

The image's `Flow.start` places the explicitly tagged run under the design
directory's `runs/`. `MultiCornerSTA` waits for corner futures but can skip
equivalent corners; output metrics remain cumulative. `DefaultOutputProcessor`
recognizes `%OL_METRIC_F name value` and `%OL_METRIC_I name value` from the actual
corner process. Normalization therefore requires **exactly one native log metric
and a matching output-state value**. Inherited keys or input/output differences
are not measurement evidence. The same lexical Liberty unit parser is shared
with rich inspection; comments, quoted attributes, conflicts and malformed units
cannot earn `ns`.

## Public shape

Illustrative completed analysis from a failed implementation (hashes/paths abbreviated):

```json
{
  "contract": "hardcaml-asic.timing-analysis",
  "schema_version": 1,
  "analysis_id": "ATTEMPT/post-pnr-sta",
  "attempt_id": "ATTEMPT",
  "occurrence_id": "ATTEMPT/implementation.signoff",
  "stage": "signoff",
  "execution_file": "/workspace/execution-ATTEMPT.json",
  "execution_sha256": "EXECUTION_SHA256",
  "source_digest": "ANALYSIS_DIGEST",
  "enclosing_status": "failed",
  "status": "completed",
  "reason": null,
  "evidence_scope": "terminal_supplementary_not_checkpoint",
  "native_grammar": "librelane-3.1.0.dev3-step-output-runtime-v1",
  "duration": {
    "seconds": 1.575,
    "basis": "librelane_step_wall_clock",
    "precision_seconds": 0.001,
    "source": {"path": "/exact/producer/runtime.txt", "sha256": "HASH"}
  },
  "producer": {
    "class_id": "OpenROAD.STAPostPNR",
    "step_id": "OpenROAD.STAPostPNR-1",
    "ordinal": 11,
    "directory": "/exact/run/11-openroad-stapostpnr-1",
    "run_dir": "/exact/run",
    "config": {"path": "/exact/producer/config.json", "sha256": "HASH"}
  },
  "request_id": "signoff-REQUEST",
  "request_sha256": "REQUEST_HASH",
  "request": {"protocol_version": 1, "operation": "execute_segment"},
  "transport_terminal": "/workspace/signoff-REQUEST-transport-result.json",
  "corners": [{"corner": "slow", "status": "measured", "setup_goal": "fail", "hold_goal": "pass"}],
  "metrics": [{
    "key": "setup_slack",
    "raw_key": "timing__setup__ws__corner:slow",
    "corner": "slow",
    "value": -0.125,
    "unit": "ns",
    "availability": "available",
    "reason": null,
    "units_source": {"path": "/exact/producer/slow/generated.lib", "sha256": "HASH"},
    "source": {
      "file": {"path": "/exact/producer/slow/sta.log", "sha256": "HASH"},
      "state": {"path": "/exact/producer/state_out.json", "sha256": "HASH"},
      "line": 123
    }
  }],
  "timing_goal": "fail",
  "inventory": [{"path": "/exact/source", "sha256": "HASH"}]
}
```

`request` is the complete existing backend protocol v1 request, not the shortened
example above. `source_digest` is the canonical `Identity_json.identity` SHA-256
of the entire analysis object **without** the `source_digest` field.

Supported execution statuses are deliberately only:

- `completed`: valid native terminal grammar. Metrics may still be unavailable.
- `unavailable`: no authoritative complete observation; `reason` is a string,
  duration/producer are null, metrics/corners empty and goal unknown. Reasons
  include unreached STA, partial/malformed output, ambiguous producer, unsupported
  version/image or missing freshness evidence. This is not a claimed STA failure.

`enclosing_status` is independently `completed`, `failed` or `interrupted`.
There is no inferred running/failed STA status from enclosing signoff status.

Metric keys are `setup_slack`, `hold_slack`, `setup_violations`,
`hold_violations`, one set for each measured configured corner. Slack means native
**worst slack (`ws`)**, not clipped WNS. Units are `ns` or `count`, otherwise null;
unavailable values are null with a reason. Infinity, NaN, enormous sentinel values,
duplicate/conflicting log records, mismatched output-state values and unknown units
cannot become measured slack. Counts must be finite nonnegative integers within
the exact binary64 integer range. A missing/equivalent corner is represented as
`missing_or_equivalent`, not falsely claimed measured or assumed equivalent.

Each corner has setup/hold `pass|fail|unknown`. Positive violation count or negative
slack yields a scoped fail. Pass requires both valid slack and a zero violation
count. Overall `timing_goal` fails if any scoped goal fails; otherwise all configured
corners/modes must pass to earn pass. Unknown coverage remains unknown. These are
timing-constraint goals, never signoff acceptance or proof from sampled paths.

## Exact inspection invocation (Agent B handoff)

```sh
hardcaml-asic-flow report "$EXECUTION" --json
# Capture timing_analysis.source_digest as ANALYSIS_DIGEST.
hardcaml-asic-flow inspect "$EXECUTION" --domain timing --stage signoff \
  --expected-digest "$ANALYSIS_DIGEST" --json
# Capture the returned index source_digest as INDEX_DIGEST and a returned ROW_ID.
hardcaml-asic-flow inspect "$EXECUTION" --domain timing --stage signoff \
  --row-id "$ROW_ID" --expected-digest "$INDEX_DIGEST" --json
```

With **no row ID**, `--expected-digest` pins the **analysis** digest. With a row ID,
it pins the **index** digest as before. The two digests are intentionally different.
Inspection envelopes retain schema 1 and add `analysis_digest` and `analysis_id`
when using this source. Consumers must match those fields to the captured analysis
on index and detail responses. An unpinned index request remains supported.

Timing/signoff inspection prefers the published observation when present, even
without a signoff checkpoint. All inventoried sources are revalidated and every
report subsequently read must have been captured by that observation. Changes,
deletions, wrong execution bytes/attempt, wrong analysis digest or stale detail
digest fail with exit 2 and no JSON stdout; there is no fallback to another run or
checkpoint. The report preserves immutable completion/metrics if native reports
are later removed; inspection then explicitly fails. Without an observation,
legacy checkpoint-backed inspection is unchanged. Other domains/stages retain
their existing source selection.

## Bounds and verification

Capture and source validation admit at most 512 reads, 32 MiB/source, 64 MiB total;
observation metadata is limited to 1 MiB, producer enumeration to 1024 entries,
configured corners to 64 and STA log lines to 262144. Each corner has four metrics.
Rich inspection retains its existing input/index/detail limits in addition to
observation validation. Failed supplementary publication leaves the original
implementation outcome intact and reports the capture error on stderr.

Focused commands (serialize heavy aliases; no EDA):

```sh
opam exec --switch=5.2.0+ox -- dune runtest -j 6 test/timing_analysis
opam exec --switch=5.2.0+ox -- dune build -j 6 @test/ocaml-stage-preparation
opam exec --switch=5.2.0+ox -- dune build -j 6 @test/inspection @test/ocaml-stage-report @test/ocaml-segment-service
```

The new native grammar suite covers failed signoff with exact report/index/detail,
zero duration/counts, negative slack, nonfinite and inherited metrics, missing
corners, units, duplicate producers, stale/wrong-image records, partial output,
symlinks, byte bounds, mutation/deletion, no-replace publication and read-only
queries. The preparation suite executes the actual provider transport, supervisor,
Runner, publisher and journal against fixture runtime APIs, including STA followed
by success, ordinary failure, timeout and cancellation. No physical flow is run.

Limitations: terminal-only delivery; host death before capture leaves no observation;
no automatic historical backfill; no claimed equivalence without explicit evidence;
no independently runnable timing stage; native duration is wall-clock-derived.

### Verification record (2026-10-21)

- New suite: 18 native grammar/availability cases plus cancellation, wrong-execution
  rejection, public report/index/detail, mutation/deletion and read-only assertions passed.
- `@test/ocaml-stage-preparation`: 62 checks passed, including completed STA followed
  by success, DRC failure, transport timeout and actual SIGTERM cancellation.
- `@test/ocaml-segment-service`: 70 checks passed.
- `@test/inspection` and `@test/ocaml-stage-report`: passed, including legacy fixtures.
- `dune build -j 6 @all`: passed. New OCaml modules/consumer pass `ocamlformat --check`;
  `git diff --check` passed. The whole provider runtest alias was not run.
- Heavy checks were serialized. Source-mode aliases above do not enter the scripts'
  optional installed-prefix branches containing nested `dune build -j20`; those
  branches were audited and not invoked. No EDA flow or installation was run.

A persistent synthetic failed-signoff fixture for consumer integration is available at:

```text
/tmp/opencode/wb069-provider-handoff-a/execution-attempt.json
analysis digest: 24e4c2593bdfb4877af096f7082651563ee910dcf5eda529b9bd01e37ceba264
```

It has no checkpoints, failed Signoff (607.08s), completed STA (1.575s), and a failed
slow-corner setup goal. Both the report and exact public timing index were queried
successfully. It is a deterministic grammar fixture, not a physical-flow result.
Use the built `_build/default/bin/flow_cli.exe` for this checkout; a previously
installed provider will not acquire the new capability without a parent-owned refresh.
# Executable-stage extension

The schema-1 signoff-scoped contract below remains historical evidence. New
schema-4 recipes publish schema-2, Timing-scoped analysis at the real Timing
boundary. See [the executable Timing contract](executable-timing.md) for stable
capability, snapshot identity, digest, duration and continuation rules.
