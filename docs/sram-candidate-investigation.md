# SRAM candidate investigation for TT 6x4 / IHP CMOS5L

Status: bounded ASIC S.1 inventory and preliminary S.2 / protemu P5.1a
evidence, 2026-09-20. This is not macro-backend or physical-integration
evidence.

## Executive conclusion

**Overall answer: unresolved, with a strong exact-shape candidate.** The pinned
IHP Open PDK contains the public, Apache-2.0-licensed
`RM_IHPSG13_1P_256x16_c2_bm_bist` hard macro. It is an exact 256-word by
16-bit, one-port candidate for protemu's current program store, and the pinned
checkout contains documentation, functional/timing Verilog, three Liberty
corners, LEF, GDS, and CDL. Its documented and modeled behavior appears
adaptable to the normative `Single_port_ram` contract with a small fixed-control
wrapper: tie `A_DLY` and all `A_BM` bits high, keep BIST disabled, and derive
the macro's separate active-high memory/read/write enables from the contract's
`enable` and `write_enable`.

That is candidate discovery, not established support. In particular:

- the exact pinned `tt-support-tools` revision rejects the macro's
  `SRAM.drawing` and `DigiBnd.drawing` marker layers during precheck;
- the immediate child commit on Tiny Tapeout's official CMOS5L branch adds
  those two layers, after a public 1024x8 CMOS5L SRAM project reported successful
  GDS, full TT precheck, gate-level test, and viewer jobs;
- no source found says that this exact 256x16 macro is approved for the selected
  March 2027 shuttle, and no authoritative submission policy was found that
  turns the merged tooling change into shuttle permission;
- the exact 256x16 model has not been run through the library conformance suite,
  and its views, dual supply connection, PDN, placement, LVS/black-box handling,
  and checks have not been exercised in this project's pinned flow.

The correct current conclusion is therefore: **an accessible, exact-process,
exact-shape candidate exists and merits model checks, but it is not usable with
the exact pinned TT support revision and is not yet a supported backend.**

## Search scope and revisions

### Project inputs

The following current files were inspected before searching collateral:

- `toolchain.lock`, `docs/phase_plan.md` S.1-S.4,
  `docs/program-memory-contract.md`, and `docs/target-reference.md` here;
- `../scaf/tinytapeout/toolchain.lock`,
  `../scaf/tinytapeout/asic-dependencies.lock`, and
  `../scaf/docs/phase_plan.md` P5.1/P5.1a;
- the older negative investigation in `program-memory-contract.md` section 8,
  which explicitly said that no PDK checkout had then been inspected.

No `AGENTS.md` exists in either local repository. Both project worktrees had
unrelated concurrent changes; none were modified by this investigation.

All three current lockfiles still agree on:

| Input | Locked revision/version |
| --- | --- |
| IHP Open PDK | `2bbec755dc67ca3db0261c3d6163e15735d66710` |
| Tiny Tapeout support tools | `da63c9927411e3aca350977d653d24bbf5bca972` |
| LibreLane | `3.1.0.dev3` |
| Target | `ihp-sg13cmos5l`, TT `6x4` |

### Installed collateral

The primary inspected installation was this repository's provisioned
`.toolchain`:

| Checkout | Location | Observed state |
| --- | --- | --- |
| IHP Open PDK | `.toolchain/pdk` | exact locked revision; clean; origin `https://github.com/IHP-GmbH/IHP-Open-PDK.git` |
| TT support tools | `.toolchain/tt` | exact locked revision; clean; origin `https://github.com/TinyTapeout/tt-support-tools.git` |
| LibreLane | `.toolchain/.venv` | provisioned package path for the locked `3.1.0.dev3` flow |

The independently provisioned protemu copies at `../scaf/tinytapeout/pdk` and
`../scaf/tinytapeout/tt` have the same two revisions. Its support-tools checkout
is clean. Its PDK checkout has one untracked generated identification file,
`ihp-sg13cmos5l/SOURCES`, containing the locked PDK revision; no tracked PDK
file is modified.

