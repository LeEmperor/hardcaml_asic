# PT7 named synthesis — independent B runtime/lifecycle review

2026-10-28. Reviewer: B (evidence/report owner), reviewing A's runtime/lifecycle
implementation. **Independent correction reviews now close original R1/R2 and R3.
The latest review also verifies external-alias capture/rechecks, strict metadata,
and exact published-State input within the stated fixture scope.** See the final
section below; prior reproductions/dispositions remain as history. No A-owned
source or test was edited. This is non-EDA review, not C's native qualification.

## Initial review — retained pre-correction evidence

Read the current `Stage_preparation`, `Runner`, `Segment_service`, `Runtime_probe`,
`Timing_intent_named_service`, Python bridge/helper, transport/supervisor contracts,
and A's handoff. Independent harnesses:

```text
/tmp/opencode/pt7-named-runtime-review.py
/tmp/opencode/pt7-named-runtime-review-runner/{main.ml,dune,dune-project}
/tmp/opencode/pt7-named-coarse-independent-replay.py
```

Authoritative retained results:

```text
/tmp/opencode/pt7-named-runtime-independent-r1c/summary.json
/tmp/opencode/pt7-named-runtime-independent-r1c/source-{before,after}.json
/tmp/opencode/pt7-named-runtime-independent-r1c/<case>/review-launches.jsonl
/tmp/opencode/pt7-named-runtime-independent-r1c/<case>/{process,inspection}/
/tmp/opencode/pt7-named-runtime-independent-r1c/runner/{stdout,stderr,process.json}
/tmp/opencode/pt7-named-runtime-coarse-replay-r1/{summary,before,after,stdout}.json
```

Executed **122 independent Python consistency assertions over nine supervised
fixture cases**, plus **37 independently written OCaml Runner assertions**. These
are review assertions, not an additive count of native executions. The harness
uses genuine public named plan preparation and A's fake external engine as the
process boundary. It does **not** import or execute A's `check.py`, `native_core.py`
or lifecycle assertion suite. A reviewer-owned fake-Docker shim records the actual
durable execution/preflight records before dispatching that engine. No Docker
daemon, Yosys, OpenSTA/OpenROAD or physical tool is invoked.

The OCaml review consumer links the installed public API from the current build.
Builds used switch `5.2.0+ox`, explicit `-j6`, shared
`/tmp/opencode/asic-pt7-build.lock`, including its separate `/tmp` Dune root:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @install test/timing_intent_named_runtime/emitter.exe \
    test/timing_intent_named_runtime/consumer.exe \
    bin/experimental_plan_inspect.exe bin/experimental_timing_intent_inspect.exe
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  env OCAMLPATH=/home/wayne/devel/jane/hardcaml_asic/_build/install/default/lib \
  dune build -j6 --root /tmp/opencode/pt7-named-runtime-review-runner main.exe
