# PT.7 named synthesis — B evidence handoff

2026-10-28. Published before implementation; updated after A/B integration.
**B implemented and ready for C's fresh named synthesis qualification.** The active
wire is A's `pt7-named-runtime-handoff.md`, adopted below; the first proposal is
retained explicitly as history. Native audit schema2/profile2 are unchanged. Named
evidence is path-bound; named archives and relocation are not supported.

Active CLI: `timing-intent-inspect EXECUTION_JSON --kind execution --json`.
Capability: `timing_intent_execution1`; native/exhaustive coverage stays unavailable.
Concrete APIs, implementation checks and C checklist follow the historical proposal.

## Active B-NAMED-R4 correction — implemented; unchanged real evidence replayed

2026-10-28. Read A's latest `pt7-named-evidence-review.md` R4 reproduction. B added
the missing frozen `target.external_references[].sha256` authority check in
both publisher and inspector. Existing supported locators only: Support_tools /
Floorplan_def maps to exact `project/tt/<path>`; Pdk (historical PDK spelling also
recognized) / known Technology_view role maps to exact recorded
`pdk_root/<frozen target.technology>/<path>`. No current target catalog, discovery,
renderer, template selection or new runtime resolution is introduced. Non-null pins
must agree with the exact selected checkpoint external key and retained source bytes;
declared PDK aliases continue to require their existing immutable proof. Null pins
remain unpinned, not invented hashes. Duplicate locators/conflicting pins reject.

This changes only B validation, not A runtime, emitted/native producer or native
schema2/profile2. C's successful area/delay executions must remain byte-identical.
Fresh current inspector/report/source-API replay against those original executions
passed, preserving their original execution provider identity. No EDA recapture was
needed. The R4 closeout below records exact results and source/binary hashes;
previous readiness predates this correction.

## Active R2S / declared external alias seam — implemented and tested READY

2026-10-28. C's real declared closure has1062 noncanonical paths. Bounds alone
did not qualify that input; previous READY did not cover this actual alias policy.
B corrected R2S and implemented/tested the following explicit, named-only seam.

**Agreed with A and integrated:** optional `publication.external_aliases`
is an array of exact rows:

```json
{"path":"<original declared external closure key>",
 "target":"<resolved canonical regular-file target>",
 "root":"<allowed canonical collateral root>",
 "sha256":"<target/declared bytes SHA256>","bytes":193}
```

Allowed runtime roots are exactly the canonical `request.pdk_root` and canonical
`request.project/tt` (staged support collateral). The PDK root is the **whole PDK
directory**, not the ihp-sg13cmos5l child: its declared aliases legitimately resolve
into sibling ihp-sg13g2 under that same root. Each row must be an exact noncanonical
**checkpoint.external** key with matching recorded hash/byte count; metadata,
bundle members, checkpoint views and native audit files never gain alias permission.
No broad filesystem root or caller-supplied table root can replace that authority.

A should capture this table from the completed checkpoint external inventory
**before STA/publication**, keep every original `sources[].path` and external closure
key (no target deduplication or rewriting), and recheck exact resolution/hash/size
before and after analysis. B's publisher consumes/preserves that immutable table;
it must not regenerate a different association after execution. Old canonical-only
publications may omit it. A's native helper must validate the same named table
before/after its source checks/copies; any original external Liberty/collateral alias
read must use its recorded row. Retained copies and all audit/metadata paths remain
strict regular/canonical files. Coarse receives no alias relaxation.

B API signatures for A (published before implementation; now available):

```ocaml
Timing_intent_inventory.capture_aliases : roots:string list -> paths:string list -> alias list
Timing_intent_inventory.aliases_to_json : alias list -> Evidence_json.t
Timing_intent_inventory.aliases_of_json : Evidence_json.t -> alias list
Timing_intent_inventory.validate_aliases : roots:string list ->
  external_files:(string * Checkpoint.file_record) list -> alias list -> unit
Timing_intent_inventory.hash : ?aliases:alias list -> string -> string
Timing_intent_inventory.admit_paths : ?aliases:alias list -> ?external_roots:string list ->
  string list -> usage
Timing_intent_execution.precheck_sources : ?external_roots:string list ->
  paths:string list -> unit -> (Evidence_json.t,string) result
```

Precheck without roots stays strict. With explicit canonical collateral roots it
returns stat-only declared->target associations (no hash claim); it counts/charges
**every distinct declared path**, including two aliases to the same target. Runtime
capture hashes the recorded associations. Limits4096/128MiB/512MiB and inner audit
bounds stay fixed; no archive/relocation scope is added. A has adopted this exact
seam; tested readiness is recorded in the R2S/alias closeout below.

## Active correction seam — B-NAMED-R1/R2/R3 and native closure bounds

2026-10-28. **Corrections implemented and tested; B ready for C's fresh capture.**
The tested correction closeout below supersedes the earlier generation. User-authorized **named outer** inventory limits are
4096 sources, 128MiB/source, 512MiB total. Inner native audit limits and coarse
512-source/64MiB-source limits remain unchanged. The actual conservative PDK
closure (1486 files, largest 67,485,696 bytes) must remain complete; do not filter
it to loaded Liberty or omit large physical collateral. Named publication and
reader use the same admission/hash limits and bounded traversal. C must precheck
the full closure plus bundle, checkpoint, analysis and metadata overhead before
launch. A/B will record a concrete public no-EDA precheck seam below.

