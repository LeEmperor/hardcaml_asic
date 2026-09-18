# P4.5 small physical path, 2026-09-18

The observable example hardened on a Tiny Tapeout 6x4 `ihp-sg13cmos5l` tile,
passed LibreLane signoff, TT precheck, and gate-level wrapper simulation in one
attempt. Its build identity is
`c456203dbc6ce53b4452e884e30e56349143e4ea1763ec60a39c513653d1498f`; the separate
run ID is `60a632eec5fb40e485ca9c549540b31b`. The immutable
[manifest](manifest.json), [preflight report](preflight.json),
[run record](run.json), [postcheck record](postcheck.json), and structured
[results](results.json) are beside this note, with logs and reports in
`reports.tar.gz`. Unpack it with `tar -xzf reports.tar.gz -C <empty-directory>`;
its paths mirror the run directory, so `execution.log`, the emitted
`project/src/config.json`, the signoff STA corners under
`project/runs/asic/55-openroad-stapostpnr`, the Yosys reports, and the precheck
reports under `checks/<id>` land where the records name them. The full run
directory is 235 MB of tool output and is not archived; the files here are the
ones the acceptance criteria are read from.

## Result

LibreLane `3.1.0.dev3` completed the `full` stage in 23m48s; postcheck took a
further 7m55s, for 31m43s end to end. The design is `tt_um_asic_observable` at
48 MHz (20.8333 ns), hardened into the pinned `tt_block_6x4_pgvdd` floorplan.

Timing meets its goal on every reported corner with no violations: worst setup
slack 15.882 ns at `nom_slow_1p08V_125C`, worst hold slack 0.148 ns at
`nom_fast_1p32V_m40C`, and no mode left unconstrained. Hold is the tight one, as
expected for a design this small in a tile this large, and it closed without
manual intervention: the post-CTS resizer reported no setup violations and
repaired hold against the bundle's `GRT_RESIZER_HOLD_SLACK_MARGIN` 0.05 and
`PL_RESIZER_HOLD_SLACK_MARGIN` 0.1.

Antenna, DRC, and LVS pass. Inferred latches, unmapped instances, and synthesis
check errors are all zero. Yosys mapped 48 standard cells (711.2448 µm², of
which 391.9104 µm² sequential): 16 `and2_1`, 8 `dfrbpq_1`, 8 `tiehi`, 16
`tielo`. Final standard-cell area including fill is 1,409.79 µm² at 0.156%
utilization — the tile is far larger than this design needs, which is the point
of the exercise, not a result about density.

TT precheck passes all nine rows (KLayout pin-label, SG13CMOS5L DRC, and
zero-area DRC; pin, boundary, layer, cell-name, and analog-pin checks). This is
the check that the bundle's reasoned physical overrides exist for: without
`FP_PDN_MULTILAYER=0` and the TT template's PDN and LEF-pin settings, LibreLane
puts the power grid on `TopMetal1` and precheck rejects the layout even though
LibreLane's own DRC, LVS, and antenna checks pass.

Gate-level simulation passes. Icarus 13.0 from the run's pinned LibreLane image
compiled the PDK I/O, UDP, and standard-cell models with the final
`final/nl/tt_um_asic_observable.nl.v` and `test/tt_bundle_tb.v`. The GDS,
netlist, and testbench hashes are in the postcheck record.

## Provenance and exceptions

`manifest.json` here is byte-identical to the bundle the run consumed: its
SHA-256 is `fd78d6976ad2c1f9ee9f134a5b417186014ce26f73f5caf5ef9ce9c57570a330`,
the `manifest_sha256` recorded in `run.json`. The manifest's `source_revision`
is `64c6255953ff596d6b296b82c95c7db3935e3ead`.

`preflight.json` was regenerated after the run, because `flow.sh` did not yet
save the report to a file when this attempt ran. It is byte-identical to the
`environment` block `run.json` recorded at the time, so it describes the same
toolchain and the same external file hashes; `run.json` remains the
contemporaneous record. `scripts/phase4.py preflight --output` now writes it
directly and `flow.sh` copies it into each run directory.

The host launcher used Python 3.12.3 and the LibreLane image uses Python
3.13.13, while the bundle requested 3.11. The run used
`--allow-python-mismatch`; both exceptions are recorded as waivers in the
preflight and run records, and neither alters the build.

## Scope

This is a library-owned example, emitted from `examples/tt_bundle_example.ml`.
It closes P4.5, whose acceptance is the physical path itself. It is **not**
evidence for P5.4: that gate requires the consumer's own adopted design, and
[the plan](../../../docs/phase_plan.md#8-p5--reference-consumer-adoption-and-initial-usage)
says not to substitute a library-owned fixture for consumer evidence. P4.5's
allowance to "count jointly with P5 evidence" would have applied only if this
run had used the emulator's adopted observable design; it did not.
