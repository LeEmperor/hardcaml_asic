# PT.7c B — ordinary coarse synthesis integration handoff

2026-10-28. Published before integration. Scope follows `pt7c-native-flow.md`:
new producer-bearing bundles, ordinary coarse synthesis only. Named executions,
checkpoint recipes and post-PNR capture are deferred.

**Active integration:** the review corrections at the end of this handoff supersede
the initial wire details below. Fresh capture requires A's native-data/profile 2,
the historical execution-root fields and explicit consumed-source associations.

## A/B seam (agreed against A's published native handoff)

- Opt in only through the identity-inventoried member
  `constraints/pt7-native-coverage.tcl` plus nonempty `timing_intent`.
- A owns schema-2 audit validation in `Timing_intent_evidence.inspect ~directory ()`.
  B calls that API, preserves standalone schema-1 routing, and never rerenders Tcl.
- Each executed corner has an independent schema-2 audit directory. Required
  schema-1 roles remain; A adds native SDC, diagnostics/endpoints/raw report roles
  and the retained generated producer. Concrete added spellings follow A's handoff.
- Audit context remains `producer.tool=OpenSTA`, `stage=synthesized_netlist`,
  `scope=standalone_synthesized_netlist_sta`. Outer companion binds ordinary
  provenance separately. Added roles are exactly A's `native_producer`,
  `native_sdc`, `native_data`, `native_checks`, `native_endpoints`; the first joins
  receipt input roles. The provider sources the retained producer then calls
  `::hc_pt7_native::write $output_directory` through the extra-corner hook.
- Receipt precedes the single SDC resolution/application block. The extra-corner
  producer runs after this block; hook completion does not prove process success.
  Wrapper records actual corner argv, exit, native version and input closure.

## Layout and immutable association

`RUN/timing-intent/` is separate from `RUN/project/runs/asic`:

```
request.json              exact run/build, primary synthesis process, runtime
analysis.json             immutable companion, status and full hash-bound sources
runtime.log               complete provider helper output
transport.json            observed immutable runtime binding and actual argv
transport-result.json     actual supervised process outcome/cleanup
effective-config.json     filtered, resolved runtime analysis configuration
configuration-delta.json  four explicit original/effective analysis settings
runtime-result.json       synthesis refs and requested/actually executed corners
corners/<corner>/         actual native step directory and schema-2 audit closure
```

The provider helper selects exactly the completed `Yosys.Synthesis` producer from
the ordinary run by metadata (not latest/ordinal guesses), retains its config and
state, and binds its exact `nl`. It loads resolved config, applies the explicit
typical-only corner delta (`DEFAULT_CORNER`), `STA_THREADS=1` and the retained
producer hook. It runs `STAPrePNR.start`, not a Classic/floorplan prefix. Requested
and executed corners are recorded independently. No synthesis state is overwritten.

All new PT7 producer runs use six or fewer workers from preflight onward, including
container quota, LibreLane jobs, thread environment and explicit tool flags. STA
is serialized. Runtime transport uses the preflight's exact image binding,
cancellation and cleanup. B runs no EDA.

## Public interface

New `Timing_intent_flow.inspect ~run_dir ()` returns a checked evidence envelope,
including explicit historical unavailable / expected-but-missing diagnostics.
`Timing_intent_flow.source_files ~run_dir ~context ()` supplies verified run-relative
source references for collection/archive replay. New coarse CLI:

```
hardcaml-asic-flow timing-intent-inspect RUN --kind coarse_run --json
```

Omitting `--kind` retains standalone schema-1 behavior. Coarse reports/collection
include `timing_intent`; unavailable exhaustive coverage never becomes a pass.
Invalid advertised evidence contributes an explicit collection/report error and
is rejected by inspection/archive. Archives retain all advertised sources,
including loaded libraries, and replay without current PDK/provider/emitter.

## Verification and C commands

Implemented B modules: `Timing_intent_service.capture`,
`Timing_intent_flow.{expected,inspect,source_files,publish}` and the installed
`timing_intent_runtime.py`. Capability `timing_intent_flow1` explicitly reports
`named_execution=false`; `timing_intent_evidence2` advertises schema-2 reading.
Historical bundles retain their old collection/report shape; explicit coarse
inspection reports unavailable. A new advertised producer with missing evidence
is an error, never historical absence. Valid failed supervised analysis retains
its failure companion and process sources; the enclosing run fails.

