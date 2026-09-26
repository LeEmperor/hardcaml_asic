# SRAM S.3 findings disposition

Status: review complete, 2026-09-20. This is a findings-disposition review of the
ASIC S.3 qualified feasibility result recorded in
[`sram-flow-feasibility.md`](sram-flow-feasibility.md). No physical flow was rerun,
no EDA tool was invoked, and no configuration, lock, or consumer file was changed.

**Conclusion: qualified S.3 closure remains justified.** The evidence satisfies
S.3's own acceptance criterion. Three wording corrections and two previously
unrecorded defects are required, but none of them invalidates the feasibility
result. S.4 remains gated on S.2, unchanged.

## Evidence identity

| Item | Established value | How verified |
| --- | --- | --- |
| Final run | `attempt-005-full`, all 80 stages | `runs/attempt-005-full/flow.log` |
| Configuration | `experiments/sram_flow_feasibility/config.json`, SHA-256 `780273cc…` | `sha256sum`; matches the restoration hash in the evidence README |
| Macro instance | `memory.sram` = `RM_IHPSG13_1P_256x16_c2_bm_bist`, `FIXED ( 42000 81000 ) N` | `21-openroad-generatepdn/tt_um_sram_probe.def:316` |
| Macro extent | `SIZE 236.8 BY 118.78` → global x 42.0–278.8, y 81.0–199.78 | macro LEF; used to localize every marker below |
| Die area | `0 0 1289280 710640` (DEF units 1000/µm) | same DEF, lines 5–6 |
| LibreLane | `3.1.0.dev3`, container digest `sha256:d109140b…` | `sram-flow-feasibility.md`; `.toolchain/.venv` install |
| IHP PDK | `2bbec755dc67ca3db0261c3d6163e15735d66710`, clean | `git rev-parse HEAD` + `git status` in `.toolchain/pdk` |
| TT support tools **actually used** | `cfa06bae536d00282cb2fdb3d0bdeebc562c6365`, clean, in `.toolchain/tt-sram-s3-cfa06bae` | `git rev-parse HEAD` + `git status` in that checkout |
| TT support tools baseline | `.toolchain/tt` still at `da63c9927411e3aca350977d653d24bbf5bca972` | `git rev-parse HEAD` |
| Archive | `attempt-005-artifacts.tar.gz` SHA-256 `de16cf3d8a584e2bace6ec999651e4c73f2c2adfe28a0b042f531835e9843d43` | recomputed today; **matches** the recorded digest and the reported value |
| Precheck input artifact | `runs/attempt-005-full/final/gds/tt_um_sram_probe.gds`, SHA-256 `40c666cc…` | `sha256sum`; matches restoration hash; named throughout `precheck-nix.log` |
| Precheck result record | `tt-precheck-attempt-005/results.xml`, SHA-256 `cafaae86…` | `sha256sum`; matches restoration hash |

The experimental tooling revision is **not** the established baseline. The physical
probe's precheck ran at `cfa06bae…`, the immediate child of the locked `da63c992…`,
which adds `SRAM.drawing` and `DigiBnd.drawing` to the accepted layer list. The
baseline checkout was left untouched. This matches the existing record.

Archive extraction for this review used a fresh isolated directory and did not
touch the preserved evidence or the ignored run directory.

### Completeness gap

The archive is **not self-sufficient** for re-deriving the DRC, extraction, and LVS
conclusions. Three inputs required by this review are absent from it and exist only
in the gitignored 230 MB live run directory:

- `44-openroad-detailedrouting/tt_um_sram_probe.def` — the final routed DEF, needed
  to localize the Magic DRC markers to real routing tracks.
- `52-openroad-fillinsertion/tt_um_sram_probe.pnl.v` — LVS comparison input.
- `64-magic-spiceextraction/tt_um_sram_probe.spice` — LVS comparison input, and the
  only artifact that shows what the layout actually connected to the macro supplies.

This does not invalidate the archive, which deliberately omits rebuildable
intermediates. It does mean the archived set alone cannot reproduce this
disposition. Recorded, not corrected, since correcting it would mean rebuilding the
archive and invalidating the published digest.

## Finding-by-finding disposition

### F1 — Four Magic DRC markers: abstract-representation artifact

**Evidence.** `62-magic-drc/reports/drc.magic.rpt`: one `M2.f` at
`144.380 70.995 144.580 81.000`, three `M3.f` at y `80.540–80.740` spanning x
`42.000–97.580`, `155.300–165.700`, and `215.900–278.800`.

