# Project flow catalog: implementation and verification

Implemented in bounded dispatches against provider base `0d04bae`, through
2026-10-15. This is the chronological evidence record for
[the design](project-flow-catalog.md). Earlier slice limitations below retain
their historical scope; this summary describes the delivered milestone.

## Current milestone

**Delivered:** standalone project catalogs, typed profiles/defaults, declaration-only
discovery/description, concrete preview, expected-identity fresh execution, frozen
methodology evidence, historical reporting and public-protocol headless reconnect.
These interfaces do not depend on Workbench. The
[named-flow guide](../guides/named-flows.md) gives current commands.

- The example declares `standard/balanced` and `standard/synth_delay`, using the
  supported strategy enum and boolean ABC-buffering parameter.
- Profile settings are applied before bundle publication. Native launch verifies
  the frozen plan, complete required input inventory and actual bundle; staged
  inputs and backend-resolved parameter values are checked during execution.
- Preview, allocation, observation, execution and report preserve explicit plan,
  bundle and attempt associations. Historical reads use saved definitions, not
  the current catalog or active selection. Legacy command/record behavior remains.
- The example exposes `flow list`, `flow describe`, `flow plan`, `flow run`, plus
  a headless client that uses only public machine interfaces and explicit refs.

**Verified:** final forced provider regression, 57 installed-prefix tests, consumer
catalog/routing/installer/RTL checks and installed headless fixtures. Two actual
selected-image synthesis runs completed with matched generated/resolved settings:
balanced had 673 cells / 13041.6048 µm², synth_delay had 685 cells / 13277.4012 µm².
RTL/SDC hashes matched; plan/methodology/bundle identities differed. Actual
allocation-only reconnect and historical source-hidden reporting passed.
See [physical evidence](../../evidence/namedflow/20261015-real-synthesis.json).

Independent review corrections cover input-inventory contradictions, staged-input
mutation, runtime parameter-domain checks, publication/inspection races and client
setup cancellation cleanup. The two-profile physical snapshot predates the last
lifecycle corrections; their source/installed regressions passed separately.
The final consumer-only timeout extension also has separate routing/headless
tests: `flow run --timeout` controls provider calls; headless `--stage-timeout`
forwards it while headless `--timeout` retains its overall-client meaning.

The orchestrator subsequently forced `@scripts/headless-test` with the verified
`namedflow-race-provider-v2` prefix and prepared native-engine fixtures: all **16
tests passed**, including the native integration case, with `-j 20` and no skipped
case. This verifies the final consumer timeout extension alongside the lifecycle
corrections; it does not replace the separately captured physical synthesis evidence.

**Not claimed:** named-flow physical signoff/acceptance for either profile,
Workbench application integration, arbitrary LibreLane operation rearrangement,
configuration-changing checkpoint reuse, or P6 source-artifact stamping. Actual
synthesis completion remains distinct from acceptance (`not_evaluated`).

## Delivered API

The public library `hardcaml_asic.flow_domain` remains Core-only. Its new
`Catalog`, `Methodology`, `Profile`, `Selection` and `Parameter` modules each
have an `.mli`. The main library exposes identical modules as `Flow.Catalog`,
`Flow.Methodology`, `Flow.Profile`, `Flow.Selection` and `Flow.Parameter`.

All checked declarations, selections, assignments and resolution results are
abstract immutable values. Constructors return `Or_error.t`. Read-only accessors
expose the complete declaration data for later serialization. There is no
deserialization constructor that bypasses validation.

- **Selection:** `Selection.Id.create` accepts exactly `[a-z][a-z0-9_-]*`.
  Labels are separate nonblank display text; descriptions may be empty. Text
  is retained verbatim. Flow IDs are catalog-scoped; profile IDs are flow-scoped.
  `Selection.create ?flow ?profile ()` rejects a profile without a flow.
- **Methodology:** `Methodology.create` declares identity/display metadata,
  a closed `Backend_recipe.Librelane_classic_v1` value (canonical spelling
  `librelane.classic.v1`), allowed endpoints, configurable parameter keys and
  explicit methodology defaults. `Backend_recipe.of_string` rejects other
  recipes. Endpoints are a nonempty, duplicate-free subset of `Stage_id.all`.
  `Methodology.stages ~endpoint` requires a declared endpoint and returns the
  complete fixed synthesis → floorplan → placement → CTS → routing → signoff
  prefix ending there. `Methodology.input` is always `Fresh`.
- **Profile:** `Profile.create` declares metadata and explicit typed assignments;
  duplicate keys are rejected even when their values agree.
- **Entry:** `Catalog.Entry.create ~methodology ~profiles ~default_profile`
  checks duplicate profile IDs, the per-flow default reference and **every**
  profile's assignments against the methodology's configurable set.
- **Catalog:** `Catalog.create ~entries ~default_flow ~default_profile`
  checks duplicate flow IDs and both default references. The catalog default
  profile may differ from that flow's per-flow default profile. Empty catalogs
  and empty profile collections cannot satisfy their required defaults.
- **Resolution:** `Catalog.resolve ?selection ?request catalog ~endpoint ()`
  checks selection, endpoint and typed request assignments, then freezes the
  selected entry, selected profile, endpoint, stages and resolved parameters.
  `Catalog.declaration` retains the entire original catalog, including both
  kinds of default and complete selected/unselected declarations.

Selection semantics are exact:

| Request | Result |
| --- | --- |
| No selection, or `Selection.default` | Catalog's declared flow/profile pair |
| Explicit flow, no profile | That flow's declared default profile |
| Explicit flow and profile | That exact pair |
| Profile without flow | Constructor error |
| Unknown flow/profile or unsupported endpoint | Resolution error; no fallback |

Canonical ordering candidates are supplied, **not a wire identity contract**:
catalog entries and profiles sort by stable ID, endpoints by fixed physical
order, and configurable keys, assignments and resolved parameters by backend
key string. Strategy enum values retain the backend's declared enum order.

## Initial parameter boundary and evidence

Only these two knobs are representable as assignments:

| Typed key | Type / allowed values | Documented backend default |
| --- | --- | --- |
| `Synth_strategy` / `SYNTH_STRATEGY` | `Strategy.Area_0` … `Area_3`, `Delay_0` … `Delay_4`; backend strings `AREA 0` … `AREA 3`, `DELAY 0` … `DELAY 4` | `AREA 0` |
| `Synth_abc_buffering` / `SYNTH_ABC_BUFFERING` | OCaml boolean | `false` |

Verified against the installed `.toolchain/.venv` package: Python package
metadata reports LibreLane **3.1.0.dev3**. Read-only source evidence:

- `librelane/steps/pyosys.py:415–435`: exact `Literal` strategy enum,
  strategy default `AREA 0`, buffering boolean and default `False`.
- `librelane/steps/pyosys.py:631–648`: `Yosys.Synthesis` step identity.
- `librelane/scripts/pyosys/synthesize.py:465–474`: strategy passed to ABC
  script generation.
- `librelane/scripts/pyosys/construct_abc_script.py:72`: buffering consumption.

`Parameter.descriptors` exposes key, enum/boolean type, allowed values, backend
default, units (`None`), semantic meaning and versioned backend consumer.
`synth_strategy` and `synth_abc_buffering` construct assignments directly.
`of_string_value`, `of_bool_value` and `of_scalar` provide checked scalar
boundaries for the eventual wire reader. Unknown keys (including deprecated
`SYNTH_BUFFERING`), unknown enum strings, whitespace/case variants, wrong scalar
types, numeric booleans and null are rejected. There is no raw-key assignment
escape hatch. Objects/arrays and wire envelopes belong to the later decoder.

### Explicit values and provenance

Precedence is **methodology defaults → profile assignments → typed request**.
Duplicate keys within any layer are errors; keys must be configurable in every
layer, including methodology defaults. One override across different layers is
valid. Resolution includes only explicitly assigned keys. Descriptor defaults
are documentation, never injected as provider assignments or claimed as observed
runtime values. Even a configurable key may remain unspecified.

For each item from `Catalog.parameters`:

```ocaml
let winner = Flow.Parameter.winning resolved_parameter in
let assignment = Flow.Parameter.assignment winner in
let key = Flow.Parameter.assignment_key assignment in
let value = Flow.Parameter.assignment_value assignment in
let origin = Flow.Parameter.origin winner in
let replaced = Flow.Parameter.overridden resolved_parameter in
(* replaced: oldest to newest, excludes winner; equal values still retained *)
```

Origins are `Methodology`, `Profile` and `Request`. The associated identities
and full original layers remain available from the selected entry/profile and
declaration snapshot. A changed catalog default or another catalog using the
same IDs cannot change an earlier result.

## Checks and bounded evidence

The executable in `test/catalog_domain/` directly links **only** the public
`hardcaml_asic.flow_domain` library. It compiles and exercises declarations and
resolution without a hardware or execution-library dependency. Its 149 checks
cover ID/label validation, recipe rejection, exact enum/scalar parsing, descriptor
metadata, default/dangling/duplicate failures, all six physical prefixes,
endpoint restrictions, gating of every assignment layer, default-selection
semantics, canonical ordering, precedence with overridden values/origins,
runtime-unspecified values, independent catalogs, and immutable prior snapshots.

Successful checks (Dune invocations run sequentially with a maximum of 20 jobs):

```sh
dune build -j20 @test/catalog_domain/runtest
dune build -j20 @install @all
```

This is pure-model/build evidence. Physical execution, a versioned wire payload,
plan hashing and Project/settings integration are subsequent slice work. Existing
`Flow.t`, stage/recipe APIs and upstream LibreLane/TT implementations retain
their existing semantics.

## Exact handoff for Project integration

1. Add project-owned catalog storage/discovery using these abstract types.
   Keep declaration discovery independent of hardware elaboration. Reuse
   `Selection.create` and `Catalog.resolve` for the default rules rather than
   recreating them in Project, a CLI or Workbench.
