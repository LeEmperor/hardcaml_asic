# SRAM integration through the independent example

> Follow-on: the [2026-10-25 physical closeout](sram-example-physical.md) delivers
> the physical slice described as next work below. Timed-model conformance and
> macro checkpoint support remain open. This record retains the synthesis milestone.

Status: public synthesis/functional slice verified 2026-10-24; physical integration
and timed-model conformance remain open. This is the agent-sized implementation
record for the revised direction accepted by the owner. The [phase plan](../phase_plan.md)
remains the only active queue; this record supplies design decisions and evidence.

## Architectural and acceptance decisions

1. `hardcaml_asic_example/memory/` is the ongoing production-style acceptance
   design. It must use public ASIC APIs, emitted immutable bundles and supported
   execution interfaces. Protemu will adopt that demonstrated capability later.
2. The Verilog circuit under `experiments/sram_flow_feasibility/` remains a
   historical feasibility specimen and bounded diagnostic reproducer. It is not
   a second production consumer. Electrical closure of its direct pad-to-SRAM
   wiring is not a prerequisite to implementing the public example path.
3. The owner controls architecture. The library/flow must not insert registers,
   retime across the resource boundary, change read latency, add initialization,
   or change arbitration to repair physical violations. Any such change requires
   an explicit consumer design and contract revision.
4. Behavior-preserving combinational buffering, cell sizing, placement and routing
   are legitimate implementation operations under recorded flow settings. If they
   cannot close the design, report failure rather than alter its architecture or
   weaken macro electrical limits.
5. Resource identity and actual emitted macro instance names must be linked.
   Source names aid diagnosis but are not a promise of one-to-one net survival
   through synthesis. Do not apply blanket preservation attributes for diagnostics.
6. The initial backend supports exactly the existing 256×16, 1RW, latency-one
   contract. There is no automatic banking, shape rounding or implicit fallback.
   Functional-model acceptance and timed-model conformance remain distinct.

## Blog findings and target-specific checking