python3 -B /tmp/opencode/pt7-named-runtime-review.py
```

For a repeat, pass a new reviewer-owned destination as its optional first argument;
the harness intentionally refuses to replace an existing result directory.

Seven reviewed implementation source hashes match before/after the independent
fixture review. No provider capture/activation, Git mutation, Protemu/Workbench
work, or historical-evidence rewrite occurred.

## R1 — high: expectation is not durable before preflight

**Contract:** the requested review explicitly requires expectation durability
before preflight/work. The existing handoff's narrower claim of an initial Runner
summary before invocation is true, but does not establish this earlier boundary.

**Source:** `execution/backends/librelane/stage_preparation.ml`:

- Lines 71–94 allocate/write preflight records and commit the methodology reference
  and native request. `named_request` (59–63) contains no timing expectation.
- Lines 131–149 execute collateral Git commands and host/container metadata probes.
- Lines 174–215 create/stage the workspace, reserve an empty execution file, and
  finish readiness.
- Only lines 216–224 construct the optional expectation in memory and return it.
  It first reaches durable Runner JSON through `execute`/`Runner.execute`.

`Runner.execute` also calls `callbacks.validate` at `runner.ml:140–146` before its
first persistence call. The independently recorded order is
`["validate", "persist", "persist"]`, not persistence-before-validation.

**Actual reproduction:** the successful `good` fixture's reviewer shim records no
execution record at its first external Docker metadata invocation. Its captured
preflight records contain the methodology/request but no explicit versioned
expectation. This observation repeats across all eight cases reaching execution.
The `cancel_preflight` case exits **143** with a retained interrupted preflight,
no workspace, and no top-level `timing_intent` expectation in any retained early
JSON record. It never reaches the later constructor.

Retained products are under `.../r1c/good/review-launches.jsonl` and
`.../r1c/cancel_preflight/evidence/`; `runner/stdout` independently records the
Runner validation ordering. The harness assertions deliberately assert these
counterexamples, not a hypothetical inspection result.

**Impact:** crashes/cancellation/failure during preflight cannot recover the
explicit promised occurrence/profile/companion paths from a persisted expectation.
The frozen methodology/bundle still independently advertises the producer; this
finding does **not** claim that the B reader accepts corrupt evidence or upgrades
absence to native coverage. It is an early-durability contract gap and blocks the
stated before-preflight requirement.

**Suggested A correction:** derive the expectation once attempt/workspace/named
bundle eligibility are known, commit it in the durable preflight/native request
before the first external probe, and preserve it on every failure path. Reuse the
same exact value for the initial Runner record and publication. Persist the Runner
expectation before validation if validation is included in the no-work-before-save
contract. Add an actual early-failure/reconnect assertion; initial-before-invoke
alone does not cover this case. No preflight workspace creation is required merely
to retain the expectation in its already-owned metadata store.

## R2 — medium: failed analysis plus companion obstruction loses secondary error

**Source:** `execution/backends/librelane/timing_intent_named_service.ml:175–180`.
Failure handling attempts the failed companion only when:

```ocaml
not (Sys.file_exists (dir ^ "/analysis.json"))
```

A directory or malformed existing object at that path is treated like an already
published companion. Its existence silently skips publication and the associated
secondary diagnostic.

**Actual reproduction:** case `review-failure-obstruction` uses a reviewer-owned
fake process shim to create a **directory** at the advertised companion path just
before the native helper, then runs the normal modeled `later_failure` behavior.
The native hook log is written, its later modeled native process fails, the helper
exits **1**, and the owned transport is cleaned up. The final occurrence/outer
execution correctly fail with **1** and retain their promoted checkpoint. However:

```text
analysis.json: directory, not a companion
diagnostics.primary.exit_code: 1
diagnostics.primary.secondary: []
diagnostics.secondary: []
```

Products: `.../r1c/review-failure-obstruction/workspace/diagnostics-*.json`, the
retained `timing-intent/<attempt>/` directory, and the transport/process logs.
The independent harness asserts the directory, exact primary exit and both empty
secondary arrays.

**Positive control:** with successful native analysis and the same directory
obstruction (`publication_failure`), publication is attempted normally; the final
primary is a `Published` hook **EEXIST/link** failure with exit **2**. Thus the path
really is a storage/publication error; it is the existing-primary path that skips
recording it. Process-failure-plus-container-cleanup separately preserves its
secondary cleanup cause correctly.

**Impact:** primary failure and stop semantics remain correct; no false native
success results, and the B inspector rejects the missing/malformed companion. But
the combined failure loses the promised secondary explanation for why no failed
companion could be published. This is an evidence/diagnostic defect, not timing
closure or checkpoint corruption.

**Suggested A correction:** distinguish a verified completed publication from an
obstructing/malformed existing path. Preserve nonreplacement semantics and the
original process/cancellation failure; append a secondary companion-publication
error for a directory, invalid existing file, or failed attempted publication.
Add this combined control beside the successful-process storage-obstruction case.

## Passing assertions and source review

| Boundary | Independently observed result |
| --- | --- |
| Initial execution versus synthesis invocation | The real engine sees the persisted expectation before execute-segment; R1 concerns earlier preparation. |
| Promoted checkpoint versus Published analysis | At the actual analysis launch, persisted JSON has exactly one checkpoint and synthesis is still Running. |
| Durable-save veto | Reviewer OCaml callback fails the first save containing an artifact: Published is never called, artifact remains retained, next action is unreached, exact storage exit 28 survives. |
| Required hook failure | Independent failure/cancel/timeout controls retain the artifact and block the next Floorplan action. This is pure Runner callback testing, not a physical run. |
| Primary/secondary ordering | Analysis exit 9 plus later persistence failure keeps exit 9 as primary and records secondary persistence diagnostics; cancellation keeps 130 and timeout keeps 124. |
| Actual analysis input | `good/corners/state_in.json` equals the published checkpoint's State; it is not the candidate or native producer State path. |
| Checkpoint preservation | Every file hash in the engine's pre-analysis checkpoint inventory remains identical across all eight promoted-checkpoint cases. |
| Exact originating association | Publication request is execute_segment; retained checkpoint reference and frozen methodology equal the finalized execution's references. |
| No validation-triggered STA | Only execute, publication validation, and one linked analysis transport occur. There is no retry or additional stage call; analysis starts after promotion. |
| Failure products | Later native failure exits 1, timeout 124, cancellation 130, successful process plus cleanup failure 2; readable failed companions remain unavailable without interpreting partial corners. |
| Worker limits | All three actual work transports have one `--cpus=6`, `_OPENLANE_MAX_CORES=6`, `OPENROAD_THREADS=6`, `OMP_NUM_THREADS=6`; every observed container metadata probe also has `--cpus=6`. |

Source review additionally confirms:

- `Segment_service.call` supervises both execute and publication-validation calls,
  retains correlated request/launch/terminal records, checks runtime and frozen
  inputs around success, and propagates native cancellation/timeouts/cleanup.
- `Segment_service.publish` uses the completed segment object from that service,
  verifies reply/report/resolved inputs, validates the private publication, and
  returns the promoted checkpoint. Runner retains it before the required hook.
- `Stage_preparation` records the exact occurrence/segment/publication association
  in the publish wrapper; its hook requires that exact retained association.
- `Timing_intent_named_service` checks the original reply and candidate/promoted
  segment, producer returned position/metadata, source closure, and checkpoint
  netlist. It rechecks sources/runtime/inputs after process completion. Analysis
  and companion files live outside the checkpoint.
- The Python selector requires the exact terminal Yosys producer position, the
  publication's request-derived run, checkpoint State/resolved paths, native/
  candidate State agreement and native/published netlist hash equality. Step.load
  receives the **published State**, while executed native inputs are retained
  copies of netlist/SDC/ordered libraries and corner script.
- The bridge sets the official LibreLane executor to six and resolves resource
  overrides for **both** execute and publication validation. Validation returns
  before `Flow.start`. Named linked STA sets its executor to one, selects only
  DEFAULT_CORNER, sets STA/OpenROAD threads to one, and executes
  `sta -threads 1`; `sta -version` has its own bounded timeout. These are recorded
  policy/source checks, not independent OS scheduling attestation.

## Shared runtime / accepted coarse compatibility

The coarse Python selector, request/output identity branch, original synthesis
State/config route, and native receipts/audit profile remain separate from named
publication selection. The new named executor/identity handling is gated by the
named request kind. No coarse run record is used in the named path.

Executed the existing coarse orchestration suite specifically for this refactor:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 --force test/timing_intent_flow
```