2. Pass the chosen endpoint and typed request assignments into `Catalog.resolve`.
   Retain that **resolved value** for preview and publication/launch. Extract
   selected IDs with `Methodology.id (Catalog.Entry.methodology
   (Catalog.entry resolved))` and `Profile.id (Catalog.profile resolved)`;
   retain `Catalog.declaration resolved` for the full declaration snapshot.
3. Integrate effective typed parameters at the existing settings-resolution
   boundary (`lib/resolved_flow.ml`, `resolve_settings`), **before** bundle
   rendering/publication. The current legacy path reads
   `Elaborated_project.flow` and merges raw `Flow.Librelane.overrides` over
   derived settings. Slice 1 intentionally does not merge or classify those
   overrides. The next slice must define/check their interaction with typed
   methodology/profile/request settings, retain their origins, reject ambiguity
   and protected-fact conflicts, and preserve unrelated supported settings.
   Do not silently concatenate the two assignment sources or accidentally let
   a legacy override erase a typed request's provenance.
4. Consume **checked** `Catalog.parameters` through the accessors above. At the
   backend boundary, map `Key.to_string` to the backend key; map
   `Parameter.Strategy s` using `Strategy.to_string s` to a JSON string, and
   `Parameter.Bool b` to a JSON boolean. Preserve winning and overridden
   contributions in new evidence; the old `Setting.Override reason` string alone
   cannot represent this provenance. Do not materialize descriptor defaults to
   fill absent keys. Project-owned existing settings may still supply values
   for keys this pure result leaves unspecified, subject to the new checked merge.
5. Use `Catalog.stages`, `Catalog.endpoint` and the closed backend recipe to
   prepare the existing fresh execution path. `Flow.Stage.t` aliases the same
   `Stage_id.t`, so there is no stage-name translation to invent. The new
   `Methodology.Backend_recipe` identifies supported composition; it is distinct
   from the existing execution-oriented `Flow.Recipe.t`. There is no checkpoint
   input/continuation capability in this model.
6. Define the versioned wire encoding and canonical identity in the next slice.
   Serialize through the full declaration/selection/result accessors, include
   effective settings in bundle/plan identity before publication, and retain
   the frozen selected snapshot in execution evidence. Checked constructors are
   available to validate every decoded declaration and scalar assignment.

Files delivered here: ten new domain `.ml`/`.mli` files under `lib/flow/`, five
aliases in `lib/flow.ml`, `test/catalog_domain/dune` and its direct consumer,
and this progress record.

## Bounded slice 2: checked public pre-bundle seam (2026-10-14)

Delivered additive `?methodology:Flow.Catalog.resolved` on
`Resolved_flow.resolve`, `Project.elaborate_for_flow`, `Project.emit_bundle` and
`Project.emit_bundle_to_store`. Published `Project.render_bundle` exposes their
exact shared rendering sequence as an in-memory `Bundle.t`. It reads the declared
source inventory and Git using the existing emission contract. After comparing a
preview hash, call `Bundle.publish`/`Bundle.write` on **that same bundle**, without
calling an emission method or rendering again.

`Project.t` stays abstract and immutable. Neither the source declaration nor its
`Flow.t` is replaced. The resolved result retains the original checked snapshot
in `methodology` and exposes private immutable
`Effective_parameter.{t,contribution}` records through `effective_parameters`.
Their typed assignments, winning owners and oldest-first overridden history
include project assignments with their original `Owner.Override reason` intact
(including template-origin text). Catalog contributions use the additive
`Owner.Methodology Parameter.origin` constructor. All existing owner strings and
the no-methodology path retain their meaning.

Merge precedence is provider defaults → existing project assignment → methodology
default → profile → request. Configurable inherited project values are strictly
validated even when a later catalog value replaces them; numeric/string booleans
and noncanonical enums fail. Unconfigurable project overrides survive as raw
settings. The authoritative protected-key check still runs before this merge;
the typed winners are also checked against it. Existing declaration/domain checks
reject duplicate keys per layer. Configurable keys left unassigned by both project
and catalog remain unspecified; descriptor defaults are not emitted.

Bundle config uses the actual backend keys and JSON scalar types. The existing
manifest settings/owner representation records typed winners without adding
manifest fields or changing its schema/source stamp. Full snapshot and merge
history are exposed on `Resolved_flow.t` for the next rendered-plan format.

Checks completed, sequential Dune invocations at `-j20`, no EDA:

```sh
dune build -j20 @test/catalog_domain/runtest @test/runtest-hardcaml_asic_test
dune build -j20 @install @all
python3 -B test/check_project_api.py
python3 -B test/check_resolved_flow_api.py
python3 -B test/check_methodology_legacy.py
```

The inline suite covers lifecycle/resolution, inherited/default/profile/request
precedence, strict enum/bool validation, preserved reasons/history, independent
immutable resolutions, unspecified values, protected facts and duplicate refusal.
The installed-tree external Project consumer exercises AREA 0 vs DELAY 1 profiles,
explicit false buffering, distinct identities, identical generated RTL/clock SDC,
emission/render equivalence, and publication of the previewed concrete bundle
without elaborating again. Compiler negatives reject forged effective records.
The legacy regression script builds the pre-seam Project/settings implementation
from provider `0d04bae` in a disposable directory and compares both emitters over
the same current inputs/Git state: **47/47 files byte-identical** for each of the
observable and memory fixtures, including config, SDC and manifest.

### Next wire/plan handoff

Slice 1 handoff items 3–4 are now implemented. Define a versioned rendered-plan
encoding and canonical hash from the checked declaration/selection snapshot **and
the actual `effective_parameters`**, including original project attribution and
overridden contributions. Keep this additive metadata in the rendered plan, not
the source stamp or an unversioned manifest extension. Endpoint/stage preparation,
catalog discovery/storage and CLI/Workbench payload decoding remain subsequent
work; the execution recipe schema is unchanged. A profile-only identity difference
with identical settings is a plan-identity concern; differing emitted configurations
already have distinct bundle identities. Preserve the concrete bundle across
preview/publication so changing source/Git observations cannot replace the preview.

Slice 2 files: `lib/project.{ml,mli}`, `lib/resolved_flow.{ml,mli}`,
`test/test_resolved_flow.ml`, `test/project_api_consumer.ml`,
`test/check_resolved_flow_api.py`, `test/check_methodology_legacy.py`, this record.
The prior accumulated domain edits and user-owned namespace document are preserved.

## Bounded slice 3: strict wires, identities and preparation (2026-10-15)

Delivered additive **`Flow_spec`**, **`Methodology_plan`**, and **`Plan_json`**
`.ml`/`.mli` APIs in the main `hardcaml_asic` library. The catalog domain remains
Core-only; execution still depends on main, with no reverse dependency. `Flow.t`
retains its existing adapter/operation meaning. The supported methodology remains
the closed `librelane.classic.v1`, fresh complete physical prefixes only.

### Wire and discovery data

`Flow_spec` supplies the following version-1 contracts. All envelopes have exact
`contract` and integer `schema_version` fields; readers reject unsupported versions,
unknown/missing fields, duplicate object keys and declarations, nonfinite numbers,
Yojson extensions, unknown typed keys and noncanonical enum/bool values. Readers
return actual checked domain values, never unconstrained wire records.

| API | Contract / payload |
| --- | --- |
| `declaration_to_yojson`, `declaration_of_yojson`, `declaration_of_string` | `hardcaml-asic.flow-catalog`: full entries and explicit catalog default pair |
| `list_to_yojson`, `list_of_yojson` | `hardcaml-asic.flow-list`: declaration, parameter descriptors, selection/execution capabilities |
| `describe_to_yojson`, `describe_of_yojson` | `hardcaml-asic.flow-describe`: checked entry, descriptors, capabilities |
| `selection_to_yojson`, `selection_of_yojson` | exact `{flow, profile}` with stable IDs or null; profile requires flow |
| `resolved_to_yojson`, `resolved_of_yojson` | `hardcaml-asic.flow-snapshot`: frozen full declaration, explicit selected IDs, selected definition/profile, endpoint, complete ordered stages, typed request, winning/overridden evidence |

List/describe are declaration-only: no design construction, source/Git reads or
tools. Descriptors explicitly distinguish **documented backend defaults** from
runtime-unspecified values; they never become effective assignments. Capabilities
describe fresh prefixes and exact default/selection rules without making runtime
availability claims. They are the JSON selection data seam for later Workbench
discovery, not a CLI or consumer implementation.

Snapshot decoding resolves the stored declaration, selected IDs, endpoint and
typed request using `Catalog.resolve`, then compares all selected facts and complete
winner/history evidence with the re-encoded checked result. Catalog mutations in
future requests cannot alter these immutable snapshots.

### Rendered result and prepare API

`Project.Rendered.t` is abstract and inseparable. Only `Project.render_result`
constructs it by the existing elaboration/resolution/simulation sequence and one
`Bundle.render`. Its accessors are `resolution` and `bundle`. Existing
`render_bundle`, `emit_bundle` and `emit_bundle_to_store` retain their signatures
and share this implementation. No constructor accepts an arbitrary resolution and
unrelated bundle. `Methodology_plan.of_rendered` checks the emitted configuration,
legacy manifest identity, project, actual typed values/owners and replayed merge.
It does not parse owner S-expressions; project attribution comes from the checked
project flow and typed resolver records.

`Methodology_plan.prepare` accepts a Project, catalog, endpoint, optional selection,
typed request, target inputs, simulation option, `catalog_inputs`, and
`expected_plan_identity`. It resolves selection before elaboration, renders exactly
once in memory, derives the checked plan, and fails a stale expected comparison
before publication or tool probes. Source/Git observations are allowed; workspace
writes and EDA are absent. Relative consumer catalog files supplied through
`catalog_inputs` join Project's declared source inventory under Bundle's existing
copy/hash/revision rules. There is no inferred discovery inventory.

