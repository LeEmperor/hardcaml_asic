# PT7 named synthesis — A runtime handoff

## Active R3 / declared PDK alias coordination

A read C's `hardcaml_asic_example/docs/pt7named_acceptance.md` final-02/final-03:
1505 supplied paths include1062 declared aliases, whereas canonical-target-only
deduplication yields1409 diagnostic targets. The native bridge/checkpoint deliberately
retains lexical declared external keys; replacing that closure is not authorized.
No named synthesis/STA has run. Numeric4096/128MiB admission alone is not readiness.

A is correcting runtime-review R3 with a **nonmutating allocation-authority guard**
before metadata allocation. It resolves existing ancestor aliases without mkdir or
probes and rejects equal/nested/ancestor metadata/workspace roots before any write.
This guard is distinct from deferred frozen-input/runtime validation: valid separate
roots still get the durable expectation before those checks/cancellation/probes.

B owns the alias proof wire/API. A will consume B's published contract rather than
invent competing proof fields. Required A behavior: retain every original declared
checkpoint external key; explicitly bind canonical target, byte hash/size; check
resolution before/after hashing and after linked runtime; never silently rewrite,
deduplicate aliases by target, omit source keys, mutate PDK or relax metadata links.
Integrated tests and the real read-only declared-list checks now pass; see final
R3/alias closeout below. C must still capture a fresh provider and update its public
precheck adapter to supply explicit roots before real native qualification.

### A adopts B's published alias wire/API

Read B's active seam and use `Timing_intent_inventory` directly. Optional immutable
`publication.external_aliases` rows are exactly `{path,target,root,sha256,bytes}`.
`path` remains the original checkpoint external key; `root` is exactly canonical
whole `pdk_root` or canonical `project/tt`, and `target` must be a canonical regular
file beneath that same root. No alias permission is granted to metadata, bundle
members, checkpoint views, retained native inputs or native audits.

A captures the table before STA using B's `capture_aliases`, compares hash/bytes
with the checkpoint external inventory, preserves every declared source path, and
uses B's alias-aware bounded hash/regular checks before and after runtime. Its
stat-only helper now accepts optional `?external_roots:string list`; no roots keeps
strict canonical behavior. Distinct declared aliases to one target remain distinct
counted/charged entries, not a target-deduplicated inventory.

The Python named helper consumes the same table before source checks and native
Liberty copies, pins exact canonical resolution before/after bounded hashing/copying,
and revalidates the full table/source inventory after the native Step. Metadata and
retained copies stay strict; coarse remains on its unchanged strict-copy branch.
No bridge recipe/closure-key change or PDK edit is needed. Synthetic declared
file/directory aliases plus identical-byte retarget negatives pass, and A separately
checked the actual C declared inventory read-only. Neither is actual native acceptance.

## Active R1/R2 correction seam (2026-10-28)

The original contracts below remain except for these explicit extensions:

- Before named input validation, cancellation polling, external probes or readiness
  work, allocation of the owned metadata directory is followed by an immutable
  **`timing-intent-expectation.json`** containing the exact expectation object
  (unchanged version1 schema). Initial operation receipt and preflight report carry
  top-level `timing_intent` (that same object) and `timing_intent_snapshot`
  `{path:<absolute snapshot>,sha256:<bytes>}`. The later checked named `request`
  also includes these two fields. Terminal failed/interrupted reports/receipts keep
  them even if methodology validation fails before publishing its checked snapshot.
  This is a pending requested analysis, not a claim of eligibility/tool readiness.
  Only nonmutating allocation-authority admission, exclusive metadata allocation,
  and pure derivation of attempt/workspace paths
  precede its first save; no implementation workspace is created for this purpose.
  B may consume these additive preflight fields without a new execution schema.
- Runner persists its initial expectation-bearing record before callbacks.validate
  or cancellation polling. Failed initial persistence vetoes validation/work. Legacy
  no-expectation records retain their historical validation/save ordering.
