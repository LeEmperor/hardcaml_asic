# Producer event timing and live observation

Status: delivered and independently reviewed, 2026-10-13. Full provider and
installed-prefix verification, private consumer refresh, consumer tests and actual
synthesis/floorplan live-watch verification passed. New schema-2 attempts expose producer
timing; retained schema-1 journals remain unchanged and readable.

## Purpose

Make journal event timing visible and verify that observers receive intermediate
facts while execution is still running. The existing journal is written at stage
lifecycle boundaries; it is not assembled only after execution. Foreground watch
validates historical records, then polls for newly published records (default
0.5 seconds). A watcher attached to a completed run prints the retained history
together, which does not show the original spacing without producer timestamps.

## Contract

- Record an explicit UTC wall-clock timestamp on each new producer event, inside
  the integrity-protected record. Name/document it as recording time, not precise
  physical tool-start time, disk-durability time, or reader delivery time.
- Include monotonic elapsed time from attempt creation if supported cleanly by
  the writer lifecycle, to measure spacing independently of wall-clock adjustment.
  Sequence remains the authoritative ordering; timestamps do not replace cursors.
- Use a versioned event schema or another explicitly validated compatibility
  mechanism. Old journals remain inspectable/watchable without modification or
  synthesized timestamps from file mtimes. Missing historical times are clearly
  unavailable. A stream must not silently mix incompatible record formats.
- Human updates/watch display producer times and useful elapsed values without
  overwhelming the existing stage/status output. JSON preserves full timing facts.
- Reader delivery timestamps, if used for verification, are separate measurements
  and not journal facts. Do not claim exactly-once delivery, sub-poll latency,
  fsync durability, or physical tool instruction-level observation.

## Verification and workflow

Use sequential single general agents, preserving existing work and forbidding
Git staging/history changes or AI attribution. Every Dune build/test/exec/install,
including nested scripts, uses `-j 20`.

Test schema compatibility, strict timestamp validation, hashing, reconnect and
clock behavior; ensure watch retains incremental parsing and reader isolation.
Verify a reader receives intermediate events before terminal outcome using a
controlled real producer process and a cheap actual `hardcaml_asic_example` run.
Record independent reader receipt times for the experiment, without claiming a
universal latency guarantee. Refresh only the consumer's private development
provider as needed and preserve its recorded dependency pin/global opam install.

No new daemon, event bus, cancellation service, heartbeat, progress percentage or
fine-grained LibreLane lifecycle hooks are part of this feature. Workbench can
consume the existing watch JSONL or cursor reads.

## Evidence

Provider implementation and controlled live verification are recorded below.
See also [flow journal](flow-journal.md) and
[execution ownership](workbench-execution-boundary.md).

## Delivered schema and compatibility

Contract remains `hardcaml-asic.stage-observation`. New Writer attempts use schema
**2**; new software reads **1 and 2**, including old inspect/read-updates/watch.
Lifecycle grammar, event data, execution/checkpoint references and cursor semantics
are unchanged. A stream cannot mix versions. Schema 1 has no timing fields and
readers never synthesize them from filesystem metadata.

| Record field | Schema 1 | Schema 2 |
| --- | --- | --- |
| `contract`, `schema_version`, `stream_id`, `sequence`, `previous_sha256`, `event`, `data`, `sha256` | Required, existing meanings | Required, existing meanings; version 2 |
| `recorded_at` | Absent | Required valid UTC string, exactly `YYYY-MM-DDTHH:MM:SS.ffffffZ` |
| `elapsed_seconds` | Absent | Required finite nonnegative JSON number, not boolean/string, nondecreasing monotonic seconds since attempt creation |

Attempt creation's monotonic origin is sampled immediately before allocation after
workspace ownership. Each append samples UTC and elapsed time before hashing and
atomic promotion. Both timing fields are hash-protected. UTC may regress; sequence
is authoritative. Equal elapsed values are valid. Recording time is not tool-start,
reader receipt or durable/fsync time. Promotion establishes atomic visibility and
process-restart readability, not power-loss durability.

