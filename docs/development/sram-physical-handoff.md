# A → B: exact SRAM physical bundle contract

> Final status: public P4 full execution and external TT/gate acceptance passed
> on 2026-10-25. See the [coordinator closeout](sram-example-physical.md).
> The dated diagnostic handoffs below preserve intermediate findings and do not
> supersede that final status.

## B p3 physical-evidence disposition (2026-10-25, execution-owned)

Source run `20261025T023413976323Z_cf909599` reached LibreLane `Flow complete.`
with LVS/electrical gates clear. Its original public wrapper record remains failed
and immutable. B ran diagnostics only, <=6 CPUs, with no full P&R replay.

### Exact M2/M3 obstruction diagnosis and policy

The source has two M2.f markers and one M3.f marker. The relevant **stock LEF**
artificial wide rectangles are:

- Metal2 OBS: `RECT 0 0.52 236.8 118.78 ;` (not the narrow M2 obstructions).
- Metal3 OBS: `RECT 0 0 236.8 118.78 ;`.

Using the **same routed DEF**, the actual controlled Magic checks produce:

| Diagnostic-only LEF | Remaining findings |
| --- | --- |
| Unmodified stock | All 3 original coordinates/multiplicities |
| Only the exact M2 wide rectangle removed | Exactly the original M3 marker (1) |
| Only the exact M3 wide rectangle removed | Exactly the original M2 markers (2) |
| Both exact wide rectangles removed | 0 |

Every pin, narrow M2 obstruction and other layer is preserved. Diagnostic LEFs
never enter implementation, streamout, extraction or LVS. The policy also requires
clean assembled-real-GDS KLayout, exact stock macro polygons and the existing
power/LVS/electrical checks. Raw Magic count is retained as **3**, dispositioned
count **3**, unclassified count **0**.

This is not a rule-name waiver. Only the two exact M2.f/M3.f rule renderings
(`120` internal 0.005-um units or `0.6um`) are recognized. The unmodified-stock
control must reproduce exact coordinates and multiplicities. Each single-layer
control must remove only its target markers, preserving the other layer's exact
markers; the combined control must be clean. Unknown rules, missing controls,
shifted markers, retained target errors, new errors and unrelated disappearing
errors fail. Source-LEF rectangle recognition is exact and refuses changed or
duplicate rectangles.

M3 markers must be thin strips just above/below the macro. M2 markers must be thin
strips outside its left/right edges, overlapping the stock wide M2 rectangle's
runlength. Perpendicular influence is bounded by min(halo, 0.6 um), and markers
crossing/inside the macro footprint reject. M2's longitudinal projection is bounded
by the pinned `widespacing ... 10005 10005 ... 600` rule: at most 10.005 um beyond
the wide obstruction's end. No arbitrary rectangle or halo-wide waiver is used.

The full-DEF controls take about three minutes here. They now run as at most four
independent single-worker Magic jobs, with a 300-second per-tool bound, inside the
six-CPU allocation. This avoids the former 180-second timeout without unbounded
workers. Standalone intrinsic-stock checking stays separate.

### Entire updated checker: actual disposable-clone pass

Diagnostic root: `/tmp/opencode/sram-p3-evidence`.

- `full-check-03/process.json`: **exit 0**, **188.190 seconds**, **6 CPUs**.
- `full-check-03/project/runs/asic/physical-checks.json`: **status pass**; the
  complete production `check` function executed, not only the marker classifier.
- `validated-summary.json`: independently verifies all **50** recorded artifact
  hashes, source immutable-bundle/runtime bindings, and byte identity of original
  versus clone GDS, final netlist and metrics.
- `full-check-03/clone-receipt.json`: records source-to-clone path-only relocation
  of metadata/logs/scripts and the updated checker hash. Both geometries, all
  electrical counts and original data remain unchanged.
- `original-inventory.json`: direct inspection of original P3 metrics, actual
  final-netlist cells and original LVS reader/report.
- `p3-models-01/replay-models.json`: actual final-netlist model derivation passes
  for all **23** used standard-cell types, with original/derived hashes verified;
  no simulation is implied.

Earlier diagnostic attempts are retained: `full-check-01` exposed the tight Magic
timeout; `full-check-02` passed the new classifier but exposed a diagnostic-clone
relocation omission (`.lvs` scripts). That omission was fixed in the clone harness,
not by weakening the production consumption verifier. The final run exercised
all later log, Netgen-receipt, final-pin, artifact-path and hashing checks as well.

P3 real-GDS SHA-256:
`2d1b1eb9d9d5c6cc0fb543f34903f36a779637fc9985eb3f3cf0f52f9c888dc4`.
Passing clone physical-evidence SHA-256:
`be3b8a0d36dc961d4db3fe64502399aff0e3243811dd2f8687931f725640746c`.

### Original final physical results and boundary

The final netlist retains **one** stock SRAM at `hc_resource_7_program` and exactly
**16** `sg13cmos5l_dfrbpq_1` staging flops; no other standard-cell storage type was
found. LVS has 109 matched macro pins and **421 nets on each side**.