**150 coarse public/orchestration/replay checks and 11 actual Tcl startup controls
pass.** They exercise fake external/native boundaries, not new EDA.

Separately, the current public coarse inspector replayed the **original accepted
native-v2 coarse run** `83a02bdcb4b34f22bbc03b0ec5223b41` at its original path.
Output is exactly equal as JSON to the retained accepted
`acceptance/pt7c/public-v2-01/inspect/stdout.log`: exit1, completed/unavailable, six
matched stored relations, seven diagnostic categories and 12 endpoints. All **199
original run files** retain identical hashes, sizes and mtimes before/after replay.
No original source, SDC, native report, provider pointer or evidence was rewritten.
This establishes compatibility for the accepted coarse read-only replay, not a new
execution of the changed runtime or a claim of timing closure.

## Reviewer launcher qualifications / disposition

Earlier reviewer destinations `.../pt7-named-runtime-independent-r1` and `...-r1b`
are retained. The first stopped because I incorrectly expected cleanup-only exit1;
the implementation truthfully uses default failure exit2 after successful native
exit0 plus failed cleanup. The second stopped because I incorrectly expected a
secondary error when publication storage failure itself was the primary. Both
reviewer assumptions were corrected; neither is reported as an implementation
defect. The final r1c combined-failure reproduction is distinct and passes its
explicit counterexample assertions.

