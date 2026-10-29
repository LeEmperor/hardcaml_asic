# Independent A review of B physical timing flow

2026-10-29. Review after B's initial 116 modeled-boundary checks. A reviewed B's
code and exercised independent source-rebound cases; A made no B implementation
edits and ran no EDA. C's reported 198 native precontrols are separate evidence;
the full physical run had not launched at review request.

## Final reviewer disposition

**F1–F6 independently verified addressed.** The original repro script was replayed
against B's corrected binaries, followed by ten focused negative/true-positive
controls. Malformed metrics now remain **unknown**, missing/commented/repeated
serialized primary-clock propagation rejects, and actual filter script/report/ODB
sources are checked against the qualified causal association. See the final
verification section below for exact results and snapshot hashes. No new major
issue was found in this bounded fix verification. This closes the implementation
review findings; it does not claim closure of C's physical run or native timing.

## Initial verdict (historical): corrections required before physical acceptance

The exact extracted SPEF/native input associations and several fail-closed gates
work in the reviewed snapshot. The following independently reproduced gaps allow
contradictory or incomplete physical evidence to retain completed/pass goals.
These are local retained-source consistency findings, not claims of authenticated
execution or arbitrary-tampering resistance.

| ID | Severity | Finding |
| --- | --- | --- |
| F1 | High | Propagated-clock JSON can contradict missing/commented native serialized propagation while timing remains pass. |
| F2 | High | Recorded annotation filter/hook execution paths can differ from the qualified retained/effective script association. |
| F3 | Medium | Filter's actual `checks.rpt` input can be absent from the retained source closure while annotation remains pass. |
| F4 | High | RCX output ODB need not match original post-PNR STA input/filter ODB. |
| F5 | Medium | Selected original post-PNR STA producer need not follow RCX; intermediate State view paths can be dangling. |
| F6 | Medium | A malformed second metric record for the same required corner/key is silently ignored, leaving pass. |

## Reproduction and tested snapshot

Independent script: `test/timing_physical/review_flow.py`. It borrows only B's
modeled native fixture construction, not B's negative tests. The actual production
runtime builds the fixture's audit/association structure, then A copies it per
case and recomputes receipt/log/process, inner audit, input-selection, runtime,
progress and outer companion source hashes bottom-up. Rejections therefore test
semantic association checks rather than a stale digest. Baseline passes with
three executed corners and all-corner timing pass; exhaustive coverage stays
unavailable.

Build and run (no EDA):

```sh
flock /tmp/opencode/asic-pt7-build.lock opam exec --switch=5.2.0+ox -- \
  dune build -j6 test/timing_physical_flow/emitter.exe \
  test/timing_physical_flow/consumer.exe bin/flow_cli.exe \
  @test/timing_physical_flow/runtest
python3 -B test/timing_physical/review_flow.py
```

Initial independent run retained at
`/tmp/opencode/timing-physical-flow-review-o17oebs_/results.json`, with separate
case directories and copied binaries/helpers. The script records raw exit/stdout/
stderr; observed stdout contains the complete public reader response. The existing
B runtest target was up-to-date in this invocation (no new 116-test execution is
attributed to this build). Independent mutations actually executed.

Reviewed source hashes at that run:

| Source | SHA256 |
| --- | --- |
| `flow/hardcaml_asic_flow/timing_physical_runtime.py` | a2290a232cc5c20797c316d10fe5ca26c1b3be4b156bc9d4f924f6be531e32f7 |
| `execution/results/timing_physical_flow.ml` | 0e2992952b801d0a0588e3649938e97569cfb866105e02367ccddddb27f31033 |
| `execution/results/timing_physical_metrics.ml` | b204035723dc8f767e3775d3d6c9cdaf44bf4454ba389be5e199dde52a864ab5 |
| `execution/results/timing_native_coverage.ml` | 7ad6af1df5958b547847793924a930e5fadafea8b5c6cf9d7cb77edf6ec057f7 |
| B fixture `test/timing_physical_flow/check.py` | c292c72ea166d5a8557c9090327ddaca567fde4d699b3dbccbd38c2f5b34ed9a |

