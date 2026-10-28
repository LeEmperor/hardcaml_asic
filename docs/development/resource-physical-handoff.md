# PT.5b A — physical/common integration handoff

Implementation complete and integrated with B, 2026-10-27. Shared contract:
`resource-measurements-plan.md`. This early handoff freezes the integration seam.

## Common reader / B seam

The existing engine owns contained bounded reads and the single source inventory.
Callbacks supplied to feature collectors:

```ocaml
read : string -> string -> string * Evidence_json.t
exists : string -> bool
```

`read path format` takes a selected-run-relative path and returns actual bytes and
the engine-created `{path; sha256; format; scope}` reference. `exists path` is
selected-run-relative. No external absolute producer/PDK paths may be read.
All successful reads automatically join top-level refs and replay/archive closure.

B should publish its exact signature in `resource-timing-handoff.md`. Available
inputs are `context` (selected run record), `manifest`, `flow` (selected flow-relative
root; `flow` for a retained physical-p4 snapshot), `resources` (reconciled final
resource rows), and the final-netlist `(raw, ref)` or ref/identity. B returns
resource-keyed timing/electrical objects and diagnostics; A wires this exact API.

## Schema 2

New inspection/collection emits schema 2. Existing schema-1 validation remains
strict; source replay explicitly invokes schema-1 collection semantics, never
compares old unavailable assertions to enriched schema-2 output.

Final observation gains `physical` (structured aggregate/denominator evidence),
and each final resource row gains `geometry` (exact observed footprint or explicit
unavailable). Existing `area` becomes physical footprint when geometry is available.
Synthesis rows have unavailable geometry in schema 2. Timing/electrical fields keep
their existing names and are replaced with B's structured objects when available.
Geometry/sums are not architectural flop ownership or integration area envelopes.

## Physical sources / layout

Use physical-checks artifact keys to select unique executed geometry and routed
DEF, then read through the common callback. Require checker pass/profile/hash
validation and exact final resource instance/master plus DEF placement/units.
The live final DEF equals the checker-bound stage-54 DEF; snapshot retains stage-54.
Metrics are `flow/final/metrics.json`, or root `metrics.json` only in snapshot layout.
Optional exact sums use retained `baseline-inputs/*.lef` whose bytes match retained
preflight/checker input bindings. Never borrow live PDK bytes. Missing LEFs leave
exact sums unavailable, while native rounded metrics remain separately labeled.

New augmented C capture may keep physical-p4 layout and add `flow/56-openroad-stapostpnr`
plus unchanged timing inputs. These sources join the same reader/ref inventory.

## Ownership

A owns `resource_physical_evidence.*`, `resource_evidence.*`, physical tests,
root `test/dune`, common integration. B owns new timing modules/parser and isolated
timing tests. C owns example capture/acceptance. Coordinator owns plan/public guide.
No agent needs to edit another agent's files to deliver its collector.

## Integrated wire shape (ready for C)

The exact physical collector signature is now in `resource_physical_evidence.mli`.
It additionally takes already-verified checker and final-netlist refs so footprint
claims directly close over both identities. B's frozen `Resource_timing_evidence`
API is wired into schema-2 collection and strict validation; its read sources use
the common registry. Final observations also contain `timing_diagnostics`.

Available resource `geometry`:

```text
status: available
instances: [{instance, module, orientation:R0, dbu_per_um, origin_dbu,
             bounds_dbu, width_um, height_um, area_um2, halo_dbu}]
area_um2: sum of owned instance footprints
scope, evidence_refs
```

Final observation `physical` has `status`, nullable `reason`, `floorplan`,
`measurements`, `ratios`, `evidence_refs`. Each floorplan `core` / `die` is either
unavailable or `{bounds_um, area:<normal measurement>}`. Measurements retain the
existing `value/unit/definition/stage/scope/evidence_refs/unavailable_reason` shape.

Measurement keys:

- `macro_footprint_area` (geometry/DEF/checker/netlist proof).
- `native_all_component_area`, `native_nonspacer_area`, `native_spacer_area`,
  `native_macro_area` (separately labeled rounded producer values, when metrics exist).
