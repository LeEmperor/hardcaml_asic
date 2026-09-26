# SRAM flow-feasibility evidence

This directory preserves the bounded ASIC S.3 probe of
`RM_IHPSG13_1P_256x16_c2_bm_bist`. The decision and interpretation are in
[`../../docs/sram-flow-feasibility.md`](../../docs/sram-flow-feasibility.md).

## Attempts

- `behavioral/run.log`: two writes, two reads, and disabled-output hold passed.
- `attempt-000-config.log`: Docker TTY allocation failed.
- `attempt-001-config.log`: a duplicated `pdk_dir::` prefix failed.
- `attempt-002-config.log`: configuration and Verilator lint passed.
- `attempt-003-full.log`: the upper `VDDARRAY!` bridge did not reach its stripe.
- `attempt-004-full.log`: the extended bridge completed the flow, but zero macro
  placement halo caused 253 Magic DRC markers and TT precheck failed with 62
  `M1.b` markers and 20 power-pin errors.
- `attempt-005-full.log`: the bounded final probe used a 2 um placement halo and
  one full-height public Metal4 pin per supply. It completed all 80 flow stages;
  LibreLane returned failure for four Magic DRC markers and two Magic extraction
  overlap markers.
- `tt-precheck-attempt-004/` and `tt-precheck-attempt-005/`: complete logs and
  copied reports. Attempt 005 passes every TT precheck row, including the IHP
  KLayout DRC and pin check.

## Archive And Restore

`attempt-005-artifacts.tar.gz` contains the standalone inputs, all attempt logs,
both precheck records, selected synthesis/PDN/STA/DRC/LVS reports, and final GDS,
LEF, Liberty, netlist, SDC, SDF, and SPEF views. It deliberately omits rebuildable
LibreLane intermediate databases.

The archive digest is recorded in `attempt-005-artifacts.tar.gz.sha256`. It was
independently extracted under `/tmp/opencode/sram-s3-restore-20260920` without
using the ignored run directory. The restored files had these hashes:

```text
780273ccf64f0bd475a31fac381d4abd4b8a149ca98ddbfcde3e5162cde50607  experiments/sram_flow_feasibility/config.json
40c666ccc5688b9d942571fce0b82a8a29a7c820e083828e2b2ff2527faa0f4f  experiments/sram_flow_feasibility/runs/attempt-005-full/final/gds/tt_um_sram_probe.gds
cafaae860240a97b5ed99ceda53ad0c05d4e4adb6b43eca30edda431ce4d5f4b  evidence/sram-flow-feasibility/tt-precheck-attempt-005/results.xml
```

The exact external inputs remain separately provisioned by revision: IHP Open
PDK `2bbec755dc67ca3db0261c3d6163e15735d66710`, TT support tools
`cfa06bae536d00282cb2fdb3d0bdeebc562c6365`, and LibreLane `3.1.0.dev3`.