In that initial reviewed generation R1 and R2 were **open findings**, not edited or repaired by B. Passing lifecycle,
input association, resource, failure and coarse replay controls are accepted only
within their stated fixture/read-only scope. C's actual named native production,
real-tool limits and downstream timing qualification remain separate. Overall
exhaustive effect/reset-release/metastability/timing-closure claims remain unavailable.

## Intermediate correction review — R1/R2 closed; R3 then remained

2026-10-28. Re-read A's corrected preparation, CLI, Runner and capture implementation.
Executed new reviewer-owned assertions rather than re-running A's21-case suite or
importing its verification scripts. The fake external engine remains A's fixture
boundary; reviewer-owned wrappers independently record receipt/snapshot state before
every Git/Python/Docker-fixture invocation. This does not execute a Docker daemon
or native EDA tool.

```text
Harness:
  /tmp/opencode/pt7-named-runtime-final-review.py
  /tmp/opencode/pt7-named-runtime-final-runner/{main.ml,dune,dune-project}

Authoritative new results:
  /tmp/opencode/pt7-named-runtime-final-3wbdxkb6/summary.json
  /tmp/opencode/pt7-named-runtime-final-3wbdxkb6/source-{before,after}.json
  /tmp/opencode/pt7-named-runtime-final-3wbdxkb6/runner/{stdout,stderr,process.json}
  /tmp/opencode/pt7-named-runtime-final-3wbdxkb6/<case>/process/
  /tmp/opencode/pt7-named-runtime-final-3wbdxkb6/<case>/review-external.jsonl
```

**161 independently executed Python assertions over17 focused cases and44
independently written OCaml Runner assertions** pass. These counts include assertions
that reproduce remaining R3; they do not mean17 universally clean acceptance cases.
Eight A-owned implementation source hashes match before/after. The original genuine
emitted bundle is unchanged across all stale/malformed/mutated-copy controls.
Existing initial review products and source hashes remain untouched.

### R1 closure: durable before frozen-input validation, probes and cancellation

`stage_preparation.ml:78–118` now derives native intent from the already-decoded
frozen typed plan, allocates exclusive metadata, writes the exact expectation
snapshot mode0400, records its byte hash in the pending operation receipt/report,
and only then calls `Methodology_execution_service.check`. This deliberately records
a **requested** analysis; invalid inputs do not become eligible or ready merely
because the expectation exists.

Independent controls establish:

| Case | Actual result |
| --- | --- |
| API stale expected plan identity | exit2; valid early snapshot/receipt/report; zero cancellation callbacks and zero external commands |
| API malformed staged manifest | exit2; valid early snapshot/receipt/report; zero cancellation callbacks and zero external commands |
| API immediate cancellation | exit143/signal15; the review callback reads and checks the already-durable snapshot/receipt/report on its **first** invocation; zero external commands |
| API failed metadata probe | exit17; every independently recorded external call sees the exact early expectation; failed report/receipt retain its original reference/hash |
| Public CLI valid named synthesis | exit0; finalized execution's expectation equals the early receipt/snapshot exactly; one promoted checkpoint; public timing inspection completed/unavailable exit1 |

Failed/interrupted cases retain actual status/code/signal, do not create an
implementation workspace, and do not claim readiness/completion. Snapshot mode0400
and byte-hash/reference equality are asserted, not inferred from the handoff.

`runner.ml:140–148` now saves the initial expectation-bearing state **before**
`callbacks.validate`. The independent Runner consumer observes:

```text
validation failure: [persist, validate, persist, persist], exit17
validation cancel:  [persist, validate, persist, persist], exit143/signal15
initial storage failure: [persist, persist], exit28; validation/invoke never run
legacy no-expectation: [validate, persist, persist]
```

Initial persistence failure vetoes validation/work. Required hook failure retains
its saved promoted checkpoint and exact primary/secondary, leaves the next action
unreached, and still enters Published while the occurrence is Running. The pure
Runner test uses two callback actions to test stop semantics; it does not qualify
or execute a named physical endpoint.