The new run record sets `timing_intent_expected=true` before preflight, so even a
missing staged manifest cannot silently downgrade collection to historical absence.
It additionally retains `synthesis_process` (actual supervised
outcome/code/success and argv). Its argv is checked against the run's primary
command and bound into the analysis request. `analysis.json` sources are all
run-relative; the complete source inventory is replayed and rehashed, including
native audit sources, original synthesis state/config/netlist/resolved config,
actual per-corner version/process results, helper/driver/hook and libraries.
Historical absolute native paths remain labels after restore; only the explicit
retained run-relative association is read. No current PDK or tools are queried.

The companion allows at most 512 sources, 64 MiB/source and 512 MiB total; metadata
reads are bounded at 8 MiB with duplicate JSON keys rejected. Inner audits retain
A's tighter role-specific bounds. Toolbox scratch files are not advertised source
evidence. Source hashes/receipts are producer assertions, not authenticated execution.

### C: fresh ordinary route

Use a fresh PT7c provider and freshly emitted **Synthesis**, macro-free bundle.
`FLOW` is the new provider's absolute `hardcaml-asic-flow`; `PYTHON`, `TT`, `PDK`
are explicit already-provisioned paths. `EVIDENCE` is a fresh C-owned directory.
No provider refresh, provisioning or EDA has been performed by B.

```sh
"$FLOW" --version --json > "$EVIDENCE/provider.json"
"$FLOW" run "$BUNDLE" --stage synthesis --support-tools "$TT" \
  --pdk-root "$PDK" --python "$PYTHON" --runs "$EVIDENCE/runs" \
  --json > "$EVIDENCE/run-outcome.json"
RUN=$(jq -er .run_dir "$EVIDENCE/run-outcome.json")
"$FLOW" collect "$RUN" --json > "$EVIDENCE/collect.json"
"$FLOW" report "$RUN" --json > "$EVIDENCE/report.json"
# Expected exit 1: valid retained evidence, exhaustive coverage unavailable.
INSPECT_STATUS=0
"$FLOW" timing-intent-inspect "$RUN" --kind coarse_run --json \
  > "$EVIDENCE/timing-intent.json" || INSPECT_STATUS=$?
test "$INSPECT_STATUS" -eq 1
"$FLOW" archive "$RUN" --output "$EVIDENCE/archive" --json \
  > "$EVIDENCE/archive-result.json"
```

Handle inspection's expected exit 1 explicitly in a `set -e` launcher. Its JSON
must show `status=completed`, exact native stored scopes/diagnostic dimensions,
and `verdict=unavailable`; exit 1 by itself is not acceptance. The per-corner inner
audit is `RUN/timing-intent/corners/<DEFAULT_CORNER>/audit.json` and is also readable
through standalone inspection. The supported runtime is the qualified immutable
image (`d109140b…`), LibreLane 3.1.0.dev3 and OpenSTA 2.7.0. Other versions reject.

The analysis deliberately requests only `DEFAULT_CORNER`. The original configured
corner list, the exact four-setting delta, and actual executed corner are exposed
separately. `STA_THREADS=1`, native `sta -threads 1`, six-worker synthesis flags and
container quotas are explicit. No all-corner or P&R acceptance follows.

Restore `archive/run.json` plus `reports.tar.gz` at a fresh root, then overlay
`input-bundle.tar.gz`'s `bundle/` contents into `project/`. Run the same explicit
coarse inspection on that restored root. Replaying requires neither current
PDK files nor the original source root. C must preserve native failures and run
its separately labelled diagnostic controls without editing the baseline bundle.

### B verification

All Dune calls used switch `5.2.0+ox`, explicit `-j6` and the shared
`/tmp/opencode/asic-pt7-build.lock`. No EDA was run.

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/timing_intent_flow test/timing_intent_evidence \
  test/timing_native_coverage
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @test/ocaml-collect @test/ocaml-report @test/ocaml-archive \
  @test/flow-cli @test/ocaml-coarse-run @test/ocaml-preflight
