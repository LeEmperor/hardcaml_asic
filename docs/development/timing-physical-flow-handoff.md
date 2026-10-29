# Timing physical — B execution/evidence seam

## CURRENT AUTHORITY — 2026-10-29 post-native-qualification follow-up

**RESOURCE DISPOSITION: original mid-PNR STA was1/6/6/6, not uniformly STA1.**
Retained commands for steps31/36/38/43 show one/six/six/six requested OpenROAD
threads. This stayed within C's explicit six-worker allocation/container ceiling
and global20 budget; it is a stronger-policy/label discrepancy, not a budget breach
or timing failure. The original timing/physical acceptance remains supported and
needs no new full run. Earlier blanket mid-STA1 claims below are superseded by this
actual-command disposition. A separate **forward, unexecuted** alias enforcement
fix now passes focused model and installed-LibreLane command-construction tests;
it must not be attributed to provider4856 or the original run.
C's archive republication can continue using its corrected archiver independently.

**ACTUAL FIRST FULL PASS; corrected archive reader READY for republication.**
C's run `23a6954b852d4205b542d3815634d772` passed actual extracted all-corner
setup/hold/electrical checks, normal TT9 and512-observation final functional replay.
See `hardcaml_asic_example/docs/timing_physical_full_result.md`. One full attempt
was used; no new full run or repair is needed for this fix. Portable collect/report
replay was missing seven advertised antenna/DRC/LVS reports (423 original raw
artifacts versus416 restored). B's correction is limited to archive selection and
its fixtures: C will use a separate corrected reader/helper capture to publish a
new archive from the same unchanged run, preserving the original archive/evidence.
The archive-only correction and regression checks now pass:223 isolated checks,
old archive/codec cases and exact fixture collect/report replay. Read-only selection
on the actual run includes all seven omitted reports. B has not published from or
modified that run. C should fresh-capture the corrected archive helper and publish
to a **new output directory** using the same run; actual hidden-input replay remains
C's final portability acceptance. Details/source hashes are in the archive closeout
at the end. No native/provider execution-source change or new full run is required.

**F1–F6 FIXED in current sources; the pre-fix full snapshot remains blocked.**
C's native controls and all-configured public synthesis remain READY6. Full capture
must use a fresh generation advertising
`timing_intent_physical2.source_closure = extracted_state_views_retained_filter_v2`
as well as the functional-postcheck profile below. Do not launch full against the
snapshot reviewed in `timing-physical-flow-review.md` or retrofit its evidence.
B's205 durable checks pass. The unchanged reviewer-owned
`test/timing_physical/review_flow.py` was rerun: its38 observations now have the
intended rejections/valid controls, including F6 unknown rather than pass. Latest
receipt: `/tmp/opencode/timing-physical-flow-review-8yac81an/results.json`.
This clears B's implementation-fix hold for fresh capture; actual native extracted
execution, timing closure and independent review of C's real evidence remain
acceptance boundaries. Details and exact updated filter wire are in the F1–F6
closeout at the end. No A resolver review was performed in this slice.

**READY: C may run all-configured coarse synthesis with its allocated six workers
now.** C reports198 passing native controls across standalone STA and ODB; actual
findings are in `hardcaml_asic_example/docs/timing_physical_findings.md`. Earlier
pre-implementation/not-ready wording below is historical and does not veto this
readiness. No default-only or named physical route is substituted.

Use A's emitted explicit qualification opt-in and the public syntax:

```sh
timeout --signal=TERM --kill-after=60s 15m \
  "$FLOW" run "$SYNTH_BUNDLE" --stage synthesis --support-tools "$TT" \
  --pdk-root "$PDK" --python "$PYTHON" --runs "$EVIDENCE/synthesis-runs" --json
```

Limits are READY6: preflight/probe transports<=6; implementation
container CPUs6 / flow jobs6 / physical repair OpenROAD6 / KLayout DRC6 and XOR6;
standalone/linked STA corners1 with native `-threads 1`; historical repeated mid-PNR
STA requested6 as disposed above (the one-thread policy is forward-only there).
TT/final replay nested
budgets<=6. Postcheck timeout1800 and explicit outer deadlines below apply. Owned
container cleanup remains required on success, failure, cancellation and timeout.
B builds use switch5.2.0+ox, explicit-j6 and
`/tmp/opencode/asic-pt7-build.lock`; B runs no EDA. C serializes builds/EDA within
its six-worker allocation.

**Functional-postcheck fix ready; full capture requires the F1–F6 corrected source closure above.**
C may proceed to its bounded ordinary full attempt after its fresh all-corner
synthesis acceptance, using a **fresh captured generation containing this fix**.
Check `--version --json` for
`cli_contract.capabilities.timing_intent_physical2.functional_postcheck` equal to
`cmos5l_physical_timing_used_cells_v1`. Its new full-run preflight must retain the
supplied vendor/UDP hashes; do not retrofit missing hashes or model outputs into
an older run. Earlier captures, baseline failures and all historical evidence stay
unchanged. The new view is functional-only, not vendor timing conformance; native
timing/physical gates remain required. Actual Icarus/final-netlist acceptance still
belongs to C. The full/repair attempt budget is unchanged.

```sh
timeout --signal=TERM --kill-after=60s 60m \
  "$FLOW" run "$FULL_BUNDLE" --stage full --support-tools "$TT" \
  --pdk-root "$PDK" --python "$PYTHON" --runs "$EVIDENCE/full-runs" --json
# RUN is the exact completed full run returned above. No user-local model patch.
timeout --signal=TERM --kill-after=60s 35m \
  "$FLOW" postcheck "$RUN" --support-tools "$TT" --pdk-root "$PDK" \
  --precheck-python "$PRECHECK_PYTHON" --testbench "$TB" \
  --testbench-top "$TB_TOP" --timeout 1800 --json
"$FLOW" collect "$RUN" --json
"$FLOW" report "$RUN" --json
"$FLOW" archive "$RUN" --output "$ARCHIVE" --json
```

**This top section is final current readiness authority.** Initial publication and
earlier not-ready text below describe historical integration checkpoints only.

## Historical initial publication (superseded readiness)

