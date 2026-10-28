# PT5b B — timing integration handoff

## Frozen integration seam (published before implementation)

`execution/results/resource_timing_evidence.mli` is the exact public signature.

```ocaml
type links = {
  resource_id : string;
  timing_links : Evidence_json.t;
  electrical_links : Evidence_json.t;
}
type collection = { resources : links list; diagnostics : string list }
val collect :
  read:(string -> string -> string * Evidence_json.t) ->
  exists:(string -> bool) -> flow:string -> context:Evidence_json.t ->
  manifest:Evidence_json.t -> resources:Evidence_json.t list ->
  final_netlist:Evidence_json.t -> (collection, string) result
val validate_links :
  references:Evidence_json.t list -> resource:Evidence_json.t ->
  timing_links:Evidence_json.t -> electrical_links:Evidence_json.t ->
  (unit, string) result
```

A calls `collect` once for reconciled **final physical** rows, with the existing
contained shared `read`/`exists`, selected flow-relative directory, coarse run
context, manifest, and already-read final netlist reference. Merge each returned
pair by exact `resource_id`. All read references are automatically registered by A;
B owns no hash registry. `Error` means invalid/contradictory producer provenance;
missing optional retained STA yields explicit unavailable links and diagnostics.
Call `validate_links` on schema-2 resource rows; full source replay must rerun
collection and compare links, catching coherent forged values over unchanged hashes.
Schema-1 semantics remain A-owned.

## Raw capture needed by C

From the exact accepted live run
`_flow_results/sram-physical/runs/20261025T034710180883Z_be961b2c/project/runs/asic/`:

- Copy `56-openroad-stapostpnr/` metadata `config.json`, `state_in.json`,
  `state_out.json`, `runtime.txt` and each configured corner's `max.rpt`, `min.rpt`,
  `sta.log`, generated `tt_um_program_memory__<corner>.lib`, unchanged.
- Preserve the flow-relative producer name. Absolute paths in raw metadata are
  compared by their exact recorded flow suffix, never dereferenced. The collector
  hashes the retained selected input netlist and requires equality with A's
  final-netlist reference. Retain `53-openroad-fillinsertion/tt_um_program_memory.nl.v`
  (same bytes as accepted final netlist), and `preflight.json` at capture root.
- Retain original run and bundle manifest identity, and existing accepted physical
  checks. New capture maps original sources to destinations with byte hashes;
  historical snapshot/live files remain untouched.

External macro model references/hashes are recorded separately from retained
generated unit libraries; the latter provide `1ns` and `(1,pF)` declarations.
Do not fetch PDK inputs. Fast analysis corner `nom_fast_1p32V_m40C` explicitly binds
the SRAM `fast_1p32V_m55C` model; both identities remain visible.

Implementation and focused verification status will be appended below.

## Wire shape ready for A integration

Available `timing_links`: `{status:"observed", scope, coverage, paths, evidence_refs}`.
Available `electrical_links`: `{status:"observed", scope, coverage, points,
evidence_refs, compliance:"not_assessed"}`. Unavailable links use the existing
`{status:"unavailable", reason}` shape. No new top-level resource row keys.

- `scope = "sampled retained post-PNR macro-boundary observations"`.
- `coverage = "sampled_reported_paths_not_exhaustive"`.
- Paths: `path_id`, `corner`, `group`, `path_type` (`min|max`), header endpoints,
  structured `data_start`/`data_end`, signed `arrival`/`required`/`slack`,
  `time_unit:"ns"`, `status` (`met|violated`), `provenance`.
- Electrical entries: `path_id`, `corner`, `point`, same `provenance`.
- Points: one-based `line`, full `name`, nullable `instance`/`pin`/`master`,
  `role` (`data|launch_clock|capture_clock`), `edge` (`rise|fall`), nullable
  `fanout`/`reported_load`, `slew`, `incremental_delay`, `arrival`,
  `time_unit:"ns"`, `capacitance_unit:"pF"`. Blank report fields remain null.
- Provenance includes explicit `origin:"coarse_run_retained_post_pnr_sta"`,
  run/build, `stage:"final_physical"`, producer/directory, report ref/span,
  unit-library ref, separately recorded `external_models`, and all source refs.

