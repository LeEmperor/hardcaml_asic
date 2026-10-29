# PT.7 — named synthesis timing-evidence integration

2026-10-28. Written before implementation. The [phase plan](../phase_plan.md)
is the only active queue. This slice extends accepted native-v2 evidence to
**fresh, macro-free named synthesis executions**, not P&R or named full-flow
qualification. Existing PT.7c modifications/untracked evidence are the baseline.

**Final status: bounded named synthesis accepted.** The original pre-implementation
plan follows; actual verification and limits are recorded below.

## Lifecycle and evidence boundary

Bind linked pre-PNR STA to the exact named methodology, attempt,
`implementation.synthesis` occurrence and published synthesis checkpoint. Consume
published State/netlist and resolved configuration, checked against the originating
execute-segment request/reply, successful transport and native Yosys producer.
Never manufacture a coarse run record or infer association by directory recency,
matching names or aggregate cells.

Use `Runner.Published` after Runner retains the promoted checkpoint. Capture the
exact segment/publication association through the publish callback. The occurrence
is still Running at Published; don't record completion prematurely. Keep analysis
in a separate attempt-owned directory. Do not mutate checkpoints, replace State,
change recipes or rerender. Native schema2/profile2 and LF-only reader are reused.

**Failure policy:** advertised analysis is required. Runtime/validation/publication
failure or cancellation stops the attempt before later actions; promoted checkpoints
stay retained. Preserve primary/secondary process, cancellation and cleanup causes;
no implicit retries. Unavailable exhaustive coverage or negative timing is not a
runtime failure. Unsupported native/macro/physical endpoints reject before synthesis.

## Exclusive ownership and dependencies

| Slice | Ownership | Dependencies / acceptance |
| --- | --- | --- |
| A: runtime/lifecycle | `stage_preparation.*`, `segment_service.*`, `runtime_probe.*`, Runner writer/expectation plumbing, new `timing_intent_named_service.*`, Python timing runtime/bridge as needed; `test/timing_intent_named_runtime/` | Publish request/expectation contract first; analyze retained publication, exact checkpoint input, bounded workers, truthful cancellation/failure |
| B: evidence/report/CLI | New `timing_intent_execution.*` and shared verifier if justified; coarse verifier only for shared factoring; `stage_execution_record.*`, `stage_report_service.*`, minimal `inspection_service.*`, CLI/capabilities; `test/timing_intent_execution/` | Decode A expectation; native-v2 reuse, exact methodology/attempt/occurrence/checkpoint association, inspect/report parity, source closure |
| C: example | New named timing scripts/catalog adapter/docs/evidence, isolated `.dev/asic-pt7named` and `_build_pt7named` | Fresh public named synthesis, checkpoint preservation, native analysis, named report/inspect equality, cross-attempt/profile/input negatives |
| Coordinator | Plan, phase queue, guide, orchestration/review | Preserve baseline and record actual evidence/limits |

A/B publish concrete seams in `pt7-named-runtime-handoff.md` and
`pt7-named-evidence-handoff.md` before integration. Root test/build declarations
belong to B; prefer isolated directories. A owns Runner writer; B owns strict
stage-record decoder. C uses public APIs without a local production timing parser.

## Shared contract

1. Persist an optional versioned named timing expectation/reference **before**
   execution. Bind exact attempt/occurrence, producer profile and deterministic
   companion directory. The producer-bearing bundle independently requires evidence;
   removing either signal cannot downgrade to historical absence. Legacy shapes stay.
2. Reader: `Timing_intent_execution.inspect ~execution ()`; explicit CLI
   `timing-intent-inspect EXECUTION_JSON --kind execution --json`. Require the exact
   file, not guessed workspace/checkpoint/latest. A checked snapshot seam lets report
   use the same captured record without combining generations.