2026-10-29. Published before implementation. B owns execution/evidence as assigned
in `timing-physical-qualification.md`. Publication alone was not full-run readiness;
the final current-authority section above now supplies that readiness.

## Initial A integration request — subsequently fulfilled

A's handoff was not yet present at initial publication. B subsequently read it
before integrating policy/emission. Required A seam: an identity-covered explicit
all-configured analysis opt-in, physical resolution policy, and checked stage
endpoint map used by downstream witnesses. Historical synthesis policy and named
admission remain unchanged. Exact manifest spellings follow A's published handoff.

## Versioned capture contract

- Existing audit1/audit2 and coarse companion1 remain unchanged.
- New coarse companion2 has kind `hardcaml-asic.timing-intent-flow`, schema2,
  run_id/build_identity/manifest_sha256, stage (`synthesized_netlist` or
  `post_pnr`), status, sources and the exact immutable request reference.
- New request2 records stage, original implementation process and execution_root,
  in addition to existing runtime/input identities. Configured/requested corners
  come from the retained resolved configuration and input-selection/result records
  described in the implemented contract below, not duplicated request assertions.
  Full execution is an actual coarse run; no fabricated named or coarse records.
- Physical audit3 keeps the closed existing audit envelope, kind
  `hardcaml-asic.timing-intent-audit`, stage `post_pnr`, scope
  `standalone_extracted_netlist_sta`, native-data/profile2. Required source roles
  are audit2 roles plus singleton `spef`, `parasitic_annotation`, `clock_state`.
  SPEF joins receipt inputs. All-configured synthesis retains audit2 semantics.
- Helper result2 records configured/requested/executed/equivalent corners separately,
  exact producer config/input/output State/runtime and physical producer-chain refs.
  Each corner binds original selected netlist/SPEF/library inputs to retained
  copies and actual native environment paths, preserving library order/multiplicity.
  No missing/equivalent corner earns an executed result or physical closure.
- Physical input is the unique completed STAPostPNR producer's INPUT State,
  associated with native RCX output and retained placement/CTS/routing/RCX states.
  Linked STAPostPNR is a separate analysis, not the original process. Native hook
  runs after normal parasitic loading; enclosing process AND Step completion are
  required. Keep complete reports, annotation and propagated-clock evidence.

## APIs and lifecycle

Preserve `Timing_intent_flow.{inspect,source_files,publish}` and
`Timing_intent_evidence.inspect`. Extend capture internally with explicit stage
and corner policy; new schemas are dispatched independently of historical readers.
Native-v2 interpretation stays shared. Add narrowly qualified propagated-clock
serialization only after inspecting the exact form; no Tcl execution on reads.
All-corner metrics require actual corner log/output-State agreement, ns units,
setup/hold >=0 and violation counts0. Exhaustive exception coverage stays unavailable.

Persist expectation before preflight; failed required capture fails the run while
retaining process/cleanup failures and native sources. Successful native capture
with negative slack is retained evidence, not closure. Public report gates closure
separately and retains ordinary physical/external acceptance requirements.

## Limits and C route

Every probe/flow/transport/OpenROAD/KLayout/postcheck <=6 workers; STA executor1
and `sta -threads 1`. B runs only non-EDA tests, switch5.2.0+ox, shared
`/tmp/opencode/asic-pt7-build.lock`, explicit `-j6`.

After implementation readiness, C uses an approved captured executable and fresh
emitted allconfigured synthesis then Hardening bundles:

```sh
"$FLOW" run "$SYNTH_BUNDLE" --stage synthesis --support-tools "$TT" \
  --pdk-root "$PDK" --python "$PYTHON" --runs "$EVIDENCE/synthesis-runs" --json
"$FLOW" run "$FULL_BUNDLE" --stage full --support-tools "$TT" \
  --pdk-root "$PDK" --python "$PYTHON" --runs "$EVIDENCE/full-runs" --json
"$FLOW" timing-intent-inspect "$RUN" --kind coarse_run --json
"$FLOW" postcheck "$RUN" --support-tools "$TT" --pdk-root "$PDK" \
  --precheck-python "$PRECHECK_PYTHON" --testbench "$TB" --testbench-top "$TB_TOP" \
  --timeout 1800 --json
"$FLOW" collect "$RUN" --json
"$FLOW" report "$RUN" --json
"$FLOW" archive "$RUN" --output "$ARCHIVE" --json
```

Inspection exit1 is expected for unavailable exhaustive coverage; inspect JSON for
completed actual corners and separate closure. Publication alone did not authorize
full launch; the current-authority section now states implemented readiness.
Preserve all failures and old providers/evidence.

## Implemented contract — B ready for C's native qualification

B read A's handoff before integrating its implemented marker, trace/inventory
events and `checked_endpoints` API. No A-owned library file was edited by B.
The implementation supports **coarse only, fresh, macro-free CMOS5L**. An opted-in
full launch requires a Hardening bundle. Physical qualification remains explicitly
rejected by named execution. Historical coarse/named synthesis retains its old
writer/reader/argv semantics and one-default-corner behavior.

The implementation and non-EDA tests are ready for C's allocated six-worker
native diagnostics, then the bounded full run after those diagnostics pass.
This implementation checkpoint was not native/physical acceptance. C's subsequent
198 native controls are acknowledged in the current authority above; actual routed
post-repair behavior, extracted closure and final-netlist replay remain separate
acceptance boundaries.

### Public opt-in and API

C emits both bundles with A's public
`Bundle.render ~timing_physical_qualification:true` (default false), using its
Synthesis and Hardening resolved projects respectively. The exact marker and
physical-v2 resolution policy are in `timing-physical-library-handoff.md`.
No new CLI switch or extra coarse run/checkpoint record is necessary.

Existing signatures remain:

```ocaml
Timing_intent_service.capture :
  ?timeout:float -> run_dir:string -> context:Identity_json.t ->
  binding:Execution_transport.binding -> pdk_root:string -> resources:string ->
  environment:string list -> cancel:(unit -> int option) ->
  verify_runtime:(unit -> (unit,string) result) -> unit -> unit
Timing_intent_flow.inspect : run_dir:string -> unit -> (Evidence_json.t,string) result
Timing_intent_flow.source_files : run_dir:string -> context:Evidence_json.t -> unit ->
  (Evidence_json.t list,string) result
Timing_intent_evidence.inspect : directory:string -> unit -> (Evidence_json.t,string) result
```

