# PT7 named synthesis — A independent review of B evidence

**Final bounded closeout: R1, R2, R3, R2S and R4 are independently verified closed.**
No remaining blocker was found in the prior reviewed cases. The original R4 rebound
and publisher repro now reject; pinned/alias and unpinned true controls pass. Fresh
corrected-reader replay of both original C area/delay products is identical to their
accepted inspection/report/source outputs. Historical findings and dispositions
below remain unchanged; the final R4 closeout supersedes their status. Actual native
boundary review: [pt7-named-final-review.md](pt7-named-final-review.md).

2026-10-28. Reviewer A owns runtime/lifecycle, not B reader/report/CLI. This review
does not modify B source or C evidence. All executions below are fixture/native-API
models, **no EDA**. Existing dirty PT7c/named work is baseline. C's actual named
qualification is separate and was not rerun or relabelled by this review.

## Initial result: three independently reproduced validation gaps

### B-NAMED-R1 — frozen inventoried RTL/config/source can disagree with retained input (high)

The named reader compares frozen/staged **manifest JSON**, verifies the checkpoint
closure against its own hashes, and checks promoted/native netlist bytes. It does
not compare retained inventoried RTL/source bytes against the file hashes in the
unchanged frozen methodology manifest.

Repro uses a real public prepared `area` plan and valid baseline named fixture:

1. Change `workspace/project/<manifest.synthesis_sources[0]>` to different RTL.
2. Preserve the frozen methodology snapshot, plan identity, bundle identity and
   manifest (including its original declared RTL hash).
3. Put the changed RTL into candidate and promoted checkpoint `closure.json` with
   its actual new digest. Rehash the checkpoint inventory/identity, execute reply
   artifact records, current checkpoint reference and publication/request checkpoint
   reference. Add the RTL to the retained source inventories.
4. Rebind publication/request/transport request hashes and all companion source
   hashes. Native netlist and native audit bytes stay unchanged.

**Actual:** inspector/public CLI exit1, report exit0; status remains `completed`,
native stored-exception scope remains matched, and report/inspection parity holds.
The declared frozen RTL hash and actual retained RTL hash disagree. An even simpler
control with an additional retained RTL source and no closure rewrite is accepted
as well, but the closure-rebound case is the substantive provenance reproduction.

Relevant code: `timing_intent_execution.ml` association and staged/frozen manifest
checks; `timing_intent_linked.ml` manifest/native input verification. This is a
missing cross-link to an existing identity-covered authority, not a demand for
authenticated execution or a claim that arbitrary producer assertions cannot be
forged. Recommended correction: validate every relevant inventoried staged input
against the frozen manifest and require the closure's occurrence/input association
to agree. Never rerender to establish the expected bytes. Check source-input copy,
configuration and SDC/producer as well as synthesis RTL, with truthful legacy rules.

Expanded independent controls reproduce the same acceptance for **src/config.json**
(change CLOCK_PERIOD to123 while frozen/resolved configuration stays unchanged) and
the original source copy **inputs/dune-project**. Both rebound the checkpoint closure
and all outer source hashes, preserving the original frozen manifest/plan/bundle
identity. This is not limited to an irrelevant extra source: the retained closure
explicitly claims the mismatching file as an input. Relevant reviewed lines are
`timing_intent_execution.ml:96–100,159–166,232–233`.

### B-NAMED-R2 — failed companion cause need not agree with retained transport (medium)

Start with a truthful failed timeout: occurrence/outer execution failed/124,
companion failure `{kind:failed,exit_code:124,signal:null,error:timeout,...}`, and
transport `timed_out/code:null/succeeded:false`. This positive control is valid.

Change only the advertised transport terminal (then rebind all source hashes) to:

- `cancelled/code:2/succeeded:false`, or
- `exited/code:9/succeeded:false`.

**Actual:** both contradictions are accepted as valid failed evidence by explicit
inspection and report, with the timeout/124 companion cause unchanged. No partial
native coverage is promoted, but cancellation/process provenance is misreported.

`failure_check` compares companion failure to finalized occurrence, whereas the
shared linked verifier checks the terminal's internally closed shape and returns
early for failed analysis without correlating that terminal with the claimed cause.
Reviewed locations: `timing_intent_execution.ml:56–68` and
`timing_intent_linked.ml:255–274`.
Recommended correction: correlate primary failure kind/code/signal for unsuccessful
transports; preserve the legitimate separate case of successful transport followed
by failed input/runtime verification or companion publication.

### B-NAMED-R3 — execute cleanup attempts can contradict successful terminal (medium)

In the successful originating execute-segment terminal retain
`transport_succeeded:true`, process `exited/0/cleanup_error:null`; set cleanup to
`{error:null,attempts:[{process:{outcome:exited,code:23,cleanup_error:null},
diagnostic:owned removal failed}]}`. Rebind publication and companion sources.

