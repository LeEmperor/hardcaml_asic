# SRAM capability checkpoint

Status: ASIC S.1, S.2a, and S.3 complete; bounded S.2b public-source research is
complete and partially resolved, 2026-09-20. S.3's residual findings were reviewed
finding-by-finding on 2026-09-20 and its qualified closure was upheld; see
[`sram-s3-disposition.md`](sram-s3-disposition.md). S.3 establishes qualified local
flow feasibility, but S.2 remains open on exact macro eligibility, accepted
common-supply mapping, final submission pins, and timed-model evidence. SRAM
backend support remains unimplemented. This track does not block or reopen
P-series or M3 closure.

## Gate status

| Gate | Status | Evidence or outstanding question |
| --- | --- | --- |
| S.1 inventory | **Complete** | [`sram-candidate-investigation.md`](sram-candidate-investigation.md) records the locked inputs, Apache-2.0 terms and unresolved restrictions, exact 256x16 one-port shape, controls and power names, functional/timing Verilog, three Liberty corners, LEF, GDS, CDL, and representative hashes |
| S.2a model behavior | **Complete** | [`sram-model-conformance.md`](sram-model-conformance.md): exact functional model passed 23 directed vectors and 86 checks; timed source compiles, but Icarus cannot execute its delayed timing-check signals, so actual timing behavior remains unestablished |
| S.2b target/pin/power research | **Partially resolved; research complete** | [`sram-target-compatibility.md`](sram-target-compatibility.md): exact March 2027 6x4 target and mutable template/action/tool refs established; observed support head `f6bf5c58...` includes required marker fix; macro voltages match the 1.20 V TT target. Exact macro eligibility, authoritative `VDD!`/`VDDARRAY! -> VPWR` commoning, final immutable submission refs, and SRAM LVS treatment remain unresolved |
| S.2 overall | **Open** | S.2a functional evidence does not answer S.2b or establish timing-model conformance under a simulator supporting the exact delayed timing checks |
| S.3 flow feasibility | **Complete; qualified feasible result, closure upheld on review** | [`sram-flow-feasibility.md`](sram-flow-feasibility.md): the exact macro remained one hard instance, routing/power/antenna/setup/hold checks completed, and all TT precheck rows passed under frozen support revision `cfa06bae...`. [`sram-s3-disposition.md`](sram-s3-disposition.md) dispositions each residual: the four Magic DRC markers are LEF-obstruction artifacts contradicted by the PDK KLayout deck on the real GDS; the two extraction overlaps are a real probe defect (both `VPWR` bridges misplaced ~1.87 um, 0.23 um pin contact); LVS is macro-black-box only but does confirm both positive supplies reach `VPWR`; the absent parasitics are macro-internal only and correctly superseded by Liberty. One new defect: all three STA corners matched `nom_*`, so the macro was timed at `typ` in every corner |
| S.4 backend | **Gated on S.2** | No production wrapper, mapping, or registered collateral exists. S.3 establishes local feasibility but not target permission, authoritative dual-supply commoning, complete SRAM LVS, or timing-model conformance |

## Inspected inputs

| Input | Revision/version and observed state |
| --- | --- |
| IHP Open PDK | `2bbec755dc67ca3db0261c3d6163e15735d66710`; primary `.toolchain/pdk` clean; `../scaf/tinytapeout/pdk` at the same revision with only untracked generated `ihp-sg13cmos5l/SOURCES` |
| TT support tools | `da63c9927411e3aca350977d653d24bbf5bca972`; both installed checkouts clean |
| LibreLane | locked and installed in the primary repo as `3.1.0.dev3`; no `../scaf/tinytapeout/.venv` installation available |
| Official layer fix | `cfa06bae536d00282cb2fdb3d0bdeebc562c6365`; GitHub commit metadata confirms parent `da63c992...` and the one-line valid-layer change |
| Isolated S.3 support checkout | `.toolchain/tt-sram-s3-cfa06bae` at `cfa06bae536d00282cb2fdb3d0bdeebc562c6365`, clean after the official layer fix; used only for the experimental precheck |
| Official mutable refs, observed 2026-09-20 | Template `cmos5l` -> `b86a2a...`; action `ihp-cmos5l` -> `341265...`; support tools `ihp-sg13cmos5l` -> `f6bf5c58...`, whose parent is `cfa06bae...`. These observations are not permanent immutable submission pins |

Primary evidence paths are:

- `.toolchain/pdk/ihp-common/README.md`
- `.toolchain/pdk/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram`
- `.toolchain/pdk/ihp-sg13g2/libs.ref/sg13g2_sram/{doc,verilog,lib,lef,gds,cdl}`
- `.toolchain/tt/precheck/tech_data.py` and `.toolchain/tt/precheck/precheck.py`
- `toolchain.lock`, `../scaf/tinytapeout/asic-dependencies.lock`, and
  `../scaf/tinytapeout/toolchain.lock`

## S.3 verification record

