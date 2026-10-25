# A → B: resource preparation library handoff

Concrete API contract (library implemented; focused library tests pass).

```ocaml
Resource_preparation.Phase.t =
  | Source_before | Construction | Finalization | Resolution
  | Circuit | Source_after | Snapshot
Phase.to_string : t -> string
Phase.of_string : string -> t Or_error.t

Resource_preparation.Failure.diagnostic =
  { code : string; message : string; detail : Sexp.t }
Resource_preparation.Failure.t =
  { phase : Phase.t; diagnostics : diagnostic list }
Failure.create : phase:Phase.t -> code:string -> message:string -> Error.t -> t
Failure.to_json : t -> Yojson.Safe.t
Failure.of_json : Yojson.Safe.t -> t Or_error.t

Resource_preparation.t (* abstract successful preparation *)
Resource_preparation.identity : t -> string
Resource_preparation.source_identity : t -> string
Resource_preparation.configuration_identity : t -> string
Resource_preparation.circuit_identity : t -> string
Resource_preparation.resources : t -> Elaboration.Resource_snapshot.t
Resource_preparation.to_json : t -> Yojson.Safe.t
Resource_preparation.of_json : Yojson.Safe.t -> t Or_error.t
Resource_preparation.to_string : t -> string
Resource_preparation.of_string : string -> t Or_error.t

Project.prepare_resources :
  ?inputs:Platform.Target.Inputs.t ->
  ?methodology:Hardcaml_asic_flow_domain.Catalog.resolved ->
  ?catalog_inputs:string list ->
  ?on_phase:(Resource_preparation.Phase.t -> unit) ->
  Project.t -> source_root:string ->
  (Resource_preparation.t, Resource_preparation.Failure.t) Result.t
```

`Resource_preparation.t` is the success type (also named `Success.t`); failure
is returned separately. The callback is invoked immediately before actual work
for each phase. Callback exceptions propagate to B (so interruption/storage
exceptions are not relabeled as project failures). Consumer construction is
outside this function and must be caught by B's allocated-operation closure.

## JSON wire and verification

Success is an exact-field object:

```
schema_version: 1
kind: "hardcaml_asic.resource_preparation"
identity: <sha256>
source_identity: <sha256>
configuration_identity: <sha256>
circuit_identity: <sha256>
source: <Source_snapshot JSON>
configuration: <versioned tagged-sexp declaration/effective-input payload>
circuit: {format: "verilog", rtl: <actual deterministic RTL bytes>}
resources: <Resource_snapshot JSON>
coverage: {declared_sources: true, compiled_source_proven: false,
           p6_source_stamp: false, collateral_files_verified: false,
           measured_evidence: false}
```

All hashes use the library's domain-separated deterministic JSON codec. B must
call `of_string` on retained bytes (strict duplicate-key/schema/identity checks)
and use `identity` on the returned value; do not hash JSON through execution's
different codec. `to_string` supplies deterministic pretty JSON plus newline.
B separately hashes exact file bytes for its lifecycle record.

Failure JSON has exact fields `schema_version`, `phase`, `diagnostics`; each
diagnostic has `code`, `message`, `detail` (tagged sexp). Phase wire spellings:
`source_before`, `construction`, `finalization`, `resolution`, `circuit`,
`source_after`, `snapshot`. No inventory is attached to failures.

Snapshot wire has version/project/top/mode/scope and ordered resource entries.
All contracts and diagnostic detail use `{atom: string}` or `{list: [...]}`;
order and atom/list distinction are preserved. Structured selection/policy,
source roles, actual-instance availability, collateral and physical intent
remain distinct. Successful empty resource lists are valid.

This artifact is historical declaration/elaboration evidence, not readiness,
bundle identity, synthesis retention, PDK presence or measured physical proof.
Source observations occur before/after; changes reject success. Neither source
hashes nor RTL prove compiled constructor/source consistency. No output path,
attempt ID or timestamp contributes to content identity.

Actual success callback order is `Source_before`, `Construction`, `Finalization`,
`Resolution`, `Circuit`, `Snapshot`, `Source_after`. The final observation follows
snapshot encoding too, so mutation in any earlier callback is rejected. Pure
snapshot encoding and actual RTL encoding operate entirely in memory. Callback
exceptions propagate; B must handle its own interruption/publication exceptions.