| Corner | Setup slack ns | Hold slack ns | Setup/hold/slew/cap/fanout counts |
| --- | ---: | ---: | --- |
| fast | 15.809827 | 0.223533 | all 0 |
| slow | 11.246561 | 0.814843 | all 0 |
| typical | 14.150889 | 0.430151 | all 0 |

Routing DRC, real-GDS KLayout, illegal overlaps, LVS, power-grid violations,
critical disconnected pins and antenna net/pin counts are all zero. The complete
checker verifies final macro/power/public-pin geometry and retains abstract
macro-boundary-with-schematic-CDL LVS scope; it does not claim internal-device LVS.

External TT precheck and final-netlist gate replay remain acceptance work. No
original run status/evidence was rewritten, no supplied PDK/CDL/LEF was changed,
and no Git mutation or provisioning was performed. The updated runtime must be
captured before future public use. Focused tests include exact per-layer controls,
unknown/integration-overlap rejection and preservation of non-target collateral.
The physical-policy suite now has **14** passing tests; existing SRAM runtime
contract/negative fixtures also pass under the shared flock with `-j6`.
Native collection/report/archive regressions and `dune build -j6 @install` pass.

## B p2 diagnostic coordination (2026-10-25, execution-owned)

Original run `79df6b00` is immutable. Diagnostic root:
`/tmp/opencode/sram-lvs-p2-diagnostic`; all Netgen/Magic commands use the recorded
image, read-only workspace/PDK mounts, fresh output directories and <=4 CPUs.

- Netgen library-first reads expose a naming mismatch: stock CDL uses scalar
  `A_ADDR<7>` and `VDD!`; powered Verilog uses vector named ports and escaped
  `\VDD!`. Positional calls and reversing read order were **rejected**: although
  Netgen says "match uniquely", their JSON has unmatched macro pins (96/192),
  and positional calls can make the macro disappear from the top inventory.
- B's runtime adapter keeps supplied files unchanged, derives an injective
  per-subcircuit CDL naming view (`<bit>` -> `[bit]`, explicit supplies without
  trailing `!`), and changes only the three matching macro named supply ports in
  an LVS-only powered Verilog view. No cell/device/order/connectivity is removed.
  Actual isolated runtime step: **LVS count 0**, all pins matched and one SRAM on
  both sides. Address-bit swap and VDDARRAY-to-ground controls both fail the actual
  runtime validator. This remains abstract macro-boundary LVS, not device LVS.
- Final assembled macro polygons and the recorded three power contacts/public
  pins pass B's actual GDS checks. A's power construction does not need a change
  for those checks.
- Pinned LibreLane coerces textual deck booleans to integer 0. Actual deck logs
  confirm all geometry switches enabled. The checker now accounts for that exact
  coercion. The relative deck log is at project root; captured stdout is
  `63-klayout-drc/klayout-drc.log`, not `drc-klayout.log` in that step.
- The single M3.f marker is outside the macro's bottom boundary, so the original
  intrinsic-stock baseline correctly rejects it. A controlled diagnostic using
  the **same routed DEF** and removing only stock LEF's full-footprint Metal3 OBS
  produces Magic count **0**. That derived LEF is diagnostic-only, never physical
  or LVS collateral. B implemented a narrow exact-rule/halo/counterfactual policy
  requiring independently clean real-GDS DRC and unchanged stock polygons.
- A owns remaining slew closure. No full P&R replay is authorized/performed by B.

### B p2 delivered execution changes and retained proof

`flow/hardcaml_asic_flow/macro_flow.py` installs a scoped Classic Netgen subclass
for fresh physical execution. It retains the native library-first read order and
native checker. A's `EXTRA_SPICE_MODELS` stays pointed at the original CDL; no new
library setting or emitted-bundle edit is needed. Only this step uses the recorded
derived reader inputs. Both source/derived hashes and every naming change are in
`lvs-reader.json`. The checker recomputes the transformation and verifies actual
script/log consumption, all 109 matched macro pins, zero JSON discrepancies and
the macro's survival in both top-level device inventories. The original layout
SPICE, supplied CDL, powered Verilog, implementation state and final netlist are
unchanged. The runtime driver/helper bytes are bound to the run and archived.

Actual proof under `/tmp/opencode/sram-lvs-p2-diagnostic/`:

| Path | Result |
| --- | --- |
| `runtime-adapter-01/` | Actual new runtime subclass, Netgen 1.5.320: LVS metric **0**, one SRAM on each side, 109 matched pins, 322 nets each |
| `runtime-negative-address-01/` | Actual subclass rejects swapped address bits; Netgen JSON has bad nets/elements |
| `runtime-negative-supply-01/` | Actual subclass rejects VDDARRAY connected to VGND; Netgen JSON has bad nets/elements |
| `strict-results.json` | Successful independent source/derived/script/log/JSON verification; rejected positional and ordering-only false leads |
| `audit-02/audit.json` | Successful read-only source-run audit: real-GDS/power/deck/log checks pass, M3 marker disposition established, original LVS/slew failures retained |
| `audit-03/audit.json` | Adds measured-clearance/final-public-LEF checks and derivation of **22** actual final used-cell types; persisted checks complete, outer 180-second command timed out, so not a successful acceptance/process receipt |
| `driver-contract-01/` | Actual isolated installed-style driver import/CLI help passes; no Flow.start/P&R |