**Actual:** completed inspection/report still accepted. The reader only checks
`cleanup.error=null`; it never requires retained removal attempts to substantiate
successful owned cleanup. Production transport success requires removal success or
definitive absence, so this source set cannot support its success assertion.
Recommended correction: validate the production cleanup/attempt terminal protocol
and successful terminal removal/absence semantics without losing primary errors.
If deliberately supporting reduced historical launch/terminal records, version and
scope that compatibility explicitly rather than admitting contradictions in new
advertised named evidence.
Reviewed location: `timing_intent_execution.ml:128–131`.

## Independent controls / positive boundaries

The review script is `/tmp/opencode/pt7-named-evidence-review.py`. It reuses B's
fixture **constructors only** to make genuine `Methodology_plan.prepare` plans and
native-schema positives; all mutations, rebinding and acceptance checks are
independently authored by A. It does not import a production Python reader.

Initial retained results:
`/tmp/opencode/pt7-named-evidence-review-y0pzq8pf/results.json` and
`reviewed-sources.json`. A fresh final run with per-control source overlays and
additional containment/size controls is recorded below when complete. Re-running
allocates a new directory and never overwrites previous review products.

- Two independently valid named fixture attempts use genuinely prepared `area`
  and `alternative` profiles. Plan identities differ, while bundle identity is
  intentionally equal because the profiles select equal effective settings.
  Both initial and restored-final baselines inspect completed/unavailable and
  have exact report/inspection/public-CLI parity.
- Substituting the actual other profile's methodology, other attempt's checkpoint,
  or other attempt's native synthesis references rejects on semantic association,
  after hash rebinding rather than incidental checksum failure.
- Removing expectation, methodology, both, or the required companion rejects.
  The independent staged/frozen advertisement guards prevent historical downgrade.
- Duplicate and >512-source inventories reject. A valid extra absolute external
  source is accepted; this alone is not a containment defect because named evidence
  intentionally includes path-bound methodology and external collateral sources.
- A captured-current execution replacement is rejected by the supplied frozen
  execution hash, including a duration-only replacement.
- Genuine producer-free historical named absence is unavailable/exit1 and omits
  the additive report field. A present corrupt companion on that historical record
  rejects (inspection/report/CLI exit2). Historical omission is intentional, so its
  absent report field is not classified as a parity failure.

## Source inspection observations

- Optional expectation decode closes fields/version/profile/attempt/occurrence,
  requires a fresh named schema4 synthesis plan, checks absolute canonical directory
  spelling and deterministic request/publication/companion paths.
- Publication binds the exact frozen methodology/plan and finalized checkpoint;
  Running-at-Published is distinct from finalized completed/failed/interrupted.
- Exact generated Docker argv, six-worker policy, execute-versus-validation,
  producer returned position/metadata, candidate/native State equality, promoted
  State input, per-corner libraries and native profile/version are checked. Shared
  coarse association remains a distinct adapter.
- Report captures execution bytes/hash and validated checkpoint snapshot before
  calling `inspect_snapshot`. The named reader checks that selected generation and
  rehashes sources. No current catalog, PDK discovery or Tcl/SDC rerender is used.
- The methodology codec fix admits only the three named optional manifest fields
  beside the closed field list, keeping bundle identity/inventory validation. Real
  native and producer-free fixture plans prepare successfully. Malformed/unknown
  declaration controls and shared coarse compatibility checks are recorded below.
- Resource observation: `verify_sources` hashes before checking the source's size,
  and methodology snapshot decode reads before the named inventory's metadata
  bound. These can do more I/O/allocation than the advertised admission limit before
  rejection. This is a bounded-I/O hardening concern, not currently a demonstrated
  accepted-evidence provenance bypass; do not conflate it with R1–R3.

## Commands / preservation

The review builds use switch5.2.0+ox, explicit `-j6`, and shared
`/tmp/opencode/asic-pt7-build.lock`. Review probes are serialized, no EDA, and C's
native allocation is separate. No B source edits, Git mutations, provider/config
changes, Workbench/Protemu changes or historical-evidence edits. Only this review
document and new `/tmp/opencode/` review scripts/products are written by this task.

## Final retained reproduction / actual checks

Final independent run:
**`/tmp/opencode/pt7-named-evidence-review-ls3ryimm/`**.

- `results.json`: **30 control groups**, consisting of81 inspector/report/public
  CLI invocations and3 API controls (captured-generation race and two methodology
  codec negatives). Fixture-construction API calls are additional setup, not counted
  in that query total. These are **executed controls**, not30 passing rejection
  tests: the unexpected acceptances are the findings above.
- `probes/<label>/changes.json` maps each mutated original absolute path to an
  independently retained changed-byte overlay under `files/`. The originals are
  restored before each next case. Both valid original fixture attempts remain
  independently inspectable at the end.