Human watch/read-updates append `[recorded <UTC>; +<elapsed to 3 decimals>s]` to
timed event lines. Old records have no timing label. Full JSON retains producer
precision. No reader delivery timestamp is persisted.

`observation describe --json` advertises:

- `schema_version: 2`, `supported_schema_versions: [1, 2]`;
- capabilities `producer_event_timestamps: true`, `monotonic_elapsed_seconds: true`;
- `timing` rules, `response_schema_policy`, schema-2 `schemas.record` and exact
  untimed `schemas.legacy_record`.

Identity adds `cli_contract.capabilities.stage_observation_schemas:
{write: 2, read: [1, 2]}`, plus the same two timing flags. CLI contract remains
**4**, package **0.1.0**, identity schema **1**. Generic identity
`supported_record_schemas: [1]` remains the coarse operation-record contract;
journals negotiate through their dedicated capabilities.

Inspect/read-updates/watch updates/status report the validated stream's version:
schema-1 payloads retain original facts and field sets; schema-2 update records add
timing. Reduced inspector state deliberately retains its existing facts without
adding redundant timing projections. Allocation/terminal/query-error CLI envelopes
keep schema 1; nested terminal `observation` reports the stream version. JSONL
discriminators and envelope field sets are unchanged, so no gratuitous CLI bump or
example contract-gate migration is required. Timed-journal consumers must explicitly
accept schema 2 after negotiating support.

## Provider verification, 2026-10-13

One sequential general agent; no subagents. Workspace `../AGENTS.md` read; the
existing untracked feature document was preserved and extended. No Git staging or
history operations, consumer refresh or real EDA were performed.

Passed:

```sh
dune build -j20 @test/flow-observation @test/observation-watch \
  @test/default-journal @test/inspector-presentation \
  @test/related-presentation @test/flow-cli @install
python3 -B test/test_packaging.py
python3 -B test/test_installed_prefix.py \
  InstalledPrefixTest.test_installed_flow_observation_suite_and_public_cli \
  InstalledPrefixTest.test_installed_incremental_watch_suite \
  InstalledPrefixTest.test_installed_default_journal_lifecycle_suite \
  InstalledPrefixTest.test_installed_inspector_presentation_suite \
  InstalledPrefixTest.test_installed_related_presentation_suite \
  InstalledPrefixTest.test_installed_shared_cli_contract_version_is_separate_from_records \
  InstalledPrefixTest.test_version_reports_the_package_and_its_prefix \
  InstalledPrefixTest.test_imports_come_from_the_prefix_even_when_a_checkout_is_exported
```

Counts: journal **20**, watch **11**, default journal **10**, inspector presentation
**11**, related presentation **8**, flow CLI **43**, packaging **17**, fresh isolated
installed prefix **8 top-level tests** (including the full journal/watch/default/
presentation suites). Installed helper's nested build and install both use `-j 20`.
An initial controlled-test checkpoint assertion omitted required compatibility;
it was fixed to validate using the published manifest's compatibility, then the
targeted and installed-subset checks passed.

After strengthening the pre-launch marker, missing-field, writer-clock regression
and exact legacy-inspector assertions, the targeted command passed again and the
two installed journal/watch tests passed in a fresh prefix. After making the
malformed elapsed-chain fixture fully clock-independent, `dune build -j20
@test/flow-observation` and the installed journal/public-CLI test passed again.
`git diff --check` passed at closeout.

New tests cover backward fake UTC with nondecreasing/equal monotonic elapsed and
writer rejection of a regressing clock sample without promotion; origin before
promotion; missing/extra fields, malformed UTC/calendar time and boolean/string/negative/
nonfinite/overflow elapsed; independently hash-protected timing; rehashed elapsed
regression and mixed versions in both directions; legacy exact updates/status,
unchanged reduced state, human/JSON watch and no file mutation; cursor reconnect.
Existing warm-reader no-reparse and reader SIGINT/broken pipe/ENOSPC isolation
checks now run on schema-2 streams as well.