## Findings

### F1 — serialized/native clock-state contradiction (High)

Locations: `timing_native_coverage.ml:203–231,246–249` and
`timing_physical_flow.ml:305–313`.

Repros `missing-propagation` and `propagation-commented-out`: remove/comment
`set_propagated_clock [get_clocks {clk}]` from the retained native state (and its
exceptions copy), retaining `clock-state.json` all_propagated=1. Rebound public
inspection exits0, status completed, all-corner timing pass, annotation pass.
The parser's new flag permits the command but does not require native stored
propagation to agree with the JSON observation.

Required correction: keep historical schema2 behavior, but at the physical
qualification boundary require the qualified serialized primary-clock state and
the native observation to agree. Do not let command admission stand in for
presence/propagation evidence. Add matching positive/commented/missing controls.

### F2 — executed filter script not bound to retained source (High)

Locations: `timing_physical_runtime.py:243–264` and
`timing_physical_flow.ml:330–354`.

Repro `filter-executed-script-substitution`: change only
`filter-inputs.json.script_path` and its matching native-process argv member to
`/tmp/independent-always-zero.py`. The retained filter script and native-sources
script remain unchanged/equal. Rebound inspect exits0 and all annotation goals
pass, even though the recorded executed script is not that retained script.
The reader reconstructs expected argv from the same unchecked script_path claim.

Required correction: execute the retained script with a qualified dependency
layout, or independently constrain the image script path to the exact qualified
image-owned source/dependency association. Preserve archive replay without
consulting current image/PDK paths. Test path substitution with unchanged retained
bytes as well as source-byte substitution.

Expanded repro `actual-native-hook-substitution` also changes only actual
`native-inputs.json.environment.STA_EXTRA_CORNER_TCL_FILE` to
`/tmp/unrelated-hook.tcl`, leaving effective config and retained hook unchanged.
It too completes/pass. The reader checks `PT7_CORNER_SCRIPT` and other input
environment keys but not actual extra-corner hook equality to effective config.
Bind that actual executed hook path/source as part of the same correction.

### F3 — actual annotation input report omitted (Medium)

Locations: `timing_physical_runtime.py:126,239–276` and
`timing_physical_flow.ml:349–366`.

Native LibreLane's filter consumes `checks.rpt`, **not** the hook's standalone
`parasitic-annotation.rpt`. Repro `filter-input-report-not-retained` deletes that
report and removes its optional outer source entry, then rebinds. Inspection
still exits0 with annotation pass. The argv name is checked but required retained
report bytes are not. This breaks replayable input closure for the measurement
used to gate extracted annotation.

Required correction: make the actual filter report a required source and bind
it to the recorded filter invocation; do not substitute the hook report as its
provenance. Retain the existing explicit filtered scope. Raw unannotated drivers
alone do not disprove a zero wired-net-filter count; the separate
`raw-annotation-contradicts-zero` observation is **not** classified as a bug.

### F4 — RCX/STA/filter physical database mismatch (High)

Locations: runtime `select` at `timing_physical_runtime.py:94–104`; reader
`timing_physical_flow.ml:248–262,335–348`.

Repro `rcx-odb-not-sta-input-odb`: change RCX output State `odb` to an unrelated
historical run path, keeping its nl/spef and the original STA input/filter ODB
unchanged. Rebind both selection/result refs and all sources. Inspection exits0
with annotation pass. RCX→STA association checks nl/spef only; the filter is
bound to STA input ODB, not also to the RCX physical database.

Required correction: bind the RCX physical database to the original STA input
ODB/filter input (exact retained bytes/path association), using an explicit
qualified transition if the actual native pipeline changes that view. A zero
filter result from a different layout is not the extracted layout's annotation
result. Add a valid ODB-match positive and this source-rebound negative.

### F5 — incomplete physical stage association (Medium)

Locations: `timing_physical_flow.ml:214–224,251–262` and runtime `select`.