New `Timing_physical_flow` is the separate versioned coarse adapter behind those
interfaces; `Timing_physical_metrics` interprets actual corner log/State metrics.
`Timing_native_coverage.inspect` stays historically strict. Its added
`inspect_with_clock_policy ~allow_propagated:true` is used only by audit3 and admits
only `set_propagated_clock` with the literal primary `clk` collection. Wildcards,
`all_clocks` queries, extra/scoped arguments and other clocks reject. Native-v2
profile/data and overall unavailable exhaustive coverage are unchanged.

### Exact outer wire

The run persists `timing_intent_expected=true` and `timing_physical_expected=true`
before preflight. It records `timing_runtime_helpers` with both helper hashes
before implementation, and `implementation_process` with exact supervised
`{outcome,code,succeeded,argv}`. Old runs still use `synthesis_process`.

`timing-intent/request.json` has exactly:

```text
schema:2, run_id, build_identity, manifest_sha256, analysis_id, stage,
implementation_process, execution_root, host_uid, host_gid, binding, pdk_root,
helper_sha256, base_helper_sha256, producer_sha256
```

Analysis IDs are `RUN_ID/pre-pnr-sta` or `RUN_ID/post-pnr-sta`. `stage` is
`synthesized_netlist` or `post_pnr`, respectively. The two helpers are retained
both in project/ (implementation) and timing-intent/ (analysis); hashes must agree
with the run's pre-implementation identities. Transport reconstructs the complete
qualified Docker argv, including image position, flags, roots and worker limits.

`analysis.json` has exactly:

```text
schema:2, kind:hardcaml-asic.timing-intent-flow,
run_id, build_identity, manifest_sha256, stage, status:completed|failed,
request:{path,sha256}, sources:[{path,sha256}]
```

It is exclusively created after supervised completion and cleanup. A publication
obstruction is retained and added to an existing process/cancellation/timeout
failure, not overwritten or allowed to replace that primary. All sources are
run-relative; native absolute paths remain historical labels after restore.

`input-selection.json` is saved **before** native analysis. It binds the selected
implementation producer, originating synthesis and physical chain. It also names
every retained file in the selected synthesis/placement/CTS/detailed-routing/RCX/
original-post-PNR producer directories. These sources survive failed linked STA.
`runtime-result.json` schema2 repeats those checked associations on success and
adds effective config, configured/requested/executed/equivalent corners and audits.

`corner-selections.json` retains complete native CornerFileList tuples.
`corner-progress.json` retains exact observations/process references even after
native failure: configured/requested, actually observed executed processes,
input-equivalence proofs, not-observed corners, audits when completed, and separate
Step completion. Native MultiCornerSTA's one-worker executor is drained on failure
before progress is published; no queued-corner/source race is silently ignored.
Input equivalence does not mean execution. Initial acceptance requires all three
fast/slow/typical corners to execute; an equivalent/missing corner blocks success.

### Exact inner inputs, native processes and sources

Audit3 uses the closed audit2 envelope with schema3, `stage=post_pnr` and
`scope=standalone_extracted_netlist_sta`. It adds singleton `spef`,
`parasitic_annotation`, `clock_state` roles; `spef` joins receipt input roles.
All-configured pre-PNR keeps audit2. Both admit A's physical-v2 policy and expose
validated trace/sequential inventory in `resolved.physical_topology`.

Each `native-inputs.json` contains `associations`, `corner_script`, `environment`.
Every association is exactly:

```text
role, original_path, actual_path,
retained:{path,sha256}, bytes
```

The reader checks complete ordered Liberty selection from retained CELL_LIBS /
PAD_LIBS against actual `_CURRENT_CORNER_LIBS`. Physical SPEF selection must be
unambiguous under the input State's corner mapping, agree byte-for-byte with the
RCX output/STA input, and be the retained file actually supplied through
`_CURRENT_SPEF_BY_CORNER`. No hierarchical/extra netlists/SPEFs or extra models are
admitted. `spef_selection` in each public corner explicitly links stage, timing
corner, input/RCX States, original mapping/path, retained bytes and native env key.

The native STA and native ODB annotation filter are distinct processes with
separate `native-process-N.json` `{argv,exit_code}` records. The filter uses
retained ODB/LEF copies and records its image-script/source association. Neither
a successful hook nor successful STA followed by failed filter/Step completion
can publish completed evidence. Native-version commands have independent receipts.

Sources include both helpers, producer, driver, hook, retained executed corner Tcl,
native common Tcl, ODB Python dependencies and Step/MRO source snapshots, rerouted
environment Tcl, ordered libraries, netlist/SPEF/ODB/LEFs, configs/States/runtime,
all raw per-corner reports and native process/version results. Image-internal tool
binaries remain bound to the qualified immutable image; hashes are trusted-local
producer assertions, not authenticated execution. Toolbox scratch is not evidence.
No reader executes Tcl, imports tools, rerenders, or consults the current PDK.

Coarse bounds remain512 sources,64MiB/source,512MiB total; selected original producer
files are additionally bounded at384 before capture. Inner audit bounds remain64
sources/256MiB and existing text/metadata bounds. No truncation or omitted source
is used to fit a limit. A real over-limit specimen is a retained route blocker.

### Metrics and acceptance

Each public corner separates native evidence, actual inputs and timing metrics.
Metric sources identify exact log/line, output State and loaded Liberty units.
Pass requires one native log metric matching output State, ns units, setup/hold
worst slack>=0 and violation counts0. Missing, conflicting, duplicated, nonfinite,
sentinel, wrong-unit or inherited-only metrics cannot earn pass. Sampled witnesses
are queried through A's checked map and remain separate from closure metrics.

Report additionally requires executed fast/slow/typical qualification coverage,
all-corner electrical limits, native propagated primary-clock evidence and the
existing native ODB connected-net annotation check. Raw annotation reports remain
visible; a zero filtered count is not relabelled blanket raw-report perfection.
Standard physical and external TT/gate-level postcheck requirements remain.
Process completion, timing goal and unavailable exhaustive exception coverage are
separate. A negative timing result may be retained/archived as completed analysis;
it cannot be accepted by full-flow report.