The controlled producer subprocess runs the real Writer/runner/SegmentAdapter
composition with fixture checkpoint production, not EDA. It publishes and pauses
after each event until the separate foreground watcher acknowledges receipt, with
a small delay between events. The test receives individually `allocated`, `planned`,
`prepared`, `started`, `published`, `finished`, `outcome`, verifies producer activity
and absent outer outcome at every intermediate delivery, proves `started` arrives
before the fixture's stage launch marker, and validates the promoted checkpoint at
`published`. Independent reader monotonic receipt measurements stay
in the test, separate from producer facts. Local watcher interval is 0.01 seconds;
10-second waits bound stalled processes, without tight elapsed/latency assertions.
This proves no batch-at-end publication/delivery in the controlled lifecycle;
it does not assert universal latency or instruction-level tool observation.

## Independent integration closeout, 2026-10-13

Reviewed writer, strict cold/warm readers, schema propagation, identity,
presentation and source/installed tests. UTC calendar validation rejects invalid
dates, year zero, leap seconds, offsets, alternate precision/case and trailing
characters. Monotonic values reject booleans, strings, negative/nonfinite numbers,
overflow and regression; equal values and backward wall-clock jumps are valid.
The independent review fixed a canonical writer edge case: platform `strftime`
can leave years below 1000 unpadded. UTC `isoformat(timespec="microseconds")` now
emits the required four-digit year; year 0001 and valid/invalid leap-date coverage
was added to the existing timing test. Timing/hash integrity, mixed-schema
rejection, unchanged legacy payloads and full-precision JSON all pass.

Sequential checks after that fix:

```sh
# Provider checkout; full suite, including controlled live producer/watch:
dune runtest -j20 --force
# Fresh temporary installed prefix; full suite, 55 top-level tests:
python3 -B test/test_installed_prefix.py
# Consumer checkout; private development snapshot and activation:
python3 -B scripts/asic_dependency.py refresh --source /home/wayne/devel/jane/hardcaml_asic --mode development
. .dev/asic/current/activate.sh
python3 -B scripts/asic_dependency.py status --json
dune runtest . -j20
# Force execution of consumer checks with the activated generation:
dune runtest . -j20 --force
```

All passed. Refresh's nested build/install/link probe each uses `-j 20`.
Installed checkpoint validation, curated-to-raw timestamp/hash comparisons and
documentation link checks also passed.
Activated generation **`9e8c5d9fe0ef47908e2c39f00fba0dc0`**, snapshot SHA-256
`fa0fa21723a7696cb0091f00f0e1b74de165271205732889c2d4b0cc98b0d3ba`, captured
development bytes based on `57d335f7d76ed2a3db233d0b01007f1b5ff15bae`.
Status confirms the published generation is active and first on `OCAMLPATH`.
This is a local refresh receipt, not source/release attestation; final documentation
and curated evidence below were added after the refresh. Before/after hashes of
152 pin/global-installation file-or-absence entries match. The recorded consumer
pin remains `1714764859274f80a9f5ad207421a04601824e99`. Existing dirty/untracked
work was preserved; consumer tracked files remain clean.

### Activate and use timed journals

Refresh does not activate the caller's shell. In the example checkout, source
`.dev/asic/current/activate.sh` **after each refresh or opam environment reset**;
activate separately in the reader's shell as well. Existing shells may still run
older installed code, despite the unchanged package version `0.1.0`.