`strict-results.json` additionally verifies the final public LEF power rectangles
and all original/derived model hashes successfully, independently of that timed-out
audit command. No Icarus simulation or TT postcheck was run in this allocation.
A separate attempted full-real-GDS Magic diagnostic (`magic-real-01/`) timed out at
180 seconds and is **not** a disposition basis; the clean same-DEF controlled
obstruction diagnostic supplies that basis.

Supplied CDL SHA-256 is
`f7918bfd22caa5b317bd2222adbdf700588e93c9c55a131a753fa6227abb2c53`.
The successful actual runtime LVS JSON SHA-256 is
`d71f557cc9345ac7e44f5c20ba74c8ee6ea6187f2d5b0a2e3dc6900d303a3ac1`.

The source run still has LVS **35** and slew **1 fast / 2 slow / 1 typical**;
all three cap counts are zero. It remains failed and is never relabeled accepted.
The next captured provider must include this new driver/helper, then a fresh full
run after A's slew fix. Segmented macro execution remains unsupported.

Focused verification after these fixes: **12 physical-policy tests**, public
SRAM schema/command/negative fixtures, coarse execution, collection, archive,
report and postcheck suites pass under the shared flock with `-j6`.
`dune build -j6 @install` also passes, including installation of the new driver.

Implementation contract, 2026-10-24. A owns library generation and
`test/sram_physical`; B owns runtime/checking and the existing synthesis fixture.
The coordinator's main record is `sram-example-physical.md`.

## Serialization (exact field names)

Synthesis continues to emit macro contract schema **1**, execution
`synthesis_only`, with the existing fields and no physical-plan files.
Hardening emits the same collateral/model inventory, macro contract schema **2**,
execution **`fresh_full`**, and `physical_plan` with this shape:

```json
{
  "schema_version": 1,
  "strategy": "cmos5l_m4_edge_access_v1",
  "plan_file": "physical/macro-plan.json",
  "pdn_tcl": "physical/pdn.tcl",
  "checking_profile": "cmos5l_real_gds_v1",
  "lvs_scope": "abstract_macro_boundary_with_schematic_cdl",
  "macros": [
    {
      "resource": "program",
      "instance": "hc_resource_7_program",
      "module": "RM_IHPSG13_1P_256x16_c2_bm_bist",
      "location_um": [40.0, 81.0],
      "orientation": "R0",
      "halo_um": 2.0,
      "supplies": {"VDD!": "VPWR", "VDDARRAY!": "VPWR", "VSS!": "VGND"}
    }
  ]
}
```

`physical/macro-plan.json` is exactly that object (pretty JSON plus newline).
The manifest embeds the same object. Array ordering is canonical instance order.
The example numbers above are illustrative; actual locations/IDs come from checked
resolution. Existing per-macro `physical_intent` retains location/orientation/halo/
power fields; its `execution` becomes `fresh_full` for physical bundles.

## Generated settings

In addition to existing MACROS/stub/exact-corner settings, physical bundles own:

| Key | Value |
| --- | --- |
| `PDN_CFG` | `dir::../physical/pdn.tcl` |
| `PDN_MACRO_CONNECTIONS` | two bindings per actual instance: VDD!/VSS! and VDDARRAY!/VSS! to VPWR/VGND; anchored escaped instance regex |
| `PDN_CONNECT_MACROS_TO_GRID` | `true` |
| `PDN_MULTILAYER` | `false` |
| `PDN_VERTICAL_LAYER` | `Metal4` |
| `PDN_VWIDTH`, `PDN_VPITCH`, `PDN_VOFFSET`, `PDN_VSPACING` | `2.1`, `50.0`, `10.0`, `2.0` |
| `PDN_ENABLE_RAILS`, `PDN_ENABLE_PINS`, `PDN_ENABLE_GLOBAL_CONNECTIONS` | `true` |
| `PDN_RAIL_LAYER`, `PDN_RAIL_WIDTH` | `Metal1`, `0.44` |
| `PDN_SKIPTRIM`, `PDN_CORE_RING` | `false` |
| `PDN_HORIZONTAL_HALO`, `PDN_VERTICAL_HALO` | `0.0` |
| `FP_MACRO_HORIZONTAL_HALO`, `FP_MACRO_VERTICAL_HALO` | common declared halo (at least 2 µm) |
| `ROUTING_OBSTRUCTIONS` | Metal4 macro footprints, translated from each intent and the exact stock dimensions; no halo expansion. Lower-layer signal access retains native LEF OBS/PORT semantics rather than an extra global blockage over ports. |
| `RUN_KLAYOUT_STREAMOUT` | `true` |
| `PRIMARY_GDSII_STREAMOUT_TOOL` | `klayout` |
| `RUN_KLAYOUT_DRC` | `true` |
| `KLAYOUT_DRC_RUNSET` | `pdk_dir::libs.tech/klayout/tech/drc/ihp-sg13cmos5l.drc` |
| `KLAYOUT_DRC_THREADS`, `KLAYOUT_XOR_THREADS` | `6` (the backend appends its worker option after deck options) |
| `KLAYOUT_DRC_OPTIONS` | object below |
| `EXTRA_SPICE_MODELS` | singleton exact stock `pdk_dir::libs.ref/sg13cmos5l_sram/cdl/RM_IHPSG13_1P_256x16_c2_bm_bist.cdl` |
| `RUN_MAGIC_DRC`, `ERROR_ON_ILLEGAL_OVERLAPS` | `true` |
| `MAGIC_MACRO_STD_CELL_SOURCE` | `PDK` |
| `MAGIC_EXT_ABSTRACT_CELLS` | singleton stock macro module |
| `MAGIC_DRC_USE_GDS` | `false` (abstract Magic diagnostics retained; real GDS checked by KLayout) |

