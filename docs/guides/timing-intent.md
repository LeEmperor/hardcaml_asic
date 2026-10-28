# Declare and inspect narrow timing intent

PT.7 extends the existing `Timing` declaration and generated bundle SDC. The first
qualified subset is scalar synchronizer stages, one rising primary `clk`, exact
input bits/scalars, and selected CMOS5L mapped reset flops. It does not insert
registers or alter latency/reset behavior.

## Declare existing hardware

Define `Timing.Stage.create ~id ~chain ~index` references, with contiguous indices
from zero and at least two scalar stages per chain. During design construction,
register each existing register signal:

```ocaml
Elaboration.Context.register_timing_stage_exn context ~stage ~q;
```

Registration attaches a reserved Q anchor and Yosys `keep=1`. Resolution validates
the actual circuit, primary clock, scalar register kind, absence of enable/clear,
exact registration inventory and direct predecessor-Q/downstream-D connections.
The attribute is preservation intent; successful native mapping is separate evidence.

Use `Timing.create ~input_delays ~output_delays ~stages ~exceptions ()` in
`Project.create`. Existing two-field Timing record literals need migration to
`Timing.create` (or explicit new empty `stages`/`exceptions` fields). `Timing.empty`
retains no timing exceptions. Existing min/max I/O delay semantics are unchanged.

Supported exception constructors:

```ocaml
Timing.Exception.async_capture
  ~id:"capture_input" ~reason:"Reviewed asynchronous input assumption"
  ~source:(Timing.Port.bit (Timing.Port.input "ui_in") 0)
  ~first_stage;

Timing.Exception.async_reset
  ~id:"reset_controls" ~reason:"Explicit external reset-control waiver"
  ~source:(Timing.Port.input "rst_n") ~targets:reset_stages;
```

Each ID is unique and each reason nonblank. Capture targets exactly one index-zero
data pin. Reset targets enumerate only the intended asynchronous-control pins,
including later stages if appropriate to the declared hardware. The supported reset
subset is externally active-low/reset-to-zero. **This deliberately excepts timing
checks at those asynchronous controls; it is not proof that reset release is safe.**
Downstream data paths and other reset fanout are outside that scope. Review reset
protocol and recovery/removal assumptions before adopting a waiver.

See the complete public consumer in
[`timing/timing_project.ml`](../../../hardcaml_asic_example/timing/timing_project.ml).
No CDC, bus-coherence or metastability adequacy is inferred from these declarations.

## Exact mapped resolution

The identity-covered manifest `timing_intent` records requested intent separately
from tool results. Generated SDC resolves **all** endpoints before applying any
exceptions. Native full-name equality and exact cardinality checks reject empty,
ambiguous, merged, renamed/optimized-away and unsupported endpoints.

The initial pin table supports `sg13cmos5l_dfrbpq_{1,2}` and
`sg13cmos5l_dfrbp_{1,2}` with noninverting Q, D, CLK and RESET_B. Source/clock/reset
tracing accepts direct wiring or up to eight whitelisted noninverting CMOS5L buffers.
Unknown transforms, constants, inversion, wrong inputs and disconnected nets fail
clearly. Interstage data connections must remain direct. Other cell families and
post-PNR transforms are not qualified by this slice.

Missing resolution never becomes a warning-and-skip waiver. Command-completed audit
events mean `set_false_path` returned; they do not prove exhaustive path effect.

## Inspect retained audits

```sh
hardcaml-asic-flow timing-intent-inspect "$AUDIT_DIRECTORY" --json
```

Public API:

```ocaml
Hardcaml_asic_execution.Timing_intent_evidence.inspect ~directory ()
(* (Evidence_json.t, string) result *)
```

This is read-only inspection of a **standalone synthesized-netlist STA audit**, not
an ordinary coarse run/checkpoint. It probes no PDK, runs no tools and rewrites no
evidence. Capability: `timing_intent_evidence1`. The
[schema-1 producer contract](../development/pt7-evidence-handoff.md) specifies all
required retained inputs, process/version receipts, report roles and reader bounds.

Inspection verifies build identity, selected bundle-envelope cross-links, complete
SDC hash, current generated Tcl replay, exact build/audit/stage/producer/corner and
source hashes. It separates `requested`, `resolved` (`producer_reported`) and
`applied` (`command_completed`). Recorded process provenance is not cryptographic
producer authentication or proof of which source compiled a constructor.

**Exit codes in this initial implementation:**

- **1:** structurally valid audit, but native coverage remains `unavailable`.
- **2:** invalid query, missing/corrupt/inconsistent or unsupported evidence.
- There is currently **no passing coverage outcome**. Do not turn exit 1 into pass.

Native exception, unconstrained and downstream reports are retained/hash-checked
but not interpreted as exhaustive coverage. The qualified OpenSTA 2.7.0 build lacks
`report_exceptions`; its unsupported-command report remains visible. The current
reader also replays its current Tcl serializer, so older development audits can
reject after a renderer correction; use their immutable provider for historical
inspection. Stable cross-renderer replay is not promised by schema 1.

## Accepted boundary

The [fresh example r3 evidence](../../../hardcaml_asic_example/docs/pt7_timing_final.md)
and [independent review](../development/pt7-final-review.md) demonstrate actual
Yosys mapping and OpenSTA consumption of unmodified bundle SDC for scalar and bit
sources. Five original stages survive. Three downstream setup/hold path samples
remain timed, with setup **+19.432287 ns** and hold **−0.044244 ns (violated)**.
This is sampled timing preservation, not closure. Graph and provenance negatives
have passing positive controls and retained intended diagnostics.

Ordinary-flow evidence integration, interpreted native coverage, other corners,
post-PNR preservation, and consumer-specific review remain in the
[PT.7 queue](../phase_plan.md#pt7--synchronizerreset-aware-timing-declarations).
No historical SRAM run proves these new declarations were applied.
