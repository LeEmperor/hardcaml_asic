# SRAM flow-feasibility decision

Status: ASIC S.3 complete with a bounded, qualified feasibility result,
2026-09-20. The exact `RM_IHPSG13_1P_256x16_c2_bm_bist` macro can survive
synthesis, placement, routing, streamout, and the complete Tiny Tapeout
CMOS5L precheck in a 6x4 project. This is not submission authorization or a
production backend: S.2 authority and timing-model questions remain open, and
the experimental LibreLane run retains Magic-only discrepancies.

## Decision

The candidate is physically integrable enough to justify retaining S.4 as a
conditional future implementation task rather than deferring it for lack of flow
feasibility. S.4 remains gated on S.2, especially exact-target eligibility and an
authoritative decision on connecting both `VDD!` and `VDDARRAY!` to `VPWR`.

This decision is deliberately narrower than a signoff claim:

- The official TT precheck at frozen support revision `cfa06bae...` passes every
  check, including SG13CMOS5L KLayout DRC, boundary/layer/cell-name checks, and
  public pin geometry. Its own Magic DRC and KLayout FEOL/BEOL/offgrid steps are
  gated to `sky130A`/`gf180mcuD`, so for this technology the PDK KLayout deck is the
  only geometric DRC it runs.
- LibreLane's Magic checks still report four long-run spacing markers and two
  extraction overlap markers. The four spacing markers arise because this run set
  `MAGIC_DRC_USE_GDS: 0`, so Magic's `widespacing *obsm2/*obsm3` rules treat the
  macro's blanket LEF obstruction as wide metal; the PDK KLayout deck implements the
  same `M2.f`/`M3.f` rules at the same 0.6 um value on the real GDS and reports zero.
  The two extraction overlaps are a genuine probe defect, not a Magic artifact: both
  `VPWR` bridges are placed about 1.87 um left of their macro pins. See
  [`sram-s3-disposition.md`](sram-s3-disposition.md) for the source-backed analysis.
- Netgen reports zero differences only through LibreLane's black-box macro path.
  The generated LVS script does not read the supplied SRAM CDL, so this proves
  wrapper boundary equivalence, not transistor-level SRAM LVS. It does establish,
  from extracted layout, that `VDD!` and `VDDARRAY!` both reach `VPWR` and `VSS!`
  reaches `VGND`; because the two positive supplies are then interchangeable, netgen
  resolves them as a symmetry and does not confirm per-supply identity.
- STA has positive setup and hold slack at the configured corners. Top-level routed
  parasitics are fully annotated (zero unannotated drivers); only a macro-internal
  SPEF is absent, which the macro Liberty correctly supersedes. However, all three
  STA corners are named `nom_*`, so the config's `min_*`/`max_*` Liberty entries never
  applied and the macro was timed at `typ_1p20V_25C` in every corner. Max
  slew/capacitance violations remain, all on macro pins.

## Frozen Inputs

| Input | Identity |
| --- | --- |
| IHP Open PDK | `2bbec755dc67ca3db0261c3d6163e15735d66710`, clean |
| TT support tools used for precheck | `cfa06bae536d00282cb2fdb3d0bdeebc562c6365`, clean; immediate child of the locked `da63c992...`, adding only `SRAM.drawing` and `DigiBnd.drawing` to accepted layers |
| LibreLane | `3.1.0.dev3`, container digest `sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a` |
| Probe | TT 6x4 template, 20 ns clock, macro at `(42,81)` in `R0`, 2 um placement halo |
| Experimental supplies | `VDD! -> VPWR`, `VDDARRAY! -> VPWR`, `VSS! -> VGND`; physical feasibility only |

The standalone fixture is in `experiments/sram_flow_feasibility/`. It keeps the
SRAM observable through TT inputs and outputs and preserves the S.2a control
mapping. The PDN uses Metal4, explicit bridges to the macro's two positive rails
and ground rail, and one uninterrupted full-height public pin for each TT supply.