KLayout options (all boolean switches are **strings**):

```json
{"no_feol":"false","no_beol":"false","no_offgrid":"false",
 "no_angle":"false","no_pin":"false","no_forbidden":"false",
 "no_recommended":"false","precheck_drc":"false",
 "log":"drc-klayout.log","threads":6}
```

The log is relative to the step's working directory, not a generated bundle output.
B must validate effective worker limits, including this deck's `threads` option.
Physical generated keys and deprecated aliases reject project/catalog overrides;
ordinary synthesis settings remain compatible.

Consumer Hardening must remove these existing `Tt_cmos5l.overrides` defaults via
`~without`: `RUN_KLAYOUT_DRC`, `FP_PDN_VPITCH`, `FP_PDN_VWIDTH`,
`FP_PDN_MULTILAYER`. They become generated facts, rather than override assignments.

## Geometry and execution artifact

The generated Tcl contains an instance/resource table and all implementation
logic. It runs native pdngen first, then inspects transformed OpenDB pins, OBS,
special wires and via enclosures. It adds bounded Metal4 edge access to all three
named supplies, never crosses the internal split-supply obstruction bar, and
selects real uninterrupted public supply stripes. Coordinates are integer DBU
derived from loaded geometry, not copied probe positions.

The explicit policy is 0.6 µm conservative clearance, 1.4 µm minimum bridge neck
and contact width, and 0.4 µm positive pin/grid overlap; these are integration
policy minima, not a claim of current/EM adequacy. Native technology minimum width,
spacing, manufacturing grid and actual DBU are also checked. Complete intent,
common halo >=2 µm, and 0.005 µm placement/halo alignment are required.

Successful generation writes:

```text
$STEP_DIR/macro-power-geometry.json
```

Report schema 1 records strategy, units, per-resource/instance/master placement,
each supply contact (pin/bridge/grid rectangles and clearances), and selected
VPWR/VGND public pin rectangles. B should retain/hash this artifact, require all
three named contacts for every registered resource, and revalidate geometry after
later template application/final routing. A geometry report is not DRC/LVS/IR proof.

The Tcl hook is installed through `PDN_CFG`, after native grid definition and
before the caller invokes `pdngen`. A scoped wrapper calls native generation,
performs checked edge construction, restores the original command, and returns
before LibreLane writes/checks views. Errors propagate as errors; no waiver is
emitted. Failed candidate search reports the resource/supply and rejects.

B verifies pinned collateral/deck closure, exact generated file hashes/config,
CDL consumption on the schematic side and abstract extraction scope, final real
GDS DRC, retained raw Magic counts/dispositions, worker limits and full-run gates.
No segmented/checkpoint capability is implied.

Each contact includes policy `minimum_clearance_dbu`, actual conservative
`measured_minimum_clearance_dbu`, `minimum_contact_width_dbu`, and
`minimum_overlap_dbu`. Native rails are explicitly Metal1 / 0.44 µm; trim is on
and core ring is off. All PDN/FP_PDN overrides are owned by this physical profile.

Exact report fields:

- Root: `schema_version: 1`, `strategy`, `dbu_per_um`,
  `manufacturing_grid_dbu`, `macros`, `public_pins`.
- Each macro: `resource`, `instance`, `module`, `orientation: R0`,
  `footprint_dbu`, `halo_dbu`, `contacts`.
- Each contact: `pin`, `net`, `edge` (`bottom`/`top`), `pin_rect_dbu`,
  `grid_rect_dbu`, `neck_rect_dbu`, `landing_rect_dbu`,
  `minimum_clearance_dbu`, `measured_minimum_clearance_dbu`,
  `minimum_contact_width_dbu`, `minimum_overlap_dbu`.
- Each public pin: `net`, `layer: Metal4`, `rect_dbu`.
- Every rectangle is `[x_min,y_min,x_max,y_max]` in integer DBU. Measured
  clearance is conservative rectangular separation, not a signoff-deck result.

## A verification / delivered boundary

Passed:

```sh
flock /tmp/opencode/asic-sram-build.lock opam exec --switch=5.2.0+ox -- \
  dune runtest -j6 test/sram_physical
```

- Complete/missing intent, common/global/minimum halo, grid alignment, overlap,
  die fit, generated-key/alias conflicts and normal TT template integration.
- Deterministic schema-2 plan/config/Tcl emission, inventory hashes, matching
  manifest/plan JSON and exact resource-to-instance bindings for two resources.
- Schema-1 synthesis compatibility and byte-identical architectural RTL between
  Synthesis and Hardening of the same declaration.