- Named outer source bounds are **4096 distinct files,128MiB each,512MiB total**;
  metadata8MiB and inner schema2/profile2 audit bounds remain unchanged. This replaces
  the earlier named512-source/64MiB discussion below, not the coarse bounds. A checks
  source stat/header bounds before streaming hashes; no binary collateral is parsed
  as JSON or loaded whole. The67,485,696-byte GDS and1486-source C closure fit these
  outer limits without omitting files. B owns the matching companion/reader limits.
- A only treats a companion successfully published by this capture as completed.
  An existing directory, malformed/unowned regular file or symlink at analysis.json
  is an obstruction: retain the original process/cancel/timeout primary and append
  an explicit companion-publication secondary; never overwrite or silently skip it.

Implementation/tests and C readiness for this correction are appended below.

2026-10-28. Initial wire published before implementation. A owns runtime/writer;
B owns strict execution decoding and `Timing_intent_execution`. See
`pt7-named-synthesis.md`. Existing PT7c files are baseline.

## Frozen wire (version 1)

Execution JSON optionally adds **`timing_intent`**, an exact object:

```json
{"schema_version":1,"kind":"hardcaml-asic.named-timing-expectation",
 "attempt_id":"ATTEMPT","occurrence_id":"ATTEMPT/implementation.synthesis",
 "profile":"opensta-2.7-native-state-v2",
 "directory":"/WORKSPACE/timing-intent/ATTEMPT",
 "request":"/WORKSPACE/timing-intent/ATTEMPT/request.json",
 "publication":"/WORKSPACE/timing-intent/ATTEMPT/publication.json",
 "companion":"/WORKSPACE/timing-intent/ATTEMPT/analysis.json"}
```

This expectation is included in the initial persisted Runner record before any
action. It is enabled only for a producer-bearing **named**, fresh, macro-free,
schema4 synthesis-only plan. Other producer-bearing named endpoints reject during
preparation. Historical producer-free records retain their old shape.

At Published the occurrence is still Running. An immutable `publication.json`
anchors that event (no mutable execution hash): exact fields `schema_version:1`,
`kind:hardcaml-asic.named-timing-publication`, `expectation` (above), `methodology`
(existing immutable reference), `plan` (Execution_plan JSON), `occurrence`
(Runner occurrence JSON at Published), `checkpoint` (Runner.reference_json),
`request` (Backend_protocol request JSON), `reply` (Backend_protocol reply JSON),
`segment` (Segment_report.raw), and `sources` (absolute path/sha256 references).
Sources include original backend request/reply, launch/terminal, candidate State,
resolved/closure/segment, checkpoint manifest/State/resolved/closure/segment and
all checkpoint files. They are checked before and after analysis. Published State
is the actual native Step input; candidate/native State is provenance, not input.
Publication sources also include exact native producer config/State/netlist and
candidate netlist **before launching STA**, so failed native attempts still have
the full producer association; non-image checkpoint external sources are included
to match B's path-bound source verifier. `/nix/store/` closure stays image-bound.

`request.json` exact fields: `schema:1`,
`kind:hardcaml-asic.named-timing-request`, `expectation`, `publication` (absolute
path/sha256 ref), `execution_root` (workspace), `project` (workspace/project),
`analysis_directory`, `host_uid`, `host_gid`, `binding`, `pdk_root`,
`helper_sha256`, `producer_sha256`, `manifest_sha256`, `build_identity`,
`analysis_id` (attempt + `/pre-pnr-sta`), `attempt_id`, `occurrence_id`,
`checkpoint` (Runner reference), `synthesis_run_dir` (exact request-derived run),
`state_path` (published checkpoint/state.json), `resolved_path` (published
checkpoint/resolved.json). No fake run_id/coarse record.

The retained helper supports this request and the existing coarse request.
Named helper output `runtime-result.json` has `schema:1,status:completed,kind:
hardcaml-asic.named-timing-result,attempt_id,occurrence_id,build_identity,
analysis_id,synthesis,effective_config,requested_corners,executed_corners,audits`.
Named `synthesis` refs are workspace-relative `config` (actual native producer),
`state` (published State), `netlist` (published nl), `resolved` (published config),
plus `state_netlist` (exact historical pointer), `native_state` (native producer
state_out), `candidate_state` (originating candidate state.json).