```ocaml
let%bind prepared =
  Methodology_plan.prepare ~catalog ~endpoint:Flow.Stage.Synthesis
    ~catalog_inputs:[ "asic/flows/standard.ml"; "asic/flows/profiles.ml" ]
    ?expected_plan_identity project ~source_root
in
let plan = Methodology_plan.Prepared.plan prepared in
let bundle = Methodology_plan.Prepared.bundle prepared in
(* Show Methodology_plan.to_yojson plan; preserve prepared until publication. *)
Bundle.publish bundle ~store_dir
```

The immutable prepared value is the client handoff. Publish that bundle later,
without calling Project emission/rendering again. A deserialized plan is checked
evidence, not a deserialized Bundle or a publication authorization; only a prepared
render result carries the actual concrete bundle.

### Plan v1 and canonical identity contract

`hardcaml-asic.methodology-plan` v1 contains:

- `methodology.snapshot`: selected stable IDs, definition/profile and complete
  frozen declaration, endpoint/stages and checked request/provenance;
- `methodology.project_assignments`: configurable typed project assignments with
  original nonblank override reasons, sorted by backend key;
- `methodology.effective_parameters`: actually assigned typed winners and complete
  oldest-first overridden project/methodology/profile/request contributions;
- `methodology.translation`: the closed versioned backend/enum-string/boolean,
  fresh-input, runtime-unspecified and schema-3 translation contract;
- `methodology.recipe`: exact existing fresh `Flow.Recipe` schema-3 JSON;
- `methodology_hash`, `project_name`, `bundle_identity`, `bundle_manifest`,
  `configuration_bytes`, and `plan_identity`.

`Resolved_flow.resolve_effective_parameters` is the pure checked replay seam: it
validates unique configurable typed project assignments and original reasons,
then calls the **same merge** used by actual resolution. Plan decoding replays it,
reconstructs the fresh recipe, verifies snapshot/effective/history/configuration
associations (including Bundle's floorplan-path rewrite and generated source/SDC
settings), and recomputes both identities. Re-signing a mismatched bundle/config
and all outer hashes still fails the effective-value correspondence check.

Main owns **`Plan_json` v1**, not execution's Python-compatible `Identity_json`.
Canonical objects sort by bytewise string key, assignment maps are produced in
checked backend-key order, and arrays representing stages/history preserve sequence.
Scalars use Yojson.Safe's compact finite JSON spelling. SHA-256 hashes compact
canonical `{contract, schema_version:1, payload}` envelopes with distinct
`hardcaml-asic.methodology-hash` and `hardcaml-asic.plan-identity` discriminators.
Later execution must call this main-library implementation; do not substitute a
Python JSON encoder for arbitrary floats/strings.

`methodology_hash` covers the snapshot, project assignment attribution, actual
effective typed settings, backend translation and recipe. `plan_identity` covers
the complete versioned plan payload without its own assertion, including project
and concrete bundle/configuration evidence. Definition/profile-only changes affect
plan identity even when Bundle bytes agree. Emitted configuration, catalog input
bytes and source revision changes affect Bundle/plan identity. Timestamp, workspace,
attempt and observed executable/tool paths have no plan fields and are rejected.
Neither hash is a **P6 source stamp**, tool observation or execution-attempt identity.

Existing Bundle identity is unchanged and remains order-sensitive. The plan retains
its compact manifest as a JSON **string** to preserve that legacy field order,
with exact configuration bytes and their manifest file digest. The additive pure
`Bundle.verify_manifest_identity` uses Bundle's existing algorithm. Plan canonical
object sorting must never be used to recompute Bundle's identity.

### Evidence and bounded handoff

Checks completed sequentially; every Dune invocation uses `-j20`:

```sh
dune build -j20 @test/plan_contract/runtest @test/catalog_domain/runtest @test/runtest-hardcaml_asic_test @install @all
python3 -B test/plan_contract/check.py --installed
python3 -B test/check_resolved_flow_api.py
python3 -B test/check_project_api.py
python3 -B test/check_methodology_legacy.py
```

The focused contract driver passes **79 checks** covering strict declaration/list/describe/snapshot/plan
roundtrips and rejections, duplicates, finite scalar boundary, canonical ordering,
definition/profile/endpoint/target/project-attribution identity changes, unspecified
backend defaults, tampered metadata/effective/history/recipe/translation and fully
rehashed mismatched bundle/configuration evidence. Two profiles emit AREA 0 vs
DELAY 1 and boolean false in actual config bytes with identical RTL/SDC/input bytes.
The Python driver independently checks fixture hashes, relocated roots, source and
catalog file changes and Git-only revision changes. Stale comparison leaves output
directories absent. Publication uses the prepared bundle with one elaboration even
when source bytes change between prepare and publish. An unrelated installed-tree
build exercises the same public API and compiler negatives for abstract plan,
prepared value and render pair. The legacy fixture excludes only the additive plan
module while replacing Project/resolver with the pre-seam versions; observable and
memory bundles are each **53/53 files byte-identical** to that baseline.

**Next native-enforcement handoff:** execution should consume this checked plan and
the *same* prepared bundle, verify their identities before runtime preparation,
enforce the fresh schema-3 endpoint/translation contract, use main's identity
algorithm, and retain snapshot/effective provenance in attempt evidence. Runtime
tool/PDK/bundle-file verification, native backend application/receipt checks and
attempt ownership remain execution's boundary. Catalog discovery/storage, CLI
decoding and Workbench consumer wiring remain subsequent work. Preserve the
distinction between documented backend defaults and applied typed values.

Slice 3 files: new `lib/{flow_spec,methodology_plan,plan_json}.{ml,mli}`;
additive `lib/project.{ml,mli}`, `lib/resolved_flow.{ml,mli}` and
`lib/bundle.{ml,mli}` seams; `test/plan_contract/`; the legacy fixture build adapter;
and this progress record. Prior accumulated code and the user-owned namespace
document remain preserved. No live Git staging/commit/push/stash/reset was used.

## Bounded slice 4: native enforcement and immutable attempt evidence (2026-10-15)

### Production command and authority

The additive public native route is:

```sh
hardcaml-asic-flow stages BUNDLE \
  --methodology-plan PLANFILE --expected-plan-identity HASH \
  --support-tools TT --pdk-root PDK --python HOST_VENV_PYTHON \
  --workspace FRESH_WORKSPACE --checkpoint-store FRESH_WORKSPACE/checkpoints --json
```

Selection is exactly one of `--methodology-plan`, ordinary `--plan`, or
`--endpoint`. Named launches require a lowercase SHA-256 expected identity and
reject `--checkpoint`; the delegated native helper also rejects explicit
`--through`, `--stages`, ordinary `--plan` and checkpoint combinations. No resume
or executable-command authority is added to the plan. CLI4 remains version 4 and
advertises the additive boolean `cli_contract.capabilities.namedflow1`. The source
reference identity oracle is deliberately extended only in the native comparison
test (`test/check_native_cli.py`), not in retired Python production routing.

`Methodology_execution_service.check` is the no-write/no-probe boundary. It consumes
`Methodology_plan.t`, compares the expected identity, verifies the actual manifest
against the plan's frozen manifest and Bundle's legacy identity algorithm, checks
exact config bytes, every inventoried file digest, safe paths and complete copied
source-input digest associations. The frozen manifest includes source revision,
settings, configuration, target and requested runtime policy. The plan decoder uses
main's `Plan_json`/`Methodology_plan` algorithms and checked frozen domain values;
there is no re-resolution against a current external catalog. Only the closed
`librelane.classic.v1` and its two typed knobs are supported. The returned ordinary
schema-3 fresh prefix feeds existing `Stage_preparation`/`Segment_service`/`Runner`.
Parameters have already been materialized into the bundle; no adapter Python
translation or new EDA path was introduced.

The CLI checks before runtime path selection and probes. Stage_preparation repeats
the bundle/plan association check for direct library callers, before any runtime
probe or staging. Existing early observation allocation/failure reporting is
retained; neither pending allocation nor a checked plan asserts runtime readiness.

### Exact snapshot/reference contract

Named execution JSON adds **only optional `methodology`** at the Runner record
level. Its absence preserves the old serialization exactly. Its value has exact
fields:

```json
{
  "contract": "hardcaml-asic.methodology-execution-reference",
  "schema_version": 1,
  "attempt_id": "<actual Runner/observation stream ID>",
  "snapshot_path": "<canonical absolute retained path>/methodology-plan.json",
  "snapshot_sha256": "<SHA-256 of exact snapshot bytes>",
  "expected_plan_identity": "<required preview hash>",
  "plan_identity": "<checked main-library identity>",
  "methodology_hash": "<checked main-library methodology hash>",
  "bundle_identity": "<checked concrete bundle identity>"
}
```

`Methodology_execution_record.publish` writes main's canonical plan bytes once,
using an exclusive temporary file and atomic hard-link no-replace publication.
An existing snapshot is never overwritten. The snapshot is read-only on initial
publication; integrity relies on the retained checksum and checked identities,
not mode bits. Context fields are in the reference, outside the plan content hash.
As with existing immutable storage, visibility is atomic, not fsync crash durability.

The exact snapshot directory is the owned observation attempt, or the allocated
preflight operation directory when observation is disabled. There is no newest
directory search or lookup of the source PLANFILE on reads. The operation receipt,
preflight report and `prepared.json` retain the same reference; ready receipt
publication follows snapshot publication. Failed preflight retains the published
reference in the receipt and previous report. Failed/interrupted execution keeps
the reference on early/running and terminal summaries. Every named summary
serialization checks the reference's snapshot, attempt and stage plan.

