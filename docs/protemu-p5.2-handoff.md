# Protemu handoff: adopt `hardcaml_asic` (ASIC P5.2 / protemu P0.6)

## What is available now

`hardcaml_asic` is an installable OCaml/Dune package (`0.1.0`, library name
`hardcaml_asic`). An independent project can pin a library commit and use
`(libraries hardcaml_asic)` without a sibling checkout. See the
[consumer installation guide](consumer-installation.md) for the pin and the
matching external toolchain revision.

- `Project.create` declares a design, metadata, TT pin meanings, a primary
  clock, optional I/O delays, resource policy, and LibreLane flow settings.
  `Project.elaborate ~mode:Simulation` builds behavioral RTL;
  `Project.elaborate_for_flow` validates an implementation build for the
  supported Tiny Tapeout `6x4` / IHP CMOS5L target. Each elaboration has a
  fresh `Elaboration_context` and produces an immutable build.
- `Bundle.render` and `Bundle.write` emit generated synthesis RTL, optional
  separate simulation RTL, `info.yaml`, `src/config.json`, `constraints/top.sdc`,
  copied source inputs, and a content-hashed `manifest.json`. The bundle does
  not run EDA tools. Target, clock, source list, and protected LibreLane settings
  are validated as one configuration; other overrides require a reason.
- `Single_port_ram` provides registered 1RW, whole-word memory with a
  diagnostic simulation model and explicitly selected synthesizable flops.
  There is no CMOS5L SRAM macro backend yet. External preflight, LibreLane
  execution, result collection, and postchecks can consume an emitted bundle.

The working [TT bundle example](../examples/tt_bundle_example.ml) shows the
declaration and emission calls. The [bundle guide](bundle-emission.md) describes
the files; the [target reference](target-reference.md) lists the validated TT
interface and configuration ownership.

## The first consumer test

Adopt the library in protemu's **current observable top and protemu-owned TT
wrapper** (protemu P0.6), keeping the hardware modules ordinary Hardcaml.
Use a `Project.Design` at the top, declare the TT `6x4` / CMOS5L target, real
clock and pin meanings, metadata, a resource policy, and only reasoned
LibreLane overrides. Pin the package and matching collateral revisions in
protemu's own dependency record. Have protemu emit the bundle from its own
repository and enumerate its own source inputs; the old `tinytapeout/`
configuration should cease to be a second authority for this path.

**What we want to learn:** can a separate, real design use `hardcaml_asic` as
the source of truth for ASIC build inputs and still pass its existing wrapper
behavior? The acceptance evidence is:

1. A clean independent build and repeatable emission of the same bundle and
   manifest identity from the same protemu inputs.
2. A validated TT top interface, generated metadata/SDC/LibreLane config,
   separate simulation and synthesis source sets, and a manifest that records
   the actual protemu inputs and dependency revisions.
3. The existing protemu wrapper regression rerun against emitted RTL, plus
   checks that conflicting clock, source-list, or target-owned overrides fail
   with useful diagnostics.

This is the library's ASIC P5.2 evidence and protemu's P0.6 evidence. The
library's own observable physical run proves the flow path, but it does not
substitute for this independent consumer test. After P0.6, protemu P0.7 /
ASIC P5.3 exercises `Single_port_ram` with an explicitly selected flop store,
consumer validity and access gating, read latency/hold checks, and mapped
synthesis. A later adopted-bundle physical run closes ASIC P5.4.

## Response from protemu (2026-09-18)

The adopted path ran end to end. `./flow.sh` with no steps took a
`hardcaml_asic`-emitted bundle through build, emit, preflight, harden,
postcheck, collect, and report without intervention.

- Bundle identity `5edf30f980c96bdd67aa0b32d1aed806eee1994bb1e1164c2adb8a93504d308f`,
  declared by protemu's own `bin/asic_bundle.ml` against
  `asic_revision=414b7f4f92a201bd9bceb6864579dc3ee475101f`.
- Hardened onto TT `6x4` / `ihp-sg13cmos5l` at 48 MHz, LibreLane 3.1.0.dev3.
  Setup slack +15.589 ns (`nom_slow_1p08V_125C`), hold +0.147 ns
  (`nom_fast_1p32V_m40C`), no unconstrained modes. DRC, LVS, and antenna
  counts zero. TT precheck passes all nine rows. Gate-level simulation of the
  final netlist against protemu's `tb.v` passes. Inferred latches, unmapped
  instances, and synthesis errors are zero.
- 94 mapped cells, 13 flops, 2228 µm² final standard-cell area, utilization
  0.25%.