`transport.json` fields: `request_sha256,binding,argv,workers:6,sta_threads:1,
timeout_seconds`. Docker workspace mount/workdir are workspace and project;
payload is retained helper/request, bound interpreter flags, workers6.
`transport-result.json` fields: `request_sha256,succeeded,outcome,code,
cleanup_error`. Same closed terminal outcome/code shapes as coarse. Additive
`error` is NOT used: primary and secondary errors are in companion `failure`.

`analysis.json` exact fields: `schema_version:1`,
`kind:hardcaml-asic.named-timing-analysis`, `expectation`, `publication` (ref),
`request` (ref), `status` (`completed`/`failed`), `failure` (null or
`{kind:failed|interrupted,exit_code,signal:null|POSIX,error,secondary:[strings]}`),
`sources` (absolute path/sha256 refs, including request, publication, helper,
transport, logs, native source closure and synthesis provenance; excludes itself
and toolbox scratch). Exclusive creation; no replacement/retry. Completed native
audits remain schema2/profile2; `audit_id=analysis_id`. Partial audits never confer
coverage after failed transport/cleanup/verification. Reader invokes native audit
inspector only for completed companions. No rerender in runtime or reader.

## Lifecycle / failure

Stage_preparation composes publish callback to remember exact segment/publication,
then launches only from Published after Runner artifacts/source retain checkpoint.
Analysis errors become Runner.Callback_error: stop attempt; preserve promoted
checkpoint, signal/timeout and cleanup secondary diagnostics. No validation call
launches STA. Native process success and unavailable exhaustive coverage is runtime
success. Expectation alone before synthesis does not assert publication/completion.

## API and C launch

Implementation API and verification results will be appended after tests. Public
C route remains named methodology synthesis through Stage_preparation.prepare with
`~methodology:(expected_identity, frozen_plan)`, then Stage_preparation.execute.
No resources/provider activation or EDA is performed by A. Workers at most6,
STA1; Dune switch5.2.0+ox, -j6 and shared asic-pt7-build.lock.

## A/B integration update

A read B's handoff including its adoption of the wire above. A now invokes B's
`Timing_intent_execution.publish ~directory ~succeeded ~failure ()`, then uses
only the standalone native audit inspector at Published (not the finalized named
execution inspector). Runner stores expectation in its `t` so every serializer,
including the existing CLI caller, emits it without an extra caller argument.
The initial summary is persisted before invocation. New bridge digest (explicit
6-worker executor + resolved thread overrides) is
`19e34f189f8cd47a3911c48a772c0b77a7a3f66dc3470a252f9cd88251f1fed0`;
Segment_service pins this for newly prepared runs. Old checkpoints are not edited.

First integration build reached B's in-progress reader and failed at
`timing_intent_execution.ml:43` (`read_manifest` self-reference needs `rec`).
A did not edit B-owned source; later builds will pick up B's correction.

### Coordinator blocker found by real named emitter

The first `test/timing_intent_named_runtime` run cannot prepare a native bundle:
`Methodology_plan.prepare` raises `Invalid_argument "object fields do not match
versioned schema"` at `lib/methodology_plan.ml:163–185`. Its closed manifest list
allows resource_snapshot but neither timing_intent nor timing_native_coverage.
The test uses the actual public preparation API, not a manufactured plan. This
main-library codec is outside A's ownership. Coordinator/B must admit and validate
the identity-covered timing fields before any genuine named timing plan can exist.
A continues independent runtime/lifecycle checks; no workaround/relabelled plan.

The full checkpoint's conservative PDK closure participates in B's 512-source /
512MiB inventory limits. C should check that actual input inventory fits those
bounds before launch; an oversized closure is a real bounded-route rejection,
not a reason to omit declared sources. No named archive/relocation is claimed.