For named launches only, the operation receipt and `prepared.json` also retain an
explicit `request` object containing that complete `methodology` reference, derived
ordinary `plan`, `bundle`, `workspace`, `checkpoint_store`, `support_tools`,
`pdk_root`, `python`, `docker`, `git`, `resources`, `timeout_seconds` and
`probe_timeout_seconds`. This request comes from native execution arguments, not
freeform caller metadata; it is persisted before probes, including when observation
is disabled. Tool roots and limits remain outside all plan identity hashes.

The public initial allocation has additive `methodology` metadata with `state:
"pending"`, expected identity, actual identity null, exact `snapshot_path`, and
`reference: null`. The immutable allocated observation request adds
`methodology_launch: {state, attempt_id, expected_plan_identity, snapshot_path}`.
This is a pending reference to the exact future snapshot, not ready evidence.
The native request still records caller tool roots and limits separately. On an
early terminal error, `methodology.state` becomes `checked` only when the snapshot
has actually been published, with its complete reference; otherwise it stays
pending. A decoded but stale plan can expose its actual identity while pending.
Normal terminal execution JSON carries the complete `methodology` reference.

### Reader and next-agent handoff

- `Stage_execution_record.of_json`/`read` expose optional typed `methodology`.
  Present references require the exact regular sidecar, checksum, strict plan
  decoder, expected/actual/methodology/bundle identities, matching attempt and
  schema-3 recipe. Published checkpoint references must match that bundle and their
  publication identities. Missing/mutated required sidecars fail, never silently
  downgrade to legacy. Absent references use the historical reader behavior.
- `Methodology_execution_record.plan` exposes the immutable checked historical
  plan (including selected profile, effective winners and override history).
  Reports include the raw execution reference and now parse it successfully;
  richer historical presentation is left for the next agent.
- Native full-flow finalization accepts the optional reference and validates it
  and the selected checkpoint bundle links. Its historical no-reference branch
  explicitly preserves the older reduced-occurrence selection contract; new named
  records require complete Runner validation. Terminal finalization still records
  the explicit source execution path/hash, not a guessed workspace or catalog.
- Consumer discovery/project CLI/Workbench wiring remains the next agent's work.
  Reuse the prepared concrete bundle, the public command above and the record API;
  do not elaborate again after preview or consult live catalog definitions when
  presenting historical runs. Runtime tool roots, resources and limits remain
  request facts, with installed prefix resources and no source fallback.

### Checks and bounded evidence

All Dune invocations were sequential and used `-j20`:

```sh
dune build -j20 @test/ocaml-stage-preparation @test/ocaml-finalization @test/ocaml-stage-report @test/ocaml-runner @test/plan_contract/runtest @test/catalog_domain/runtest @test/runtest-hardcaml_asic_test @install @all
python3 -B test/check_methodology_execution.py
python3 -B test/check_native_cli.py
python3 -B test/check_stage_preparation.py --installed
```

The new installed-prefix named fixture uses actual Project-rendered bundles and
main-generated plans for AREA 0 and DELAY 1 with explicit false buffering. Both
complete **all six native stages**, transporting the production bridge against
fixture LibreLane APIs, retain distinct emitted config bytes and backend-resolved
`resolved.json` typed values at every checkpoint, together with immutable
references, and one completes native results-only full-flow finalization. It
rejects stale hashes, plan/bundle mismatch, changed config/source files, corrupted
source hashes/stages/typed keys/backend and conflicting/fresh-only selections
before any fake probe event or workspace creation. Historical reads survive
original-plan removal/edits and fail for changed reference identities, snapshot checksum
changes and snapshot removal. Real SIGTERM and failed backend process summaries
retain truthful references; runtime policy failure retains a checked snapshot with
no prepared workspace. Kernel file/process traces of installed six-stage fixtures
show no checkout accesses or retired provider Python modules. Runtime fixture
engines and the retained bridge are Python test/backend machinery; metadata and
historical native reads run with Python/PATH denied.

The original native fixture recomputed **all** bundle/plan identities after
corrupting only the source-input metadata digest. At slice 4 delivery the plan
decoder accepted that wire and execution rejected it. The review correction below
moves this association rejection into pure decoding as well. Snapshot presence is asserted by the fake engine at
its very first probe. Observation opt-out still persists the explicit reference in
the exact preflight operation, and missing required sidecars also prevent native
full-flow finalization before any new fake probe.

The legacy preparation suite passes **51** source-mode and **51** installed-mode
checks, the latter with checkout reads denied; the Runner parity suite passes
**628** cases; stage reporting passes; finalization passes **26** original fixture
invocation differentials and **16** original tests plus native protocol checks.
The plan contract remains **79** checks. The native CLI metadata/presentation,
routing and Python/source-denied corpus passes with its intentional `namedflow1`
capability extension. An initial finalizer regression exposed reduced historical
occurrences and was fixed with the explicit historical branch above.

This is production orchestration and fixture-backend evidence, not new physical
EDA/PDK readiness or acceptance evidence. No long EDA was run, no subagents were
spawned, and no live Git stage/commit/push/stash/reset was used. All accumulated
slice 1–3 edits and the user-owned namespace document remain preserved.

## Provider review correction: findings 1 + 4 (2026-10-15)

### Reproduction and bounded fix

Before correction, sequential `dune build -j20 @test/plan_contract/runtest`
regression runs failed with `Failure "rehashed bad-source"` and
`Failure "rehashed omit:constraints/top.sdc"`: each assertion expected a decoder
rejection, but decoding accepted the fully rehashed incomplete evidence. Both
Bundle's order-sensitive identity and main's plan identity had been recomputed.

New main-library **`Methodology_inventory.verify`** is pure and shared by
`Methodology_plan` construction/decoding and native
`Methodology_execution_service.check`. It enforces the closed named classic v1
provider translation, without changing the Bundle schema, bytes, identity
algorithm, or legacy execution:

- Inventory paths are unique safe relative file names, with lowercase SHA-256
  digests and no file/descendant collisions.
- Every source input has a safe original path, exactly `inputs/<path>` as its
  copy, and the same digest as that unique inventory record. Copies are nonempty,
  duplicate-free, and exhaust the `inputs/` inventory subset. The former
  intentionally accepted bad-source fixture now requires pure decoder rejection.
- Config bytes require their inventoried digest. Generated `VERILOG_FILES` must
  be the exact single provider `dir::<top>.v` link, and both generated SDC
  references must be `dir::../constraints/top.sdc`. Their actual bundle paths
  must be inventoried. Both SDC references intentionally share one inventory
  record; this is not treated as a duplicate file.
- Declared synthesis and simulation source lists require inventoried files and
  the provider's exact single-source layouts. Simulation may intentionally reuse
  synthesis RTL or name the separately generated `simulation/<top>.v` file.
- The support-tools floorplan link retains the existing exact target association
  and requires a literal safe path. Additional config path/script/Macro variables
  and their deprecated aliases are conservatively refused with a named-contract
  error, rather than being expanded or accidentally consumed from the copied
  bundle. The path-key list is source-traced to installed LibreLane
  **3.1.0.dev3** Classic `get_all_config_variables` Path/Macro descriptors and
  deprecated aliases (`config/flow.py`, step `config_vars`). Generic expression
  strings and conditional configuration are rejected without interpreting them;
  `meta` cannot introduce a separate generic config contract. Ordinary raw
  non-path project knobs remain accepted, including the existing TT overrides.

Native verification still hashes the actual files, compares exact configuration
bytes and the frozen manifest, and retains its existing regular-file/realpath
containment checks. No filesystem access was added to decoding. Execution still
depends on main, with no reverse dependency.

### Exact checks and evidence

Successful commands below ran sequentially; every Dune invocation, including
disposable builds inside scripts, used `-j20`:

```sh
dune build -j20 @test/plan_contract/runtest @install @all
python3 -B test/check_methodology_execution.py
dune build -j20 @test/catalog_domain/runtest @test/runtest-hardcaml_asic_test @test/ocaml-stage-preparation @test/ocaml-finalization @test/ocaml-stage-report @test/ocaml-runner
python3 -B test/plan_contract/check.py --installed
python3 -B test/check_resolved_flow_api.py
python3 -B test/check_project_api.py
python3 -B test/check_methodology_legacy.py
python3 -B test/check_native_cli.py
python3 -B test/check_stage_preparation.py --installed
```

The source and independently linked installed plan consumers pass **108 checks**,
including valid separate simulation RTL, shared SDC/source references, and **27**
fully rehashed inventory/config mutations. The native installed integration repeats
all 27 with the attacker's recomputed expected hash; omitted bytes remain present
and are changed before launch. Every case rejects before a probe marker or
workspace exists. Independent unchanged-plan native cases reject changed copied
source, RTL, SDC and an escaping internal filename symlink (even with identical
target bytes). Both genuine profiles still complete all six fixture-backed native
stages and retain valid historical/finalization evidence. The first integration
invocation exceeded the harness's 120-second timeout; rerunning with a 600-second
limit completed successfully.

Project/Resolved_flow installed API checks pass. Legacy observable and memory
bundles are each **55/55 files byte-identical** against the pre-seam provider
implementation. Other successful checks retain **628** Runner parity cases,
**51** preparation checks in each source/installed mode, **26** finalization
differentials and **16** original finalization tests, reporting, and native CLI
metadata/routing/source-denied cases.

### Handoff

This correction is limited to review findings **1 + 4**, pure plan/native input
inventory integrity. Subsequent staged-copy race/runtime-probe contract work is
still a separate handoff. If the named translation grows new executable inputs,
extend its explicit pure associations and negative fixtures together; do not
replace this boundary with a generic LibreLane expression parser. Producer bundle
generation and legacy behavior remain unchanged. The accumulated consumer changes
and user-owned namespace document were preserved. No subagents were spawned and
no live Git staging/commit/push/stash/reset was used; fixture Git writes occurred
only in disposable test repositories.

Correction files: `lib/methodology_inventory.{ml,mli}`,
`lib/methodology_plan.ml`, `lib/execution/methodology_execution_service.ml`,
`test/plan_contract/consumer.ml`, `test/check_methodology_execution.py`, and this
progress record.