A's early-durability correction may add optional `timing_intent` to its retained
preflight/native **request** and reference-bearing report/receipt before probes.
Use the exact existing version1 expectation object, preserving attempt/occurrence/
profile/deterministic paths, and carry that identical value into Runner. No change
to the finalized Runner expectation or native schema2/profile2 is needed. B's
strict final execution decoder remains unchanged; optional preflight metadata is
not a second authority or fabricated execution record. A owns its writer/query
plumbing and failure retention; B will coordinate any concrete schema need in its
reader after A publishes the update.

Consumed A's active correction seam: immutable early
`timing-intent-expectation.json`, with additive preflight `timing_intent` and
`timing_intent_snapshot:{path,sha256}` in report/receipt/request. B agrees these
metadata extensions; the finalized Runner expectation remains unchanged.
For explicit final linkage (without scanning preflight stores), **publication.json
may optionally add `timing_intent_snapshot:{path,sha256}`**. When present, A includes
that exact early snapshot in publication.sources and passes its original recorded
reference; B verifies its hash and exact equality with final expectation. Absence
retains the original named schema1 publication semantics and does not assert early
durability. No optional field is added to the native audit or final analysis request.

R1 correction requires every frozen manifest member (including RTL, source copies,
config, SDC and producer) in the outer inventory and in the published conservative
checkpoint closure with the manifest's original hash. Source-copy entries are
cross-checked against their inventoried copy. Runtime's real `closure()` already
includes all bundle members and manifest; synthetic A runtime fixtures must retain
that truthful closure too (an unrelated `/nix/store/fixture-runtime` alone cannot
substantiate the frozen inputs). B's publisher will inventory and verify all staged
members. No current renderer/source checkout is used to supply expected bytes.

## Historical first proposal — superseded by A's active wire

### Persisted Runner expectation (A writer, B strict decoder)

Optional top-level `timing_intent` on the Runner record is exactly:

```json
{"contract":"hardcaml-asic.timing-intent-expectation","schema_version":1,
 "attempt_id":"ATTEMPT","occurrence_id":"ATTEMPT/implementation.synthesis",
 "profile":"opensta-2.7-native-state-v2",
 "directory":"/canonical/workspace/timing-intent/ATTEMPT"}
```

Persist before execution. Omit for legacy records. Directory is an absolute
canonical lexical path (it need not exist before synthesis). Only fresh named
synthesis is supported. The frozen methodology manifest independently advertises
the requirement; removing expectation alone does not make evidence optional.

### Immutable publication association (historical proposal)

A publishes `DIRECTORY/publication.json` once after promotion, before analysis.
Exact fields:

```text
contract: hardcaml-asic.timing-intent-publication
schema_version: 1
attempt_id, occurrence_id
plan: exact Runner stage plan JSON
methodology: exact checked methodology reference JSON
expectation: exact timing_intent expectation
checkpoint: exact Runner synthesis artifact reference JSON
request: {path,sha256} execute-segment request
reply: {path,sha256} execute-segment reply
transport: {path,sha256} execute-segment launch
terminal: {path,sha256} execute-segment terminal
```

All references here are canonical absolute regular files, path-bound. This binds
the immutable publication, not a hash of the mutable Running occurrence. Reader
compares the finalized execution's exact attempt/plan/methodology/expectation and
synthesis checkpoint with this record. At publication the occurrence is Running;
the reader permits completed, failed or interrupted synthesis when publication is
retained, never unreached. Validation-publication calls cannot substitute for the
execute-segment invocation.

### Linked runtime seam (historical proposal)

Use explicit retained synthesis config/state/netlist/resolved references selected
from the published checkpoint and its segment's exact returned producer position.
Do not construct a coarse run record. B will expose a named companion publisher
and reuse the existing linked native/source/path/library/process verifier through
a distinct named association adapter. The runtime handoff must freeze concrete
request/runtime-result fields before this part is integrated.

Proposed `request.json`: existing linked request schema1 common fields
`build_identity`, `manifest_sha256`, `analysis_id`, `execution_root`, `host_uid`,
`host_gid`, `binding`, `pdk_root`, `helper_sha256`, `producer_sha256`, plus
`publication:{path,sha256}`; no invented coarse `run_id` or coarse command.
`execution_root` is the canonical workspace. Analysis files reside in DIRECTORY.
Use `analysis_id=ATTEMPT/named-synthesis-sta`. Runtime result binds that analysis ID
and exact publication, synthesis sources, requested/executed default corner and
audits. Native audit `audit_id` equals analysis ID.

### Initial B API proposal

```ocaml
Timing_intent_execution.inspect : execution:string -> unit -> (Evidence_json.t,string) result
Timing_intent_execution.source_files : execution:string -> unit -> (Evidence_json.t list,string) result
```

A checked captured-snapshot entry point will take execution path, exact raw bytes
and decoded/validated checkpoint snapshot for report parity, without rereading a
different execution generation. Publisher writes `DIRECTORY/analysis.json` once,
inventories all required sources, preserves failed attempts and never mutates
checkpoint files. Concrete signature will be recorded below before A integration.

Explicit CLI `timing-intent-inspect EXECUTION_JSON --kind execution --json` accepts
only an exact execution file. Valid evidence (including truthful failed/unreached
states) returns unavailable/exit1; corrupt/missing required evidence returns exit2.
Legacy report shapes remain unchanged. New named report `timing_intent` equals the
explicit inspector's checked value. Source inventory is verified and bounded;
no named archive/hidden-root restoration claim follows.

## Implementation status

### A/B agreement — runtime wire adopted

A's concurrently published `pt7-named-runtime-handoff.md` freezes a more complete
wire. **Its exact expectation/publication/request/result/analysis spellings
supersede the proposed wire above. B adopts that wire**, including `kind` (not
`contract`), explicit expectation paths, embedded publication request/reply/segment
and absolute source inventories. Analysis ID is `ATTEMPT/pre-pnr-sta`. No native
schema/profile change. B will decode these exact objects and adapt only common
linked validation inputs in memory; no coarse record is generated or persisted.

