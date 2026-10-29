# PT.7c B — independent runtime / retained-flow evidence review

2026-10-28. Reviewer: A (native producer/reader owner), **not B's flow implementer**.
Reviewed the current `pt7c-flow-handoff.md`, B runtime/service/coarse/collection/
report/archive source, and C's retained startup failure/findings. No B source was
edited. Review scripts, synthetic cases and results are under `/tmp/opencode`.
No EDA, provider refresh, Git mutation or C native acceptance was performed.

## Final independent follow-up disposition

**B-R1–B-R5 are independently verified closed for the corrected native-v2
source/reader protocol.** The original repros were rerun at a fresh destination;
all previously accepted inconsistent mutations now reject, while the native-v2
baseline and actual archive encoding/restore remain accepted as completed /
unavailable. Additional independently authored true controls verify historical
root/UID/GID relocation, Tcl-list equivalence, valid failed/partial publication
and current service supervision. No additional concrete finding was observed.

The final verification receipt and limitations are in the final section below.
C's final native-v2 actual run is a separate acceptance activity; this review ran
no EDA and does not pre-approve that run. The original findings and failed review
attempts below are retained as historical results against the original sources.

## Original disposition (superseded by verified corrections below)

**Changes requested before accepting B's claimed retained-source association and
archive closure.** Five findings below reproduce against the built public library
entry points. Three are high-severity association/archive gaps; two are medium-
severity process/resource validation gaps. These are reader consistency failures,
not evidence that B's generated runtime actually used the wrong inputs or exceeded
its allocation.

Successful mutated inspections still return `verdict=unavailable`; the false
positive is `status=completed` and its asserted association to retained native
inputs, **not** a passing exhaustive-coverage result. Fully forged execution is
outside receipt authentication. The repros instead change specific recorded facts
while retaining conflicting assertions elsewhere, with the required hashes
recomputed. A retained-source reader should reject those inconsistencies.

## What was independently executed

Built only the small fixture emitter/consumer and public helper binaries:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 test/timing_intent_flow/emitter.exe \
  test/timing_intent_flow/consumer.exe bin/flow_cli.exe \
  bin/experimental_archive.exe bin/experimental_timing_intent_inspect.exe
```

Executed:

```sh
python3 -B /tmp/opencode/pt7c-flow-review.py
python3 -B /tmp/opencode/pt7c-flow-supervision-review.py
python3 -B /tmp/opencode/pt7c-flow-controls-review.py \
  /tmp/opencode/pt7c-flow-controls-review-v2
```

The first script extracts only B test fixture-constructor/API-model function
definitions using Python AST; it does **not** execute B's original top-level test
suite. Independently authored mutations call the compiled `Timing_intent_flow`,
collector/reporter and archive APIs. The native/LibreLane boundary is synthetic;
ordinary library bundle emission is real. Companion source hashes are explicitly
rechecked for the hash-consistent mutation cases. No producer is rerendered during
inspection. The supervisor probe uses the actual transport/supervisor with a fake
Docker client, never a daemon or native tool.

Artifacts:

- `/tmp/opencode/pt7c-flow-review/results.json` and named case directories.
- `/tmp/opencode/pt7c-flow-supervision-review/results.json` and cleanup/client log.
- `/tmp/opencode/pt7c-flow-controls-review-v2/results.json` and control directories.
- The initial controls-review directory retains the review-script assertion failure
  discussed under the historical C attempt below; it was not relabelled as passing.

For another fresh main run, pass a new directory to `pt7c-flow-review.py`.
The supervision script intentionally requires its fixed output directory to be
absent. Do not overwrite old review attempts when rerunning it.

## Findings

### B-R1 — High: actual Liberty receipt is not linked to retained linked libraries

**Source:** `execution/results/timing_intent_flow.ml:241–250,264–271`;
`flow/hardcaml_asic_flow/timing_intent_runtime.py:185–209`.

The runtime retains each selected Liberty and explicitly records
`_CURRENT_CORNER_LIBS`, but the reader only requires the latter to be non-null.
It never compares its objects/paths with the inner audit's Liberty inventory.

**Repro:** from a passing synthetic baseline, change only the actual-input receipt
and reseal the outer companion:

```text
different-actual-liberty:
  native-inputs.json._CURRENT_CORNER_LIBS = /outside/unrelated.lib