**Disposition: original R1 is closed for valid, separately owned metadata paths.**
The additional invalid-destination side effect below is R3, not a failure to close
the originally reproduced missing-expectation behavior.

### CLI eager-validation deferral: frozen authority and rejection preserved

The deferral at `bin/experimental_stages.ml:81–92` applies only after a genuine
methodology plan has been decoded and only when its **frozen** plan advertises native
intent. It does not derive eligibility from an untrusted current staged manifest.
Preparation reuses the normal exact expected-identity, frozen manifest/configuration,
bundle member hash and stage-plan checks at lines112–118. The change moves those
checks after durable request metadata; it does not bypass them.

Ran the actual public `flow_cli.exe stages` dispatch, not merely a private API, with
fresh copied bundles:

- Stale expected plan identity, malformed staged manifest, changed inventoried RTL,
  and a staged `../escape` member all exit2 **before any external probe/work**. Their
  early metadata remains truthful failed/pending-request evidence.
- The malformed-manifest case retains the actual JSON parser error (expected colon),
  an absent `execution_file`, and null `recording_error` in the observation terminal;
  it is not a fake completed execution or a hidden reporting failure.
- Existing workspace is rejected without changing its sentinel/file inventory.
- A checkpoint store outside the workspace is rejected without creating the store
  or workspace. These path controls use the public CLI's standard separate metadata
  root, so no rejected destination receives implementation artifacts.
- The observation-enabled valid baseline succeeds through the same route. Mutations
  affect only separate reviewer-owned bundle copies; the original good baseline
  inventory is identical afterward.

This validates the tested public deferral path and frozen authority; it is not an
assertion that every arbitrary direct-API metadata destination is safe (see R3).

### R2 closure: original primary plus explicit obstruction secondary

`timing_intent_named_service.ml:97–105,202–215` now tracks an actually attempted/
successfully published companion. It uses `lstat` to distinguish a preexisting
directory, unowned regular file, symlink or special object from a companion produced
by this capture. An obstruction during an existing process/cancel/timeout failure
adds an explicit publication secondary and never overwrites the obstruction.

Focused independent controls, each through real provider supervision/publication:

| Existing primary plus obstruction | Exact final exit | Secondary / preservation |
| --- | ---: | --- |
| Later native-process failure + directory | 1 | contains `companion publication failed` and `obstructed`; directory retained |
| Cancellation + directory | 130 | same secondary; original cancellation remains primary |
| Timeout + directory | 124 | same secondary; original timeout remains primary |
| Later process failure + malformed regular file | 1 | same secondary; exact `not a valid companion\n` bytes retained |

Each control retains unchanged promoted checkpoint hashes and exactly three work
calls (execute, publication validation, linked analysis): no retry/later action.
The earlier successful-process/publication-failure control remains a storage-primary
case, not a reason to add a duplicate secondary. **Original R2 is closed.**

### R3 — medium, remaining: invalid overlapping metadata root writes before rejection

The new early-native branch bypasses `check_evidence_root` before allocation:

```text
stage_preparation.ml:85     if not early_native then check_evidence_root ()
stage_preparation.ml:89     Result_store.allocate (evidence_root ^ "/operations")
stage_preparation.ml:96–108 snapshot, receipt and pending report writes
stage_preparation.ml:109    if early_native then check_evidence_root ()
```

`Result_store.allocate` recursively creates its root/ancestors. Therefore the later
path rejection does not undo metadata already written into the rejected workspace.
This is a direct API/private-backend metadata-ownership problem; the tested public
CLI normally derives a separate sibling `stage-preflight` root and did not exhibit
this side effect for its standard route.

**Concrete new reproductions (both reviewer-owned paths only):**

1. `workspace=<case>/workspace` already contains a sentinel;
   `evidence_root=workspace`. Preparation exits2 with
   `evidence root must be separate from workspace`, but adds:

   ```text
   workspace/operations/<new allocation>/operation.json
   workspace/operations/<new allocation>/preflight.json
   workspace/operations/<new allocation>/timing-intent-expectation.json
   ```

   The sentinel is unchanged; the existing workspace namespace is nevertheless
   modified before being rejected.

