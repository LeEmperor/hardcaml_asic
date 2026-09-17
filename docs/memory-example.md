# Registered memory example

The [example](../examples/memory_example.ml) declares one 4×8 single-port RAM.
Its design constructor is identical for simulation and implementation elaboration.
The project explicitly selects flops. The consumer writes complete words before
checking readback and tracks which words are written outside the RAM.

Run from the repository root:

```sh
dune build
dune runtest
dune exec examples/memory_example.exe
```

The command prints the selected resource and reason for each mode, checks
readback and disabled-output hold, shows that an exact macro requirement fails
on the current CMOS5L technology, and prints the reason for an explicitly
permitted flop fallback. None of these commands needs a PDK.

To inspect the synthesizable RTL:

```sh
dune exec examples/memory_example.exe -- --rtl /tmp/memory_example.v
```

With Icarus Verilog available, run the generated RTL testbench:

```sh
sh test/run_rtl_sim.sh /tmp/hardcaml_asic_rtl_check
```

The runner accepts `IVERILOG_BIN`, `VVP_BIN`, and `IVERILOG_BASE` when the
tool is extracted outside the normal system path. Its generated RTL test checks
whole-word writes, latency-one reads, and hold after both defined and unspecified
outputs. The ordinary Dune checks use Hardcaml's simulator and do not require
Icarus.

The behavioral model initializes unwritten locations to alternating-bit poison
and returns poison after writes or enabled out-of-range accesses. Poison is an
ordinary two-state value, not an unknown or an assertion. The implementation
flops have no reset or initialization; output after writes and reads of
unwritten locations is unspecified. Consumers must track validity and legal
addresses themselves.
