# Program memory contract (`Single_port_ram`)

Status: draft, 2026-09-15. Normative for `lib/single_port_ram.mli`. This document
decides behaviour; the interface summarises it and the implementation obeys it.

This is the first concrete memory in `hardcaml_asic`, written before the API was
frozen, per the review note that memory semantics must precede the `Sram.create`
signature. Every decision below cites the requirement that forces it, so that a
later reader can tell a derived constraint from an arbitrary one.

Citations of the form `construction-plan.md:NNN` refer to the protocol emulator
repository (`hardcaml_protemu`, worktree `scaf`), which is the reference design
per the concept note's "Relationship to the Protocol Emulator Competition".

---

## 1. Why this memory, and only this memory

The emulator names three storage users:

| Storage | Size | Decision |
| --- | --- | --- |
| Program memory, 256x16 | 4,096 bits | **This primitive.** 94% of all storage bits |
| Two byte FIFOs, 16x8 | 256 bits | Flip-flops. Not a macro, not this primitive |
| Register file, 8x16 | 128 bits | Flip-flops. Multi-port read; wrong shape for 1RW |

`construction-plan.md:179` — *"256x16 program bits plus two 16x8 FIFOs already
total 4,352 storage bits before registers and metadata. That can dominate a small
design if implemented in flip-flops."*

Only the program memory is large enough to justify a physical macro. Routing the
FIFOs or the register file through this interface would buy interface complexity
and no area, and is explicitly out of scope for v0.1.

---

## 2. Port shape: single-port 1RW, shared address

**Decision: one address bus, one enable, one write-enable. A cycle is a read or a
write, never both.**

Forced by `construction-plan.md:186` — *"Permit host program writes only while
halted with engines idle."*

Host program load and instruction fetch are **temporally exclusive by
construction**. They cannot occur in the same cycle, because the core is halted
during load. There is therefore no requirement for concurrent read and write, and
no reason to pay for a second port.

This is the most consequential decision in the document. 1RW is the smallest,
cheapest and most widely available compiled-macro configuration. A 1R1W or true
dual-port memory is substantially larger and much less likely to exist in an open
PDK. Had the architecture permitted host writes during execution, the memory
requirement would have changed shape entirely.

**Consequence for the architecture:** the halted-during-load rule is now a
*memory* constraint, not only a safety convention. Relaxing it later is not a
firmware change; it is a change of memory primitive. Record it as such.

---

## 3. Read-during-write: not expressible, therefore not promised

The concept note's sketch carries a `read_during_write` field with `Read_first`,
`Write_first` and `Undefined`. **This primitive does not have that field.**

With a shared address and a single write-enable, a simultaneous read and write of
the same address cannot be expressed: when `write_enable` is high the cycle is a
write, when it is low the cycle is a read. There is no second port to read from.