**Historical limit above superseded:** current named admission is4096 files,
128MiB each,512MiB total. The full conservative closure is still mandatory.
Coarse and inner audit limits are unchanged.

### Blocker resolution and durable publication ordering

Coordinator has corrected the main-library manifest gate. The genuine named
runtime suite now reaches preparation, synthesis, publication validation and STA.
The first actual supervised fixture exposed that Published previously preceded
the summary save containing its artifact. For expectation-bearing executions,
Runner now persists the retained promotion **before** Published; storage failure
vetoes analysis without losing the artifact. Historical executions retain their
previous ordering. Finalized occurrence is still recorded only after the hook.

## Implemented API / C launch handoff

`Timing_intent_named_service` exposes:

```ocaml
val expected : Identity_json.t -> bool
val validate_plan : methodology:Methodology_execution_record.t option ->
  initial_checkpoint:string option -> plan:Execution_plan.t -> Identity_json.t -> unit
val expectation : workspace:string -> attempt_id:string -> Identity_json.t
val capture : ?timeout:float -> workspace:string -> resources:string ->
  methodology:Methodology_execution_record.t -> plan:Execution_plan.t ->
  expectation:Identity_json.t -> occurrence:Runner.occurrence ->
  segment:Segment_service.segment ->
  publication:Segment_service.checkpoint Runner.publication ->
  binding:Execution_transport.binding -> pdk_root:string -> environment:string list ->
  cancel:(unit -> int option) -> verify_runtime:(unit -> (unit,string) result) ->
  verify_inputs:(unit -> (unit,string) result) -> unit -> unit
```

`Stage_preparation.prepare` adds optional `?cancel:(unit -> int option)`;
`Segment_service.create` and testing fixture creation add optional workers (1..6,
default6) and cancel. `Runtime_probe.observe` adds optional workers, default6.
`Runner.execute` adds optional timing_intent; Runner.t retains it and every
Runner.to_json emits it automatically. Existing CLI caller signatures work.

C should use a freshly captured provider containing A+B+coordinator changes,
freshly prepared native-profile2 named **synthesis** plan/bundle, new isolated
workspace/evidence paths, and already provisioned explicit tools:

```sh
"$FLOW" stages "$BUNDLE" --methodology-plan "$PLAN" \
  --expected-plan-identity "$PLAN_ID" \
  --support-tools "$TT" --pdk-root "$PDK" --python "$PYTHON" \
  --docker "$DOCKER" --git "$GIT" --workspace "$WORKSPACE" \
  --checkpoint-store "$WORKSPACE/checkpoints" --timeout 600 --probe-timeout 20 --json
# Use the returned exact execution_file (or execution-<returned attempt_id>.json).
"$FLOW" timing-intent-inspect "$EXECUTION" --kind execution --json
# Expected inspection exit1: verify completed status and unavailable verdict.
"$FLOW" report "$EXECUTION" --json
```

Public preparation owns runtime resource selection. No separate coarse `run`,
manual STAPrePNR invocation, recipe/checkpoint edit, or rerender is needed. Do not
pass --through/--stages/--checkpoint alongside methodology selection. A normal
successful named synthesis has exactly one synthesis checkpoint, a completed
occurrence and companion, published State as corners/state_in input, default-only
corner, and report/inspection native evidence with unavailable exhaustive coverage.
Use original checkpoint inventory hashes before/after public inspection. Paths
remain bound; named archive/restore is outside scope. A ran no EDA or provider
capture/activation. Real native C qualification remains required.

## A verification closeout

Final bounded command passed:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @install @test/timing_intent_named_runtime/runtest \
  @test/timing_intent_named_runtime/core @test/ocaml-runner \
  @test/ocaml-segment-service @test/ocaml-stage-preparation \
  @test/timing_intent_flow/runtest
