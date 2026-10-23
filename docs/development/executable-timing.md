# Executable Timing provider contract

## Discovery and recipes

`hardcaml-asic-flow --version --json` advertises both `timing_stage1: true`
and `timing_analysis1: true`. Only the former grants a runnable Timing endpoint.
The public OCaml `Flow.Stage` includes `Timing`; `Stage.all`, fresh catalog
endpoints, `Flow.Recipe.through`, execution planning and Python
`execution_plan.resolve_stages/resolve_sequence` use this order:

```
synthesis floorplan placement cts routing timing signoff
```

New recipes have **schema_version 4**, exactly `schema_version`, `stages`, and
`initial_boundary`. Schemas 2 and 3 decode using the historical six-stage order;
they never acquire a fabricated Timing occurrence. They remain inspection
evidence; execution requires the current contiguous composition. Schema 1 coarse
plans are unchanged. Finalization validates the complete fresh sequence belonging
to the selected recipe version, including its matching publication count.
New methodology plans declare translation `recipe_schema_version: 4`; their
recipe-sensitive methodology/plan identities change accordingly. Historical
schema-3 methodology snapshots reconstruct using their original six-stage recipe
and translation bytes rather than silently upgrading their identities.

Routing ends at `OpenROAD.DetailedRouting`. Timing begins at its immediate Classic
successor `Odb.RemoveRoutingObstructions`, includes all post-route checks, fill,
cell tables and RCX, and ends at `OpenROAD.STAPostPNR`. Signoff begins immediately
after STA at `OpenROAD.IRDropReport` and ends at `Misc.ReportManufacturability`.
The actual Classic `Flow.start` API still owns ordering, gates, final snapshots
and deferred checks; STA is never invoked as a standalone shortcut. The trusted
80-step inventory and configured gates/defaults are unchanged.

Checkpoint manifests remain schema 2. Routing now advertises restart target
`timing`; Timing advertises `signoff`. The direct historical synthesis-to-placement
API is preserved. Old routing manifests/references advertising `signoff` remain
readable. Restart checks still validate exact bridge, runtime, workspace,
configuration and complete input/collateral closure. An old bridge checkpoint
cannot resume with the new bridge: preparation rejects it explicitly as
`incompatible target, tools, runtime, bridge or workspace`. Decoding a historical
backend request does not authorize executing its old Routing-to-Signoff range.

Final transported digests:

* bridge: `f22dd1074c8cd4b987bb598a4429690d053b9fdfd3e31d47e2a319a9be42460f`
* backend protocol: `eb6490db856f551ffe2ab35ea872bdc85c86801339e67a9d5bdf427238b25ae1`

## Timing evidence and identity

Historical observations remain `hardcaml-asic.timing-analysis` **schema 1**,
`stage: signoff`. New observations are **schema 2**, `stage: timing`, with the same
metric, goal, native duration and source-inventory fields. The analysis identity
is `ATTEMPT/post-pnr-sta`; occurrence identity is `ATTEMPT/implementation.timing`.
Capability `timing_stage1` also announces this schema-2 producer extension.

At successful Timing segment completion/publication, before Signoff starts, the
provider hardlinks the atomic execution summary to immutable
`EXECUTION.json.timing-source` and publishes its immutable
`.timing-analysis.json` sidecar. `execution_file` and `execution_sha256` name/hash
that exact frozen prefix, **not the later terminal execution summary**. Its
`enclosing_status` is normally `running`: it is the captured prefix's status,
not the current overall execution outcome. The main report's `execution.status`
is the authoritative current/terminal outcome. `evidence_scope` is
`immutable_timing_execution_source_not_checkpoint`.

Reports and inspection invoked on the main execution resolve that frozen source
only after checking identical attempt, plan, Timing occurrence and Timing
checkpoint reference. The snapshot is never retargeted or rewritten. Thus Timing
evidence is available during Signoff and survives Signoff failure/cancellation.
If Timing itself fails, end-of-attempt recovery can publish independently proven
native STA evidence against the terminal execution, without claiming a completed
Timing segment or checkpoint. Missing/skipped native STA cannot earn completed
analysis. A resumed Signoff-only attempt does not borrow another attempt's STA.

Segment duration/status live in `execution.occurrences` (including publication and
preparation/extraction work); `timing_analysis.duration.seconds` is **native STA
runtime only**. `timing_goal`, stage completion and final acceptance remain
independent. Report/inspection envelope schema remains 1; stage identity must be
part of consumers' captured targets/cache keys.

Finalization receipts retain the optional exact `timing_analysis` object when
present; the selected execution path/hash still identifies segment occurrences
and their full durations. The finalization receipt envelope remains schema 1.

Read-only exact inspection:

```
hardcaml-asic-flow report EXECUTION.json --json
hardcaml-asic-flow inspect EXECUTION.json --domain timing --stage timing \
  --expected-digest ANALYSIS_SOURCE_DIGEST --json
hardcaml-asic-flow inspect EXECUTION.json --domain timing --stage timing \
  --row-id ROW_ID --expected-digest INDEX_SOURCE_DIGEST --json
```