The bounded final probe completed all 80 LibreLane stages and passed the full TT
precheck. Yosys retained exactly one hard SRAM and inferred zero memories; final
routing and power-grid connectivity had zero violations, antenna repair cleared
all markers, and setup/hold checks had positive slack. The result remains
qualified by four Magic DRC markers, two Magic extraction overlaps, max slew/cap
violations, absent macro parasitics, and black-box-only SRAM LVS.

The 2026-09-20 disposition review verified the archive digest and all three recorded
restoration hashes, re-confirmed the PDK, baseline, and isolated support-tool
revisions, and traced every residual finding to its source. It upheld qualified S.3
closure against S.3's own acceptance criterion and required no `phase_plan.md` status
change. It did find two probe defects not in the original record — the misplaced
`VPWR` bridges and the corner-glob collision that bound the macro to its typical
Liberty in all three STA corners — plus two evidence gaps: the behavioral fixture is
RTL-only, and the archive omits the routed DEF, P&R netlist, and extracted SPICE
needed to reproduce the DRC/extraction/LVS analysis. Both defects are probe
configuration, not candidate properties, and neither overturns feasibility.

Standalone inputs, complete attempt logs, copied precheck reports, selected flow
reports/final views, a checksummed 1.30 MB archive, and independent restoration
hashes are under `evidence/sram-flow-feasibility/`. The detailed decision and
exact assumptions are in [`sram-flow-feasibility.md`](sram-flow-feasibility.md).

## S.2a verification record

The exact functional model was compiled and executed through the experimental
wrapper. The timed branch and controlled simulator diagnostics were compiled and
run separately. No physical tool was run.

- `experiments/sram_model_conformance/run.sh --pdk-root
  /home/wayne/devel/jane/hardcaml_asic/.toolchain/pdk --output-dir
  evidence/sram-model-conformance`: functional compile/run passed with 23 vectors,
  86 checks, and zero failures; intentional-failure run returned status 1; both
  timed compiles passed and both timed executions exposed Icarus's undriven
  delayed-signal limitation.
- `/usr/bin/iverilog` and `/usr/bin/vvp`: Icarus Verilog 12.0 stable. The
  `-gspecify` diagnostic applied the requested 1 ns path delay but did not fire a
  deliberately violated setup notifier.
- Input validation re-established clean PDK revision `2bbec755...`, matching
  model/data/Liberty hashes, and the tracked CMOS5L-to-SG13G2 SRAM symlink.
- Full commands, flags, versions, hashes, checkout state, compile logs, and run
  logs are in `evidence/sram-model-conformance/`.

The earlier S.1 verification remains:

- `git status --short --branch` in both repositories: pre-existing concurrent
  changes observed and preserved; no `scaf` file changed.
- `git rev-parse HEAD`, `git status --short`, and `git remote get-url origin` in
  both PDK and support-tools installations: revisions matched locks; the primary
  installations and both TT installations were clean; the `scaf` PDK had only
  the generated untracked `SOURCES` file noted above.
- `git ls-files -s ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram` plus `readlink`:
  confirmed the tracked relative symlink to the SG13G2 SRAM data.
- Targeted text searches and file reads of the candidate datasheet, Verilog/shared model,
  Liberty, LEF, CDL, common README, and precheck sources: confirmed the inventory
  claims and pinned layer-list behavior.
- `git ls-files ... | wc -l`: confirmed 244 SRAM deliverables: 30 each CDL,
  documentation, GDS, and LEF; 90 Liberty; 34 Verilog.
- `sha256sum` over the exact candidate views/model: all recorded hashes in the
  investigation matched, including macro Verilog `645c4757...` and shared model
  `d0a6258f...`.
- `.toolchain/.venv/bin/librelane --version`: reported `LibreLane v3.1.0.dev3`.
- HTTP inspection of GitHub PR 187, commit API, and immutable patch for
  `cfa06bae...`: confirmed merge status, exact parent, and added layer names; the
  commit object was unavailable in the pinned local checkout and was not fetched.
- `git diff --check -- docs/sram-candidate-investigation.md
  docs/program-memory-contract.md docs/phase_plan.md docs/sram-status.md`: passed.

Files added or changed by S.2a are `experiments/sram_model_conformance/*`,
`evidence/sram-model-conformance/*`, `docs/sram-model-conformance.md`,
`docs/sram-candidate-investigation.md`, and this checkpoint. Shared code, RAM
interfaces/tests, phase-plan task state, locks, installed checkouts, and consumer
files affected: none.

## Next bounded task

Seek one consolidated authoritative clarification of the exact macro's
competition eligibility, commoning both 1.2 V macro supplies onto `VPWR`, and
final immutable submission refs, using the precise questions in
[`sram-target-compatibility.md`](sram-target-compatibility.md). Note that physical
connection of both supplies to `VPWR` is now confirmed from extracted layout; what
remains unresolved is whether that commoning is electrically accepted, which is not
the same question.

The locally resolvable follow-ups are ordered in
[`sram-s3-disposition.md`](sram-s3-disposition.md); the first is correcting the two
`VPWR` bridge rectangles in `pdn_cfg.tcl`. The completed S.3
probe establishes local physical feasibility but not submission readiness. Do
not begin S.4 backend implementation until S.2 permits it. There is no P6
dependency; P6.5 only owns later provisioning and revision enforcement.