- `proofs/{rtl,config,source-copy}-closure.json` retain frozen identities and the
  declared versus actual file SHA-256s. Example config proof: declared
  `73457eef0a76a08ff28ddb1916beca592881adbb715c53ffce2c333216b8646b`, actual
  `d4d556863a1f5f6dde978aca07b45aaa5d20b62e70546863dfe35dd8fb50afb4`, unchanged
  bundle `252f08c9441e1869d5baea9f6f139ec8a1f5e322186719f93dcbd167cd5ed551`.
- Additional explicit negatives reject symlink sources, a64MiB+1 source, and
  >8MiB metadata across inspector/report/public CLI. >512-source and duplicate
  controls also reject. The512MiB aggregate cap was source-inspected; no separate
  aggregate-size execution is claimed.
- Methodology codec negatives reject an unknown manifest field and a native
  declaration change without identity rebinding. Valid native-profile2 and legacy
  preparation succeed. No general semantic validation of arbitrary malformed
  rehashed timing declarations is inferred from these controls.

Reproduction:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 test/timing_intent_execution/emitter.exe \
  test/timing_intent_execution/consumer.exe \
  bin/experimental_timing_intent_inspect.exe bin/experimental_report.exe bin/flow_cli.exe
python3 -B /tmp/opencode/pt7-named-evidence-review.py
```

Compatibility/regression command actually rerun and passed:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/timing_intent_execution test/timing_intent_flow \
  test/timing_intent_evidence test/timing_native_coverage
```

Observed groups: **97 named**, **150 coarse**, **54 schema1 +27 prior review
regressions**, **154 native-v2**. Existing suite success does not invalidate the
independent source-rebound reproductions. The plan-contract regression harness was
read but not run in this review because it performs temporary Git mutations; real
public preparation/decoding was exercised by the no-Git fixture emitters instead.

Reviewed-source SHA-256s (also retained in `reviewed-sources.json`):

| File | SHA-256 |
| --- | --- |
| `timing_intent_execution.ml` | `64cc3b8a382185a56080b8e8f2628e3fcbab2ea875b264a82ff603ab5908cb3a` |
| `timing_intent_linked.ml` | `607402a3e0d7fcd7cc58d088a412e316cc6b31042b404c5f4c36f755004087a5` |
| `stage_execution_record.ml` | `0e6f259f09d41449119eaa81f317e74d534027cb3231e2c9654a0aa8d3a5a7ce` |
| `stage_report_service.ml` | `99e27697cde271268feacde69e815f34e422d744038d8a3da35b025a7766c3d8` |
| `lib/methodology_plan.ml` | `90901bc8ae893ef62d90296c4804ec9ccfe545c6f15fdcc2a9ccb7d035dec64b` |

**Review disposition:** R1–R3 remain open in this reviewed generation. Request B
correction and independent rerun before reader qualification/closeout. C may retain
its ongoing actual execution unchanged; these findings do not turn a fixture into
native acceptance or justify edits to executed evidence/provider generations.

## Independent final verification of B corrections

2026-10-28. **No B source edits.** Rebuilt the actual current public reader/report/CLI
and fixture emitters, then independently replayed the original A controls. The
original script and all previous result directories remain unchanged.

Scripts/products:

```text
/tmp/opencode/pt7-named-evidence-review-a-final.py
/tmp/opencode/pt7-named-evidence-review-sagq7j9w/
  results.json
  correction-source overlays under probes/<label>/
  supplemental-verdict.json
  bounds-controls.json
  large-closure-proof.json
  final-verification.json
  reviewed-sources.json

/tmp/opencode/pt7-named-evidence-review-a-coarse-bounds.py
/tmp/opencode/pt7-coarse-bounds-independent-55996zky/results.json

/tmp/opencode/pt7-named-evidence-review-a-secondary.py
/tmp/opencode/pt7-named-evidence-review-ceb7gdxx/results.json
  paired mutation bytes under overlays/<label>/
```

The replay adapts only two necessary harness details: the user-authorized named
4096/128MiB limits, and deduplicating a retained frozen member now already present
in the corrected truthful fixture's source inventory. The substantive source-rebound
mutations, frozen manifest authority and original expectation/association controls
are unchanged. A did not rely on B's earlier correction-verdict assertion script.

### Verified original corrections

