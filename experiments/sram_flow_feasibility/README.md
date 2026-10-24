# Bounded PT.0 probe runs

Run from the ASIC repository root with Python 3.9 or newer. `run_pt0.py` uses only
the standard library; EDA runs use the existing `.toolchain` installation. Every
mode requires a fresh tag and an explicitly allocated share of the shared
20-job pool. The runner executes one flow at a time, serializes STA corners, and
sets OpenROAD and KLayout thread limits. It does not reserve jobs globally.

## Coordinator commands

First inspect commands without creating files or launching tools:

```sh
python3 experiments/sram_flow_feasibility/run_pt0.py sta --tag corners-01 --jobs 10 --dry-run
python3 experiments/sram_flow_feasibility/run_pt0.py magic-gds --tag magic-01 --jobs 10 --dry-run
python3 experiments/sram_flow_feasibility/run_pt0.py power-only --tag power-01 --jobs 10 --precheck --dry-run
python3 experiments/sram_flow_feasibility/run_pt0.py corrected-full --tag corrected-01 --jobs 10 --precheck --dry-run
```

After coordinator allocation, remove `--dry-run` to execute. Do not execute the
heavy commands while competing builds consume the allocation.

| Mode | Inputs and attribution |
| --- | --- |
| `sta` | Corrected exact Liberty map; original routed geometry by default. Runs only `OpenROAD.STAPostPNR`. |
| `magic-gds` | Retained geometry; enables `MAGIC_DRC_USE_GDS` in the snapshot and runs only `Magic.DRC`. |
| `power-only` | Original config read from the SHA-256-verified S.3 archive, with current corrected `pdn_cfg.tcl` and other authored inputs. Retains original typical-in-all-corners binding and abstract Magic DRC setting. Runs a fresh full flow. |
| `corrected-full` | Current corrected bridges and exact corner map. Runs a fresh full flow. |
| `precheck-only` | Requires explicit `--retained-run`; snapshots that run's final GDS/LEF and nearest ancestor `info.yaml`. Runs precheck only, without LibreLane. |

The fast standard-cell model is **−40 °C**, while the SRAM fast model is **−55 °C**.
Exact binding preserves and records this difference; it does not resolve it.

### Bridge correction after the first physical rerun

The retained `runs/pt0-power-01/inputs/runs/power-01/` result exposed a second
geometry defect in the first repair. Its
`62-magic-drc/reports/drc.magic.rpt` contains the original four abstract M2/M3
markers plus ten M4.b (0.21 um) and two M4.e (0.24 um) markers. The bridges ending
at x=115800 had only 0.13 um clearance to VGND. Zero extraction overlaps and a
black-box LVS pass did not establish metal spacing legality.

Source geometry was checked in that run's
`44-openroad-detailedrouting/tt_um_sram_probe.def` SPECIALNETS (also present in
`21-openroad-generatepdn/tt_um_sram_probe.def`):

| Object | x range (DBU) | y range (DBU) |
| --- | --- | --- |
| Nearby VPWR grid | 111830–113930 | 3560–80520 and 200260–707080 |
| Nearby VGND grid | 115930–118030 | 3560–80520 and 200260–707080 |
| Revised lower VPWR bridge | **113700–115650** | 79520–81000 |
| Revised upper VPWR bridge | **113700–115650** | 197660–201310 |

At 1000 DBU/um, the revised right edge gives **0.28 um** VGND clearance, with
0.04 um margin over the stronger applicable 0.24 um M4.e rule. Each bridge retains
**0.23 um x overlap** with VPWR, over 1.00 um (lower) and 1.05 um (upper) in y.
The macro LEF at the configured `(42,81)` R0 placement gives positive supply pins
at x=113700–116510, so contact is now **1.95 um**, superseding the initial 2.10 um
target to accommodate real grid clearance. The lower pin contact is an edge
abutment; the upper bridge overlaps VDDARRAY in y by 2.12 um. The Metal4 obstruction
ends at x=113440 and remains clear. VGND geometry is unchanged.

The PDK technology LEF (`libs.ref/sg13cmos5l_stdcell/lef/sg13cmos5l_tech.lef`,
Metal4) specifies width 0.20 um, area 0.144 um², and spacing 0.21/0.24 um.
The new rectangles have minimum dimensions 1.48 and 1.95 um, areas 2.886 and
7.1175 um², and the grid connection overlap is 0.23 um wide. These satisfy the
checked local width/area geometry; they do not establish IR/EM adequacy.
`test/test_pt0_probe.py` checks contact, opposite-net grid clearance, rejects the
old 115800 edge, and cross-checks its representative grid against the retained
DEF when available. The new physical run must still verify emitted geometry,
DRC, extraction, supply connectivity, LVS and precheck. Macro-boundary slew/cap
residual remediation remains explicit PT.0c follow-up; constraints are unchanged.

STA and Magic default to retained `runs/attempt-005-full`. To analyze the fresh
corrected physical result after it completes:

```sh
python3 experiments/sram_flow_feasibility/run_pt0.py sta --tag corrected-sta-01 --jobs 10 \
  --retained-run experiments/sram_flow_feasibility/runs/pt0-corrected-01/inputs/runs/corrected-01
python3 experiments/sram_flow_feasibility/run_pt0.py magic-gds --tag corrected-magic-01 --jobs 10 \
  --retained-run experiments/sram_flow_feasibility/runs/pt0-corrected-01/inputs/runs/corrected-01
```

