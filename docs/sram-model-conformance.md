# Exact SRAM model conformance experiment

Status: ASIC S.2a complete, 2026-09-20. The exact candidate's supplied
functional model conforms to the checked portable RAM behavior. Its timed branch
compiles, but Icarus cannot execute that branch meaningfully because it does not
drive the delayed signals attached to unsupported timing checks. This is model
evidence only, not a production backend, physical-flow result, or target approval.

## Result

The candidate is
`RM_IHPSG13_1P_256x16_c2_bm_bist` from IHP Open PDK revision
`2bbec755dc67ca3db0261c3d6163e15735d66710`. The PDK checkout was clean and its
tracked CMOS5L SRAM path remained the relative symlink to the shared SG13G2 SRAM
library. All expected input hashes matched before compilation; no drift was
observed.

The three separate conclusions are:

| Question | Result |
| --- | --- |
| A. Functional-model conformance | **Pass.** `FUNCTIONAL` model: 23 deterministic directed operation vectors, 86 checks, zero failures |
| B. Timed-model compilation/elaboration | **Pass with explicit limitations.** The exact non-`FUNCTIONAL` source compiles and elaborates with Icarus both with default specify handling and with `-gspecify` |
| C. Actual timing behavior/checks | **Not established.** Icarus applies module-path delay with `-gspecify`, but reports timing checks unsupported and does not drive the exact model's delayed clock/control/address/data/mask signals; exact-model timed runs therefore retain unknown read data |

There is no functional contract mismatch in the tested scope. Timed execution is
a simulator limitation, not evidence of a candidate defect.

## Contract and adapter

The normative contract is
[`program-memory-contract.md`](program-memory-contract.md): positive-edge input
sampling, one-cycle registered read output, whole-word writes, output hold while
disabled, no initialization promise, and unspecified output after writes and
unwritten reads. The existing
[`test_single_port_ram.ml`](../test/test_single_port_ram.ml) scoreboard supplies
the comparison rule reused here: track expected storage independently, compare
only defined reads, and preserve each DUT's actual output across disabled cycles.
The external four-state Verilog model cannot run in Hardcaml's two-state
`Cyclesim`, so the experiment adapts that scoreboard rather than changing the
ordinary test harness.

[`RM_IHPSG13_1P_256x16_portable_wrapper.v`](../experiments/sram_model_conformance/RM_IHPSG13_1P_256x16_portable_wrapper.v)
contains exactly one candidate instance and maps:

```text
A_MEN = enable
A_WEN = enable && write_enable
A_REN = enable && !write_enable
```

This mapping follows the exact documentation and shared model truth table. It
never requests the candidate's separate write-through operation. `A_BM[15:0]`
is tied to active-high `16'hffff` for whole-word writes. Mandatory `A_DLY` is
tied high. `A_BIST_EN`, clock, memory/read/write enables, address, data, and mask
are all stable zero, permanently selecting the normal port. The wrapper checks
no physical supplies because this Verilog module has no supply ports; physical
`VDD`, `VDDARRAY`, and `VSS` integration was not modeled or tested.

The shared model samples `CLK_MUX` on its rising edge. A plain write updates only
selected memory bits, a read updates `dr_r`, write-through updates both, and
no-operation/plain-write cycles leave `dr_r` unchanged. Neither memory nor
`dr_r` has an initializer. The macro wrapper selects this direct model when
`FUNCTIONAL` is defined; otherwise it feeds the model through specify delayed
signals and declares 1 ns paths plus width/setup-hold checks and a notifier.
Liberty independently describes rising-edge `A_CLK` memory write/read behavior,
conditional setup/hold groups, and a clock-related `A_DOUT` timing arc.

## Functional coverage

The deterministic vectors are embedded in
[`sram_model_conformance_tb.sv`](../experiments/sram_model_conformance/sram_model_conformance_tb.sv);
there is no random seed. Coverage includes:

- initial unknown output followed by disabled hold, without requiring zero or X;
- unwritten reads and four-state-aware hold of their actual result;
- writes and complementary same-address rewrites (`a55a`/`5aa5`) to expose an
  inactive or partial mask;
- first and last legal addresses, consecutive writes and reads, representative
  addresses, and `0000`, `ffff`, alternating, and mixed data;
- write/read, read/write, and same-address transitions;
- disabled cycles while all inputs change, including `write_enable=1`, followed
  by a defined read proving memory was not modified;
- output hold after defined reads, writes, unwritten reads, and initial state;
- no output update between falling-edge stimulus and the next rising edge;
- stable mask, DLY, and every BIST tie-off, plus no simultaneous read/write
  request.

All stability checks use case inequality (`!==`), so X/Z changes cannot be
hidden. Stimulus changes on falling edges. Functional results are sampled 100 ps
after each rising edge, after the vendor model's nonblocking assignment region
and its 10 ps precision, avoiding a scheduling race. The exact depth is 256 and
the address is eight bits, so no out-of-range vector exists. The test never
initializes the macro or constrains unspecified output values.

