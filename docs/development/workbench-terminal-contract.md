# Minimal Workbench terminal-results contract

## Existing public route

Use a fresh named execution through `signoff`, public `report EXECUTION --json`,
then public `finalize EXECUTION --operation-store ROOT --json`. Finalization
without `--accept` collects physical results and leaves acceptance and external
postchecks `not_evaluated`. Add explicit acceptance collateral and `--accept`
when acceptance is required. This route already exists in CLI contract 4; it
does not require a new provider generation or stage-report rewrite.

`finalize` emits JSONL: retain its early `allocated` event and terminal receipt.
Pass the **returned** `attempt` to `finalization-inspect --json`. Read the exact
`results.path` from that receipt and verify its raw-byte SHA-256 against
`results.sha256`. The receipt inspector checks receipt structure; the consumer
still checks the referenced bytes. Do not reconstruct an operation or execution
path, select the newest directory, or pass the finalization directory to `report`.
Finalization deliberately creates no coarse `run.json` there.

Correlate receipt `execution.path`, `execution.sha256` and `execution.attempt_id`
with the selected execution, and `selected_checkpoints` with the public stage
report. Results `provenance.operation` identifies this operation's `operation.json`.
Its `run_id` is the operation ID, not the implementation stream ID. Keep both
identities. A failed acceptance can still have valid published results.

## Normalized terminal data

The referenced results use results schema 1. A metric contains `value`, `unit`,
`definition`, `stage`, `corner`, `source`, `unavailable_reason`, `tool`, `mode`
and (for segmented finalization) `origin_boundary`.

| Results field | Unit / meaning | Translation |
| --- | --- | --- |
| `metrics.setup_slack`, `metrics.hold_slack` | `ns`; worst reported corner | Signed finite number; retain corner and mode |
| `metrics.mapped_area`, `metrics.sequential_area` | `um^2` | Synthesis evidence, not final physical area |
| `metrics.mapped_cells` | `cells` | Finite nonnegative integral count |
| `metrics.final_standard_cell_area` | `um^2` | Final physical area |
| `metrics.final_utilization` | `fraction` | Ratio, not percent; multiply by 100 only for a percent-labelled display |
| `synthesis_checks.*` | `count` | Nonnegative integral count; absent is not zero |
| `checks.drc`, `checks.lvs`, `checks.antenna` | `status`: `pass`, `fail`, `unknown` | Retain reason, raw counts and source; unknown is not pass |
| `timing_goal` | `pass`, `fail`, `unknown` | Provider timing verdict, separate from acceptance |
| `timing_unconstrained_modes` | setup/hold mode names | No constrained paths; do not display zero slack |

Only expose numeric values when finite, the unit is recognized, and
`unavailable_reason` is null. Slack may be negative: a generic nonnegative
metric parser silently discards actual violations. Sentinels for unconstrained
paths are already normalized to unavailable by collection. Keep diagnostic
`errors`; do not promote incomplete evidence to acceptance.

Resolve metric/check `source` relative to the returned operation `attempt`.
Retain the complete source object in Workbench's metric provenance, including
the results path/hash, metric field, supplied tool/stage/corner/mode and
`origin_boundary`. `origin_boundary: signoff` identifies the accumulated
publication, **not** a claim that signoff produced every measurement. `stage:
final` and tool LibreLane are the provider's declared aggregation attribution;
do not replace them with an inferred OpenSTA/OpenROAD step. Stage reports likewise
describe accumulated boundary snapshots and currently normalize only synthesis
units; do not guess units for their unknown raw keys.

Physical completion comes from validated stage report `completion.physical`;
`full` requires selected completed signoff evidence. Execution `status: completed`,
physical completion, successful collection, external postcheck and acceptance
are distinct facts. Only the finalization receipt supplies acceptance `pass` or
`fail` for its explicitly requested acceptance operation.

## Clocks are declared constraints

The immutable version-1 methodology plan includes `configuration_bytes` (JSON
text) and `bundle_manifest` (JSON text). The latter's `flow_configuration` has
the same configuration. Read `CLOCK_PORT` and `CLOCK_PERIOD` from that checked
configuration; `CLOCK_PERIOD` is in **ns**. `resolved_settings` identifies their
clock origin. Require a nonempty port and a finite positive period. Preserve
plan identity, bundle identity and the exact configuration field as provenance.
Display as **declared clock**, not a measured clock, CTS result or achieved
frequency. A derived frequency is `1e9 / period_ns` Hz and must be labelled derived.
There is no public measured-clock inventory in this terminal contract.

## Workbench translation boundary

The current Workbench stage-summary adapter only accepts eight synthesis keys
and requires nonnegative numbers. Keep its checkpoint validation, then add a
separate finalization-result projection. The existing protocol's generic
`Metric` records can represent physical numbers and signed timing after updating
validation. Its `timing` triples alone cannot retain attribution: preserve the
full supplied context in metric `source` as well. Explicit check and declared-clock
records are needed if these are to be structured protocol fields; do not encode
check status as a numeric metric. Keep operation references in the cache and
include stage report, operation/results and clock plan evidence in freshness
digests. A cached stage summary alone cannot validate terminal acceptance.

The example's [bounded execution commands](../../../hardcaml_asic_example/docs/headless_flow.md#terminal-physical-results-and-acceptance)
cover installation, fresh physical execution and finalization. All builds,
tests, installs and EDA runs remain caller-owned.