- 18 pure emitted-Tcl geometry assertions: translated placements, contact area,
  clearance equality/off-by-one, opposite supply, OBS, insufficient neck, core/
  halo escape, top array access and irregular columns.
- Strict non-EDA Tcl OpenDB fixture: full two-resource hook, 12 actual bridge-box
  constructions, all six supply contacts, measured clearances, public pins and
  parseable report; six independent failure cases (wrong supply net, orientation,
  dimensions, missing grid, native failure, via-enclosure collision). Hook restores
  the native command on success and error. Fixture unknown methods fail.

All tests above use PDK-free fixtures/Tcl, not an EDA invocation. Actual native
grid clipping, final pin/route geometry, physical DRC/LVS/IR/electrical acceptance
remain coordinator execution evidence. The temporary fixture bundles/reports are
removed by the test; production output paths are the two bundle files and the
per-step report path documented above. No existing `test/sram_bundle` fixture was
edited by A.

## Native PDN correction (physical-p1 follow-up)

The public physical-p1 run exposed PDN-0232/PDN-0233: the empty default native
macro grid has no shapes/vias on the same-Metal4 strategy, so native pdngen fails
before edge access runs. The generator now defines only the native stdcell grid;
the explicit checked edge-access hook supplies the macro after native generation.

**B setting changes: none.** `PDN_CONNECT_MACROS_TO_GRID` stays **true** and both
`PDN_MACRO_CONNECTIONS` entries remain generated. Global supply binding is
independent of defining a native macro grid and must not be disabled. The generated
Tcl bytes/hash change; a fresh captured provider/bundle is required for full flow.

A bounded real OpenROAD diagnostic from preserved stage-19 ODB/state is authorized
for this correction, in new disposable directories, six CPUs/threads, without a
full-flow launch. Results and exact commands follow below after verification.

### Bounded real result, 2026-10-25

**Passed** in `/tmp/opencode/sram-pdn-native-fix-03`, using the locally pinned
LibreLane image `sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a`.
Container quota: `--cpus 6`; OpenROAD: `-threads 6`; OMP: 6. Workspace/PDK/TT and
all preserved run inputs were mounted read-only; only the fresh output directory
was writable. No full flow was launched, and no container remained afterward.

Commands from the ASIC root (reproduction requires a **new** output name):

```sh
flock /tmp/opencode/asic-sram-build.lock opam exec --switch=5.2.0+ox -- \
  dune runtest -j6 test/sram_physical

python3 -B test/sram_physical/run_pdn_diagnostic.py \
  --project /home/wayne/devel/jane/hardcaml_asic_example/_flow_results/sram-physical/runs/20261025T010527676274Z_9c439718/project \
  --generator _build/default/test/sram_physical/physical_consumer.exe \
  --output /tmp/opencode/sram-pdn-native-fix-03

python3 -B test/sram_physical/verify_pdn_diagnostic.py \
  /tmp/opencode/sram-pdn-native-fix-03
```

The emitter's `generate-pdn` mode validates/reconstructs the saved plan through
`Macro_physical_plan.create/files`, and emits the same bytes as bundle generation;
the non-EDA test checks that equivalence. The old run/bundle was not hand-edited.
The diagnostic restores LibreLane's private nominal Liberty, SDC and excluded-cell
environment from retained public settings. Attempts `-01` and `-02` are retained:
both stopped at harness setup (`STA-0577`, missing private corner variables), before
native PDN. After restoring those variables, `-03` passed without further generated
runtime API changes.

`openroad.log` contains only `Inserting grid: stdcell_grid`, no PDN-0232/0233,
and PSM-0040 for both VPWR and VGND from the normal step and explicit verification.
Both `*-grid-errors.rpt` files are empty. Actual power nets and saved powered Verilog
retain `VDD! -> VPWR`, `VDDARRAY! -> VPWR`, `VSS! -> VGND`; 16 staging flops remain.

Actual chosen rectangles, **µm** (from integer-DBU report and independently verified
in the saved DEF):

| Supply | Edge | Neck `[xmin,ymin,xmax,ymax]` | Landing `[xmin,ymin,xmax,ymax]` |
| --- | --- | --- | --- |
| VDD! / VPWR | bottom | `[112.180,79.000,113.580,81.400]` | `[111.830,79.000,113.930,80.400]` |
| VDDARRAY! / VPWR | top | `[112.180,199.380,113.580,201.780]` | `[111.830,200.380,113.930,201.780]` |
| VSS! / VGND | top | `[165.790,199.380,167.190,201.780]` | `[165.790,200.380,168.030,201.780]` |

All three contacts have 1.4 µm neck/contact width, 0.4 µm macro penetration,
and measured conservative minimum clearance **0.6 µm**. Public pins:

- VPWR: `[1011.830,3.560,1013.930,707.080]` µm.
- VGND: `[1015.930,3.560,1018.030,707.080]` µm.

These are **observed outputs**, not coordinates embedded in the generator.

Artifact inventory in the successful directory:

- `commands.json`: exact generation/container argv and input SHA-256s.
- `pdn.tcl`: freshly generated Tcl, SHA-256
  `a1795098f315d1720aed470efabb7f3fc930a97c0a0bc02cbf4e984e4ebcaf9e`.