- `macro_component_area/count`, `nonspacer_component_area/count`,
  `spacer_component_area/count` (exact bound LEF/complete DEF coverage, otherwise null).
- `nonspacer_plus_macro_area`, `all_component_area` (only with complete exact coverage).

Ratios: `macro_over_core`, `macro_over_die`, plus with exact sums
`nonspacer_plus_macro_area_over_core/die` and `all_component_area_over_core/die`.
Each is `{name,numerator:<measurement>,denominator:<measurement>,value,unit:ratio,scope}`.
The denominator contains the bbox-derived gross rectangle area and source refs.
No native utilization formula is asserted. JSON floating values are nearest binary
representations of DBU-area/decimal results; consumers need precision-aware checks.

Missing sources produce explicit unavailable data. Contradictory supplied data
produces `physical:{status:invalid,reason}` and a failed final observation with
`measurement_error`. This remains valid, archivable failure evidence, not a pass.
Current retained checker support is deliberately `cmos5l_real_gds_v1` and its stock
`RM_IHPSG13_1P_256x16_c2_bm_bist` dimensions/R0 placement, matching executed checker
semantics. The DEF component parser rejects unsupported clauses rather than
silently claiming complete coverage. No external LEF/PDK source is followed.

Schema 1 is accepted strictly and source-replayed using the original schema-1
collector semantics. Schema-2 synthesis rows add unavailable geometry. Existing
schema-1 geometry/timing-unavailable assertions do not gain assertions or sources
during replay. JSON object order is semantically irrelevant; arrays remain ordered.
CLI capabilities now advertise `resource_evidence2` and write/read schema versions.

Focused old PT.5 regressions and new physical rebound/schema/replay cases pass.
Original physical-p4 read-only CLI inspection returns exact 28127.104 footprint,
4793.6448 nonspacer, 866655.4176 spacer and the expected ratios. Final broader and
live/augmented-capture verification receipts will follow below.

## Final A receipt — ready for C provider capture / coordinator review

Broader integrated source verification passed:

```sh
flock /tmp/opencode/asic-pt5b-build.lock opam exec --switch=5.2.0+ox -- \
  dune build @test/resource-physical-evidence @test/resource-evidence \
  @test/resource_timing/runtest @test/inspection @test/ocaml-collect \
  @test/ocaml-report @test/ocaml-archive @test/ocaml-finalization \
  @test/ocaml-stage-report @test/flow-cli @install \
  test/resource_evidence_consumer.exe -j6
```

Exit 0. New A suite: **32 public CLI observations** plus strict validation,
schema-1 synthesis/physical replay, coherent physical/timing forgery rejection,
stale-source checks and archive-reference closure. B isolated suite: **44 tests,
0 failures**. Existing PT.5 suites: **27 + 19** CLI observations; collection **131**,
report **585**, archive **16**, finalization **26** differential cases; **43** CLI
presentation tests, stage-report contract, inspection and install passed. The
historical optional retained-finalization fixture was unavailable, as before.
`finalize: missing native helper` is deliberate passing negative-fixture output.
An earlier 120-second invocation timed out on the long finalization test; no
process remained, and the complete command above passed with a 300-second bound.

Read-only public library inspection **and full source replay** (`inspect-verify`
in the test consumer) on final source state:

| Selected evidence | Status / refs | Physical exact sums µm² | Timing |
| --- | --- | --- | --- |
| Original `acceptance/sram/physical-p4` | pass / 59 | macro 28127.104; nonspacer 4793.6448; spacer 866655.4176; all 899576.1664 | unavailable, as historical sources lack raw STA |
| Original live `20261025T034710180883Z_be961b2c` | pass / 75 | exact macro 28127.104; complete exact LEF sums unavailable | 186 paths / 372 electrical points, zero diagnostics |
| C raw `acceptance/resource-measurements/accepted-live-01/run` | pass / 76 | all four exact sums above | 186 paths / 372 electrical points, zero diagnostics |

Also source-replayed the legitimate historical schema-1 assertion at
`acceptance/resource-realization/installed-final/037.stdout` against the unchanged
original physical-p4 root: **valid**. The older top-level `physical.json` predates
the strict resource-inventory anchor and still correctly fails strict validation;
it is not used as the schema-1 compatibility oracle.

