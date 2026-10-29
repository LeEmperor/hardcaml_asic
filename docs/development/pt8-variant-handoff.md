# PT.8 A — hardware variant contract and integration handoff

2026-10-29. Concrete implementation contract published before code. Implements A
of [the plan](pt8-variant-plan.md); execution validators/comparison/CLI belong to B.

## Public OCaml API

`Hardcaml_asic.Hardware_variant`:

```ocaml
module Value : sig
  type t = Int of int | Bool of bool | Enum of string
end
module Parameter : sig
  type kind = Integer of { minimum : int; maximum : int }
            | Boolean | Enumeration of string list
  type t
  val create : key:string -> kind:kind -> t Or_error.t
  val key : t -> string
  val kind : t -> kind
end
module Schema : sig
  type t
  val create : design_id:string -> schema_id:string
    -> parameters:Parameter.t list -> t Or_error.t
  val design_id : t -> string
  val schema_id : t -> string
  val parameters : t -> Parameter.t list
end
type t
val create : schema:Schema.t -> assignments:(string * Value.t) list -> t Or_error.t
val schema : t -> Schema.t
val assignments : t -> (string * Value.t) list
val get_int : t -> key:string -> int Or_error.t
val get_bool : t -> key:string -> bool Or_error.t
val get_enum : t -> key:string -> string Or_error.t
val identity : t -> string
val to_yojson : t -> Yojson.Safe.t
val of_yojson : Yojson.Safe.t -> t Or_error.t
val to_string : t -> string
val of_string : string -> t Or_error.t
val sexp_of_t : t -> Sexp.t
```

`Project.of_variant ~variant ~create` calls
`create : Hardware_variant.t -> Project.t Or_error.t` exactly once, passes the
same immutable value and attaches it internally only after success. Exceptions
become errors. A returned project already carrying ANY variant (equal or different)
is rejected. Failure leaves all existing values unchanged; later calls are independent.
This is factory construction, not hardware elaboration. `Project.hardware_variant`,
`Elaborated_project.hardware_variant` and `Methodology_plan.hardware_variant` return
`Hardware_variant.t option`. Normal `Project.create` remains unparameterized.

Consumer adapter pattern: construct a checked schema/complete assignment, then call
`Project.of_variant ~variant ~create:(fun checked -> ... get_int checked ~key:"depth"
... ordinary Project.create with the resulting depth ...)`. Policy and flow remain
ordinary separately supplied values. Cross-parameter capability checks belong in
the factory. No new defaults, catalog, constraints or policy-selection logic.

For C, the complete bounded memory declaration can be constructed as follows:

```ocaml
let open Core.Or_error.Let_syntax in
let module H = Hardcaml_asic.Hardware_variant in
let%bind depth_parameter = H.Parameter.create ~key:"depth"
  ~kind:(Integer { minimum = 128; maximum = 256 }) in
let%bind width_parameter = H.Parameter.create ~key:"width"
  ~kind:(Integer { minimum = 16; maximum = 16 }) in
let%bind latency_parameter = H.Parameter.create ~key:"read_latency"
  ~kind:(Integer { minimum = 1; maximum = 1 }) in
let%bind schema = H.Schema.create ~design_id:"program_memory"
  ~schema_id:"program_memory.v1"
  ~parameters:[ depth_parameter; width_parameter; latency_parameter ] in
let%bind variant = H.create ~schema
  ~assignments:[ "depth", Int depth; "width", Int 16; "read_latency", Int 1 ] in
Hardcaml_asic.Project.of_variant ~variant ~create:(fun checked ->
  let%bind depth = H.get_int checked ~key:"depth" in
  if depth <> 128 && depth <> 256 then Core.Or_error.error_string "unsupported depth"
  else Program_memory.project ~depth ~operation requirement)
```

`depth`, `operation` and `requirement` in this adapter are explicit caller inputs.
The existing memory implementation consumes fixed width16/latency1; these singleton
domains record those actual supported facts. Its policy/flow arguments remain
outside the hardware declaration. This is an adapter illustration, not a new edit
to the example or evidence that its conformance oracle has passed.

## Wire (exact schema 1)

Optional manifest member **`hardware_variant`** contains this entire object:

```json
{
  "contract": "hardcaml-asic.hardware-variant",
  "schema_version": 1,
  "design_id": "program_memory",
  "schema_id": "program_memory.v1",
  "parameters": [
    {"key":"depth","type":"integer","minimum":128,"maximum":256},
    {"key":"enabled","type":"boolean"},
    {"key":"encoding","type":"enum","values":["binary","one_hot"]}
  ],
  "assignments": {"depth":256,"enabled":true,"encoding":"binary"},
  "identity": "<lowercase SHA256>"
}
```

Integer domains are inclusive ranges, not arbitrary discrete sets. Consumers must
reject unsupported combinations/holes (e.g. depths other than 128/256). Integer
bounds and values are limited to [-1000000000,1000000000]. There are 1..64
parameters and 1..64 distinct enum members per enum. IDs, keys and enum members
are 1..128 ASCII bytes matching `[a-z][a-z0-9_.-]*`. Total input string limit is
128 KiB. Only integer JSON tokens, boolean tokens and closed enum strings are
accepted; floats/numeric booleans/null/objects/arrays are not assignment scalars.