```

- **13 supervised genuine named-plan fixture cases**: successful published-State
  analysis; native hook followed by later process failure; unexecuted corner;
  timeout; cancellation; successful native process + cleanup failure; companion
  storage obstruction; changed immutable request selecting wrong State;
  post-runtime identity failure; process failure + cleanup failure; cancellation +
  cleanup failure; unsupported signoff endpoint rejected before probes/workspace;
  preflight cancellation. All retain checkpoint bytes after promotion, use the
  exact occurrence/publication and6-worker argv, and do not run STA in publication
  validation. Eight valid failure shapes plus success are accepted by B's strict
  reader; malformed/missing advertised evidence rejects. Native boundary is fake.
- **7 independent native-core cases** run the actual helper and schema2/profile2
  native inspector, checking published State, immutable checkpoint, later native
  failure, missing corner, wrong State/netlist/position and duplicate producer.
- Runner lifecycle controls verify initial expectation persistence, Running at
  Published, durable artifact save before required hook, retained checkpoint and
  blocked downstream work on failure/cancel/timeout/storage error, primary/secondary
  truth and prework cancellation. A final extra failed-durable-save veto control
  passed with `dune exec -j6 test/timing_intent_named_runtime/lifecycle.exe` under
  the same switch/lock after the broad command.
- Existing **691 Runner**, **70 segment service**, **62 stage preparation** and
  **150 coarse flow** check groups pass; install builds. These are heterogeneous
  groups, not an additive assertion total. The bridge fixture now asserts the
  official executor cap and four resolved resource overrides; the segment test's
  old20-worker expectation was corrected to6. Those two narrow existing fixture
  updates accompany the new isolated runtime tests.
- `git diff --check` passes. No EDA, Git mutation, provider/configuration changes,
  Workbench/Protemu changes or historical-evidence edits. Initial failed fixtures
  exposed/corrected the manifest prerequisite, missing fixture header view and
  durable Published save order; they are not relabelled as native acceptance.

The first combined regression exceeded a120s harness window; the repeated final
command with a900s window completed. No passing native execution is attributed to
these fixtures. C's actual named synthesis/STA and independent review are next.

## R1/R2 corrections and real-PDK bounds — ready for C

Implemented A's independent-runtime-review findings without editing B readers.
This section supersedes the earlier before-invocation-only durability claim.

### Exact early snapshot API/wire for B and C

From an already-decoded typed methodology plan, `plan_expected` performs only pure
selection of the frozen native advertisement. Stage preparation then allocates its
exclusive metadata directory and publishes a read-only expectation snapshot before
bundle/expected-plan/path policy validation, cancellation or any external command.
No implementation workspace is needed. Snapshot bytes are Result_store record JSON
(sorted/indented ASCII + newline), not a different identity JSON protocol.

```text
EVIDENCE/operations/<allocation>/timing-intent-expectation.json
  exact existing schema1 expectation object (unchanged fields), mode0400

operation.json / preflight.json / prepared.json:
  timing_intent: <same object>
  timing_intent_snapshot: {path:<absolute snapshot>,sha256:<exact bytes>}

checked named request:
  existing fields + timing_intent + timing_intent_snapshot