| Finding | Independent actual result |
| --- | --- |
| R1 frozen input authority | Original RTL/config/source-copy mutations, including fully rebound checkpoint closure/inventory/identity/reply/request/companion hashes, now reject through inspector, report and public CLI. Frozen plan/manifest/bundle identity stays unchanged. |
| R2 primary cause | Original timeout124 versus cancelled/SIGINT or exited9 contradictions now reject. Truthful timeout, exited9, SIGINT/SIGTERM cancellation, signaled TERM and launch-failed records remain readable as failed/unavailable. |
| R3 execute cleanup proof | The original reduced contradictory cleanup object rejects. Crucially, an independently constructed **full production-shaped** failed-only last removal also rejects specifically on cleanup-attempt semantics, so this is not merely a rejection of the old fixture's missing fields. Full-shaped supervisor cleanup failure rejects too. |
| R3 true retry controls | An earlier failed removal followed by actual successful removal or qualified definitive absence remains completed/unavailable with exact inspector/report/public-CLI parity. |

R1's new authority is the checked frozen methodology manifest. Each exact absolute
`project/<member>` must be in the verified source inventory, hash to the frozen
member SHA-256, and have that same hash in the promoted checkpoint external closure.
The manifest itself must match the frozen JSON and closure hash. Source-input copy
mapping must be exactly `inputs/<path>` with matching hashes. Expected bytes do not
come from a current renderer or the rebound checkpoint's own assertions.

**Same-name control:** remove the exact original RTL path from both closures and
substitute a different directory containing the **same basename and correct original
bytes**; rebind checkpoint/reply/publication/request/source hashes. All three queries
reject specifically for missing/different frozen input closure mapping. A harmless
additional same-basename file passes when the exact original mapping remains. Thus
neither a matching name nor even matching content at a different path substitutes
for the required occurrence's source association. Symlink and cross-attempt/profile
substitutions also continue to reject.

### R2S — medium: recorded analysis cleanup can still disappear from companion secondary

The primary-kind/code/signal fix is correct. However, `failure_transport` validates
only those three primary fields. It does not connect a non-null retained analysis
`transport-result.cleanup_error` to `analysis.failure.secondary`.

Independent paired controls hold all primary facts fixed and coherently rebind
source hashes:

| Actual compact analysis transport | Truthful companion primary | Matching secondary control | Empty-secondary mutation |
| --- | --- | --- | --- |
| exited9, succeeded=false, cleanup_error=`owned removal failed` | failed/9, signal null | Accepted failed/unavailable | **Also accepted** |
| cancelled2, succeeded=false, same cleanup_error | interrupted/130, signal2 | Accepted failed/unavailable | **Also accepted with secondary=[]** |
| exited0, succeeded=false, same cleanup_error | failed/2, signal null | Accepted failed/unavailable | **Also accepted** |

Each empty-secondary case returns inspector1/report0/public-CLI1 with parity. The
retained raw transport still contains the cleanup error, so this is **not loss of
the underlying source bytes or promotion of native coverage**. It is acceptance of
a companion/finalized failure summary that omits a known secondary cause. A's actual
runtime preserves those causes; the strict reader currently fails to enforce that
relationship. Controls are `dropped-cleanup-secondary-{exit9,cancel,cleanup-only}`
in the final results and their changed-byte overlays.

A separate freshly prepared fixture independently pairs the SIGINT/cleanup case:
the matching secondary passes, the empty secondary also passes, and replacing it
with a nonempty **unrelated observation warning** also passes. The original completed
baseline passes after exact byte restoration. Those three paired queries plus
restored baseline are retained in `.../pt7-named-evidence-review-ceb7gdxx/`, with
inspection/report/public-CLI parity. This distinguishes content linkage from mere
string/list shape validation.

Suggested B correction: for an unsuccessful analysis transport with a non-null
cleanup error, require the retained cleanup text to be represented in the failure's
secondary causes, while permitting additional storage/observation diagnostics. The
current compact transport joins supervisor and owned cleanup messages with `; `;
the check should preserve those contents rather than merely demand a nonempty
unrelated string. Do not turn a legitimate successful-transport/post-verification
failure into a process failure. Existing true post-runtime verification failure
and cancellation controls both pass in this review.

This is a related residual diagnostic-consistency finding, not a claim that the
original R2 primary-cause reproduction still passes. R1 and R3 remain closed for
their verified contracts.

### Named large admission verified; coarse limits not loosened

- Stat-only B precheck admits **exactly4096** distinct files and **exactly512MiB**
  aggregate (four128MiB sparse files).4097 entries reject before opening a nonexistent
  last path; a five-file640MiB set rejects. Original128MiB+1 and8MiB metadata controls
  also reject. `hashes_verified:false` correctly distinguishes this header admission.
- Independently constructed a complete final named host closure with **exactly4096
  returned source references**, an **exact128MiB file** and the **67,485,696-byte GDS**.
  Rebound candidate/promoted closure, checkpoint identity and all source associations,
  then invoked B's **real companion publisher**, not just a stat helper. Publication,
  inspection, report and public CLI pass; every additional host collateral member
  remains in the returned source inventory. This includes execution/companion
  overhead, not4096 sources followed by silently omitted metadata.
