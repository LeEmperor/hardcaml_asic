# PT.0 corrected SRAM evidence — 2026-10-24

**Disposition: PT.0a (power access) and PT.0b (corner binding) have verified
evidence for completion. PT.0c remains open. This is not physical signoff.**

## Evidence identity and verification

`pt0-artifacts.tar.gz`: **8,379,623 bytes**, SHA-256:

```text
0c32607e16d3bb5e3c313033a53db0883167b3ab6b44c5f30bac0e3066546b9a
```

The archive has 1,163 inventoried payloads plus its internal `inventory.json`.
The adjacent inventory, summary and dependency manifest are convenience copies
of the archived versions. The archive uses sorted members, normalized regular-file
metadata, and a gzip header with timestamp zero. Two independent collections
produced byte-identical archives. Collection and verification launch no EDA.

From the ASIC checkout:

```sh
python3 -B experiments/sram_flow_feasibility/collect_pt0.py \
  --verify evidence/sram-pt0/pt0-artifacts.tar.gz
(cd evidence/sram-pt0 && sha256sum -c SHA256SUMS)
```

`--verify` checks the exact member set, safe member paths, regular-file types,
every payload length and every SHA-256 against the internal inventory. The
outer SHA-256 above / `SHA256SUMS` also authenticates the inventory bytes.
`SHA256SUMS` covers all adjacent deliverables except itself.

Regeneration from the original complete live runs (not from the compact archive):

```sh
# Parent must exist; destination must not exist. No existing evidence is replaced.
.toolchain/.venv-precheck/bin/python -B \
  experiments/sram_flow_feasibility/collect_pt0.py --output /tmp/pt0-new-evidence
```

Collection uses `gdstk` from the existing precheck interpreter to inspect actual
GDS polygons and macro references. Archive verification uses only Python stdlib.
The collector itself and the current 33-test regression sources are archived.
The 33 tests passed with no skips or expected failures during this review.

The original S.3 archive was read and rehashed, never rewritten:

```text
evidence/sram-flow-feasibility/attempt-005-artifacts.tar.gz
de16cf3d8a584e2bace6ec999651e4c73f2c2adfe28a0b042f531835e9843d43
```

## Corrected-grid-02 findings

Raw run prefix inside the archive:

```text
experiments/sram_flow_feasibility/runs/pt0-corrected-grid-02/
```

Its `status.json` records **flow exit 2, precheck exit 0**. Under
`inputs/runs/corrected-grid-02/`, `error.log` identifies the deferred flow error:
**3 Magic DRC errors**. The flow exit does not mean setup/hold failed, and
precheck success does not waive the remaining electrical or model/deck findings.

### Power geometry, retention and supplies

The emitted final GDS and routed DEF independently retain exactly **one**
`RM_IHPSG13_1P_256x16_c2_bm_bist`, at **(42,81) um, R0**. GDS Metal4 drawing is
layer/datatype **50/0**, units 1 um, precision 1 nm.

| Net | Actual rectangle `(xmin,ymin)-(xmax,ymax)`, um |
| --- | --- |
| VPWR lower | `(113.700,79.520)-(115.650,81.000)` |
| VPWR upper | `(113.700,197.660)-(115.650,201.310)` |
| VGND lower | `(64.400,79.520)-(68.030,81.000)` |

Positive-pin contact width is **1.950 um**; ground contact width is **1.530 um**.
The adjacent VGND stripe begins at x=115.930 um, leaving **0.280 um** clearance,
above the applicable 0.210/0.240 um Magic Metal4 spacing rules. Both the original
obstruction overlap and power-01's 0.130 um bridge/grid clearance are corrected.

`64-magic-spiceextraction/feedback.xml` has **zero items**. Its extracted SPICE
contains exactly one macro instance, with **VSS -> VGND, VDD -> VPWR,
VDDARRAY -> VPWR**. `66-netgen-lvs/reports/lvs.netgen.rpt` reports a unique match.
This is macro **abstract/black-box LVS**, not SRAM transistor-level verification.

