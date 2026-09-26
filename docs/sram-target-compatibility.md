# SRAM target, submission, and power-source investigation

Status: bounded ASIC S.2b public-source research completed 2026-09-20; S.2b is
**partially resolved**. The exact competition target, its currently prescribed
mutable tool branches, the branches' observed revisions, required SRAM marker
support, and electrical voltage compatibility are established. Public sources do
not yet establish final submission eligibility for this exact macro, an immutable
submission tool pin, or authoritative permission to common `VDD!` and
`VDDARRAY!` onto the TT `VPWR` grid.

All web sources below were accessed 2026-09-20. No maintainer was contacted. No
toolchain checkout, lock, consumer file, or physical flow was changed or run.

## Verdict and decision table

The research task is complete rather than network-blocked. S.2b remains partly
open because the competition page says that a final submission form will be
published later and the available IHP SRAM documentation does not state a
common-supply or sequencing rule. These missing statements block a supported
submission claim, not an explicitly experimental S.3 probe.

| Question | Status and classification | Strongest authority and evidence | Remaining limitation |
| --- | --- | --- | --- |
| Exact-target macro eligibility | **Unresolved for submission; explicit target and SRAM encouragement, plus derived family applicability.** | Jane Street's 2026-09-10 [competition rules](https://blog.janestreet.com/protocol-emulator-asic-competition/) require IHP CMOS5L, the linked CMOS5L template, 6x4, and the March 2027 shuttle; they say, "For instruction memory, SRAM can be more area-efficient" and link an SRAM example. Pinned IHP [`ihp-common/README.md`](https://github.com/IHP-GmbH/IHP-Open-PDK/blob/2bbec755dc67ca3db0261c3d6163e15735d66710/ihp-common/README.md) says the SRAM cells are identical in SG13G2 and SG13CMOS5L. | The linked example is SG13G2. No checked competition, template, action, TT documentation, PR, or IHP document states that every PDK-distributed SRAM is accepted, lists approved macros, describes an approval procedure, or names this 256x16 macro. The rules' encouragement is not converted into exact-target permission by silence. |
| Official template/action/support-tools requirement | **Partially resolved; explicit mutable refs, no final immutable submission pin.** | The competition rules say "Start with" `ttihp-verilog-template` branch `cmos5l`. Its [workflow at observed commit `b86a2a...`](https://github.com/TinyTapeout/ttihp-verilog-template/blob/b86a2a781484bcab7ba522dc5de540086695a430/.github/workflows/gds.yaml) selects `tt-gds-action@ihp-cmos5l`; the [action at observed commit `341265...`](https://github.com/TinyTapeout/tt-gds-action/blob/3412659307918422f3f0727917cf9b499aaca588/action.yml) defaults `tools-ref` to `ihp-sg13cmos5l`, PDK `ihp-sg13cmos5l`, and LibreLane `3.1.0.dev3`. | All three refs are mutable branches. The competition page says the final submission form will be added later and publishes no immutable action/support-tools pin or acceptance-time resolution rule. |
| Required SRAM-marker support | **Resolved for technical precheck compatibility; explicit tooling requirement.** | TT PR [#187](https://github.com/TinyTapeout/tt-support-tools/pull/187), merged by Uri Shaked into the official Tiny Tapeout repository on 2026-09-17, states that `SRAM.drawing` and `DigiBnd.drawing` are used by the CMOS5L DRC deck and that omission rejects the macro or applies non-SRAM rules. Immutable commit [`cfa06bae...`](https://github.com/TinyTapeout/tt-support-tools/commit/cfa06bae536d00282cb2fdb3d0bdeebc562c6365) adds both to the valid-layer list. The observed official branch head `f6bf5c58...` contains that commit as its parent. | Marker acceptance is not macro authorization and does not prove DRC, LVS, timing, electrical qualification, or final acceptance. The currently locked `da63c992...` predates the fix and is incompatible with candidate marker layers. |
| `VDD`/`VDDARRAY` voltage and TT net connection | **Voltage-compatible by source-backed derivation; common-net acceptance unresolved.** | The pinned exact [datasheet](https://github.com/IHP-GmbH/IHP-Open-PDK/blob/2bbec755dc67ca3db0261c3d6163e15735d66710/ihp-sg13g2/libs.ref/sg13g2_sram/doc/RM_IHPSG13_1P_256x16_c2_bm_bist.txt#L193-L219) gives one 1.08-1.32 V operating range and 1.20 V typical corner. Exact [typical Liberty](https://github.com/IHP-GmbH/IHP-Open-PDK/blob/2bbec755dc67ca3db0261c3d6163e15735d66710/ihp-sg13g2/libs.ref/sg13g2_sram/lib/RM_IHPSG13_1P_256x16_c2_bm_bist_typ_1p20V_25C.lib#L25-L35) maps both `VDD` and `VDDARRAY` to 1.20 V; slow and fast do likewise at 1.08 V and 1.32 V. TT's [observed target code](https://github.com/TinyTapeout/tt-support-tools/blob/f6bf5c587fba4a4a8abd4c0a03234fccfbf6e61e/project.py#L483-L505) emits one `VPWR` and one `VGND`; observed [`tech.py`](https://github.com/TinyTapeout/tt-support-tools/blob/f6bf5c587fba4a4a8abd4c0a03234fccfbf6e61e/tech.py#L119-L161) selects `nom_typ_1p20V_25C`, and the [6x4 DEF](https://github.com/TinyTapeout/tt-support-tools/blob/f6bf5c587fba4a4a8abd4c0a03234fccfbf6e61e/tech/ihp-sg13cmos5l/def/tt_block_6x4_pgvdd.def) exposes only `VPWR`/`VGND`. | IHP calls the pins support-logic and array supplies but gives no separation, commoning, differential-voltage, or sequencing instruction found in the pinned public tree. TT provides no second 1.2 V user rail. Equal voltage characterization makes `VDD!`/`VDDARRAY! -> VPWR` electrically plausible, but public authority does not explicitly accept shorting the named rails. Physical PDN reachability is S.3. |
| Additional SRAM-specific submission/check obligations | **Marker preservation resolved; other SRAM-specific policy unresolved.** | The currently prescribed template workflow runs GDS build, TT precheck, gate-level test, and viewer jobs. The observed precheck runs CMOS5L KLayout DRC, top/boundary, pin, layer, and cell-name checks; its valid-layer list includes both SRAM markers. IHP's pinned [SRAM validator README](https://github.com/IHP-GmbH/IHP-Open-PDK/blob/2bbec755dc67ca3db0261c3d6163e15735d66710/ihp-sg13g2/libs.qa/sram/README.md) requires consistent CDL, documentation, GDS, LEF, Liberty, and Verilog packaging upstream and explicitly says this does not replace DRC, LVS, or silicon qualification. | No checked TT source defines an SRAM allowlist, SRAM-specific LVS abstraction/black-box rule, mandatory macro-view submission list, or permitted DRC/LVS exception. The public 1024x8 project's view set and extraction settings are technical precedent only. |

## Source findings

### Competition authority and scope

**Claim:** the selected target is the March 2027 IHP CMOS5L shuttle at 6x4.

- **Source:** Jane Street, [competition rules](https://blog.janestreet.com/protocol-emulator-asic-competition/), published 2026-09-10.
- **Text:** "We're targeting IHP's 130nm CMOS5L process"; "Start with the CMOS5L Verilog template"; "Set the tile size ... to 6x4"; and "March 2027 CMOS5L shuttle".
- **Authority/scope:** competition organizer; exact competition and intended shuttle.
- **Classification:** explicit requirement.
- **Reasoning:** this directly selects the target and current allocation. The page says 8x4 is only a possible later expansion, so it does not replace 6x4.

**Claim:** the rules contemplate SRAM but do not explicitly authorize this exact
PDK macro.

- **Source:** same dated competition rules.
- **Text:** "For instruction memory, SRAM can be more area-efficient than flip-flops" and a link to a Tiny Tapeout SRAM example "running on this process node".
- **Authority/scope:** competition organizer; design guidance for entrants.
- **Classification:** explicit encouragement/general technical guidance, not an exact-macro permission or allowlist.
- **Reasoning:** the link is to a fabricated SG13G2 example, while the selected target is CMOS5L. IHP's pinned common-library statement establishes that this candidate family is deliberately shared with CMOS5L, but neither source says that PDK inclusion alone guarantees shuttle acceptance.

**Claim:** final submission requirements are not yet complete publicly.

- **Source:** same dated competition rules.
- **Text:** "We'll add a final submission form to this page closer to the deadline!"
- **Authority/scope:** competition organizer; final competition intake.
- **Classification:** explicit unresolved future procedure.
- **Reasoning:** no immutable final submission revision can be inferred from a form that has not yet been published.

### Current official tool chain

The competition's official instruction is a branch, not a commit pin. Following
that branch on the access date produced this chain:

| Layer | Prescribed mutable ref | Observed commit on 2026-09-20 | Exact evidence |
| --- | --- | --- | --- |
| Template | `TinyTapeout/ttihp-verilog-template@cmos5l` | `b86a2a781484bcab7ba522dc5de540086695a430`, commit date 2026-06-24 | [Branch API](https://api.github.com/repos/TinyTapeout/ttihp-verilog-template/branches/cmos5l); workflow selects CMOS5L action, PDK, GDS, precheck, GL test, and viewer jobs |
| Action | `TinyTapeout/tt-gds-action@ihp-cmos5l` | `3412659307918422f3f0727917cf9b499aaca588`, commit date 2026-09-14 | [Branch API](https://api.github.com/repos/TinyTapeout/tt-gds-action/branches/ihp-cmos5l); action defaults support-tools branch and LibreLane version |
| Support tools | `TinyTapeout/tt-support-tools@ihp-sg13cmos5l` | `f6bf5c587fba4a4a8abd4c0a03234fccfbf6e61e`, commit date 2026-09-17 | [Branch API](https://api.github.com/repos/TinyTapeout/tt-support-tools/branches/ihp-sg13cmos5l); parent is marker fix `cfa06bae...` |
| PDK | installed by action at an immutable revision | `2bbec755dc67ca3db0261c3d6163e15735d66710` | [Action installer](https://github.com/TinyTapeout/tt-gds-action/blob/3412659307918422f3f0727917cf9b499aaca588/install_sg13cmos5l.sh) |
| LibreLane | action input default | `3.1.0.dev3` | [Action definition](https://github.com/TinyTapeout/tt-gds-action/blob/3412659307918422f3f0727917cf9b499aaca588/action.yml) |

These observations are reproducible historical facts, not permanent official
pins. The template and action branch heads happened to equal the existing local
locks on the access date. The support-tools branch had advanced two commits past
the project's `da63c992...` lock: marker commit `cfa06bae...`, then CI commit
`f6bf5c58...`. The current action checks out the branch at run time, so a future
run can resolve differently without a template change.

For a later experimental S.3 probe, freeze `f6bf5c58...` explicitly: it is the
observed official branch resolution, includes the marker fix, and retains the
same PDK and LibreLane selections. The minimal marker-compatible revision is
`cfa06bae...`. Neither is documented as the final competition submission pin,
and this investigation changes no lock.

### Marker and check requirements

TT PR #187 was authored by the public 1024x8 project owner, not by a TT
maintainer. Its test result is therefore technical precedent. The important
authoritative act is that Uri Shaked merged the change into Tiny Tapeout's
official target branch. The PR text states:

> The IHP SRAM macro includes SRAM.drawing and DigiBnd.drawing marker layers
> used by the SG13CMOS5L DRC deck. Without these layers, the macro is either
> rejected by the layer check or incorrectly checked under non-SRAM DRC rules.

The immutable merge commit modifies only `precheck/tech_data.py`. At observed
head `f6bf5c58...`, precheck both accepts those marker layers and runs the
CMOS5L KLayout DRC deck. Consequently, preserving the supplied marker geometry
through final GDS and using a support revision containing the change are
technical requirements for meaningful official precheck. Removing markers to
make the old layer check pass would select the wrong DRC treatment.

The current TT precheck does not prove everything needed for an SRAM backend. It
does not establish macro timing closure, supply current/IR drop, physical PDN
access, extraction correctness, LVS abstraction, or silicon qualification. The
IHP validator likewise limits itself to packaging, interface, and functional
model regressions and explicitly disclaims DRC, LVS, electrical
characterization, and silicon qualification.

### Power requirements and limits

The exact candidate's pinned IHP sources establish:

- Datasheet interface lines 103-105: `VDD` is the macro support-logic supply,
  `VDDARRAY` is the memory-array supply, and `VSS` is ground.
- Datasheet operating conditions lines 193-219: one documented operating range,
  1.08-1.32 V, with 1.20 V typical, 1.08 V slow, and 1.32 V fast corners.
- Exact [typical](https://github.com/IHP-GmbH/IHP-Open-PDK/blob/2bbec755dc67ca3db0261c3d6163e15735d66710/ihp-sg13g2/libs.ref/sg13g2_sram/lib/RM_IHPSG13_1P_256x16_c2_bm_bist_typ_1p20V_25C.lib), [slow](https://github.com/IHP-GmbH/IHP-Open-PDK/blob/2bbec755dc67ca3db0261c3d6163e15735d66710/ihp-sg13g2/libs.ref/sg13g2_sram/lib/RM_IHPSG13_1P_256x16_c2_bm_bist_slow_1p08V_125C.lib), and [fast](https://github.com/IHP-GmbH/IHP-Open-PDK/blob/2bbec755dc67ca3db0261c3d6163e15735d66710/ihp-sg13g2/libs.ref/sg13g2_sram/lib/RM_IHPSG13_1P_256x16_c2_bm_bist_fast_1p32V_m55C.lib) Liberty files, lines 25-35 and 127-138: both `VDD` and
  `VDDARRAY` are `primary_power` pins and receive equal voltage maps at every
  supplied corner; `VSS` is `primary_ground`.
- No checked pinned SRAM datasheet, Liberty, common README, or QA document
  specifies independent voltages, permits or forbids commoning, or defines a
  power-up/power-down sequence.

The observed official TT target sources establish:

- `project.py:create_user_config` emits `VDD_PIN: VPWR` and `GND_PIN: VGND`.
- `tech.py:IHPTech` selects nominal corner `nom_typ_1p20V_25C` and limits user
  routing to `Metal4`.
- The exact 6x4 DEF contains only the `VPWR` and `VGND` special nets; there is no
  second user 1.2 V array rail.
- The CMOS5L template disables multilayer PDN and configures a 2.1 um vertical
  PDN width. Those are project-grid constraints, not proof that either macro
  rail is physically reached.

Thus the electrical values align: both macro rails are characterized at the TT
target's nominal 1.20 V and across the same supplied corners. Logical mapping to
the sole positive user net is the only apparent topology, but the authoritative
sources stop short of saying that the two separately named rails may be
shorted. The public 1024x8 project maps both to `VPWR` and passed its recorded
flow/precheck jobs; that is useful precedent, not an IHP electrical rule or TT
acceptance policy for this candidate.

## Exact revisions and roles

| Revision | Role and conclusion |
| --- | --- |
| `2bbec755dc67ca3db0261c3d6163e15735d66710` | Existing project PDK baseline and immutable PDK revision installed by the observed official action; contains the exact candidate and shared CMOS5L SRAM exposure |
| `b86a2a781484bcab7ba522dc5de540086695a430` | Existing consumer template lock and observed `cmos5l` head; not prescribed immutably by the competition |
| `3412659307918422f3f0727917cf9b499aaca588` | Existing consumer action lock and observed `ihp-cmos5l` head; not prescribed immutably by the competition |
| `da63c9927411e3aca350977d653d24bbf5bca972` | Existing support-tools baseline; parent of marker fix and incompatible with unmodified candidate marker layers |
| `cfa06bae536d00282cb2fdb3d0bdeebc562c6365` | Official minimal marker-compatible support-tools commit; not a published submission pin |
| `f6bf5c587fba4a4a8abd4c0a03234fccfbf6e61e` | Observed `ihp-sg13cmos5l` head on 2026-09-20 and recommended exact experimental S.3 ref; includes `cfa06bae...`; not a permanent branch identity or final submission pin |
| `3.1.0.dev3` | Existing baseline and observed action default; experimental compatibility only until final submission requirements publish it or another version |

No official immutable revision was found for the final January 18, 2027
competition submission. The PDK installer is pinned, while template, action, and
support-tools selection remains branch-based.

## Outstanding authoritative questions

These are the smallest unresolved questions; no one was contacted.

1. **Macro eligibility:** Does the March 2027 Jane Street/Tiny Tapeout 6x4
   CMOS5L submission accept PDK-distributed SG13 SRAM macros, including
   `RM_IHPSG13_1P_256x16_c2_bm_bist`, without a separate allowlist or approval?
   Appropriate authority: Jane Street competition owner and Tiny Tapeout shuttle
   integration owner. Sources already checked: dated rules, linked example,
   template/action/support branches, TT PR #187, and pinned IHP docs. This blocks
   submission eligibility, not a local external S.3 experiment.
2. **Supply commoning:** Does IHP permit `VDD` and `VDDARRAY` of this macro to be
   tied to one 1.20 V source with no sequencing constraint, and does Tiny Tapeout
   accept both corresponding physical pins on the sole `VPWR` user grid?
   Appropriate authority: IHP SRAM collateral owner for the electrical half and
   Tiny Tapeout target owner for the harness half. Sources already checked: exact
   datasheet and Liberty corners, IHP common/QA docs, TT target code/DEF/template,
   issue searches, and public project precedent. This blocks supported power
   mapping and final acceptance; it does not block testing that mapping under an
   explicitly experimental S.3 flow.
3. **Final immutable tool requirement:** Will the final submission instructions
   freeze template/action/support-tools revisions, and must the support revision
   contain `cfa06bae...` or an equivalent marker rule?
   Appropriate authority: Jane Street competition owner and Tiny Tapeout
   submission owner. Sources already checked: competition page and complete
   branch chain. This blocks final reproducibility/acceptance, not physical
   experimentation with frozen `f6bf5c58...`.
4. **LVS/extraction treatment:** Is there a required TT SRAM-specific CDL/LVS
   abstraction or approved exception for PDK hard macros?
   Appropriate authority: Tiny Tapeout CMOS5L flow owner, informed by IHP macro
   views. Sources already checked: official workflow/precheck/action, IHP QA
   scope, and public project settings. This is primarily an S.3 physical-check
   and final-acceptance question; it should first be tested without inventing an
   exception.

## Handoffs

### P6.5 owner

There is no dependency from S.2b research or an experimental S.3 probe on P6.
When P6.5 unifies revision/provisioning authority, it must be able to record and
enforce an immutable support-tools revision containing `cfa06bae...` or an
equivalent marker fix. It must not treat mutable branch `ihp-sg13cmos5l` as an
immutable pin. The observed candidate for experiments is `f6bf5c58...`; final
adoption waits for submission instructions. No P6 implementation change is made
or requested here.

### S.3 owner

A minimal external probe may be prepared as **experimental**, not submission
ready, using exact PDK `2bbec755...`, exact candidate views/hashes from the S.1
record, LibreLane `3.1.0.dev3`, and frozen support-tools `f6bf5c58...`. Preserve
`SRAM.drawing` and `DigiBnd.drawing`; register GDS, LEF, all three Liberty
corners, synthesis/timing netlist, and CDL; place the macro explicitly; and test
the provisional mapping `VDD!`/`VDDARRAY! -> VPWR`, `VSS! -> VGND` without
claiming that it is approved.

The probe must separately report macro fit/placement, Metal4 obstruction and
pin access, PDN continuity to every rail, IR/current assumptions, routing,
timing at all registered corners, antenna/DRC, extraction/LVS behavior, TT
precheck, final-netlist simulation, marker preservation, and whether any
black-box or abstraction setting was necessary. Passing precheck alone is not
closure.

### Timing-model follow-up

S.2a's functional result remains valid and its limitation remains open. A
separate bounded task must run the exact non-`FUNCTIONAL` model under a simulator
that implements its `$setuphold` delayed signals and timing checks. Neither this
source research nor an S.3 physical pass establishes timed-model behavior.

## Next bounded task

Perform one consolidated authoritative clarification after the final submission
instructions are published, or through the already named Jane Street/Tiny
Tapeout authority channel if a gate decision is needed sooner: ask questions 1-3
verbatim and record the dated response. Existing evidence is sufficient to
prepare an S.3 probe in parallel under frozen `f6bf5c58...`, but clarification is
the smaller next task because it directly decides submission eligibility and the
accepted power mapping without consuming a physical-flow run.