```

The initial isolated suite passed **58 public/orchestration/replay checks**. It
executes the real public coarse CLI over fake external tools,
the actual supervised transport over a fake Docker executable, and native-schema
source replay over synthetic engine output. It checks bounded workers, exact
synthesis handoff, source/config/producer/corner linkage, hook-then-process failure,
unexecuted corners, real timeout/cancellation, changed sources, duplicate keys,
object-order equivalence, read-only collection/report and actual archive/restore.
These are orchestration/parser tests, not native acceptance. Legacy collection
(131 differentials), report (585), archive (16), coarse (15 record/outcome plus
aggregate/cancellation/presentation cases), preflight (24 plus 72 cancellation
publication cases), and CLI regressions passed. The longer preflight/coarse run
initially exceeded 120/300-second command windows; rerunning with a 900-second
window completed both successfully, with no orphaned test processes.

**Initial B handoff:** isolated suite 58 checks; `dune build -j6 @install`
and schema-1/schema-2 evidence regressions pass. All B source remains uncommitted.
The qualified-image native Step API route still requires C's actual execution and
counterfactual controls; fixture success is not relabelled as native acceptance.
No B implementation blocker is currently known. New producer bundles are supported
only by this macro-free coarse synthesis route; unsupported native/full/macro
requests reject explicitly before launching synthesis.

## B-REAL-1 — native Tcl bootstrap correction, ready for fresh C capture

C's real ordinary `coarse-integration-02` synthesis reached the linked STA step
and failed at wrapper line 1, before any receipt or SDC resolution:

```
Error: driver.tcl, 1 can't read "::env(PT7_RECEIPT)": no such variable
```

Read-only source evidence: example `docs/pt7c_native_findings.md`,
`acceptance/pt7c/runtime-api-06/stdout.log`, and original run
`.dev/asic-pt7c/probe-runs/20261028T164800799130Z_44ded577/`. Actual
`TclStep._reroute_env` puts changed, non-allowlisted `PT7_*` values into
`_env_ThreadPoolExecutor-1_0.tcl`. Only `_TCL_ENV_IN` identifies this file in the
native process environment. The earlier synthetic Step fixture did not model
that startup boundary and therefore missed a real defect.

Corrected `timing_intent_runtime.py`'s retained `DRIVER` startup sequence:

1. Enter the error handler and source `$::env(_TCL_ENV_IN)`.
2. Read the rerouted receipt path and print exactly one `PT7_AUDIT_RECEIPT`.
3. Source the normal LibreLane corner script, which performs linking and the
   **only SDC load**, followed by native producer/standard reports.
4. Print `PT7_AUDIT_COMPLETE` only after that script returns successfully.

The normal `common/io.tcl` bootstrap re-sources the assignment file; this does
not read the SDC or produce another resolution block. B does not source the SDC
early, move the receipt after resolution, bypass `_reroute_env`, or rely on direct
`PT7_*` process variables. Bootstrap/receipt failures are now inside the same
catch as the native corner script: `PT7_ERROR` plus explicit exit 1, no successful
completion marker. No audit/receipt/event schema or A-owned implementation changed.

Verification with switch `5.2.0+ox`, shared ASIC lock and explicit `-j6`:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/timing_intent_flow
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @install @test/timing_intent_evidence/runtest \
  @test/timing_native_coverage/runtest
```

- **11 real-Tcl startup checks** run the actual wrapper under `tclsh` with fixture
  corner/SDC operations. They model rerouted-only fields, stale direct fields,
  normal double environment bootstrap, exactly one SDC load, receipt-before-wire
  and completion-after-standard-reports. Missing pointer/file/receipt/corner,
  broken bootstrap, SDC/hook/report failures all terminate nonzero. Removing the
  new bootstrap reproduces the original missing-`PT7_RECEIPT` failure.
- **64 public/orchestration/replay checks** pass. Three added hash-consistent
  provenance negatives reject receipt-after-resolution, duplicate SDC wire blocks,
  and the actual startup diagnostic despite an asserted native process exit zero.
  Rejections check intended reader diagnostics, not incidental changed hashes.