Every marker abuts the macro boundary: y 81.000 is the macro's bottom edge, x 42.000
its left edge, x 278.800 its right edge.

**Underlying geometry.** The M3 markers are real top-level routes. The final routed
DEF has Metal3 in the 2 µm halo band on tracks y = 79.380, 79.800, 80.220, 80.640
(0.42 µm pitch, 0.2 µm wide, so the y = 80.640 track occupies 80.540–80.740 — exactly
the marker box). Segments include `NEW Metal3 ( 216000 80640 ) ( 281760 * )` and
`NEW Metal3 ( 155200 80640 ) ( 165600 * )`.

**Rule source.** `.toolchain/pdk/ihp-sg13cmos5l/libs.tech/magic/ihp-sg13cmos5l-drc.tech`
lines 485–488 and 429:

```
widespacing *obsm3 10005 10005 allm3 600 touching_ok \
	"Metal3 > 10.0um with runlength > 10.0um spacing to unrelated m3 < %d (M3.f)"
widespacing *obsm2 10005 10005 allm2 600 touching_ok \
	"Metal2 > 10.0um ... (M2.f)"
```

The rule takes `*obsm3` / `*obsm2` — the LEF **obstruction** layers — as the
wide-metal trigger. The macro's LEF declares a single Metal3 obstruction spanning
`0 → 118.78` across the whole macro and 822 Metal2 obstruction rectangles. Under the
abstract view that blanket obstruction is "metal wider than 10 µm", and the routes
0.26 µm below the macro edge violate the 0.6 µm requirement. The report prints
`< 120` in Magic internal units (0.005 µm each) = 0.6 µm, consistent with the tech
file's `600`.

**Why the abstract view was used.** `config.json` sets `"MAGIC_DRC_USE_GDS": 0`, so
Magic DRC ran on DEF plus the macro's LEF abstract and never saw the macro's real
geometry.

**Cross-check against the authoritative deck.** The PDK KLayout deck implements the
same rules with the same value —
`rule_decks/beol/5_17_metaln.drc:68–77`, "Min. space of Metal(n) lines if at least
one line is wider than 5.0 µm and the parallel run is more than 10.0 µm is 0.6 µm" —
and reported **zero violations** on the real final GDS. `drc_sg13cmos5l.xml` contains
`M2.f` and `M3.f` as declared categories and **0** `<item>` elements. It also ran with
`PRECHECK_DRC = false`, which enables the *fuller* rule set, since the deck's
conditional blocks are written `unless PRECHECK_DRC` / `next if PRECHECK_DRC`.

**Coverage comparison — important.** TT precheck's own Magic DRC step is gated to
`"techs": ["sky130A", "gf180mcuD"]` (`precheck/precheck.py:387–390`), as are KLayout
FEOL, BEOL, and offgrid. For `ihp-sg13cmos5l` the precheck's only geometric DRC is
the PDK KLayout deck. So the design has exactly **one** GDS-based DRC opinion, and
Magic-on-GDS was never run at all.

**What this proves and does not prove.** It proves the four markers are produced by
the blanket-obstruction abstraction rather than by real adjacent metal, and that the
authoritative GDS-based deck is clean on the identical rules. It does not prove the
design is DRC clean: macro-internal and macro-boundary geometry has been checked by
one tool only.

**Classification: understood limitation, with a residual verification gap.** Not a
design defect. Not a waiver.

### F2 — Two extraction overlaps: concrete integration defect

**Evidence.** `64-magic-spiceextraction/feedback.txt` and `feedback.xml`, category
`obsm4-metal4.ILLEGAL_OVERLAP`, multiplicity 2, polygons
`(111.830,197.660)–(113.440,199.565)` and `(111.830,199.555)–(113.440,199.780)`.
`magic-spiceextraction.log` ends `tt_um_sram_probe: 2 errors`.

**Root cause, traced to source.** `experiments/sram_flow_feasibility/pdn_cfg.tcl`
hand-creates the macro supply bridges:

```tcl
odb::dbSBox_create $vpwr_swire $metal4 111830  79520 113930  81000 STRIPE
odb::dbSBox_create $vpwr_swire $metal4 111830 197660 113930 201310 STRIPE
odb::dbSBox_create $vgnd_swire $metal4  64400  79520  68030  81000 STRIPE
```