## Provider review correction: findings 2 + 3 (2026-10-15)

### Frozen staged inputs and actual applied parameters

Named `Stage_preparation.prepare` now retains verification closures over the
**checked immutable plan**, plus the measured declared collateral digests. This
baseline is not captured from the workspace's current configuration at execute
time. `Methodology_execution_service.check` verifies the actual staged project
against the plan's frozen manifest, exact configuration bytes, pure checked input
associations and every inventoried file hash. Thus the physical config, generated
RTL, SDC and copied source paths used by the closed provider translation still
match the published bundle. Declared original collateral files and staged
support-tools copies are also rehashed against preparation's retained evidence.

`Segment_service` invokes this verifier at Runner validation, before **each**
backend call (including publication validation), after each successful backend
call, at publication entry, and immediately before atomic checkpoint promotion.
The publisher's additive `before_promote` veto executes even for host-only closure
and propagates the original Runner error after owned staging cleanup. The
existing resource hash and runtime binding checks remain in place. No failed
input/parameter check advances Runner's checkpoint source; the actual named error
is retained as primary failure and in diagnostics. An earlier successful boundary
can remain published when a later boundary fails.

Only frozen inventoried inputs and declared collateral are input baselines.
Backend-generated requests/replies, `runs/`, candidates, constructed markers and
supplementary reports are intentionally outside that inventory. Existing backend
closure/artifact verification remains authoritative for tool-generated output and
runtime dependencies. This is tool-call closure pre/post validation with trusted
stable parents and exclusive workspace use, **not** a race-free sandbox against
arbitrary adversarial filesystem mutation between checks.

New `Methodology_execution_service.check_resolved` compares every explicitly
effective named parameter with the actual backend `resolved.json`: strategy must
be the exact expected enum **string**, buffering the exact expected **boolean**.
Missing/duplicate assigned keys, null, numeric/string boolean encodings and
different values all fail. Unassigned documented defaults are not materialized or
claimed as observed. Successful execute and validate-publication replies, the
candidate at publication entry, and final staging before promotion all require
this comparison. It therefore catches a backend ignoring or mistranslating a knob
even when the frozen input config still matches. Named historical execution
readers additionally validate checkpoint contents and compare `resolved.json`
against the retained checked plan. Reports/finalization selecting that named
reference share the check; no live catalog or original PLANFILE is consulted.

### Selected runtime declaration contract

`Mapping.settings "Yosys.Synthesis"` now declares:

- `SYNTH_STRATEGY`: enum, default `AREA 0`, exact ordered domain `AREA 0`–`AREA 3`,
  `DELAY 0`–`DELAY 4`. The domain is mapped directly from
  `Parameter.Strategy.all/to_string`, the domain library's single source of truth.
- `SYNTH_ABC_BUFFERING`: boolean, default `false`, no units or PDK-owned default.

Enum descriptors add optional `allowed_values`; existing non-enum descriptor JSON
retains its old fields. The stage metadata helper extracts `typing.Literal`
arguments as the enum domain, and reads `config_vars` from the actual selected
Classic step with `step.id == "Yosys.Synthesis"`. Installed source inspection
confirmed `steps/pyosys.py:397–435` (`SynthesisCommon`, input RTL in configuration,
Literal strategy and bool buffering); runtime introspection confirms both step ID
and implementation ID are `Yosys.Synthesis`. This does not assume an older Yosys
frontend module or flatten the Literal into an unchecked generic string.

`Classic_contract.validate_settings` rejects missing declarations and drift in
type, units, default, PDK flag or exact enum domain. New ordinary/unmethodologized
stage launches also require this current runtime contract. Existing persisted
historical metadata remains readable as evidence: no reader imposes a fresh
runtime declaration probe on old records, and no retained fixtures were rewritten.
Domain-only discovery has no backend imports. Default/coarse preflight still uses
the metadata-only branch, which does not import Classic; selected physical stage
preparation uses the enriched import-only probe.

The helper SHA-256 is now
`60e8da8444e76b95c43186eb5c2ff1d229175c500226caae3e41a5ccb4465425`,
recorded as metadata-probe evidence. Bridge/protocol bytes and their pinned hashes
are unchanged (`e8dc9532…da841` and `732c05a5…2e49d` respectively), so this does not
invent a new bridge identity for old checkpoints. Bundle/plan identity algorithms,
schemas and source stamps are unchanged.

### Verification and standalone boundary

Successful checks ran sequentially; all Dune invocations, including disposable
installed consumers, used `-j20`:

```sh
dune build -j20 @install @all @test/stage-domain @test/plan_contract/runtest @test/ocaml-stage-preparation @test/ocaml-segment-service @test/ocaml-finalization @test/ocaml-stage-report @test/ocaml-runner
dune build -j20 @install @all @test/ocaml-stage-preparation @test/stage-domain @test/plan_contract/runtest @test/catalog_domain/runtest @test/runtest-hardcaml_asic_test
python3 -B test/check_stage_preparation.py --installed
python3 -B test/check_native_cli.py
python3 -B test/plan_contract/check.py --installed
python3 -B test/check_methodology_execution.py
python3 -B test/check_stage_domain.py --installed --selected
git diff --check
```

After the public callback regression was added, `@install @all`, preparation,
segment-service, finalization, reporting and Runner aliases were rerun sequentially
in one `dune build -j20`, followed by the named integration script. Results:

- Public API prepare→mutate→execute rejects config AREA 0→DELAY 1, RTL, SDC and
  copied source edits before a transport launch or constructed-flow marker. Two
  injected **public Runner callback wrappers** mutate config/RTL after successful
  invoke and before publish; publication rejects with no checkpoint. Diagnostics
  retain the named failure rather than invented completion.
- Native fixture hooks mutate config/source during calls at synthesis/floorplan
  and source between stages. Failed boundaries publish nothing; between-stage
  mutation retains only synthesis and prevents a second transport launch.
- Ten wrong/missing backend-resolved cases cover ignored strategy, non-domain
  strategy, bool/null strategy, true/string/numeric/null buffering and missing
  assignments. The config file itself is unchanged; every case rejects publication.
- Both genuine profiles still complete all six native fixture-backed stages, and
  native full-flow finalization succeeds. Historical reads reject a fully rehashed
  wrong resolved config/checkpoint/reference for each profile, and still enforce
  sidecar integrity with Python/PATH denied. Prior inventory/stale-plan negatives
  and failed/interrupted attempt references continue to pass.
- Stage domain: 80 ordered occurrences, 14 inventory, five placement and **11
  synthesis declaration drift negatives**. Actual import-only probes pass against
  the installed host package and exact image
  `sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a`:
  LibreLane **3.1.0.dev3**, container Python **3.13.13**, including the enriched
  synthesis enum/type/default/domain and boolean/default. No full EDA was run.
- Preparation: **58** checks each in source and installed/source-denied modes,
  including seven new runtime synthesis-contract failures before workspace staging.
  Segment service: **70** checks. Runner: **628**. Finalization: **26** original
  differentials and **16** original tests. Stage reporting passes.
- Plan consumer: **108** checks in source and installed modes; pure catalog:
  **149** checks; resolution inline suite passes. Native CLI metadata, ten cold
  presentation differentials, 24 contract negatives, prefix routing and
  Python/source-denied queries pass.

Discovery, preview and run are standalone provider interfaces; none requires
Workbench. These independently linked installed consumers and native headless
fixtures exercise that boundary directly. Consumer/Workbench work and the
user-owned namespace document were preserved. No agents were spawned, no upstream
rewrite scripts were used, and no live Git add/commit/push/stash/reset occurred;
Git writes were confined to disposable fixture repositories.

## Bounded slice 5: provider-only historical presentation (2026-10-15)

Delivered `Historical_methodology.{recorded,pending,not_recorded,human}` with an
`.mli`, plus `Stage_report_service.methodology`. Named stage report schema-1
envelopes add normalized `hardcaml-asic.historical-methodology` v1 metadata:
frozen flow/profile IDs, labels and definitions; requested endpoint; methodology,
plan and bundle identities; effective typed winners and oldest-first origin
history; full frozen methodology; immutable snapshot reference and host validation.
Legacy stage/checkpoint/coarse report JSON and human contracts remain unchanged;
the accessor explicitly returns `not_recorded` for old evidence.

`Observation.inspect` adds `methodology`, `execution_request` and `execution_file`
outside hashed records and reduced state **only for named allocations**. Old
streams retain their exact JSON shape and human output; missing methodology means
`not_recorded` to clients. Early unpublished named launches return `pending`.
Named preflight reports now retain the
native request before probes, and inspection follows only the exact allocated
preflight path/previous-report chain. Failed preflight therefore retains request
and checked snapshot evidence without an execution file or workspace.

Inspection shares `Methodology_execution_record`'s strict decoder (additive
`of_reference_json` for attempts before a plan event). The execution reader's
checkpoint/bundle/content/backend-resolved typed-value verifier is factored into
`Stage_execution_record.check_methodology_checkpoints` and reused by inspection.
Missing/mutated required snapshots and mismatched references fail with exit 2,
never legacy fallback. No current catalog, active selection, original source plan,
Git, backend tools or runtime probes are consulted. Endpoint remains a request
under the fixed flow; unspecified runtime defaults remain unobserved.

Human named report/inspection output is compact ID/label/profile, endpoint, preview
identity and an effective-setting table before checkpoints/stages. `--verbose`
adds full provenance and frozen evidence. Native schema and API details are in
[the reference](../reference/native-historical-methodology.md), linked from the
provider stage guide; `observation describe` documents the additive inspect fields.

Checks completed during parallel consumer work; **every Dune command used `-j10`**:

```sh
dune build -j10 @install @test/ocaml-stage-report @test/ocaml-observation @test/ocaml-stage-preparation @test/ocaml-finalization @test/plan_contract/runtest
python3 -B test/check_methodology_execution.py --source
git diff --check
```