Source, retrieved 2026-10-24:
[Ken Pettit, Dropping a real SRAM macro into your CMOS5L tile](https://kdp1965.github.io/ihp-um-janestreet-prism/ihp_sram_macro.html).
The article describes a 2026-09-29 design using two IHP **512×32** macros in an
**8×4** tile. Our macro is **256×16**, initially targeting **6×4**. Its coordinates,
column counts, supply access and measured results are not our design inputs.

Relevant findings to verify and implement:

- IHP supplies the SRAM family in the Open PDK, with GDS, LEF, Liberty, Verilog
  and CDL. Our macro is stock IHP collateral, not a modified or third-party SRAM.
  Wrappers, placement and surrounding power metal are our integration.
- Tie `A_DLY` high, disable BIST, and implement the portable full-word 1RW contract
  with the appropriate read/write enables. Load both the exact Verilog model and
  shared core with `FUNCTIONAL` for functional implementation/netlist simulation.
- Match exact LibreLane corner names to the actual macro files. Record the
  fast standard-cell −40 °C versus SRAM −55 °C difference; do not use overlapping
  wildcard mappings or describe those temperatures as identical.
- Macro power requires physical pin access to both `VDD!` and `VDDARRAY!`, plus
  `VSS!`. Supply-name hooks alone do not establish adequate physical connection.
  Read geometry from the applicable pinned LEF/technology data and check nearby
  signal and opposite-supply metal. Our PT.0 spacing defect makes this concrete.
- The article explains Magic's limitations with SRAM LEF obstructions and uses
  the **CMOS5L KLayout deck on real GDS** for geometric DRC. Its configuration
  disables Magic DRC and illegal-overlap failure, enables KLayout DRC, and sets
  `KLAYOUT_DRC_RUNSET` to the PDK's `ihp-sg13cmos5l.drc`.
  This is precedent for an explicit target-specific checking policy, not a blanket
  waiver: confirm the pinned runset/options and final GDS coverage, retain raw
  extraction/DRC findings, and never hide newly introduced connection defects.
- The article supplies CDL via `MACROS.spice` for LVS. Verify actual tool
  consumption and distinguish abstract/black-box comparison from internal-device
  verification. Supplying a filename is not proof of transistor-level LVS.
- The TT marker-layer fix is already in our current pinned support tools.
- Antenna diode insertion and grid-alignment steps are possible implementation
  measures, not architectural registers. Adopt only when actual reports justify it.

The 29,294 Magic findings in the earlier retained GDS need not be repaired by
editing stock macro internals. If checker compatibility remains uncertain, compare
the supplied macro standalone under the same deck and document the result. Prefer
establishing the supported KLayout/CDL checking path in the real example over
turning Magic-specific cleanup of the old probe into the main project.

## Deliverable and checkpoints

First deliverable: the example requests Exact through `Single_port_ram`, emits
the real macro with the unchanged cycle contract, independently simulates it with
the vendor functional model, and reaches mapped synthesis through the installed
public flow. Physical intent and checking must be explicit before proceeding to
hardening. Each checkpoint reports unsupported/unverified operations truthfully.

1. Exact library mapping/instantiation, stable names and role-complete collateral.
2. Deterministic public bundles, execution preflight and actual mapped synthesis.
3. Example physical implementation with declared placement/power/checking policy,
   electrical diagnostics and final-netlist functional replay where supported.

Checkpoint 1 or 2 alone does not close PT.1 timed-model conformance or PT.2 physical
acceptance. The actual run evidence decides completion; no copied probe config or
hand-editing emitted bundles may substitute for the public path.

## Agent assignments and shared interface

### A — Exact hardware backend (6 jobs)

Own `lib/single_port_ram.*`, `lib/resource/request.*`, `id.*`, `technology.*`,
`lib/elaboration/context.*` if necessary, and focused resource/RAM tests.

- Introduce one canonical RAM request builder to avoid duplicate order-sensitive
  sexp contracts and a module dependency cycle.
- Register the stock 256×16 mapping. Add CDL and timed-model collateral roles;
  keep references PDK-relative and elaboration PDK-free.
- Instantiate the macro directly through Hardcaml, with combinational control
  adaptation and no new registers. Unknown macro implementations still fail.
- Provide deterministic injective `Resource.Id.rtl_instance_name` for B to match
  against Hardcaml's actual emitted instance name; preserve logical resource IDs.
- Verify selection, wiring, unsupported shapes and functional-model behavior.

Shared collateral convention: PDK references are `pdk_dir::libs.ref/...`; the
production synthesis stub is generated by B for the known macro, rather than
resolved from the historical experimental directory. A and B must agree on its
reference marker before changing code. Existing simulation remains behavioral;
implementation simulation uses the separate functional collateral inventory.

### B — Resolution, bundles and execution integration (6 jobs)

Own `lib/elaboration/resolved.*`, `bundle.*`, necessary platform/flow/project
declaration files and exports, execution/preflight/backend changes, and their tests.

- Add the smallest coherent explicit physical-intent API, keyed by resource ID,
  for supported placement/orientation and power/checking policy. Unsupported
  physical cases must fail rather than inherit the old probe's absolute geometry.
- Validate actual emitted instance naming, exact collateral/corner closure and
  selected operation. Emit synthesis stub and macro configuration from records.
- Remove blanket macro execution rejection only for validated supported inputs;
  account for collateral in preflight/checkpoint identities and simulations.
- Expose an explicit CMOS5L real-GDS KLayout policy with documented scope; retain
  extraction diagnostics and report whether LVS is abstract or CDL/device-backed.
- Keep all PDK reads at preflight/execution, not elaboration/rendering. Coordinate
  public API signatures with C early. Do not run EDA until coordinator allocation.

### C — Example adoption and independent acceptance (6 jobs)

Own `hardcaml_asic_example/memory/` and its documentation only. Preserve existing
FIFO and untracked memory work. Coordinate public API use with A/B.

- Update Exact-negative checks to positive supported-macro acceptance; preserve
  unsupported-shape negatives and the explicit flop configuration.
- Exercise actual macro implementation RTL with its vendor functional models,
  including full-address reads/writes, latency, holds and negative oracles. Never
  substitute behavioral-only simulation for macro implementation evidence.
- Use isolated `.dev/asic-sram` provider capture/install and a dedicated build
  directory. Do not change active FIFO/Workbench generations or tracked pins.
- Supply a memory-specific public flow launch path and documented commands.
  Record physical results only when actually run with coordinator resource limits.

### Coordinator

Maintain docs and shared API decisions, serialize builds in the ASIC checkout,
review handoffs, and run the installed example implementation with a total budget
of at most 20. Physical EDA uses an explicitly allocated pool after competing
builds finish. Retain exact evidence and failures, and update the phase plan.

## Execution policy

- No git add/commit/push or authorship/publication actions.
- Maximum 3 implementation agents. A/B/C allocations are 6 each (18 total), with
  2 reserved; A and B must serialize Dune in their shared checkout. C's capture
  build uses a separate directory. All nested jobs count toward the pool.
- No automatic provisioning, pin advancement or mutation of installed PDK/TT
  sources. Existing local toolchain is available; actual readiness is checked.
- No heavy EDA until explicitly allocated; bound OpenROAD, STA corners, KLayout
  and postcheck rather than assuming `dune -j` or LibreLane `--jobs` bounds them all.

## Evidence

### Delivered boundaries

- A delivered canonical RAM requests, injective resource-to-instance naming, the
  exact stock technology mapping, direct macro instantiation and role-complete
  collateral. Control adaptation is combinational; no extra registers were added.
- B delivered checked resource/actual-instance association, public R0 placement
  intent, deterministic macro bundles, PDK preflight and post-execution identity
  checks, plus the installed fresh coarse synthesis route. See
  [the public API and supported-operation contract](sram-public-bundle.md).
- C adopted the backend in the independent example using isolated provider
  captures, preserved explicit flops, and verified actual vendor-functional RTL
  and mapped-netlist behavior. No FIFO/Workbench active generation or dependency
  pin changed. The tracked ignore list now covers `_build_sram/`.

Hardening, full runs, physical postchecks and macro checkpoint publication remain
explicitly rejected. Physical intent does not imply power metal was constructed.
CDL is inventoried/verified, but actual consumption/extraction scope is not yet
proved. The real-GDS KLayout policy is a documented next implementation contract,
not a claim that the example has passed physical DRC.

### Verification and review

- Three-backend contract replay (behavioral, flop and vendor-functional macro):
  **2,307 edges / 1,794 defined-read/hold checks each**, plus negative oracles and
  control/tie-off checks. Unsupported shapes and custom incompatible mappings fail.
- Independent example: **1,792 Cyclesim edges** in each tested configuration,
  **four TT RTL replays × 1,280 word checks**, and direct Exact core replay of
  **2,048 edges / 1,536 response checks**, with negative oracles. Exact
  Implementation uses vendor-model HDL simulation, not Cyclesim black-box guessing.
- Runtime tests cover two-resource bundles, partial/no placement, collateral and
  stub mutation, unsupported physical gates and explicit 6/1 thread limits.
  Review found runtime resource/instance metadata could contradict the registered
  inventory after resealing. This was fixed in both OCaml and Python; **12 mismatch
  variants** now reject in both validators, while valid two-resource cases pass.
- Backend protocol **54 accepted / 943 rejected**, segment service **70 checks**,
  stage preparation **62 checks**, and targeted existing resource/flow tests passed.
- Full `dune runtest -j12` exposed stale six-stage expectations already present
  in the committed baseline. Four test files now explicitly require Timing between
  Routing and Signoff, seven ordered checkpoint publications and 25 lifecycle
  events. Their **81 tests** pass without changing production scheduling or weakening
  skip, resume, presentation or acceptance checks. A retained historical finalization
  fixture is unavailable on this machine; the suite reports that fact separately.
  After those test corrections, the final `dune runtest -j12` completed successfully.

All ASIC builds used the shared flock. Example refresh/builds used `-j6`; the
largest concurrent allocation was ASIC 12 plus isolated example 6 = **18**.
The actual synthesis route bounded tool workers at 6 and STA corners at 1.

### Installed public example synthesis

Final installed generation:
`hardcaml_asic_example/.dev/asic-sram/generations/aa00a92d707447fcba308789e57fa2f6`.
Observed source base: `bba13079abd519b984e522aa7e898cbef85f4139`.
Development worktree capture SHA-256:
`8f054fde7462a687139b31564fd823bedb4e0a0f1d7197ea813dcefee27214ca`.
This captures working bytes, not a newly committed/released dependency.

Bundle `program-memory-exact-c2` identity:
`4fe842a7c07b94ae9e8e0546210c9273d019fccdca2d5cbf84311948bde64d09`.
Public run `8b48d7d0818d494f8a9c45000c2bcbbd` completed with **exit 0**:

```sh
# Working directory: hardcaml_asic_example. Use this retained generation explicitly.
.dev/asic-sram/generations/aa00a92d707447fcba308789e57fa2f6/bin/hardcaml-asic-flow \
  run .dev/program-memory-exact-c2 --toolchain _flow_tools \
  --results-root _flow_results/sram --stage synthesis --json
```

The run's actual Yosys output retains **one**
`RM_IHPSG13_1P_256x16_c2_bm_bist` at **`hc_resource_7_program`**, plus the original
**16 staging flops**. Total mapped cells: **176**; unmapped cells, inferred latches
and synthesis-check errors: **0 each**. One lint warning is for deliberately
unused input bits. Final mapped RTL SHA-256:
`a12c6b63e21ed2ab2898bd7c41da3f6dfac768b53382538a7acfb96dd9918575`.

Reported synthesis area **2,182.7232 µm²** omits the SRAM black box. Macro Liberty
area is **28,127.104 µm²**; **30,309.8272 µm²** is their combined cell-area estimate,
not placed/routed area. The report omission is an important PT.5 resource-reporting
follow-up; do not compare this raw total to flop implementations as total chip area.

The actual technology-mapped netlist passed **1,280 word checks** and its corrupted
data oracle failed as intended. Icarus cannot execute the standard-cell model's
delayed timing-check reference signals, so replay uses a documented derived
zero-delay used-cell view preserving vendor logic/UDP calls, alongside stock SRAM
functional models. The original failed model invocation is retained. This is
gate-functional evidence, **not SDF simulation or timing-check conformance**.

Raw reports, configurations, netlists, model sources, exact source copies, provider
receipt, replay logs and checksums live in the
[example acceptance evidence](../../../hardcaml_asic_example/acceptance/sram/README.md).
Final snapshot `8b48d7d0-functional` verifies **37 files / 595,437 bytes**. The
earlier C1 attempt remains unchanged and independently verified; final netlist and
metrics are byte-identical after the runtime validator correction.

### Next agent-sized slice

1. **Physical backend:** implement placement-aware Metal4 supply construction and
   pin/grid validation from the actual pinned macro geometry. Preserve user
   architecture and include generated physical inputs in immutable closure.
2. **Checking integration:** execute the pinned CMOS5L KLayout deck on assembled
   real GDS, verify CDL use and extraction scope, and retain raw Magic/extraction
   diagnostics with explicit target-specific disposition. No blanket silent waiver.
3. **Example physical acceptance:** run the same public memory consumer through
   hardening, diagnose actual example electrical violations, and perform final
   netlist functional replay. Keep architectural register changes user-owned.

Timed-model conformance remains its own PT.1d obligation. The old probe is not the
acceptance target for these next items.