Against the macro LEF, in global coordinates:

| Object | Global x | Global y |
| --- | --- | --- |
| Macro `OBS Metal4` stripe | 111.15 – 113.44 | 81.0 – 199.78 |
| Macro `VDD!` pin | **113.70 – 116.51** | 81.0 – 119.825 |
| Macro `VDDARRAY!` pin | **113.70 – 116.51** | 126.465 – 199.78 |
| Macro `VSS!` pin | 63.12 – 65.93 | 81.0 – 199.78 |
| Upper VPWR bridge | 111.830 – 113.930 | 197.660 – 201.310 |
| Lower VPWR bridge | 111.830 – 113.930 | 79.520 – 81.000 |
| VGND bridge | 64.400 – 68.030 | 79.520 – 81.000 |

Both VPWR bridges are placed about 1.87 µm too far left. Each sits on the macro's
Metal4 **obstruction** for 1.61 µm and reaches its intended pin for only **0.23 µm**.
The upper bridge additionally overlaps the obstruction in y for 2.12 µm inside the
macro, which is precisely what Magic reports. The VGND bridge, by contrast, makes a
healthy **1.53 µm** contact to `VSS!`.

The tcl comment claims the bridges "abut the lower VDD/VSS pin edges and the upper
VDDARRAY pin edge". For VGND that is accurate; for both VPWR bridges it is not.

**Not a short.** The bridge's left edge (111.830) lies right of the `VSS!` pin's right
edge (110.890), so no VPWR–VGND bridging occurs. This is consistent with netgen's
unique match and with the zero power-grid violations.

**What this proves and does not prove.** It proves the connection exists but is
carried through a 0.23 µm Metal4 neck on both positive-supply bridges, and that
routed metal sits on declared macro obstruction. It does not prove any electrical
failure; no IR-drop or electromigration analysis was performed on these necks.

**Classification: concrete integration defect requiring correction.** This is a probe
defect, not a candidate defect, and it does not overturn feasibility — but it must not
be carried into S.4.

### F3 — LVS black-box only: accurate, and stronger than recorded in one respect

**Evidence.** `66-netgen-lvs/lvs_script.lvs`:

- `circuit1` = `64-magic-spiceextraction/tt_um_sram_probe.spice` (layout-extracted).
- `circuit2` = `sg13cmos5l_stdcell.spice` + `sg13cmos5l_io.spi` +
  `52-openroad-fillinsertion/tt_um_sram_probe.pnl.v`.
- `lvs … -blackbox -json`.

**The supplied CDL is never read.** `config.json` declares
`"spice": ["pdk_dir::libs.ref/sg13cmos5l_sram/cdl/RM_IHPSG13_1P_256x16_c2_bm_bist.cdl"]`,
but that path appears nowhere in the generated LVS script. The existing record's
claim is correct.

**What the pass does establish.** The macro enters the comparison as a zero-device
subcircuit carrying its full port list, including `VSS`, `VDD`, and `VDDARRAY`
(`tt_um_sram_probe.spice:28–29`). Ports 11/12/13 of the extracted instance
`Xmemory.sram` are `VGND`, `VPWR`, `VPWR`. The P&R netlist independently carries
`.\VSS! (VGND), .\VDD! (VPWR), .\VDDARRAY! (VPWR)`. Netgen reports
`Netlists match with 1 symmetry` and `Final result: Circuits match uniquely`.

So LVS does confirm, **from extracted layout**, that both positive macro supplies
reach `VPWR` and the ground supply reaches `VGND`. The current record understates
this as "wrapper boundary equivalence". It is worth stating precisely, because it is
the strongest supply evidence in the run.

**What it omits.** No comparison of macro-internal devices against the CDL. And
because `VDD!` and `VDDARRAY!` both land on `VPWR`, they are interchangeable — that
is the reported "1 symmetry" — so LVS cannot distinguish them and does not
independently confirm per-supply identity. It also says nothing about contact
adequacy, which is F2.

**Is a stronger check technically viable here?** Yes. The CDL is present in the PDK.
A transistor-level comparison would require reading it into `circuit2` and dropping
`RM_IHPSG13_1P_256x16_c2_bm_bist` from `MAGIC_EXT_ABSTRACT_CELLS` so Magic extracts
the macro from GDS. That is a real option in this toolchain, at substantial runtime
cost. It is **not** currently required by anything we can cite: TT precheck runs no
LVS at all for this tech.