empty-actual-liberty:
  native-inputs.json._CURRENT_CORNER_LIBS = ""
```

Both inspect with **exit 0 / status completed**, despite an unchanged inner audit
claiming `library-0.lib` was linked. All advertised companion hashes match.
By contrast, the same mutation to `CURRENT_NL` or `_CURRENT_CORNER_NAME` rejects
with `actual native input/corner receipt differs` (positive controls for reaching
the intended association check).

**Required correction:** retain a bounded, explicit per-library actual-path /
run-relative-copy/hash association, and compare the native environment's exact
library list against it without evaluating Tcl. Require the complete nonempty
list, order/multiplicity policy and actual inner-audit library closure. A non-null
string is not evidence of which libraries the native command consumed.

### B-R2 — High: executed helper / driver / hook identities can refer to unrelated roots

**Source:** `timing_intent_flow.ml:168–174,244–254,258–271`;
`timing_intent_runtime.py:157–169,200–214`.

Several checks compare only a suffix or compare path assertions to one another,
without linking the recorded executed path to the retained script source:

| Repro case | Mutation | Observed result |
| --- | --- | --- |
| `different-launched-request-root` | Launch argv ends in `/another/run/timing-intent/{timing_intent_runtime.py,request.json}` | exit 0, completed |
| `coherent-wrong-native-driver-root` | Native argv ends in `/another/run/timing-intent/driver.tcl`; rehash process/audit/helper-result links | exit 0, completed |
| `coherent-unretained-hook-pointer` | Effective config, delta, native step config and native-input receipt point to `/outside/unrelated-hook.tcl`; retained `hook.tcl` unchanged | exit 0, completed |
| `wrong-native-script-pointer` | `PT7_CORNER_SCRIPT=/outside/unrelated.tcl` | exit 0, completed |

The native `PT7_AUDIT_DIR` and other retained input labels still refer to the
baseline's historical root. Thus the first two cases are not ordinary archive
relocation: independently conflicting historical labels are accepted. An initial
unresealed driver mutation correctly rejects on the inner process-source hash;
the coherent variant demonstrates the missing semantic association beyond hashes.

The runtime also copies `librelane-corner.tcl` but executes `original_script`, not
that retained copy. The qualified immutable image is useful provenance, but the
reader has no checked path/hash mapping between the script pointer and the copy.
This is not a claim that the real image script changed during C's attempt.

**Required correction:** bind all run-owned executed paths to a single historical
execution root, derived/recorded consistently with native inputs and synthesis
state. Validate the exact launched request/helper, driver and hook associations,
and bind the actual corner-script pointer to its retained bytes. Historical
absolute labels need not exist after restore; compare their consistent recorded
relationships to explicit retained sources. Do not fix this by requiring current
source or installed-renderer equality.

### B-R3 — High: archive can bypass the new-run producer expectation marker

**Source:** `execution/archive/archive_service.ml:163–166`, contrasted with
`collect_service.ml:228–232`, `report_service.ml:275–281` and
`timing_intent_flow.ml:101–105`.

Collection/report explicitly consider `run.timing_intent_expected=true`; archive
only considers `Timing_intent_flow.expected manifest`. Removing the producer
declaration therefore skips timing source replay during archive selection.

**Repro:** `archive-downgrade` removes `timing_native_coverage` and the producer
member entry from the staged manifest, updates the run's manifest hash, and leaves
the original `timing_intent_expected=true` and build identity. This is deliberately
invalid new-run evidence; it is not a newly emitted historical bundle.

- Explicit inspection: **exit 2**, `new run's advertised producer declaration is missing`.
- Archive selection: **exit 0**; timing-intent source closure is omitted.

The original bundle fails the changed manifest-hash comparison, so archive falls
back to the staged bundle. Archive's existing bundle inventory validation does
not itself establish the ordered-payload identity of this altered manifest.