The actual native-helper fixture completes two profiles through six fixture-backed
stages, matches report/inspection identities and effective provenance against saved
plans/receipts, checks compact/verbose output, and proves report stability after
source plan/profile-catalog mutation and deletion. Required snapshot checksum,
absence and preflight-reference identity negatives fail explicitly. Existing
fully rehashed wrong-resolved checkpoint rejection, failed/SIGTERM request evidence,
and failed-preflight inspection pass. Read-updates remain byte-identical before
and after historical presentation/source changes. Old report byte-contract tests
pass. The original slice allowed additive legacy inspect fields; the full-regression
correction below restores exact legacy equality. Only the known describe extension
has an explicit fixture expectation (307 accepted, 2077 rejected, 173 queries,
22 incremental cases). Preparation passes 58 source-mode checks; finalization
passes 26 differentials and 16 original tests. No long EDA or live Git writes.

`@install` built the provider staging tree only; the consumer's frozen
`/tmp/opencode/catalog-headless-provider` was not overwritten. Installed scripts
were deliberately deferred until **both agents finish**, including scripts that
internally build with `-j20`. Standalone handoff:

```sh
dune build -j10 @install @all
python3 -B test/check_methodology_execution.py
python3 -B test/check_stage_report.py --installed
python3 -B test/check_observation.py --installed
python3 -B test/check_native_cli.py
```

This slice owns provider code/build/docs only. No agents were spawned; no live
stage/commit/push/stash/reset was used. Prior accumulated work remains preserved.

## Bounded provider + headless delivery integration (2026-10-15)

Closed the successful native terminal/reference gap. Named `stages --json`
delivery adds only `execution_file`, after matching the actual persisted record
against Runner output and validating it with `Stage_execution_record.available`.
The strict stored Runner record remains unchanged; legacy terminal bytes remain
unchanged. Named public `observation inspect` returns the same canonical absolute
reference from allocation alone, using the writer's shared deterministic `path`
constructor and the immutable allocated workspace/attempt, never directory search.
The new availability seam requires a regular readable record, strict execution
decoding, exact attempt/reference equality, checked recipe/plan/bundle/snapshot
and recorded checkpoint/backend-resolved values. No tools or live catalog needed.

Absent/empty reservations are null, including failed preflight with a checked
snapshot; malformed/tampered present evidence is an error. A completed named
attempt missing its record is an error. Available running/failed/interrupted
records remain host-readable evidence, not claims of completion or acceptance.
Delivery metadata does not enter hashed observation records or stored execution
schemas. Detailed payload/validation compatibility is documented in
`docs/reference/native-historical-methodology.md`.

Consumer `scripts/headless_flow.py` now obtains the report target exclusively from
public inspect, compares any stdout reference with it, and verifies report
plan/bundle/attempt identities against preview/allocation. Reconnect uses saved
allocation/stream/cursor with no preview, catalog resolution or launch. Old cached
blockers/reports are refreshed. Failed preflight explicitly records
`unavailable_no_execution_record`, client exit 1. A failed native execution can
have report query exit 0 and `report_status: available`, still client exit 1.
Acceptance remains separate and `not_evaluated` is preserved.

### Installed native integration evidence

Latest private thin prefix:
`/tmp/opencode/namedflow-delivery-provider-v3`; original frozen prefixes retained.
Consumer freshly linked under `_build_delivery` using that prefix's public
libraries. Test engine collateral prepared under
`/tmp/opencode/namedflow-delivery-engine-v4`. Retained consumer receipts, complete
reports, allocation-only reader caches and native records are under
`/tmp/opencode/namedflow-delivery-evidence-v3/`.

New `test/prepare_headless_engine_fixture.py` prepares test-only native inventory
and copies external engine scripts plus the actual pinned TT floorplan DEF. The
helper is fixture setup, never a client dependency. Runtime clients use public
discover/describe/preview/run/observation/report commands and an actual installed
thin provider. Native Stage_preparation, Runner, production bridge, checkpoint
publication, strict readers and reporting run for real; only the external tool
engine/backend APIs are mocked. Both consumer profiles (`balanced` AREA 0 and
`synth_delay` DELAY 1) complete synthesis and report; a third native exit17 case
reports recorded failure. A backend gate proves allocation is consumed before
completion, reader SIGINT leaves the owned launcher alive, and a cache with no
terminal stdout reconnects to the identical exact execution/report. Client
runtime PATH contains fixture tools only; reconnect has PATH/PYTHONPATH denied.
No Workbench dependency, provider Python imports or client Dune/source fallback.

Successful commands ran sequentially, all Dune builds/installs at `-j20`:

```sh
# provider
dune build -j20 @install @all @test/ocaml-stage-report @test/ocaml-stage-preparation @test/ocaml-observation
dune install -j20 --prefix /tmp/opencode/namedflow-delivery-provider-v3
python3 -B test/check_methodology_execution.py
python3 -B test/check_stage_report.py --installed
python3 -B test/check_observation.py --installed
python3 -B test/check_native_cli.py
# consumer, OCAMLPATH and HARDCAML_ASIC_TEST_PROVIDER bound to the v3 prefix
# HARDCAML_ASIC_ENGINE_FIXTURES bound to the v4 fixture directory
dune build -j20 --build-dir _build_delivery bin/project.exe acceptance/export_trace.exe @scripts/headless-test
python3 -B scripts/test_project_routing.py _build_delivery/default/bin/project.exe _build_delivery/default/acceptance/export_trace.exe .
python3 -B scripts/check_project_cli.py _build_delivery/default/bin/project.exe
git diff --check
```

Results: **12/12** headless tests (the original 11 plus native prepared-stage
integration), **20/20** routing tests; provider named two-profile six-stage fixture
integration passes, including strict report/inspection tampering, missing/empty
completed records, failed/interrupted/preflight availability and legacy stored
record equality. Report source/installed checks pass; observation **307 accepted,
2077 rejected, 173 queries, 22 incremental** and installed checkout-denied reads
pass; preparation **58**; native CLI **10** cold presentation differentials and
**24** contract negatives, routing and source/Python-denied reads pass.

The first engine fixture attempt exposed the consumer's real pinned collateral
revision/hash requirements; the fixture now supplies exact requested revisions
and the real pinned floorplan DEF, rather than relaxing native checks. A symlink
parent path regression exposed lexical-vs-canonical delivery differences; available
references now canonicalize only the validated existing file, preserving kernel
path traversal and identical terminal/reconnect references.

Real two-profile synthesis acceptance commands are in consumer
`docs/headless_flow.md`. No full physical runs were performed; those belong to the
next integration slice. No agents spawned or live Git staging/commit/push/stash/
reset used. Fixture Git mutations only; accumulated provider/consumer code,
Workbench and the user-owned namespace document were preserved.

## Full-regression compatibility correction (2026-10-15)

The orchestrator's forced full run exposed unconditional historical delivery
fields in legacy `Observation.inspect`. Inspection now adds `methodology`,
`execution_request` and `execution_file` only when the allocation request contains
the named `methodology_launch` descriptor. Legacy JSON retains exact writer/pure
snapshot/Python-reference parity; legacy human output has no added methodology
section. Clients treat absent methodology as implicit `not_recorded`.

Named pending/failed-preflight responses still retain their descriptor, checked
snapshot/reference and native request. Missing or tampered required named evidence
remains an error, with no snapshot fallback or downgrade to legacy behavior.

`observation describe` intentionally has additive capability metadata and three
named-only inspect schema entries. The test-only shared reference harness constructs
exact expectations for `named_execution_delivery` and those three entries on top
of the unchanged base description. Complete response equality remains enforced;
unknown differences are not stripped. The describe expectation/schema has been
deliberately updated; this is not a claim that the old describe output is unchanged.
No source Python oracle became production authority.

The source named-flow adapter now resolves its workspace path before delegation,
matching public dispatch for the existing symlink/`..` case. This is a test adapter
correction; installed named-flow checks exercise the public dispatcher directly.
The optional absent `/tmp/opencode/backend-v1-integration/results/observations`
fixture is explicitly skipped in historical-reader mode; existing example
observation assertions remain required.

Commands completed sequentially (including nested fixture Dune builds at `-j20`):

```sh
dune build -j20 @test/ocaml-observation-writer @test/inspector-presentation @test/default-journal @test/related-presentation @test/ocaml-observation @test/ocaml-stage-report @test/ocaml-report --force
dune build -j20 @install @all
python3 -B test/check_methodology_execution.py --source
python3 -B test/check_methodology_execution.py
python3 -B test/check_stage_report.py --installed
python3 -B test/check_observation.py --installed
python3 -B test/check_observation.py --installed --historical
python3 -B test/test_installed_prefix.py
dune runtest -j20 --force
```

Results:

- Focused aliases passed: writer **21** checks; inspector **11**, default journal
  **12**, related presentation **8** tests; reader **307 accepted / 2077 rejected /
  173 queries / 22 incremental**; stage-report contract passed; report **585**
  Python policy/human-byte differentials plus **15** original tests passed.
- Native named-flow source-helper and installed two-profile six-stage fixtures
  passed, including strict reader/report negatives and failed/interrupted/preflight
  evidence. The first source-helper attempt exposed the adapter mismatch above;
  its rerun passed. A combined source/installed invocation hit its 600-second outer
  timeout after source passed; the installed check passed separately.
- Installed stage-report and checkout-denied observation checks passed. Installed
  historical mode passed on **20** existing example observations (**253 queries**,
  same **307 / 2077 / 22** reducer/incremental counts), with the optional old `/tmp`
  observation fixture skipped explicitly.