**Classification: understood limitation with bounded claims** on technical adequacy;
**external requirement unresolved** on whether submission demands SRAM LVS. These are
separate questions and are kept separate.

### F4 — "Missing macro parasitics": benign, and the record overstates it

**Exact warning**, three times in `runs/attempt-005-full/warning.log`, once per corner:

> Netlists found for macro RM_IHPSG13_1P_256x16_c2_bm_bist, but no parasitics
> extraction found at corner `<corner>`. The netlist cannot be used for timing on
> this module.

**The missing object is a per-corner macro SPEF**, wanted because `config.json`
supplies `"nl": ["dir::RM_IHPSG13_1P_256x16_c2_bm_bist.blackbox.v"]`. Lacking it,
LibreLane declines to time the macro from its netlist and falls back to the macro
Liberty. That is the intended hard-macro abstraction, not a gap.

Against the four categories the review asked to separate:

| Category | Present? |
| --- | --- |
| Macro internal timing represented by Liberty | **Yes** — the macro Liberty is loaded in every corner |
| External routed interconnect parasitics | **Yes** — `54-openroad-rcx/nom/tt_um_sram_probe.nom.spef` is read; `report_parasitic_annotation` shows **0 unannotated and 0 partially unannotated drivers** in all three corners |
| Macro internal parasitics, separately extracted | **No** — correctly superseded by Liberty |
| Load / interface modeling | **Yes** — macro pin capacitances and limits come from its Liberty and are exercised by the max-cap check |

So the absent item is exactly the one that does not need to exist. External
interconnect is fully annotated, which is the thing that *would* have mattered.

**Classification: resolved by existing evidence.** The record's phrase "timing lacks
macro parasitics" reads as a timing-validity gap and should be narrowed. The real
timing gap is F5.

### F5 — Slew/capacitance violations, and a corner mis-binding not previously recorded

**Counts and corners** (`55-openroad-stapostpnr/summary.rpt`): max capacitance 12 in
*every* corner; max slew 8 slow, 5 typ, 0 fast. The "Overall" row reports 12 and 8.

**Violating endpoints** (`nom_slow_1p08V_125C/checks.rpt`) are all macro pins, none
are tie-offs, clocks, or IO:

- Max slew, limit 0.476 ns — macro **inputs** `memory.sram/A_DIN[8,10,11,9,12,13,14]`
  and `A_MEN`. Worst `A_DIN[8]` at 1.131 ns (slack −0.655).
- Max capacitance, limit 0.064 pF — macro **outputs**
  `memory.sram/A_DOUT[15,11,9,8,12,6,14,7,0,13,5,10]`. Worst `A_DOUT[15]` at
  0.0969 pF (slack −0.033).

**Where the limits come from.** `constraints.sdc` contains no `set_max_transition`
and no `set_max_capacitance`. Both limits are Liberty values: the typ macro Liberty
declares `max_transition : "0.476"` and `max_capacitance : 0.064`. These are genuine
device limits, not constraint artifacts.

**Reports are final.** They come from `55-openroad-stapostpnr`, after
`52-openroad-fillinsertion` and with the routed SPEF annotated. Not stale.

**New finding — the macro was timed at typical in every corner.** `config.json` maps:

```json
"nom_*": [ … _typ_1p20V_25C.lib ],
"min_*": [ … _fast_1p32V_m55C.lib ],
"max_*": [ … _slow_1p08V_125C.lib ]
```

but LibreLane's three STA corners are named `nom_fast_1p32V_m40C`,
`nom_slow_1p08V_125C`, and `nom_typ_1p20V_25C`. **All three match `nom_*`**, so the
`min_*` and `max_*` entries never applied. Verified directly — grepping each corner's
`sta.log` for the macro Liberty returns `…_typ_1p20V_25C.lib` in all three.

Consequences, using the macro's own Liberty values (`max_transition` 0.38 ns fast,
0.476 ns typ, 0.5952 ns slow):

- **Slow corner**: the applied 0.476 ns limit was *too strict*. Re-checked against the
  correct 0.5952 ns, all eight violators (0.606 – 1.131 ns) still violate. The eight
  slew violations are real regardless.
- **Fast corner**: the applied 0.476 ns limit was *too loose* — the correct limit is
  0.38 ns. The reported "0 slew violations at fast" is therefore **not established**.