- `macro-power-geometry.json`: actual contacts/public pins/clearances, SHA-256
  `9110b34a0efed2fb016737dd7886e8f0a87b109e9df993adfd2e1ff6fcf3d3d8`.
- `inspection.json`, `openroad.log`, `metrics.json`, `pdn.odb`, `pdn.def`,
  `pdn.nl.v`, `pdn.pnl.v`, `pdn.sdc`, empty per-net grid error reports.
- `verification.json`: independently confirms all six bridge rectangles and both
  public pins in saved DEF, supply bindings in saved powered Verilog, positive
  contact dimensions, report/grid correspondence and unchanged hashed inputs;
  hashes all diagnostic artifacts and the preserved stage-19 state.

The ordinary suite also reproduces the empty native macro-grid failure when that
declaration is reintroduced, rejects it before bridge construction and verifies
hook restoration. Generated configuration/schemas are unchanged. B/C should
capture the corrected source and emit a fresh immutable bundle; the old physical-p1
bundle still correctly fails and is preserved. This bounded result establishes
PDN-stage construction/connectivity, not routed DRC/LVS/electrical acceptance.

## P2 electrical correction: post-CTS long-wire buffering (2026-10-25)

### B/C setting changes — schemas and architecture unchanged

New **generated physical-only** settings, protected against project/catalog
conflicts (including the three `GLB_RESIZER_*` deprecated aliases):

| Key | Value |
| --- | --- |
| `RUN_POST_GRT_DESIGN_REPAIR` | `true` |
| `GRT_DESIGN_REPAIR_RUN_GRT` | `true` |
| `GRT_DESIGN_REPAIR_MAX_WIRE_LENGTH` | `200.0` µm |
| `GRT_DESIGN_REPAIR_MAX_SLEW_PCT` | `20` |
| `GRT_DESIGN_REPAIR_MAX_CAP_PCT` | `20` |
| `RSZ_CORNERS` | exact fast/slow/typ `STA_CORNERS` list |

This activates native `OpenROAD.RepairDesignPostGRT` after CTS/global routing,
using native buffering, legalization and re-GRT. The positive wire limit enables
long-wire buffering which the pinned zero setting does not perform. The 20%
values are optimization guardbands, **not changes to Liberty/SDC limits**.
No register/retiming/latency changes, no net-specific preservation attributes or
hard-coded example pin repair, and no output-port-buffer override are introduced.
The ordinary TT `~without` list does not change. B regenerates expected settings
through the library; C must capture the new source and emit a fresh bundle.
Schema 1 synthesis and the schema-2 physical plan/report shapes remain unchanged.

### Actual p2 root cause and all-corner extracted baseline

Preserved input run:

```text
/home/wayne/devel/jane/hardcaml_asic_example/_flow_results/sram-physical/runs/20261025T011729961662Z_79df6b00/project/runs/asic
```

Resource `program` is actual macro `hc_resource_7_program`. Exact final extracted
slew violations (ns), independently reproduced from the final ODB and actual SPEF:

| Pin | Fast slew / limit | Slow slew / limit | Typical slew / limit |
| --- | --- | --- | --- |
| `hc_resource_7_program/A_DIN[9]` | 0.452601 / 0.380000 | 1.064665 / 0.595200 | 0.693125 / 0.476000 |
| `_150_/Y` | below limit | 2.689511 / 2.507400 | below limit |

- Data path: `uio_in[1] -> hold199 -> hold127 -> input7 -> hold128 -> A_DIN[9]`.
  `hold128` is `sg13cmos5l_dlygate4sd3_1`, inserted by CTS hold repair. Its `net128`
  drives the SRAM and `_165_/A1`, `_182_/A1` (two mux inputs). Its final driver is
  near `(180,395)` µm; the SRAM load is near `(206,81)`, the mux loads near
  `(173,63)` and `(70,63)`. Final extracted wire cap is **0.115602 pF**, versus
  **0.008418–0.010824 pF** total pin cap. The weak delay cell drives a long,
  wire-dominated three-load branch, not simply an excessive macro input cap.
- Read/output path: `program/A_DOUT[2] -> _148_/B -> _150_/B -> uo_out[2]`.
  `_150_` is `sg13cmos5l_nor3_1`, near `(121,66)` µm, driving the port near
  `(110,710)`. Final wire cap is **0.133458 pF** versus **0.006000 pF** external
  load: **0.139458 pF** total. Slow rise slew fails even though capacitance and
  clock-period setup/hold checks pass.
- Pre-CTS electrical repair ran with 20% margins; CTS then inserted 88 hold
  buffers/delay cells. Both post-GRT repair switches were off. Native placement
  repair could not account for this later topology and detailed-route wire load.
- GRT estimates understate these two final wire caps: **0.063582 pF** on net128
  and **0.083579 pF** on the output. Raw rise/fall min/max paths and all three
  corners are retained; the analysis does not rely only on the worst path.

### Bounded native diagnostics and evidence

All real diagnostics used the pinned image from the PDN correction, six container
CPUs, OpenROAD threads=6, OMP=6, a 300-second limit and read-only workspace/PDK/run
mounts. Each attempt has a fresh directory and exact command/input hashes.

