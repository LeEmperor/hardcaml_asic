# SRAM example physical integration

Status: **public example physical acceptance passed 2026-10-25**. This implements the next slice of
[PT.2 and the remaining PT.0c disposition](../phase_plan.md), following the
[public synthesis integration](sram-example-integration.md). The phase plan owns
completion; this record owns the bounded work breakdown and actual execution log.

## Acceptance target and non-negotiable boundaries

Use `hardcaml_asic_example/memory/`, through an installed captured provider and
ordinary immutable Hardening bundle. Preserve its latency-one SRAM and two
8-bit staging registers. No automatic architectural registers, retiming, weakened
Liberty limits, modified stock SRAM internals or edited emitted bundles.

Physical repair may buffer, resize, place and route combinational logic under
recorded settings. Explicit user placement can change where justified. Macro
electrical checks, actual power contact and both supply rails must be inspected.

The old direct-pad probe remains historical/diagnostic evidence. It does not have
to become electrically perfect before the real example is evaluated. Its unresolved
Magic findings are not silently waived by this change of acceptance design.

## Findings informing the implementation

- The installed exact macro is 236.8 × 118.78 µm, R0, with irregular Metal4 pin
  columns and split VDD/VDDARRAY regions. Do not derive its geometry from the
  blog's 512×32 macro or reuse probe bridge coordinates.
- Native `PDN_CFG` is sourced before `pdngen`. Placement-aware bridges therefore
  need to run after native grid generation, before view writing and connectivity
  checks. Inspect actual transformed pin/OBS/grid geometry in integer DBU.
- The pinned LibreLane KLayout step supports the CMOS5L `.drc` deck, but the deck
  needs a writable `log` argument. Boolean options use textual `true`/`false`;
  `threads`, not `thr`, controls its workers. Include transitive deck/data inputs
  in checked execution provenance.
- Pinned Netgen does not consume `MACROS.spice` as schematic-side CDL by itself.
  Supply `EXTRA_SPICE_MODELS` and verify the actual generated LVS script reads it.
  DEF/LEF extraction and Netgen black-box handling initially establish macro-
  boundary/interconnect comparison with CDL loaded, not internal-device LVS.
- Keep raw Magic DRC/extraction output. KLayout on final assembled real GDS is
  the explicit geometric authority for this supported target/profile. Any permitted
  Magic diagnostic needs a narrow recorded disposition; integration defects and
  unclassified findings must still fail. Keep illegal-overlap errors enabled.
- Existing container/postcheck defaults allow 20 workers. The macro physical route
  must enforce its six-worker allocation end to end, including nested tools and TT.