### Corners and timing

`55-openroad-stapostpnr/<corner>/sta.log` records exactly one SRAM Liberty per
corner, under `.toolchain/pdk/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram/lib/`:

| Corner | SRAM filename suffix after `RM_IHPSG13_1P_256x16_c2_bm_bist_` |
| --- | --- |
| `nom_fast_1p32V_m40C` | `fast_1p32V_m55C.lib` |
| `nom_slow_1p08V_125C` | `slow_1p08V_125C.lib` |
| `nom_typ_1p20V_25C` | `typ_1p20V_25C.lib` |

The fast standard-cell **-40 C** / SRAM **-55 C** difference is retained explicitly.

| Corner | Setup worst slack, ns | Hold worst slack, ns | Slew violations | Cap violations |
| --- | ---: | ---: | ---: | ---: |
| Fast | 15.502759 | 0.277922 | 12 | 12 |
| Slow | 11.739905 | 1.039666 | 25 | 12 |
| Typical | 14.137210 | 0.537211 | 21 | 12 |

All corners have zero setup/hold violations, zero setup/hold TNS, zero fanout
violations, and zero unannotated/filtered-unannotated nets. Register-to-register
paths are N/A. Raw driver annotation checks also report zero partially
unannotated drivers. These use the retained nominal extraction corner for RC.
Exact values and actual Liberty load multiplicities are in `summary.json`.

Worst slow-corner examples in `checks.rpt`:

* `A_ADDR[1]` slew **1.252720 ns**, limit **0.595200 ns**.
* `A_DOUT[13]` capacitance **0.104796 pF**, limit **0.064000 pF**.

### Physical checks and residuals

`62-magic-drc/reports/drc.magic.rpt` contains only three **M3.f** LEF-obstruction
boundary rectangles (um):

```text
(42.000,80.540)-(97.580,80.740)
(123.460,80.540)-(145.340,80.740)
(215.900,80.540)-(278.800,80.740)
```

No M2 or M4 category remains in this abstract Magic report. The earlier retained
GDS check supports the abstract nature of M3.f, but is not a new Magic-on-GDS
check of corrected-grid-02.

`tt/precheck/reports/results.md` and `results.xml` record **all nine rows passing**:
pin-label overlap, SG13CMOS5L DRC, zero area, KLayout checks, pin, boundary, layer,
cell name and analog pin. All three DRC XML databases contain **zero items**.
The actual TT checkout is **d66cf179e7bc4d296362ab7e2e3b344dc3c4f665**; the PDK is
**2bbec755dc67ca3db0261c3d6163e15735d66710**, both recorded clean at execution.
The launcher and precheck log record **10 threads**. Older attribution runs used
the historical TT checkout; their manifests preserve that distinction.

## Attribution runs preserved

* **corners-01:** outer status records flow exit 0. Retained geometry with corrected
  exact macro corners; setup/hold pass. Slew counts fast/slow/typical **2/8/5**,
  cap counts **12/12/12**. Raw timing logs and nominal SPEF/netlist inputs retained.
* **power-01:** flow exit **2**, precheck exit **1**. Pin/obstruction correction
  worked, but 0.130 um clearance produced **10 M4.b + 2 M4.e** rectangles, alongside
  **1 M2.f + 3 M3.f**. Zero extraction feedback, unique black-box LVS. Historical
  typical SRAM Liberty loaded twice in each corner. Precheck report-directory
  failure is preserved, not represented as a geometric pass.
* **magic-01:** **outer exit is unavailable** after the invoking shell timed out;
  there is no fabricated `status.json`. Stage state/log/runtime prove completion
  in **21m51.867s**. The retained GDS, raw text and LYRDB reports are preserved.
  **29,294** reported rectangles are all inside the macro bbox: NW.d exception
  **115**, subcell abut/partial overlap **368**, Cnt.c **12**, layer overlap
  **13,087**, M2.d **15,360**, Cnt.c SRAM exception **22**, LU.d/LU.d1 **330**.
  No M2.f/M3.f/M4 category occurs. **Macro-internal Magic/PDK/deck compatibility
  disposition remains unresolved; these findings are not waived.**