Codec details: object keys sort lexicographically, arrays retain order, scalar
encoding uses Yojson.Safe. Hash input is
`"hardcaml_asic/" ^ domain ^ "/v1\000" ^ compact_canonical_json`, where `\000`
denotes one NUL byte. Domains are `source`, `configuration`, `circuit`, and
`preparation`. The outer preparation hash excludes only its own `identity` field;
the source hash likewise excludes only its own identity. Configuration and actual
RTL are retained inside the success JSON and individually verified. Neither
Bundle's order-sensitive codec nor execution's Identity_json defines these hashes.

`configuration` has exact fields `schema_version`, `operation`, `declaration`,
`inputs`, `methodology`, `resolved_settings`. Declaration and effective target
inputs are tagged sexp trees, not pretty text; methodology is Flow.Spec's checked
snapshot or null; resolved settings have `key`, `value`, tagged `owner`.

Each resource entry has exact fields `id` (`path`, `name`, `display`), `request`
(`kind`, tagged `contract`), `requirement`, `policy`, `selection`
(`implementation`, `reason`), `elaborated_as`, `sources`, `actual_instances`,
`collateral`, `physical_intent`. Inspectors should present these fields, without
trying to deserialize them into a new selection or Resolved.t.

B owns durable I/O and inspection. A owns no execution/CLI files. Public aliases
are `Hardcaml_asic.Resource_preparation`, `Resource_snapshot`, `Source_snapshot`.

### A library verification (2026-10-25)

Focused suite: `opam exec -- dune runtest -j6 test/resource_preparation` under
`flock /tmp/opencode/asic-preparation-build.lock-j6`. Existing library inline
tests also pass (runner with explicit `-source-tree-root .../hardcaml_asic/test`).
No Bundle code changes were needed. Source observations are independently
implemented and existing bundle bytes/identity semantics are untouched.

The focused suite covers callback order and exception propagation; exactly one
Implementation construction; construction/finalization/resolution/source failure
phases; explicit flops, fallback, exact
macro, unsupported Exact, resource-free success; actual macro RTL linkage and
intent; generic ordered tagged contracts; simulation macro selection versus
behavioral role; deterministic roundtrip; effective default inputs; methodology
and catalog coverage; independent config/circuit/source identity changes; mutation
including the Snapshot callback; strict schema, identity and JSON corruption;
invalid source paths and escaping symlinks. Standard JSON validation rejects
comments, nonfinite values, unpaired Unicode surrogates, duplicate object keys,
trailing data and excessive nesting before any historical success is accepted.

## B → C: durable consumer invocation and generic inspection

Concrete B API (implementation in progress; execution modules only):

```ocaml
module E = Hardcaml_asic_execution
module P = Hardcaml_asic.Resource_preparation

let outcome = E.Preparation_service.run_cli
  ~store:operation_store
  ~request:(* E.Identity_json.t object: project-owned selection metadata *)
  ~json
  ~prepare:(fun ~on_phase ->
    (* This closure runs AFTER operation.json and allocation delivery. *)
    let project = (* construct chosen Project.t, raising on construction error *) in
    Hardcaml_asic.Project.prepare_resources ~on_phase project ~source_root)
  ()
in
Stdlib.exit (Option.value outcome.record.exit_code ~default:1)
```

`Preparation_service.run` has the same arguments except `json`, and optional
`allocated:(directory:string -> attempt_id:string -> unit)` for a caller-owned
presentation. It returns `{directory; record}`. `run_cli` owns flushed allocation
and terminal JSONL (or human summaries); the consumer should not print another
success object. Exceptions from project construction are retained as failures.
Terminal storage/delivery exceptions propagate and must yield command failure.
No external command specification, Project deserialization or driver protocol.

Stored files: unique `<store>/<allocated-attempt>/operation.json` plus, on
successful snapshot publication, `resources.json`. Only a completed operation
with verified snapshot reference commits success; an orphan snapshot is not a
successful preparation. Retrying always reserves another attempt. Atomic local
visibility only, no fsync guarantee. SIGINT/SIGTERM are scoped to the runner,
restored afterward; cancellation is cooperative at phase boundaries. SIGKILL can
leave `running`. There is no persisted-PID cancellation interface.

Public read-only inspection:

```sh
hardcaml-asic-flow preparation-inspect ATTEMPT --json
hardcaml-asic-flow preparation-inspect ATTEMPT --current-identity SHA256 --json
```