The portable A suite now wraps B's unchanged actual slow-path excerpt in diagnostic
producer metadata, observes it through the public schema-2 API, verifies it,
checks all timing metadata/report/unit-library/input-netlist refs enter archive
selection, then changes slack and required coherently over unchanged hashes.
Structural validation remains valid, while full source replay rejects the forged
assertion. Neither original source evidence nor B's fixture files are edited.

### Final provenance/precision details

- Exact decimal LEF dimensions are converted with integer arithmetic to DEF DBU;
  sub-DBU decimals are rejected, not rounded into exact claims. Component areas
  accumulate in arbitrary-precision integer DBU² before JSON numeric conversion.
- LEF/DEF comments and quoted strings cannot supply declarations; unsupported
  multiline strings, clauses, nonzero/missing origins, duplicate attributes and
  incomplete inventories reject/diagnose rather than yielding partial exact sums.
- Optional LEF admission uses the retained preflight **role**: standard-cell
  technology LEF, or macro physical abstract matching the manifest's exact configured
  `MACROS[master].lef` reference. Byte digests must match. Unrelated collateral
  cannot establish class/area coverage. Technology-only LEFs are unnecessary and
  are not advertised as measurement sources.
- Native areas retain their producer values, with separate six-significant-digit
  rounding consistency checks against derived areas. Native area/count conflicts,
  die mismatch, core escape and macro/core mismatch are diagnosed even after
  fixture hashes are rebound. Exact coverage is all-or-unavailable; contradictory
  retained partial LEF coverage is still rejected.
- Common schema-2 validation cross-checks geometry against reconciled resource
  instances, area/count aggregates and completed stage. B validates nested links;
  A additionally binds timing run/build provenance to its enclosing observation.
- Source replay dispatches by the **normalized recorded schema version**. It does
  not add new physical/timing sources while verifying schema 1. All schema-2 feature
  reads use the shared bounded registry and join final post-read hash verification.

No common integration remains pending on B. C still owns installed provider capture,
independent public acceptance/negative receipts and original-history preservation;
the read-only raw-capture smoke above is not that installed acceptance receipt.
No EDA, Workbench/Protemu operations or Git mutation was used.

After the final two offline consistency guards (gross-area unit must be `um^2`;
available resource geometry requires an available physical observation), repeated
the same command **without** `@test/ocaml-finalization` and `@test/ocaml-stage-report`:
exit 0, including the two new forged-assertion negatives. The earlier broader
finalization/stage-report receipt above remains the receipt for those aliases.
`git diff --check` also passed. No source changes remain pending from A.

## Independent-review corrections — prior capture superseded

2026-10-27: the previous freeze/capture receipt above predates four confirmed
independent-review corrections. C must capture the final corrected provider again
after A/B correction verification; earlier installed captures are historical.

Implemented in A-owned files only:

1. Native category and total consistency no longer depends on complete LEF
   coverage. Known class areas/counts and independently known macro geometry form
   lower bounds; complete standard-cell classes are checked even with no macro
   LEF. A native category count equal to the known classified count establishes
   category completion for consistency checks. Combined native/known category
   lower bounds and rounded native category/total sums are checked independently.
   Complete exact aggregate output remains unavailable when LEF coverage is missing.
2. LEF parsing now tracks named PIN and unnamed PORT/OBS/DENSITY scopes. Matching
   END terminators restore macro scope, so duplicate direct SIZE/CLASS/ORIGIN after
   a nested group cannot hide. Mismatched or unclosed scopes reject; unsupported
   nested forms fail closed.
3. DEF `END COMPONENTS` requires an exact token boundary. Prefixes such as
   `END COMPONENTS_WRONG` do not terminate the section.
4. Schema-2 resource footprint `area` must use `um^2`, and its nonempty, closed
   source refs must include the resource geometry's complete proof-reference set.
   Wrong units, empty refs and incomplete proof refs fail offline validation.

