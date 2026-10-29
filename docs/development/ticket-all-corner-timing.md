# Qualify timing-intent evidence across all supported pre-PNR corners

**Issue draft — not yet published to GitHub.** The CLI lacks authentication in the
current session. Check existing issues for duplicates before publishing. This is a
follow-up specification; [phase_plan.md](../phase_plan.md) remains the active queue.

**Implementation outcome, 2026-10-29:** all three configured cell-PVT corners now
have fresh pre-PNR and routed evidence for the bounded example. See
[qualification closeout](timing-physical-qualification.md) and
[actual result](../../../hardcaml_asic_example/docs/timing_physical_full_result.md).
The unchanged uncertainty budget is explicitly retained as an assumption, not
new board-clock qualification. Reset-effect/adequacy and exhaustive per-check
coverage remain unestablished; those are not claimed by empty native diagnostics.
Original acceptance criteria below remain the draft specification, not a second queue.

## Purpose and scope

Extend accepted default-corner synthesis-stage timing-intent qualification to the
configured fast/typical/slow CMOS5L corners using `hardcaml_asic_example`. This is
separate from the completed bounded PT.7 library/flow feature. No P&R is required.

Reuse the current declarations, native-v2 producer, coarse/named execution linkage
and public evidence APIs. Keep requested corners, actually executed corners and
any native deduplication/aliasing distinct. Do not infer execution from config lists.

## Acceptance criteria

- [ ] Explicitly select the supported analysis corner set and record original and
  effective configuration. Retain exact loaded library bytes/hashes, native process
  versions/results, run/build/stage/occurrence identities and raw reports per corner.
- [ ] Verify exact endpoint resolution, preservation of the original five stages,
  narrow native stored exception relations, all seven diagnostic categories and
  downstream min/max timing at each executed corner. Missing/failed corner evidence
  cannot become an all-corner success.
- [ ] Inspect reset recovery/removal check availability and explicitly distinguish
  the enumerated waived controls, observed check effects and unsupported analysis.
  Do not infer reset-release safety or metastability adequacy from STA.
- [ ] Record setup/hold violations and their source paths. Explain the current
  direct register-to-register hold witnesses and the contribution from uncertainty,
  library checks, derates, clock assumptions and modeled interconnect.
- [ ] Review the basis of the current **0.25 ns clock uncertainty**, including whether
  setup/hold assumptions should differ. Preserve the existing baseline. Any revised
  policy needs an engineering rationale and separate evidence, not a reduction just
  to remove violations. Without a justified revision, keep the existing budget.
- [ ] Test wrong-corner/library substitutions, unexecuted/failed corners, repeated
  producer ambiguity and truthful alias cases. Public inspect/report must agree and
  preserve unavailable exhaustive coverage and original schema compatibility.
- [ ] Independently review actual example results and record supported scope,
  failures/skips and limits. All-corner evidence delivery does not require pretending
  an unrepaired pre-PNR hold violation is timing closure.

## Baseline and interpretation

Named area attempt `cb5e7cd92dbf43b4a6c00a74b61c6d72` and delay attempt
`9374823306a64897959e1b2295f52c84` have three downstream hold witnesses each at
−0.044244 ns under `nom_typ_1p20V_25C`. The actual report decomposes one as:

- Launch-register clock-to-Q / data arrival: **0.199838 ns**.
- Modeled interstage net increment: **0 ns**; both clocks ideal.
- Clock uncertainty: **0.250000 ns**.
- Library hold adjustment: **−0.005918 ns**.
- Effective earliest allowed arrival: **0.244082 ns**.
- Hold slack: **0.199838 − 0.244082 = −0.044244 ns**.

This is a real failure under the current model, not a measured routed-chip delay
or an analog metastability finding. Other native min-report samples are worse;
three declared witnesses are not an exhaustive worst-path summary.

References: [named acceptance](../../../hardcaml_asic_example/docs/pt7named_native_final.md),
[native review](pt7-named-final-review.md), [timing guide](../guides/timing-intent.md).

## Boundaries and dependency

No Protemu adoption, Workbench changes, SRAM feasibility restart or arbitrary new
constraint system. Preserve prior evidence/provider selections. Use explicit Dune
limits, serialized checkout builds and a maximum 20-job shared allocation. No EDA
or implementation is launched by filing this issue.

This produces the corner-policy baseline for
[post-PNR qualification and timing closure](ticket-post-pnr-timing.md). Insert the
published GitHub issue links into both tickets and the phase plan when available.
