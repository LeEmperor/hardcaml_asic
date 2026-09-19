# Handoff: a TT/CMOS5L template module

Short brief for a session that will build the thing, not decide whether to.
The decision and its reasoning are in the consumer's
[`tooling theory 1`](../../scaf/docs/tooling_theory1.md); read that first if
the boundary itself is in question.

## The problem, in one measurement

The 20 raw LibreLane overrides in `examples/tt_bundle_example.ml` and the 20 in
protemu's `scaf/bin/asic_bundle.ml` are the same 20, with the same values, both
citing TT CMOS5L template commit `b86a2a7` in their `reason`. Two copies, and
there is only one real consumer so far. The third copy gets written the day a
second design starts.

The same file shows the other half of it. protemu's declaration is 208 lines,
of which roughly half is transcription rather than decision:

- ~30 lines of `module I` / `module O` — `ui_in, uio_in, ena, clk, rst_n` in,
  `uo_out, uio_out, uio_oe` out. Fixed by Tiny Tapeout. Identical in every TT
  design that will ever exist, and already enforced by
  `Resolved_build.validate_interface`, which knows these ports.
- ~24 lines of the override list above.
- ~35 lines of `Design.create` reset-synchroniser and pad-gating on
  `rst_n & ena` — the TT wrapper idiom, with a design-specific core in the
  middle.

The genuinely per-design parts are metadata, pin descriptions, clock period,
I/O delays, resource policy, `input_paths`, and the core instantiation.

## What to build

A library module — `Tt_cmos5l` or similar, beside `flow.ml` / `harness.ml` /
`target.ml` — that supplies:

1. **The template overrides as library-owned defaults**, carrying the template
   revision in their `reason` so provenance survives. A consumer overrides
   these rather than retyping them.
2. **The fixed TT wrapper I/O**, so a design declares its ports by using the
   library's interface rather than restating it.

Optionally, if it falls out cleanly, the reset-sync/pad-gating idiom as
something a design can opt into. Do not force it: a design that wants different
reset behaviour must still be able to write its own.

## Constraints

- **Do not weaken the `reason` discipline.** Every override still carries one.
  Library defaults carry the template revision; a consumer override carries the
  consumer's justification. The point of the change is that `reason` stops
  being a copied string and starts meaning something.
- **Protected settings stay protected.** `CLOCK_PERIOD`, `VERILOG_FILES` and
  `DIE_AREA` are derived from the declaration and must still be refused as
  overrides. protemu's `asic_bundle.ml --check-conflicts` asserts exactly this
  and must still pass.
- **Defaults must be overridable and visible.** A consumer has to be able to
  see what it is getting and change one entry without abandoning the rest.

## Acceptance

The sharp test, because it separates the two things that could change:

1. Rewrite protemu's `bin/asic_bundle.ml` against the new module. It should
   land near 90 lines, and every surviving line should be a decision about that
   chip.
2. Re-emit the bundle. **The emitted files must be byte-identical** —
   `src/config.json`, `constraints/top.sdc`, `info.yaml`, and the RTL. If
   `config.json` changes, the defaults are not the same defaults.
3. The bundle `identity` *will* change, and that is correct: `asic_bundle.ml`
   is a declared source input, so its hash moves. Confirm the change is
   confined to `source_inputs`, not to `generated_settings` or
   `resolved_settings`.
4. `--check-conflicts` still passes.

Reference point: the current adopted bundle is identity
`5edf30f980c96bdd67aa0b32d1aed806eee1994bb1e1164c2adb8a93504d308f`, archived
with its emitted config at
`scaf/flow_results/20260918-230920-05f65042/`. Unpack `reports.tar.gz` for the
`project/src/config.json` the flow actually consumed.

## One decision to make, not inherit

`RUN_KLAYOUT_DRC = 0` and `RUN_KLAYOUT_XOR = 0` are in the copied template.
Their effect on the 2026-09-18 run: LibreLane recorded no
`klayout__drc_error__count`, so `collect` had no KLayout metric, and step 72
warned about it. The layout is still covered — TT precheck runs the KLayout
decks against the final GDS afterwards and reported zero items — but the
coverage comes from precheck rather than the flow.