`Timing_report_model.parse` shares the **existing** public
`Inspection_service.timing_records` summary parser; no compatibility API change
or duplicate consumer parser is needed. Its new typed point model is public via
`execution/results/timing_report_model.mli`.

Producer discovery is bounded to ordinals 1–256 and occurrence suffixes absent,
`-1`, `-2`, `-3`; more than one retained post-PNR producer is rejected. Coarse run
paths require the original run directory suffix `_<run_id first eight chars>` and
the exact recorded `outputs.flow` suffix. Unsupported layouts remain explicit;
the reader never follows the historical absolute paths.

## Final B verification and integration notes

Implementation complete in:

- `execution/results/timing_report_model.{ml,mli}` — typed points/paths using the
  unchanged `Inspection_service.timing_records` summary API. Supported native
  fixed-width column boundaries are 6/18/30/42/54, edge at 55 and description at
  57. The edge-tagged native `input external delay` arithmetic row is checked but
  is not a pin. Endpoint names must agree with headers; a pin observed in a clock
  section cannot also supply a data endpoint in that path.
- `execution/results/timing_report_units.{ml,mli}` — exactly one lexical `1ns`
  declaration and one `(1,pF)` declaration, both direct library attributes in one
  balanced library scope; comments/quoted text or nested groups cannot supply
  missing declarations. No unsupported unit conversion or blank-column filling.
- `execution/results/resource_timing_evidence.{ml,mli}` — frozen seam above.
- `test/resource_timing/` — isolated Dune test and actual first-path excerpts.

Collector bounds: 64 configured corners, 512 paths query-wide, 65536 parsed
points query-wide, 256 diagnostics, bounded numbered producer discovery above.
The shared reader must enforce its source-count/byte/containment/hash-consistency
limits. Parser admission additionally retains the legacy 32MiB/report and 262144
line bounds. Partial/malformed/over-bound supported reports generate diagnostics;
remaining valid links keep **sampled**, never exhaustive, coverage. Provenance
contradictions (wrong netlist hash/run, producer, corner or model binding) return
`Error`; missing reports/units/models yield unavailable or partial observations.

Preflight model binding is exact to
`manifest.flow_configuration.MACROS[master].lib[analysis_corner]`, then config/log
path and retained preflight reference/hash. The recorded external model is not
read or added as if its bytes were retained. Only the generated unit library is
a retained, hash-closed library source. Retained input netlist bytes must hash-match
the passed final implementation netlist reference. Log netlist/corner identity is
unique, not merely a substring match. No current PDK discovery occurs.

`validate_links` checks exact nested fields, owned data endpoints, consistent pin
names, roles/units/finite quantities, signed slack/status, spans, path source IDs,
external-model corner identity, source closure, electrical-to-timing relationships,
and `compliance:"not_assessed"`. It intentionally cannot prove numeric truth from
hashes alone: A must replay collection for schema-2 `verify_sources` and compare
the complete result. The focused test demonstrates a coherent changed slack over
unchanged source refs is structurally admissible but differs from fresh source
replay. **A's public replay integration/forgery negative remains A-owned.**

Verification on 2026-10-27, no EDA:

```sh
flock /tmp/opencode/asic-pt5b-build.lock opam exec --switch=5.2.0+ox -- \
  dune runtest -j6 test/resource_timing
# 44 tests, 0 failures

flock /tmp/opencode/asic-pt5b-build.lock opam exec --switch=5.2.0+ox -- \
  dune exec -j6 test/inspection_parser_tests.exe
# passed
```

The test executable also supports explicit optional read-only original-run checks.
From `test/resource_timing/`, set `PT5B_RETAINED_STA` to the original absolute
`.../56-openroad-stapostpnr` path and invoke `dune exec -j6 ./check.exe` through
the same flock/opam switch. This passed **46 tests, 0 failures**: all six full raw
reports yielded **306 paths**, and the original coarse-run collector yielded
**186 resource-linked paths / 372 macro electrical points**, with no diagnostics.
The optional collector check supplies the independently known exact macro identity;
it is not a substitute for A's full resource reconciliation/public replay tests.
It reads original metadata/netlist/reports/libraries only and makes no copies.