Retained state must be a JSON object. STA requires `nl` and a nonempty
corner-keyed `spef` map (path or path-list entries); Magic-on-GDS requires `gds`.
All supplied view paths must exist. Optional `odb`/`sdc` views are not required:
LibreLane declares ODB optional and this probe config supplies the signoff SDC.
Other optional views, nulls, corner maps and path lists remain supported.
Invalid input is rejected with exit 2 before output reservation or dispatch.

To retry precheck on the completed power-only run without repeating physical work:

```sh
python3 experiments/sram_flow_feasibility/run_pt0.py precheck-only \
  --tag power-01-precheck-02 --jobs 10 --tt-root .toolchain/tt \
  --retained-run experiments/sram_flow_feasibility/runs/pt0-power-01/inputs/runs/power-01 \
  --dry-run
```

Remove `--dry-run` after coordinator allocation. This creates
`runs/pt0-power-01-precheck-02/`; the failed `pt0-power-01` attempt is preserved.
No `--precheck` flag is needed in `precheck-only` mode.

## Output and preservation

New output is always `runs/pt0-<tag>/`, exclusively created. An existing identity
is rejected even after failure. No historical run/evidence is overwritten.

- `inputs/`: read-only copies of authored inputs, effective config, floorplan
  template, runner, and (for bounded checks) initial state JSON.
- `inputs/runs/<tag>/`: LibreLane's new outputs, including resolved configuration
  and, for full runs, `final/`.
- `manifest.json`: exact command, allocation, revisions/checkout status, input
  hashes, retained view hashes, attribution and optional precheck command.
- `flow.log`, `status.json`: subprocess output and exit results.
- With `--precheck`: `precheck.log`, `bin/klayout`, and isolated `tt/precheck/`
  reports. Precheck and `tech/` are copied from the selected TT root; installed
  TT/PDK sources and historical precheck reports are untouched.
- `precheck-only` has the same precheck outputs and a fresh, initially empty
  `tt/precheck/reports/`. Its read-only `inputs/` holds the runner, this README,
  `gds/`, `lef/`, and the retained `info.yaml`. Hashes identify both source files
  and copied inputs. There is no flow invocation or `flow_exit` in its status;
  it returns the precheck exit status directly.

Snapshots are sealed read-only at creation, not made tamper-proof. Retained view
files and PDK views remain external dependencies; their paths/hashes or revisions
are recorded. Preserve those inputs when curating portable evidence. Power-only
mode gets its config from the original archive, but uses the current authored RTL,
SDC and PDN; their hashes explicitly identify any additional future changes.

## Precheck and result interpretation

The default `.toolchain/tt-sram-s3-cfa06bae` at `cfa06bae…` is an intentional
**historical S.3 comparison choice**, not the current project support-tools pin.
The project pin moved to `d66cf179e7bc4d296362ab7e2e3b344dc3c4f665`, which already
includes the SRAM marker-layer fix. To use the currently provisioned checkout:

```sh
python3 experiments/sram_flow_feasibility/run_pt0.py corrected-full \
  --tag corrected-current-01 --jobs 10 --precheck --tt-root .toolchain/tt --dry-run
```

Remove `--dry-run` only after resource allocation. `--tt-root` requires
`--precheck` or `precheck-only`; the selected directory must contain `precheck/precheck.py`,
`precheck/default.nix`, and `tech/`. The runner records the selected absolute path,
actual revision and checkout status, and copies its precheck sources. It does not
assert that an arbitrary checkout matches the current pin or provision one.
The physical floorplan template still comes from `config.json` (historical S.3
template), is copied into the input snapshot, and is attributed separately.
Changing `--tt-root` selects precheck sources, not the physical template.

`--precheck` is supported only for full-flow modes; `precheck-only` enables the
same isolated setup automatically. Both create an empty reports directory before
dispatch instead of copying historical reports. Precheck uses the copied
`default.nix` shell and `.toolchain/.venv-precheck/bin/python`. Within that shell it
resolves the real KLayout executable, then prepends a recorded launcher which
injects `-rd threads=<jobs>`. Both the pin-label deck and CMOS5L deck use this
variable; the historical `thr=1` argument does not limit them. The launcher fails
if the real executable cannot be resolved. The Nix shell may need its pinned
dependencies downloaded; the runner does not provision or change tool pins.
The installed precheck Python environment must also satisfy the selected
checkout's dependencies; dry-run checks input availability, not runtime imports
or Nix dependency realization.

On this machine Nix may print `file 'nixpkgs' was not found` while trying to
select `bashInteractive`, then `will use bash from your environment`. The retained
log shows it continues into the real KLayout checks. This is distinct from the
missing reports-directory failure fixed here. No cached source was established
as the exact pinned nixpkgs revision, so the runner does not guess a store path or
download a replacement to suppress the warning. `default.nix` retains its own
explicit nixpkgs tarball pin.

A full Classic run can produce final GDS but return nonzero for known checkers.
Precheck still runs if final GDS exists; both exits are recorded, and the runner
returns failure if either tool fails. Missing GDS skips precheck. Unexpected
interruptions may leave an incomplete output directory; choose a fresh tag.
An external foreground timeout can leave a Docker tool container alive. The runner
does not guarantee container cleanup after external termination; the coordinator
must check for surviving work before reusing the allocation. Precheck-only invokes
Nix directly and does not start a LibreLane Docker container.

An STA-only or Magic-only exit is not an acceptance decision: subsequent Classic
checker stages are not run. Inspect per-corner Liberty loads, setup/hold,
slew/capacitance, parasitic coverage and Magic violation reports. For full runs,
also inspect actual bridge geometry, extraction feedback, power connectivity,
macro retention, LVS and every precheck row. The existing behavioral fixture is
RTL-only. This runner does not add gate-level or timed-model validation.