Turning it on costs about eight minutes (the same deck took 478.64s in
precheck on the same GDS) and duplicates what precheck already does. That is a
real trade, and moving these into a library default is the moment to make it
deliberately rather than inherit it. Whichever way it goes, the `reason` should
say why, not just name a template.

## What to hand back

The consumer cannot adopt this from a commit hash alone. A return context
should carry the following, and should state a fact for each rather than
leaving it to be inferred from the diff.

**Blocking**

1. **The new `asic_revision`.** protemu pins
   `414b7f4f92a201bd9bceb6864579dc3ee475101f` in
   `scaf/tinytapeout/asic-dependencies.lock`; nothing else here is usable until
   that is a commit the consumer can install from.
2. **The API surface, written out.** The module's name and location; how
   defaults are obtained; how a consumer overrides exactly one of them without
   restating the rest; how the fixed TT I/O is consumed (functor, `include`, or
   a module type to satisfy), since that decides whether `module I` / `module
   O` disappear from the declaration or merely shrink; and whether any of
   `Project.create`'s nine labelled arguments changed name or type.

**Behaviour that changes the physical run**

3. **A byte-level verdict on the emitted configuration**, not a claim of
   equivalence. Diff against the archived reference:
   `scaf/flow_results/20260918-230920-05f65042/reports.tar.gz` →
   `project/src/config.json`. Say what was diffed and what came back.
4. **The `RUN_KLAYOUT_DRC` / `RUN_KLAYOUT_XOR` decision and its new `reason`.**
   Flipping either to `1` lengthens a full flow by roughly eight minutes and
   makes `collect` start finding `klayout__drc_error__count`, which is a
   results-schema change on the consumer side, not only a timing one.
5. **Every default whose value moved, with a reason each.** A changed
   `PL_TARGET_DENSITY_PCT` or `FP_PDN_*` is a different chip, not a refactor.

**Coupling surfaces, because the consumer vendors the Python**

6. **Whether the manifest schema moved.** protemu's `adopted_phase4.py` reads
   `files`, `identity`, `requested_tools`, `target` and `top_module`;
   its `check-adopted-bundle.py` reads those plus `project`, `source_revision`,
   `source_inputs`, `synthesis_sources` and `simulation_sources`. A rename or
   renesting among them means re-vendoring, not re-pinning. `schema_version` is
   `1` today; a bump is the signal.
7. **Whether `phase4.py`, `report.py` or `archive.py` changed.** If so the
   consumer re-vendors all three and re-applies its deltas (79, 11 and 27 lines
   respectively). Only the `adopted_phase4.py` delta is a real local choice —
   it substitutes protemu's own `tb.v`.
8. **Whether the conflict diagnostics were reworded.** protemu's
   `asic_bundle.ml --check-conflicts` asserts that `CLOCK_PERIOD`,
   `VERILOG_FILES` and `DIE_AREA` are refused *and that the message names the
   key*; `check-adopted-bundle.py` separately greps for `CLOCK_PERIOD` and
   `VERILOG_FILES`. Rewording breaks both.

**Not required, but worth stating if true:** that the library's own
`examples/tt_bundle_example.ml` was moved onto the new module too. If the
example still carries its own copy of the twenty overrides, the duplication
this work exists to remove has only been halved.

## Files to read

- `scaf/bin/asic_bundle.ml` — the consumer declaration being shrunk
- `examples/tt_bundle_example.ml` — the library's copy of the same overrides
- `lib/flow.ml` — `Override.t` and the protected-setting machinery
- `lib/resolved_build.ml` — TT wrapper ports and interface validation
- `lib/target.mli`, `lib/technology.mli` — where CMOS5L already lives

## Why now

This is P5.5's groundwork: "document a minimal declaration" is hard to do
honestly while half the minimal declaration is a copied template. It is also
what makes the second consumer cheap, which is the point at which the
duplication stops being theoretical.