```

The initial receipt is pending/not-ready. A validation failure may have this
expectation but no checked methodology snapshot; this is a requested operation,
not an assertion that it was eligible or ran. Failed/interrupted preflight reports
retain both fields and expose status, exit_code and POSIX signal/null. Operation
receipts retain their actual failed/interrupted status/code. The same in-memory
expectation reaches Runner and publication; it is never reconstructed from mutable
post-preflight inputs. B can consume the additive preflight fields directly; no
change to the strict execution expectation/publication/request schema is required.

`bin/experimental_stages.ml` now defers its redundant **native-only** eager bundle
check to this preparation seam. Typed CLI/plan parsing and private metadata
allocation necessarily precede the snapshot; environmental/frozen-input validation
and cancellable work do not. Producer-free launches keep historical eager checking.
Runner likewise saves named initial state before callbacks.validate; storage
failure vetoes validation and work. No-expectation validation/save order is unchanged.

### Failure truth

A companion completed by this capture is tracked explicitly. When a native process,
cancellation or timeout is already primary, a directory, symlink or unowned/malformed
file at analysis.json adds `named timing companion publication failed: ... obstructed`
as secondary. Primary code/signal and other cleanup diagnostics are retained;
the obstruction's bytes/type are preserved. A successful process whose publication
itself fails keeps that storage failure primary and does not retry publication or
add a duplicate explanation. Promoted checkpoints remain untouched.

### Resource/closure bounds

New public A helpers:

```ocaml
val plan_expected : Hardcaml_asic.Methodology_plan.t -> bool
val source_count_limit : int       (*4096*)
val source_size_limit : int        (*128 *1024 *1024*)
val source_total_limit : int       (*512 *1024 *1024*)
val precheck_sources : string list -> unit
```

`precheck_sources` uses canonical regular-file headers/stat only, de-duplicates
paths, and rejects over-limit sets before hashing. Actual capture uses the same
admission before streaming every source hash through Checkpoint.file_record. The
Python named selector also admits the full publication inventory under these
limits before streaming its checks. **No opaque .gds/PDK file is parsed as JSON or
read wholesale.** Explicit metadata retains its8MiB bound; native State has its
own syntax/view decoding; inner native audit bounds/profile stay unchanged.

C's67,485,696-byte GDS is below128MiB;1486 PDK+analysis sources are below4096.
The entire conservative host closure must remain inventoried and hash checked;
there is no basename filtering, omission of collateral or shortened source list.
Image-only /nix/store closure retains its established exact-image association.
B's new outer publisher/verifier owns final admission of all analysis additions.

### Verification actually completed

All commands used switch5.2.0+ox, explicit-j6 and the shared ASIC lock. Broad
compatibility command passed:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @install @test/timing_intent_named_runtime/runtest \
  @test/timing_intent_named_runtime/core @test/ocaml-runner \
  @test/ocaml-segment-service @test/ocaml-stage-preparation \
  @test/timing_intent_flow/runtest @test/timing_intent_execution/runtest @test/flow-cli
```

- **21 supervised named runtime cases** pass, including immediate/preflight
  cancellation, validation failure before probes, failed metadata probe, unsupported
  endpoint, first-external-command observation of initial receipt/snapshot, exact
  expectation equality through execution, combined process/cancel/timeout + directory
  obstruction, malformed regular-file obstruction, and existing failure/cleanup
  policies. The successful storage obstruction remains its own primary failure.
- The full **1486-file synthetic PDK closure includes the67,485,696-byte GDS**;
  complete linked capture and B inspection succeed without dropping any member.
  The analysis metadata adds additional files, so this exceeds1486 total advertised
  sources and tests the enlarged final outer inventory too. The EDA boundary is fake.
- **8 stat-only admission controls** cover actual size/count shape,4096 exact/over,
  de-duplication,128MiB over-limit,512MiB exact/over, and symlink rejection. Sparse
  large-file controls are not parsed or loaded whole.
- Runner controls prove persist-before-validation, veto on initial storage/28,
  validation cancellation/143 and failure/17, Running-at-Published, durable retained
  artifact before required hook, storage-save veto, and primary/secondary retention.
- Compatibility groups pass: **691 Runner**, **70 segment service**, **62 stage
  preparation**, **150 coarse +11 Tcl startup**, **156 B named evidence**, **7 native
  core** and **43 CLI/policy tests**. Install builds. Counts are heterogeneous, not
  an additive native execution/acceptance total.

After the final mode0400 snapshot hardening, reran `dune build -j6 @install
@test/timing_intent_named_runtime/runtest` under the same switch/lock: all21 runtime,
8 admission and Runner lifecycle groups pass, including the new read-only snapshot
mode assertion. The broad compatibility groups above precede only that permission
hardening; they are not relabelled as a later complete regression.

The first changed fixture delegated Git/Python through runpy with the wrong argv0;
its failure was corrected in the fixture. A later modeled closure omitted info.yaml;
the fixture now inventories every genuine manifest member, matching the corrected B
frozen-input checks. Neither was counted as a passing real native run.