Searches began under `ihp-sg13cmos5l` and `tech/ihp-sg13cmos5l`, then broadened
only within those installed repositories. The relevant process path
`ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram` is a **tracked relative symlink** to
`../../ihp-sg13g2/libs.ref/sg13g2_sram`; it is not generated or a dangling
reference. This is not an inference from SG13G2 naming: the pinned IHP
repository's `ihp-common/README.md` explicitly states that its SRAM cells are
identical in SG13G2 and SG13CMOS5L. The linked target contains 30 macros and 244
tracked deliverable files: 30 each of CDL, documentation, GDS, and LEF, 90
Liberty files (three per macro), and 34 Verilog files including shared models.

The CMOS5L PDK-level LibreLane configuration names only standard-cell and I/O
views; it does not register the SRAM. Conversely, LibreLane `3.1.0.dev3`
supports a structured `MACROS` object with GDS, LEF, Liberty, netlist, SPICE,
and instance placement fields. This establishes representability only.

## Candidate inventory

### Candidate table

| Candidate | Exact process status | Shape/ports | Availability | Assessment |
| --- | --- | --- | --- | --- |
| `RM_IHPSG13_1P_256x16_c2_bm_bist` | Exposed by the tracked `sg13cmos5l_sram` symlink; IHP says the SRAM data is identical for SG13G2 and SG13CMOS5L | 256x16, one port, column mux 2 | Present locally and publicly downloadable at the locked PDK revision; Apache-2.0 | Strongest candidate: exact protemu shape and potentially contract-compatible; target/flow support unresolved |
| `RM_IHPSG13_1P_64x16_c2` | Same CMOS5L exposure | 64x16, one port, column mux 2 | Same complete public view set | Potential candidate only for an explicitly selected 64x16 resource; not a replacement for 256x16 |
| Other `RM_IHPSG13_1P_*` macros | Same CMOS5L exposure | 64x64; 256x8/32/48/64; 512x8/16/32/64; 1024x8/16/32/64; 2048x32/64; 4096x8/16; 8192x32 | Same view classes and three Liberty corners are present for each | Candidates only for their exact declared shapes; no rounding, composition, or reinterpretation is justified |
| Ten `RM_IHPSG13_2P_*` macros | Same CMOS5L exposure | Various 64-1024 word shapes, two ports | Same view classes present | Not selected: an exact one-port 256x16 macro exists, and unused extra-port behavior/integration would add needless obligations |

The candidate name is not being used to infer behavior. The facts below come
from its datasheet, Verilog model, Liberty, LEF, GDS/CDL inventory, and the PDK's
cross-view validator documentation.

### Exact 256x16 interface and behavior

| Property | Evidence-backed finding |
| --- | --- |
| Organization | 256 words x 16 bits, one port, eight address bits |
| Clock/read latency | Inputs are positive-edge sampled; documentation says "one-cycle data-access"; Liberty models `A_DOUT` as `memory_read()` with a rising-edge `A_CLK` arc |
| Enables | Active-high `A_MEN`, `A_REN`, and `A_WEN`; read is `MEN=1, REN=1, WEN=0`; write is `MEN=1, REN=0, WEN=1`; both high requests write-through |
| Write mask | `A_BM[15:0]`, active high per bit. Tying all bits high implements whole-word writes |
| Disabled/no-operation output | The shared behavioral model updates its output register only on a read or write-through. `MEN=0`, `MEN=1/REN=0/WEN=0`, and plain writes leave it unchanged. Thus contract disable can hold; holding during a write is allowed because the contract leaves that result unspecified |
| Collision behavior | `REN=WEN=1` is documented and modeled as write-through. A contract wrapper must never request it; the portable contract has no simultaneous read/write operation |
| Initialization/reset | No reset or initialization exists in the interface or model. Verilog memory and output registers have no initial assignment. Power-up and unwritten values are therefore not guaranteed, as required |
| Delay control | `A_DLY` must remain tied high; the supplied simulation model checks this at time zero and on changes |
| BIST | Separate active-high BIST select, clock, enables, address, data, and masks. Keep `A_BIST_EN=0` permanently and tie unused BIST controls/data to stable values. The datasheet forbids access for one cycle before/after changing BIST mode; a fixed zero select avoids mode changes |
| Supplies | Datasheet: `VDD` support logic, `VDDARRAY` array supply, `VSS` ground. LEF/CDL names are `VDD!`, `VDDARRAY!`, `VSS!`; Liberty names are `VDD`, `VDDARRAY`, `VSS`. Documented operating range is 1.08-1.32 V, nominal 1.20 V |
| Physical size/layers | 236.80 x 118.78 um = 28,127.10 um2; macro metal use through M4. LEF signal pins are on Metal2 and repeated supply rails are on Metal4. GDS also carries CMOS5L SRAM/DigiBnd marker layers |
| Timing views | Typical 1.20 V/25 C, fast 1.32 V/-55 C, slow 1.08 V/125 C. Datasheet clock-to-output at those corners is approximately 3.02/1.86/5.06 ns rising and 2.95/1.82/4.94 ns falling |
| License | Repository and individual generated views state Apache License 2.0; the collateral is public, not access-restricted |