Parameter order, assignment order and enum-member order normalize by bytewise
key/value ordering. Duplicate parameters, enum members or assignments reject,
even if equal. Assignments must contain exactly all schema keys. Strict readers
reject unknown/missing/duplicate object fields at every depth, unsupported versions,
invalid bounds/types/values, bad identity, trailing JSON and oversized input.

Identity is `Flow.Plan_json.identity ~contract:"hardcaml-asic.hardware-variant"`
over the normalized object above **without** `identity`, including contract and
schema_version. Use the provider codec, not a foreign encoder. A decoder accepts
reordered objects/lists, normalizes, then checks that digest. There is no label or
semantic-use attestation field.

## Exact gates required from B

1. Add `hardware_variant` to optional manifest whitelists in execution readers,
   publication/archive/inspection paths wherever full bundle manifests are checked.
   Absence alone is historical absence. **Present null is invalid.**
2. If present, call `Hardware_variant.of_yojson` (or the identical main-library
   bundle verifier that invokes it), including after a coherent outer rehash.
   Never accept an unchecked JSON sidecar, silently discard malformed metadata,
   infer parameters from a project/profile label, or convert corruption to absence.
3. Preserve the exact frozen manifest bytes and existing bundle identity algorithm.
   The new object is inside the manifest payload, hence inside bundle and plan
   identity; no separately writable second hardware copy is authoritative.
4. Existing manifest/file inventory, RTL/config/SDC/source digests, attempt/plan/
   publication association and effective backend-setting gates remain required.
   Hardware identity is not a replacement for any of them.
5. Old absent manifests/plans retain exact bytes/digests and decode as `None`.
   Comparisons expose unavailable hardware metadata rather than assumed defaults.
6. Tests: valid new metadata; absent old metadata; null/unknown/duplicate/missing/
   wrong-type/out-of-bound/incomplete assignments; mismatched inner digest even
   after outer rehash; cross-bundle/attempt substitution; saved historical reads
   independent of current schema/catalog. Rehashing a *valid different declaration*
   is a different bundle, not proof it matches that bundle's hardware behavior.

A owns `lib/` manifest/plan gates and isolated `test/hardware_variant/`.
B owns **all execution sources**, bin/root declarations and comparison tests.
C uses the public API for actual memory128/256 behavior and an ignored-depth
negative. This document is the source handoff; no execution source is edited by A.

## Identity propagation and limits

Project inspection includes the declaration only when present; absent inspection
bytes stay unchanged. Resource preparation inherits it through Project.describe.
Elaboration carries the same immutable value; bundle render checks optional
simulation/implementation declaration agreement and emits the optional member.
Methodology plans use the manifest declaration and existing inseparable rendered
pair; no second declaration argument is introduced.

Calling a getter, a valid digest, different bundle identities, or successful factory
binding does **not** prove hardware uses a parameter. C's independent resource
contract/capacity/latency oracle must catch a factory that ignores depth. Declared
source observations remain neither compiled-source consistency nor P6 stamping.
No EDA, readiness, physical acceptance, workload equivalence or consumer selection
is established by this API.

## Validation status

Implemented the public API above, curated root export, factory binding and
Project/Elaborated_project/Bundle/Methodology_plan propagation. Absent declarations
are omitted rather than encoded as null. Factory exceptions become errors; an
already-bound returned project rejects equal as well as conflicting attachment.

The new grammar-only `Flow.Plan_json.parse` uses standard JSON admission before
Yojson, including comments/extensions/trailing-data/UTF-8/surrogate/depth rejection;
existing canonical/hash functions and existing preparation codec are unchanged.
Hardware JSON has an additional maximum nesting depth of 8. Its own codec validates
the descriptor/assignment/digest semantics. This helper lives below Elaboration to
keep the hardware-declaration dependency graph acyclic.

Verified with switch `5.2.0+ox`, explicit `-j6`, under the shared
`/tmp/opencode/asic-pt7-build.lock`:

```sh
dune build -j6 @test/hardware_variant/runtest @test/runtest-hardcaml_asic_test @install
```

- Schema suite: **85 checks**, including type/bound/completeness negatives,
  canonical ordering/identity coverage, nested duplicates/unknown fields, strict
  syntax and total declaration size admission.
- Integration suite: **41 checks**, including exact factory assignment, success/
  failure/exception/repeated/conflicting lifecycle, describe/preparation propagation,
  implementation/simulation association, one-render/determinism, frozen plan
  roundtrip, stale identity and independent profile changes.
- Absent legacy manifest **exact object order/bytes and identity** equal the new
  metadata-bearing manifest after removing only that field and recomputing the
  unchanged historical outer hash. All nonmanifest emitted bytes match the plain
  project; historical plan absence decodes as None. Existing inline lifecycle
  expectations and project/selection/resource/target tests pass unchanged.
- Inner declaration corruption and present null reject even with coherent outer
  bundle/plan hashes. A valid substituted declaration can still decode: the codec
  honestly does not assert that a producer used the declared parameter.
- `@install` builds successfully; C's independent installed adapter and actual
  memory conformance, B's execution readers/comparison/CLI and cross-review remain
  their own acceptance work, not results claimed by A.

The integration suite reads the actual checkout's declared `dune-project` and Git
facts without changing them. It performs no publication, fixture Git mutation,
EDA or PDK/toolchain probe. Existing dirty physical changes and frozen runs are
preserved. No execution source, old provider/config, Protemu or Workbench was edited.