- Independent coarse controls preserve both sides of its boundary: original coarse
  evidence and an extra **exact64MiB** source pass; the named-sized67,485,696-byte GDS
  rejects on **64MiB**, and513 source entries reject on the **512-source** cap.
  Original coarse evidence passes again after restoring the companion. These are
  five actual API/public-CLI control pairs, separate from the150-case regression.
- Source inspection confirms typed named/coarse selection in the shared linked
  verifier: named uses `Timing_intent_inventory`4096/128MiB; coarse remains512/64MiB;
  both keep512MiB aggregate. Explicit metadata remains8MiB and inner native audit
  schema2/profile2 bounds are unchanged.
- Named inventory admission now precedes hash processing. Hashing is restricted to
  the admitted file length with descriptor/path inode-size-time rechecks. Opaque
  GDS/PDK collateral is hashed rather than metadata-decoded. The older bounded-I/O
  observation is addressed for this named route; no new coarse streaming semantics
  or general hostile-writer guarantee is inferred.

### Actual checks and source generation

- **30 original control groups** have the expected corrected outcomes: all original
  finding negatives reject, original true positives remain valid, historical absence
  omits the report field intentionally, corrupt presence rejects, and captured-current
  execution generation replacement rejects.
- **21 supplemental inspector/report/public-CLI groups** were executed:18 expected
  true/negative controls behave correctly; the3 secondary-cleanup omission mutations
  expose R2S. Four additional stat-only API controls and five coarse API/CLI pairs
  exercise the limits independently. Four fresh follow-up inspector/report/CLI groups
  establish the matching/empty/unrelated cancellation secondary pair and restored
  baseline. Fixture construction is separate setup, not an
  extra count of native executions.
- Both genuine prepared area/alternative-profile baselines remain valid and restored
  at the end. Native tool output is modeled. No original C run/provider/evidence is
  edited or used as a mutable control.
- Current regression command passed: `dune runtest -j6 test/timing_intent_execution
  test/timing_intent_flow test/timing_intent_evidence test/timing_native_coverage`
  under switch5.2.0+ox and the shared ASIC lock. It actually reran150 coarse,
  54 standalone and27 prior review checks; unchanged named/native actions were cached.
  Then explicitly forced `dune runtest -j6 --force test/timing_intent_execution` under
  that same switch/lock: **168 B public/API checks pass**. Independent findings are
  not relabelled as covered by that suite.

Reviewed sources, unchanged between retained original-control source capture and
the end of the supplemental verification:

| File | SHA-256 |
| --- | --- |
| `timing_intent_execution.ml` | `4c3ae35b4cdb131c5793f21032a203c8e715b442fcbe33ba685a5fbbeb8b1fdd` |
| `timing_intent_inventory.ml` | `12910edea22e0ad16e07ffec89b71253dc2200cfd82e16463e27a8eeb35d28e9` |
| `timing_intent_linked.ml` | `3d2c5cf5cf5e745e5567b40ce30caa6dd9e43fa68024b9421bee5bd282ff6c43` |
| `stage_execution_record.ml` | `3eba095590d94853e23955e2d0906b61a7dac118a25ae6a2d8c5c6db397a81c3` |
| `stage_report_service.ml` | `99e27697cde271268feacde69e815f34e422d744038d8a3da35b025a7766c3d8` |
| `methodology_execution_record.ml` | `6b1ee4a8e58f0cb57d1962f92ba6600ef6d6f1905f17332f3d620fec10808ff9` |
| `lib/methodology_plan.ml` | `90901bc8ae893ef62d90296c4804ec9ccfe545c6f15fdcc2a9ccb7d035dec64b` |

**Final disposition:** original R1, R2-primary and R3 corrections independently
verified. **R2S remains open** for full primary/secondary diagnostic qualification.
The completed named path and enlarged inventory boundary pass their positive and
source-rebound controls. C's next actual runs may be retained independently; do not
edit/relabel earlier failures or call this no-EDA verification native acceptance.
No B edits, Git mutation, provider/configuration changes, Workbench/Protemu work or
historical-evidence modifications were performed by A.

## Final R2S and declared-external-alias independent verification

2026-10-28. Reviewer A, **no B edits or EDA**. Reviewed current B source and executed
fresh independently authored mutation/assertion controls. Reused only the existing
fixture constructors to obtain genuine public prepared methodology plans, native-v2
modeled audits and validated checkpoint structures; no B assertion script or new
production Python reader was used as the independent oracle.

### Retained final products / reproducibility