**C readiness:** use a fresh provider containing these A changes and B's frozen-input,
terminal/cleanup and4096/128MiB bound fixes. Existing C failures/identities remain
unchanged; do not complete or repair their companions in place. The public launch
commands above are unchanged. Check early snapshot/receipt fields as well as exact
published-State/native association, full source count/GDS retention and checkpoint
hash preservation. A performed no EDA, provider/config changes, Git mutation,
Workbench/Protemu changes or historical-evidence edits.

## Final R3 / declared-alias closeout — A ready for C

2026-10-28. Read B's new R3 runtime review, B's exact alias proof handoff and C's
latest final-02/final-03 acceptance/precheck records. Fixed A's allocation side
effect and adopted B's alias API/wire; B owns R2S/reader corrections. No PDK,
checkpoint, recipe, old provider or C history was changed by A.

### R3: allocation authority before any write

`Stage_preparation.prepare` now resolves existing path components and symlink
ancestors **without mkdir, allocation, cancellation polling or external processes**.
It compares the prospective metadata/workspace namespaces, including not-yet-existing
descendants, and rejects equal/nested/ancestor roots (including root `/`) before
writing anywhere. This uses result-store-compatible path resolution, not a lexical
prefix comparison that could miss aliases. Existing stable-parent/exclusive-ownership
requirements still apply; it is not an adversarial filesystem race sandbox.

This allocation-authority admission precedes the durable expectation. For valid
separate roots, the exact mode0400 snapshot and pending receipt/report still precede
all frozen-input/expected-plan checks, runtime readiness/probes and cancellation
polling. There is no attempt to write a request into an unowned/rejected destination.

Four direct-API controls snapshot the **entire fixture tree before/after**:

- evidence_root equals an existing workspace with a sentinel;
- evidence_root is inside an absent workspace;
- a lexically separate evidence-root symlink resolves into a workspace descendant;
- evidence_root is an ancestor of the workspace.

All exit2 with zero added/changed paths, zero cancellation polls and zero external
commands. The absent workspace stays absent and the sentinel/link bytes stay intact.
The standard valid separate-root case still completes, and all early validation/
probe/cancellation failure receipt/snapshot controls remain passing.

### Full declared alias association, not canonical-target replacement

Runtime uses B's `Timing_intent_inventory.capture_aliases` and validates its result
against the completed checkpoint's **unchanged** external inventory before STA.
The optional publication field is exactly:

```json
{"external_aliases":[{"path":"<declared external key>",
  "target":"<canonical target>","root":"<canonical PDK or staged-tt root>",
  "sha256":"<exact closure SHA256>","bytes":193}]}
```

Original `sources[].path` entries and checkpoint closure keys are never replaced.
Distinct aliases to one target are retained and charged separately. A's source
admission/hash capture uses the alias table only for those exact external paths;
all metadata/native retained files keep canonical regular-file requirements.
After native execution, A checks the entire bound table and every declared source
again before companion publication. B's publisher consumes that immutable table,
not a newly regenerated post-runtime association.

The Python named helper also validates the table against exact checkpoint keys and
allowed roots, hashes declared paths through their bound targets with bounded
64KiB reads/descriptor identity checks, and pins target resolution before/after
hashing and copying. Native Liberty reads through an original PDK alias use the
same proof. It rechecks all declared publication sources/alias rows after the native
Step; returned library/report/audit paths remain strict retained copies. The coarse
selector/copy branch, producer schema2/profile2 and stage recipe are unchanged.

### Passing integrated controls

Focused A tests pass **30 supervised runtime cases**, **10 outer-admission controls**,
**7 native-core controls** and the existing Runner lifecycle controls. Added cases:

- Full1486-declared-path synthetic collateral set, including1062 file/directory
  aliases and a67,485,696-byte GDS. A captures all1062 proof rows, preserves every
  original key through real companion publication/B inspection, and supplies the
  native modeled library through a declared alias. No target deduplication occurs.
- Identical-byte alias retarget **before helper input selection**, **after native
  Step work**, and **after helper completion but before host verification** all
  fail. The exact canonical-target change is detected even though byte SHA256 stays
  equal. The promoted checkpoint's own file hashes remain unchanged; changed source
  evidence is not promoted to completed native coverage or silently republished.
