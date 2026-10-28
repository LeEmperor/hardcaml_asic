# PT.5b — physical measurements and sampled resource timing

Implementation authorized 2026-10-27. `docs/phase_plan.md` is the only active queue.
This document freezes bounded scope, ownership and acceptance before source edits.

**Final status:** implemented and independently accepted in the supported retained-
evidence scope. See [closeout](#implementation-and-acceptance-closeout); original
plan sections below describe the agreed boundary, not unfinished assignments.

## Scope and evidence boundary

Continue the existing ASIC-owned resource-evidence API/CLI. No second selector,
consumer parser/framework, Workbench schema/UI, or physical-stage enum is introduced.
Use retained SRAM evidence; physical EDA allocation is zero. No P&R rerun is planned.

Read-only investigation found sufficient evidence:

- The accepted run `be961b2c95f74c81ad6af81ca4d2b269`, bundle
  `fa38d9064dffdf2ec1578c79c2e8890eba81bf704af460e85fcc6031b707d53c`, retains
  checker-bound macro geometry and routed DEF. The curated `physical-p4` snapshot
  includes matching standard/macro LEFs and core/die metrics.
- Geometry identifies `program` / `hc_resource_7_program`, stock master, 1000 DBU/µm,
  rectangle `[40000,81000,276800,199780]`, R0/DEF N. Physical footprint is
  **28127.104 µm²**, excluding halo, bridges, routing and repair cells.
- Complete DEF + bound LEF classes reconstruct **389 nonspacer cells / 4793.6448 µm²**,
  **68539 spacer/fill/decap cells / 866655.4176 µm²**, one macro / 28127.104 µm².
  All-component area sum is 899576.1664 µm²; nonspacer-plus-macro is 32920.7488 µm².
- Native core bbox `[2.88,3.78,1286.4,706.86]` gives a **gross rectangle** area
  902417.2416 µm². DEF/native die bbox gives 916213.9392 µm². Native area metrics
  are rounded; arithmetic cannot invent extra precision in the absence of LEFs.
- The original accepted run additionally retains `56-openroad-stapostpnr` with
  three corners' max/min path reports, config/state, logs and generated unit libraries.
  These raw reports are absent from the historical curated physical snapshot.
  New capture may copy them unchanged into a new evidence directory with source hashes.

No original run/snapshot is rewritten. A later failed run sharing a build/netlist
is not interchangeable with the accepted run. Integrity is not producer authentication.

## Shared API/schema contract

Public entry remains `Resource_evidence.inspect`, `collect`, `validate`,
`verify_sources` and `resources-inspect`. New structured measurement/link evidence
requires **resource-evidence schema 2**; readers retain exact schema-1 compatibility.
Source replay must compare using the recorded schema's semantics, so legitimate
old reports do not fail merely because newer inspection produces more evidence.
Historical schema-1 physical/timing-unavailable claims remain history.

One shared contained/bounded reader owns evidence references and digest closure.
Feature modules consume reader callbacks or already-read `(raw, evidence_ref)`
sources. They never discover current PDKs or dereference historical absolute paths
outside the selected run. All sources used for advertised claims join archive closure.

### Physical output

- Resource geometry identifies exact observed instance/master, DBU scale, orientation,
  placement, bounds, area and evidence sources. Match reconciled final instances,
  checker-recorded geometry and actual DEF; declared plan placement alone is insufficient.
- Optional exact component sums use complete DEF counts and hash-bound LEF `CLASS`,
  `ORIGIN`, `SIZE`; no filename-prefix filler classification. Missing or unsupported
  source remains unavailable. Present contradictory data must not appear valid.
- Report macro/nonspacer/spacer/all-component scopes separately. Keep original
  native rounded metrics separate from derived exact footprint sums.
- Derived occupancy uses explicitly named numerator/denominator and source refs:
  macro/core, nonspacer+macro/core, all-components/core, optionally nonspacer/(core−macro).
  These are sums of component rectangles over gross core/die rectangles, not geometric
  unions, routed coverage, usable placement sites, or proof of native utilization formulas.
  State filler/decap inclusion and halo/blockage exclusion rules. No nearby cell ownership
  or architectural flop attribution is inferred.

### Timing/electrical output

- Reuse or extend the ASIC timing-report parser, preserving its existing public
  `timing_records` compatibility API. New structured path/point model retains header
  endpoints, exact pin/master, data/launch-clock/capture-clock role, corner, min/max,
  group, signed slack, arrival/required and one-based source line spans.
- Link only exact reconciled resource instance/master data endpoints. A matching
  clock point or prefix-near-match must not fabricate a data path association.
- Parse observed slew, output load, delay, edge and fanout only with explicit units
  and supported columns. Blank fields remain absent. Output Cap is reported load,
  not intrinsic pin capacitance. Negative slack is valid failing measurement evidence.
- Retain producer/config/state/log/netlist and report/unit-library hashes. A historical
  coarse producer is labeled as such, not fabricated as a modern checkpoint.
  Recorded external model refs/hashes remain distinct from retained verified bytes.
- Preserve analysis corner `nom_fast_1p32V_m40C` separately from its bound SRAM
  model `fast_1p32V_m55C`; never relabel temperature to conceal the difference.
- Coverage is sampled reported paths/points, not exhaustive resource timing or pin
  compliance. Global zero slew/cap counts do not become resource electrical passes.
  Per-pin limits/margins, timed-model conformance, IR/EM qualification, per-resource
  power and optimized-flop ownership are outside this slice. IR voltage CSVs are
  deferred: they are unnecessary to establish the requested path/electrical links.

### Agent seam

A owns the common integration and physical module. B owns timing parser/collector
modules. B publishes concrete signatures early in `resource-timing-handoff.md`;
A wires them after handoff. Expected timing seam takes contained `read`/`exists`
callbacks, manifest/run context, flow-relative producer root, reconciled resources
and final input-netlist identity; returns per-resource timing/electrical link objects
and diagnostics. A registers all actually read sources in the shared reader.
No module independently constructs alternative source identities.

## Exclusive bounded assignments

| Owner | Ownership | Dependencies / acceptance |
| --- | --- | --- |
| A — physical + common integration (6 jobs) | New `execution/results/resource_physical_evidence.*`, `resource_evidence.*`, common CLI/schema/capability/collection/archive edits if needed, shared test/dune, physical tests | Freeze schema2 and handoff; exact bound footprint/class sums/ratios; schema1 read/replay; integrate B links; contradictory/missing sources explicit; archive closure |
| B — timing/electrical (6 jobs) | New timing report/resource timing modules, shared `inspection_service.*` parser extension only if needed, new isolated timing test directory | Publish API for A; exact data-endpoint linking, signed slack, ns/pF provenance, corner/model distinction and sampled coverage; preserve existing parser semantics and no implicit external reads |
| C — independent example (6 jobs) | New `scripts/check_resource_measurements.py`, `acceptance/resource-measurements/`, example guide; isolated provider capture | Bind fresh compact raw capture to original accepted run; public API/CLI measurements and negatives, original histories unchanged, replay/archive source closure, no consumer-local implementation |
| Coordinator | This plan, phase queue and public guide, interface arbitration, independent review and integration | No overlapping edits; review guards and retained actual evidence before completion claims |

A/B may use new test subdirectories to avoid root test/dune conflicts; root declarations
belong to A. C begins evidence capture while A/B implement, but waits for final public
handoffs before installed acceptance. Completed agents review each other's slice.

## Acceptance oracles and negatives

Physical positives: exact stock macro rectangle/area, nonspacer/spacer counts and
sums above; gross core/die source provenance; macro/core **0.03116862434** and
nonspacer+macro/core **0.03648062923**, distinct from all-components/core
**0.99685170554**. Values need precision-aware comparisons, not copied constants.

Timing positives (report-rounded):

- Slow max path `program/A_DOUT[11] → uo_out[3]`: slack **11.246561 ns**,
  arrival **7.336773**, required **18.583334**; output slew **0.067838 ns**,
  reported load **0.004815 pF**.
- Fast min path `_203_/Q → program/A_ADDR[6]`: slack **0.223533 ns**,
  arrival **0.949038**, required **0.725504**; input slew **0.167545 ns**,
  blank Cap remains absent. Clock-pin observations retain clock role.

Negatives must reach semantics as well as hash rejection: wrong/duplicate/missing
instance, moved/rotated/wrong-unit geometry, malformed DEF/LEF or class conflicts,
invalid/zero denominator, stale sources, unrelated clock-only timing, wrong pin/master,
near-prefix instance, wrong run/stage/corner, ambiguous/missing units, truncated path,
nonfinite values, valid negative slack, blank column, bounded parsing and coherent
forged structured links over unchanged hashes. Rebound fixtures are diagnostic
mutations, not new geometry/STA qualification.

Both schema-1 stored reports and historical snapshots must remain read-only and
inspectable; original physical-p4 timing remains unavailable while the new augmented
capture supplies real sampled links. Full source replay and archived bytes must cover
all new sources. Focused tests precede independent installed example acceptance,
then appropriate broader ASIC/example suites.

## Execution constraints

- No Git staging/commit/push/amend/config or authorship changes.
- Three agents maximum, six jobs each, two reserved. Every Dune invocation explicit
  `-j6`; all ASIC checkout operations share `/tmp/opencode/asic-pt5b-build.lock`.
  Serialize example Dune separately; captured private provider builds count within C's six.
- Isolated provider `.dev/asic-pt5b`, example build `_build_pt5b`. Preserve all current
  provider pointers including the approved Workbench PT.5 configuration.
- No Workbench/Protemu code, tests, UI integration or live daemon actions.
- No EDA allocated. New report parsing/capture is not new synthesis/physical execution.

## Implementation and acceptance closeout

Completed 2026-10-27. Public entry points remain `resources-inspect`,
`Resource_evidence.inspect/collect/validate/verify_sources`. Collection now emits
schema 2; historical schema 1 remains strictly readable and source-replays with
its recorded semantics. No old report is silently enriched or rewritten during replay.

Implementation details: [physical/common handoff](resource-physical-handoff.md),
[timing handoff](resource-timing-handoff.md), [operating guide](../guides/resource-realization.md).

### Delivered measurements

The original curated `physical-p4` now supports exact stock resource footprint,
bound LEF-class component sums and explicit gross core/die ratios. Its absent STA
sources still yield unavailable links. The accepted live run supports macro geometry
and sampled timing; missing run-contained LEFs leave exact aggregate sums unavailable.
Neither reader borrows missing inputs from the other root or a current PDK.

The example's new `acceptance/resource-measurements/accepted-live-01/` capture
retains **333 unchanged files / 111,847,065 bytes**, combining the old physical
snapshot with raw STA/producer inputs from the exact accepted run, with explicit
source/destination hashes. The common reader advertises **76** source references
for its complete schema-2 claims. Extra captured inputs are not silently elevated
to validated claims.

Verified values:

| Measurement | Result |
| --- | ---: |
| Macro footprint, no halo/bridge/route/repair envelope | 28,127.104 µm² |
| Nonspacer standard-cell footprints | 4,793.6448 µm² / 389 |
| Spacer/fill/decap footprints | 866,655.4176 µm² / 68,539 |
| All component footprint sum | 899,576.1664 µm² / 68,929 |
| Nonspacer + macro footprint sum | 32,920.7488 µm² |
| Gross core / die rectangle | 902,417.2416 / 916,213.9392 µm² |
| Macro / gross core | 0.03116862434 |
| Nonspacer + macro / gross core | 0.03648062923 |
| All components / gross core | 0.99685170554 |

Ratios use sums, not unions, over gross rectangles. Six explicit ratios include
both core and die denominators. No native utilization formula or usable-site
capacity is claimed. Native rounded metrics remain separate.

All six raw STA reports contain **306 parsed paths**; exact macro data-endpoint
ownership selects **186 sampled paths / 372 electrical point observations**, with
zero original-report diagnostics. The slow setup and fast hold cases retain the
plan's numeric oracles, actual data/clock roles, report spans, ns/pF declarations,
and separate −40°C analysis/−55°C SRAM model binding. The unit-library and SDF files
are unchanged ASCII text; an early research documentation claim of gzip encoding
was corrected after direct magic-byte verification. No decompression claim is needed.

### Independent review and correction

Initial installed acceptance preceded independent reviews. Review found and corrected:

- Missing primary arrival markers could let subtraction-summary arithmetic assign
  a capture-clock pin as a data endpoint. Ordered sections and actual endpoint
  agreement now reject/quarantine those malformed paths.
- Empty/unrecognized/compressed report content lacked partial diagnostics. It is
  now diagnosed; only exact native no-path envelopes qualify as understood reports.
- Nested Liberty attributes could supply false unit declarations. Units now require
  direct, balanced library scope with bounded lexical handling.
- Rejected-path points did not consume the query-wide work budget. Attempted points
  now count and exhaustion prevents later report reads.
- Partial LEF coverage suppressed independently provable area/count contradictions.
  Known lower bounds and category-complete comparisons now remain active.
- LEF nesting ignored later direct attributes and malformed terminators. Supported
  nested scopes now balance and restore macro scope; unsupported structures reject.
- DEF component termination accepted a token prefix. Exact section tokens are required.
- Geometry-backed area validation now enforces `um^2` and complete proof references.

Independent correction follow-up passed **24 physical/schema checks** and **21
additional public timing cases**, each source-replayed. It independently audited
all **372 electrical observations** against actual source columns. No blocker
remains in these reviewed scopes. Durable regressions live in the physical and
timing suites; diagnostic receipts remain under `/tmp/opencode`:

- `pt5b-independent-A-968fmmkx/independent-review.json`
- `pt5b-corrected-B-independent-A-c3r90qzi/receipt.json`
- `pt5b-timing-review-a-t7a8y3xr/report.json`

### Final installed example acceptance

Authoritative retained receipts under the example's `acceptance/resource-measurements/`:
`installed-final/receipt.json`, `closeout-final.json`, `provider-final-binaries.json`.
Earlier `installed-02` / `closeout-01` remain unchanged and are explicitly superseded.

| Identity | Final corrected capture |
| --- | --- |
| Provider generation | `4848a66eeda54751b12d645ee9bcd5c4` |
| Captured source SHA-256 | `03b13eb7dd2b2918594754c19b41cbc5fe5042f309a9f2f91eae221b6aed4f4f` |
| Native resource-inspection executable SHA-256 | `84e2c061cf9aa45ee1fc2c232481ab0268a6555d8196f4340cbb13a8ee167ac9` |
| Installed API consumer SHA-256 | `edb23745eb57f295a9c7c05b9b87ad3f8e44a14ef7e25968359b6795a305219f` |

The dispatcher hash is unchanged across captures; the native companion identities
are recorded separately. This is development-capture provenance, not a clean-source
or compiled-source stamp. Coordinator-only documentation closeout follows the capture.

- **15 installed public acceptance tests**, zero failures/errors/skips.
- Public CLI/library agreement, exact physical/sampled timing observations, changed
  raw values including valid negative slack, semantic negatives after hash rebinding,
  and coherent structured forgery rejection by full source replay.
- All **76 schema-2** and **56 genuine schema-1** advertised archive references
  verified against exact tar bytes. Historical stored results remain unchanged while
  current read-only reporting produces schema 2.
- Full example suite and **five** standalone FIFO flow-emission tests passed on the
  final provider. All **276 original historical files**, augmented raw capture,
  earlier acceptance receipts, pre-existing provider pointers and app configuration
  remained unchanged. The app remains explicitly pinned to the approved PT.5 provider.

### ASIC regression and limits

Final focused suites passed: **56** physical public CLI observations, **73** timing
tests, existing **27 + 19** resource cases, collection/report/archive/finalization/
inspection/stage-report/CLI/install checks. Optional original timing checks passed
75 including live parsing; these are not an additional independent test total.

Full ASIC testing used the shared lock and explicit `-j6`:

```sh
flock /tmp/opencode/asic-pt5b-build.lock \
  opam exec --switch=5.2.0+ox -- dune runtest --force -j6
flock /tmp/opencode/asic-pt5b-build.lock \
  opam exec --switch=5.2.0+ox -- dune runtest -j6
```

The forced run hit its 1,800-second tool deadline with only `ocaml-preflight`
unfinished and no reported assertion failure. The resume completed with exit 0,
rerunning that unfinished action (24 exact report differentials plus 72 cancellation/
publication cases). Do not claim the timed-out forced command passed. Combined
receipt: `/tmp/opencode/pt5b-full-runtest-B-receipt-20261027.json`. Output includes
25 unittest suites / 521 tests, 131 collection / 585 report / 16 archive differentials,
26 finalization / 15 postcheck / 15 coarse-run differentials and 691 runner cases.
These are heterogeneous checks, not one additive total. The optional older retained
accepted-finalization fixture remains unavailable; the actual example supplies
separate retained acceptance above.

No EDA, Workbench/Protemu code/tests, user-daemon action, Git staging/commit/push or
provider-selection changes were performed. Maximum agent allocation was 18 jobs,
ASIC checkout Dune serialized; example and captured private builds each stayed within
their six-job allocation. All source changes were frozen before final acceptance.

Supported scope remains deliberately bounded: stock/R0 checker geometry, retained
native post-PNR format, exact macro ownership and sampled electrical observations.
No exhaustive path/pin coverage, electrical limits/margins, timed SRAM conformance,
IR/EM adequacy, per-resource power or optimized-flop attribution is established.