```text
Main independent script:
  /tmp/opencode/pt7-b-alias-independent-a.py
Authoritative final generation:
  /tmp/opencode/pt7-named-evidence-review-ymmvj3fa/
    results.json
    verdict.json
    pinned-binaries.json
    pinned/_build/default/bin/     exact reader/report/CLI/API/emitter executables
    source-before.json / source-after.json
    verified-source-files.json
    overlays/<control>/           exact rebound metadata/checkpoint source products
    pinned-support-proof/         changed source bytes + immutable authority proof

Coarse strictness script:
  /tmp/opencode/pt7-b-alias-coarse-strict-a.py
  /tmp/opencode/pt7-coarse-bounds-independent-rq4iqfv8/results.json

Actual PDK read-only script:
  /tmp/opencode/pt7-named-alias-real-precheck-a.py
  /tmp/opencode/pt7-real-alias-precheck-a-in1dtkks/summary.json
```

Earlier `ckmfo9ht`, `kssrgat3`, `yzfrble8` and `hx_sysf7` destinations remain as
separate evolving review products. Final generation pins executable copies so C's
concurrent builds cannot change which reader a query executes. Reviewed source
hashes match before/after all controls. Original source scripts and earlier review
results were not replaced. The native boundary is modeled, not qualified tool EDA.

The final main run executes **39 inspector/report/public-CLI control groups**,
four additional public precheck controls, a direct verified-source-files equality
check and a direct companion-publication repro. **37 groups have their intended
positive/negative outcome; two accepted records reproduce the one new R4 finding**
(rebound inspection and real republishing of that same contradictory source set).
Do not describe all39 as passing negative acceptance tests.

### R2S closed — actual cleanup contents, primary preserved

For exited9, cancelled/SIGINT130 and successful-process/cleanup-only failure2, retain
the exact compact transport cleanup text:

```text
supervisor cleanup failed; owned removal failed
```

Paired truthful companions contain both causes in their qualified order, with
additional diagnostics before/after. Each is accepted failed/unavailable with exact
inspector/report/public-CLI parity and no promoted partial native coverage.

For each primary, independently remove all secondaries, substitute an unrelated
warning, retain only the supervisor cause, or reverse the two causes. All **12
source-rebound negatives reject** specifically with `cleanup error missing from
companion secondary causes`. Primary kind/code/signal remains fixed in these
controls; failure is not caused by incidental request/source hashes. This verifies
the original residual R2S content linkage, not merely a nonempty secondary list.

**Disposition: R2S closed** in the final source generation below. Original R2
primary-outcome correlation remains enforced; this review does not loosen the
separate successful-transport/post-verification failure semantics.

### Alias proof verified against exact selected checkpoint authority

The baseline contains declared file aliases, a directory alias and staged support
collateral aliases under **both** recorded allowed roots. Three distinct declared
PDK paths resolve to one identical target. Each proof row is tied to an exact
selected checkpoint external key and its recorded hash/size. All declared external
paths remain in inspection and `source_files`; source_files equals the inspector's
entire checked inventory. Native retained copies are strict canonical files.

Independent source-rebound negatives reject through inspector/report/public CLI:

- same-byte file-link retarget and same-byte directory-link retarget;
- a wrong canonical table target with identical bytes;
- wrong table hash, wrong byte count, missing row and duplicate declared row;
- alias row not present as an exact selected checkpoint external key;
- filesystem-root, ancestor-root and technology-child-root assertions replacing
  the registered authority; choosing the other allowed root for the wrong path;
- a same-byte target in a `pdk-collision` sibling (a lexical prefix is insufficient);
- removing an alias from returned sources, or from both publication and companion
  source inventories while the selected checkpoint/table still require it;
- attempted alias permission for frozen config, native audit data, native driver
  and checkpoint State—even when the rebound checkpoint external inventory is made
  to include that path with correct bytes. Metadata/internal-file/root boundaries
  reject; the alias table does not turn them into allowed collateral.

These controls preserve/rebind the relevant closure, checkpoint identity, execute
reply artifacts, finalized/publication/request checkpoint references, request hashes
and companion inventories as needed. They do not rely on a stale outer checksum.

The public stat precheck explicitly rejects an overlapping whole-PDK/technology-child
root collision as ambiguous. No-roots admission remains strict; a technology-only
root cannot authorize its sibling target. Distinct declared aliases to one target
count **3 sources/3 aliases and3 times the bytes**, not one canonical target. Extra
proof rows outside the checkpoint external inventory and duplicate declarations do
not create permission. These are explicit-root header diagnostics, not source
completeness or runtime readiness assertions.

**Disposition:** no remaining demonstrated bypass in the requested exact declared
path->canonical target/root/size/hash alias contract. Frozen bundle member metadata,
internal checkpoint and native audit rules stay strict. New R4 below concerns a
different immutable authority: a pinned external reference in the frozen manifest.

### Coarse stays strict; real PDK checked read-only

Eight independently executed coarse API/public-CLI pairs establish:

- original coarse baseline and an extra exact64MiB source remain accepted;
- the67,485,696-byte named-sized GDS and513 source entries remain rejected;
- leaf and directory source aliases remain rejected;
- adding a named `external_aliases` table does **not** open the coarse source walker;
- restoring original companion bytes restores original valid coarse inspection.

Thus named4096/128MiB and explicit external aliases have not widened coarse
512/64MiB/strict-source behavior. Inner native audit schema2/profile2 is unchanged.

The actual C `area-run-final-03/pdk-precheck.json` was rechecked read-only with
explicit canonical whole-PDK/original-support roots: **1505 original declared paths,
1062 aliases**, largest67,485,696 bytes. Every1062 alias SHA was cross-checked through
the runtime helper against B's captured table; the large GDS was hashed too.
Canonical resolutions, device/inode, sizes, mtimes/ctimes and C's inventory JSON
bytes match before/after. No alias was replaced by a diagnostic canonical-only list.
This is real path/hash evidence, **not EDA or native acceptance**; C's active native
attempts/provider/evidence were not changed.

### New B-NAMED-R4 — medium: frozen pinned external support hash is not enforced

The alias and R2S fixes work, but a separate source-authority gap remains in both
reader and companion publisher. `verify_bundle` verifies the frozen `files` and
`source_inputs` authorities; it does not compare a pinned
`target.external_references[].sha256` with the corresponding staged declared
external source/closure hash. The selected checkpoint's self-consistent external
record alone becomes authority for that byte content.

**Exact reproduction:** start from the genuine prepared baseline, with a valid
retained staged floorplan and its correct frozen pin. Keep frozen methodology,
plan identity, bundle identity, manifest, target reference and configuration
unchanged. Change only:

```text
workspace/project/tt/tech/ihp-sg13cmos5l/def/tt_block_6x4_pgvdd.def
```

Update candidate/promoted external closure records to its new SHA/size; rebind
checkpoint inventory/identity, reply artifact records, current/publication/request
checkpoint references, publication/request/transport hashes and full source
inventories. No source path is omitted, and all alias rows remain correct.

Frozen `Floorplan_def` reference SHA:
`50a08c18522cb4a0c92882bc3886cf6ba5569c8260f6542507effc7c53025072`

Actual retained/closure SHA:
`515243fb0ef3d2f0236bf2b452a244e81f427d67b0595e505355e87badf44934`

**Actual:** inspector1/report0/public-CLI1, `status=completed`, parity holds.
Deleting the companion in this private control and calling B's **real public
publisher** also succeeds; subsequent three queries remain completed/unavailable.
The writer therefore does not independently close the gap. Exact changed bytes,
reference/identity proof and publisher response are retained in
`pinned-support-proof/{changed-floorplan.def,authority.json,publisher-result.json}`.

**Truthful controls:** original correctly pinned staged floorplan passes. A rebound
*unpinned* arbitrary external collateral change also passes, as intended. Original
baseline and every declared source key are restored at the end. This isolates a
missing comparison to existing frozen authority from arbitrary collateral byte
changes, missing source data or a demand for authenticated execution.

Relevant reviewed code: `timing_intent_execution.ml:51–71` (`verify_bundle`), its
association call at219 and publisher call at461. `Inventory.validate_aliases`
correctly ties alias data to checkpoint external hash/size, but does not supply the
missing frozen target-reference pin. This reproduction uses a canonical staged
support file, so it is **not a bypass of the alias permission rules**.

**Impact/severity:** medium provenance consistency. The physical template is not
an STA timing witness; this does not demonstrate wrong native exception scope or
claim a timing-closure failure in C's actual circuit. But the source set contradicts
an explicit frozen external byte pin that ordinary preparation checks before work,
and is still labelled a completed checked named association.

Suggested B correction: map supported frozen external references to their exact
declared staged support/PDK paths using the captured recorded roots, require pinned
hashes to agree with the selected checkpoint closure and actual retained bytes,
and apply that check in publisher and reader. Keep null/unavailable pins distinct;
do not invent hashes, discover a current catalog or rerender. Preserve canonical
metadata and the explicit alias proof for any allowed external alias. Test changed
pinned bytes against the matching pinned baseline and the unpinned collateral
positive; keep coarse/historical semantics separate.

### Verification commands / generation / final disposition

All Dune calls used switch5.2.0+ox, explicit `-j6` and
`/tmp/opencode/asic-pt7-build.lock`. The final independent harness records exact
executable SHA256s in `pinned-binaries.json` and matches source hashes before/after.
No B source edits, Git mutation, provider/config changes, Workbench/Protemu work,
real PDK edits or historical-evidence modifications occurred.