- A request-metadata symlink is rejected, not admitted as external collateral.
- Precheck stays strict without roots, admits registered aliases with explicit
  canonical roots, and rejects an alias outside the selected root. Existing size/
  count/aggregate boundaries remain4096/128MiB/512MiB with no omission.

Broad compatibility command passed under switch5.2.0+ox, `-j6`, shared ASIC lock:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @install test/timing_intent_execution/consumer.exe \
  @test/timing_intent_named_runtime/runtest @test/timing_intent_named_runtime/core \
  @test/ocaml-runner @test/ocaml-segment-service @test/ocaml-stage-preparation \
  @test/timing_intent_flow/runtest @test/timing_intent_execution/runtest @test/flow-cli
```

Observed compatibility groups:691 Runner,70 segment service,62 stage preparation,
150 coarse and43 CLI/policy checks; A focused groups had already run successfully
and were reused where unchanged. B's current alias/secondary suite is independently
owned; see its final handoff for215 checks and source-specific correction results.
These heterogeneous groups are not an additive count of native executions.

After the final root-`/` ownership guard and API-comment cleanup, reran `@install`,
`@test/timing_intent_named_runtime/runtest` and `@test/timing_intent_named_runtime/core`
with the same switch/lock/-j6: all30 runtime cases,10 admission controls,7 native-core
and Runner lifecycle groups pass. Earlier broad compatibility is not relabelled as
a later complete regression.

### Actual C declared inventory checked read-only — no EDA

A also ran a new read-only script, not the old canonical-target diagnostic gate:

```text
/tmp/opencode/pt7-named-alias-real-precheck-a.py
/tmp/opencode/pt7-real-alias-precheck-a-kgf2n_kk/summary.json
```

It consumes C's **unchanged** `area-run-final-03/pdk-precheck.json`, passing explicit
canonical whole-PDK and original support-tools roots to both A's stat helper and
B's public precheck. Result: **1505 declared paths admitted,1062 aliases retained**,
largest67,485,696 bytes. It additionally captures B's SHA-bound alias table and
cross-checks **every1062 declared alias hash** with A's Python `named_digest`, plus
the large GDS hash. Before/after canonical resolutions, device/inode, sizes, mtimes
and ctimes for all1505 entries are identical; C's original inventory JSON bytes are
identical. Full source/resolution/hash products are under the new `/tmp` directory.

This proves the real existing path-policy/hash seam, **not** readiness of synthesis
or an actual linked STA execution. It does not substitute diagnostic canonical
targets into C's declared list, and writes nothing into PDK/C evidence/provider roots.

### C's next steps / resource confirmation

Capture a fresh combined provider with these A changes and B's R2S/alias fixes.
Update C's public precheck adapter to pass explicit canonical roots with the original
declared paths:

```ocaml
Timing_intent_execution.precheck_sources
  ~external_roots:[ canonical_whole_pdk_root; canonical_original_support_tools_root ]
  ~paths:complete_original_declared_paths ()
```

Do not use the technology child as root: CMOS5L aliases legitimately target sibling
ihp-sg13g2 under the whole PDK root. Original support-tools precheck authority is
not runtime authority: runtime uses its staged canonical `project/tt` instead.
Inspect counts/association rows and budget future checkpoint/analysis metadata.
Use the ordinary public named `stages` route and exact returned execution file;
check `association.external_aliases`, full source retention, native-v2 evidence,
report parity, early expectation and stable checkpoint bytes. Preserve all old
blocked attempts and do not fill their companions in place.

**A confirms current implementation resource policy:** preflight container probes,
synthesis and publication validation use six workers; linked analysis transport is
at most six with the native STA executor/tool at one thread. Alias admission/hash
checks are synchronous and launch no tools or additional worker pool. No additional
EDA allocation is used by A. Actual native acceptance still belongs to C and has
not been performed by A; no P&R, provider configuration, Git, Workbench/Protemu or
historical-evidence changes occurred.