An `INJECT_FAILURE` build executes an intentional `$fatal(1)` under a 30-second
timeout. `vvp` returned status 1, proving the runner rejects an assertion failure
instead of reporting success.

## Timing assessment

The exact timed branch compiled twice: once with Icarus's default disabled
module-path handling and once with `-gspecify`. Both compilations emitted the
precise warning `Timing checks are not supported and delayed signal ... will not
be driven` for the candidate's `$setuphold` delayed arguments. Both attempted
contract runs consequently failed defined reads with `xxxx`; that is expected
from the undriven delayed model inputs and is not classified as macro behavior.

The separate `timing_support_tb.sv` diagnostic uses a 1 ns specify path and a 1 ns
setup check. Without `-gspecify`, output changed at the 5 ns and 15 ns active
edges. With `-gspecify`, those changes occurred at 6 ns and 16 ns, confirming
module-path delay support. A data transition 0.2 ns before the 15 ns edge did not
change the initialized notifier from zero, confirming that setup checks were not
executed. Thus path delays alone are supported, timing checks and delayed
reference signals required by this candidate are not, and actual timed-model
conformance remains open for a capable simulator.

## Reproduction and evidence

Run from the repository root without editing the PDK checkout:

```sh
experiments/sram_model_conformance/run.sh \
  --pdk-root /home/wayne/devel/jane/hardcaml_asic/.toolchain/pdk \
  --output-dir evidence/sram-model-conformance
```

The runner accepts an explicit PDK root, defaults only to this repository's
`.toolchain/pdk`, validates the exact Git revision and all consumed collateral
hashes, and never downloads inputs. It records full commands, working directory,
tool paths/versions, checkout state, compile output, run output, outcomes, and
input hashes. The durable text artifacts are in
[`evidence/sram-model-conformance/`](../evidence/sram-model-conformance/).
Generated `.vvp` files are deleted at the end of the run; no artifact is stored
externally or only in an ignored path.

The compiler/runtime were `/usr/bin/iverilog` and `/usr/bin/vvp`, both Icarus
Verilog 12.0 stable. Relevant commands and flags are present verbatim in the
logs: `-g2012 -Wall -s sram_model_conformance_tb`, `-DFUNCTIONAL` for functional
runs, omission of that define plus `-DTIMED_MODEL` for timed runs, and a separate
`-gspecify` timed build. Inputs were the shared behavioral source, exact macro
source, experiment wrapper, and testbench; no include path was required.

Key SHA-256 values are:

| Input | SHA-256 |
| --- | --- |
| Exact macro Verilog | `645c475787b077da4dbd15856c68bbae46aa9846a155239eb895ed2de7511053` |
| Shared behavioral model | `d0a6258f8e9c93d1d5b1f78c0a1d66f30d28b1ad8037e5e07f53d1a4e3670b12` |
| Datasheet | `92b32189ff35af75e096e3faf8f85df9fe572f207d5f97405cc0ddf20ec2a609` |
| Typical/fast/slow Liberty | `6f4cca1ed508f879a35bdc15a9de2d027f81ec0eeec0d6c8ab27d05f5edad445`, `c28bb80737d7a7daea14b9d259380c7e1dfc27c71c3ad1223a5387d8515ebe4b`, `a04cff61cb4befb2290427db1ff2cb1c31c8d5990dca53ee3e5d1cc621679cd9` |
| Experimental wrapper | `c1a9e37a3cffb6e6df97ba6353fa36c2aa90105ef32a115fed30efe1ccb5f352` |
| Testbench/vector source | `4bca5b5589798c1b7a58ff342652be9ce1f847b8c249d31afc215e567e8d2241` |
| Timing support diagnostic | `a5202303a9c2f7b899f3d74087e0dc9f3d3750939c7af6672cbd50d9f8729b60` |
| Runner | `29937d9eef92979d3d5a4165400d700045968a7e9f20948d8e4c1694d1fe8805` |

`inputs.sha256` is generated from those inputs and deliberately does not hash
itself. The exact Liberty files are named in that manifest and were inspected,
not supplied to the Verilog compiler.

## Boundary and next task

No library interface, ordinary RAM test, technology mapping, resource selection,
lock, production adapter, PDK file, or consumer file changed. S.1 remains closed.
S.2a is complete only for functional behavior and the recorded timing-support
limit; S.2 overall remains open because S.2b target/submission permission,
accepted dual-supply connection, and official submission pin remain unresolved.
S.3 physical feasibility and S.4 backend implementation remain gated.

The next bounded task is S.2b: obtain authoritative target, pin, and power
requirements for the March 2027 CMOS5L 6x4 submission. Do not infer permission
from this functional result or begin physical/backend work.