The 64x16 candidate has the same active-high one-port control structure,
one-cycle access, hold-producing registered model, supplies, operating range,
and three-corner view classes, but no bit-mask or BIST ports. It measures
236.80 x 64.36 um (15,240.45 um2). It could back only an explicitly requested
64x16 resource.

## Collateral availability

For the strongest candidate at the locked PDK revision:

| Collateral | Availability | Notes |
| --- | --- | --- |
| Datasheet | Present, tracked through the CMOS5L symlink | Interface, operations, timing, supplies, dimensions, and layers |
| Functional simulation | Present | Macro wrapper plus shared `SRAM_1P_behavioral_bm_bist`; `FUNCTIONAL` selects untimed behavior |
| Timing simulation | Present | Same macro wrapper has specify timing checks/arcs when `FUNCTIONAL` is absent |
| Liberty | Present | Typical, fast, and slow files; macro area, PG pins, read/write groups, and clock arcs |
| LEF | Present | Block outline, all signal/BIST pins, Metal4 supply rails, and obstructions |
| GDS | Present | Top-level hard-macro layout; the PDK validator checks top name and labels when run for SG13G2 |
| CDL | Present | Transistor-level hierarchy and top-level signal/power interface |
| SPICE/SPEF/SDF | No separate files found | CDL is the supplied circuit view; Liberty supplies timing. Whether this is sufficient for the exact LibreLane/LVS path remains an integration question |
| PDK registration | Not present | CMOS5L `libs.tech/librelane/config.tcl` does not add SRAM views automatically |
| Tiny Tapeout registration | Not present | `cells.json` lists standard cells only and generated project configuration does not introduce this macro |

The PDK's SRAM QA documentation says its validator checks every macro across
CDL, documentation, GDS, LEF, three Liberty corners, and Verilog, including
names, ports, widths, GDS labels, compile checks, and a 64x16 functional smoke
test. At this locked revision that validator lives under SG13G2; CMOS5L exposes
the same data by symlink but has no `libs.qa/sram` entry, so this is upstream
packaging evidence rather than a recorded CMOS5L validator run. It explicitly
does not establish electrical characterization, DRC, LVS, or silicon
qualification.

Representative SHA-256 values from the inspected checkout, useful for detecting
accidental collateral drift, are:

| View | SHA-256 |
| --- | --- |
| Datasheet | `92b32189ff35af75e096e3faf8f85df9fe572f207d5f97405cc0ddf20ec2a609` |
| Macro Verilog | `645c475787b077da4dbd15856c68bbae46aa9846a155239eb895ed2de7511053` |
| Shared functional model | `d0a6258f8e9c93d1d5b1f78c0a1d66f30d28b1ad8037e5e07f53d1a4e3670b12` |
| LEF | `bea0d602296a03ea2020420501767ff321f53186d7444ea0faefa4d49dac047b` |
| GDS | `763ddd53d812e0400c2cb89af192a0000d7b3f27e049de93aef41a2be9b547c6` |
| CDL | `f7918bfd22caa5b317bd2222adbdf700588e93c9c55a131a753fa6227abb2c53` |
| Typical Liberty | `6f4cca1ed508f879a35bdc15a9de2d027f81ec0eeec0d6c8ab27d05f5edad445` |