Actually forced the current B/coarse regression groups:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 --force test/timing_intent_execution test/timing_intent_flow
```

Observed **215 B public/API checks**, **150 coarse** and **11 real-Tcl startup
controls** pass. The new R4 independent counterexample is not claimed covered by
that existing suite. These heterogeneous counts are not an additive native total.

Final reviewed source SHA256s:

| File | SHA256 |
| --- | --- |
| `timing_intent_execution.ml` | `495078d08651314c12330ad1e05a14797bc0645a8541f328129f45dac9d9686f` |
| `timing_intent_inventory.ml` | `ab0932981b41a3a6e964506544accf5dc1617983184812bb5d2325f06dff1945` |
| `timing_intent_linked.ml` | `8750d29de762a2b55831835a5a69af0df7f20b386e94bf7c844fd81cc80db487` |
| `stage_execution_record.ml` | `3eba095590d94853e23955e2d0906b61a7dac118a25ae6a2d8c5c6db397a81c3` |
| `stage_report_service.ml` | `99e27697cde271268feacde69e815f34e422d744038d8a3da35b025a7766c3d8` |

**Final disposition:** R2S closed; requested declared-alias/root/metadata/coarse
boundaries independently verified. **R4 remains open** for pinned external-reference
provenance, so the overall strict source review is not yet unconditionally clean.
This does not invalidate or edit C's ongoing actual products; it is a concrete
reader/publisher correction request for the recorded generation.

## Final bounded R4 correction closeout — no remaining reviewed blocker

2026-10-29. This is the requested bounded closeout, not new exploration or a broad
test campaign. No B source edits, new EDA, provider/configuration/Git changes, PDK
edits or original evidence rewrites. Existing fresh executables already exactly
matched B's tested source/binary receipt, so no Dune/build was necessary.

Read the production `verify_external_pins` implementation: it maps the supported
frozen v1 support/PDK locators to exact declared paths under captured roots, checks
non-null pin syntax/duplicate/conflicting locators, and requires both selected
external closure and actual retained bytes to equal that frozen pin. The same check
is invoked by publisher and inspector; alias-aware hashing retains declared keys.
Null pins do not acquire invented byte authority. No renderer/catalog/PDK discovery
is used to obtain expected hashes.

**Independently executed original repro and true controls:**

```text
/tmp/opencode/pt7-a-r4-bounded-closeout.py
/tmp/opencode/pt7-named-evidence-review-0byhl1zj/
  results.json / bounded-closeout.json / pinned-binaries.json
  pinned-support-proof/publisher-result.json
  pinned-alias-publication-rejection.json
```

The adapter preserves A's original script/results and changes only fixture-directory
idempotence and corrected rejection assertions. All **39 original R4/alias/secondary
control groups** have their intended outcomes. In particular, the original fully
rebound pinned floorplan now rejects inspector/report/public CLI specifically on
the frozen pin, and the real publisher refuses it. Correct original pinned data,
unpinned collateral rebound and restored baseline remain completed/unavailable.
Prior same-byte retarget/root spoof/collision, source omission, metadata/native
widening and cleanup-secondary negatives still reject; truthful controls still pass.

Added only the requested pinned-alias counterpart: a genuine strict-decoded frozen
PDK pin and matching declared alias publish/read successfully; changing its bytes
and coherently rebinding alias proof/closure/checkpoint/outer hashes while keeping
that frozen pin rejects queries and real publication. These are modeled-native
fixture controls, not additional native executions. **R4 is closed.**

**Unchanged real area/delay replay:** independently ran six read-only public queries
(inspection, entire report, source API for each original exact execution path):

```text
/tmp/opencode/pt7-a-native-final-closeout.py
/tmp/opencode/pt7-a-native-final-review-lg47ifhl/summary.json
```

Both fresh inspections equal the original accepted inspection JSON; both entire
reports equal their original accepted report JSON and contain that exact timing
value; source API returns the same1584 references. Original run trees (168 files
each), all seven checkpoint files against C's pre-STA hashes, and closeout receipt
remain unchanged. Raw publication/State/native process/log/witness/budget checks are
summarized in the companion final review. Runtime source bytes still match C's
original executed provider; R4 is a validation-only reader/publisher correction.

Verified reader source SHA256:
`1717a6813d9b299895be6c5f371ff360b610b7b94e37b2ec080f16f8ea685676`.
Fresh inspector/report/CLI/API executable hashes match B's tested receipt exactly:
`751496b3…`, `cb590e99…`, `eb10b137…`, `646a0ef2…` respectively; full hashes are in
the retained binary receipts. B's282-check suite is its reported regression, **not
re-run or relabelled as A's check**. A ran only the focused repro/true controls and
six real read-only queries above. No broad suites or EDA were launched.

**Final disposition: no remaining finding/blocker in the prior reviewed named
synthesis evidence scope.** Stored scope, diagnostics and bounded timing witnesses
do not imply exhaustive exception effects, reset/CDC adequacy, physical closure,
all-corner/post-PNR acceptance or relocatable checkpoints/named archives.