This is the consumer's adopted design on its own emitted bundle and pinned
dependencies, so it supplied the physical precursor P4.5 said was missing. It
did not alone close P5.4 because its source inputs were dirty. P5.2 closed on
2026-09-19; P5.4 closed on 2026-09-20 with the separate clean-staging
[P0.5c record](../../scaf/tinytapeout/reports/2026-09-20-p0.5c-clean-staging-physical.md)
and [archive](../../scaf/flow_results/20260920-081325-ccecd9ed/README.md).

1. **Emission is not yet reproducible from the recorded revision.** Five of the
   eight recorded source inputs were dirty or untracked at emission, including
   `bin/asic_bundle.ml` itself (`??`). The manifest hashes the copied content
   and records each input's `git_status`, so nothing is silently wrong, but
   `source_revision` does not describe the declaration that produced this
   bundle. P5.4's clean-staging clause therefore needed a committed tree, a
   re-emission, and a statement of whether `identity` is stable across that
   change.

   *Emission follow-up:* protemu committed at `7e29ecd`, all eight inputs clean, and
   re-emitted. `identity` is **not** stable across that change: it moved to
   `b699c8160775d269dd9fec5e6c17541cbc426c4bb9b5bf23952ed17b9626690b` while
   every emitted file stayed byte-identical, because the manifest records
   `source_revision` and each input's `git_status` and nothing else moved. The
   four-row identity table and the re-check of `src/config.json` against the
   archived one are in [`cmos5l-template-return.md`](cmos5l-template-return.md).
   That was a clean emission data point, not a hardened P5.4 result. The general
   property is worth keeping in view:
   `dune-project` and `hardcaml_protemu.opam` are declared inputs, so any commit
   touching them moves the bundle identity even when no RTL, configuration or
   constraint byte changes.
2. **P5.2's own evidence list is not covered by this run.** Repeatable
   emission, the wrapper regression on emitted RTL, and the
   configuration-conflict checks live in protemu's `check-adopted-bundle.py`,
   which the flow does not invoke and which left no record here. It needs to be
   run and linked separately.

   *Closed:* run in full against protemu `e7e3bb47` from a clean tree, exit 0,
   and recorded at
   [`2026-09-19-p0.6-adopted-bundle-check.md`](../../scaf/tinytapeout/reports/2026-09-19-p0.6-adopted-bundle-check.md)
   in the consumer repository. Four passes: the conflict diagnostics
   (`CLOCK_PERIOD`, `VERILOG_FILES`, `DIE_AREA` each rejected naming the key),
   repeatable emission and manifest/metadata checks, the `tb.v` wrapper trace on
   emitted RTL, and Verilator lint plus Yosys synthesis inside image
   `sha256:d109140b`, at identity
   `22dfaf9a9fe0bce4e0c58d78bd0bb4d39173223de16fbd2f0f6ce8119cb46c7a`. Generic
   synthesis reports 52 cells, 13 sequential and 39 combinational, which agrees
   with the 13 flops the physical run above found. The flow still does not invoke
   the check; that remains deliberate, since a physical run is physical evidence
   and the adoption invariants are checked separately.

The run record was archived with this library's own `scripts/archive.py`,
which ran against the consumer run directory unmodified: 111 files, 9.4 MB of a
239 MB run, into `scaf/flow_results/20260918-230920-05f65042/` (784 KB on disk)
with a README beside the records. Link that directory for P5.4; it is protemu's
evidence, so it lives in the consumer repository per the P5 entry note.

protemu has since vendored that script as `adopted_archive.py` and made
`archive` the eighth `./flow.sh` stage, so a full flow now promotes its own run
without anyone remembering to. The vendored copy differs only in which phase4
module it loads, which is worth knowing here: `scripts/archive.py` is the third
library script the consumer has had to copy rather than call, after
`phase4.py` and `report.py`.

**Current follow-up.** P5.3 has since closed with protemu's explicit-flop P0.7
integration and mapped synthesis, and P5.5 has since closed with the consolidated
usage guide. Memory physical feasibility and the separate CMOS5L SRAM capability
investigation remain open. Nothing in this observable physical run exercised
memory; at
0.25% utilization it does not test congestion or routability under pressure.

One flow-side note, not a blocker: LibreLane skipped `KLayout.DRC` in this run
(`klayout__drc_error__count` is absent from `final/metrics.csv`; step 72 warned
about it). Magic DRC covered it in-flow and TT precheck ran the KLayout decks
against the final GDS with zero items, so the layout has coverage — it just
comes from precheck rather than the flow, leaving `collect` no KLayout metric
to read. Enabling the step is not cheap: the same deck on the same GDS took
478.64s in precheck, so it would add roughly eight minutes and duplicate work
precheck already does. Teaching `collect` to read precheck's `drc_sg13cmos5l.xml`
is the better trade unless the metric is wanted in `metrics.csv` specifically.
