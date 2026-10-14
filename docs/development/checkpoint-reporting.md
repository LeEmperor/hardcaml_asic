# Native checkpoint reporting — slice 1

Delivered 2026-10-14. Public `report TARGET` routes coarse runs to the existing
`Report_service` and stage targets to `Stage_report_service`. The helper's private
`--run-dir`, context, synthesis-state and diagnostic paths remain available for
execute/finalization callers.

## APIs and evidence

- `Stage_execution_record.of_json/read`: checked schema-2/3 segmented Runner
  records, occurrence identities/order/status/exit/duration, and ordered
  publication associations. Supports failure before any stage is reached and
  publication before an interrupted occurrence is finalized.
- `Stage_report_service.select`: direct structural selection; ambiguous workspaces
  require an explicit execution file. `run` validates publications using
  `Checkpoint.validate` and embeds the existing host-only inspection payload.
- Checkpoint `segment.json` supplies inventoried metric-origin evidence; metrics
  must agree with the manifest. No backend-native state metrics are reparsed.
  Selected checkpoints must agree on compatibility, closure and resolved config.
- Contract `hardcaml-asic.report`, schema 1, reserves `supplementary: []` per
  checkpoint. Original availability wrappers survive under each metric's source;
  missing known synthesis values carry `not_recorded` reasons. Unknown keys and
  their values remain visible without guessed units.

Focused checks: `dune build -j20 @test/ocaml-stage-report @test/ocaml-report`,
then `dune build -j20 @install`, then
`python3 -B test/check_stage_report.py --installed`. The installed test independently
links a library consumer and runs the thin-prefix native public command with no
Python/EDA on PATH and Python-driver checkout-open denial. Fixtures are synthetic
and isolated. `--real WORKSPACE` adds read-only workspace/checkpoint/execution
queries, a human preview, and SHA-256/size/mtime before-after verification.

The supplied synthesis workspace was checked read-only: 112 files unchanged,
stage duration 11.328 s, mapped area 13041.6048 µm², 673 cells, zero unmapped cells,
synthesis errors, latches, lint errors and lint timing constructs; two lint warnings.

## Slice 2 — retained synthesis inventory

Delivered 2026-10-14. `Yosys_stat_evidence.read` projects the cell-type inventory
from **exactly** `segment.run_dir/06-yosys-synthesis/reports/stat.json`, using the
selected, hash-validated checkpoint segment. No producer search or tool rerun.
It reads one regular file with descriptor/path identity, size, mtime and ctime
checks around the read (atime is intentionally excluded), hashes the actual bytes,
and parses with the evidence codec's opt-in duplicate-key rejection. This is a
stable-read check, not an extension of checkpoint validation.

The schema-1 `supplementary` entry carries `kind: yosys_stat`, path, raw-byte
SHA-256, `tool` from creator, `evidence_scope: retained producer report; not
checkpoint-inventoried`, `design_area`, `sequential_area` (value/unit or null),
`mapped_cell_count` and the complete name-sorted `mapped_cell_types` object.
Counts must be finite nonnegative integers, excluding booleans; decoded names
must be nonempty. Their sum must match `design.num_cells` and the checkpoint's
available mapped count when present. Areas must be finite nonnegative µm² values.
No cell class, sequential count or measurement corner is inferred.

Missing sources leave supplementary empty. Invalid sources leave supplementary
empty and emit explicit top-level diagnostics with source path/hash/scope; trusted
checkpoint metrics remain visible and query success is preserved. Interrupts are
not caught as missing evidence. Unknown metrics retain raw availability/value;
invalid known counts remain unavailable.

Human stage metrics use grouped decimals. The inventory summary reports type count,
cell total and sequential area, then the 10 largest counts (name-sorted ties).
`Stage_report_service.run ~verbose:true` and public `--verbose` show all rows;
JSON always retains every row. Coarse output and acceptance behavior are unchanged.