The supplied original disposable review roots were rechecked **without rewriting
them**, using `/tmp/opencode/pt5b-a-corrections-review-20261027.py`.
Receipt: `/tmp/opencode/pt5b-a-corrections-kcffrxlq/receipt.json`.
Both partial-coverage contradictions, post-PIN duplicate attributes, unclosed PIN
and malformed DEF termination now yield exit 1 / invalid physical evidence.
Genuine failure evidence still source-replays as valid evidence. Both supplied
geometry-area unit/reference forgeries now fail offline validation.

New regressions additionally cover valid nested groups, post-OBS/DENSITY duplicate
attributes, nested PORT mismatches, partial-class/count/native-total combinations,
and failed-evidence archive closure. Final integrated verification receipt follows.

### Corrected A/B freeze receipt — ready for final C recapture

All A corrections are frozen. B's corrected timing modules are integrated without
API/schema changes. No B-owned file was edited by A.

Final broader command passed, exit 0:

```sh
flock /tmp/opencode/asic-pt5b-build.lock opam exec --switch=5.2.0+ox -- \
  dune build @test/resource-physical-evidence @test/resource-evidence \
  @test/resource_timing/runtest @test/inspection @test/ocaml-collect \
  @test/ocaml-report @test/ocaml-archive @test/ocaml-finalization \
  @test/ocaml-stage-report @test/flow-cli @install \
  test/resource_evidence_consumer.exe -j6
```

Then forced both corrected feature suites after B's ready/frozen handoff:

```sh
flock /tmp/opencode/asic-pt5b-build.lock opam exec --switch=5.2.0+ox -- \
  dune build --force @test/resource-physical-evidence \
  @test/resource_timing/runtest -j6
```

Passed: **56 A public CLI observations**, strict/schema/replay/archive assertions,
and **73 B tests, 0 failures**. The broader run also passed existing **27 + 19**
PT.5 CLI observations, **131** collector, **585** report, **16** archive and **26**
finalization differential cases, **43** CLI presentation tests, inspection,
stage-report and install. The optional older retained-finalization tree remained
absent. Deliberate `finalize: missing native helper` negative-fixture output is
not a test failure.

Latest independent supplied-fixture receipt:
`/tmp/opencode/pt5b-a-corrections-xnjzuuri/receipt.json`.
Independently reran the A review of corrected B through public inspection/replay:
`/tmp/opencode/pt5b-timing-review-a-bzxc5mex/report.json`. The arrival-marker and
clock-only attacks now quarantine the malformed min path with diagnostics and
zero data-role clock points. Empty/garbage/gzip reports diagnose; nested-only
units produce no observations; exhausted attempted-point budget prevents the
later min report from being read. All original **372** electrical observations
still independently match their fixed-column source bytes.

Final corrected-source read-only inspection **and full source replay** passed:

| Root | Status / refs | Exact macro / nonspacer / spacer / all µm² | Timing |
| --- | --- | --- | --- |
| Original physical-p4 | pass / 59 | 28127.104 / 4793.6448 / 866655.4176 / 899576.1664 | unavailable |
| Original accepted live run | pass / 75 | 28127.104 / unavailable / unavailable / unavailable | 186 paths / 372 points, zero diagnostics |
| C augmented raw `accepted-live-01/run` | pass / 76 | all four exact sums above | 186 paths / 372 points, zero diagnostics |

Historical strict schema-1 physical assertion `installed-final/037.stdout` also
source-replayed successfully against unchanged physical-p4. Original histories
were never rewritten. C's earlier **installed provider** capture is superseded;
the augmented raw bytes remain usable as inputs to final recapture/acceptance.

A source freeze SHA-256s:

```text
execution/results/resource_physical_evidence.ml
4f8360e32f25d0748cd6e7b66e2f16749deef74c312b5b1da6b80482b39fce05
execution/results/resource_physical_evidence.mli
2737f99f2f97740ff7e922fd5759813ba88084c1732cdec4092f4837a30da0b8
execution/results/resource_evidence.ml
ffdfa1f6fa5399822f2f4f911c7d60fecd0a3f6497fde341916b50cc0fb61e5c
test/check_resource_physical_evidence.py
dc6b9282c9944ea5b1e977b571ba0d191582f1b7a37791c4d5c0d5d70f97c738
```

No further A implementation edits are pending. C can perform final provider
recapture and installed acceptance now. No EDA, Workbench or Git operations were
used during these corrections.