## Results

The behavioral fixture passed four checks covering two writes, two reads, and
disabled hold. That fixture is pre-synthesis RTL simulation against the macro's
functional model; it does not exercise the synthesized or final physical netlist, and
no gate-level simulation was run. Yosys retained exactly one
`RM_IHPSG13_1P_256x16_c2_bm_bist` and inferred zero memories.

The final physical attempt completed all 80 LibreLane stages with these material
results:

| Check | Result |
| --- | --- |
| Macro retention | 1 exact SRAM instance; 0 inferred memories |
| Detailed routing | 0 final router DRC errors; 0 disconnected pins |
| Power connectivity | 0 VPWR/VGND power-grid violations |
| Antenna | 0 violating nets and pins after repair |
| Setup/hold | 0 violations; worst setup slack 14.017 ns, worst hold slack 0.218 ns. Macro timed at `typ` in all three corners, so fast-corner hold and slow-corner setup are not established for macro paths |
| Max slew/capacitance | 8 worst-corner slew and 12 capacitance violations; unresolved limitation |
| Magic DRC | 4 markers: one `M2.f`, three `M3.f`, all at the macro boundary and all produced by the LEF-obstruction abstraction; KLayout on the real GDS reports zero |
| Magic illegal overlap | 2 `obsm4`-`metal4` markers; both `VPWR` bridges sit on the macro's Metal4 obstruction and contact their pins over only 0.23 um |
| Netgen LVS | 0 differences under black-box macro treatment |
| TT precheck | All rows pass, including SG13CMOS5L KLayout DRC and pin check |

The placement halo reduced Magic DRC from 253 markers to 4 and changed TT
precheck from 62 `M1.b` plus 20 pin errors to a complete pass. That bounded
correction isolates the remaining Magic behavior without tuning the probe into a
production backend.

## Reproduction And Evidence

Run the behavioral fixture from the repository root:

```sh
PDK_ROOT=/home/wayne/devel/jane/hardcaml_asic/.toolchain/pdk \
  bash experiments/sram_flow_feasibility/run_behavioral.sh \
  evidence/sram-flow-feasibility/behavioral
```

The final physical command was:

```sh
.toolchain/.venv/bin/python -m librelane \
  --docker-no-tty --dockerized --manual-pdk \
  --pdk-root /home/wayne/devel/jane/hardcaml_asic/.toolchain/pdk \
  --pdk ihp-sg13cmos5l --run-tag attempt-005-full \
  experiments/sram_flow_feasibility/config.json
```

TT precheck ran from `.toolchain/tt-sram-s3-cfa06bae/precheck` inside its
`default.nix` shell, with `PDK_ROOT` set to the same PDK, `PDK` set to
`ihp-sg13cmos5l`, and `precheck.py --tech ihp-sg13cmos5l` pointed at the final
GDS. The complete invocation and output are retained in
`tt-precheck-attempt-005/precheck-nix.log`.

The durable evidence is in `evidence/sram-flow-feasibility/`. Its
`attempt-005-artifacts.tar.gz` archive has SHA-256
`de16cf3d8a584e2bace6ec999651e4c73f2c2adfe28a0b042f531835e9843d43`
and was independently restored and checked as recorded in that directory's
README. Failed attempts are retained because they explain the final PDN bridge,
placement halo, and public-pin geometry rather than hiding probe evolution.

## Remaining Gate

S.3 answers local physical-flow feasibility only. Before S.4 begins, obtain the
S.2 authoritative answer for exact macro eligibility, common-supply acceptance,
and immutable submission revisions, and resolve or explicitly accept the timed
model limitation. A production integration must also establish the target's SRAM
LVS treatment and disposition the remaining Magic and electrical-rule warnings. The
finding-by-finding disposition, including two probe defects found after this decision
was recorded, is in [`sram-s3-disposition.md`](sram-s3-disposition.md).