### Worker readiness and C commands

Six-worker limits cover preflight containers, flow `--jobs`, Docker quota/environment,
OpenROAD/KLayout and postchecks. The corrected **forward policy** bounds dedicated
STAPrePNR/PostPNR and every STAMidPNR occurrence to one-thread; the original actual
mid-PNR profile was1/6/6/6 as disposed at the top. Linked STA/filter and corner
executor were one-thread. Macro-free
qualification postchecks now use host affinity<=6, container<=6, Nix max-jobs1 /
cores6, nested worker environment6 and a default1800-second per-tool timeout.

B has performed no provider capture/activation and no EDA. C may capture this
combined A+B source into a **fresh isolated store**, under the shared ASIC lock:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  python3 -B scripts/asic_dependency.py --store "$NEW_STORE" refresh \
  --source "$ASIC" --mode development --jobs 6
```

Use the returned captured generation's explicit installed executable, without
changing an old provider selection. Capture `--version --json` and verify
`timing_intent_physical2` (native qualification is still pending). Emit through
A's true opt-in and qualify native STA/ODB object/serializer controls first.
Then use the ordinary public commands above, wrapped in explicit outer deadlines:

```sh
timeout --signal=TERM --kill-after=60s 15m \
  "$FLOW" run "$SYNTH_BUNDLE" --stage synthesis --support-tools "$TT" \
  --pdk-root "$PDK" --python "$PYTHON" --runs "$EVIDENCE/synthesis-runs" --json
timeout --signal=TERM --kill-after=60s 60m \
  "$FLOW" run "$FULL_BUNDLE" --stage full --support-tools "$TT" \
  --pdk-root "$PDK" --python "$PYTHON" --runs "$EVIDENCE/full-runs" --json
```

Take RUN from the exact returned outcome. Preserve nonzero outcomes/logs; inspect
failed companions without granting partial native coverage. Postcheck only a
completed full run. Handle inspection exit1 explicitly in set-e launchers and
verify JSON status/corner sets/goals. Public archive currently requires a completed
coarse run; process-failed runs remain retained locally, not relabelled to archive.
Restore archived run.json + reports and overlay input-bundle contents into project/;
the same public inspection must replay without original PDK/library paths.

### Verification record

All B Dune calls used switch5.2.0+ox, explicit-j6 and the shared ASIC lock.
Isolated `test/timing_physical_flow` currently passes116 checks: public fresh
coarse all-configured synthesis/full orchestration, checked-map Tcl language
oracle, implementation/mid-STA limits, native/source/corner/SPEF/scope/clock and
metric controls, real supervision over fake Docker (failure/timeout/cancel/cleanup/
publication obstruction), failed-corner executor drainage, public collect/report,
actual archive encoding/restore without original libraries, and macro-free bounded
public postcheck. Native Step/tool output is modeled; no EDA is attributed to B.

Final integration command passed:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @install \
  @test/timing_physical_flow/runtest @test/timing_physical/runtest \
  @test/timing_intent_flow/runtest @test/timing_intent_named_runtime/runtest \
  @test/timing_intent_named_runtime/core @test/timing_intent_execution/runtest \
  @test/timing_intent_evidence/runtest @test/timing_native_coverage/runtest \
  @test/ocaml-coarse-run @test/ocaml-preflight @test/ocaml-collect \
  @test/ocaml-report @test/ocaml-archive @test/ocaml-postcheck @test/flow-cli \
  @test/timing_analysis/runtest
```

Observed compatibility includes150 old coarse timing checks,282 named evidence
checks,30 named runtime cases,10 named admission and7 native-core controls,
54 schema1 evidence plus27 independent reader regressions,154 native-v2 checks,
131 collect and585 report differentials,16 archive differentials,15 postcheck
differentials, coarse/preflight cancellation/public-routing checks,43 CLI/policy
tests and18 timing-analysis grammar cases. Unchanged dependency results may be
cached. Counts are heterogeneous, not an additive native execution total.
The harness's optional retained historical finalization fixture remains unavailable
at `/tmp/opencode/native-final-integration/finalizations/20261014T040711301534Z_913453bd`;
it is not counted as passed. This is affected integration verification, not a claim
of every repository test or native acceptance. `git diff --check` passes.

The physical expectation is independent of the older synthesis expectation:
collect/report/archive require source replay if either the marker or persisted
`timing_physical_expected` advertises it. A regression removes both old producer
advertisements and the old expectation while preserving the physical expectation;
inspection/archive reject and collection reports invalid, never historical absence.

**Completion boundary for C:** ordinary `run` completes only after real full
implementation, required linked Step/processes/cleanup and strict evidence replay.
That is separate from full report acceptance, which also needs actual executed
fast/slow/typical corners, setup/hold/electrical/annotation goals and ordinary
physical/external postchecks. The archive is source-evidence replay, not a claim
that arbitrary restored States form relocatable runnable checkpoints. Native
serializer/object/repair controls and actual physical evidence still need C and
independent review. No EDA, Git mutation, provider capture/selection, daemon,
Workbench/Protemu change or historical evidence edit was performed by B.

## Functional-postcheck follow-up — implemented and verified

C's198 native object/clock controls and its unchanged-vendor Icarus failure are
recorded in `hardcaml_asic_example/docs/timing_physical_findings.md`. B read these
findings. The vendor source uses delayed CLK/D/RESET_B reference wires driven by
specify timing checks which Icarus does not implement. Its positive and negative
baseline failures remain failures; the source model and final netlist are not
patched in place.

### Public route and ownership

The ordinary `postcheck` now selects the existing production
`physical_runtime.replay_models` path for the explicit macro-free timing profile,
as well as the previously supported SRAM physical profile. The old macro branch
and legacy raw-model postcheck path retain their meanings. The new path requires
the exact identity-covered physical marker, a completed full run and intact
completed native post-PNR evidence. The final replay netlist must hash-match the
netlist actually used by native physical timing. Native sources are revalidated
again after replay; functional results cannot replace missing/corrupt timing
evidence. A real negative timing goal remains negative, independently of functional
replay, and full report still enforces its timing/electrical/physical gates.

