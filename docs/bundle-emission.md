# TT/CMOS5L bundle emission

Phase 3 emits a Tiny Tapeout project directory from one validated project
declaration. It does not run synthesis or hardening.

From this repository's root:

```sh
dune build
dune exec examples/tt_bundle_example.exe -- observable /tmp/asic-observable
dune exec examples/tt_bundle_example.exe -- memory /tmp/asic-memory
dune runtest
```

Each output directory must be new or empty. The optional third CLI argument is
the source root; it defaults to the current directory. The command reads Git
HEAD and every `.ml`/`.mli` under that root's `lib/`, plus the example and Dune
declarations. Missing source inputs and a source root without a Git commit fail
before files are written. The command names no sibling checkout.

The memory example uses an explicitly selected four-word, eight-bit flop RAM.
`ui_in[1:0]` is its address, `ui_in[2]` is write enable, `uio_in` is whole-word
write data, `ena` enables access, and `uo_out` is registered read data. It has
no reset or validity port on the RAM; reads of unwritten words are unspecified.
The observable example registers `ui_in` on `clk`, clears on active-low `rst_n`,
and drives zero to `uo_out` when `ena` is low. Its declared input and output
delays (minimum 0 ns; maximum 1 ns on `ui_in`, `rst_n` and `ena`, 2 ns on
`uo_out`) demonstrate typed SDC emission;
these are example assumptions, not values inferred from the TT board. The
minimum of 0 ns is the hold-pessimistic choice for inputs driven asynchronously
to `clk`.

## Bundle layout

```text
OUTPUT/
  info.yaml                 TT metadata, pinout, top, clock and source list
  src/config.json           resolved LibreLane settings
  src/<top>.v               synthesis RTL
  simulation/<top>.v        separately elaborated behavioral simulation RTL
  constraints/top.sdc       typed clock, target constraint environment, and
                            optional min/max I/O delays
  inputs/...                exact copies of declared generator source inputs
  manifest.json             schema version 1, identity and SHA-256 inventory
```

`info.yaml` names the single file under `src/`. `VERILOG_FILES` uses
`dir::<top>.v`, relative to `src/config.json`. The SDC paths use
`dir::../constraints/top.sdc`; the floorplan path uses
`dir::../tt/tech/ihp-sg13cmos5l/def/tt_block_6x4_pgvdd.def`. The pinned TT
[`project.py` at the pinned TT revision](https://github.com/TinyTapeout/tt-support-tools/blob/da63c9927411e3aca350977d653d24bbf5bca972/project.py)
expects a checkout linked at `OUTPUT/tt` when the physical flow
runs. That checkout, the PDK, LibreLane, and the flow runner are external
prerequisites for phase 4. The bundle itself needs none of them. TT's
`create_user_config` may regenerate derived settings from `info.yaml`; they
originate from the same declaration and must agree with `src/config.json`.
LibreLane's [PnR and signoff SDC variables](https://librelane.readthedocs.io/en/latest/usage/timing_closure/index.html)
consume the generated timing file.

## Generated SDC

Because `PNR_SDC_FILE` and `SIGNOFF_SDC_FILE` point at `constraints/top.sdc`,
LibreLane's `FALLBACK_SDC` never runs, so this file is the whole timing
environment. It is written in a fixed order, with every number formatted to
round-trip exactly, so the same declaration always produces the same bytes:

```tcl
create_clock -name clk -period 20.833333333333336 [get_ports {clk}]
set_clock_uncertainty 0.25 [get_clocks {clk}]
set_clock_transition 0.14999999999999999 [get_clocks {clk}]
set_timing_derate -early 0.94999999999999996
set_timing_derate -late 1.05
set_max_fanout 10 [current_design]
set_driving_cell -lib_cell sg13cmos5l_buf_4 -pin X [get_ports {ena rst_n ui_in uio_in}]
set_driving_cell -lib_cell sg13cmos5l_buf_4 -pin X [get_ports {clk}]
set_load 0.0060000000000000001 [get_ports {uio_oe uio_out uo_out}]
set_input_delay -max 1 -clock clk [get_ports {ena}]
set_input_delay -min 0 -clock clk [get_ports {ena}]
...
```

The clock and the per-port delays come from the project declaration; everything
between them comes from the resolved target's constraint environment and is
documented in [the target reference](target-reference.md). `set_load` is in the
Liberty `capacitive_load_unit`, which is picofarads for sg13cmos5l, so the 6 fF
`OUTPUT_CAP_LOAD` is divided by 1000 exactly as `base.sdc` does. The six
LibreLane variables behind those lines are also emitted into `src/config.json`
as `Target`-owned settings, so synthesis — which reads `SYNTH_DRIVING_CELL`,
`OUTPUT_CAP_LOAD` and `MAX_FANOUT_CONSTRAINT` outside the SDC — optimises
against the same environment that timing analysis assumes. All of them, plus
`IO_DELAY_CONSTRAINT`, `SYNTH_CLK_DRIVING_CELL`, `MAX_TRANSITION_CONSTRAINT` and
`MAX_CAPACITANCE_CONSTRAINT`, are protected keys: a raw override of one would
either do nothing or move synthesis away from what the SDC analyses.

No `set_propagated_clock` or `unset_propagated_clock` appears, on purpose.
LibreLane's `read_current_sdc` greps the file for both and, finding neither,
unpropagates clocks for pre-CTS analysis and propagates them afterwards.

The two RTL source sets have separate paths and are compiled independently.
For the memory example, the synthesis set contains flop storage without
behavioral poison initialization; the simulation set contains diagnostic
initialization. No consumer should compile both sets together. The manifest
lists each set explicitly and records the resource request, selection reason,
source roles, resolved settings and override reasons.

The manifest identity is SHA-256 of its canonical ordered payload, excluding
the identity field itself. Its file inventory hashes every emitted file except
the manifest. Each declared input has a content hash, Git status, and a copy
under `inputs/`, so dirty and untracked source bytes remain retrievable. Target
references record their role, path, revision, corner and any known hash. The
floorplan has a pinned SHA-256; standard-cell PDK views are external references
whose installed bytes require the phase 4 environment preflight.
Actual run versions, logs and reports belong to separate execution records.

`dune runtest` regenerates both examples in a temporary Git repository, checks
stable output and content hashes, changes a tracked source and adds an untracked
source to prove manifest identity changes, checks missing-input diagnostics, and
compiles and simulates each RTL source set with Icarus when it is installed.
The testbench is [`test/tt_bundle_tb.v`](../test/tt_bundle_tb.v). The
[Phase 4 guide](phase4-execution.md) covers preflight, isolated execution,
result collection, and physical acceptance evidence.