```sh
. .dev/asic/current/activate.sh
hardcaml-asic-flow --version --json
hardcaml-asic-flow observation describe --json
dune exec -j20 bin/project.exe -- run --endpoint synthesis --json
# In another activated shell, copy attempt from the early allocation JSON:
hardcaml-asic-flow observation watch "$ATTEMPT" --interval .1 --json
# Human producer-time display and full JSON facts:
hardcaml-asic-flow observation read-updates "$ATTEMPT" --stream-id "$STREAM_ID" --after 0
hardcaml-asic-flow observation read-updates "$ATTEMPT" --stream-id "$STREAM_ID" --after 0 --json
# Reconnect with the cursor from a completely received updates envelope:
hardcaml-asic-flow observation watch "$ATTEMPT" --stream-id "$STREAM_ID" --after "$CURSOR" --json
```

Negotiate `stage_observation_schemas`/`supported_schema_versions`, not package
version alone. A fresh attempt is written in schema 2 by this generation; refresh
does not upgrade old attempts. Inspect is a reduced state snapshot; read-updates
and watch updates provide the complete timing-bearing records. Success on the
reader means it reached a recorded terminal outcome: check the outcome's status
and exit code for execution success.

### Actual synthesis and independent receipt measurements

Curated evidence: [journal-event-timing.json](../../evidence/librelane-observation/journal-event-timing.json).
Raw producer/watch JSONL, full per-envelope UTC/monotonic receipts, descriptor,
identity, replay/reconnect output, human output and hashes are retained externally
under `/tmp/opencode/journal-timing-live-final`; capture script is
`/tmp/opencode/journal-timing-live.py`. EDA workspaces/checkpoints remain in the
consumer's ignored `_flow_results`. These local raw paths are not portable repo
artifacts; the curated JSON retains the essential facts.

Ordinary command: `dune exec -j20 bin/project.exe -- run --endpoint synthesis --json`.
The independent installed foreground watch attached immediately after allocation,
with explicit **0.1-second** polling (default remains **0.5 seconds**). Receiver
UTC and monotonic were sampled by the capture process after extracting each JSONL
envelope, independently of the writer. These are application receipt times,
including pipe/capture scheduling, not kernel-arrival measurements. Liveness and
the last committed record were checked immediately afterward.

Attempt: `_flow_results/observations/20261013T192958461823Z_86621622`;
stream `86621622dcef406cb9d1227dbd7f4084`. Producer and watch exits **0**;
outcome **completed/0**. Synthesis occurrence duration **4.809296 s**; allocation
through outcome monotonic elapsed **5.465391537 s**. Actual Docker-bound LibreLane
`3.1.0.dev3` ran against image
`sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a`.
Its retained log shows configuration loading at `19:29:59` and Classic flow start
at `19:30:00`; these second-resolution tool log labels are separate from producer
UTC. The synthesis checkpoint was published and both owned containers cleaned up.
Physical completion remains `not_recorded`; acceptance/postcheck `not_evaluated`.

All six received envelopes have separate UTC/monotonic measurements in the evidence:

| Envelope | Cursor | Receipt UTC (2026-10-13) | Receipt monotonic seconds | Producer alive / outcome committed |
| --- | --- | --- | --- | --- |
| updates: allocated, planned | 2 | 19:29:58.546426Z | 151749.737111633 | yes / no |
| live status | 2 | 19:29:58.547217Z | 151749.737906420 | yes / no |
| updates: prepared, started | 4 | 19:29:59.149489Z | 151750.340175790 | yes / no |
| live status | 4 | 19:29:59.149915Z | 151750.340604820 | yes / no |
| updates: published, finished, outcome | 7 | 19:30:03.974006Z | 151755.164691074 | no / yes |
| final status | 7 | 19:30:03.974778Z | 151755.165467276 | no / yes |

| Producer event | Recorded UTC (2026-10-13) | Elapsed seconds (rounded here) | Recording-to-receipt seconds |
| --- | --- | --- | --- |
| allocated | 19:29:58.462061Z | 0.000301 | 0.084365 |
| planned | 19:29:58.463771Z | 0.002012 | 0.082655 |
| prepared | 19:29:59.117048Z | 0.655296 | 0.032441 |
| started | 19:29:59.117351Z | 0.655591 | 0.032138 |
| published | 19:30:03.926252Z | 5.464505 | 0.047754 |
| finished | 19:30:03.926653Z | 5.464895 | 0.047353 |
| outcome | 19:30:03.927150Z | 5.465392 | 0.046856 |

