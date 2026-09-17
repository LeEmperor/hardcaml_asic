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
delays (minimum 0 ns; maximum 1 ns and 2 ns) demonstrate typed SDC emission;
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
  constraints/top.sdc       typed clock and optional min/max I/O delays
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