Inspection JSON contract `hardcaml-asic.preparation-inspection`, schema 1:
`attempt`, `operation` (full durable record), `preparation` (A's complete decoded
success payload, or null), `comparison` with `state`, `scope`, `current_identity`,
`recorded_identity`. Comparison scope is `preparation_identity`; states are
`not_requested`, `matches`, `differs`, `unavailable`. Failed/interrupted/running
attempts never supply a successful empty resource list. A valid failed attempt
is reader exit 0; corruption/invalid query is exit 2. Plain inspection never
observes current sources, tools or PDK. `--current-identity` validates lowercase
64-hex and compares only the explicitly supplied preparation identity.

Launch JSONL contract `hardcaml-asic.resource-preparation-operation`, schema 1:
first `{event:"allocated",attempt,attempt_id,...}`, then
`{event:"terminal",attempt,record,...}`. Both include contract/schema and are
flushed. No terminal success delivery if terminal storage publication fails.
Operation descriptor is versioned `hardcaml-asic.workflow-operation`, category
`preparation`, kind `elaborate_resolve_resources`, independent of physical stages.
Public capability: `preparation1: true`; generic JSON command:
`preparation-inspect`. B's focused test alias is `@test/preparation`.

### B implementation verification (2026-10-25)

The consumer API and inspector above are implemented. Passed, serialized with
`flock /tmp/opencode/asic-preparation-build.lock`, explicit `-j6`:

```sh
opam exec --switch=5.2.0+ox -- dune build -j6 \
  @test/preparation @test/flow-cli @test/flow-packaging
```

Preparation acceptance covers real typed success/resource-free success, constructor
failure, unsupported exact selection, invalid source inventory, invalid preparation
payload, allocation/terminal JSONL, retry isolation, explicit comparison, historical
source independence, strict record/snapshot corruption, snapshot-write failure,
post-write mutation, terminal-write failure, publication cancellation, SIGINT,
SIGTERM, SIGKILL and restoration of an existing consumer signal handler. Existing
CLI tests: 43 passed; packaging tests: 17 passed. No EDA/provisioning/Git mutations.
The install artifact build `dune build -j6 @install` also passed under the same lock.
See [consumer guide](../guides/resource-preparation.md) for runnable integration.

### B independent-review corrections

The terminal cancellation cutoff is now explicit: block SIGINT/SIGTERM, perform
the final check of already-observed cancellation, then noncancellably save and
verify the exact terminal record bytes and strict decode. Restore the previous
handlers and original signal mask before pending commit signals are delivered;
do not rewrite terminal records. A default handler can terminate the process
after terminal persistence and before terminal JSONL delivery. The prior mask
and POSIX coalescing semantics apply. This behavior also applies on commit error.

Malformed public Failure values (including empty diagnostics) become durable
`preparation_exception` failures. Evidence leaf symlinks/nonregular files are
rejected using lstat/nonblocking-open/fstat plus final checks; reads are bounded
at 4 MiB for operation records and 64 MiB for snapshots.

Workflow **descriptor schema 2** corrects the actual phase order to
`circuit -> snapshot -> source_after`. The reader explicitly accepts the exact
original descriptor schema 1, preserving its stored advertised ordering and C's
captured historical records without modification. Arbitrary variant descriptors
and unknown versions fail. Outer operation/inspection schemas remain 1; A's
snapshot payload and identities are unchanged.

Review regressions pass in `@test/preparation`: empty-diagnostics callback
failure becomes durable failure; silent terminal `{}` replacement raises;
external SIGINT and SIGTERM before cutoff interrupt, during commit reach custom
previous handlers exactly once, and default handlers terminate only after a
valid terminal record. Both handlers and the unblocked original mask are checked
after return. Reader regressions cover operation/snapshot FIFOs, symlinks,
directories and oversized files, plus deterministic FIFO/same-inode-symlink
replacement after lstat. The actual saved phase callbacks agree with descriptor
schema 2; exact descriptor v1 reads preserve bytes, while unknown/arbitrary
descriptor variants fail.

Serialized `-j6` checks passed after these corrections:
`@test/preparation`, `@test/flow-cli`, `@test/flow-packaging`, and `@install`.
The supplied `/tmp/opencode/preparation_inspection_review.py` also confirms both
evidence FIFO cases and both symlink cases reject immediately with exit 2.