**Required correction:** invoke the timing evidence verifier when **either** the
manifest advertises the producer **or** the run marker requires it. Preserve
historical absence only for genuine old records. Include this exact disagreement
between explicit inspection and archive in a durable negative test. Acceptance of
archive *selection* is what was executed here; no corrupt encoded archive was
published by the review.

### B-R4 — Medium: contradictory cleanup success and malformed failed transports are admitted

**Source:** `timing_intent_flow.ml:175–183`; actual publication behavior is in
`timing_intent_service.ml:42–59` and `execution_transport.ml:168–169`.

Two independent reproductions:

1. `cleanup-failure-labelled-success` sets
   `transport-result.cleanup_error="owned container removal failed"` while leaving
   `succeeded=true`, `outcome=exited`, `code=0`. Inspection returns **completed**.
   This contradicts the transport's actual success predicate, which includes
   cleanup success, and could hide a recorded cleanup failure.
2. `failed-malformed-transport-result` publishes a failed companion with
   `succeeded="not-a-boolean"`, `outcome="invented"`, `code="not-an-exit-code"`.
   Inspection returns **exit 0 / status failed** instead of rejecting malformed
   advertised process evidence. The failed branch bypasses terminal-result shape
   validation altogether.

**Required correction:** validate a closed terminal-result schema for both paths,
including Boolean success, allowed outcome/code combinations and cleanup status.
Do not allow a completed companion with any recorded cleanup error. Preserve
valid timeout/cancellation/failure receipts as failures; missing/invalid native
audits in genuinely partial attempts must not be converted into coverage claims.

This does not demonstrate a runtime success-publication bug: the service itself
uses `T.succeeded` and the independently executed timeout/cancellation probes
correctly publish failed companions.

### B-R5 — Medium: Docker resource argv check accepts an overriding CPU allocation

**Source:** `timing_intent_flow.ml:146–158,167–173`.

`check_docker_argv` requires a literal `--cpus=6` and rejects other `--cpus=...`
tokens, but does not parse the equally valid two-token `--cpus VALUE` form.

**Repro:** `alternate-cpu-option-20` inserts `--cpus 20` after `--cpus=6` in the
retained analysis launch argv and reseals its companion. Inspection returns
**exit 0 / completed**, and still accepts the resource assertion as bounded.
No Docker process with this argv was launched by the reviewer.

The generated transport uses the correct six-worker form; the defect is the
reader's permissive membership/prefix check, not observed excess resource use.

**Required correction:** parse/validate the qualified generated Docker argv
structure, rejecting duplicate/conflicting resource options in both spellings.
Bind the actual image position, entrypoint and relevant environment/worker flags
as structured arguments, rather than finding expected tokens anywhere in argv.
Keep the existing exact native `sta -threads 1 ...` check, which passed the
independent negative control below.

## Passing independent controls and limits

### Native and synthesis association checks that do reject

The following hash-consistent mutations reject for the intended diagnostic:

- Different actual `CURRENT_NL` / `_CURRENT_CORNER_NAME`.
- Version-process argv changed from `sta -version` to `/unrelated/sta -version`:
  `native version process did not complete`.
- Native `-threads 20`: `unbounded or unexpected native process argv`.
- Native process exit 9 after all hook/completion records:
  `STA process did not exit successfully`.
- Selected synthesis config's producer changed to `Yosys.Other`:
  `wrong synthesis producer`.

Code inspection additionally confirms fixed supported version checks for
LibreLane `3.1.0.dev3` and OpenSTA `2.7.0`, explicit single requested/executed
`DEFAULT_CORNER`, the four-key configuration delta, equal native/synthesis netlist
hashes, full bundle-SDC hashes, and retained-producer member hashes. These checks
are useful but do not close B-R1/B-R2's actual consumed-source linkage gaps.

### Cancellation, budgets and partial failure

The independent supervisor script executes the actual `Timing_intent_service`
and transport over a fake Docker client:

- 0.2-second timeout returns **124**, records `timed_out`, no completed native
  audit/runtime result, and a reader-visible failed companion.