Changed production ownership in this follow-up: `preflight_service.ml` pins the
two supplied standard-cell model sources for this opt-in; `physical_runtime.py`
derives/retains the functional view; `postcheck_service.ml` selects and verifies it;
collect/report/archive replay and expose the retained model facts. Capability
`timing_intent_physical2.functional_postcheck` advertises the profile. No emitted
bundle, architectural stage, native checker/exception, timing budget or PDK file
is changed to obtain functional replay.

### Safe adaptation and exact provenance

Only used vendor module definitions are emitted. The four reset-flop masters
`sg13cmos5l_dfrbpq_{1,2}` / `sg13cmos5l_dfrbp_{1,2}` require their **entire reviewed
non-timing functional bodies**, not just a name/delayed-wire substring match.
Q/Q_N/reset polarity, UDP connectivity, declarations and original functional logic
must match. Exactly the three undriven timing-reference wires are bridged to their
same-named supplied input pins. Other used cells preserve their supplied structural
function with specify removed; procedural, notifier or unreviewed delayed-reference
behavior rejects. Unsupported/duplicate modules fail rather than silently falling
back to the broken raw model.

The adapter derives and retains from single hash-checked byte snapshots, with
before/after supplied-source checks. Preflight vendor/UDP hashes must match those
snapshots. The complete unchanged vendor file is retained as `stdcell-vendor.v`,
the unchanged UDP as `model-0.v`, and the derived used-cell view as
`stdcell-functional.v`. New `replay-models.json` schema2/profile
`cmos5l_physical_timing_used_cells_v1` binds exact manifest, preflight, netlist,
supplied/retained source hashes, selected vendor module hashes, adaptations and
defines. Its claim is explicitly
`zero_delay_digital_functional_only_not_vendor_timing_or_sdf_conformance`.
No vendor delayed timing check or SDF conformance is claimed.

Postcheck records the helper and inventory identities before compilation and
checks all supplied/retained files again afterwards. Collect/report reject changed
or missing completed model artifacts. Report refreshes this source validation even
when results.json is present, without rewriting it or hiding later failed checks;
the stored-results tamper regression verifies that read-only boundary. Archive
includes and verifies the complete
model closure for macro-free timing, rather than only for SRAM. Report's new-profile
human output explicitly labels zero-delay digital functional scope. All worker,
deadline, native/physical and external TT checks remain as stated in the authority
section. Failed checks and their partial sources remain retained.

### Verification and actual-source review

Final affected integration command passed with switch5.2.0+ox / shared lock / -j6:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @install @test/timing_physical_flow/runtest \
  @test/physical_execution/runtest @test/ocaml-postcheck @test/ocaml-preflight \
  @test/ocaml-coarse-run @test/ocaml-collect @test/ocaml-report @test/ocaml-archive \
  @test/flow-cli @test/timing_intent_flow/runtest \
  @test/timing_intent_named_runtime/runtest @test/timing_intent_execution/runtest
```

New totals:126 public/runtime/source checks in `timing_physical_flow`, plus11 pure
used-cell model tests. Existing14 physical-runtime tests (including the historical
SRAM model branch), postcheck/preflight/coarse/collect/report/archive/CLI and
coarse/named timing compatibility checks pass. The optional historical-finalization
fixture remains unavailable as previously documented. No real simulator/EDA tool
is run by these tests; external Icarus/TT boundaries are modeled.

Meaningful new controls include all four reset-flop sizes, used-only emission,
unchanged vendor/UDP retention, hash-consistent wrong reset function / extra delayed
driver, unsupported delayed/unknown/duplicate cells, missing profile, substituted
final netlist, supplied-source changes, fresh-output admission, corrupt native
evidence, model/inventory mutation during replay, and artifact mutation after a
completed postcheck (collect/archive reject). Review also corrected an old isolated
test's invalid `archive --list --json` negative control: it now exercises actual
JSON archive publication rejection and verifies no destination was created.

Explicit **non-EDA structural source qualification** also passed against the
actual provisioned supplied vendor/UDP, with hashes unchanged before/after:

```text
vendor b0adbc84c8f78feb01c3d8d9d55e9818ee6502347d336f3a1f846e6a5d64e0a2
UDP    5491a3edf7468792b5222e7abe057e0583a407c01b2086d4fd44a55b6cf88055
```

It covers16 actual supplied cell types: four reset flops, all five qualified
buffer drives, all three delay gates, both AND2 drives and the two tie cells.
Reproduce without invoking a simulator:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  python3 -B test/timing_physical_flow/model_replay.py \
  flow/hardcaml_asic_flow/physical_runtime.py --pdk-root "$PDK"
```

This establishes the adapter/source structural seam, **not actual Icarus replay**.
C must still run the unchanged positive and intentional-negative functional test
through the production generated view and retain final-netlist acceptance. B has
performed no EDA, provider capture/selection, Git mutation, SRAM rerun or modification
of supplied model/PDK/netlist/history bytes. Current readiness is stated at the top;
no historical baseline is relabelled as passing.

## Independent flow review F1–F6 — B correction closeout

2026-10-29. B read `timing-physical-flow-review.md` and corrected its six findings.
The reviewer-owned review document and `test/timing_physical/review_flow.py` were
not edited. B's durable reproductions live in `test/timing_physical_flow/check.py`.
The current-authority section at the top supersedes both the initial full-ready
claim and the temporary F1–F6 hold on the pre-fix source.

### Corrections