3. Per-corner native audit stays schema2/profile2. A distinct versioned outer
   association binds methodology snapshot/plan/bundle, attempt/stage plan,
   synthesis occurrence/publication, execute request/reply/launch/terminal,
   returned-step position/native metadata/netlist, and linked-analysis transport/
   config/libraries/processes/reports. Freeze a stable publication source record,
   not a hash of a mutable live execution; avoid cycles.
4. Compare finalized occurrence/publication with retained source association.
   Valid failed analysis stays failed/unavailable; unreached/pre-analysis failure
   is explicit. Missing required evidence after synthesis or malformed present
   evidence is invalid. Later unrelated failures cannot retarget synthesis evidence.
5. Reuse ordered-library, historical-path, complete transport argv, terminal/cleanup
   and native-v2 validation. Distinguish configured from actually executed default
   corner. No current PDK discovery, retained Tcl execution or renderer calls.
6. Named report and timing inspection expose the same checked timing value; corrupt
   required evidence rejects both. Overall exhaustive coverage remains unavailable,
   inspection exit1. Query success is separate from timing closure.
7. Expose a bounded verified source inventory. **Named archive/export and relocated
   runnable checkpoints are outside this slice.** Existing checkpoint/methodology
   references are path-bound; no hidden-root replay claim without checked mapping.
   Coarse archives remain compatible.

## Verification

- Lifecycle/decoder positives and negatives: legacy, expectation persistence,
  publication association, Running versus finalized, hook-success/process-failure,
  cancellation/timeout/cleanup, companion publication failure, retained checkpoint
  and blocked downstream work. Validation/publication must not accidentally run STA.
- Hash-consistent provenance mutations: wrong attempt/profile/plan/publication,
  duplicate/wrong producer position, publication-validation success substituted for
  execute transport, wrong State/netlist/library, downgrade/missing companion,
  duplicate CPU flags, bad version/corner/report. Truthful controls required.
- Inspector/report parity, source rehash and read-only/no-rerender behavior; missing
  PDK doesn't trigger discovery. Preserve truthful path-bound limitations.
- Fresh actual public named synthesis: five original stages, six stored relations,
  seven categories, 12 endpoints; exact plan/bundle/checkpoint association, native
  version/process/library evidence, unchanged checkpoint bytes, one default corner,
  and visible downstream setup/hold. No physical flow. A second attempt/profile
  may supply a real wrong-association control within C's allocation.
- Independent cross-review after passing suites, fixes/retests, appropriate named,
  coarse and CLI regressions, actual final evidence and explicit limitations.

## Resource and preservation policy

20 concurrent jobs globally: A/B/C at most six each, two reserved. Every Dune
invocation explicit `-j6` or lower, switch `5.2.0+ox`, shared checkout locks
`/tmp/opencode/asic-pt7-build.lock` and `/tmp/opencode/example-pt7-build.lock`.
Nested captures count too. C alone has initial synthesis/STA allocation within
its six jobs; STA one thread and explicit container/worker limits. Named preflight,
probe, synthesis, publication validation and analysis must all respect six workers
(current default-20 paths need correction). P&R allocation zero.
No Git mutations/publication, Protemu/Workbench changes, old providers/configuration,
historical-evidence edits, provisioning or daemon actions.

## Acceptance closeout

Delivered required named-synthesis analysis, exact publication/source linkage and
public report/inspection parity. Contracts:
[runtime](pt7-named-runtime-handoff.md),
[evidence](pt7-named-evidence-handoff.md).
Independent reviews: [runtime](pt7-named-runtime-review.md),
[evidence](pt7-named-evidence-review.md),
[actual final products](pt7-named-final-review.md). No reviewed blocker remains
for this bounded scope.

### What the reviews and integration corrected

- Named manifest codec initially rejected the identity-covered timing fields.
- Full conservative PDK closure exceeded initial source limits; named limits now
  admit 4096 sources/128 MiB each/512 MiB total without loosening coarse or inner
  audit limits. Existing PDK aliases require explicit immutable declared-path,
  canonical-target, root, hash and size associations, not dropped/deduplicated keys.