Historical schema-1 inspection uses `--stage signoff`. Index requests pin the
analysis digest; detail requests pin the returned index digest. Native source
replacement is rejected rather than silently retargeted. Reports preserve the
immutable completion facts even if a native report later disappears; inspection
revalidates native inventory bytes.

Execution examples (with the usual bundle/runtime/toolchain arguments):

```
hardcaml-asic-flow stages --through timing ...
hardcaml-asic-flow stages --checkpoint ROUTING_CHECKPOINT --through timing ...
hardcaml-asic-flow stages --checkpoint TIMING_CHECKPOINT --through signoff ...
```

## Verification and retained fixtures

No EDA flow was launched. Import-only metadata introspection verified the exact
supported image `sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a`
(LibreLane 3.1.0.dev3, Python 3.13.13), all 80 step IDs/implementations/artifact
contracts and gates/defaults. Container introspection used network disabled,
`--cpus 6`, and 30-second subprocess deadlines.

Deterministic production-bridge coverage is `@test/executable_timing/runtest`.
It checks Routing -> Timing -> Signoff, no Signoff at the Timing endpoint, no STA
on Signoff continuation, full seven-stage finalization selection, schema-2 exact
inspection, incompatible historical checkpoint rejection, Timing deferred failure
recovery, live evidence during Signoff, and stable evidence after cancellation.
The existing finalization differential suite also exercises complete seven-stage
finalization, collection and acceptance with synthetic runtime boundaries.

All invoked Dune commands use explicit `-j6`. Installed-only test branches with
nested `-j20`, and suites creating Git fixture commits, were not invoked. Selected
fixture suites have no nested Dune/EDA work. Runtime execution's ordinary resource
policy is unchanged; this validation launches only deterministic native fixtures.

To retain fresh absolute-path-bound fixtures for another consumer:

```
dune build -j6
python3 -B test/executable_timing/check.py --retain /tmp/opencode/timing-handoff-UNIQUE
```

`case-2/report.json` is full success, `case-3/report.json` is downstream Signoff
failure, `case-4/report.json` is failed Timing with independently completed STA.
Each contains exact execution/source paths, stage/analysis durations and digests.
These are deterministic fixtures, not real-tool timing/QoR measurements.

### Retained handoff from this implementation

Root: `/tmp/opencode/executable-timing-handoff-final` (absolute paths are part of
the evidence contract; consume in place). Successful full flow is `case-2`,
failed Signoff is `case-3`, failed Timing recovery is `case-4`, and live-Signoff
cancellation is `case-5`. Case 1 retains separate Routing/Timing/Signoff attempts.

Example failed-Signoff invocation:

```
_build/default/bin/flow_cli.exe report \
  '/tmp/opencode/executable-timing-handoff-final/case-3/workspace with spaces/execution-20261021T195427773317Z_b88e60f9.json' --json
_build/default/bin/flow_cli.exe inspect \
  '/tmp/opencode/executable-timing-handoff-final/case-3/workspace with spaces/execution-20261021T195427773317Z_b88e60f9.json' \
  --domain timing --stage timing --expected-digest \
  7b16ef2ae7490d5641c9bdbd219f915ddefb4860301a717115575c178acba98d --json
```

Its retained `case-3/report.json` contains:

```json
{
  "execution.status": "failed",
  "execution.plan.schema_version": 4,
  "implementation.timing.status": "completed",
  "implementation.timing.duration_seconds": 2.798826,
  "timing_analysis.schema_version": 2,
  "timing_analysis.stage": "timing",
  "timing_analysis.status": "completed",
  "timing_analysis.enclosing_status": "running",
  "timing_analysis.duration.seconds": 1.575,
  "timing_analysis.timing_goal": "pass"
}
```

Verification receipts (all passed, explicit `dune build -j6`):

* full default build;
* `@test/executable_timing/runtest`, plus the retained standalone invocation;
* `@test/ocaml-stage-preparation`: 62 API/pipeline checks;
* `@test/ocaml-segment-service`: 70 execution/publication checks;
* `@test/ocaml-stage-recipes`: 46 accepted/3210 rejected recipes, 33 drift negatives;
* `@test/execution-plans`: 168 accepted/6737 rejected cross-language cases;
* `@test/backend-protocol`: 54 accepted/943 rejected wire cases;
* `@test/ocaml-observation`: 335 accepted/2077 rejected, 203 queries/22 incremental;
* `@test/ocaml-runner`: 691 lifecycle/parity/cancellation/filesystem cases;
* `@test/timing_analysis/runtest`: 18 native grammar cases and legacy exact inspection;
* `@test/ocaml-stage-report`, `@test/inspection`, `@test/flow-cli` (43 CLI tests);
* `@test/ocaml-finalization` (serial heavy check): 26 differential invocations,
  16 tests, runtime/cleanup/cancellation/acceptance and immutable inspection.

Import-only selected-image command:
`python3 -B test/check_stage_domain.py --consumer _build/default/test/stage_domain_consumer.exe --inspector _build/default/bin/experimental_plan_inspect.exe --selected`.
Metadata payload SHA-256 was
`60e8da8444e76b95c43186eb5c2ff1d229175c500226caae3e41a5ccb4465425`.