| Finding | Implemented boundary | Durable controls |
| --- | --- | --- |
| F1 | Physical audit3 requires exactly one actual serialized propagated primary `clk`, with the native clock observation agreeing. Clock JSON alone cannot establish stored state. | Missing/commented propagation rejects after full source rebinding; false clock JSON rejects; equivalent literal-list serialization passes. |
| F2 | Actual extra-corner hook environment equals the retained/effective hook. Annotation executes a closed retained bootstrap with a same-layout retained odbpy dependency set, rather than an unchecked image script path assertion. | Substitute script path/argv with unchanged source bytes rejects; substitute executable source bytes rejects; either actual hook variable substituted rejects; real Python bootstrap imports the retained reader despite poisoned ambient PYTHONPATH. |
| F3 | The actual `checks.rpt` consumed by the native filter is a required hash-bound source, explicitly linked to the filter argv. | Missing checks report rejects after removing/rebinding optional inventory entries; substituting the hook's standalone report rejects. A retained raw report containing unwired/unannotated drivers may still have a valid zero native connected-net-filter count. |
| F4 | RCX output and original STA input agree on exact nl/SPEF/ODB locators. The retained filter ODB must be the same bytes as that physical ODB. | A real retained unrelated ODB substituted into RCX output rejects on association mismatch, not merely missing file/hash; matching baseline passes. |
| F5 | Positive producer ordinals are causal from synthesis through placement, CTS, detailed routing, RCX and original post-PNR STA. Every claimed non-metric view in the selected physical States resolves to a real, hash-bound retained run member, including nested maps/lists and inherited views. | STA before RCX/ordinal zero and synthesis after placement reject; dangling CTS views reject. Distinct valid retained CTS/routed netlists/ODBs and nested SDF views pass, without equating pre-repair and post-repair content. |
| F6 | Every native metric-family record naming a required corner/key participates in uniqueness/shape checking, including malformed records. An extra/missing value or malformed duplicate cannot be ignored in favor of a positive sample. | Rebound malformed duplicate setup lines produce timing unknown, never pass; missing/duplicate/conflicting metrics retain unknown; consistent negative hold retains fail; irrelevant text and other-corner metrics do not poison a valid sample. |

Runtime admission checks physical ordering and State closure before starting linked
STA, as well as checking RCX ODB association. The reader independently source-replays
those facts. Original and linked STA outputs must preserve implementation nl/odb/
spef; generated timing views remain separate. No blanket equality is required
across CTS/routing repair. All opaque State views are checked as retained file
identities, not parsed as JSON or re-executed as EDA.

The new physical State-closure and propagation requirements do not reinterpret
schema1/schema2 synthesis. Historical/default coarse and named native-v2 behavior
remains supported. An explicit all-configured synthesis compatibility control keeps
an unused historical view locator, without granting that locator physical provenance.

### Exact corrected filter execution seam

The outer companion/audit versions remain2/3 and native data/profile remainsv2.
Physical full now requires the capability source-closure profile
`extracted_state_views_retained_filter_v2`. Fresh physical capture is required;
do not edit old companions to add fields.

`filter-inputs.json` has exactly:

```text
driver_profile: retained_odbpy_v1
script_path: <historical timing-intent/corners/CORNER/filter-driver.py>
script: {path,sha256}                 # that exact retained bootstrap
filter_source: {path,sha256}          # native-sources/odbpy/filter_unannotated.py
dependencies: [{path,sha256}, ...]    # complete retained odbpy *.py layout
checks_report: {path,sha256}          # corners/CORNER/checks.rpt actually consumed
inputs: [{original_path,actual_path,retained:{path,sha256},bytes}, ...]
```

The reader checks the bootstrap's exact closed protocol bytes and executed path.
It inserts the retained odbpy directory before ambient Python lookup, suppresses
bytecode writes into evidence, and runs the retained native filter with its original
argv. `reader.py` and the filter are required dependencies; every declared dependency
is source-bound. The helper also checks its original native filter command against
the qualified image's script location/retained bytes before substituting the retained
bootstrap. The script path in argv is reconstructed independently of the metadata
claim. All execution still uses native OpenROAD with `-threads 1` and the original
filter algorithm; no always-zero substitute is introduced.

Actual hook authority checks both `STA_EXTRA_CORNER_TCL_FILE` and the physical
`_EXTRA_CORNER_TCL_FILE` against the exact retained/effective hook. Native SDC
propagation uses the bounded LF-only parser, not comment matching or Tcl evaluation.

Public `timing.annotation_sources.report` now identifies the actual filter input
`checks.rpt`; `hook_report` separately identifies the standalone hook annotation
report. Native process/metric/State sources and the explicitly filtered annotation
scope remain distinct. The source closure is retained and replayable after archive
restore without current image/PDK paths. All configured worker/thread ceilings and
native/physical/electrical/postcheck gates remain enabled.

### Verification receipts

The broad affected install/compatibility command passed under switch5.2.0+ox,
shared `/tmp/opencode/asic-pt7-build.lock` and explicit-j6, including physical flow,
native-v2/schema1 readers, old coarse and named timing, physical-runtime fixtures,
preflight/coarse/postcheck/collect/report/archive/CLI and timing-analysis checks.
Final focused install/readers/results replay also passed after the bootstrap's
bytecode-write guard. `test/timing_physical_flow` now reports **205 checks**, plus
the unchanged11 model derivation tests. The previous optional retained-finalization
fixture remains unavailable and is not counted as passed.

The reviewer-owned script was executed unchanged against current built binaries:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  python3 -B test/timing_physical/review_flow.py
```

Latest38-observation receipt:
`/tmp/opencode/timing-physical-flow-review-8yac81an/results.json`.
F1/F2/F3/F4/F5 mutations now reject; F6's malformed duplicate yields completed
evidence with timing **unknown**, not pass. Baseline/equivalent clock selector,
valid filtered-annotation scope, negative-hold fail, metric unknown and truthful
failure/progress controls retain their intended meanings. This is rerunning an
independently authored reproducer, not changing A's review verdict on A's behalf.
The earlier review/failure directories remain intact.

No EDA, Git mutation, provider capture/selection, SRAM rerun, A resolver change or
Workbench/Protemu change was performed. C still owns actual native bootstrap/filter
execution, extracted physical closure and final-netlist acceptance on the fresh
captured source; no native or exhaustive exception-effect pass is inferred from
these modeled-boundary and source-replay checks.

## Archive report closure — reader-only correction after actual full pass

2026-10-29. C's first full run `23a6954b852d4205b542d3815634d772`, execution provider
`4856e6af993642988c18c07f47a8c689`, actually passes all-corner extracted setup/hold,
electrical/native annotation, ordinary physical checks, TT9 and512-observation
functional replay. C's `timing_physical_full_result.md` and findings retain the
actual evidence. The remaining archive defect was423 original advertised raw
artifacts versus416 restored: seven ordinary antenna/Magic DRC/Netgen LVS reports.
No native timing/model/repair change or second full attempt is needed.

### Corrected archive selection

The only production source changed for this correction is
`execution/archive/archive_service.ml`. Native execution helpers, synthesis/full
admission, timing readers, functional adapter, collection/report implementations,
provider selectors and the original run/archive were not changed.

For explicit timing-qualification coarse Full archives, selection now constructs
a bounded **verified native direct-report inventory** from the same shallow report
namespace advertised by collection:

```text
<selected flow>/<positive ordinal>-<native class slug>[-<occurrence>]/reports/
    <direct regular filename>.rpt | <direct regular filename>.json