- Cancellation callback returns **130**, records `cancelled` / code 2 and the same
  truthful failed status. This is a cancellation-before-native-work control, not
  an independently demonstrated mid-STA interrupt.
- Owned `rm -f` cleanup was observed; all observed launched fake client PIDs were
  gone when checked. The run recorded 115 bounded removal attempts across both
  probes; these are fake-client calls, not daemon/container observations.

Source inspection confirms the linked transport's default 600-second supervisor
bound, separately bounded cleanup, six-worker/container generation, native
`sta -threads 1`, effective `STA_THREADS=1` and serialized one-corner analysis.
The analysis timeout bounds the helper including its native child through owned
container cleanup. Ordinary synthesis still uses its existing coarse cancellation
route. No EDA resource usage or OS allocation enforcement is inferred from these
fixtures.

### Source containment, read-only collection/report, archive restore

- Missing library, linked source, `../outside` source entry and >8 MiB companion
  metadata each reject. These exercise the actual no-symlink run-relative member
  walker and metadata bounds. Source inspection also checks <=512 references,
  <=64 MiB/source and <=512 MiB aggregate before hashing advertised sources.
- With a stored successful `results.json`, changing a retained Liberty makes fresh
  collect/report expose `timing_intent.status=invalid`; archive rejects on the
  changed-source diagnostic. Every file hash before/after those read-only queries
  is identical. Stored summaries are not used as authority for the timing evidence.
- Actual public CLI archive encoding of the unmodified baseline succeeded.
  `run.json`, reports archive and input-bundle archive restored at a different root
  inspect as **completed / unavailable**, with historical absolute labels retained.
  The reader uses retained run-relative files; it does not query original PDK/tool
  paths during replay. This positive uses synthetic native reports and does not
  replace C's real archive acceptance.
- B-R3 remains a separate archive-selection false positive despite this working
  ordinary positive restore path.

### No rerender and ordinary-flow boundaries

The runtime sources the emitted retained native producer and SDC copies. It builds
only supplementary witness queries from the retained stage manifest; no design
elaboration or SDC renderer is called. Inspection calls the schema2 reader and
pure manifest identity verification, not current producer/SDC rendering or tools.
`STAPrePNR.load/start` is separate from the original synthesis state; there is no
`Flow.start`, Classic recipe replacement, Floorplan or checkpoint publication.
Coarse orchestration checks inputs around analysis and fails the enclosing run on
linked-analysis errors. A completed hook alone does not satisfy the service's
process requirement. These source-level conclusions are not native execution
qualification.

## C's retained original startup failure

Read the exact `coarse-integration-02` run at:

```text
hardcaml_asic_example/.dev/asic-pt7c/probe-runs/20261028T164800799130Z_44ded577
```

Its native log still contains the missing `::env(PT7_RECEIPT)` error. Native
`process-result.json.exit_code=1`, transport is exited/code 1/succeeded false,
and the run remains `status=failed`. Independently rehashed all **30** advertised
companion sources before and after the read-only check; they match and did not
change. The current driver loads `_TCL_ENV_IN` inside its catch before receipt
access, consistent with C's reported `_reroute_env` boundary.

The current reader rejects this preliminary run for missing current
`synthesis_process` provenance; the old `run.json` has no such field. My first
controls-script assertion expected a valid failed view and was corrected after
reading the actual old record. This is recorded as current-schema rejection of
an earlier incomplete producer capture, **not** a new runtime regression or a
passing native recapture. No old evidence was repaired or rewritten.

## Reviewed source / repro receipt

SHA-256 of reviewed B sources:

```text
4c80f199dabbf7fa79fa19789a0b7b556da081d0daad4037d3d7a2efd517cb8a  execution/results/timing_intent_flow.ml
11b893a20b722582f768c040e776a143d5fb80281510a650f4f83ca8089303c2  execution/backends/librelane/timing_intent_service.ml
4edad0644e9256cf5114ea87afe1b08247e4f04634b9eec28bf466201899494a  flow/hardcaml_asic_flow/timing_intent_runtime.py
494647b63d98bc2f7ec8b559c987dd7b303f9fc5e2ee129c243b96d34d1b26bd  execution/coarse_run_service.ml
24c9e41346038c47626eda7affb49292431d9805cc6928c3dc4f0faecce430e2  execution/results/collect_service.ml
7869d62a5a77e740f4b5afbd2d53dc623a00635d917471c4a91edfa84ab6a7de  execution/results/report_service.ml
726ed8e7d8c0ff8ddf6b61fc2d0936496c3119e94ef90545fa7ade3d2de6aa7f  execution/archive/archive_service.ml
1cc4b4cae60ac3001efd8afbc2de72c9b7a41414f77dda0e534e2b2178c9acff  execution/runtime/execution_transport.ml
```

Repro/result SHA-256:

```text
1735cc1bb2392a63da5739291b1f7bc9926885a541890b98eb0345ee80df9b27  /tmp/opencode/pt7c-flow-review.py
2ecc8cdf9450a7360647553b290962b77cad458c3184ab47df0db13381bee1ad  /tmp/opencode/pt7c-flow-review/results.json
268e212d7002c4241927cc6e0d2e15d8df26ce32716cccedb4dd3c6fa7a66164  /tmp/opencode/pt7c-flow-supervision-review.py
42e1322a73bb322c83d2a366e4856eaa8c3fc6e7348af260c53aef87c6dcdd75  /tmp/opencode/pt7c-flow-supervision-review/results.json
0c4aaf05505c98fee51921375c1f377bf761e260c4e8b5b1370d4c8a27bdb580  /tmp/opencode/pt7c-flow-controls-review.py
494a8325c3d8695cb9941c41f4a86f9e9b82aa49c51c5fbd6f2808b4c738bdcb  /tmp/opencode/pt7c-flow-controls-review-v2/results.json
```

**Recommendation:** B should close B-R1–B-R5 with intended-diagnostic negatives
and working archive-restore / partial-failure positives, then obtain C's fresh
native acceptance. Retain the earlier failed captures and the review repros.
No exhaustive exception-effect, timing closure or post-PNR claim follows here.

## Final independent verification of B-R1–B-R5 corrections

2026-10-28, after B's native-v2/source-association corrections. A independently
read the updated implementation and `pt7c-flow-handoff.md:245–399`, rebuilt only
the thin public/fixture entry points, and reran its original repros. No B source
or B-owned tests were edited; no broad suites were repeated.

### Executed commands / retained products

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 test/timing_intent_flow/emitter.exe \
  test/timing_intent_flow/consumer.exe bin/flow_cli.exe \
  bin/experimental_archive.exe bin/experimental_timing_intent_inspect.exe
python3 -B /tmp/opencode/pt7c-flow-review.py \
  /tmp/opencode/pt7c-flow-review-independent-v2