Publication API for A (B-owned):

```ocaml
Timing_intent_execution.publish :
  directory:string -> succeeded:bool -> failure:Identity_json.t -> unit -> unit
```

Reads immutable publication/request already written by A. Inventories the analysis
directory (excluding analysis.json/toolbox), publication sources, exact manifest,
SDC/producer and runtime-result synthesis refs when present. Failure is null on
success, otherwise A's exact failure object. Exclusive atomic publication. A may
invoke the public inspector only after the Runner occurrence has been finalized;
it must not require the finalized reader at Published while occurrence is Running.

Captured report API (B-owned):

```ocaml
Timing_intent_execution.inspect_snapshot :
  execution:string -> execution_sha256:string -> raw:Identity_json.t ->
  record:Stage_execution_record.t ->
  checkpoints:(string * Checkpoint.t) list -> unit ->
  (Evidence_json.t option,string) result
```

None means historical producer-free/no-expectation/no-companion (legacy reports
omit field); explicit inspect converts that to historical unavailable. Both paths
use the same checked snapshot and reader. Companion sources are absolute and
path-bound, not relocated or coarse archive sources.

### Integration finding for A/coordinator

B's first real named bundle fixture fails **before runtime** in
`lib/methodology_plan.ml:163–185`: `verify_associations` accepts optional
`resource_snapshot` but omits the new identity-covered `timing_intent` and
`timing_native_coverage` manifest fields. `Methodology_plan.prepare` therefore
raises `object fields do not match versioned schema` on a genuine PT7 bundle.
This main-library gate needs the narrow optional-field compatibility update before
either A or B can exercise genuine named fixtures. B applied the minimal unowned
main-library compatibility fix: add only the two known optional identity-covered
fields beside resource_snapshot; keep the closed field schema and normal bundle
identity/inventory validation. No A/runtime files were edited. Coarse/native/schema1
regression remains passing.

## Implemented evidence and source validation

- `Timing_intent_execution.{inspect,inspect_snapshot,source_files,publish}` reads
  A's exact version1 expectation/publication/request/companion. The publisher uses
  exclusive atomic link publication, rehashes original publication sources, retains
  native producer config/State/netlist even on a failed analysis, and includes the
  frozen methodology snapshot and checkpoint external host closure.
- `Stage_execution_record` strictly decodes the optional expectation, exact paths,
  attempt/occurrence/profile and fresh named schema4 synthesis-only plan. Shared
  `validate_snapshot` retains the exact checked checkpoint manifests, inventoried
  segment bytes and resolved/shared-file checks for report and inspection callers.
- Named association checks finalized execution against the immutable Running
  publication: exact plan/methodology/expectation/checkpoint; execute-segment
  request/reply/launch/terminal (never publication-validation); full generated
  Docker argv and six-worker fields; fresh exact run; exact returned producer
  position/metadata; candidate/native State equality; candidate/promoted config,
  closure and segment; published/native netlist bytes; and actual published State
  as the supplementary Step input.
- The common existing linked reader moved to `Timing_intent_linked`; coarse
  `Timing_intent_flow` remains its coarse adapter. Named association passes an
  explicitly typed named context and common source-envelope projection, **no
  coarse run object, run ID, coarse synthesis argv or coarse directory is invented**.
  The existing native audit reader, LF grammar, ordered library/Tcl-list decoder,
  source paths, process/cleanup, exact analysis argv, corner/config and native
  profile/version checks are reused. Failed analyses do not interpret partial audits.
- `Stage_report_service` captures raw execution bytes and their hash, validates
  that generation and calls `inspect_snapshot`; source hashes/checkpoint inventory
  and execution generation are checked before returning. It does not reload a
  different execution to obtain timing evidence. The same checked value appears in
  explicit inspection and named report `timing_intent`. Minimal generic synthesis
  timing inspection also invokes this strict verifier before supplementary browsing.
- Independent expectation or frozen/staged bundle advertisement requires evidence.
  Producer-free historical records omit the report field. A genuine finalized
  unreached/pre-publication failure returns `not_produced`, retained failed analysis
  returns `failed`; both have unavailable coverage. Missing publication/companion
  after promotion, changed sources or malformed present evidence reject, never
  downgrade. All valid explicit inspections remain exit1; invalid queries exit2.

The original generation used <=512 sources / <=64MiB each; the active named outer
contract is now **<=4096 sources / <=128MiB each / <=512MiB total**, metadata <=8MiB;
inner audit bounds also apply. Directory enumeration
and inventory traversal are bounded. Source digest binds the companion closure and
exact selected execution generation. Named source_files is a **verified path-bound
inventory**, not archive/export or hidden-original-root replay. Hashes remain local
producer assertions, not authenticated execution. Conservative checkpoint external
closure participates in these limits; do not silently omit sources to fit a run.

## Verification and C readiness

All Dune calls used switch `5.2.0+ox`, explicit `-j6`, shared
`/tmp/opencode/asic-pt7-build.lock`. No EDA or provider capture/activation was run.

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/timing_intent_execution test/timing_intent_flow \
    test/timing_intent_evidence test/timing_native_coverage
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @install @test/ocaml-stage-report @test/inspection \
    @test/ocaml-report @test/flow-cli @test/plan_contract/runtest