2. Workspace does not exist; `evidence_root=workspace/forbidden-metadata`.
   Preparation exits2 with the same error, but **creates the workspace ancestor**
   and those three files beneath `forbidden-metadata/operations/<allocation>/`.

Both have zero cancellation polls and zero external commands. Actual added relative
paths are retained in final `summary.json`, and their complete request/config/process
and metadata products are under cases `evidence-equals-existing-workspace` and
`evidence-inside-absent-workspace`. This is an executed side effect, not a hypothetical
alias/race concern. It does not overwrite the sentinel, run implementation, mutate a
checkpoint, or produce false completed native evidence.

**Suggested A correction:** validate ownership/separation of the metadata destination
before allocating/writing there, including canonical existing ancestors where needed.
That is an allocation-authority guard, distinct from deferred circuit/frozen-input
eligibility checks; the early-request record should still precede those latter
checks, probes and cancellation once a safe metadata destination is established.
Reject an overlapping destination without creating its workspace/operations subtree.
Add the two before/after namespace controls. **R3 remains open; B made no A edits.**

### Final integration and resource/preservation record

Builds and review-consumer linking used switch5.2.0+ox, explicit `-j6`, and the shared
`/tmp/opencode/asic-pt7-build.lock`, including the separate `/tmp` Dune project.
The reviewer consumer's first compile needed a local type annotation on the Runner
occurrence; only that reviewer-owned source was changed. No A implementation was
patched to make a control pass.

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @install bin/flow_cli.exe bin/experimental_stages.exe \
    test/timing_intent_named_runtime/emitter.exe \
    test/timing_intent_named_runtime/consumer.exe
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  env OCAMLPATH=/home/wayne/devel/jane/hardcaml_asic/_build/install/default/lib \
  dune build -j6 --root /tmp/opencode/pt7-named-runtime-final-runner main.exe
python3 -B /tmp/opencode/pt7-named-runtime-final-review.py
```

Broadened final named/coarse integration **once**, to check the current combined
request/lifecycle/reader route after the correction review, without rerunning A's
whole21-case/large-closure runtime suite:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 --force test/timing_intent_execution test/timing_intent_flow
```

**168 named public/API checks,150 coarse orchestration/replay checks and11 Tcl
startup controls pass.** The named suite includes its existing complete enlarged
closure control; this final review adds no duplicate C native run or PDK qualification.
All review subprocesses are serialized or fit the six-job Dune allocation. No EDA,
Git mutation, provider/configuration change, Protemu/Workbench work or original
evidence rewrite occurred. `git diff --check` passes.

**Disposition of that generation:** independently close A R1/R2 for the reproduced corrected
boundaries; retain R3 medium for invalid direct-API metadata/workspace overlap.
The normal public fresh named route with separate metadata passes these focused
controls. C native production/closure/timing acceptance remains separate; neither
fixture success nor unavailable evidence establishes exhaustive effects or closure.

## Final R3 and external-alias runtime review — no remaining finding in this slice

2026-10-28. Independently reviewed A's new allocation-authority guard and the new
external-alias runtime path. **R3 is closed.** No additional blocker was found for
the reviewed guard, alias proof/recheck, metadata or published-State boundaries.
C is executing real native acceptance separately; this review uses only new
reviewer-owned fixture directories and does not inspect/mutate C's live runs.

### Independently executed evidence

```text
Harness:
  /tmp/opencode/pt7-named-runtime-r3-alias-review.py
Reviewer API consumer (rebuilt against current library):
  /tmp/opencode/pt7-named-runtime-final-runner/{main.ml,dune,dune-project}
Authoritative results:
  /tmp/opencode/pt7-runtime-r3-alias-independent-z7q8xwf7/summary.json
  /tmp/opencode/pt7-runtime-r3-alias-independent-z7q8xwf7/source-{before,after}.json
  /tmp/opencode/pt7-runtime-r3-alias-independent-z7q8xwf7/namespace-proofs/*.json
  /tmp/opencode/pt7-runtime-r3-alias-independent-z7q8xwf7/processes/<case>/
  /tmp/opencode/pt7-runtime-r3-alias-independent-z7q8xwf7/<alias-case>/review-before-analysis.json
  /tmp/opencode/pt7-runtime-r3-alias-independent-z7q8xwf7/queries/{inspect,report}/
```