- **Setup**: macro arcs were timed with typical delays. Worst setup slack is 14.017 ns
  on a 20 ns period, so setup is very likely still safe, but slow-corner macro timing
  is not established.
- **Hold**: worst hold slack 0.2177 ns occurs at `nom_fast_1p32V_m40C` — the design's
  tightest margin — and it was computed with typ rather than fast macro timing.

This also supersedes the existing record's framing. The note that "the standard-cell
fast corner is −40 °C while the supplied SRAM fast Liberty is −55 °C" implies the fast
macro Liberty was loaded. It was not loaded in any corner, so the temperature
mismatch never arose.

**Likely remedy for the violations themselves.** Drive and load at the macro boundary:
macro input nets are under-driven and macro output nets over-loaded. LibreLane's
repair and resize steps did not target macro pins. The fix is buffering/resizing, not
constraints — the limits are real.

**Classification: concrete integration defect (the corner mis-binding, in
configuration) plus a real electrical limitation (the violations).** Neither is
waived by setup/hold passing.

### F6 — Behavioral fixture is RTL-only (new)

`experiments/sram_flow_feasibility/run_behavioral.sh` invokes
`iverilog -g2012 -Wall -DFUNCTIONAL` over the macro's functional model, the macro
wrapper, `tt_um_sram_probe.v` (**RTL source**), and the testbench. It does not read
the synthesized netlist, the post-P&R netlist, or any SDF, although SDF exists for
all three corners.

The four checks are therefore **pre-synthesis RTL evidence with the functional macro
model**. In `sram-flow-feasibility.md` they are reported in the "Results" section
immediately above the physical results table, where they can be misread as
post-layout functional validation. No gate-level simulation was run.

**Classification: verification gap requiring a targeted check.** Low priority for
S.3, which is a physical-feasibility gate; relevant to S.4.

## Disposition table

| Finding | Exact evidence | Classification | Consequence | Required action |
| --- | --- | --- | --- | --- |
| F1 — 4 Magic DRC markers (1×M2.f, 3×M3.f) | `62-magic-drc/reports/drc.magic.rpt`; tech rules `ihp-sg13cmos5l-drc.tech:429,485–488`; `config.json` `MAGIC_DRC_USE_GDS:0`; KLayout `drc_sg13cmos5l.xml` 0 items | Understood limitation + verification gap | Artifact of blanket LEF obstruction treated as wide metal; authoritative GDS deck clean on identical rules; but only one GDS-based DRC opinion exists | Re-run Magic DRC alone with `MAGIC_DRC_USE_GDS: 1`; triage anything new |
| F2 — 2 `obsm4-metal4` illegal overlaps | `64-magic-spiceextraction/feedback.{txt,xml}`; `pdn_cfg.tcl` bridge coords vs macro LEF pin/OBS coords | **Concrete integration defect** | Both VPWR bridges offset ~1.87 µm: 1.61 µm on obstruction, only 0.23 µm contact to `VDD!`/`VDDARRAY!`. No short. Not an S.3 blocker; must not reach S.4 | Move both VPWR bridges to x `113700–115800`; re-extract |
| F3 — Black-box-only LVS | `66-netgen-lvs/lvs_script.lvs`; `reports/lvs.netgen.rpt`; `tt_um_sram_probe.spice:28–29`, `Xmemory.sram` ports 11–13 | Understood limitation (technical) + external requirement unresolved (policy) | Confirms both positive supplies reach VPWR from layout; omits macro-internal devices; VDD/VDDARRAY indistinguishable (the "1 symmetry") | Narrow wording both ways; keep the submission-policy question for S.2 |
| F4 — "Missing macro parasitics" | `warning.log` ×3; `54-openroad-rcx/nom/*.spef`; `filter_unannotated.log` 0 unannotated | **Resolved by existing evidence** | Only macro-internal SPEF is absent, correctly superseded by Liberty; external interconnect fully annotated | Narrow the record; stop listing it as a timing limitation |
| F5a — Macro Liberty bound to typ in all 3 corners | `config.json` glob map vs corner names; `sta.log` per corner shows `_typ_1p20V_25C.lib` ×3 | **Concrete integration defect (config)** | Fast-corner slew limit applied 0.476 vs true 0.38 → "0 fast slew violations" unestablished; tightest hold margin (0.2177 ns) computed at wrong macro corner | Rename corner keys or use exact corner names; re-run STA only |
| F5b — 8 slew / 12 cap violations | `summary.rpt`; `nom_slow_1p08V_125C/checks.rpt`; macro Liberty limits | Real electrical limitation | Macro inputs under-driven, macro outputs over-loaded; all 8 slew violations survive the corrected slow limit | Buffer/resize at the macro boundary; remeasure |
| F6 — Fixture is RTL-only (new) | `run_behavioral.sh` command line; no netlist/SDF inputs | Verification gap | Four checks are pre-synthesis; no post-layout functional evidence exists | Narrow wording; defer gate-level sim to S.4 |
| F7 — Archive not self-sufficient (new) | Archive listing vs files needed here (routed DEF, `.pnl.v`, extracted `.spice`) | Verification gap | Archived set alone cannot reproduce F1/F2/F3 | Record only; do not rebuild the archive and invalidate the published digest |