- Install packaging builds, and existing schema-1/schema-2 reader regressions pass
  (cached results remain valid where their dependencies were unchanged).
- The original failed run remains a failure: all **30 advertised companion source
  hashes** still match, its native exit is still **1**, and its original error log,
  wrapper, generated environment and process receipt were not changed.

**B ready for C's fresh recapture.** Capture the corrected provider and use the
same ordinary CLI commands above, coordinating A's separate real-writer grammar
fix. The old failed run must remain retained; do not replace its wrapper, inputs,
summary or identity. B ran no EDA and does not infer native success from the Tcl
fixtures. Fresh actual synthesis/STA, public inspection/archive replay and C's
controls remain required before native acceptance.

## B-R1–B-R5 — implemented independent-review corrections

Read `pt7c-flow-review.md` and retained review reproductions without changing them.
The five findings are corrected in the runtime and read-only source verifier.
This is a new source capture requirement, not a repair or reinterpretation of
earlier C runs. C's existing native success remains evidence for its original
captured implementation; fresh production/inspection/archive replay must qualify
these corrections and A's changed native producer.

### Exact source association — B-R1/B-R2

`request.json` now additionally retains:

```text
execution_root: canonical absolute run directory at execution time
host_uid, host_gid: nonnegative recorded execution IDs
```

The reader uses these **historical labels**, never current filesystem lookups of
the original root. All run-owned executed pointers must agree with that one root:
launched helper/request, synthesis state netlist, resolved SDC, native directory,
driver, hook and corner script. Restoring the evidence elsewhere does not change
the historical root or require the original root, PDK, UID or GID to exist.

Each `native-inputs.json` adds:

```json
{
  "libraries": [
    {"actual_path":"<historical run>/<corner>/library-0.lib",
     "retained":{"path":"timing-intent/corners/<corner>/library-0.lib",
                 "sha256":"<exact retained bytes>"}}
  ],
  "corner_script": {
    "path":"timing-intent/corners/<corner>/librelane-corner.tcl",
    "sha256":"<exact retained bytes>"
  }
}
```

The complete nonempty Liberty sequence must match both the decoded
`_CURRENT_CORNER_LIBS` Tcl list and the inner audit's ordered Liberty source list.
Order/multiplicity are preserved; no sorting, deduplication or basename matching
is used. Every actual path must identify its exact run-relative copy and hash.
A bounded, nonexecuting Tcl-list decoder handles the qualified list quoting and
escaping; no Tcl evaluator or current renderer runs during inspection. Equivalent
quoted/braced lists and historical paths containing spaces, brackets and dollar
signs have passing controls.

The runtime now **executes the retained `librelane-corner.tcl` copy**, not the
original image-path pointer. Its source bytes are copied/hash-checked from the
qualified image's normal Step script. `PT7_CORNER_SCRIPT` must point to that exact
retained source, while its native common/io dependencies remain associated with
the immutable image. Wrapper receipt/bootstrap ordering and single SDC loading
remain as documented in B-REAL-1.

### Archive expectation — B-R3

Archive now invokes timing source replay when **either** the manifest advertises
the producer **or** `run.timing_intent_expected=true`, matching collect/report and
explicit inspection. The exact reviewed producer-declaration-removal mutation
now fails archive selection with the same missing-advertised-producer diagnostic
as inspection; collection marks it invalid and report rejects its invalid bundle
identity. Historical absence is reserved for records without the expectation.

### Terminal truth and resource argv — B-R4/B-R5

Both completed and failed companions validate the closed transport-result shape:

| Outcome | Allowed code |
| --- | --- |
| `exited` | integer 0–255 |
| `signaled` | positive POSIX signal <128 |
| `cancelled` | 2 or 15 |
| `timed_out`, `failed` | null |

`succeeded` must be Boolean and equal exactly to `exited/code=0` with no recorded
cleanup error. Cleanup is null or a nonempty error string. The writer now retains
both supervisor and owned-container cleanup errors and normalizes native signal
codes to POSIX values. A completed companion cannot override a cleanup failure.
Valid failed attempts return failed/unavailable without interpreting partial
native audits. A successful native process followed by failed post-runtime
identity verification also remains a truthful failed analysis.

