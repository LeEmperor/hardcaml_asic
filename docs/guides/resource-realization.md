# Inspect selected and realized resources

Preparation selects resources; bundle emission records their expectations;
synthesis and physical result validation establish which instances survived.
These are separate facts, not another physical execution stage.

## Read-only inspection

```sh
hardcaml-asic-flow resources-inspect "$RUN_DIR"
hardcaml-asic-flow resources-inspect "$RUN_DIR" --json
```

The public library equivalent is:

```ocaml
Hardcaml_asic_execution.Resource_evidence.inspect ~run_dir
(* (Evidence_json.t, string) result *)
```

Inspection reads retained evidence without EDA, current sources, PDK discovery or
publication. Supported inputs are ordinary coarse run directories and the retained
example synthesis/physical snapshots described below. Exit codes:

- **0:** no failed required-macro reconciliation checks. A resource-free/flop-only
  design may have no required macro checks; consult coverage and availability.
- **1:** required reconciliation failed or required evidence is unresolved.
- **2:** invalid input or provenance.

The schema-1 `hardcaml-asic.resource-evidence` object exposes manifest-derived
`resource_inventory`, stage-specific `observations`, `check_outcomes`, provenance,
coverage and hashed `evidence_refs`. Expectations and observed instances remain
separate. Missing, unexpected and unresolved outcomes have explicit reasons;
absence is never assumed to prove optimization. Instance identity matters even
when aggregate counts agree.

New bundles contain an identity-covered `resource_snapshot` made from the same
resolved implementation used to render the bundle. Historical manifests without
it remain readable through an explicitly labeled legacy inventory adapter.
`Project.prepare_resources` and `Methodology_plan.prepare` are different APIs:
neither shared names nor similar inventories prove that a separately retained
PT.4 attempt produced a bundle. `preparation_link` currently remains unavailable.

## Collection, acceptance and archives

Ordinary collection embeds the same object in `results.json`. Authoritative
`Report_service.run` rechecks source integrity and reconciles expectations in
memory, including historical results that predate this field. Required macro
mismatches fail the relevant acceptance checks. Historical files are not rewritten
by reporting. Existing physical/checker and external postcheck requirements remain.

`Resource_evidence.validate` checks schema and internal consistency, not the truth
of an arbitrary assertion against external files. Use `verify_sources ~run_dir`
for source-aware verification: it rechecks advertised hashes and replays the full
reconciliation. Explicit in-memory execution contexts require the matching
`~context`. Report and archive use this replay. Genuine failed evidence remains
archivable; forged passing assertions over failed source evidence are rejected.
Archives retain every advertised resource evidence source.

## Interpret counts and areas

Every measurement has a unit, definition, stage, scope, evidence references and
an unavailable reason where needed. In particular:

- Mapped cell totals include macros. Standard-cell count excludes declared macros.
- Synthesis standard-cell area is cross-checked against retained mapped library
  attributes. Macro area requires bound, hash-verified default-corner Liberty.
  Their sum is a **combined cell-area estimate**, not placed/routed or die area.
- Final netlist counts include fillers/decaps/taps/ties present in that netlist;
  they are not the native logical standard-cell count from the placement database.
- Final physical standard-cell area is separate from the synthesis estimate.
  Standard-cell utilization is not whole-design occupancy; the retained producer
  percentage does not establish its denominator or excluded regions.
- Sequential counts/area are whole-design evidence, not per-resource flop cost.
  Resource-linked timing/electrical attribution, optimized flop ownership and
  physical macro footprint are currently unavailable.

Supported mapped standard-cell classification requires known library namespaces,
finite area attributes and blackbox leaf semantics. Unsupported hierarchy becomes
unresolved rather than hiding nested macros. A mapped file alone does not prove a
completed synthesis boundary. Physical checks use the retained checked final
netlist and artifact hashes, not a synthesis file with a convenient basename.
Checkpoint-only stage reports explicitly lack per-resource instance evidence;
this feature does not add named-flow macro/checkpoint execution support.

## Validated example

From `hardcaml_asic_example`, using its isolated PT.5 capture:

```sh
P="$PWD/.dev/asic-pt5/current/bin/hardcaml-asic-flow"
"$P" resources-inspect acceptance/sram/8b48d7d0-functional --json
"$P" resources-inspect acceptance/sram/physical-p4 --json
```

The synthesis specimen reports 176 total cells: **175 standard cells + one SRAM**.
Its standard-cell area is **2,182.7232 µm²**, bound macro Liberty area
**28,127.104 µm²**, and combined estimate **30,309.8272 µm²**. The separate physical
run reports **4,793.64 µm²** final standard-cell area. Its final netlist contains
68,928 non-macro instances including fillers/decaps, unlike the native metric's
389 logical standard cells. The physical snapshot lacks bound synthesis stat and
Liberty area inputs; inspection does not borrow them from the other run.

See the [implementation/acceptance record](../development/resource-realization-plan.md#implementation-and-review-closeout-2026-10-27)
and [example guide](../../../hardcaml_asic_example/docs/resource_realization.md)
for identities, negative fixtures and limitations. The old physical qualification
remains unchanged: raw Magic=3 with exact disposition, abstract macro-boundary LVS,
and no new timed-model/IR-EM claim.