```

Isolated B suite currently passes **97 public/API checks** over actual prepared
named plans/bundles/checkpoint validators and modeled native output. Includes
explicit public CLI/capability, inspector/report equality, verified source_files,
coherent actual second-attempt/alternative-profile/publication substitutions,
Running versus finalized publication, execute-versus-validation substitution,
producer metadata/position mismatch, exact published/native State, wrong corner,
six-worker/duplicate CPU argv, cleanup truth, source duplicates, expectation
downgrade, missing companion, captured-execution race, truthful timed-out analysis,
failed/interrupted/unreached before publication, and historical named absence.
Initial/final public queries preserve source bytes/size/mtime. Fixtures are not
native acceptance. Final focused run below records any added checks.

Compatibility checks pass: coarse **150** orchestration/replay checks; standalone
schema1 **54 + 27** review checks; native-v2 **154** pure checks; report **585**
differentials plus **43** policy tests; **15** CLI tests; stage-report and inspection
aliases; **108** plan-contract checks; install packaging build. Counts describe
different test groups and are not an additive native acceptance count. Unchanged
dependencies may be cached. One short build command window expired while work was
serialized; the later 900-second-window commands completed normally.

C: capture the current combined provider and fresh named synthesis bundle/plan;
use A's ordinary `stages --methodology-plan ...` route and returned exact
execution_file. Inspect with `--kind execution` (expect exit1, completed/unavailable),
then report and compare exact `timing_intent`. Verify checkpoint bytes unchanged,
actual native-v2 six relations/seven categories/12 endpoints and downstream hold
witnesses for the real five-stage specimen. Retain original process/cleanup/runtime,
ordered library and source inventory. Do not infer all-corner, post-PNR, exhaustive
effect, reset-release safety or timing closure. B has no remaining implementation
blocker for this stated path-bound reader slice; real C qualification is pending.

## B-NAMED-R1/R2/R3 correction closeout — ready for fresh C qualification

Read A's `pt7-named-evidence-review.md` and its source-rebound reproductions.
Implemented all three findings without editing A's review, runtime/lifecycle files,
old providers, C attempts or retained native products.

### R1 — frozen member/copy/config authority

The reader **and publisher** now obtain the expected manifest from the checked
frozen methodology, not an independently rehashed closure. Every inventoried staged
member must exist in the outer inventory, hash to that frozen member's exact hash,
and occur with the same hash in the published conservative external input closure.
The manifest itself must also match its frozen JSON and closure reference.
`source_inputs` entries must identify their exact `inputs/<path>` inventoried copy
and matching original declared hash. Original generator checkout paths are never
read, and no renderer or current catalog supplies expected bytes.

Durable controls mutate RTL, config/CLOCK_PERIOD, source-input copy, SDC and native
producer bytes while preserving frozen plan/manifest/bundle. They coherently rehash
both closures, checkpoint inventory/identity, execute reply artifacts, finalized
and immutable publication checkpoint references, request/transport references and
outer source inventories. Both inspection and report reject for the intended frozen
member mismatch. A truthful rebound unrelated collateral closure remains readable.

### R2 — failed transport and claimed primary cause

After the existing closed compact transport validator, unsuccessful analysis
transport must match companion/finalized occurrence kind/code/signal:

| Recorded transport | Required primary |
| --- | --- |
| timed_out/null | failed/124, signal null |
| cancelled/S | interrupted/(128+S), signal S |
| signaled/S | failed/(128+S), signal null |
| exited/N, N>0 | failed/N, signal null |
| failed/null | failed/2, signal null |
| exited/0 with failed cleanup | failed/2, signal null |

A successful transport may legitimately be followed by failed runtime/input
verification, cancellation during that verification, or publication failure. That
separate path remains readable as failed/unavailable and never interprets partial
native evidence. Timeout-claimed-as-cancel/exit9/signal/failed negatives reject in
both queries; truthful timeout, SIGINT/SIGTERM cancellation, signaled/nonzero/failed,
cleanup-only and successful-transport/post-verification controls pass.

### R3 — actual owned cleanup proof

New advertised named execute evidence requires the full production process fields
and owned cleanup `{error,attempts}` record. Process status/code/error, child status,
PID, finite elapsed duration, paths and cleanup-error shape are validated. A null
cleanup summary alone is insufficient: the nonempty, bounded removal sequence's
last attempt must substantiate successful removal or the exact qualified transport's
definitive-absence diagnostic. Earlier failed attempts followed by real success or
absence remain valid. Failed-only attempts, absent proof, contradictory child or
supervisor cleanup status reject. This tightens the new named boundary only; legacy
producer-free shapes and coarse contracts are preserved.

### Named outer bounds / streaming admission

Shared `Timing_intent_inventory` centralizes **4096 distinct sources, 128MiB each,
512MiB aggregate**. Metadata remains8MiB. Files are stat-admitted before hashing;
hashing streams exactly the admitted length with inode/size/time rechecks rather
than reading opaque collateral whole or scanning an unbounded growing EOF. Named
checkpoint host closure is admitted before strict checkpoint validation hashes it.
Methodology snapshot reads reject >8MiB before allocation. Publisher traversal has
matching source/directory/count/byte bounds, retains every required host external
and frozen bundle member, and includes execution/companion overhead in final bounds.

The common linked verifier selects named versus coarse outer limits explicitly.
**Coarse remains512 sources /64MiB each /512MiB aggregate.** Inner schema2/profile2
native role/byte/token/endpoint limits are unchanged. No named archive, export,
relocation or hidden-original-root replay is added.

Installed capability `timing_intent_execution1.outer_inventory` reports the limits.
Public stat-only precheck:

```ocaml
Hardcaml_asic_execution.Timing_intent_execution.precheck_sources
  ~paths:complete_existing_required_absolute_paths ()