Repro `post-sta-producer-before-rcx`: rename selected original producer directory
from ordinal06 to00 and rebind all selected refs; inspection still completes/pass.
Only the four physical-chain ordinals are compared with one another, not with
the selected original STA producer or originating synthesis.

Repro `cts-output-not-associated-to-later-state`: change CTS output State nl/odb
to nonexistent historical view paths. Retained State/config/runtime files still
hash correctly, so inspection still completes/pass. The four States are retained
as disconnected provenance records rather than checked view-bearing lineage.
Do not require CTS and routed netlists to be identical—repair legitimately
changes them. The bounded fix is actual ordered producer association and retained
closure/association of claimed physical views, not blanket equality across repair.

### F6 — malformed duplicate native metric silently skipped (Medium)

Location: `timing_physical_metrics.ml:18–29`.

Repro `malformed-second-setup-metric`: append
`%OL_METRIC_F timing__setup__ws__corner:nom_fast_1p32V_m40C -0.5 unexpected`
while retaining the valid positive record and matching output State. Inspection
still reports all-corner timing pass. The tokenizer only counts exactly three
tokens, silently discarding a malformed record with the same recognized key.

Required correction: distinguish irrelevant log text from malformed/duplicate
records for required native keys. Such records cannot earn pass; return unknown
or invalid. Exact duplicate, missing record, and log/State mismatch already
correctly yield unknown. Preserve those controls.

## Checks that held in the initial independent run

* Wrong retained SPEF bytes, wrong-corner original SPEF association, and a changed
  actual `_CURRENT_SPEF_BY_CORNER` path reject even after source rebinding.
* Missing executed corner rejects against progress/actual process association.
* Failed native STA/filter process and `sta -threads 20` reject.
* `clock-state.json all_propagated=0` rejects.
* Wrong propagated clock name and backslash-continued native comment reject;
  explicit literal-list wrapping of the same `clk` selector is accepted.
* Consistent negative hold remains valid completed evidence with timing **fail**.
  Missing setup metric, conflicting hold log/State and duplicate setup record
  remain completed evidence with timing **unknown**, not pass.

## Completed targeted review: terminal, downgrade, State and ceilings

Expanded final run:
`/tmp/opencode/timing-physical-flow-review-e6c8plga/results.json`.
All five source hashes above remained unchanged. **38 observations** were
executed/retained: baseline, 34 copied/rebound cases, two modeled helper-failure
cases and one implementation worker model. This is an observation count, not
38 passing acceptance tests: F1–F6 intentionally retain unexpected acceptances.

Additional verified controls:

* Replacing linked Step input State's netlist rejects with `linked Step did not
  consume exact implementation INPUT State`. Source review confirms the runtime
  loads original `STAPostPNR/state_in.json`, not its output State; its nl is
  separately tied to the retained consumed mapped.v. This important part is sound.
* Coherently downgrading an inner physical audit to schema2/synthesis (including
  receipt/input closure and removing serialized propagation) still rejects at
  the outer native audit stage/corner/producer check.
* Removing the physical marker while preserving its persisted expectation rejects;
  removing the expectation while preserving the marker still selects/replays the
  physical reader. Either advertisement prevents a fallback to historical absence.
* Declared transport workers20, Docker `--cpus=20`, and native STA threads20 reject.
  Implementation wrapper's API model verifies TPE6 and pre/mid/post STA threads1,
  with ordinary Classic steps retained. Source review also confirms the linked
  executor is forced to one and drained before corner progress publication.
* A failed transport code or cleanup error contradicting `succeeded=true` rejects.
  A consistently failed terminal/companion returns status failed, timing unknown,
  and no completed-corner coverage view, even if old completed files remain.
* Running the actual helper over the modeled native boundary with late failure
  records all three drained process observations, Step incomplete, no success
  runtime result, and public failed/unknown. A missing-corner run records two
  executed, typical not-observed, no success runtime result, and failed/unknown.
  The native Step can complete in this latter case; the additional actual-corner
  requirement correctly prevents promoting that Step completion to qualification.

Cancellation/timeout/publication obstruction have B's initial supervised fake-
Docker tests plus A's source inspection of `timing_intent_service.ml:64–101`;
A did not independently re-execute those transport scenarios. The code preserves
primary cancellation/timeout failures and adds cleanup/publication diagnostics.
Postcheck review was limited to the requested allocation seam: bounded marker
selects six workers and default1800s, with existing affinity/Nix/container limits.
B's ongoing functional-replay generalization is outside this review's edits and
is not independently qualified here.

## Closure and parser interpretation

The native SDC addition stays in the existing closed LF-only, no-evaluation
grammar. Wrong clock collections, unsupported commands, CR/continued-comment
semantics and historical inspect separation were inspected; targeted wrong-name
and continued-comment cases reject. Explicit literal-list wrapping of the exact
primary collection is semantically equivalent and its acceptance is not widening.
F1 concerns required stored-state presence/agreement, not an ability to evaluate
arbitrary Tcl.

Per-corner timing uses one recognized native log metric + matching linked output
State and parsed ns Liberty units, separately from sampled witnesses. Fail and
unknown remain distinct; F6 is the malformed-record hole in that otherwise
conservative gate. `Report_service.ml:72–85` requires complete executed nominal
fast/slow/typical coverage, all-corner setup/hold pass, electrical pass and
annotation pass for Full, in addition to ordinary physical/external requirements.
The fixture does not satisfy all ordinary physical acceptance requirements;
**this review does not claim an end-to-end full report was falsely accepted**.
The demonstrated defect is false pass in required timing/annotation/provenance
components, which must be corrected before relying on full acceptance.

No B implementation file was changed. Reproduction script and this review are
A-owned additions. No EDA, Git mutation, provider changes, Protemu/Workbench work,
or functional-replay redesign was performed. B should fix the six findings in
its own slice and rebind/replay these cases; C's actual full-flow results still
require separate independent evidence review after the bounded launch.

## Final independent fix verification — F1–F6 closed

2026-10-29. B implemented the corrections; A did not edit B's files. C's first
full physical execution is separate from this no-EDA verification. No broad
duplicate suite, provider operation, Git mutation or physical launch was run.

### Actual commands and retained results

Only the required binaries were built, switch `5.2.0+ox`, at most six jobs under
the shared ASIC lock:

```sh
flock /tmp/opencode/asic-pt7-build.lock opam exec --switch=5.2.0+ox -- \
  dune build -j6 test/timing_physical_flow/emitter.exe \
  test/timing_physical_flow/consumer.exe bin/flow_cli.exe
python3 -B test/timing_physical/review_flow.py
python3 -B test/timing_physical/verify_flow_fixes.py \
  /tmp/opencode/timing-physical-flow-review-onl8iuwy