## Verified positive claims

| Claim | Status | Evidence |
| --- | --- | --- |
| Exact macro retained, no inferred memory | **Confirmed** | `06-yosys-synthesis/reports/stat.rpt` lists exactly one `RM_IHPSG13_1P_256x16_c2_bm_bist`; no `$mem` in `pre_techmap.rpt` |
| Antenna clean after repair | **Confirmed** | `46-openroad-checkantennas-1/reports/antenna_summary.rpt` — empty violation table |
| Power connectivity | **Confirmed logically; narrow physically** | `30-checker-powergridviolations` passed and extraction shows `VDD!→VPWR`, `VDDARRAY!→VPWR`, `VSS!→VGND`. Physical contact is 0.23 µm on both VPWR bridges (F2). Topological connection ≠ adequate physical access |
| Both supplies covered, not just one | **Confirmed** | Both appear as distinct extracted ports both landing on VPWR |
| Setup/hold 0 violations | **Confirmed as run; narrow** | `summary.rpt`; critical path genuinely traverses the macro (`A_CLK → A_DOUT[15] → wire28/A → uio_out[7]`); `check_setup` reported no unconstrained endpoints or loops. But all corners used typ macro timing (F5a) |
| External parasitic coverage in STA | **Confirmed** | 0 unannotated / 0 partially unannotated drivers, all corners |
| TT precheck all rows pass | **Confirmed** | `results.md` — 9 checks, all ✅; `precheck-nix.log` "Precheck passed"; consumed the verified final GDS at revision `cfa06bae…` |
| TT precheck DRC scope | **Narrower than it reads** | Its Magic DRC and KLayout FEOL/BEOL/offgrid are gated to sky130A/gf180mcuD (`precheck.py:387–406`). For this tech only the PDK KLayout deck runs |
| Behavioral fixture, 4 checks | **Confirmed but RTL-only** | F6 |

## S.3 closure assessment

S.3's acceptance criterion in [`phase_plan.md`](phase_plan.md) is:

> a reproducible supported-candidate result or a documented decision to defer,
> including the missing evidence and next investigation step.

The evidence meets it. The probe is reproducible (exact commands, frozen and
re-verified revisions, a checksummed archive whose digest and restoration hashes all
re-verify today), the candidate survives the full flow and the complete TT precheck,
and the missing evidence and next step are documented.

**Qualified S.3 closure stands. Do not reopen it**, and do not restate it as signoff.
Nothing found here materially fails S.3's own criterion: F2 and F5a are defects in the
*probe*, not in the candidate, and their correction is expected to improve the result
rather than overturn it. No status correction to `phase_plan.md` is required.

Separately assessed:

- **Experimental physical feasibility**: established, with F2 and F5a as known probe
  defects and F5b as a real unresolved electrical limitation.
- **S.4 entry readiness**: still gated on S.2, unchanged.
- **Submission/signoff readiness**: not established, and never claimed.

## S.4 prerequisites

Actual blockers, all pre-existing S.2 items — **none are waived by this review**:

1. Exact macro eligibility for the March 2027 6x4 `ihp-sg13cmos5l` target.
2. Authoritative acceptance of commoning `VDD!` and `VDDARRAY!` onto `VPWR`. F3
   establishes *physical* connection; it says nothing about *accepted electrical*
   supply commoning. These must not be conflated.
3. Final immutable submission revisions, or the recorded instruction that branches
   are prescribed plus the exact executed revisions. A missing immutable pin is not
   automatically a blocker; the executed revisions here are recorded and re-verified,
   and need rechecking when the target freezes.