The original first-path slow setup/fast hold numbers, ns/pF provenance, blank Cap,
and fast −40°C analysis / −55°C SRAM model distinction all pass. The portable
suite also covers unsupported/truncated columns, nonfinite and valid negative
slack, malformed/duplicate/conflicting units, exact vs near-prefix/wrong-master
ownership, clock-only paths, wrong stage/run/input hash, unsafe flow/corner/state
paths, missing/duplicate/wrong producers, conflicting report/log corners,
duplicate/conflicting netlist logs, model/state binding and forged wire fields.

No common schema/physical/archive/root test Dune or example files were edited by B.

## Independent A timing review corrections — B ready/frozen

All four findings from
`/tmp/opencode/pt5b-timing-review-a-20261027.py` are fixed. This receipt supersedes
the earlier B verification counts above. The public collector/validator signatures
and schema-2 wire fields are unchanged; A requires no integration changes.

1. **Ordered primary/capture/summary boundaries.** The structured parser now checks
   data table → primary arrival → capture-clock section → primary required →
   separator → repeated required → negated arrival → separator → slack. A capture
   clock header after data launch but before primary arrival rejects the path
   independently of the arrival-marker-based role assignment. Primary arrival must
   immediately follow and match the actual data endpoint; summary arithmetic cannot
   replace a primary measurement. Required/arrival copies must agree with their
   primaries. Dropping the first arrival marker, optionally also the actual SRAM
   `A_ADDR` row, yields a diagnostic and no fabricated data-role `A_CLK` endpoint.
2. **Explicit report recognition.** Empty, gzip, binary and unrecognized retained
   reports produce diagnostics rather than silent zero summaries. The supported
   native `No paths found.` report has an exact command/corner/no-path envelope;
   collector checks its min/max and corner against the selected directory and
   reports its sampled no-path outcome explicitly. Trailing garbage is rejected.
3. **Library-level units.** A bounded token scanner tracks comments, escaped quoted
   strings, braces and parentheses. Exactly one direct library `time_unit:"1ns"`
   and `capacitive_load_unit(1,pF)` are required. Nested spoof attributes,
   unbalanced/truncated/multiple library scopes and conflicting units cannot earn
   units. The legacy `Liberty_unit_evidence`/inspection APIs remain unchanged.
4. **Attempted-point accounting.** New additive
   `Timing_report_model.parse_with_usage` returns accepted paths, diagnostics,
   `consumed_points`, `point_limit_reached`, and recognized native `no_paths`
   `(corner, mode)`. Attempted points in subsequently rejected paths consume the
   shared 65536-point budget. On exhaustion the collector stops reading subsequent
   path reports. The existing `parse` projection and legacy `timing_records` API
   remain compatible. Regressions cover both one-report exhaustion and rejected
   attempts accumulated across reports.

Final focused/compatibility command, under the prescribed shared lock and switch:

```sh
flock /tmp/opencode/asic-pt5b-build.lock opam exec --switch=5.2.0+ox -- \
  dune build -j6 @test/resource_timing/runtest @test/inspection \
  bin/flow_cli.exe test/resource_evidence_consumer.exe
```

Passed: **73 focused tests, 0 failures**, and the existing inspection suite. The
optional original-run checks passed **75 tests, 0 failures**, preserving all
**306 full native paths**, **186 resource-linked paths**, **372 electrical points**,
and zero original-run diagnostics.

Re-ran A's independent public API/source-replay repro against rebuilt final source.
Receipt: `/tmp/opencode/pt5b-timing-review-a-gd8a4zpc/report.json`.
Both arrival-marker attacks now retain only the valid max path with diagnostics;
there are **zero data-role clock points**. Empty/garbage/gzip min reports have
explicit diagnostics. Nested-only units yield no paths. Exhausting attempted
points yields no later min path and explicitly reports remaining reports unread.
The script independently re-audited every one of the original **372** electrical
points against fixed-column source bytes and passed full source replay.

Only B-owned timing modules, isolated tests and this handoff were changed for these
corrections. No EDA, Workbench/Protemu, Git operations or historical evidence edits.