- Installed-prefix suite: **57 tests, 327.800 seconds, OK**.
- Final `dune runtest -j20 --force`: **exit 0**, all executed aliases passed. Full
  output included catalog **149**, plan contract **108**, identity **62221 accepted /
  55 rejected**, runtime **2961 / 1253**, recipe **36 / 1819**, execution plan
  **164 / 4900**, runner **628**, reader **307 / 2077 / 173 / 22**, writer **21**,
  report **585**, collect **131**, and finalization **26** differential checks.
  The full run explicitly reported the already unavailable optional retained
  finalization at
  `/tmp/opencode/native-final-integration/finalizations/20261014T040711301534Z_913453bd`;
  this was not a new failure. No assertion was weakened to accept legacy inspect
  shape changes.

Scope: provider compatibility code, test expectations/adapters and these progress/
reference docs only. No EDA, consumer refresh, physical integration or agent spawn.
No live Git staging/commit/push/stash/reset; disposable fixture Git only. Existing
consumer/user work remains preserved for the physical-integration handoff.

## Final private installed + actual synthesis integration (2026-10-15)

**Both standalone public-client runs complete actual synthesis, client exit 0,
with available identity-matched reports.** The actual consumer design is
`controlled_fifo_specimen` / `tt_um_controlled_fifo`, not the fixture engine.
Default selection (both client selection flags omitted) chooses
`standard/balanced`; explicit `--flow standard --profile synth_delay` chooses
the delay profile. Acceptance and external postcheck remain **`not_evaluated`**.
This is synthesis-only evidence, not named-flow full-signoff acceptance.

Curated, small machine-readable evidence:
[`evidence/namedflow/20261015-real-synthesis.json`](../../evidence/namedflow/20261015-real-synthesis.json).
All exact plan, metadata, launchspec, native operation/prepared receipt, immutable
snapshot, execution record, report, config, backend-resolved, client-cache and
watch references/hashes are retained under:

```text
/tmp/opencode/namedflow-real-20261015/
  provider/                       new private reduced native installation
  source-capture/                 explicit provider source expectation
  source-expectation.json         inventory and capture checksum
  consumer-source-expectation.json
  commands.jsonl                  exact checked commands, environments and exits
  balanced-{receipt,plan,metadata,report,live}.json
  synth_delay-{receipt,plan,metadata,report,live}.json
  {balanced,synth_delay}-results/  fresh independent workspaces/results roots
  verified-summary.json           exact paths, hashes, observed settings/metrics
  lineage.json                    operation/prepared/launchspec/runtime links
  source-denied-readers/          allocation-only reconnect cache copies
```

### Installation and independent consumer validation

Captured current tracked/relevant untracked provider bytes with the consumer's
development capture API, checked its public source interface expectations, and
retained the capture. The explicit snapshot checksum is
`a12a763f842f283ab31649e8ded40786b304277f8e572d0f68e500e1fdc1686d`.
After sequential `dune build -j20 @install`, created a **new** dereferenced
hardlink generation at the prefix above from that current install tree. The
source expectation matched before/after build and after execution, before this
evidence/progress addition. The generation has no escaping staging symlinks;
the runtime contains exactly nine Python payload files, without retired installed
planner/reader/CLI modules. Earlier frozen-prefix labels were not reused.

Ran the consumer's actual `validate_install`: exact ocamlfind resolution to this
prefix, installed public interface compiler probe, independent external Dune link
probe, native executable/runtime inventory, help and exact CLI4 plus boolean
`namedflow1=true` validation. Public metadata was available before toolchain
readiness, independently of Workbench. Fresh consumer linkage uses only explicit
`OCAMLPATH=/tmp/opencode/namedflow-real-20261015/provider/lib` in the separate
`_build_namedflow_real` build directory. All four catalog/profile declaration
files are present in actual source inventories and copied/hash-verified in both
bundles. No normal activation or dependency pin was changed.

Successful sequential commands (every Dune invocation, including the installed
external link probe, at **`-j20`**):

```sh
# provider
dune build -j20 @install
# private prefix is a fresh dereferenced-hardlink installation; see receipt.json
# consumer, with the explicit OCAMLPATH above
dune build -j20 --build-dir _build_namedflow_real @all
HARDCAML_ASIC_TEST_PROVIDER=/tmp/opencode/namedflow-real-20261015/provider/bin/hardcaml-asic-flow \
  dune runtest -j20 --build-dir _build_namedflow_real . --force
HARDCAML_ASIC_TEST_PROVIDER=/tmp/opencode/namedflow-real-20261015/provider/bin/hardcaml-asic-flow \
HARDCAML_ASIC_ENGINE_FIXTURES=/tmp/opencode/namedflow-delivery-engine-v4 \
  dune build -j20 --build-dir _build_namedflow_real @scripts/headless-test --force
```

Consumer results: **20** installer, **20** routing, **12** headless and **11**
bootstrap tests pass, along with catalog/resolution, core/wrapper directed and
seeded simulation, CLI checks, bundle acceptance, and both **11,429-edge** generated
RTL replays with negative oracles. The fixture engine applies only to the headless
test alias. Actual runs below use the provisioned toolchain. The preceding provider
full forced suite and 57 installed tests already passed; no production correction
was needed, so those suites were not repeated.

### Current runtime and actual applied results

Installed public `provision --check --toolchain
/home/wayne/devel/jane/hardcaml_asic_example/_flow_tools` exits 0. Native selected
stage preflight reports ready, no issues or waivers, including the enriched actual
synthesis declaration contract. Both actual transports bind the same image:
`sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a`.
LibreLane is **3.1.0.dev3**, host Python **3.11.17**, container Python **3.13.13**.
Support tools revision is `da63c9927411e3aca350977d653d24bbf5bca972`; PDK revision
is `2bbec755dc67ca3db0261c3d6163e15735d66710`. Recorded Docker CPU, LibreLane core,
OpenROAD thread and OMP limits are each **20**, on execution and publication
validation transports. No runtime/declaration check was bypassed.

| Profile | Config **and actual checkpoint resolved.json** | Client/launcher/watch/reconnect | Mapped cells | Mapped cell area |
| --- | --- | --- | --- | --- |
| balanced (default) | `AREA 0`, boolean buffering `false` | all 0 | 673 | 13,041.6048 µm² |
| synth_delay (explicit) | `DELAY 1`, boolean buffering `false` | all 0 | 685 | 13,277.4012 µm² |

These are cumulative synthesis boundary observations, **not an improvement claim**
or timing/physical closure evidence. Both native executions are `completed`, exit
0, and reports say requested/physical completion `synthesis`. The client requires
that successful execution plus an available matching report; query exit 0 alone
does not establish execution success. The observation `final_results` summary's
coarser `physical_completion: not_recorded` is not substituted for the detailed
stage report's synthesis completion.

Balanced plan identity:
`41f81b7cce0c0592d686f80d77a19c63c687499a3ec9f38d4c363f4860be2c30`.
Delay plan identity:
`8692e13744bde2ff82eef9ea760f2d6c824d0ad1c4f184db8879e0d3ec4b37bf`.
Methodology, plan and bundle identities are distinct between profiles. The required
preview identity agrees across client launch argv, early allocation, native
request, operation/prepared receipt, immutable snapshot, stored execution and
normalized historical report. Launchspec/snapshot/preview content agrees exactly.
Generated RTL SHA-256 is identical:
`897a87e90021db5bc053d4b8ff548f4163e63576d859f21632aaf23976bbb327`;
SDC SHA-256 is identical:
`1852977c067a66e5b75f153c1bb6e13a9ccb1926082aad08ee489082fde3b5f1`.

### Early reader, exact reconnect and frozen history

Saved each early allocation cache while the client remained running with only one
launcher message, at **0.202 / 0.204 seconds**, well before the approximately
**26.81-second** terminal client completion. Independent public watchers read live
statuses at cursors **2, 4 and 6** with active writer and no outcome, including the
running synthesis occurrence. Each client retains **92 read-updates envelopes**,
**7 events**, final cursor **7**. Watchers exit 0 after actual terminal outcomes.

Discarded cached terminal stdout, inspection, execution/report references and
outcomes in **owned receipt copies**, retaining allocation/stream and preview
identity, with cursor reset to zero. Public-client reconnect exits 0 and obtains
the **same exact execution_file from public inspect**, then the identical report.
Repeated that allocation-only check inside a read-only, network-unshared `bwrap`
sandbox with current provider/consumer/catalog/Workbench sources hidden and
PATH/PYTHONPATH denied, using a byte-identical copy of the public standalone client.
Only its private reader-cache directory is writable. Execve traces show no project
executable, list or plan call. No glob, guessed execution filename or private helper
client was used.

Public report/inspect JSON is also identical with sources hidden. Read-only
changed-copy catalog/profile overlays (different labels and strategy declarations)
leave both historical reports identical; live consumer declarations were untouched.
This overlay is a source-read oracle, not a new compilation/execution of the changed
catalog. Existing mutation/deletion contract scenarios remain covered by the prior
provider suite and current consumer source/catalog stale-preview tests.

**Historical limitation:** these are path-bound checkpoints. An initial sandbox
which also hid all external toolchain collateral correctly failed exit 2 on a
declared PDK PDF closure path. Retaining `_flow_tools` read-only, while hiding all
current source/declaration files, makes historical reads pass without tools or
runtime probes. This is not a claim of independently relocated or toolchain-free
checkpoint closure. The failed attempt and sandbox argv are recorded in the raw
command log/verified summary.

Schema lineage stays unchanged: CLI4/namedflow1; catalog/discovery/plan/snapshot and
methodology execution/historical references v1; physical recipe v3; observation
allocation v1 and reader/events v2; report v1; client cache v1. Neither plan hashes,
local source-capture checksums nor receipt file digests are **P6 source stamps**.
Installed metadata explicitly remains unstamped with unknown revision/inventory and
unverified linked-artifact match. The later evidence/docs addition is outside the
captured build input; it does not retroactively change that capture.