The fresh corrected layout reran optimization with corrected libraries, so its
electrical counts need not equal corner-only STA on the historical routing.

## Contents, restoration and reproducibility limits

Archive paths preserve the checkout-relative tree. Included are authored immutable
input snapshots for all four runs; original runner manifests/commands/status when
available; stage commands, configs, states and runtimes; raw final STA logs/reports;
DRC, extraction and LVS reports; and corrected final GDS (KLayout and Magic), DEF,
LEF, NL/PNL, SPICE, nominal SPEF, SDC, SDF and timing models. Routed-stage DEF,
P&R netlists and extracted SPICE are also explicitly retained at stage paths.
The corrected isolated TT precheck/tech sources and reports are included.

ODB databases, Magic working databases, renderings, most intermediate physical
views/logs and the original large archive are excluded. Identical final/stage
views remain at their logical paths so absolute recorded references are traceable;
gzip compresses these repetitions. This is an analysis/replay evidence set,
not an arbitrary-stage resume image or a complete toolchain distribution.

Restore only into a **fresh separate directory** after checksum verification:

```sh
RESTORE=$(mktemp -d /tmp/pt0-restore.XXXXXXXX)
tar -xzf evidence/sram-pt0/pt0-artifacts.tar.gz -C "$RESTORE"
python3 -B "$RESTORE/experiments/sram_flow_feasibility/collect_pt0.py" \
  --verify "$PWD/evidence/sram-pt0/pt0-artifacts.tar.gz"
```

Raw reports, coordinates, supply mapping and loaded-library attribution can be
reanalyzed immediately. To repeat the GDS/DEF/SPICE verification without EDA,
use the existing precheck Python (with gdstk), import the restored collector and
call `geometry()` on its restored corrected `inputs/runs/corrected-grid-02` path.

For actual STA/DRC replay, first recreate the recorded toolchain/PDK externally.
`external-dependencies.json` lists 37 referenced external files with sizes/hashes;
the run manifests and `toolchain.lock` identify revisions/container pins. PDK
views, Docker/Nix images and interpreter environments are not bundled. Additional
transitive tool/deck dependencies still require those pinned installations.

Recorded JSON, commands and Tcl contain the original absolute workspace prefix,
`/home/wayne/devel/jane/hardcaml_asic`. **Do not replay them unmodified at another
location.** Copy the archived authored `inputs/` files to a disposable replay
directory, replace that prefix with the restored root in copied configuration,
and set `FP_DEF_TEMPLATE` to the copied `floorplan.def`. Keep originals untouched.
Create a minimal initial state pointing at restored files:

* STA: `{"nl": "ABSOLUTE_FINAL_NL", "spef": {"nom_*": "ABSOLUTE_NOMINAL_SPEF"}, "metrics": {}}`.
* Magic-on-GDS: `{"gds": "ABSOLUTE_FINAL_GDS", "metrics": {}}`.

The corrected final paths are under `inputs/runs/corrected-grid-02/final/`.
Use the archived command's pinned tool options, **fresh output identity** and an
explicit coordinator allocation, selecting only the intended step. Original
stage-state files also refer to intentionally omitted databases; they are
provenance, not directly usable portable resume states. A complete fresh flow
can instead use the copied authored inputs and restored external toolchain.

No replay EDA was run as part of collection. TT precheck success, black-box LVS,
positive setup/hold slack and PDK-free functional tests do not establish macro
timed-model conformance, electrical closure or physical signoff. PT.0c remains
open for targeted electrical repair, macro-internal Magic/deck disposition and
any further corrected-GDS checks required by the coordinator.