```

Each producer must match the registered selected-Classic mapping, exact directory
slug/occurrence, LibreLane3.1.0.dev3 metadata, a valid completed native output State
and native runtime grammar. The archive retains those exact config/State/runtime
sources with the report bytes. Metadata references are replay facts, not runnable
checkpoint or authenticated-execution claims; no current PDK/image is consulted.

All selected files are run-confined, traversal-safe and symlink-free. The inventory
is admitted before hashing:<=1024 direct directory entries,<=4096 source members,
<=32MiB/report,<=8MiB/metadata source,<=256MiB total. A stored results advertisement
is separately bounded at8MiB /8192 raw entries. It may require an advertised report
to exist in the verified inventory but **cannot authorize an arbitrary file read**.
The inventory also works without a collection cache. Nested report trees and
unrelated cached paths are not recursively exported.

The hash-bound source snapshot is checked by the tar writer and rechecked before
publication. A late source change fails without replacing an existing output.
`archive.json.verified.authoritative_report_inventory` records schema1/profile
`librelane-native-direct-reports-v1`, producer/source references, SHA256s and byte
counts. No original run cache, report, record or evidence is rewritten. Historical
non-opt-in archive selection and unsupported named/checkpoint archive scope remain
unchanged; old archive differential cases pass.

### Genuine-path regression and verification

`test/timing_physical_flow/check.py` now uses the exact seven actual path shapes:

```text
project/runs/asic/40-openroad-checkantennas/reports/antenna.rpt
project/runs/asic/40-openroad-checkantennas/reports/antenna_summary.rpt
project/runs/asic/46-openroad-checkantennas-1/reports/antenna.rpt
project/runs/asic/46-openroad-checkantennas-1/reports/antenna_summary.rpt
project/runs/asic/62-magic-drc/reports/drc.magic.rpt
project/runs/asic/66-netgen-lvs/reports/lvs.netgen.json
project/runs/asic/66-netgen-lvs/reports/lvs.netgen.rpt
```

The modeled native producers have real regular config/State/runtime/report fixture
files. Public archive publication encodes them; restore uses only the produced tar
and loose records/input bundle. With original run/bundle hidden and original loaded
libraries unavailable, public collect and report JSON exactly equal the original,
including the complete raw-artifact list. There is no live-run copy into restore
and no normalization of the missing list. This is a genuine path/encoder/reader
regression, not a claim that fixture data is native physical acceptance.

Controls cover cached traversal/absolute paths, symlink files/report directories,
missing advertised reports, producer/version mismatches, incomplete native State,
bad runtime, byte/directory/advertisement bounds, unsupported producer namespaces,
non-authorizing arbitrary cache paths, no-cache selection, nonrecursive selection,
and late mutation after report encoding. The late-mutation case verifies rollback
preserves existing managed output and a user sentinel byte-for-byte.

Final command passed under switch5.2.0+ox / shared lock / explicit-j6:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @install @test/timing_physical_flow/runtest \
  @test/ocaml-archive @test/ocaml-archive-encoding \
  @test/ocaml-collect @test/ocaml-report @test/flow-cli
```

The isolated suite reports223 public/runtime/source checks. Existing16 archive
differentials, original publication/link/rollback/concurrency cases, streaming
archive-codec/corruption/supervision checks and affected CLI/results checks pass
(unchanged dependencies may be cached). No EDA or real native/full run was invoked.

### Actual read-only selection and source identities

B also invoked the corrected `Archive_service.inspect` consumer **read-only** on
C's exact unchanged actual run. Selection returns449 archive members, with all
seven required reports present and none missing. This member count includes extra
verified producer metadata and is not a replacement for the423 raw-artifact count.
B did not publish or hand-patch an archive from the actual run.

```text
4c86b6516f31b0c1c18a07364ab85b7c38a9122633debec2cafeac93befb415d  corrected archive_service.ml
4df32ca20f61f94672d63c293f2a605cdbb68f8b130e0e9f014d1e68cdc679e2  unchanged timing_physical_runtime.py
20b4288ce4ecb89577454edcaa489583fd8eeaed14f663888b59c9eba7fa9048  unchanged physical_runtime.py
```

The two unchanged runtime hashes were also checked against the actual retained
run's linked helper and check `bc95939552ae415c9a5aaa8c1fff1cfe`'s helper: exact
matches. New reader/helper capture must be identified separately from actual
execution provider `4856e6af993642988c18c07f47a8c689`; do not reattribute that run.

### C republication readiness

Use a fresh corrected reader generation, the **same actual completed RUN**, and a
new archive destination. No preflight, synthesis, native diagnostics, postcheck or
P&R rerun is requested:

```sh
"$CORRECTED_FLOW" archive "$UNCHANGED_RUN" --output "$NEW_ARCHIVE" --json
```

Verify the new archive inventory/profile and all seven member paths, then repeat
C's normal fresh hidden-input restoration and public inspect/collect/report parity.
Use the exact archived loose postcheck record as already fixed in C's restoration
consumer. Preserve both prior failed restorations and the original archive. Full
portable-source acceptance remains pending C's actual republication/replay and
independent actual-evidence review; the archive-only implementation fix is READY.

## R-THREADS — actual disposition and separate forward enforcement

2026-10-29. B read A's `timing-physical-final-review.md` resource finding and
independently read the actual retained wrapper and `COMMANDS` below. **The actual
run remains supported under its six-worker allocation.** The stronger blanket
claim of mid-PNR STA1 was incorrect. This correction does not request or justify
a new full run, change timing results, or relabel historical source/commands.