(* Ok {source_count,total_bytes,largest_bytes,limits,...,hashes_verified:false} *)
```

C should enumerate the **complete conservative PDK/host closure** and existing
bundle/checkpoint/metadata inputs, deduplicating exact paths, and use this API (or
A's matching stat-only helper) before an actual launch. Account for future mapped
views/analysis reports/metadata in the remaining4096-source/512MiB budget; this is
admission of the supplied paths, not proof of completeness or a readiness verdict.
Final publisher/reader admission covers the entire actual union including their
metadata overhead. Image-only `/nix/store/` dependencies keep their established
exact-image association; no required PDK/host collateral may be omitted or reduced
to loaded Liberty to fit bounds. Actual retained sources remain path-bound.

The suite publishes/inspects/reports a full **1486-file** conservative fixture
closure including a **67,485,696-byte** GDS and verifies every member remains in
`source_files`. Exact4096 stat admission passes;4097 count,128MiB+1 and >512MiB
aggregate controls reject. The aggregate/oversize controls use sparse actual files
and deliberately wrong hashes to prove admission rejects before digest processing.
Large-file hashes use streaming blocks. These are fixture acceptance controls,
not C's actual PDK/native production.

### A early-durability coordination

Consumed A's updated runtime handoff: optional preflight/report/receipt/request
`timing_intent` and `timing_intent_snapshot` are additive, pending request metadata,
not completed execution evidence. Existing finalized expectation schema stays fixed.
The optional publication `timing_intent_snapshot` link described above is implemented
and tested: original schema1 absence passes; a supplied reference must be inventoried,
hash-match its file and decode to exactly the final expectation. A currently retains
its early snapshot through preflight metadata without requiring that optional final
publication field. C checks those actual early fields separately; final inspection
does not infer early durability merely from their absence.

### Actual verification

All Dune invocations used switch5.2.0+ox, explicit `-j6`, and
`/tmp/opencode/asic-pt7-build.lock`. No EDA or provider capture/activation was run.

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/timing_intent_execution test/timing_intent_flow \
    test/timing_intent_evidence test/timing_native_coverage
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @install @test/ocaml-stage-report @test/inspection \
    @test/ocaml-report @test/flow-cli
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @install @test/timing_intent_named_runtime/runtest \
    @test/timing_intent_named_runtime/core
```

- **168** durable B public/API checks pass, including correction negatives and
  truthful controls, optional early snapshot, full enlarged closure, public query
  parity and the original named association/legacy controls.
- Replayed A's independently authored review through a new adapter at
  `/tmp/opencode/pt7-named-evidence-review-b-corrected-bounds.py`. Its only harness
  changes are the user-authorized4096/128MiB limits and deduplicating a retained
  frozen member now already inventoried by the truthful constructor. Original A
  script/results remain unchanged. New results:
  **`/tmp/opencode/pt7-named-evidence-review-e9lg22xn/`**. All **30 control groups**
  have expected outcomes, including all three original unexpected acceptances now
  rejecting and positive controls retaining inspection/report/public-CLI parity.
  `correction-verdict.json` records this checked disposition. Historical absence
  intentionally omits the report field and is not mislabeled as a parity defect.
- Compatibility passes:150 coarse controls,54 schema1 +27 prior review controls,
  154 native-v2 controls; stage report/inspection aliases;585 report differentials,
  43 policy tests and15 CLI tests; install build. A runtime/core aliases also pass
  against the integrated reader (unchanged dependencies may be cached). No native
  acceptance is inferred from these heterogeneous counts.
- `git diff --check` passes. Dirty PT7c/named baseline and original failed C attempts
  are preserved. Do not fill in an old failed companion or relabel its provider.

**B ready for C's fresh actual named synthesis/STA and independently captured
corrected reader.** Use the exact returned execution JSON with `--kind execution`,
expect completed/unavailable exit1, verify report `timing_intent` equality, full
external closure and large-GDS retention, early preflight expectation, checkpoint
hash preservation and actual native-v2/downstream witnesses. Overall exhaustive
effects, reset-release safety and timing closure remain unavailable.

## R2S and actual declared PDK aliases — tested final B closeout

2026-10-28. **B READY for C's fresh combined-provider capture**, with A's adopted
runtime alias proof seam. This section supersedes the earlier canonical-only
external-file policy and its incomplete readiness claim. Original C blocked
captures/prechecks, providers, plans and PDK bytes are unchanged.

### R2S secondary consistency

For a failed analysis with non-null `transport-result.cleanup_error`, the strict
reader now requires that exact recorded cleanup content in the companion secondary
causes. It compares against the qualified `; ` concatenation of secondary entries,
preserving supervisor/owned cleanup order and contents while allowing additional
storage/observation causes before or after them. A nonempty unrelated warning is
not evidence for the missing cleanup cause. The existing primary kind/code/signal
checks remain, and successful-transport/post-verification failure stays supported.

Durable inspection/report pairs cover exited9, cancelled/SIGINT and cleanup-only
exited0, each with matching supervisor+owned cleanup content and additional truthful
diagnostics. Empty, unrelated and partial secondary lists reject. Replayed A's
original paired reproduction via a new expected-outcomes adapter, preserving the
original script/results:

```text
/tmp/opencode/pt7-named-evidence-review-b-secondary-correction.py
/tmp/opencode/pt7-named-evidence-review-c5d56so0/results.json
```

The matching secondary remains failed/unavailable with inspector/report/public-CLI
parity; empty and unrelated secondary cases now reject in all three queries; the
restored completed baseline passes. These are fixture controls, not native runs.

### Explicit alias proof; original closure is authoritative