## Contract compatibility

Assessment against `docs/program-memory-contract.md`, without treating
candidate discovery as backend conformance:

| Contract requirement | Classification | Required mapping or missing evidence |
| --- | --- | --- |
| Exact 256x16 shape | **Confirmed compatible** | Exact depth, width, and eight-bit address; no rounding/composition |
| One shared 1RW port | **Potentially adaptable** | Use the one physical port. Drive `A_MEN=enable`, `A_WEN=enable && write_enable`, and `A_REN=enable && !write_enable`; never request write-through |
| Positive-edge, one-cycle read | **Confirmed compatible** | Datasheet, functional model, and Liberty agree |
| Whole-word writes | **Potentially adaptable** | Tie all `A_BM` bits high; do not expose masking in the portable interface |
| Disabled-output hold | **Confirmed compatible in supplied model** | Output register is not assigned on no-operation cycles. A model conformance run must still check four-state stability and timing-model behavior |
| Output after write unspecified | **Confirmed compatible** | Plain write holds the prior macro output, which is one permitted unspecified result; wrapper/tests must not require poison or any other value |
| No simultaneous read/write promise | **Confirmed compatible with wrapper restriction** | Candidate offers write-through, but the wrapper mapping never asserts both controls |
| No initialization/reset guarantee | **Confirmed compatible** | No reset or initial assignment is supplied; consumer validity remains external |
| Out-of-range behavior unspecified | **Confirmed compatible** | Depth is exactly 256, so all eight-bit addresses are in range for this exact mapping |
| Single clock domain | **Potentially adaptable** | Main port uses the contract clock; BIST clock/control must be statically tied off |
| Portable interface has no power/BIST/DLY pins | **Potentially adaptable** | Backend-owned wrapper/collateral must tie `A_DLY`, mask, and BIST pins and map physical supplies without changing `Single_port_ram` |

No model was executed in this task. Therefore preliminary compatibility is
enough to justify S.2 model work, not enough to complete S.2 or claim backend
conformance.

## Tiny Tapeout permission and flow findings

### Technically representable

LibreLane `3.1.0.dev3` has a typed `MACROS` configuration object requiring GDS
and LEF and accepting Liberty, Verilog netlist, SPICE, and placed instances. A
public CMOS5L TT-template project at commit
`48161be82bfd1f38deb9ac35a500d60c96444a63` used that mechanism for
`RM_IHPSG13_1P_1024x8_c2_bm_bist`, with three Liberty corners, LEF, GDS, CDL,
netlist, fixed placement, and two PDN connections mapping both `VDD!` and
`VDDARRAY!` to `VPWR` and `VSS!` to `VGND`. Its 2026-09-17 GitHub Actions run
`35163996266` reports successful GDS, precheck, gate-level test, and viewer jobs;
its `info.yaml` selects the same 6x4 competition allocation.

This is useful preliminary flow evidence for the same macro family, process,
and TT CMOS5L target. It is not evidence for this exact macro or pinned
collateral combination: the example's macro README cites IHP revision
`7c124b7324778fbc2261aa8529ba04388eb3339e`, not this project's PDK pin. The
example also required explicit macro placement and PDN configuration, and its
precheck job selected a temporary support-tools fork carrying the marker-layer
fix before that fix was merged upstream.

### Exact pinned-target blocker

