# PT.5 execution handoff (B)

Implemented and fixture-tested public seam for C (2026-10-26):

* Library `Hardcaml_asic_execution.Resource_evidence.inspect ~run_dir :
  (Evidence_json.t, string) result`, host-only, read-only, no PDK/tool discovery.
* CLI `hardcaml-asic-flow resources-inspect RUN_DIR --json` emits that exact
  object (`contract: hardcaml-asic.resource-evidence`, `schema_version: 1`).
  Exit 0 means required reconciliation passed, 1 means failed/unavailable required
  evidence, 2 means invalid input/provenance. No files are published.
* `Resource_evidence.problems : Evidence_json.t -> string list` is the shared
  acceptance verdict. Collection embeds the object as `resource_evidence`;
  report checks it, including on historical runs inspected in memory.
* `Resource_evidence.validate : Evidence_json.t -> (Evidence_json.t, string) result`
  checks the versioned schema, internal provenance/reference closure, finite
  measurements and verdict/instance consistency. Valid failing reconciliations
  remain valid evidence. `collect ?context ~run_dir ()` is the collection seam;
  malformed available expectations fail collection rather than disappearing.
  `verify_sources ?context ~run_dir evidence` rechecks the schema and advertised
  source hashes, then compares the complete assertion with a source-derived replay;
  report and archive share it. Supply `context` for explicit in-memory/finalization
  contexts. `inventory_available ~run_dir` is the
  bounded historical-layout expectation-discovery seam used by reporting.
* Top-level fields: `provenance`, `coverage`, `resource_inventory`, `observations`,
  `check_outcomes`, `evidence_refs`. `resource_inventory` retains the complete
  manifest-derived logical expectation rows; observation row sets and expectations
  must agree with it. Source-aware replay also binds it to actual manifest bytes.
  Observations carry `stage`, `producer`, `run_id`,
  `build_identity`, `resources`, `unexpected_instances`, `measurements`,
  `status`, `reason`, `evidence_refs`. Resource rows carry `resource_id`,
  `requested_contract`, `selected_implementation`, `expected`, `realized`,
  `status`, `reason`, `area`, `attribution`, `timing_links`, `electrical_links`.
  Rows also retain `selection`, `requirement`, `policy`, and `inventory_record`.
  Legacy requests/selection remain their original S-expressions; snapshot requests
  retain the existing structured snapshot representation.
* Stages are `synthesis` and `final_physical` (evidence labels, not flow enums).
  Synthesis instance proof uses mapped JSON; final physical proof uses retained
  physical checker artifacts/netlist and preserves existing physical gates.
* Provenance includes run/build/manifest hashes; `preparation_link` is explicitly
  unavailable. Historical inventory coverage is `legacy_resources_macro_contract`;
  structured inventory coverage is `resource_snapshot`. Neither rewrites a bundle.
* Measurements always include `value`, `unit`, `definition`, `stage`, `scope`,
  `evidence_refs`, `unavailable_reason`. Combined synthesis area is an estimate;
  final standard-cell area is a separate measurement. Flop attribution is unavailable.

## Exact measurement and inventory keys