The active wire and APIs at the top of this file are implemented. New immutable
publication `external_aliases` rows bind **declared path, exact canonical target,
allowed canonical root, SHA256 and byte count**. Rows are permitted only for exact
checkpoint external keys with matching recorded hash/bytes. Allowed runtime roots
come from the captured checkpoint/execute request: whole canonical `pdk_root` and
canonical `project/tt`. These root fields must agree with the originating execute
request, rather than an arbitrary root asserted by a row.

Every noncanonical declared external requires a row. Extra/out-of-closure rows,
duplicate declarations, wrong roots, wrong targets even with identical bytes, and
targets outside the allowed canonical root reject. Publisher consumes the table
captured before execution and **never regenerates a new target association after
STA**. It preserves all original source and checkpoint external keys. Reader hashes
each declared path through its bound target, checking exact resolution and stable
descriptor/path identity before and after each bounded streaming hash, then rechecks
the full association before returning. Final generic supplementary inspection also
rechecks the captured alias table after its normal source hash checks.

Canonical metadata, frozen bundle members, internal checkpoint files, helper/
driver/hook, native retained inputs and audits **stay strict**. The common native
verifier sees strict retained copies; original external alias sources are validated
in the complete named outer inventory, not fed through its strict member-path
walker. This is an explicit internal projection, not an omitted source: all aliases
remain in returned `sources`/`source_files` and in `association.external_aliases`.
No coarse path rule or native schema2/profile2 rule is relaxed.

Bounds count **distinct declared keys**, not distinct targets:4096 sources,
128MiB/source,512MiB aggregate. Several declared aliases to the same file each
consume their own count and byte charge. Image-only `/nix/store/` retains its
existing image association; this does not remove any required host PDK collateral.

### C precheck change required — explicit roots, no path rewriting

The old no-roots call remains intentionally strict. C's public adapter must pass
the selected canonical collateral roots with the **unchanged complete declared
input list**, e.g. for the existing toolchain:

```ocaml
Timing_intent_execution.precheck_sources
  ~external_roots:[ canonical_pdk_root; canonical_original_support_tools_root ]
  ~paths:original_declared_paths ()
```

For actual runtime, A binds PDK to that selected canonical PDK directory and
support collateral to its staged canonical `project/tt`. A precheck's original
support-tools root does not become runtime authority automatically. It is merely
explicit header admission of those existing selected inputs. Do not pass a
technology-child root for the PDK: the actual CMOS5L aliases resolve into sibling
ihp-sg13g2 under the **whole PDK root**.

Precheck returns `source_count`, byte totals/limits, `declared_alias_count`, and
stat-only `external_resolutions` rows (path/target/root/bytes). It verifies resolution
and source headers remain stable across admission. `hashes_verified:false` remains
truthful. Those rows are not hashed publication evidence; A's `capture_aliases`
creates the separate SHA-bound immutable table before native analysis. Capability
`timing_intent_execution1.external_aliases` advertises
`contract=declared_external_collateral_target_v1`, explicit-root precheck and
declared-path accounting. No new CLI target kind or archive scope is introduced.

### Read-only check of the real existing PDK and C input list

Executed only the public B precheck/hash-capture APIs, without changing C code or
launching tools, against C's original `area-run-final-03/pdk-precheck.json`:

```text
Script: /tmp/opencode/pt7-named-real-pdk-alias-check.py
Final products: /tmp/opencode/pt7-real-pdk-alias-vot8fyaz/
Earlier retained products: /tmp/opencode/pt7-real-pdk-alias-2vsydggt/
```

- **1505 declared paths admitted,1062 declared aliases retained**,165,534,478 bytes
  charged and largest67,485,696 bytes. No canonical-target deduplication replaces
  that list. These totals include C's supplied bundle/plan/support paths, not only
  its PDK-only165,433,805-byte subtotal.
- The exact real declared witness
  `.../_flow_tools/pdk/ihp-sg13cmos5l/libs.qa/README.md` is accepted with explicit
  whole-PDK root and SHA-bound to
  `.../_flow_tools/pdk/ihp-sg13g2/libs.qa/README.md`,193 bytes,
  SHA256 `70d0ec733ba0670ff1a0ac8f416121b48b564dab763cd8979e2b0af822725265`.
- Default strict admission still rejects that alias. A tech-only root rejects its
  sibling target. All supplied path resolutions, target sizes/mtimes, witness bytes
  and original C inventory bytes match before/after. The full list check is stat
  admission, not a claim that all1505 source hashes were verified or EDA ran.

### Durable synthetic proof and integration

B's named suite now passes **215 public/API checks**. Alias controls include file
and directory aliases, staged support collateral, multiple declared aliases with
identical targets/bytes, exact source counts/byte charges, real companion publication,
inspection/report/source_files parity, and unchanged declared checkpoint closure
keys. Identical-byte link retarget, incorrect identical-byte table target, outside
root, outside closure, wrong root, missing/duplicate association and native audit
symlink controls reject. Failed companion-secondary omission controls have paired
truthful positives. All use the existing native-v2 library reader, not a new native
parser or rerender.

All Dune commands used switch5.2.0+ox, explicit `-j6`, shared
`/tmp/opencode/asic-pt7-build.lock`:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @install @test/timing_intent_execution/runtest \
    @test/timing_intent_flow/runtest @test/timing_intent_evidence/runtest \
    @test/timing_native_coverage/runtest @test/ocaml-stage-report \
    @test/inspection @test/flow-cli
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @install @test/timing_intent_execution/runtest \
    @test/timing_intent_named_runtime/runtest @test/timing_intent_named_runtime/core