python3 -B /tmp/opencode/pt7c-flow-fix-verification.py
python3 -B /tmp/opencode/pt7c-flow-supervision-v2-verification.py
```

The original repro script is unchanged. It obtains the current fixture constructors
and API model without running B's top-level suite. The two new follow-up scripts
independently construct additional mutations/controls using that fresh baseline.
Their case directories and `results.json` files have the corresponding script
stem under `/tmp/opencode/`. Original review and B's own rerun directories were
not overwritten.

The baseline is explicitly checked to have manifest/native-data schema 2,
`opensta-2.7-native-state-v2`, framed V2 raw diagnostics and
`HC_ASIC_NATIVE_V2_COMPLETE`. This verification is not an accidental rerun of old
native-v1 synthetic sources which would merely fail an unsupported-profile gate.

### Closure assertions

| Finding | Independently observed correction | True controls |
| --- | --- | --- |
| B-R1 | Unrelated/empty/reordered/duplicated/omitted actual Liberty lists reject. Coherently reordering both the association array and actual list still rejects against the ordered inner audit inventory. | The complete ordered list accepts; equivalent braced, quoted and bare/escaped-space Tcl lists accept with two distinct retained libraries. |
| B-R2 | Unrelated helper/request root, coherently rehashed native-driver root, coherent unretained hook, and wrong corner-script pointer reject on the intended source-path associations. | A consistent absent historical root and rootful historical UID/GID accept after relocation; mismatched UID versus recorded argv rejects. |
| B-R3 | The original manifest producer-declaration-removal case now rejects both explicit inspection and archive selection with the missing-expected-producer diagnostic. | Actual CLI archive encoding and restore of the unmodified baseline still succeed. |
| B-R4 | Cleanup-error/success contradiction rejects; malformed failed records reject. A second negative preserves the exact receipt shape and changes only `succeeded` to a string, reaching the Boolean diagnostic rather than an incidental missing-field check. | Valid native failure, timeout, cancellation, signal, cleanup failure and post-runtime verification failure all remain failed/unavailable. A genuinely partial attempt with no runtime-result/corners also remains a valid failure. |
| B-R5 | The original CPU override rejects. Additional two-token and equals-form overrides placed immediately after the genuine `--cpus=6` token reject with the qualified-argv diagnostic. | Exact generated six-worker argv accepts for both baseline rootless and historical rootful contexts. |

Representative new diagnostics in the retained results:

```text
actual native Liberty list differs from retained library associations
actual Liberty association differs from inner audit
native process driver differs from retained historical source
executed corner script differs from retained source
executed hook path differs from retained source
transport success contradicts process/cleanup status
invalid transport success Boolean
invalid transport outcome/code
invalid transport cleanup status
transport argv differs from qualified image/resources/executed source paths
```

The unresealed driver control still rejects on the original inner source hash.
The coherent variant now also rejects, establishing semantic linkage beyond that
hash check. Native netlist/corner, missing-library, symlink, traversal and oversized
metadata controls continue to reject in the original repro rerun.

### Stronger relocation / UID / source-closure positive

The additional positive is a synthetic historical capture with:

```text
execution_root = /__pt7c_history_absent__/run [lane] $audit
pdk_root       = /__pt7c_history_absent__/pdk
host_uid       = 424242
host_gid       = 434343
rootless       = false
```

Both historical root and PDK are asserted absent. Recorded IDs are different from
the current review process IDs. All executed pointers, synthesis/native state
labels, request/transport bindings, library associations, hashes and `--user`
arguments are updated consistently. This is a deliberately self-consistent test
of historical-label replay, not an assertion that tools actually ran as those IDs.
No filesystem ownership or host identity settings were changed.

The reader accepts the positive and rejects changing only the recorded UID while
leaving argv untouched. For each of three library-list encodings, an independent
real `tclsh` LIST oracle checks the exact number and UTF-8 bytes of the decoded
paths before reader inspection. This exercises spaces, brackets and dollar signs
as data, without evaluating the list as a script.

The public CLI encodes this rootful positive into an archive. Restoring
`run.json`, `reports.tar.gz` and the input bundle at a fresh current root succeeds
with the absent historical labels and noncurrent IDs intact. Explicit inspection,
collect, report and archive selection on the restored root all succeed and keep
native coverage unavailable. Every restored file hash is unchanged before/after
those read-only operations. The original bundle label is also replaced by an
absent historical path, so archive uses the verified staged bundle; current PDK,
original bundle and historical execution paths are not replay dependencies.

### Current service/supervisor true failures

The new supervision probe uses the current actual service, transport and process
supervisor, with a fake Docker executable and regenerated current-v2 synthesis
argv. It does not invoke a daemon, LibreLane or native STA.

| Probe | Public capture exit | Recorded terminal result | Reader result |
| --- | ---: | --- | --- |
| 0.2-second timeout | 124 | `timed_out`, null code, false success | failed/unavailable |
| Cancellation callback | 130 | `cancelled`, code 2, false success | failed/unavailable |
| Fake client SIGTERM | 2 | `signaled`, POSIX code 15, false success | failed/unavailable |
| Cleanup refusal after client exit 0 | 2 | exited/code 0, nonempty cleanup error, false success | failed/unavailable |
| Failed post-runtime identity verification | 2 | exited/code 0, successful transport, no cleanup error | failed/unavailable |

Each failed view has no interpreted `corners`. The post-verification control is
important: transport success is permitted to coexist with failed **analysis
publication**, so a valid failure is not rejected merely because its process
exited zero. Recorded reasons now describe incomplete verified publication rather
than incorrectly asserting that every failure was a native process exit failure.

Owned cleanup was observed in all five cases, and all four observed launched fake
client PIDs were gone at the final check. There were 227 bounded fake removal calls
across the probes. These are supervisor/cleanup observations, not OS container
resource-attestation or mid-native-analysis cancellation claims.

### Original C failed-run semantics / source versions

The original `20261028T164800799130Z_44ded577` capture advertises the old native-v1
producer. Current native-v2 flow inspection therefore rejects it explicitly:

```text
unsupported legacy/native producer declaration; recapture with native profile 2
```

It is not a supported current-source failed-v2 capture and was not rewritten to
look like one. All 30 advertised source hashes still match before/after this
read-only check; its original run status remains failed, native exit remains 1
and transport exit remains 1. Supported current-v2 failed/partial cases above
accept as **failed/unavailable**, distinguishing legacy contract rejection from
the semantics of a genuine failed attempt. No current acceptance is inferred for
the old provider or C's final-v2 run underway.

### Final disposition and receipt

**Close B-R1–B-R5 for the source snapshot below. No additional concrete finding
was observed in this targeted follow-up.** This closes the independently
reproduced reader/runtime/archive defects; C still owns actual native-v2
production, Step compatibility and final real archive acceptance. Exhaustive
exception effect, timing closure, other-corner or post-PNR claims remain outside
this review.

Corrected source SHA-256:

```text
c52f454c85aae8090ab7d559c9003619e11a5853a4b47fc6722176a40672e3b4  execution/results/timing_intent_flow.ml
85c6bfa25903f7146e47a758d40ef4e68f7806d8041db6d291b2f70984b810c0  execution/backends/librelane/timing_intent_service.ml
6648a8c8b897facf563d81c62ef229369f5c5e2b7ee858bcb22b707c3fed31f8  flow/hardcaml_asic_flow/timing_intent_runtime.py
03d67494c48f045c9e0d686135364d4d6707835853df7f813b58a45eac232bc9  execution/coarse_run_service.ml
24c9e41346038c47626eda7affb49292431d9805cc6928c3dc4f0faecce430e2  execution/results/collect_service.ml
7869d62a5a77e740f4b5afbd2d53dc623a00635d917471c4a91edfa84ab6a7de  execution/results/report_service.ml
28e7d73f2ecab5bed21f23c8a534082d87985453a0c7a39356fa4f47917a8a0c  execution/archive/archive_service.ml
1cc4b4cae60ac3001efd8afbc2de72c9b7a41414f77dda0e534e2b2178c9acff  execution/runtime/execution_transport.ml
```

Independent repro/result SHA-256:

```text
1735cc1bb2392a63da5739291b1f7bc9926885a541890b98eb0345ee80df9b27  /tmp/opencode/pt7c-flow-review.py
53c8bb19c8f108f1633c0b0c5497dfceb4c7c0d1a69d452cc32f110124cf9f56  /tmp/opencode/pt7c-flow-review-independent-v2/results.json
5d771f88e56f66dc5f83e94f5da0ad674dd8c31621524facfe4690814d348ba9  /tmp/opencode/pt7c-flow-fix-verification.py
60979a7a770ea78cecc7d1129b8c7df57ef5a29059646260cbd99d81701bc771  /tmp/opencode/pt7c-flow-fix-verification/results.json
05a0052f33a3add3f71617944da6a05a5af4217852b3afb8511a84abf6bf300a  /tmp/opencode/pt7c-flow-supervision-v2-verification.py
7edca132b462da98027cdb2f522890dcb9b55763d5ad998212e67a1ff30ab4c4  /tmp/opencode/pt7c-flow-supervision-v2-verification/results.json
```