`started` was received **4.777661 s** before producer outcome recording by the
observed UTC samples. Direct independent receiver monotonic spacing from the
started updates envelope to final updates was **4.824515284 s**.
Thus this actual run proves intermediate delivery during execution, not
batch-at-end-only delivery. Publication, finish and outcome were recorded within
**0.898 ms** and co-delivered at the next poll after producer exit. It **does not**
prove actual pre-terminal publication receipt; the separately passed gated live
provider test above proves that capability without altering the EDA lifecycle.
The measured **32–84 ms** recording-to-receipt differences are local observations,
not a poll-bound latency SLA. They include pre-write hashing/promotion, watcher
startup, polling, serialization and scheduling. UTC differences can be misleading
under clock adjustment; sequence and producer monotonic spacing govern ordering.

Exact event-line excerpt from installed human read-updates (spaces preserved):

```text
     4 started implementation.synthesis: running [recorded 2026-10-13T19:29:59.117351Z; +0.656s]
     5 published implementation.synthesis: running [recorded 2026-10-13T19:30:03.926252Z; +5.465s]
     6 finished implementation.synthesis: completed [recorded 2026-10-13T19:30:03.926653Z; +5.465s]
     7 outcome completed; exit 0 [recorded 2026-10-13T19:30:03.927150Z; +5.465s]
```

The exact JSON `started.elapsed_seconds` is `0.6555905290006194`; human formatting
rounds only the display. Full records/hashes/data are present in updates JSONL.

Acquisition history is retained honestly: an initial identity query used the
nonexistent `version` subcommand and started no EDA. The first actual short
synthesis completed at attempt `20261013T192934412600Z_8665ed6d`, but its capture
script assumed every producer envelope had an `event` key; successful terminal
execution JSON does not. Receipt evidence from that failed capture is unavailable.
The final short synthesis repeated with corrected envelope handling and immediate
raw receipt persistence. Neither attempt was rewritten.

### Short floorplan follow-up: actual pre-terminal publication delivery

The synthesis-only terminal batch left actual pre-terminal publication receipt
unproven. A short ordinary `--endpoint floorplan --json` follow-up, with the same
installed generation and **0.1-second** watcher interval, closes that verification
gap. It runs synthesis then floorplan, leaving time to receive the synthesis
checkpoint publication while floorplan executes. No producer delays or test gates
were inserted. See [floorplan evidence](../../evidence/librelane-observation/journal-event-timing-floorplan.json);
raw output/receipts/hashes are in `/tmp/opencode/journal-timing-live-floorplan`.

Attempt `20261013T193420741968Z_2e9dc8c4`, stream
`2e9dc8c46ef147699880007a4804999f`, cursor **10**. Producer/watch exits **0**,
completed/0. Synthesis **4.760916 s**, floorplan **4.371336 s**, attempt elapsed
through outcome **9.815546596 s**. Both checkpoints were published against the
same tested Docker image. Full physical completion/acceptance are not evaluated
by this endpoint.

| Envelope | Cursor | Receipt UTC (2026-10-13) | Receipt monotonic seconds | Producer alive / outcome committed |
| --- | --- | --- | --- | --- |
| updates: allocated, planned | 2 | 19:34:20.828784Z | 152012.019470534 | yes / no |
| live status | 2 | 19:34:20.829485Z | 152012.020175165 | yes / no |
| updates: prepared, synthesis started | 4 | 19:34:21.431876Z | 152012.622562545 | yes / no |
| live status | 4 | 19:34:21.432309Z | 152012.622998255 | yes / no |
| updates: synthesis published/finished, floorplan started | 7 | 19:34:26.255743Z | 152017.446428789 | yes / no |
| live status | 7 | 19:34:26.256517Z | 152017.447206269 | yes / no |
| updates: floorplan published/finished, outcome | 10 | 19:34:30.582784Z | 152021.773469939 | no / yes |
| final status | 10 | 19:34:30.583645Z | 152021.774333993 | no / yes |