```

* Original **38-observation** replay:
  `/tmp/opencode/timing-physical-flow-review-onl8iuwy/results.json`.
  The original mutation script was used unchanged. It captures the binaries and
  helpers and retains the full reader output/case artifacts.
* **10 focused follow-up controls**, all asserted as expected:
  `/tmp/opencode/timing-physical-fix-controls-rhofta1v/results.json`.
  A-owned script: `test/timing_physical/verify_flow_fixes.py`. It also asserts
  the original replay's required rejections and fail/unknown outcomes. The control
  script uses that replay's captured consumer and passing baseline, not a newer
  uncontrolled binary. Both scripts retain old review products unchanged.

These are modeled-boundary association/reader checks, not native STA/ODB/repair
executions. The original repros and new positives share a passing three-corner
baseline; source rebinding remains bottom-up rather than warning-and-skip.

### Per-finding verification

| Finding | Original repro result after fix | Additional true/negative control |
| --- | --- | --- |
| F1 | Missing and commented serialized propagation both reject: `missing/repeated serialized propagated primary clk`. False native clock observation also rejects. | Exactly one real `clk` statement passes, including equivalent explicit literal-list wrapping. A second real statement rejects. Comments cannot stand in for actual stored state. |
| F2 | Executed filter script substitution rejects: `annotation filter executed script authority mismatch`. Actual `STA_EXTRA_CORNER_TCL_FILE` substitution rejects. | Substitution of actual `_EXTRA_CORNER_TCL_FILE` also rejects. Unmodified retained bootstrap/dependency layout passes. |
| F3 | Removing actual `checks.rpt` and its optional outer inventory entry now rejects because the required filter reference cannot resolve. | Changing report bytes while rebinding only the outer inventory rejects the filter's recorded hash; coherently binding harmless report bytes at both levels passes. Identical bytes under a different report source reject. |
| F4 | Original dangling RCX ODB repro rejects via required view closure. | A different **existing, retained and rebound** RCX ODB rejects specifically with `RCX/STA extracted nl/SPEF/ODB input mismatch`. Coherently matching original/filter ODB bytes passes. |
| F5 | Dangling CTS views reject; original ordinal00 STA repro rejects. | A legal positive STA ordinal04 before RCX05 rejects specifically as noncausal. Distinct but existing/retained CTS nl/ODB views pass, confirming the fix does not demand unchanged netlists across legitimate repair. |
| F6 | Malformed second setup metric remains valid completed evidence with all-corner timing **unknown**, not pass. | Exact duplicate, missing setup record and hold log/State conflict remain unknown; coherent negative hold remains fail; clean baseline remains pass. |

### Source-level confirmation of causal bindings

* `timing_native_coverage.ml:211–233` now counts exactly one qualified serialized
  propagated primary `clk` when physical clock policy is enabled.
  `timing_intent_evidence.ml:487–497` compares schema3 native clock observation
  with `stored_clock_propagation.clocks`. Historical strict inspection does not
  gain physical propagation permission.
* `timing_physical_runtime.py:313–338` checks the image filter source, executes
  the retained `filter-driver.py` bootstrap, snapshots the actual checks-report
  hash before invocation, and records the retained odbpy dependency layout.
  The bootstrap's source path is relative to its retained execution directory;
  it selects retained odbpy ahead of other imports.
* `timing_physical_flow.ml:364–397` checks exact bootstrap bytes/profile/path,
  actual invocation path, retained filter source/dependency closure, required
  checks-report path/hash, ODB bytes and argv. The public annotation source now
  identifies actual `checks.rpt`; the hook report is separately identified.
* `timing_physical_flow.ml:230–293` requires retained State view closure, orders
  originating synthesis through physical stages to original STA, and binds RCX
  output nl/SPEF/**ODB** to original STA input. Original and linked STA outputs
  must preserve those implementation views. The filter's consumed ODB bytes are
  then separately checked against that exact input ODB.
* `timing_physical_metrics.ml:18–30` includes malformed records with recognized
  required metric keys in the observation count; they can no longer silently
  disappear beside a valid record and earn pass.

### Corrected snapshot

Hashes recorded by the original replay at verification:

| Source | SHA256 |
| --- | --- |
| `flow/hardcaml_asic_flow/timing_physical_runtime.py` | 4df32ca20f61f94672d63c293f2a605cdbb68f8b130e0e9f014d1e68cdc679e2 |
| `execution/results/timing_physical_flow.ml` | 8b11e769fe939e8da26e8cc1592fe26258c72d733b2d1bdc14759d67df6dc14d |
| `execution/results/timing_physical_metrics.ml` | 1c6286251ccb1815b9386934df737fb37270b71df245f45d0ef5a4bb257476b4 |
| `execution/results/timing_native_coverage.ml` | 1789b4cbb9f03f9c68407ac04b9fd92741b3d56c099c5c571ce4adba3067b47d |
| B fixture `test/timing_physical_flow/check.py` | 511be6c0864b7a525545330537850b4fa746027c2fcc2ab067969afd5245d9a4 |

Final outcome: **all six original findings closed within their reviewed scope**.
SPEF/corner/input-State substitutions, missing corners, downgrade, failed terminal
and resource-ceiling controls continue to behave conservatively in the original
replay. Actual physical timing, extraction/annotation behavior and ordinary final
acceptance remain C's evidence and the subsequent independent physical-result
review, not claims inferred from these no-EDA controls.