- Expectation persistence originally followed preflight work. It now precedes
  validation/probes/cancellation, with ownership-root rejection before any writes.
- Runner now durably records the promoted checkpoint before required Published
  analysis. Primary failures retain publication/cleanup secondary causes.
- Frozen manifest members, copied inputs and pinned external collateral are checked
  against exact retained bytes and published closure, not just a coherently rehashed
  outer inventory. Cleanup attempts and failure kind/code/signal must agree.

All initial precheck failures and earlier captured providers remain preserved.
The final external-pin fix changes reader/publisher validation only; runtime and
native products are unchanged. Its corrected helper/source identities are retained
separately, without reattributing execution or rerunning EDA.

### Actual public named execution

Execution provider: `ce6be246fafa4d0dbe1dd00da980482b`, source snapshot
`acbd7ca972fba8c3f98473fc47bd099b5ce79d82ac97f8774e1a3601f06b66d5`.

| Profile | Attempt | Published checkpoint identity |
| --- | --- | --- |
| area | `cb5e7cd92dbf43b4a6c00a74b61c6d72` | `ce398522bace78e0f4b0249826f662ab7dce5d574f903d0c36d8ff6add78e84d` |
| delay | `9374823306a64897959e1b2295f52c84` | `9b72f1aeb191a967e792e6dfb8ef5a3fbaabc8e815b94569c202aa51a58ccc62` |

Both public catalog/plan/emission paths supplied frozen distinct methodologies
to actual named synthesis and linked OpenSTA 2.7.0. Each retains five stages,
six stored relations, seven diagnostic categories and 12 endpoints, with one
explicit typical corner. All seven checkpoint files remain byte-identical to
pre-analysis publication. Public inspection/report/source-list parity passes;
five actual cross-attempt/profile/publication/missing-expectation controls reject.
Each inventory contains 1584 verified sources and 1062 aliases, including the
complete 1486-path PDK closure and 67,485,696-byte GDS.

Three setup witnesses per profile are +19.432287 ns; three hold witnesses remain
**−0.044244 ns (violated)**. This is preservation/association acceptance, not closure.
Mapped netlists happen to be equal; distinct attempts/plans/checkpoints are never
treated as interchangeable.

[Native receipts](../../../hardcaml_asic_example/docs/pt7named_native_final.md),
[final corrected reader](../../../hardcaml_asic_example/docs/pt7named_reader_r4_final.md).
Independent final replay verifies identical entire inspection/report outputs,
1584 sources/1062 aliases, unchanged checkpoint files and both 168-file run trees.
Example preservation checks report 16,084 original files unchanged. Captures are
local development-byte evidence, not P6 compiled-source or execution authentication.

### Tests and limits

Final named evidence suite: 282 public/API checks, including coherent-rehash
external-pin negatives and truthful pinned/unpinned/alias controls. Runtime suites
cover 30 supervised cases, 10 admission controls, seven native-core cases and
durable lifecycle tests. Independent reviews cover early ownership/expectation,
timeout/cancellation/storage failures, exact frozen sources, alias retargets,
terminal/cleanup consistency and actual native receipts. Existing Runner (691),
segment (70), preparation (62), coarse timing (150), schema1/native-v2, named-plan,
report/inspection/CLI and install checks passed during integration; affected tests
and original native replay were repeated for later corrections. These are separate
check groups, not one additive total or a claim of a final forced full-repo run.

Two actual synthesis and two linked STA runs, no P&R. Native/preflight/publication
launch receipts show six-worker ceilings; STA uses one thread. Dune calls and
nested builds used explicit limits/shared locks within the global20-job pool.
No Git mutations, old provider/app/daemon changes or Workbench/Protemu work.

Named evidence is path-bound. Named archives, restart/physical endpoints, other
corners, post-PNR qualification, exhaustive effects/per-check coverage and reset/
CDC consumer adequacy remain unestablished. Inspection returns exit1/unavailable;
named report query success is not a timing verdict. Phase_plan.md owns follow-ups.
