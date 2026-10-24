# Note: TT GitHub submission path and its action inputs

> Deferred note, not an implementation plan. Recorded 2026-10-23 while reviewing
> the organizer-linked SRAM walkthrough. Nothing in this repository calls
> `tt-gds-action` yet.

## Context

hardcaml_asic runs LibreLane itself instead of through `tt_tool.py --harden`. The
official GitHub path for a GDS built elsewhere is the `custom_gds` sub-action of
`TinyTapeout/tt-gds-action`. It does no hardening. It takes a finished GDS, LEF
and optional gate-level netlist and writes `tt_submission/` (`commit_id.json`,
`pdk.json`, GDS, OASIS, LEF, `.v`). It uploads that as the `tt_submission`
artifact and renders a preview PNG. The `precheck` and `gl_test` sub-actions then
consume that artifact exactly as they would the normal action's output. Ken
Pettit's PRISM project works this way:
`custom_gds@ihp-cmos5l` -> `precheck@ihp-cmos5l` -> `gl_test`.

The email says to stick to the TT flow, but running that flow locally is allowed.
Whether a locally run LibreLane that is not `tt_tool` counts is not stated. Ask
asic-competition@janestreet.com before relying on it.

## Inputs to pass explicitly

Observed at `tt-gds-action@ihp-cmos5l` = `3412659…` on 2026-10-23.

| Input | Default | What it does | Pass |
| --- | --- | --- | --- |
| `custom_gds` `pdk` | none (required) | Written into `tt_submission/pdk.json`. `precheck` and `gl_test` read it to choose the technology and PDK install. **This is the input that matters.** The input's option list omits `ihp-sg13cmos5l`, but composite actions do not enforce choices. | `ihp-sg13cmos5l` |
| `custom_gds` `tools-ref` | `main` | The `tt-support-tools` branch/tag/commit checked out into `tt/`. In `custom_gds` it is used only for the PNG preview, and a failure there is only a warning. `main` is a real branch of `TinyTapeout/tt-support-tools`, but it has no `tech/ihp-sg13cmos5l` (only `gf180mcuD`, `ihp-sg13g2`, `sky130A`), so the preview may not render. | `ihp-sg13cmos5l`, or the locked revision |
| `precheck` `tools-ref` | `ihp-sg13cmos5l` | The support-tools tree that runs the actual precheck. The default already selects the CMOS5L branch. | The locked support-tools revision from `toolchain.lock`, so the official check matches the local one |
| `docs` `tools-ref` | `ihp-sg13cmos5l` | Datasheet build. | Same as above |

A branch name is mutable: today `ihp-sg13cmos5l` resolves to `d66cf179…`, the
project pin, but it can move. Passing the 40-character locked revision instead
keeps GitHub's precheck on exactly what the local flow verified. `tools-ref`
accepts a commit.

## Reactivation condition

hardcaml_asic or a consumer starts publishing a GDS to a TT GitHub repository
for official precheck and gate-level test.