**110 independent assertions over11 focused cases** pass: five ownership negatives,
one valid early-cancellation control, one successful alias runtime, three same-byte
retarget phases, and one metadata-symlink negative. The harness imports only setup/
utility functions from the previous **reviewer-owned** harness, not A's test assertion
suite. A's fake engine/native Step adapter remains the external process boundary;
the proof checks, namespace comparisons, small alias inventory and pre-analysis
observation wrapper are independently authored by B. No real Docker daemon,
Yosys/OpenSTA/OpenROAD, provisioning or P&R command is executed.

Seven reviewed A-owned implementation hashes match before/after. A first reviewer
pass stopped on a local string-versus-Path utility argument; that reviewer-only
launcher error was corrected without A edits. A subsequent106-assertion result is
retained at `.../pt7-runtime-r3-alias-independent-ozr9vycm/`; the final110-assertion
run additionally requires explicit secondary messages identifying failed alias/
metadata companion rechecks. Every run uses a fresh destination; old products are
not overwritten or relabelled.

### R3 closure — ownership admission before any preparation write

`stage_preparation.ml:15–39` now resolves prospective directories using only
`lstat`/`readlink` and lexical path traversal, including existing symlink ancestors
and missing descendants. It rejects equal, nested and ancestor metadata/workspace
roots (and filesystem-root/non-directory/over-resolution cases) without mkdir,
probe or cancellation. The call at line106 precedes both the native-advertisement
selection and every `Result_store` allocation/write at lines110 onward.

The allocation-authority guard is correctly distinct from deferred frozen-input
eligibility checks. A request cannot require recording an expectation in a metadata
destination that the operation does not own. Once separate safe roots are admitted,
the early pending expectation still precedes eligibility/probes/cancellation.

Independent before/after controls compare the **entire case file/directory/symlink
inventory**, including file bytes, modes, sizes, mtimes and symlink destinations;
process logs are retained outside that case namespace so they cannot mask a write:

| Case | Result |
| --- | --- |
| evidence root equals existing workspace with sentinel | exit2, separate-root diagnostic, identical namespace |
| evidence root nested inside absent workspace | exit2, no workspace/operations subtree created |
| evidence root is workspace ancestor | exit2, no operation or workspace allocation |
| evidence root is a relative symlink to future workspace child | exit2, sentinel/link/namespace unchanged |
| workspace uses an existing aliased parent while metadata is its physical ancestor | exit2, no hidden overlap or descendant creation |

All five show **zero cancellation polls and zero external commands**, and no early
metadata writes. They close both original R3 side-effect reproductions and extend
coverage to ancestor and aliased-parent cases. The original rejected-overlap products
remain under the preceding `final-3wbdxkb6` review root as pre-correction evidence.

The safe separate-root control immediately cancels with **143/signal15**. The review
consumer's first cancellation callback independently reads and checks the already
written exact expectation, receipt and pending report. Snapshot mode0400, SHA-256
reference, terminal interrupted status/code/signal and equality of the retained
expectation are verified. No implementation workspace or external probe is created.
Thus the ownership correction does not regress the earlier R1 durability closure.

### Runtime alias proof capture is before STA and bound to the publication

`timing_intent_named_service.ml:96–104,119–146,164–171` derives allowed roots from
the actual canonical PDK and staged support locations, checks them against checkpoint
compatibility, captures the table from **original checkpoint external keys**, validates
its hash/size relation, and uses alias-aware bounded admission/hashing. Publication
contains that captured table before invoking the helper. The same fixed table and
all original source references are rechecked after runtime and before companion
publication; no post-runtime target recapture silently substitutes a new association.

The successful fixture deliberately uses only **three** small declared aliases
(two file aliases and a directory-alias file) pointing at the same canonical PDK
Liberty. It does not repeat A's1062-alias/GDS workload or any C native job.

At the actual supervised analysis launch, before the fake native helper executes,
a reviewer-owned wrapper records:

- the already-persisted immutable publication/request and all three original alias
  rows with exact target, whole-PDK root, SHA256 and byte count;
- matching exact declared checkpoint external keys and original `sources` entries,
  not canonical-target-deduplicated replacements;
