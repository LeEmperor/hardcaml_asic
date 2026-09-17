# TT 6x4 / IHP CMOS5L target reference

The first target resolver accepts Tiny Tapeout `6x4` with `ihp-sg13cmos5l`.
`Target.resolve` returns die bounds in micrometres, the floorplan DEF reference,
power pins, the allowed project routing range, the nominal timing corner, and
standard-cell view references. It rejects unsupported combinations and incomplete
input records before any flow input is emitted. It reads no installed PDK and
performs no setup.

The default `Target.Inputs.reference_cmos5l_6x4` adopts the revisions and
floorplan hash in the [consumer's toolchain lock](../../scaf/tinytapeout/toolchain.lock):

| Input | Adopted value |
| --- | --- |
| Support tools | `da63c9927411e3aca350977d653d24bbf5bca972` |
| IHP Open PDK | `2bbec755dc67ca3db0261c3d6163e15735d66710` |
| Floorplan | `tech/ihp-sg13cmos5l/def/tt_block_6x4_pgvdd.def` |
| DEF SHA-256 | `b46d9a0ee8352160e48dbc8312f092f985629061df736c7f46d58686535a76f4` |
| Die bounds | `(0, 0)` to `(1289.28, 710.64)` µm |

The dimensions agree with the pinned support tools'
[`tile_sizes.yaml`](https://github.com/TinyTapeout/tt-support-tools/blob/da63c9927411e3aca350977d653d24bbf5bca972/tech/ihp-sg13cmos5l/tile_sizes.yaml).
The [pinned `project.py`](https://github.com/TinyTapeout/tt-support-tools/blob/da63c9927411e3aca350977d653d24bbf5bca972/project.py)
derives the DEF path, `VPWR`/`VGND`, and the project top routing layer. The
[pinned `tech.py`](https://github.com/TinyTapeout/tt-support-tools/blob/da63c9927411e3aca350977d653d24bbf5bca972/tech.py)
sets that layer to `Metal4` and the nominal corner to
`nom_typ_1p20V_25C`. The [PDK LibreLane configuration](https://github.com/IHP-GmbH/IHP-Open-PDK/blob/2bbec755dc67ca3db0261c3d6163e15735d66710/ihp-sg13cmos5l/libs.tech/librelane/config.tcl)
identifies the standard-cell LEF, GDS, and Verilog paths, the `VDD`/`VSS`
cell pins, and routing from `Metal2` through `Metal4` for this TT project.
The resolver records the nominal standard-cell Liberty reference under that
same PDK revision.

The `6x4` pair is the only resolved combination so far. Other tile constructors
remain available for declarations used by P0/P1 examples, but attempting to
resolve them fails until their floorplans and revisions are adopted. Physical
file presence and revision/hash checks belong to the explicit P4 preflight before
physical execution; no PDK is present in ordinary library tests. These
standard-cell views do not establish an SRAM macro.

## Validated TT/LibreLane build

`Project.elaborate_for_flow` elaborates an implementation and calls
`Resolved_build.resolve`. It returns the resolved target, checked interface,
clock and I/O delays in nanoseconds, clock frequency in hertz, and LibreLane
settings with an owner for each value. `Project.elaborate` still supports
resource-only examples and behavioral simulation without requiring a supported
physical target. [P3 emission](bundle-emission.md) consumes the validated result.

The TT top has exactly these ports:

| Inputs | Outputs |
| --- | --- |
| `ui_in[7:0]`, `uio_in[7:0]`, `ena`, `clk`, `rst_n` | `uo_out[7:0]`, `uio_out[7:0]`, `uio_oe[7:0]` |

Resolution checks names, widths, and directions, including unused input ports
that Hardcaml records as phantom inputs. The declaration supplies a nonblank
title, author, and description plus one description for each of the 24 `ui`,
`uo`, and `uio` bits. The TT wrapper owns reset, disable, and pad arbitration
behavior; these checks only validate its boundary.

The initial timing subset is one primary clock on input `clk`, with optional
input and output delays on named top-level ports. Each delay declares both a
`minimum` (hold) and a `maximum` (setup); both are required because an SDC
delay with only `-max` leaves hold unconstrained, so STA reports no hold paths
and the resizer inserts no hold buffers. `Clock.period` and the delay bounds use
`Time_float.Span.t`, allowing the 48 MHz reference period of about 20.833333
ns. Resolution rejects nonfinite or nonpositive clock periods, negative or
nonfinite maximums, nonfinite minimums or minimums above their maximum
(negative minimums are allowed), duplicate delays, wrong-direction endpoints,
delays on `clk`, and additional clocks. It sorts delay endpoints for
stable emission. P3 renders the resolved primary clock to LibreLane
`CLOCK_PORT`/`CLOCK_PERIOD` and TT `clock_hz`, and the validated delay
subset to SDC. No other SDC intent is accepted by this declaration API.
The pinned `src/config.json` declares only `CLOCK_PORT` and `CLOCK_PERIOD` as
timing inputs; it has no reviewed board-specific I/O delay values. Those
delays therefore remain optional declarations rather than fabricated defaults.

| Configuration fact | Owner | Override rule |
| --- | --- | --- |
| Top name and generated RTL list | Elaborated design and P3 source set | Protected |
| Clock port and period | Typed clock | Protected |
| Die area, floorplan, PDK, cell library, routing maximum, power pins | Resolved target | Protected |
| `MACROS` | Registered resources | Raw override rejected; no CMOS5L macro is supported |
| `FP_SIZING`, `RUN_LINTER` | Initial adapter defaults | Reasoned override allowed |
| Other LibreLane settings such as density, margins, PDN pitch, and checks | Reasoned override | Recorded with key, strict JSON value, and reason |

The existing consumer's `src/config.json` settings fit this boundary: clock
values come from the typed clock, `FP_SIZING` and `RUN_LINTER` have defaults,
and its other keys can be supplied as reasoned overrides. P3 populates the
generated RTL list from emitted files. `Resolved_build` rejects protected keys
even when the proposed value matches, so a raw setting cannot become a second
authority. Its adapter capability check accepts implementation elaborations for
LibreLane synthesis and hardening. Synthesis requires the PDK configuration,
standard-cell Liberty, and cell Verilog roles; hardening additionally needs the
technology LEF, cell LEF, and cell GDS roles. Every registered flop resource
must carry generated synthesis RTL. A macro selection is currently rejected by
this adapter, independently of technology selection policy.
