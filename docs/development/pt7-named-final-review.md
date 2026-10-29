# PT7 named synthesis — final independent bounded review

2026-10-29. Reviewer A. **No blocker found for the stated fresh macro-free named
synthesis + linked default-corner native STA slice.** R1/R2/R3/R2S/R4 evidence findings
are closed by focused independent controls; see [evidence review](pt7-named-evidence-review.md).
No EDA, broad suite, provider/config/Git change or B source edit was performed here.

## Actual products reviewed

Read C's `hardcaml_asic_example/docs/pt7named_native_final.md` and
`acceptance/pt7named/native-closeout-final-03/acceptance.json`, then checked referenced
raw execution, publication, checkpoint, State, native process/version, source/log,
timing-witness and launch records. Ran fresh corrected-reader inspection/report/
source queries against both **original exact execution paths**.

| | Area | Delay |
| --- | --- | --- |
| Workspace | `area-run-final-04` | `delay-run-final-03` |
| Attempt | `cb5e7cd92dbf43b4a6c00a74b61c6d72` | `9374823306a64897959e1b2295f52c84` |
| Plan | `85b949035d025689a14f72b0698440becc52224fdb785e710d16cd53d9d73687` | `673350dd8606ec6c8be49385eb8f109780dd1aae3df0452980efc2a8d94b7888` |
| Bundle | `d102a1866f7033be317a96ef01ec4ade0f3074f862d7ba2bdecdafaf7b160669` | `b778f25e704354c1bc7084b4de69076378fc084b2c8820dc6c3dede8c34ecdce` |
| Checkpoint | `ce398522bace78e0f4b0249826f662ab7dce5d574f903d0c36d8ff6add78e84d` | `9b72f1aeb191a967e792e6dfb8ef5a3fbaabc8e815b94569c202aa51a58ccc62` |

Original execution provider: `ce6be246fafa4d0dbe1dd00da980482b`, source snapshot
`acbd7ca972fba8c3f98473fc47bd099b5ce79d82ac97f8774e1a3601f06b66d5`.
Seven current runtime/lifecycle/bridge/helper source files byte-match that captured
provider's installed sources. The corrected reader source is separately identified
by SHA256 `1717a6813d9b299895be6c5f371ff360b610b7b94e37b2ec080f16f8ea685676`;
reader correction is not attributed as a new native execution or source authentication.

## Independently verified facts

- Both executions completed/0 with one exact synthesis occurrence/checkpoint. Their
  immutable publications bind **Running** occurrences and original `execute_segment`
  requests, exact methodology/plan/expectation and published checkpoint identities.
- Native `corners/state_in.json` equals each promoted checkpoint State, and request
  `state_path` is that checkpoint's actual `state.json`. All **seven checkpoint
  files** still match C's pre-STA hashes; all **168 run files/profile** preserve hash,
  size and mtime across this review's public queries. No state/checkpoint was replaced.
- Early expectation snapshots are mode0400 and match receipt/preflight/prepared
  records and finalized expectations. Their original reference hashes validate.
- Fresh inspection exits1/completed/unavailable. Fresh **entire report JSON** equals
  C's original report and contains the exact inspected timing value; source API
  returns precisely the same **1584 verified sources/profile**. All **1062 declared
  alias rows** retain exact checkpoint external keys, roots, targets, sizes and hashes.
  No canonical-target substitution or source omission was used.
- Public native inspection verifies **six stored exception relations**, **seven
  diagnostic categories**, **12 endpoints**. C retains the original five resolved
  stages. Representative raw native SDC selects `tt_um_pt7_timing` and20ns clock;
  raw log receipt precedes resolution/native completion and enclosing completion.
- Actual native version/process evidence is OpenSTA **2.7.0**, exit0, with argv
  `sta -threads 1 -no_splash -exit <retained driver>`. The two ordered Liberty copies
  match C's hashes (`34163f3e…`, `e6b5adf1…`) and declare `time_unit : "1ns"`.
- Each profile's three raw downstream max witnesses quote **+19.432287ns (MET)**;
  its three min witnesses quote **−0.044244ns (VIOLATED)**. Exact report hashes and
  C's quoted line numbers/text match. Negative hold is preserved, not waived.
- Checked **21 inventoried launch records/profile**:18 main preflight probes,
  synthesis, publication validation and linked STA. Tool-running Docker argv has
  exactly one `--cpus=6` and the pinned `d109140b…` image. Work timeouts are600s;
  preflight documentation/receipts specify20s. Linked transport is workers6/STA1;
  effective OpenROAD/STA threads and actual STA argv are1. Transport/process success
  and cleanup agree. These are recorded resource limits, not OS concurrency attestation.

## Retained independent verification

Script: `/tmp/opencode/pt7-a-native-final-closeout.py`.
Products: `/tmp/opencode/pt7-a-native-final-review-lg47ifhl/` with pinned reader
binaries, per-profile original-path query outputs, raw-check summary and run-tree
snapshots. All six actual read-only queries passed. Original closeout SHA and runtime
source comparison remain unchanged. Focused R4 and prior-case controls are separately
retained under `/tmp/opencode/pt7-named-evidence-review-0byhl1zj/`.

**Factual boundary:** C's two original public named synthesis/STA executions are
accepted for this bounded path-bound slice; this review launched none. Only the
default `nom_typ_1p20V_25C` corner executed, despite three configured corners. No P&R,
post-PNR/all-corner qualification, exhaustive exception effects, reset-release/CDC
adequacy, timing closure, named archive/export or relocated runnable-checkpoint
claim follows. Provider/source history and previous failed attempts stay preserved.