Before/after protected hashes match for the dependency pin, normal selection
receipt and user-owned namespace document. The selection remains
`generations/3cd135a1d9e14525a53789eb646a69ae`. Existing user physical runs,
checkpoints and accepted operations were only left in their original locations;
all new EDA/results/cache writes use the new `/tmp/opencode/namedflow-real...` tree.
No Workbench/user-doc edits, production fixes, subagents or live Git
add/commit/push/stash/reset occurred; test Git writes were disposable fixtures only.

### Ready current consumer commands

From `hardcaml_asic_example`, no activation is needed for these explicit binaries:

```sh
PROJECT="$PWD/_build_namedflow_real/default/bin/project.exe"
PROVIDER=/tmp/opencode/namedflow-real-20261015/provider/bin/hardcaml-asic-flow
TOOLS="$PWD/_flow_tools"
"$PROJECT" flow list --json
"$PROJECT" flow describe --flow standard --json
# Read the retained actual run (reader only):
python3 -B scripts/headless_flow.py --reconnect \
  --receipt /tmp/opencode/namedflow-real-20261015/balanced-allocation-only-receipt.json
# For a NEW actual run, choose fresh results and receipt names:
python3 -B scripts/headless_flow.py \
  --project "$PROJECT" --provider "$PROVIDER" --source-root "$PWD" \
  --results-root /tmp/opencode/namedflow-real-user-delay-results \
  --toolchain "$TOOLS" --python "$TOOLS/.venv/bin/python" \
  --support-tools "$TOOLS/tt" --pdk-root "$TOOLS/pdk" \
  --flow standard --profile synth_delay --endpoint synthesis \
  --receipt /tmp/opencode/namedflow-real-user-delay.json --timeout 1800
```

Omit both selection flags for the declared balanced default. Reconnect is a cache
writer: use a distinct owned cache copy for an additional concurrent reader.

## Final bounded provider + consumer race corrections (2026-10-15)

**Finding 1:** `Observation.inspect` uses the retained reference-bearing preflight
report as metadata readiness marker. A sidecar visible before that commit is still
`pending`, with original request and null execution reference. The reader rechecks
writer, prefix and report after an initial absent-reference read, then performs the
existing strict reference/snapshot/checkpoint validation. Preparation failure in
the publication interval retains the published reference and complete native
request. Incomplete pending metadata cannot earn completion; recorded interruption
and writer-lost/unknown outcomes remain truthful.

`test/named_observation_race.ml` forks six owned writer processes, synchronizing
with pipes at the narrow injected snapshot-publication callback. Five repeated
inspections per pause remain pending. Cases cover normal commit, report-read before
commit with validation after commit, missing snapshot at that exact interleaving,
post-commit corruption, cancellation before normal report publication, lost writer,
and an interrupted terminal journal with incomplete metadata. No timing sleeps or
guessed publication delays are used. An installed-mode driver independently links
this fixture against the installed public API. The only reader test hook is the
explicit `Observation.For_testing` callback; no production environment hooks.
Post-commit removal of the report or its required reference also fails; only an
actual initial pending diagnostic can terminate a reference-free report chain.

**Finding 2:** consumer `scripts/headless_flow.py` now owns the child across every
post-spawn setup step, including Thread construction/start and deadline setup.
Cleanup ignores additional SIGINT/SIGTERM while terminating/reaping only its own
Popen child, tolerates absent/unstarted/already-started readers, bounds waits/joins,
and avoids closing a pipe held by a live reader. The cache records failed versus
interrupted client setup and actual launcher exit; no allocation means no reconnect
claim. Runtime setup errors exit 2; SIGINT and SIGTERM retain documented exit 130.
Reader-only interruption remains independent of producer cleanup.

The new consumer test injects KeyboardInterrupt and RuntimeError at construction,
start, and start-after-thread-launch, plus SIGINT/SIGTERM at start. Each of eight
cases first launches a real disposable child with an acknowledged pipe handshake
and full stdout pipe, then asserts bounded cleanup, reaping, nonzero launcher exit,
truthful client status and unavailable reconnect. Test cleanup uses only owned
Popen objects, never arbitrary cached PIDs.

### Exact checks

All Dune commands, including disposable installed-fixture builds, ran sequentially
at **`-j20`**. Current native installation was built with `@install @all` and copied
as a fresh dereferenced-hardlink thin generation at
`/tmp/opencode/namedflow-race-provider-v2`; earlier frozen prefixes (including the
initial correction's v1) were retained. The v2 run additionally verifies stripped
committed references and deleted reports.

```sh
dune build -j20 @install @all @test/ocaml-observation @test/ocaml-observation-writer @test/ocaml-stage-preparation
python3 -B test/check_methodology_execution.py --source
FLOW_TEST_INSTALLED_PREFIX=/tmp/opencode/namedflow-race-provider-v2 python3 -B test/check_methodology_execution.py
FLOW_TEST_INSTALLED_PREFIX=/tmp/opencode/namedflow-race-provider-v2 python3 -B test/check_observation.py --installed
FLOW_TEST_INSTALLED_PREFIX=/tmp/opencode/namedflow-race-provider-v2 python3 -B test/check_stage_preparation.py --installed
python3 -B test/check_native_cli.py
dune build -j20 @test/default-journal @test/inspector-presentation @test/ocaml-observation-writer @test/ocaml-observation @test/ocaml-stage-preparation --force
# consumer, OCAMLPATH bound to the new prefix's lib; explicit native provider
# and HARDCAML_ASIC_ENGINE_FIXTURES=/tmp/opencode/namedflow-delivery-engine-v4:
dune build -j20 --build-dir _build_namedflow_race bin/project.exe acceptance/export_trace.exe @scripts/headless-test
python3 -B scripts/test_project_routing.py _build_namedflow_race/default/bin/project.exe _build_namedflow_race/default/acceptance/export_trace.exe .
```

Results: six synchronized race cases pass in source and independently linked
installed modes; full named two-profile/six-stage fixture suites pass in source and
installed modes, including strict corruption/missing-evidence and failed/interrupted
request checks. Observation: **307 accepted / 2077 rejected / 173 queries / 22
incremental**, including installed checkout-denied reads; writer **21**; preparation
**58** source and independently linked installed/source-denied checks. Default
journal **12**, inspector **11**, consumer headless **13** (eight new fault scenarios
inside one test), routing **20** pass. Native CLI metadata, ten cold presentation
differentials, 24 negatives, routing and source/Python-denied reads pass. That test
had a stale local describe override which replaced the already-correct shared
named-only oracle; the override was removed without weakening exact equality.
The native CLI routing test uses its own disposable prefix because it deliberately
replaces helpers; pointing it at a shared prefix failed its canonical-path metadata
expectation before any replacements, and was corrected by the independent run.
Initial fixture failures (read-only snapshot mutation, shadowed argparse variable)
were corrected; final focused reruns pass.
The final headless fault fixture acknowledges readiness only after its disposable
child fills stdout using nonblocking writes; the v2 headless/routing and complete
source/installed named-flow suites were rerun successfully after hardening the
missing-report/reference cases. `git diff --check` passes in both checkouts.

**Evidence boundary:** actual physical two-profile synthesis in the preceding
section belongs to the retained **pre-fix byte snapshot**. It was preserved, not
rerun or upgraded to corrected-code physical evidence. Current correction evidence
is deterministic process/native fixture evidence; see `evidence/namedflow/README.md`.
No dependency pin/normal activation, Workbench docs or user namespace work changed.
No agents or live Git stage/commit/push/stash/reset; fixture Git only.

## Final bounded verification and buildroot hygiene (2026-10-15)

After the publication-race and headless startup-cleanup corrections, the following
completed sequentially; all Dune invocations, including nested fixture builds,
use `-j20`:

```sh
# provider
dune runtest -j20 --force
dune build -j20 @install @all
python3 -B test/test_installed_prefix.py
# consumer: export these explicit private test bindings for both commands
export OCAMLPATH=/tmp/opencode/namedflow-race-provider-v2/lib
export HARDCAML_ASIC_TEST_PROVIDER=/tmp/opencode/namedflow-race-provider-v2/bin/hardcaml-asic-flow
export HARDCAML_ASIC_ENGINE_FIXTURES=/tmp/opencode/namedflow-delivery-engine-v4
dune runtest -j20 --build-dir _build_namedflow_race
dune build -j20 --build-dir _build_namedflow_race bin/project.exe acceptance/export_trace.exe @scripts/headless-test --force
```

Provider full suite and `@install @all`: exit **0**. Installed-prefix suite:
**57 tests, 327.672 seconds, OK**. Consumer full suite: exit **0**, including
**20/20 routing**, catalog, CLI, dependency/bootstrap fixtures and RTL checks.
Forced headless suite: **13/13**, including native fixture integration and eight
startup-cleanup fault scenarios. No production or test-wiring fixes were needed.

Reused the retained private v2 prefix only after comparing **all 734 files** with
the latest install tree minus the explicitly retired Python modules. The prefix
remained byte-identical after consumer checks. Audit script/state are retained at
`/tmp/opencode/namedflow-final-audit.{py,json}`. Protected namespace, Workbench docs,
consumer pin/activation/history and curated physical evidence bytes, plus checkout
status, remained unchanged across consumer verification. Both checkout
`git diff --check` commands pass. Docker reports no running containers.

Consumer `.gitignore` adds only anchored `/_build_namedflow_real/` and
`/_build_namedflow_race/` entries; existing headless/delivery entries are preserved.
Both retained `bin/project.exe` artifacts remain present. `git check-ignore -v`
confirms the exact entries and untracked source inventory excludes both roots.

The forced provider suite explicitly reports the unavailable optional old retained
finalization at
`/tmp/opencode/native-final-integration/finalizations/20261014T040711301534Z_913453bd`;
this is not evidence that absent old physical data was checked. Earlier independent
source-hidden tests remain the evidence for that boundary. No new physical EDA or
regular consumer refresh occurred; pre-fix physical JSON remains unchanged.