- `/tmp/opencode/sram-slew-final-02`: successful reproduction using preserved
  stage-53 ODB and actual stage-54 SPEF, all three exact Liberty sets. Contains
  all-corner electrical checks, every macro signal net's driver/load report and
  **24** rise/fall × min/max path reports through the two violating pins.
- `sram-slew-final-01` is retained: its reports reproduced the same violations,
  but the diagnostic inventory used unavailable `dbNet.getId`; the harness now
  uses an explicit counter. `sram-slew-repair-01` is retained as a Tcl-list
  serialization setup failure; numeric layer adjustments now use minimal quoting.
- `/tmp/opencode/sram-slew-repair-02`: native repair, 20% slew margin, zero wire
  limit; zero buffers/resizes. Slow A_DIN[9] remains **0.633677 ns** estimated.
- `/tmp/opencode/sram-slew-repair-03`: increasing slew margin to 60% still adds
  zero buffers/resizes and leaves the same violation. No such knob is adopted.
- `/tmp/opencode/sram-slew-repair-04`: 200 µm wire limit and 20% slew/cap margins
  inserts 99 buffers on 34 nets and clears all-corner estimated slew/cap checks.
- `/tmp/opencode/sram-slew-repair-05`: repeats the successful native experiment
  using **settings emitted by the rebuilt library**, with full global setup/hold
  and parasitic-annotation reports. All-corner estimated electrical checks clear:

| Corner | Worst estimated hold slack | Worst estimated setup slack |
| --- | --- | --- |
| fast | +0.126808 ns | +15.876975 ns |
| slow | +0.624496 ns | +11.431496 ns |
| typical | +0.305031 ns | +14.263145 ns |

The data net becomes a buffer tree; `hold128` now drives only `wire266/A`, reducing
its estimated total load to **0.011520–0.012261 pF**. The SRAM branch is driven by
`wire264`, a `sg13cmos5l_buf_2`. The output port is driven by `wire229`, another
`sg13cmos5l_buf_2`, with **0.025074 pF** total estimated load. Original `_150_`
and all original gates/registers are retained.

`verification.json` in `-05` checks every corner and all 24 transition/path cases,
all global min/max reports, unchanged hashed inputs and parasitic annotation.
It also **contracts all 99 new non-inverting A→X buffers and compares every port
connection/type of every original cell** against the preserved pre-repair netlist.
This proves the observed candidate is buffer-only: no new registers/inverters,
removed/resized original cells, changed macro/control connections or buffer loops.

Raw estimator warnings are retained: native re-GRT emits transient `EST-0026`
missing-route messages during rebuilding, and `RSZ-0065` notes that forcing wires
below its delay-optimal length increases delay. Final annotation has **zero
partially unannotated drivers** and only the same five unused phantom inputs
`ui_in[3..7]` as before. No active/new driver is unannotated. Positive estimated
setup/hold is checked explicitly rather than dismissing the delay warning.

**Scope:** this is all-corner **global-route estimated** improvement after native
buffering, not final detailed-route extraction, DRC, LVS or electrical signoff.
No full P&R was run. Coordinator must rerun the public example from a fresh bundle
and check final extracted slew/cap/setup/hold, DRC/LVS and functional replay.

Commands from the ASIC root (new output names required for reproduction):

```sh
flock /tmp/opencode/asic-sram-build.lock opam exec --switch=5.2.0+ox -- \
  dune runtest -j6 test/sram_physical

_build/default/test/sram_physical/physical_consumer.exe generate-settings \
  /home/wayne/devel/jane/hardcaml_asic_example/_flow_results/sram-physical/runs/20261025T011729961662Z_79df6b00/project/physical/macro-plan.json \
  /tmp/opencode/sram-electrical-settings.json

python3 -B test/sram_physical/run_slew_diagnostic.py \
  --run /home/wayne/devel/jane/hardcaml_asic_example/_flow_results/sram-physical/runs/20261025T011729961662Z_79df6b00/project/runs/asic \
  --mode repair --generated-settings /tmp/opencode/sram-electrical-settings.json \
  --output /tmp/opencode/sram-slew-repair-05

python3 -B test/sram_physical/verify_slew_diagnostic.py \
  /tmp/opencode/sram-slew-final-02 /tmp/opencode/sram-slew-repair-05
```

The diagnostic's `--mode final` command produces the extracted baseline. Ordinary
non-EDA regressions additionally reject corrupted data wiring, new registers,
inverting replacements, buffer loops and missing timing evidence. Existing
schema-1 compatibility, power geometry and unchanged architectural RTL checks
remain in the same focused suite. No p2/PDK/TT files were modified.

## B-owned execution requirements (2026-10-24)

B consumes the exact plan above and keeps schema-1 synthesis readable. Runtime
requires final real-GDS DRC report/metric agreement, checked/final GDS hash equality,
executed Netgen script reading the declared CDL, all three supply contacts per
resource in the geometry artifact, and raw Magic diagnostics. Unknown Magic
findings fail closed; a clean real-GDS report alone does not waive an abstract
finding. The runtime can generate a standalone stock-LEF baseline using the same
pinned Magic setup: only exact rule/rectangle/multiplicity matches strictly inside
the macro and outside new bridge clearance envelopes may be dispositioned. The
actual example baseline remains unrun; a failure to establish it is a failure.
Postcheck derives a hash-recorded zero-delay view of final used standard cells;
unreviewed delayed-reference patterns reject rather than guessing. All physical
launch/container/host/postcheck workers are bounded at six, STA at one.