```

Observed passing groups:215 B named,150 coarse,11 Tcl startup,54 standalone +27
prior review,154 native-v2, stage-report/inspection and43 CLI policy checks; install
builds. Integrated A actions pass **30 named runtime cases**, including a full
1486-declared/1062-alias PDK proof and GDS, alias-library native copies,
before/after/post-runtime same-byte retarget and metadata-link rejection;10 outer
admission controls;7 native-core model cases. These are heterogeneous fixtures, not
native qualification or an additive execution count. A adopted this B contract
in its runtime handoff; B did not edit A-owned files.

**C next:** capture the current combined provider, update the precheck adapter to
pass explicit roots and inspect its full declared result, then run fresh sequential
named attempts through normal public stages. Do not patch an old failed attempt,
canonicalize its closure keys, omit duplicate targets, or replace a checkpoint.
Verify actual `association.external_aliases`, full sources and stable checkpoint,
native-v2 relations/diagnostics/endpoints and downstream witnesses. Named evidence
stays path-bound; native acceptance and timing closure remain unestablished until C
supplies the corresponding real products. B's alias/secondary implementation is ready.

## B-NAMED-R4 closeout — frozen external pin validation; no new EDA

2026-10-28. Implemented the external-pin correction in **publisher and inspector**.
The same `verify_bundle` seam now checks the frozen target references in addition
to manifest members/source-input copies. No A runtime/lifecycle/Python/native
producer, receipt schema or audit profile changed. This is a reader/publisher
validation-only correction; C's already accepted area/delay executions remain their
original executions.

### Exact supported locator contract

Only the existing v1 frozen source locators are interpreted:

| Frozen source / role | Exact declared retained location |
| --- | --- |
| `Support_tools` / `Floorplan_def`, corner null | `WORKSPACE/project/tt/<reference.path>` |
| `Pdk` (historical `PDK` spelling normalized) / supported `Technology_view` role | `<checkpoint recorded pdk_root>/<frozen target.technology>/<reference.path>` |

The supported technology roles are `Pdk_configuration`, `Technology_lef`,
`Standard_cell_lef`, `Standard_cell_gds`, `Standard_cell_verilog` and
`Standard_cell_liberty`, using their existing frozen sexp-string wire spellings.
Source/role pairs, safe relative paths, corner shape, reference fields and pin
SHA256 syntax are checked. Roots come from the exact selected checkpoint/context;
the staged project must equal the selected execution's project. No current target
catalog, directory search, basename match, renderer or new target-resolution
operation supplies authority.

For every **non-null** frozen pin, that exact declared path must be a selected
checkpoint external-closure key, be present in the verified source inventory, and
have both its closure hash and actual retained bytes equal the frozen SHA256.
This applies to valid PDK/support aliases using their existing exact immutable
path->target/root/hash/size proof; it does not canonicalize or replace the locator.
Null pins remain explicitly unpinned and trigger no invented byte pin or fresh
lookup of that reference's input. Existing complete closure verification still
applies to retained sources independently.

Duplicate normalized `(source,role,path,corner)` locators reject. Conflicting
non-null pins for the same mapped declared path reject even when supplied through
different role/corner rows. Missing exact closure keys, unsupported source/role
locators, and closure/actual-byte pin contradictions have distinct diagnostics.
Correct bytes at a different path with the same basename cannot substitute for the
frozen locator. No coarse or producer-free historical semantics are widened.

### Durable verification

The isolated suite now passes **282 public/API checks**. R4 additions exercise:

- the original changed-floorplan reproduction with frozen plan/manifest/bundle
  unchanged and candidate/promoted closure, checkpoint identity, execute reply,
  finalized/publication/request references, transport hashes and source inventories
  coherently rebound: inspection/report and real companion publisher reject;
- a closure that still repeats the correct pin while actual bytes differ: the
  existing strict checkpoint reader rejects its changed external dependency, and
  publisher rejects specifically on retained-byte versus frozen-pin mismatch;
- missing exact support locator, including correct original bytes under the same
  basename in another directory: no path/hash fallback;
- duplicate equal-pin reference, conflicting pin, wrong source and wrong role
  locators through publisher and complete hash-consistent negative companion reads;
- a correctly pinned original staged template and a truthful null-pinned template
  change, both with public inspection/report parity;
- a pinned PDK reference through a legitimate declared alias, followed by changed
  bytes with coherently updated alias proof/closure/outer hashes while the frozen
  pin remains original: the positive passes and both publication/queries reject
  the contradiction.

The additional reference-authority fixture helper uses the public main-library
identity algorithms and strict `Methodology_plan` decoder to construct explicit
frozen-wire controls. It is test-only, not a new production native/target parser.
Existing unpinned arbitrary-collateral rebound and alias/secondary controls pass.

Replayed A's independent R4/alias/secondary script via a new adapter:

```text
/tmp/opencode/pt7-b-r4-correction-replay.py
/tmp/opencode/pt7-named-evidence-review-gax68yo0/results.json
```

Original A script/results are unchanged. Adapter changes are only fixture directory
idempotence (the truthful constructor now already stages floorplan collateral) and
the corrected R4 rejection assertions. **39 control groups** have their expected
outcomes. The original pinned-floorplan rebound now rejects inspector/report/CLI;
the actual publisher refuses it. The unpinned rebound and restored pinned baseline
retain completed/unavailable parity. Earlier R2S and alias negatives continue to
reject for their established boundaries.

All builds used switch5.2.0+ox, explicit `-j6`, shared
`/tmp/opencode/asic-pt7-build.lock`. Executed install/focused compatibility:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @install @test/timing_intent_execution/runtest \
    @test/timing_intent_flow/runtest @test/timing_intent_evidence/runtest \
    @test/timing_native_coverage/runtest @test/ocaml-stage-report \
    @test/inspection @test/flow-cli
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/timing_intent_execution
```

