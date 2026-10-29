# Qualify timing-intent preservation and timing closure after place-and-route

**Issue draft — not yet published to GitHub.** Check for duplicates and publish
after GitHub CLI authentication. [phase_plan.md](../phase_plan.md) owns the queue.
Depends on the corner/model policy and diagnostics from
[all-corner pre-PNR qualification](ticket-all-corner-timing.md); implementation
planning may proceed independently, but final acceptance must use reviewed corners.

**Bounded acceptance completed 2026-10-29:** the first coarse full attempt passes
routed timing at the three configured cell-PVT corners, with one nominal RC view,
unchanged constraints/five registers, nine combinational repair delay cells,
ordinary physical/external checks and exact portable source replay. See
[closeout](timing-physical-qualification.md),
[native results](../../../hardcaml_asic_example/docs/timing_physical_full_result.md)
and [independent review](timing-physical-final-review.md). Named physical support,
other RC views and analog reset/CDC qualification are outside this accepted profile.

## Purpose and scope

Qualify the supported timing-intent example through a fresh physical flow, including
clock-tree synthesis (CTS), routing and extracted timing. Establish whether named
physical execution needs additional preservation/resolution support before enabling
that route. This extends completed synthesis-stage PT.7; it does not reopen it.

Use the small independent example and the same explicit hardware/reset/latency
semantics. Ordinary physical repair may add combinational buffers/delay cells;
it must not silently insert registers, remove synchronizer stages, add latency or
broaden false paths. Do not restart completed SRAM physical feasibility.

## Acceptance criteria

- [ ] Write a bounded physical execution plan and explicit tool/thread allocation
  before P&R. Identify supported stage/checkpoint transitions and reject unsupported
  combinations before launch; preserve exact emitted bundle and frozen methodology.
- [ ] Retain run/build/stage/occurrence/tool/corner provenance for placement, CTS and
  routed analysis. Bind exact implementation netlists/databases, parasitics, SDC,
  libraries and producer artifacts to each claimed observation.
- [ ] Verify the original stages survive and resolve correctly after physical
  buffering/optimization. Explicitly qualify supported transforms; missing/ambiguous
  endpoints or unknown transforms fail rather than silently expanding scope.
- [ ] Verify first-stage capture and enumerated reset exceptions remain narrow;
  downstream setup/hold paths remain timed. Retain native stored scopes, diagnostics
  and bounded effect controls without claiming exhaustive path-effect classification.
- [ ] Review the physical clock arrival differences and extracted data delays at
  each supported corner. Diagnose hold/setup failures rather than treating pre-PNR
  ideal-clock results as final silicon behavior.
- [ ] Apply documented behavior-preserving hold/setup repair if necessary; retain
  before/after reports, inserted-cell inventories and unchanged architectural stage
  counts. Recheck setup after hold repair and hold after setup changes. Do not lower
  uncertainty/loads or waive downstream paths merely to obtain a pass.
- [ ] Establish setup/hold closure for the explicitly qualified physical profile,
  or retain a failed result with a concrete blocker. A successful tool process is
  not sufficient. Preserve appropriate native physical/electrical acceptance checks.
- [ ] Verify public report/inspection/source linkage at the physical stages and
  independently review the actual evidence. Keep timing correctness separate from
  analog metastability/MTBF, reset-release protocol and consumer CDC correctness.

## Baseline to investigate

The synthesis-only specimen has direct register-to-register paths with ideal clocks
and zero reported interstage net delay. Three downstream hold checks report
**−0.044244 ns**, substantially influenced by the existing **0.25 ns uncertainty**.
This is not proof that routed hardware fails or will automatically repair itself.
Clock-tree arrival differences can improve or worsen hold, and wire/cell delay
changes affect both hold and setup. Keep the original reports unchanged.

References: [named native acceptance](../../../hardcaml_asic_example/docs/pt7named_native_final.md),
[independent review](pt7-named-final-review.md),
[bounded declarations](../guides/timing-intent.md).

## Explicit exclusions

No Protemu changes/qualification, Workbench polish, named archive project, exhaustive
native per-check instrumentation or SRAM redesign. Those require separate concrete
scope. A period/frequency reduction is not a general repair for same-edge hold
violations. No P&R is authorized merely by creating this ticket.