### B runtime implementation and coordinator commands

The execution validator regenerates A's plan, settings and Tcl using the library
module and rejects even a resealed modified Tcl. Preflight includes transitive
CMOS5L/sibling SG13G2 checking files and both standard-cell replay sources. Macro
segmented/checkpoint execution is still rejected by both preparation and bridge.

Fresh full launch runs Classic with six jobs, six OpenROAD/KLayout workers and one
STA corner worker. It explicitly selects all slew/cap corners. The pinned CLI
parses list overrides as whitespace-delimited strings, so these overrides are
`MAX_SLEW_VIOLATION_CORNERS=*` and `MAX_CAP_VIOLATION_CORNERS=*`, not JSON arrays.
Magic DRC's upstream checker is put into warning mode **only** on this physical
route, followed by a mandatory hash-bound target-specific checker. Raw Magic
reports/counts are retained; illegal-overlap errors remain enabled. A successful
LibreLane exit without successful physical evidence validation fails the run.

`physical-checks.json` records real-GDS/DRC/CDL/power evidence and hashes the raw
artifacts. The checker compares assembled macro polygons with pinned stock GDS,
requires all three supply contacts and retained bridge/public-pin metal in final
GDS, verifies the actual Netgen script and log read the CDL, and reports only
`abstract_macro_boundary_with_schematic_cdl`. It does not claim internal-device
LVS, IR/current adequacy, SDF replay or timed-model conformance.

Collection verifies the physical evidence, final GDS and raw-artifact hashes,
retains original Magic counts, and separately requires max-slew/max-cap checks.
Report acceptance also requires intact external precheck and gate replay. Archive
includes physical reports/feedback and hash-recorded original/derived replay models.
Physical postcheck defaults to 1800 seconds per tool (caller may specify a positive
timeout), with host affinity, container quota and thread environment bounded at six.
Nix invocations also explicitly bound realization to one job and six cores.
Its run-local TT copy supplies `threads=6`, textual deck switches and writable log;
the installed TT tree is not modified.

After C captures/installs the integrated provider and emits a **new Hardening
bundle**, coordinator commands from the example root are:

```sh
PROVIDER="$PWD/.dev/asic-sram/current/bin/hardcaml-asic-flow"
BUNDLE="$PWD/.dev/program-memory-physical-next" # fresh output from memory CLI
"$PWD/_build_sram/default/memory/memory_cli.exe" emit --selection exact \
  --operation hardening --source-root "$PWD" --output-dir "$BUNDLE"
"$PROVIDER" preflight "$BUNDLE" --toolchain "$PWD/_flow_tools" \
  --results-root "$PWD/_flow_results/sram-physical" --json
"$PROVIDER" run "$BUNDLE" --toolchain "$PWD/_flow_tools" \
  --results-root "$PWD/_flow_results/sram-physical" --stage full --json
# Set RUN to the returned run_dir, retaining failed attempts independently.
"$PROVIDER" postcheck "$RUN" --toolchain "$PWD/_flow_tools" \
  --testbench "$PWD/memory/replay.v" --testbench-top memory_replay \
  --timeout 1800 --json
"$PROVIDER" collect "$RUN" --json
"$PROVIDER" report "$RUN" --json
```

The old synthesis bundle/generation is not a physical-capable provider. These
commands have not been run against physical EDA by B. Unsupported final routed
standard-cell delayed-reference patterns fail replay rather than silently changing
vendor behavior; the reviewed staging flip-flop pattern is supported.

### B verification

The following completed successfully under the shared flock with `-j6`:

```sh
flock /tmp/opencode/asic-sram-build.lock opam exec --switch=5.2.0+ox -- \
  dune build -j6 @test/sram_bundle/runtest @test/physical_execution/runtest \
  @test/ocaml-coarse-run @test/ocaml-postcheck @test/ocaml-collect \
  @test/ocaml-report @test/ocaml-archive @test/ocaml-preflight \
  @test/ocaml-execution-transport @test/ocaml-stage-preparation @test/backend-protocol
```

New coverage includes ten schema-2 OCaml/Python rejection cases, resealed
noncanonical Tcl rejection, Docker6/STA1 full argv, mandatory checker failure,
physical postcheck subprocess/model/TT contracts and source-mutation failure.
Seven focused physical-policy tests cover exact-baseline matching versus unknown,
boundary/bridge-adjacent or duplicate findings; report/GDS/CDL/log seams;
missing/nonfinite/electrical metrics; actual native collection preserving nonzero
raw Magic counts and rejecting modified reports; native acceptance requiring
slew/cap and replay; final-used-cell derivation and unsupported-pattern rejection.
Geometry/EDA interfaces in these fixtures are simulated; they are not evidence
that the real layout passed. Existing transport/preflight/coarse/postcheck,
collection/report/archive, stage-preparation and protocol regressions pass.
The collector suite separately notes an unavailable historical retained
finalization fixture; it is not a physical acceptance result.