4. Authoritative SRAM LVS requirement, if any.
5. Timed-model behavior, still unestablished (S.2a limitation, Icarus cannot drive the
   exact model's delayed timing-check signals).

New S.4 entry prerequisites from this review — corrections, not gates on S.2:

6. The emitted flow must not reproduce F2 (bridge misalignment) or F5a (corner glob
   collision). Both are configuration defects that would otherwise be inherited.

Addressable **during** S.4 emitted-flow validation, not blockers:

- F5b slew/capacitance repair at the macro boundary.
- F1 confirmation via Magic-on-GDS.
- F6 gate-level simulation against the final netlist and SDF.

Concerning **final submission acceptance** rather than backend implementation:

- Transistor-level SRAM LVS (F3), pending an applicable requirement.
- Macro eligibility (S.2 item 1).

## Ordered follow-up tasks

| # | Task | Inputs | Physical rerun? | Completion criterion |
| --- | --- | --- | --- | --- |
| 1 | Fix the two VPWR bridge x-ranges to `113700–115800` in `pdn_cfg.tcl` | macro LEF pin coords, `pdn_cfg.tcl` | Yes — one full probe rerun | `feedback.txt` has 0 entries; both VPWR bridges contact their pins over ≥2.0 µm |
| 2 | Fix the corner glob collision in `config.json` | `config.json`, corner names from `55-openroad-stapostpnr` | STA only, no re-route | Each corner's `sta.log` loads its matching macro Liberty (fast/typ/slow) |
| 3 | Re-run Magic DRC with `MAGIC_DRC_USE_GDS: 1` | final GDS, macro GDS | DRC stage only | The four boundary M2.f/M3.f markers are absent; any new markers triaged at source |
| 4 | Re-measure slew/cap after tasks 1–2 and size the repair | post-fix STA reports | STA only | Violation counts and corners restated against correct per-corner Liberty limits |
| 5 | Repair macro-boundary drive/load | post-fix netlist | Yes, if repair changes placement/routing | 0 max-slew and 0 max-cap violations, or a documented accepted residual |
| 6 | Gate-level simulation of the final netlist with SDF | `final/nl/*.nl.v`, `final/sdf/*`, existing testbench | No | The four fixture checks pass post-layout, or differences are explained |

Tasks 1 and 2 are independent of each other and both are prerequisites for 4. Task 3
is independent of all others.

## External questions

Only these genuinely require an authority. **No one has been contacted.**

| Question | Owner |
| --- | --- |
| Is `RM_IHPSG13_1P_256x16_c2_bm_bist` eligible for the March 2027 6x4 `ihp-sg13cmos5l` target? | Target competition authority — S.2b |
| Is commoning `VDD!` and `VDDARRAY!` onto `VPWR` electrically accepted, as distinct from physically connectable? | Target competition authority — S.2b |
| Does submission require SRAM LVS beyond black-box, and in what form? | Target competition authority — S.2b |
| Which immutable revisions apply at submission, if branches are not prescribed? | Target competition authority — S.2b |

Everything in F1–F7 is resolvable locally and needs no external authority.

## Commands used for this review

All read-only except the archive extraction into a scratch directory.

```sh
# Repository state, both repos, before and after
git -C /home/wayne/devel/jane/hardcaml_asic status --porcelain
git -C /home/wayne/devel/jane/scaf status --porcelain

# Evidence identity
sha256sum evidence/sram-flow-feasibility/attempt-005-artifacts.tar.gz
tar tzf evidence/sram-flow-feasibility/attempt-005-artifacts.tar.gz
sha256sum experiments/sram_flow_feasibility/runs/attempt-005-full/final/gds/tt_um_sram_probe.gds \
          experiments/sram_flow_feasibility/config.json \
          evidence/sram-flow-feasibility/tt-precheck-attempt-005/results.xml
git -C .toolchain/pdk rev-parse HEAD
git -C .toolchain/tt rev-parse HEAD
git -C .toolchain/tt-sram-s3-cfa06bae rev-parse HEAD

# Isolated re-extraction (did not touch preserved evidence or the run directory)
tar xzf evidence/sram-flow-feasibility/attempt-005-artifacts.tar.gz -C <scratch>/s3-review

# F1
cat  experiments/sram_flow_feasibility/runs/attempt-005-full/62-magic-drc/reports/drc.magic.rpt
grep -B6 'M3.f' .toolchain/pdk/ihp-sg13cmos5l/libs.tech/magic/ihp-sg13cmos5l-drc.tech
grep -o 'Metal3 ( [0-9]* [0-9]* )' \
     experiments/sram_flow_feasibility/runs/attempt-005-full/44-openroad-detailedrouting/tt_um_sram_probe.def
grep -c '<item>' evidence/sram-flow-feasibility/tt-precheck-attempt-005/drc_sg13cmos5l.xml
sed -n '380,430p' .toolchain/tt-sram-s3-cfa06bae/precheck/precheck.py

# F2
cat experiments/sram_flow_feasibility/runs/attempt-005-full/64-magic-spiceextraction/feedback.{txt,xml}
cat experiments/sram_flow_feasibility/pdn_cfg.tcl
# macro pin/OBS extents, converted to global coords with the (42,81) placement
awk '/PIN /{p=$2} /RECT/{...}' .toolchain/pdk/ihp-sg13g2/libs.ref/sg13g2_sram/lef/RM_IHPSG13_1P_256x16_c2_bm_bist.lef

# F3
cat experiments/sram_flow_feasibility/runs/attempt-005-full/66-netgen-lvs/lvs_script.lvs
tail -60 experiments/sram_flow_feasibility/runs/attempt-005-full/66-netgen-lvs/reports/lvs.netgen.rpt
grep -n 'RM_IHPSG13_1P_256x16_c2_bm_bist$' \
     experiments/sram_flow_feasibility/runs/attempt-005-full/64-magic-spiceextraction/tt_um_sram_probe.spice

# F4 and F5
grep -i parasitic experiments/sram_flow_feasibility/runs/attempt-005-full/warning.log
cat experiments/sram_flow_feasibility/runs/attempt-005-full/55-openroad-stapostpnr/summary.rpt
cat experiments/sram_flow_feasibility/runs/attempt-005-full/55-openroad-stapostpnr/nom_slow_1p08V_125C/checks.rpt
for c in nom_fast_1p32V_m40C nom_slow_1p08V_125C nom_typ_1p20V_25C; do
  grep -o 'RM_IHPSG13[^ ]*\.lib' \
    experiments/sram_flow_feasibility/runs/attempt-005-full/55-openroad-stapostpnr/$c/sta.log | sort -u
done
grep -m3 'max_transition\|max_capacitance' \
  .toolchain/pdk/ihp-sg13g2/libs.ref/sg13g2_sram/lib/RM_IHPSG13_1P_256x16_c2_bm_bist_{fast_1p32V_m55C,slow_1p08V_125C,typ_1p20V_25C}.lib

# F6
cat experiments/sram_flow_feasibility/run_behavioral.sh
```

## Evidence paths

- `evidence/sram-flow-feasibility/` — attempt logs, both precheck records, archive and
  digest, restoration hashes.
- `experiments/sram_flow_feasibility/` — probe inputs: `config.json`, `pdn_cfg.tcl`,
  `constraints.sdc`, RTL, testbench, blackbox view.
- `experiments/sram_flow_feasibility/runs/attempt-005-full/` — the live run directory
  (gitignored, 230 MB). Required for F1/F2/F3; see the completeness gap above.
- `.toolchain/pdk/ihp-sg13cmos5l/libs.tech/` — Magic DRC tech file and KLayout deck.
- `.toolchain/pdk/ihp-sg13g2/libs.ref/sg13g2_sram/` — macro LEF, Liberty, CDL.
- `.toolchain/tt-sram-s3-cfa06bae/precheck/` — the isolated precheck used for S.3.

## Next bounded task

Task 1 above, stated for handoff:

> In `experiments/sram_flow_feasibility/pdn_cfg.tcl`, change the two VPWR bridge
> rectangles from x `111830–113930` to x `113700–115800`, leaving the y ranges and the
> VGND bridge unchanged. The macro's `VDD!` and `VDDARRAY!` pins occupy global x
> 113.70–116.51; its Metal4 obstruction occupies 111.15–113.44. Re-run only the
> feasibility probe, then re-run the TT precheck at `cfa06bae…` against the new final
> GDS. Accept when `64-magic-spiceextraction/feedback.txt` contains zero entries, both
> VPWR bridges contact their pins over at least 2.0 µm, the TT precheck still passes
> every row, and macro retention remains exactly one hard instance with zero inferred
> memories. Do not change the corner map in the same run — that is task 2, so the two
> effects stay separable.