Passing groups:282 named public/API;150 coarse;54 standalone +27 prior review;
154 native-v2; stage-report/inspection and43 policy/CLI tests; install builds.
The last named-only rerun added the actual-byte/old-closure publisher control; its
first iteration exposed an earlier *correct* `changed external dependency` rejection
by checkpoint validation, and the test now asserts that intended existing boundary.
No production check was weakened to obtain a later diagnostic. Counts are not
additive native execution/acceptance totals.

### Fresh inspector replay of unchanged C area/delay products

Script and authoritative new reader-only products:

```text
/tmp/opencode/pt7-r4-real-evidence-replay.py
/tmp/opencode/pt7-r4-real-reader-replay-mt6ieg_5/
  summary.json
  reader-binaries.json
  reader-sources-{before,after}.json
  runtime-source-comparison.json
  tested-source-receipt.json
  reader/_build/default/bin/       pinned fresh CLI/reader/report/API executables
  {area,delay}/{inspect,report,sources}/
  {area,delay}/run-{before,after}.json
  {area,delay}/sources-{before,after}.json
```

The fresh executables read the **original exact execution paths**, not copied or
retargeted run records:

| | Area | Delay |
| --- | --- | --- |
| Attempt | `cb5e7cd92dbf43b4a6c00a74b61c6d72` | `9374823306a64897959e1b2295f52c84` |
| Workspace | `area-run-final-04` | `delay-run-final-03` |
| Original execution provider | `ce6be246fafa4d0dbe1dd00da980482b` | same original provider |
| Current inspection/report exits | **1 /0** | **1 /0** |
| Current timing status/verdict | **completed / unavailable** | **completed / unavailable** |
| Source references verified unchanged | **1584** | **1584** |
| Entire run files unchanged | **168** | **168** |
| External alias rows | **1062** | **1062** |

For both profiles, current inspection JSON equals C's original accepted inspection
exactly; current **entire report JSON** equals the original accepted report and
contains exactly that timing value; fresh public source API equals the same1584
references. Six stored relations, seven diagnostic categories and12 endpoints remain
verified. Both actual staged `Floorplan_def` pins validate at their exact locators,
SHA256 `b46d9a0ee8352160e48dbc8312f092f985629061df736c7f46d58686535a76f4`.

All original run-file and advertised-source SHA256s, canonical resolutions,
device/inode, sizes and mtime/ctime values match before/after. C's original public
receipt trees are unchanged too. Seven current runtime/lifecycle/bridge/helper
source files **byte-match C's executed provider's installed sources**; their hashes
are recorded separately from the new reader. This supports the validation-only
qualification; it is not P6 compiled-source authentication.

**No EDA was rerun or needed for R4.** No execution/checkpoint/companion/source was
rewritten, no constructor or Tcl was rerendered, and no old failed attempt or
provider identity was repaired. C's actual area/delay acceptance remains attributed
to its original execution generation; this is a fresh corrected-reader replay of
those unchanged products. Existing negative hold and unavailable exhaustive effects
are not turned into timing closure by report success.

### Tested source / binary receipt (SHA256)

Production source hashes are the exact generation used in the real replay and
remain identical after the final282-check run; `tested-source-receipt.json` records
the equality and test-source hashes. Handoff prose postdates the tested binaries.

| Source | SHA256 |
| --- | --- |
| `execution/results/timing_intent_execution.ml` | `1717a6813d9b299895be6c5f371ff360b610b7b94e37b2ec080f16f8ea685676` |
| `execution/results/timing_intent_inventory.ml` | `ab0932981b41a3a6e964506544accf5dc1617983184812bb5d2325f06dff1945` |
| `execution/results/timing_intent_linked.ml` | `8750d29de762a2b55831835a5a69af0df7f20b386e94bf7c844fd81cc80db487` |
| `execution/results/stage_execution_record.ml` | `3eba095590d94853e23955e2d0906b61a7dac118a25ae6a2d8c5c6db397a81c3` |
| `execution/results/stage_report_service.ml` | `99e27697cde271268feacde69e815f34e422d744038d8a3da35b025a7766c3d8` |
| `execution/methodology_execution_record.ml` | `6b1ee4a8e58f0cb57d1962f92ba6600ef6d6f1905f17332f3d620fec10808ff9` |
| `test/timing_intent_execution/check.py` | `18f5b824b909f3b6ed054662f5399555279e89bad9bdd12541ea575142b1b31c` |
| `test/timing_intent_execution/consumer.ml` | `783597cf9a1d729990ddab642c7bb3e6c85ba8e1c75add4ab01b73bad6eb1c73` |

Fresh replay executable SHA256s:

```text
751496b36b209155869e4a46f6e2984f47b6cebcf2d687480c5502212ba34461  experimental_timing_intent_inspect.exe
cb590e9950d50d6582a29e31876e5cfd6d4719b2445f3145c180844ea24ba0f7  experimental_report.exe
eb10b137a2df746753fada5556b12a3908e68302057f7861be78aa35117a5d72  flow_cli.exe
646a0ef2810fb6c6d3790765834a1628b13e40709aa4eceb20b3989a93568ea3  api.exe (public library source-query adapter)
```

`git diff --check` passes. No Git mutations, application-provider selection changes,
Protemu/Workbench work, runtime/EDA changes or C evidence edits occurred. **B R4 is
implemented/tested and the corrected reader accepts unchanged real area/delay
evidence.** Native schema2/profile2, alias proof, numeric bounds, path-bound scope
and no-named-archive limits remain unchanged.