Verification (sequential builds, all `-j20`):

```sh
dune build -j20 @test/ocaml-stage-report @test/ocaml-report
dune build -j20 @install
python3 -B test/check_stage_report.py --installed --real "$WORKSPACE"
```

Focused synthetic checks cover matching/missing evidence, malformed JSON,
nonfinite/overflow/negative/fractional/boolean values, duplicate and Unicode-escaped
keys, both total mismatches, absent checkpoint count, exact-source selection,
bounded/full human rendering, JSON provenance, and unknown metric availability.
The coarse suite passed 586 policy/human byte differentials and 15 tests.
The installed thin-prefix CLI and independently linked library consumer passed
with no Python/EDA on CLI PATH and checkout-open denial. The supplied real
synthesis workspace remained unchanged: 112 files (SHA-256, size, mtime), 23 types,
673 cells, sequential area 7348.32 µm²; retained stat SHA-256
`37b2782748e5ba56f9a2d27a1a9933708fe178a5da053a87ec868cf023063a0a`.

## Bounded review fixes — terminal snapshots and diagnostic encoding

Reviewed and fixed 2026-10-14:

1. Runner can persist an outer `failed`/2 or `interrupted`/130 record while
   the current occurrence is still `running`, with null exit and zero serialized
   duration. Clock/Started-hook failure persists this before invocation;
   Published-hook failure can additionally retain the current checkpoint reference.
   `Stage_execution_record` now accepts these transitional snapshots. Completed
   outer records still require all occurrences completed; occurrence order,
   identities, plan/reference associations and publication capabilities remain
   checked. Reports keep outer failure and unresolved stage status distinct,
   retain earlier checkpoint metrics, and derive physical completion only from
   completed occurrences. Publication alone supplies neither completion nor acceptance.
2. Invalid UTF-8 in optional producer data could enter count or duplicate-key
   error text and cause the strict JSON string constructor to fail inside the
   diagnostic handler. `Yosys_stat_evidence` now validates diagnostic message/path
   strings locally and byte-escapes invalid strings, bounded to 1024 source bytes
   with an explicit truncation marker. Original source bytes and SHA-256 are
   preserved; malformed counts remain rejected. The shared `Evidence_json`
   parser and historical coarse-evidence compatibility are unchanged.

Regression coverage captures **actual Runner persistence** with injected clock,
Started and Published errors, each as failure and cancellation, after completed
synthesis and with unresolved floorplan. It checks CLI/library success, retained
artifacts/metrics, human status distinction, no invented completion/acceptance,
and rejection of completed-outer, order, unreached-publication and forged-capability
mutations. Supplement cases include raw `0xff` names with valid/boolean counts,
duplicate raw-byte names, invalid creator, bounded oversized errors, Unicode versus
escaped duplicate names, and opaque Unix paths (projection and Unix-error paths).
Every corrupt supplement remains diagnostic-only with trusted metrics available.

Verification, sequential commands (every Dune invocation uses `-j20`):

```sh
dune build -j20 @test/ocaml-stage-report @test/ocaml-report @test/ocaml-coarse-execution @test/ocaml-coarse-run @test/ocaml-collect
dune build -j20 @install
python3 -B test/check_stage_report.py --installed --real /home/wayne/devel/jane/hardcaml_asic_example/_flow_results/synthesis-2098699-229111dd306c1bd10af065aa3e394770
```

All passed: stage reporting; 586 coarse report policy/human differentials and
15 tests; 132 collect result/byte differentials and 4 tests; 24 coarse execution
lifecycle differentials; 15 coarse run record/outcome differentials plus lifecycle,
presentation and cancellation checks. Installed thin-prefix native CLI and the
independently linked library consumer passed. The real synthesis target was queried
read-only: **112 files unchanged** by SHA-256, size and mtime; 23 cell types,
673 cells, sequential area 7348.32 µm² and the retained stat hash above.
