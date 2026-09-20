# Immediate future

Working priorities agreed in discussion on 2026-09-20. This note records the
near-term sequence; [phase_plan.md](phase_plan.md) remains the authority for task
IDs, acceptance criteria, and completion evidence.

## Current position

The project lifecycle, registered single-port RAM, TT/CMOS5L target resolution,
deterministic bundles, and external execution/results tooling are implemented.
P0–P5 and M3 have evidence and are complete. Consumer packaging, adoption,
memory synthesis, clean-staging physical reproduction, and the consolidated
user workflow are linked from the phase plan.
Protemu in the workspace's `scaf/` worktree is the first real consumer; its
committed observable design has passed a clean-staging physical reproduction.

The supported implementation path remains Tiny Tapeout `6x4`, IHP CMOS5L, and
LibreLane. Broader reuse is the direction, not a claim that arbitrary targets
or flows work today.

## 1. Completed: P5.3 / protemu P0.7

Integrate a small whole-word load/readback design in protemu using the existing
context-registered `Single_port_ram` and an **explicit `Flops` policy**.

This is flop-backed memory, not an SRAM macro. Simulation elaboration uses the
library's diagnostic behavioral model; implementation elaboration uses its
synthesizable flop storage. SRAM availability and backend implementation belong
to the separate S investigation and do not block this task.

The consumer owns validity, bounds checks, and access gating. Demonstrate:

- Whole-word writes and one-cycle reads.
- Disabled-output hold and rejected/disabled accesses having no unwanted effect.
- Consumer behavior independent of unwritten data and unspecified post-write or
  invalid-access outputs; validity/reset handling must not assume memory clears.
- Correct resource shape, stable identity, and explicit flop selection in the
  emitted manifest, with simulation and synthesis sources kept separate.
- Mapped synthesis through the pinned CMOS5L flow, with area/cell counts and
  checks for unresolved instances and synthesis errors linked to build/run IDs.

If protemu P3.1a's contract-port consumer is available, reuse it. Otherwise use a
focused fixture; the full CPU, firmware loader, and instruction execution are
not prerequisites. Consumer integration and evidence belong in protemu; generic
library fixes and backend conformance belong here. This task requires mapped
synthesis, not a new full physical run.

Completed 2026-09-20 using protemu's 256x16 P3.1a consumer: behavioral and
explicit-flop integration checks pass and pinned CMOS5L synthesis mapped 16,294
cells at 349,314.9408 um^2 with no unresolved instances or synthesis errors.
The consumer record is
[`2026-09-20-p0.7-memory-synthesis.md`](../../scaf/tinytapeout/reports/2026-09-20-p0.7-memory-synthesis.md).
Implementation and evidence cleanup landed at protemu `8d3ada1`; P5.3 is closed.
The complete historical input bundle is preserved. Its ABC delay estimate is
qualified as unusable timing evidence; the mapped cell/area result remains the
P5.3 cost evidence.

## 2. Make shared flow tooling consumable without copying it

Protemu currently vendors `phase4.py`, `report.py`, and `archive.py` under
`adopted_*` names. Establish a versioned CLI/distribution boundary for these
shared tools, building on the existing bundle and run formats.

Consumers supply their bundle, toolchain locations, verification inputs, and
output/archive locations. Shared tooling owns flow invocation semantics and
result interpretation. Consumers retain design-specific build and verification
commands. Keep provisioning explicit and separate from elaboration/emission.

Acceptance: protemu upgrades the shared tooling through a recorded dependency
update rather than synchronizing Python copies. A generic scheduler or
Workbench integration is not needed to deliver this.

## 3. Completed: P5.4 clean-staging physical reproducibility

Completed 2026-09-20 from committed protemu `8d3ada1` in a detached clean
worktree, using locked `hardcaml_asic` `a257424` from an isolated package prefix.
Observable bundle `85729c18...` / run `ccecd9ed...` completed full hardening,
three-corner timing, physical checks, all nine TT prechecks, and gate-level
simulation. The complete bundle was archived, restored independently, and
revalidated without a sibling path or generated-input edits. Evidence is the
consumer's [P0.5c record](../../scaf/tinytapeout/reports/2026-09-20-p0.5c-clean-staging-physical.md)
and [archive](../../scaf/flow_results/20260920-081325-ccecd9ed/README.md).
The earlier dirty-input physical run remains historical evidence; its identity
is not treated as the clean build's identity. Memory physical feasibility and
SRAM support remain separate.

## 4. Completed: P5.5 and the initial M3 workflow

[`usage.md`](usage.md) is now the primary path: install/pin, declare, simulate
resources, emit, provision explicitly, execute, collect, interpret, archive, and
restore. It records memory policy, common diagnostics, supported capabilities,
and the consumer P5.3/P5.4 evidence without replacing specialist references.

The standing execution guide is `flow.md`; historical P4 evidence remains in the
phase plan rather than becoming the onboarding route. P5.5 closes P5 and M3.

## 5. Measure memory costs and investigate SRAM separately

After the small consumer memory integration, measure representative protemu
memory shapes for mapped area/timing, then physical feasibility where useful.
Use those results to guide memory sizing and further backend work.

The SRAM investigation should first produce a supported-or-deferred decision
backed by macro availability, exact shape/behavior, required collateral, target
permission, and a minimal flow feasibility probe. Only then implement an exact
macro mapping and run contract/flow conformance. Do not infer support from PDK
presence or a `MACROS` configuration hook.

Before broadening public backend-authoring APIs, address the current
field-order-sensitive S-expression matching of resource contracts. This is a
follow-up API concern, not a prerequisite for explicit-flop P5.3.

## Following the initial milestone

Prefer a second real consumer to speculative framework expansion. Use it to
identify remaining protemu assumptions; then exercise portability with another
target or flow when a concrete project needs it. Additional resources,
commercial adapters, and Workbench integration remain need-driven work.