Synthesis `started` was recorded at `2026-10-13T19:34:21.424425Z`, elapsed
`0.6825274029979482`, received **7.451 ms** later. Synthesis `published` was
recorded at `2026-10-13T19:34:26.184928Z`, elapsed `5.443038233002881`, received
**70.815 ms** later, with producer alive and no outcome committed. Floorplan
`started` at `2026-10-13T19:34:26.185635Z`, elapsed `5.443737483990844`, arrived
in that same updates envelope **70.108 ms** later. Independent receipt monotonic
spacing from this intermediate publication envelope to the terminal updates was
**4.327041150 s**. This is actual live publication delivery before terminal,
in addition to the controlled test. Local recording-to-receipt differences for
all ten records range from **7.451–86.572 ms**, with the same measurement caveats
and no latency SLA. Final floorplan publication/finish/outcome still co-delivered.

Exact installed human event-line excerpt:

```text
     4 started implementation.synthesis: running [recorded 2026-10-13T19:34:21.424425Z; +0.683s]
     5 published implementation.synthesis: running [recorded 2026-10-13T19:34:26.184928Z; +5.443s]
     6 finished implementation.synthesis: completed [recorded 2026-10-13T19:34:26.185340Z; +5.443s]
     7 started implementation.floorplan: running [recorded 2026-10-13T19:34:26.185635Z; +5.444s]
    10 outcome completed; exit 0 [recorded 2026-10-13T19:34:30.557446Z; +9.816s]
```

Completed watch returned one ten-record backfill plus final status; reconnect
after 4 exactly matched the six-record suffix. The three retained legacy reads
and unchanged-file hash comparisons passed again.

### Completed backfill versus live execution

Attaching installed watch to the completed timed run returned **one updates
envelope containing all seven original records**, then final status, exit 0.
Its records exactly equal those received live; original timestamps remain, but
delivery spacing is backfill spacing. Reconnect `--after 4` returns exactly
`published/finished/outcome`, followed by final status. Saving the complete cursor
avoids intentionally replaying that prefix; no exactly-once claim is implied.

The requested retained placement attempt
`20261013T190404282325Z_62436252` and earlier placement
`20261013T162352616479Z_f0ae62fe` both remain schema **1**, cursor **13**,
completed/0; each returned all 13 untimed events together plus final status.
Earlier synthesis `20261013T184318828201Z_45fec45f` remains schema **1**, cursor
**7**, completed/0 and behaves the same way. Installed inspect/watch propagate
schema 1. Before/after byte hashes match for **15/15/9** files respectively.
They retain occurrence durations but **no event UTC/attempt elapsed timestamps**;
neither filenames nor mtimes reconstruct historical event times or delivery gaps.

### Process wait and polling ownership

The existing producer owns its child process wait, OS signals and stage journal
appends at lifecycle boundaries. It can wait for the tool while a separate
foreground watch process polls atomically promoted records and checks writer
liveness. A completed-run watcher drains history immediately. This behavior uses
the existing runner, journal and reader processes; **no new daemon or component
is needed**. These coarse stage events do not represent internal LibreLane steps.
Producer recording time is sampled before the write; atomic visibility is later;
receipt is a third, reader-side measurement. Graceful cancellation is outside this
timing verification.

Changed implementation/test paths:
`flow/hardcaml_asic_flow/{flow_observation,identity,presentation}.py`,
`test/{test_flow_observation,test_observation_watch,test_installed_prefix,test_packaging}.py`.
Documentation: this record, `docs/development/flow-journal.md`,
`docs/guides/{flow,stage-quickstart}.md`, `docs/README.md`. Curated evidence:
`evidence/librelane-observation/journal-event-timing{,-floorplan}.json`.
