# SRAM capability checkpoint

Status: ASIC S.1 and S.2a complete, 2026-09-20. S.2 remains open on target,
pin, and power permission; SRAM capability and backend support remain
unestablished. This track does not block or reopen P-series or M3 closure.

## Gate status

| Gate | Status | Evidence or outstanding question |
| --- | --- | --- |
| S.1 inventory | **Complete** | [`sram-candidate-investigation.md`](sram-candidate-investigation.md) records the locked inputs, Apache-2.0 terms and unresolved restrictions, exact 256x16 one-port shape, controls and power names, functional/timing Verilog, three Liberty corners, LEF, GDS, CDL, and representative hashes |
| S.2a model behavior | **Complete** | [`sram-model-conformance.md`](sram-model-conformance.md): exact functional model passed 23 directed vectors and 86 checks; timed source compiles, but Icarus cannot execute its delayed timing-check signals, so actual timing behavior remains unestablished |
| S.2b target permission | **Open** | Authoritative answer still required: may the March 2027 Jane Street 6x4 `ihp-sg13cmos5l` target include this PDK-distributed macro, with both 1.2 V supplies connected to the TT user grid, and which official support-tools/action revision governs submission? Licensing and accessible collateral do not answer this |
| S.2 overall | **Open** | S.2a functional evidence does not answer S.2b or establish timing-model conformance under a simulator supporting the exact delayed timing checks |
| S.3 flow feasibility | **Not established** | Pinned support-tools `da63c992...` omits `SRAM.drawing` and `DigiBnd.drawing`; its layer check rejects unlisted GDS layers. Official immediate child `cfa06bae...` adds both, but is not pinned or installed and was not exercised here |
| S.4 backend | **Gated** | No production wrapper, mapping, registered collateral, or physical integration exists; the S.2a experimental wrapper/result does not implement a backend; wait for S.2-S.3 capability evidence |

## Inspected inputs

| Input | Revision/version and observed state |
| --- | --- |
| IHP Open PDK | `2bbec755dc67ca3db0261c3d6163e15735d66710`; primary `.toolchain/pdk` clean; `../scaf/tinytapeout/pdk` at the same revision with only untracked generated `ihp-sg13cmos5l/SOURCES` |
| TT support tools | `da63c9927411e3aca350977d653d24bbf5bca972`; both installed checkouts clean |
| LibreLane | locked and installed in the primary repo as `3.1.0.dev3`; no `../scaf/tinytapeout/.venv` installation available |
| Official layer fix | `cfa06bae536d00282cb2fdb3d0bdeebc562c6365`; GitHub commit metadata confirms parent `da63c992...` and the one-line valid-layer change |

Primary evidence paths are:

- `.toolchain/pdk/ihp-common/README.md`
- `.toolchain/pdk/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram`
- `.toolchain/pdk/ihp-sg13g2/libs.ref/sg13g2_sram/{doc,verilog,lib,lef,gds,cdl}`
- `.toolchain/tt/precheck/tech_data.py` and `.toolchain/tt/precheck/precheck.py`
- `toolchain.lock`, `../scaf/tinytapeout/asic-dependencies.lock`, and
  `../scaf/tinytapeout/toolchain.lock`

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

ASIC S.2b authoritative target/pin/power requirements: establish whether the
selected submission accepts this exact macro and dual-supply connection and which
official support-tools/action pin governs it. Do not begin S.3 physical
integration or S.4 backend implementation until the capability gates permit it.