For both synthesis and analysis, the verifier reconstructs the **qualified
generated Docker argv** from the recorded binding, historical roots, owned name,
UID/GID, six-worker policy, interpreter flags and exact payload. It validates
image position, entrypoint, mounts/workdir, worker environment and script paths
together, rather than looking for expected tokens anywhere. Duplicate or
conflicting CPU options in either spelling, overridden worker environment,
alternate entrypoints and unrelated script roots reject. This is the provider's
qualified generated argv protocol, not admission of arbitrary Docker CLI forms.

### A native-v2 coordination

Consumed A's latest `pt7c-native-handoff.md`: manifest/native-data schema 2,
`opensta-2.7-native-state-v2`, category-framed raw diagnostics and
`HC_ASIC_NATIVE_V2_COMPLETE`. Outer audit stays schema 2, and all five native
source roles/receipt ordering are unchanged. Completed inspection still calls
the unchanged outer `Timing_intent_evidence.inspect` API. B's independent pure
adapter now passes mandatory `~top`. Fixtures include the exact leading native
design selection and new framing. Capability `timing_intent_evidence2` advertises
native-data schema 2/profile 2. Legacy v1 native capture requires explicit fresh
capture; coarse execution rejects a v1 producer profile before allocating a run
or launching any tools. Audit-schema1 standalone compatibility remains A's
original contract.

### Verification / ready for recapture

All commands used switch `5.2.0+ox`, the shared ASIC lock and explicit `-j6`:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/timing_intent_flow test/pt7c_native_review
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @install @test/ocaml-collect @test/ocaml-report \
  @test/ocaml-archive @test/flow-cli @test/timing_intent_evidence/runtest \
  @test/timing_native_coverage/runtest
```

- **150 public/orchestration/replay checks** pass in the durable B suite. New
  hash-consistent negatives cover every B-R1–B-R5 reproduction, reordered/missing/
  duplicate libraries, coherent wrong driver/hook roots, malformed failed terminal
  records, unknown outcome/code combinations, duplicate CPU flags and worker/env/
  entrypoint overrides. Exact rejection diagnostics are asserted. Public archive
  publication also rejects the downgrade before creating an output directory.
- **11 actual Tcl startup checks** still pass. Valid archive/restore, equivalent
  Tcl-list quoting, and rootful historical UID/GID replay at a different current
  root remain positive. The original external library files are removed for the
  durable archive replay control.
- Actual transport/supervisor over a fake Docker client verifies timeout,
  cancellation, SIGTERM, later native failure, owned cleanup failure after native
  success and failed post-runtime verification. All return failed/unavailable
  without promoting native coverage; malformed source records reject instead.
- Reran A's independently authored original review script against the corrected
  implementation at a **new** destination:
  `python3 -B /tmp/opencode/pt7c-flow-review.py /tmp/opencode/pt7c-flow-review-fixed-b`.
  All reported mutations reject; baseline and actual archive encoding/restore
  remain completed/unavailable. Results are in that new directory's `results.json`;
  the original review/failure directories were not overwritten.
- Independent native-v2 review reran **80 probes**: A-NATIVE-R1/R2/R3 now reject on
  continued-comment, category/raw mismatch and native-top mismatch diagnostics.
  This is non-EDA reader/producer-model verification, not C's native qualification.
- Install packaging, legacy collect (131 differentials), report (585), archive
  (16), CLI, schema1 evidence (54 plus 27 review regressions) and A native-v2
  checks (120) pass. The optional historical retained-finalization fixture remains
  unavailable as reported by the existing harness; it was not counted as passed.

**B ready for C's fresh provider/bundle capture and real coarse acceptance.** Use
the ordinary commands above; capture the new request/native-input fields and A's
changed emitted producer/build identity. No EDA, provider activation, Git mutation,
Workbench/Protemu work or historical evidence edits were performed by B.
Remaining limits are unchanged: macro-free coarse synthesis, one explicit default
corner, no named/checkpoint/P&R integration, no authenticated execution, and no
passing exhaustive exception-effect or timing-closure claim.