At locked support-tools revision `da63c992...`,
`valid_layers_ihp_sg13cmos5l` omits `SRAM.drawing` and `DigiBnd.drawing`, while
the layer check rejects every GDS layer outside that list. Tiny Tapeout PR
[#187](https://github.com/TinyTapeout/tt-support-tools/pull/187) states that the
IHP SRAM contains those marker layers and that omitting them either rejects the
macro or checks it under the wrong non-SRAM DRC rules. The PR's only code change
adds those names.

Tiny Tapeout merged that change as
[`cfa06bae`](https://github.com/TinyTapeout/tt-support-tools/commit/cfa06bae536d00282cb2fdb3d0bdeebc562c6365)
on 2026-09-17. Crucially, its parent is the project's exact locked revision
`da63c992...`. Thus the currently pinned target is not merely untested: its own
precheck list is **confirmed incompatible** with the candidate GDS marker
layers. This investigation does not change the pin.

### Permission evidence and limit

The 2026-09-10 competition rules select the CMOS5L TT template and 6x4 target,
say SRAM can be more area-efficient than flip-flops, and direct entrants to an
older Tiny Tapeout SRAM example. That linked fabricated example is SG13G2, not
CMOS5L, so it demonstrates Tiny Tapeout's general macro precedent but not
CMOS5L compatibility. More directly, an official Tiny Tapeout maintainer merged
PR #187 specifically to allow the CMOS5L SRAM marker layers after the public
CMOS5L macro project passed precheck. This is strong evidence that SRAM is
intended to be technically accepted by the CMOS5L tooling.

It is still not a shuttle authorization statement. The precise authoritative
question remaining for Jane Street/Tiny Tapeout is:

> For the March 2027 Jane Street 6x4 `ihp-sg13cmos5l` target, may a user design
> include the PDK-distributed `RM_IHPSG13_1P_256x16_c2_bm_bist` GDS/LEF/CDL and
> connect both 1.2 V supplies to the TT user power grid, and which official
> support-tools/action revision must submissions use now that SRAM marker-layer
> support was merged immediately after our locked revision?

Until that answer or an updated authoritative competition pin exists, classify
permission as **promising but unresolved**. PDK licensing and precheck support
do not by themselves grant a slot on a selected shuttle.

## Confirmed facts and unknowns

### Confirmed

- The locked PDK is locally installed and clean at the expected revision.
- CMOS5L deliberately exposes the shared IHP SRAM library through a tracked
  symlink, and upstream explicitly says the SRAM data is identical across the
  two process directories.
- An exact 256x16 one-port macro with a complete public cross-view set exists.
- Its supplied functional behavior can represent the contract's defined
  latency, whole-word operation, and disabled-output hold with fixed tie-offs
  and simple enable decoding.
- LibreLane can represent the views, and another public CMOS5L TT project has
  integrated a different one-port macro from the same family through GDS and
  TT precheck.
- The exact pinned TT precheck lacks two required marker layers. Official TT
  support for those layers was merged in the immediate child commit.
- `hardcaml_asic` currently has no macro resource mapping, its adapter rejects
  macro selections, and raw `MACROS` overrides are intentionally rejected.

### Unknown or not established

- Authoritative permission for this exact macro and the March 2027 competition
  shuttle.
- Whether the official competition pins will advance to include TT commit
  `cfa06bae` or equivalent; changing dependency pins is a separate decision.
- Exact-model conformance under the library's scoreboard, including four-state
  disabled hold, write-cycle unspecified output, and timed model compilation.
- Whether tying both `VDD!` and `VDDARRAY!` to `VPWR` is the required and
  accepted power implementation for this target, rather than merely one public
  project's solution.
- Correct macro placement, PDN access, routing obstruction handling, timing,
  antenna/DRC/LVS behavior, and fit with the rest of protemu in the 6x4 tile.
- Whether CDL alone is accepted by the pinned LVS path and which abstraction or
  black-box settings are required. No separate SPEF/SDF or SRAM SPICE file was
  found.
- Electrical/silicon qualification. The PDK validator itself disclaims this.

## Recommended next task

Proceed with a **bounded S.2 behavioral-model check plus authoritative pin/use
clarification**, not S.3 physical integration and not S.4 backend work:

1. Run the existing RAM contract vectors against only the supplied
   `RM_IHPSG13_1P_256x16_c2_bm_bist` functional model through a temporary test
   wrapper with the tie-offs above. Check defined reads and disabled hold within
   the four-state model; do not require a value after writes or from unwritten
   locations. Record compiler command, model hashes, and results without adding
   a technology mapping.
2. Obtain the authoritative answer to the quoted shuttle/pin/power question.
   Existing public evidence may answer it if the competition updates its lock
   or instructions; do not infer permission from the PDK or contact anyone as
   part of this task.
3. Only if both succeed, define a separate S.3 minimal external flow experiment
   for this exact 256x16 candidate, including all views, both supply rails,
   explicit placement/PDN, timing corners, extraction/LVS policy, and the
   official post-`cfa06bae` precheck. Do not begin the library backend first.

Status justified now: ASIC S.1 may be marked complete with this inventory;
ASIC S.2 remains in progress/open pending model checks and authoritative target
permission; S.3 and S.4 remain open. Protemu P5.1a remains open but should link
this as a candidate-found, capability-gate-unresolved record rather than an
unavailable decision.

## Source references

- Locked IHP PDK repository and revision:
  <https://github.com/IHP-GmbH/IHP-Open-PDK/tree/2bbec755dc67ca3db0261c3d6163e15735d66710>
- Pinned declaration that SRAM data is shared by SG13G2 and SG13CMOS5L:
  <https://github.com/IHP-GmbH/IHP-Open-PDK/blob/2bbec755dc67ca3db0261c3d6163e15735d66710/ihp-common/README.md>
- Pinned CMOS5L SRAM symlink target:
  <https://github.com/IHP-GmbH/IHP-Open-PDK/blob/2bbec755dc67ca3db0261c3d6163e15735d66710/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram>
- Exact candidate datasheet:
  <https://github.com/IHP-GmbH/IHP-Open-PDK/blob/2bbec755dc67ca3db0261c3d6163e15735d66710/ihp-sg13g2/libs.ref/sg13g2_sram/doc/RM_IHPSG13_1P_256x16_c2_bm_bist.txt>
- Exact candidate Verilog and shared functional model:
  <https://github.com/IHP-GmbH/IHP-Open-PDK/blob/2bbec755dc67ca3db0261c3d6163e15735d66710/ihp-sg13g2/libs.ref/sg13g2_sram/verilog/RM_IHPSG13_1P_256x16_c2_bm_bist.v>
  and
  <https://github.com/IHP-GmbH/IHP-Open-PDK/blob/2bbec755dc67ca3db0261c3d6163e15735d66710/ihp-sg13g2/libs.ref/sg13g2_sram/verilog/RM_IHPSG13_1P_core_behavioral_bm_bist.v>
- PDK SRAM validation scope:
  <https://github.com/IHP-GmbH/IHP-Open-PDK/blob/2bbec755dc67ca3db0261c3d6163e15735d66710/ihp-sg13g2/libs.qa/sram/README.md>
- Locked TT support tools:
  <https://github.com/TinyTapeout/tt-support-tools/tree/da63c9927411e3aca350977d653d24bbf5bca972>
- Official TT SRAM-layer change, merged 2026-09-17:
  <https://github.com/TinyTapeout/tt-support-tools/pull/187> and
  <https://github.com/TinyTapeout/tt-support-tools/commit/cfa06bae536d00282cb2fdb3d0bdeebc562c6365>
- Public CMOS5L 1024x8 integration evidence at commit `48161be...` and Actions
  run `35163996266`:
  <https://github.com/WilliamZhang20/protocol-emulator/tree/48161be82bfd1f38deb9ac35a500d60c96444a63>
  and
  <https://github.com/WilliamZhang20/protocol-emulator/actions/runs/35163996266>
- Jane Street competition rules, published 2026-09-10:
  <https://blog.janestreet.com/protocol-emulator-asic-competition/>
- The rules' older SG13G2 Tiny Tapeout SRAM example (not CMOS5L evidence):
  <https://www.tinytapeout.com/chips/ttihp0p2/tt_um_urish_sram_test>