The [organizer-linked walkthrough](https://kdp1965.github.io/ihp-um-janestreet-prism/ihp_sram_macro.html)
provides precedent for real-GDS KLayout and CDL integration. Its blanket switches
and coordinates are not copied as our acceptance policy.

## Shared contract

Keep schema-1 synthesis bundles readable. New physical bundles use macro contract
schema 2, execution `fresh_full`, and an explicit physical plan:

```text
physical_plan:
  schema_version: 1
  strategy: cmos5l_m4_edge_access_v1
  plan_file: physical/macro-plan.json
  pdn_tcl: physical/pdn.tcl
  macros: resource / actual instance / module / location / R0 / halo / supplies
  checking_profile: cmos5l_real_gds_v1
  lvs_scope: abstract_macro_boundary_with_schematic_cdl
```

The exact serialized shape is implemented once by the library; execution validates
that shape and its generated configuration, file hashes and completeness. Generated
power/checking inputs belong in bundle identity. PDK reads remain in preflight or
execution, never ordinary elaboration/rendering. Actual geometry is run evidence.
Fresh coarse full execution is the first capability; macro segmented checkpoints
remain unsupported until their complete closure is independently tested.

## Agent-sized work

### A — Library physical plan and power geometry (6 jobs)

Own lib macro physical plan/generator, `resolved`, `bundle`, `Macro_intent` and
focused library/power tests. Coordinate generated checking settings with B.

1. Require complete R0 physical intent for Hardening, common enforceable global
   halo, grid-aligned finite placement, footprint/bounds and inter-instance checks.
2. Emit `physical/macro-plan.json`, deterministic `physical/pdn.tcl`, native grid
   settings, supply hooks and halos. Search real pins/grid for legal edge contacts
   after native PDN generation; reject unsupported access instead of rounding or
   guessing. Validate opposite-net/signal/OBS clearance, neck width and contact.
3. Record actual chosen geometry and public supply pins in a machine-readable
   run artifact. Derive geometry from the loaded stock master, not probe constants.
4. Keep synthesis behavior compatible; add geometric and declaration negatives.
   No heavy EDA before allocation. All ASIC Dune invocations use shared flock.

### B — Full execution and physical checking (6 jobs)

Own runtime contract/preflight, coarse full route/transport, Python bridge,
postcheck, collection/report policy, and focused execution tests.

1. Admit the versioned physical contract only with complete generated inputs and
   pinned collateral/deck closure. Keep unsupported checkpoint transitions rejected.
2. Enforce six-worker transport, OpenROAD/KLayout settings, STA corner serialization
   and bounded postchecks. Record effective limits and tool identities.
3. Execute real-GDS KLayout with explicit options; require parseable zero-violation
   report and exact checked/final GDS identity. Verify real macro geometry exists.
4. Supply and verify schematic-side CDL consumption; report actual abstract/device
   extraction scope. Preserve Magic diagnostics and narrowly validate any accepted
   boundary artifacts, never silently zero their counts.
5. Make real electrical failures fatal to acceptance with evidence. Add macro
   functional models and a documented, checked zero-delay standard-cell replay
   path to postcheck; retain timing-conformance limits explicitly.
6. Add meaningful fixture/negative tests. Hand off runtime commands to coordinator.

### C — Independent example and acceptance (6 jobs)

Own example `memory/`, new physical evidence and docs, preserving previous
synthesis evidence and FIFO/Workbench defaults.

1. Add explicit operation selection for check/emission; retain synthesis and flop
   paths. Hardening uses the public physical contract without new hardware registers.
2. Evaluate explicit `(40,81)` R0 as a potentially better positive-grid alignment
   than `(42,81)`; accept it only when the provider validates actual power access.
3. Extend bundle/functional checks for Hardening and prepare final-netlist and
   physical-evidence validation. Do not treat a zero flow exit as acceptance.
4. After A/B handoff, capture/install into the isolated SRAM provider store using
   six jobs, then validate and emit a fresh immutable bundle. No EDA before the
   coordinator allocates it. Retain failed runs and exact development receipts.

### Coordinator — integration and actual flow

Maintain this record and shared seams, authorize serial physical work, and inspect
real results. Run preflight → fresh full → postcheck → collect/report through the
installed example provider. Diagnose concrete failures without weakening limits
or claiming unrun checks. Preserve reproducible raw evidence and source identities.

## Resource and Git policy

Maximum three agents, initially six jobs each plus two reserved. A/B serialize
shared-checkout Dune with `flock /tmp/opencode/asic-sram-build.lock`; all Dune
commands specify `-j6` (or a coordinator reassignment). C captures/builds separately.
Physical execution is explicitly allocated six workers after competing builds stop.
No git add/commit/push, authorship changes, automatic pin updates or installed
PDK/TT edits. Do not overwrite previous bundles, generations or evidence.

## Implementation / execution record

### Delivered and independently reviewed

The ordinary installed-provider path now supports fresh coarse Hardening for the
exact stock macro and checked R0 physical profile. It generates native standard-cell
PDN plus geometry-derived SRAM edge contacts; retains all three supply connections;
and validates actual geometry in the final GDS. Physical implementation preserves
the example's architecture: **one SRAM and the original 16 staging flops**.

The checking profile uses real assembled GDS with the pinned CMOS5L KLayout deck,
hashes transitive deck inputs, preserves raw Magic reports, and verifies actual
schematic CDL consumption through a naming-only Netgen adapter. Collection/reporting
require physical evidence, all-corner electrical checks and completed external
prechecks/replay; they do not infer acceptance from a successful subprocess alone.

### Failures that drove the fixes

| Attempt | Result and correction |
| --- | --- |
| P1 / `9c439718` | Native macro PDN grid had no shapes. Generate only the native standard-cell grid, then construct/verify explicit SRAM edge access; global supply connections remain intact. Bounded real OpenROAD diagnostic passed before retry. |
| P2 / `79df6b00` | Full route reached completion, KLayout/capacitance clean, but LVS naming mismatch and late wire-dominated slew violations failed. Netgen naming-only reader views and native post-global-route design repair addressed these separately. |
| P3 / `cf909599` | Full flow passed electrical/LVS checks; strict evidence validation rejected newly exposed M2 abstract-obstruction markers. Exact stock/single-layer/combined controls established their cause before extending the classifier. Original failed record remains failed. |
| P4 / `be961b2c` | Fresh installed public full run, physical evidence checks, TT precheck, final-netlist replay, collect/report and independent consumer audit all passed. |

Electrical repair enables native post-GRT buffering, legalization and re-routing,
with a **200 µm wire-length limit**, **20% optimization guardbands**, and exact
fast/slow/typical repair corners. Library limits and SDC did not change. Bounded
diagnostics compared netlists after contracting only inserted non-inverting buffers;
the final actual design retains the same 16 original flops. Delay cells used for
hold repair are combinational, not extra architectural registers.

The LVS reader changes only injective bus/supply token spelling in run-local views;
it preserves supplied CDL and powered Verilog. Tests with swapped address bits and
VDDARRAY tied to ground fail. The actual comparison pairs **109 macro pins** and
**421 nets on each side**. It is **abstract macro-boundary LVS with schematic CDL**,
not an internal-transistor verification claim.

### Magic disposition and PT.0c resolution

The final raw Magic count is **3**, not zero: two M2.f markers and one M3.f marker.
The exact-rule/geometry policy requires all four controls on the **same routed DEF**:

| Diagnostic-only LEF | Result |
| --- | --- |
| Unmodified stock | Exact three original coordinates/multiplicities |
| Only stock wide Metal2 OBS removed | Original M3 marker only |
| Only stock wide Metal3 OBS removed | Original two M2 markers only |
| Both exact wide OBS removed | Zero markers |

Only diagnostic LEFs change. Stock pins, narrow obstructions, implementation
collateral, streamout, extraction and LVS inputs stay unchanged. Unknown rules,
shifted/missing control evidence and integration-sensitive findings reject.
Independent real-GDS KLayout must also be clean. The final report retains raw=3,
dispositioned=3 and unclassified=0.

Independent review compared all **135 stock SRAM hierarchy cells** to the final
GDS and found geometry/reference/transform/text equivalence (excluding ordering
and timestamps). It also matched **11** reported bridge/grid/public-pin shapes
to actual GDS geometry and independently verified the naming-only CDL changes.

This closes **PT.0c in its revised example-centered scope**: the supported example
has zero slew/cap violations, an explicit supported checker disposition and retained
restorable evidence. It does not rewrite the old direct-pad probe's failure counts
or claim every macro-internal full-GDS Magic diagnostic has been repaired. Those
remain historical checker/fixture findings; the supported geometric authority is
the pinned real-GDS KLayout profile with the narrowly checked abstract diagnostics.

### Final public run and measurements

Provider generation:
`hardcaml_asic_example/.dev/asic-sram/generations/71a9a125992e4260b38dcdf954c6b965`.
Development capture SHA-256:
`632cb3358e36d193d3a580b9fa11164b8f376673d259bfbcfdd46ee1fdf68b99`.
Bundle `program-memory-exact-physical-p4` identity:
`fa38d9064dffdf2ec1578c79c2e8890eba81bf704af460e85fcc6031b707d53c`.
Run: **`be961b2c95f74c81ad6af81ca4d2b269`**, full execution exit **0**.
External postcheck: **`0553f6d19c8f42d28c057fc65ed23510`**, exit **0**.

Commands were executed from `hardcaml_asic_example` using that exact installed
provider, existing `_flow_tools`, a fresh run under `_flow_results/sram-physical`,
`run --stage full`, then `postcheck --testbench memory/replay.v
--testbench-top memory_replay --timeout 1800`, `collect`, and `report`.
Consumer launch/reproduction commands are in
[memory/PHYSICAL.md](../../../hardcaml_asic_example/memory/PHYSICAL.md).

| Corner | Setup slack (ns) | Hold slack (ns) | Setup/hold/slew/cap/fanout violation counts |
| --- | ---: | ---: | --- |
| Fast | 15.809827 | 0.223533 | All zero |
| Slow | 11.246561 | 0.814843 | All zero |
| Typical | 14.150889 | 0.430151 | All zero |

Routing/KLayout DRC, illegal overlaps, LVS, PDN, critical disconnected pins and
antenna violations are zero. All nine external TT precheck rows pass. Routed
gate-functional replay passes **1,280 word checks**; the deliberately corrupted
expected data fails. The final standard-cell area is **4,793.64 µm²**, separate
from the macro's **28,127.104 µm²** Liberty area. Standard-cell utilization alone
is not whole-design macro occupancy.

### Evidence and tests

Durable evidence is in the
[example acceptance index](../../../hardcaml_asic_example/acceptance/sram/README.md).
`physical-p4/` verifies **237 files / 85,863,331 bytes**; the compressed archive is
**8,789,090 bytes**, SHA-256:
`91503ecea09bd81fbe880874e4bd18737b1d5030ac206e3176656dd65f2aeb52`.
It includes inputs/provider receipts, raw reports, checked physical views, models,
commands and compact P1/P2/P3 failure records. The delivered archive was restored,
all hashes checked, and portable gate replay passed without the original workspace,
PDK or provider. Original accepted run and historical C1/C2 inputs are unchanged.

Tests include library geometry/negative fixtures, actual bounded PDN and electrical
diagnostics, real positive/negative LVS cases, **14 physical-policy tests**, consumer
tamper/model-derivation tests, and existing execution/collection/report/archive
regressions. The broad suite exposed one stale packaging module list; it now
requires the exact eleven installed runtime modules, including `macro_flow` and
`physical_runtime`, and all **17 packaging tests** pass. No runtime bytes changed
after the accepted provider capture for that test correction.
Final `dune runtest -j12` and both repositories' `git diff --check` pass. Both
delivered physical evidence inventories verify independently; no EDA containers
remain running.

All full flows and postchecks used six-worker ceilings (STA=1); concurrent diagnostic
allocations remained below 20. No pipeline stages, relaxed limits, PDK edits, git
staging/commit/push, automatic pin updates or original evidence rewrites occurred.

### Remaining scope

- PT.1d: timed SRAM/SDF conformance is not established by zero-delay replay plus STA.
- Internal-device SRAM LVS and detailed IR/EM adequacy remain unestablished.
- Fast standard-cell −40 °C / SRAM −55 °C library difference remains explicit.
- Macro checkpoint/restart support is still rejected; supported execution is fresh
  coarse synthesis/full with this exact stock R0 profile.
- Only the independent example has physical acceptance. Protemu adoption and its
  architecture-specific timing/physical validation remain PT.3 and later work.