- the saved Runner checkpoint reference with occurrence still Running;
- all promoted checkpoint hashes and absence of a prematurely completed companion.

Those facts are in each case's `review-before-analysis.json`. The completed positive
retains the same table and declared source keys in public inspection, and named
report `timing_intent` equals the inspection value exactly. Inspection remains
**completed/unavailable, exit1**, not timing closure or exhaustive-effect success.

### Exact published State and strict retained inputs

The actual helper source still invokes `LinkedSTA.load(... state_in=str(state_path))`
with the published checkpoint State selected from the immutable association.
Independent artifacts establish all of these together:

- `request.state_path` and the modeled native Step's actual `state_in` observation
  name the exact promoted `checkpoint/state.json`;
- `corners/state_in.json` equals the published State, including its rewritten
  published view pointers;
- `runtime-result.synthesis.state` points to that published file and differs from
  `synthesis.native_state` (which remains original producer provenance);
- the executed corner is the one explicitly configured default (`typ` in the
  fixture), not an inferred all-corner result;
- the native library input is a **strict regular retained copy** whose hash equals
  the captured external alias row; every actual retained analysis/audit file is
  canonical and not a symlink;
- every pre-analysis promoted-checkpoint hash remains unchanged in all five runtime
  controls, and each has only execute/validation/analysis work calls, with no retry.

### Independent same-byte retarget and metadata negatives

The fake external boundary provides injection points; B independently checks the
captured pre-runtime proof, exact primary outcome, target change, equal bytes,
checkpoint preservation, lack of a valid companion and explicit secondary cause:

| Injection | Actual result |
| --- | --- |
| retarget after publication but before Python source validation | exit1; helper reports bound-resolution mismatch; no valid companion |
| retarget after native Step output but before helper final recheck | exit1; helper rejects the changed association even though bytes/SHA remain equal |
| retarget after helper success but before host capture recheck | transport records success; A's host recheck makes execution fail/2 with alias-resolution error |
| replace analysis request metadata by a same-byte symlink | exit1; `analysis request path mismatch`; external alias permission does not apply |

All three alias controls resolve to a **different canonical target with the original
SHA256**, so their failures are not incidental content-hash mismatches. Every invalid
source/metadata case records a secondary `companion publication failed` message
identifying the rejected alias or linked/noncanonical metadata. No malformed partial
audit is promoted to completed evidence. The metadata symlink is preserved as an
invalid source; no overwrite or checkpoint rewrite hides the failure.

The Python named-only validator checks the same root/key/hash/size table before
source reads and native library copies, pins exact resolution around bounded I/O,
and rechecks after the Step. Canonical metadata, retained copies and native audits
do not inherit external alias permission. The coarse branch remains distinct and
unchanged; no coarse alias relaxation or named archive/relocation is inferred.

### Focused verification / resource and preservation disposition

Only necessary build/link targets and the focused independent review were run:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @install test/timing_intent_named_runtime/emitter.exe \
    bin/experimental_plan_inspect.exe bin/experimental_timing_intent_inspect.exe \
    bin/experimental_report.exe
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  env OCAMLPATH=/home/wayne/devel/jane/hardcaml_asic/_build/install/default/lib \
  dune build -j6 --root /tmp/opencode/pt7-named-runtime-final-runner main.exe
python3 -B /tmp/opencode/pt7-named-runtime-r3-alias-review.py
```

Successful alias inspection/report parity and unchanged-state checks supply focused
public compatibility coverage. No broad unchanged regression suite or A's30-case/
large-closure suite was repeated in this pass. Builds use the existing5.2.0+ox switch,
explicit `-j6`, shared ASIC lock; review subprocesses are serialized. No A source/test
edits, EDA, provider activation, Git mutation, Protemu/Workbench work or C evidence/
live-run manipulation occurred. `git diff --check` passes.

**Final disposition:** independently close A R3 and verify the reviewed external
alias runtime capture/recheck and exact published-State path. Earlier R1/R2 closures
remain qualified as recorded. No remaining implementation blocker was found within
these tested boundaries. C's real native execution/constraints/timing acceptance is
separate and ongoing; fixture success and unavailable coverage are not relabelled
as its acceptance, exhaustive exception effects, reset safety or timing closure.