Synthesis `observations[0].measurements`:
`total_mapped_cells`, `macro_count`, `standard_cell_count`,
`synthesis_standard_cell_area`, `whole_design_sequential_area`,
`sequential_cell_count`, `macro_library_area`, `combined_cell_area_estimate`.
`sequential_cell_count` is unavailable without retained sequential classification;
use `cell_type_counts.types` for exact whole-design typed instance counts (for
example the retained SRAM's 16 `sg13cmos5l_dfrbpq_1` cells). They are not SRAM
resource flops. `cell_type_counts` has `status`, `scope`, `types` with
`module`, `count`, `classification` (`declared_macro`, `standard_cell`, `unknown`).

Final physical `measurements`: `total_physical_netlist_cells`, `macro_count`,
`standard_cell_count`, and when metrics are retained, `final_standard_cell_area`,
`standard_cell_utilization`. Netlist counts include filler/decap/tap/tie cells
present in the netlist and exclude physical-only cells omitted from it; these
are not placement-database logical-cell counts. Utilization's denominator/excluded regions are unavailable;
it is not whole-design occupancy. Per-resource physical footprint, timing and
electrical attribution remain unavailable.

Macro classification is bounded to declared macro modules plus supported
standard-cell namespaces with finite mapped library area attributes **and blackbox
leaf semantics**. An observed mapped module with internal cells, processes or
memories, or without supported library/blackbox semantics, is unresolved; hierarchy
is not flattened by the inspector. Other types are exposed as unknown coverage
and fail required retention. Known macro types are excluded from the standard-cell
area sum even when their names share a standard-cell prefix. Synthesis area is
cross-checked against mapped library-attribute areas, not inferred from a filename
or silently assumed to exclude macros. Macro Liberty must match the configured
default-corner reference and its retained preflight SHA-256.

## Retained layouts and provenance

`RUN_DIR` may be the live coarse run or either retained SRAM acceptance directory
named in the plan. Manifest candidates: `project/manifest.json`, `manifest.json`,
`bundle/manifest.json`. Snapshot synthesis aliases are `mapped.json`, `stat.json`,
`models/<configured-lib-basename>`, and `run-preflight.json`. Final instance proof
requires the actual `flow/final/nl/<top>.nl.v` or recorded flow equivalent; a
synthesis `mapped.v` is never relabeled final physical evidence.
Root mapped/stat/metrics aliases are enabled only for the explicit snapshot
layouts (`manifest.json` or `bundle/manifest.json`, recorded flow
`project/runs/asic`). They cannot rescue an unrelated or absent producing flow in
a staged live run. Synthesis instance proof additionally requires a recorded
completed boundary of `synthesis` or `full`; a later flow failure may retain a
completed synthesis observation, while a null/unreached boundary is unresolved.

Physical profile inspection validates the run-pinned physical checker record,
all its advertised artifact hashes and final GDS digest before final-netlist
reconciliation. Existing collection/report physical gates remain active.
Evidence integrity does not authenticate the original producer or rerun geometry.

`provenance` includes run/build/requested/completed stages, manifest reference,
run reference (or explicit in-memory-context availability), `context_sha256`,
`evidence_origin`, unavailable preparation linkage and source-authentication scope.
Finalization retains its selected checkpoint identities in `producer_origin`;
collection does not invent a new synthesis producer from a completion boundary.

Collection publishes this schema inside `results.json` and advertises its sources
in `raw_artifacts`. Archive verifies the evidence schema, source digests and full
source-derived reconciliation replay and retains every advertised source. Genuine
failed reconciliations remain archivable; forged passing assertions over the same
hashed failure sources do not. Reports reconcile available expectations afresh
in memory, including when stored historical results lack PT.5; the originals are
never replaced. Historical records with no expectation inventory retain an
explicit unavailable reason, not a successful resource-retention claim. Direct
pure `Report_service.evaluate` has no filesystem/manifest context: use
`Report_service.run` for authoritative retained-run acceptance.

## Verification / handoff to C

`@test/resource-evidence` covers public CLI, library inspection, collection/report
agreement, independent physical failures, new snapshot and legacy inventories,
unavailable flop attribution, malformed evidence, stale hashes/provenance,
archive closure and byte-preserving historical reporting. Broader collection,
report, finalization, archive, inspection, CLI and packaging aliases were run.

Read-only smoke through the public CLI produced:
* synthesis retained run: 176 mapped cells, 1 macro, 175 standard cells;
  2182.7232 + 28127.104 = 30309.8272 um² combined estimate;
* distinct physical retained run: exact macro instance matched at synthesis and
  final netlist; final standard-cell area 4793.64 um². Its snapshot lacks bound
  synthesis stat/Liberty area inputs, so those synthesis area values are unavailable.

C still owns independent example acceptance, negative-copy receipts and provider
capture. This smoke is not a replacement for that acceptance.

## Independent A review and broad ASIC regression (B, 2026-10-27)

Reviewed A's bundle/resource snapshot and methodology-plan changes without editing
A-owned source. Identity coverage, recursive strict decoding, logical inventory
projection, instance/physical-intent cross-checks and legacy no-macro named-plan
compatibility are sound in the inspected paths and passing tests.

**A-owned consistency finding at review time (medium; correction delegated to A):**
`lib/elaboration/bundle.ml:verify_resource_snapshot` compares resource/module/
instance tuples and physical intent with `macro_contract.macros`, but does not
compare each macro's `collateral` against the snapshot/legacy logical sources.
An independently rendered valid exact-SRAM bundle still passes
`Bundle.verify_manifest_identity` after changing a contract collateral reference
to `wrong`, or replacing that collateral list with `[]`, and recomputing the
normal outer bundle identity. The snapshot and legacy resources retain their
original collateral. This is contradictory metadata acceptance, not evidence of
bypassing the separate runtime macro-capability/physical gates: the independent
probe also confirmed `Macro_contract.validate` accepts the original bundle and
rejects both altered contracts. A should compare
the role/corner/reference inventories and add resealed negatives, or explicitly
bound this verification guarantee. B has not changed A's implementation.

Independent probe retained outside the checkout:
`/tmp/opencode/pt5-a-review/review.ml` (own Dune project, current staged ASIC
libraries through `_build/install/default/lib`). Results:

```text
valid_new_macro: accepted
runtime_valid_new_macro: accepted
legacy_absence: accepted
snapshot_null_resealed: rejected
snapshot_module_resealed: rejected
logical_collateral_resealed: rejected
contract_collateral_resealed: accepted
contract_collateral_removed_resealed: accepted
runtime_contract_collateral_resealed: rejected
runtime_contract_collateral_removed_resealed: rejected
strict_duplicate_tagged_sexp: rejected
strict_empty_subtree: rejected
```

Full ASIC regression completed with **exit 0**:

```sh
flock /tmp/opencode/asic-pt5-build.lock opam exec --switch=5.2.0+ox -- dune runtest -j6 --display short
```

Successful-run log: `/tmp/opencode/asic-pt5-full-suite-resume.log`, ending in
`COMMAND_EXIT_CODE="0"`. The first invocation hit the tool's 300-second deadline;
its surviving fixture process trees were terminated before the longer-deadline
run. Its log is `/tmp/opencode/asic-pt5-full-suite.log`; do not use that interrupted
invocation as the completion receipt.

Confirmed output includes A's 53 bundle assertions, 108 plan checks, preparation
library tests, 131 collector and 585 report differentials, 16 archive and 26
finalization differentials, 15 postcheck and 15 coarse-run differentials, 24
preflight report differentials plus 72 cancellation cases, SRAM bundle/physical
fixture regressions, runtime/identity/protocol/runner suites and inline tests.
Cached successful aliases remain part of the full Dune target; the earlier PT.5
focused receipt records its 27 public CLI cases separately.

Availability: the optional old retained-finalization tree
`/tmp/opencode/native-final-integration/finalizations/20261014T040711301534Z_913453bd`
was absent, so its retained-real normalization/parity branches were not exercised.
The observation corpus reported `historical: 0`. Deliberate failure diagnostics
inside passing fixture tests (including `finalize: missing native helper`) are
not suite failures. No test assertion failures or B-owned fixes arose from this
full run. The default suite does not include standalone installed-prefix/installed
corpus checks or the explicit retained-checkpoint alias.

## B corrective review handoff — five confirmed defects (2026-10-27)

The full-suite receipt above predates these corrections. The latest B correction
receipt is the targeted run below; C's installed-04 acceptance likewise predates
the fixes and requires a final provider recapture and acceptance run.

1. **Final Verilog statement completeness:** balanced port parsing consumes every
   comma-separated instance, including nested connection expressions. Extra macro
   instances are reported/countable; malformed delimiters, unsupported arrays or
   trailing instance tokens produce unresolved evidence rather than a partial
   successful inventory.
2. **Mapped hierarchy/leaf semantics:** standard-family naming and area attributes
   are insufficient. Observed module definitions must have supported blackbox leaf
   semantics and no internal cells/processes/memories. Unsupported hierarchy is
   unresolved, including a nominally blackbox wrapper containing hidden macros.
3. **Synthesis boundary:** null/unreached synthesis completion fails required
   reconciliation even when a mapped file exists. Root aliases cannot mask an
   unrelated live-run flow. A genuinely completed synthesis boundary remains
   observable if a later physical stage fails.
4. **Assertion/source consistency:** the mandatory `resource_inventory` anchors
   observation row coverage and expectations. Validation cross-checks typed total,
   macro and standard-cell counts, classifications, matched-row counts and stage
   completion. `verify_sources ?context` additionally replays the *complete*
   reconciliation and compares the assertion, not just provenance and hashes.
   Offline shape validation is not source authentication: a wholly coherent
   forgery of inventory and observations is still rejected by source-aware replay.
   Report and archive use that same replay seam. Actual archive publication of a
   genuine failed reconciliation is a positive regression.
5. **Macro/standard-cell namespace overlap:** known macro types are excluded from
   the standard-cell sum. A 100.25-area `sg13g2_macro` plus 2.5 standard-cell area
   yields an unavailable combined estimate when stat reports the inclusive 102.75;
   it never becomes 203.0. When stat is proven standard-only at 2.5, the combined
   estimate is correctly 102.75. No subtraction/inclusion semantics are guessed.

New regression: `test/check_resource_evidence_review.py`, on the existing
`@test/resource-evidence` alias. It converts the old-behavior independent repro
into corrected expectations and adds coherent count/inventory forgeries,
source-aware library verification, failed archive publication/byte closure,
unsupported syntax, blackbox-flagged hierarchy, and explicit in-memory-context
replay cases. Only disposable fixtures are mutated.

Latest successful command (shared lock, allocation six):

```sh
flock /tmp/opencode/asic-pt5-build.lock opam exec --switch=5.2.0+ox -- dune build -j6 \
  @test/resource-evidence @test/ocaml-report @test/ocaml-collect \
  @test/ocaml-archive @test/flow-cli @test/ocaml-stage-report \
  @test/ocaml-finalization @install
```

Actual outcomes: original **27 public CLI cases** and **19 new CLI observations**
passed, together with the source-aware/strict-reader/archive/context assertions;
131 collector, 585 report, 16 archive and 26 finalization differentials passed;
43 CLI presentation tests, stage-report checks and the install build passed.
The optional older retained-finalization tree remained unavailable. The initial
run caught an ambiguous OCaml documentation comment; it was fixed before this
passing receipt. No EDA or checkout Git mutation was used for these corrections.

Both retained SRAM inspections were also rerun read-only after the functional
fixes: synthesis still reports 176 total / 1 macro / 175 standard cells and
2182.7232 + 28127.104 = 30309.8272 um²; the separate physical run still matches
its macro and reports final standard-cell area 4793.64 um². The old retained
manifests/results remain historical inputs; regenerate derived PT.5 evidence and
provider receipts rather than rewriting them. Pre-review derived objects lacking
the new inventory anchor do not satisfy the corrected in-progress schema.

Use the shared ASIC flock and explicit Dune `-j6` for provider builds. See the
resource-realization plan for retained run IDs and ownership boundaries.

## Final coordinator disposition

The collateral consistency finding above is corrected: A now compares role,
corner and reference inventories, with 62 passing bundle assertions. Independent
follow-up verified all five execution corrections plus the alias restriction
(89 assertions/command checks, 17 CLI observations). Forced full ASIC regression
passed after corrections; final installed example acceptance passed 20 focused
tests and 76 API/CLI calls with the corrected frozen provider. The earlier smoke,
pre-fix full suite and installed-04 capture are historical, not the final receipts.
See the [closeout](resource-realization-plan.md#implementation-and-review-closeout-2026-10-27)
for identities, retained logs, complete evidence and remaining PT.5b limitations.