Offering a policy enum here would promise a portable behaviour the primitive
cannot exhibit and a backend cannot guarantee — precisely the trap in concept-note
open question 2 ("how much memory behaviour should the portable SRAM API promise
across technologies"). A future memory that genuinely has two ports can carry the
policy; this one must not.

The real question that *does* need answering is what the output does during a
write cycle. That is section 4.

---

## 4. Cycle-by-cycle contract

`read_latency = 1`. Inputs are sampled on the rising edge of cycle *n*; the value
returned in cycle *n+1* reflects the operation presented in cycle *n*.

| `enable` | `write_enable` | Operation | Read data in the following cycle |
| --- | --- | --- | --- |
| 0 | x | none | **holds** its previous value |
| 1 | 0 | read `address` | `mem[address]` |
| 1 | 1 | write `write_data` to `address` | **unspecified** — poison in simulation |

```text
cycle               1      2      3      4      5      6
--------------------------------------------------------
enable              1      1      0      1      1      0
write_enable        1      0      0      0      1      0
address             A0     A1     --     A2     A3     --
write_data          D0     --     --     --     D3     --
--------------------------------------------------------
operation          WR     RD     --     RD     WR     --
read_data (out)     ?   POISON  M[A1]  M[A1]  M[A2] POISON
                           ^      ^      ^             ^
                           |      |      |             held from
                           |      |      held          cycle 5's
                           |      |      (enable=0)    write
                           |      read of A1 lands
                           write cycle: unspecified
```

### 4.1 Hold on disable — why this is pinned rather than left open

Real SRAM macros typically hold the previous output when chip-enable is
deasserted. A naive behavioural model emits zero, or re-reads, or emits X. The
three disagree, and the disagreement only shows up after tapeout.

This matters because the emulator *will* stall fetch:
`construction-plan.md:165` — the Time family includes *"Wait cycles, wait
level/edge with timeout"*, and *"Wait stalls control, not engines."* During a
stall the fetch stage deasserts `enable`. If the output did not hold, the
instruction register would latch garbage on every stall cycle.

**Hold is therefore required of every backend, including the flop fallback and the
behavioural model.** A macro that cannot hold is not a valid backend for this
primitive.

### 4.2 Read latency 1 — the pipeline consequence

`construction-plan.md:181` — *"First use a synchronous-read memory abstraction
with an explicit latency."*

Latency 1 forces fetch and decode into separate pipeline stages. This interacts
with `construction-plan.md:163`, which requires the Flow family to *"publish cycle
counts for every path"*: branch and jump latency become a function of fetch
latency, so those published numbers cannot be finalised before this value is.

Latency is a `Config` parameter rather than a constant so the call site states it
explicitly, and so a future registered-output macro at latency 2 has somewhere to
live. **v0.1 accepts only 1 and raises on anything else** rather than silently
rounding.

### 4.3 No write mask, no byte enables

Instructions are whole 16-bit words. There is no sub-word write case anywhere in
the ISA study (`construction-plan.md:174`), and the host loader writes whole
instruction words.

Byte enables are a portability liability: many compiled macros do not offer them,
and emulating them costs a read-modify-write that this single-port shape cannot
perform in one cycle. Not offered, and should not be added speculatively.

---

## 5. Initialisation: none, and the model must be hostile about it

**Decision: contents are undefined at power-up. There is no reset port, no
initialisation file, and no zero-fill.**

The emulator states this three separate times:

- `construction-plan.md:101` — *"Do not depend on uninitialized program/data memory."*
- `construction-plan.md:186` — *"Avoid bulk reset on program RAM. Reset its validity instead."*
- `construction-plan.md:188` — *"Any ROM is a deliberate hardware implementation, not an assumed power-up file load."*

Validity is the **consumer's** concern: a separate `program_valid` flop, outside
this primitive, gates execution until a load completes. This primitive has no
opinion about it and no port for it.

### 5.1 Poison rather than X

Hardcaml's `Cyclesim` is two-state — `Bits.t` holds 0 and 1, not X — so "drives X"
is not implementable in the simulation model. The realisable equivalent is a
**poison pattern**: a deterministic, conspicuously wrong value.

The behavioural model must therefore:

1. Fill all of memory with poison at time zero, **not** with zeros. Zero-fill is
   the failure mode that works in simulation and fails in silicon, because
   firmware that assumes a cleared memory passes every test and then meets an
   uninitialised macro.
2. Drive poison on `read_data` for the cycle following a write, per section 4.
3. Use a pattern that is implausible as real data and obvious in a waveform.
   Alternating bits (`0xAAAA` / `0x5555` by word parity) is suggested so that a
   stuck output is also visible.

This is a deliberate choice to make the model *less* forgiving than the hardware,
so that dependence on unspecified behaviour fails loudly and early.

---

## 6. Out-of-range addresses

`depth` is not required to be a power of two, so `address` can encode values at or
above `depth`. Such an access is **out of contract**: the primitive makes no
promise about what is read or which location is written.

The behavioural model should flag it — an assertion or a poison return — rather
than wrap silently. A macro will do something technology-specific and nothing
useful, so no portable behaviour can be offered.

---

## 7. What this contract deliberately does not promise

Listed so that a consumer cannot acquire a dependency on an accident of the
implementation:

- Any defined value on `read_data` during or after a write cycle.
- Any relationship between contents at power-up and any prior state.
- Byte, bit or masked writes.
- Simultaneous read and write.
- Read latency other than 1.
- Defined behaviour for addresses at or above `depth`.
- Power, area or timing characteristics. Those come from a hardening run, not
  from this document.

---

## 8. Backend obligations

Three implementations must agree on sections 4 through 6:

| Backend | Status | Notes |
| --- | --- | --- |
| Behavioural model | not written | Hostile per section 5.1. The reference for equivalence testing |
| Generic flop fallback | not written | Synthesisable, no macro. The path that works if no macro is available |
| IHP CMOS5L macro | **blocked — see below** | Requires a macro that exists, is permitted, and can hold on disable |

The macro backend must not be started yet. It is not known whether a usable
CMOS5L SRAM macro exists for a Tiny Tapeout user project. What was checked in the
pinned `tt-support-tools` revision `da63c99`:

- `tech/ihp-sg13cmos5l/cells.json` lists standard cells only; no SRAM entries.
- The only `sram` match in the repository is a `SramCore` layer in
  `precheck/tech_data.py:81`, which appears in `valid_layers_gf180mcuD` — the
  CMOS5L valid-layer list has no SRAM marker layer.
- Tiny Tapeout's generated config sets seven keys and never sets `MACROS`, so a
  macro would have to be supplied through the project's own `config.json`. That
  key does survive the merge, but nothing in the tooling anticipates it.
- `cell_regexp` is used only for cell-summary reporting in `configure.py`, not as
  a precheck gate, so a non-matching macro name would not by itself fail precheck.

The PDK itself was not inspected; there is no local checkout. **Bootstrapping the
PDK resolves this question by direct inspection, which is a further reason to run
the bootstrap before building backends.** If no usable macro exists, this
primitive collapses to the flop fallback plus a good interface, and sections 2
through 6 remain correct and useful regardless.

---

## 9. Verification obligation

Concept-note open question 7 asks how to verify that simulation semantics match
the selected physical macro. The answer this contract enables:

Write one cycle-accurate test vector set directly from section 4 — the six-cycle
trace above is the seed — and run it against **every** backend. The behavioural
model, the flop fallback and any macro model must produce identical output for
identical stimulus, including the poison cycles and the hold cycles.

A backend that cannot pass that trace is not a backend for this primitive. This is
the integration test that makes the abstraction real rather than nominal.

---

## 10. Open questions

1. Should `create` return a record rather than a bare `Signal.t`, so a backend can
   expose macro-specific extras (a ready flag, a power-down port) without a
   breaking change? Deferred until a second backend actually needs one.
2. Should the primitive take a `Scope.t` for hierarchical naming, as the
   emulator's modules do, instead of `?name`? `?name` is sufficient for an
   instance name; `Scope.t` would match house style. Resolve when the first real
   instance is placed.
3. Does the emulator want 128 or 256 program words? A sweep point in
   `construction-plan.md:176`, answerable only from mapped area. `Config.storage_bits`
   exists to feed that comparison.
4. Where does `program_valid` live — in the fetch stage, or in a thin wrapper
   around this primitive that the emulator owns? This document assumes the
   consumer owns it.