### Actual executed profile (provider4856, unchanged)

Run: `23a6954b852d4205b542d3815634d772`, provider
`4856e6af993642988c18c07f47a8c689`, original helper SHA256
`4df32ca20f61f94672d63c293f2a605cdbb68f8b130e0e9f014d1e68cdc679e2`.
All paths below are relative to its `project/runs/asic/` unless stated otherwise:

| Retained command source | Actual native launch policy |
| --- | --- |
| `31-openroad-stamidpnr/COMMANDS` | `openroad -exit -threads 1 -no_splash -metrics … openroad/sta/corner.tcl` |
| `36-openroad-stamidpnr-1/COMMANDS` | same timing script, **`-threads 6`** |
| `38-openroad-stamidpnr-2/COMMANDS` | same timing script, **`-threads 6`** |
| `43-openroad-stamidpnr-3/COMMANDS` | same timing script, **`-threads 6`** |
| `37-openroad-resizertimingpostcts/COMMANDS` | **`-threads 6`**, `openroad/rsz_timing_postcts.tcl` (physical repair) |
| Original standalone pre/post-PNR STA | `sta -threads 1 -no_splash -exit …` |
| Linked per-corner `native-process-0.json` | `sta -threads 1 …` |
| Linked per-corner `native-process-1.json` | annotation filter `openroad -threads 1 …` |

The original standalone post-PNR annotation filter is **not** the linked filter:
`55-openroad-stapostpnr/COMMANDS` shows its OpenROAD commands without an explicit
`-threads` flag. A's actual sampler observes peak1 for the inspected fast filter.
Do not convert that sample into an explicit command ceiling or attribute the linked
filter's argv to the original filter.

The mid-PNR six-thread requests stayed within C's explicit six-worker allocation,
container CPU ceiling6 and the global20 shared budget. No budget breach is asserted.
`STA_THREADS=1`/the `sta_workers` summary describe the standalone corner executor;
they are not observations proving that every OpenROAD mid-PNR engine requested1.
Actual `COMMANDS` have authority over the earlier broad label. The all-corner
extracted setup/hold/electrical results, physical/TT checks and final functional
replay are not invalidated by this methodology/label discrepancy.

### Exact cause and minimal future fix

The retained wrapper used `replacements.get(cls, cls)` keyed by exact class identity.
It replaced base STAMidPNR but missed occurrence classes made by LibreLane's ID
normalization. The provisioned LibreLane source shows:

- `flows/sequential.py:255–271`: `__normalize_step_ids` assigns repeated IDs by
  calling `step.with_id(id)`.
- `steps/step.py:1420–1431`: `with_id` constructs a **subclass** with the new ID and
  the original `_implementation_id`. The actual image's retained
  `timing-intent/native-sources/step-classes.py` also contains that implementation.
- `steps/openroad.py:517–530,548–563`: STAMidPNR inherits the normal OpenROAD command
  constructor, which uses configured `OPENROAD_THREADS=6`.
- ResizerTimingPostCTS/PostGRT derive from ResizerStep, not STAMidPNR. Lowering
  global OpenROAD threads would unnecessarily alter physical repair allocation.

The forward-only change is confined to `timing_physical_runtime.py`'s implementation
wrapper. `_bounded_sta_steps` wraps every **subclass** of the dedicated pre/mid/post
STA families, preserving each occurrence ID, original implementation ID, subclass
behavior, scripts and all other argv. Only dedicated STA's thread argument is set
to1. Non-STA classes remain the same objects with identical commands. No global
OPENROAD_THREADS6, pool6, KLayout, placement/CTS/routing/repair or numerical timing
policy is lowered or rewritten. Closed native-command shape checks remain.

The configured metadata remains6 for ordinary OpenROAD. The parent's verbose
`OpenROAD will use 6 threads` line can therefore precede the STA-only argv override;
that line is not a measurement or the final launch command. Qualification checks
the constructed argv, not the inherited verbose text.

### Focused non-EDA verification and attribution

`test/timing_physical_flow/launch_policy.py` is a durable command-only test. It
covers base classes, pre-existing `with_id` aliases, custom derived STA subclasses,
aliases/normalization created after policy installation, preserved IDs/scripts,
unchanged physical repair6, a misleading non-STA name and seven malformed alias
command rejections. Subprocess launch is prohibited by the test. It is included
in the normal isolated runtest target.

An additional explicit mode imports actual provisioned LibreLane3.1.0.dev3 and
constructs commands for all four normalized Classic mid-STA occurrences, pre/post
STA and both resizer timing-repair classes. It calls no Flow.start/Step.start/native
tool: inert command-only objects have OPENROAD_THREADS6. All four mid commands
become1; repair commands and class identity stay6/unchanged. This is installed host
API/source qualification, **not execution inside the original image**.

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @install @test/timing_physical_flow/runtest

opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  .toolchain/.venv/bin/python -B test/timing_physical_flow/launch_policy.py \
  flow/hardcaml_asic_flow/timing_physical_runtime.py --installed-librelane
```

Both pass; the223 isolated public/runtime/source checks still pass, with the new
focused launch-policy rule reported separately. Affected old coarse/named timing,
coarse execution, archive/codec, collect/report and CLI compatibility checks also
pass under the same switch/lock/-j6 policy. No EDA was run.

```text
4df32ca20f61f94672d63c293f2a605cdbb68f8b130e0e9f014d1e68cdc679e2  original executed/retained runtime
887985abdfb8a829d52f9eaccb081c56bb7d7e25bb4982dc6fcfe9fd9b0c23fa  forward alias-policy runtime (UNEXECUTED)
```

**Do not attribute the forward hash or thread1 aliases to provider4856.** A new
reader/archive capture may contain this file, but archive republication only reads
the original retained execution sources; it does not execute the forward helper.
C's current corrected-archive work can continue independently, from the same
unchanged actual run. Archive-source correction `archive_service.ml` hash
`4c86b6516f31b0c1c18a07364ab85b7c38a9122633debec2cafeac93befb415d`
is unchanged by this thread-policy fix. No original evidence, archive, provider
selection, PDK, native result or physical repair was edited or rerun.
