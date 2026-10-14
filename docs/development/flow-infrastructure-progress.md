# Flow infrastructure: bounded slices

Implemented in sequential bounded dispatches, 2026-10-13 through 2026-10-14.
This is the detailed implementation/evidence record for the
[infrastructure refactor](../flow-infrastructure-refactor.md); the
[phase plan](../phase_plan.md#ocaml-first-flow-infrastructure) remains the queue.

## Current milestone at a glance

**Delivered:** public CLI4 `stages`, checkpoint inspection, observation queries,
and foreground watch now use OCaml implementations. The explicit-stage execution
path owns preparation, runtime binding, process/container supervision, protocol
validation, checkpoint publication, run records, and schema-2 journaling in OCaml.
The focused Python bridge invokes LibreLane's native configuration/state/flow APIs.

**Where to look:**

- `lib/flow/stages/`: six visible stage groups, including placement operations.
- `lib/flow/analysis/`: shared timing analysis contracts.
- `lib/flow/backends/librelane/`: the maintained 80-occurrence backend mapping.
- `lib/execution/`: the installed `hardcaml_asic.execution` library and typed APIs.
- `bin/`: installed native command implementations, retaining experimental helper
  names behind the public routing layer.
- `flow/hardcaml_asic_flow/ocaml_backend.py`: explicit transitional public routing.

**Verified:** forced full provider regression, independent installed-prefix and
consumer tests, and a fresh six-stage physical execution followed by separate
external acceptance. The current mapping, default journal/watch, transport records,
20-CPU bound, and actual checkpoint handoffs were exercised. See
[curated final evidence](../../evidence/librelane-observation/native-final-integration.json).

**Remaining:** top-level CLI parsing, coarse command services, results/finalization,
and archive migration; broader directory reorganization; finer per-operation
backend invocation. Stage decomposition currently describes and validates trusted
Classic sequences, not new fine-grained checkpoint boundaries. Modularized
flow-file/profile support remains deferred. Later sections retain the chronological
slice results and superseded intermediate limitations.

## Maintained contract and ownership

`Flow.Stage.capability` in `lib/flow_stage.ml` is the maintained public facade.
Its domain/backend declaration source now lives under `lib/flow/` (see the
bounded stage decomposition section below); endpoints/successors are derived
from the actual maintained composition. `Flow.Stage.all` defines stage order. The installed public interface is
`lib/flow_stage.mli`, exposed through `Hardcaml_asic.Flow.Stage`; consumers can
inspect these static declarations without a source checkout or physical tools.

| Responsibility | Current implementation / public boundary |
| --- | --- |
| Stage names, order, demonstrated capabilities | `lib/flow_stage.ml`, `Flow.Stage` |
| Contiguous recipes, inputs, checkpoint outputs, serialization | `lib/flow_recipe.ml`, `Flow.Recipe` |
| Python runtime plan resolution and advertised capabilities | `flow/hardcaml_asic_flow/execution_plan.py` |
| Checked OCaml plans, resolution, action contracts and inspection | `lib/execution/execution_plan.{ml,mli}`, `Hardcaml_asic_execution.Execution_plan` |
| Installed experimental plan-inspection command | `bin/experimental_plan_inspect.ml`, `$PREFIX/bin/hardcaml-asic-experimental-plan-inspect` |
| Versioned backend request/reply models and strict runtime validators | `lib/execution/backend_protocol.{ml,mli}`, `flow/hardcaml_asic_flow/backend_protocol.py` |
| Native process specification and owned-group supervision primitive | `lib/execution/process.{ml,mli}`, `lib/execution/process_supervisor.{ml,mli}` |
| Explicit native/Docker bindings, command specifications and owned-container cleanup primitive | `lib/execution/execution_transport.{ml,mli}` |
| Pure bundle-authoritative runtime policy, metadata/readiness evidence and image/engine identity validation | `lib/execution/runtime_contract.{ml,mli}`, `lib/execution/runtime_evidence.{ml,mli}` |
| Exclusive attempt allocation, atomic finite JSON records and preflight record constructors | `lib/execution/result_store.{ml,mli}`, `Hardcaml_asic_execution.Result_store` |
| Python coarse-service runtime policy/probes and transport integration | `flow/hardcaml_asic_flow/execution_transport.py`, `runtime_observation.py`, `phase4.py` |
| Retained Python segment API/fixtures (not public stages dispatch) | `flow/hardcaml_asic_flow/stages.py` |
| Authoritative OCaml prepared-path segment callbacks and supervised publication validation | `lib/execution/segment_service.{ml,mli}`, `Hardcaml_asic_execution.Segment_service` |
| Typed closed bridge reports and finite public candidate metrics | `lib/execution/segment_report.{ml,mli}`, `Hardcaml_asic_execution.Segment_report` |
| Installed prepared-path execution harness | `bin/experimental_segment_execute.ml`, `$PREFIX/bin/hardcaml-asic-experimental-segment-execute` |
| OCaml-owned stage readiness, staging and exact retained resumption | `lib/execution/stage_preparation.{ml,mli}`, `Hardcaml_asic_execution.Stage_preparation` |
| Supervised runtime/collateral probes and bound engine/image re-verification | `lib/execution/runtime_probe.{ml,mli}`, `Hardcaml_asic_execution.Runtime_probe` |
| Import-only protocol-1 metadata payload | Installed `flow/hardcaml_asic_flow/stage_metadata_probe.py` |
| Installed preparation/execution command; authoritative public CLI4 stage backend | `bin/experimental_stages.ml`, `$PREFIX/bin/hardcaml-asic-experimental-stages`, `flow/hardcaml_asic_flow/ocaml_backend.py` |
| Typed read-only checkpoint reader/host validator and experimental inspector | `lib/execution/checkpoint.{ml,mli}`, `bin/experimental_checkpoint_inspect.ml` |
| Bounded candidate publisher and explicit native-state codec | `lib/execution/checkpoint_publisher.{ml,mli}`, `backend_state.{ml,mli}` |
| Generic synchronous typed orchestration and coarse lifecycle hooks | `lib/execution/runner.{ml,mli}`, `Hardcaml_asic_execution.Runner` |
| Typed observation schema, immutable reducer/prefix and host-only cold/incremental readers | `lib/execution/observation.{ml,mli}`, `Hardcaml_asic_execution.Observation` |
| Bounded schema-2 journal writer and experimental stage lifecycle hooks | `lib/execution/observation_writer.{ml,mli}`, `Stage_preparation`, `bin/experimental_stages.ml` |
| Installed experimental observation reader | `bin/experimental_observation_read.ml`, `$PREFIX/bin/hardcaml-asic-experimental-observation-read` |
| Public stage journal writer | `lib/execution/observation_writer.ml`, `bin/experimental_stages.ml` |
| Authoritative public foreground watch and native human/JSONL delivery | `bin/observation_watch.ml`, `bin/experimental_observation_read.ml`, `flow/hardcaml_asic_flow/ocaml_backend.py` |
| Retained Python observation API and differential fixtures | `flow/hardcaml_asic_flow/flow_observation.py` |
| Public checkpoint/observation cold-query delegation and presentation | `flow/hardcaml_asic_flow/ocaml_backend.py`, `cli.py`; actual typed OCaml readers |
| Retained Python checkpoint API and finalization inspection helpers | `flow/hardcaml_asic_flow/checkpoint.py` |
| LibreLane-native state/configuration and Classic invocation | `flow/hardcaml_asic_flow/librelane_bridge.py` |
| Installed executable and Python runtime resources | `flow/dune`, `$PREFIX/bin/hardcaml-asic-flow`, `$PREFIX/lib/hardcaml_asic/flow/hardcaml_asic_flow/` |
| Cross-language semantic emitter and contract checks | `test/stage_recipe_contract.ml`, `test/check_stage_recipes.py`, `@test/ocaml-stage-recipes` |
| Checkpoint handoff regression and installed consumer checks | `test/test_stages.py`, `@test/stage-checkpoint`, `test/test_installed_prefix.py` |

Recipe schemas remain the existing endpoint/resume schema 2 and explicit
contiguous sequence schema 3. No persisted record or public API changes are
required by these checks; the test emitter additionally reports stage order.

## Existing Classic grouping boundaries

| Stage | Endpoint | Immediate successor for continuation | Standalone restart targets |
| --- | --- | --- | --- |
| synthesis | `Yosys.Synthesis` | `Checker.YosysUnmappedCells` | floorplan, placement |
| floorplan | `OpenROAD.Floorplan` | `OpenROAD.DumpRCValues` | placement |
| placement | `OpenROAD.DetailedPlacement` | `OpenROAD.CTS` | cts |
| cts | `OpenROAD.CTS` | `OpenROAD.STAMidPNR-1` | routing |
| routing | `OpenROAD.DetailedRouting` | `Odb.RemoveRoutingObstructions` | signoff |
| signoff | `Misc.ReportManufacturability` | none | none |

Each continuation includes the immediate successor through the requested
endpoint, preserving intervening Classic checks and configured gates. These are
groupings in one upstream Classic flow. Placement includes post-floorplan power
network/setup work; routing includes post-CTS STA/repair; signoff includes
post-routing checks, fill, and extraction. The selected runtime determines the
actual steps and configured gates; the table is not an exhaustive step inventory.

The standalone synthesis-to-placement transition remains supported. Explicit
recipes still include floorplan and reject skipped stages. Signoff is terminal:
its OCaml/planner successor is null and restart targets are empty; the bridge
deliberately omits signoff from both sparse continuation tables. Contract checks
require precisely that representation, rather than masking extra entries.

Static capabilities retain the exact tested image, path-bound closure, and
`not_evaluated` acceptance. They do not establish runtime readiness, relocation
support, external postcheck success, or accepted physical results.

## Verification delivered

The OCaml emitter supplies actual capability values and recipe results. The
Python checker compares all advertised planner fields, explicit stage order,
and the bridge's `ENDPOINTS`, `SUCCESSORS`, and `RESTART_TARGETS`. Bridge tables
are extracted with `ast.parse` / `ast.literal_eval`; LibreLane and the bridge
module are never imported or executed. Missing tables, duplicate definitions,
duplicate keys, and nonliteral tables fail closed.

There are 33 deliberate negative checks covering planner fields/order, bridge
values/missing/extra entries/order, terminal entries, the standalone placement
target, and malformed literal declarations. Execution poison appended to bridge
text also proves AST extraction is inert.

The installed-prefix suite repeats the contract with installed planner and
bridge resources. It copies only the test drivers and linked OCaml emitter to
an unrelated directory and installs an audit hook denying all checkout file
reads and LibreLane/bridge imports. It also exercises installed checkpoint
inspection with the existing synthetic publication fixture.

Validation commands (sequential; internal Dune commands also use `-j 20`):

```sh
dune build -j 20 @install test/stage_recipe_contract.exe
dune build -j 20 @test/ocaml-stage-recipes @test/stage-checkpoint
python3 -B test/test_installed_prefix.py
```

Results: contract agreement, 33 drift negatives rejected, 36 accepted / 1819
rejected recipe cases, and 56 installed-prefix tests passed (including the
installed 30-test stage/checkpoint suite). The runtime bridge bytes are preserved
because checkpoint identity includes their digest. Adapter protocol changes,
stage decomposition, and modularized flow files/profiles remain later slices.

## Execution foundation: strict scoped identity JSON

Implemented as the next bounded infrastructure dispatch on 2026-10-13. This is
a prerequisite for the protocol/models/control migration, rather than completion
of architecture slices 2–4.

### Installed boundary and public API

`lib/execution/` defines a separate wrapped public library
`hardcaml_asic.execution`, namespace `Hardcaml_asic_execution`. Its initial module
is `Hardcaml_asic_execution.Identity_json`, with a typed `.mli`, private JSON
variants, validating smart constructors, strict parsing, canonical serialization,
SHA-256 byte/JSON helpers, exact-object-field checking, and unsigned-envelope
extraction. Direct dependencies are Cryptokit and Zarith; the hardware library
does not depend on this execution library. The finite-float corrective continuation
added an explicit Zarith package dependency. No Python runtime ownership moved.

The implementation inspected the real persisted writers/readers first:

- `checkpoint.canonical` / `identity` and `flow_observation.canonical` / `digest`
  hash Python `json.dumps(sort_keys=True, separators=(",", ":"), allow_nan=False)`
  encoded as UTF-8. The default `ensure_ascii=True` is identity-significant.
- Journal hashes exclude `sha256`; checkpoint hashes exclude `identity`.
- `result_store.save_json` uses sorted, indented JSON plus newline and permits
  Python's default nonfinite values. It is **not** a canonical identity writer.
  Its finite supported values can be read and canonicalized by this codec, but
  this slice does not replace its writer or redefine its persisted bytes.
- Native LibreLane state can contain Infinity and remains opaque backend data.

### Exact capability and compatibility domain

This is Python identity JSON, not RFC 8785. The parser implements strict JSON
grammar directly so permissive Yojson extensions cannot enter persisted identity
data. It rejects duplicate decoded keys at every depth, malformed objects and
numbers, trailing data, nonfinite/overflow numbers, invalid UTF-8, and nesting
beyond 256 levels. Closed schema field validation is separate from syntax parsing.

Supported values are null, booleans, arbitrary-precision decimal integers,
Unicode scalar strings, arrays, unique string-key objects, and **all finite
binary64 floats**. Integers never pass through machine integers or floats; Python's
configurable integer digit resource guard is not duplicated. Object order is
Unicode code-point order, without normalization; strings use Python's short
control escapes and lowercase ASCII Unicode escapes, including surrogate pairs
for supplementary scalars. Unpaired surrogate code points, which Python can
represent, are explicitly unsupported rather than repaired.

The initial bounded exact-float implementation was superseded by the corrective
continuation below. Finite floats now use exact shortest-roundtrip decimal digits,
nearest to the binary64 value with decimal ties to even. Scientific notation is
used when the resulting decimal exponent is below -4 or at least 16; exponents
have an explicit sign and at least two digits. Fixed integral floats end in `.0`.
This preserves `1` versus `1.0`, integer `-0` becoming `0`, and float `-0.0`.
Parsing rounds decimal float tokens to binary64, including signed underflow zero,
as Python does; overflow/nonfinite values are rejected. `Unsupported_float` is
retained for source compatibility but no finite binary64 value produces it.

### Verification and handoff

`test/execution_identity_driver.ml` is a real linked OCaml consumer.
`test/check_execution_identity.py` compares its bytes and digests with the actual
Python checkpoint and observation functions, including exact decimal midpoint
cases using `Decimal.from_float`. Coverage includes Unicode/escaping and
key ordering, large integers, lexical numeric rounding, signed zero, fixed and
scientific floats, subnormals/extremal finite values, nested duplicate keys,
malformed syntax, overflow, surrogate/UTF-8 rejection, exact-field checks, and
unsigned checkpoint/journal-shaped envelopes. Literal canonical/digest goldens
and a SHA-256 known-answer test supplement differential comparisons. Journal-like
hash chains and pretty result-store records exercise real writer/readers; they
are identity fixtures, not claims of schema/lifecycle validity.

The `--installed` check installs into a disposable prefix and builds a fresh
consumer outside the checkout using only `hardcaml_asic.execution`. It verifies
the installed META dependency boundary and reruns the differential suite with
installed Python helpers while denying Python checkout reads.

Validation commands (all Dune invocations sequential and `-j 20`, including
installation and the independent consumer build inside the installed test):

```sh
dune build -j 20 @install @test/execution-identity @test/ocaml-stage-recipes
python3 -B test/check_execution_identity.py --installed
```

Initial foundation results: **5,029 accepted byte/digest parity cases and 670 rejected cases** in
both source-linked and independently installed consumers. The slice-1 stage
contract also passed: 33 deliberate drift negatives, 36 accepted recipes, and
1,819 rejected recipes. `@install` and `git diff --check` passed.

Remaining work at that foundation handoff: define the versioned backend protocol
and typed plan models; migrate process supervision and storage/publication with one writer;
then migrate observations/results/CLI under existing lifecycle and identity
invariants. No process/storage migration, backend execution, new restart promise,
or modularized-flow capability was implemented here.

### Corrective continuation: general finite binary64 (2026-10-13)

Scope: codec float conversion, differential consumers/tests, dependency declaration,
and these progress notes. Existing parser, Unicode rules, protocol, processes,
and publication ownership retain their foundation behavior.

No suitable shortest-decimal formatter was exposed by the inspected installed
float interfaces. The implementation uses installed Zarith for exact rounding
interval arithmetic rather than printf digit generation or a Python subprocess:

- Represent positive binary64 values as integer multiples of `2^-1074`; compute
  predecessor/successor midpoint bounds exactly, including asymmetric power-of-two
  intervals and the maximum-finite virtual successor `2^1024`.
- Include midpoint endpoints exactly when the binary significand is even.
- For each precision from 1 through 17, compute exact floor/ceil decimal grid
  candidates and test membership. The first successful precision is shortest;
  choose the closest admitted candidate, with exact decimal ties to even.
  More distant candidates cannot be preferable on the same grid. A carry at a
  power of ten is normalized before applying Python's notation thresholds.
- `log10` only seeds the decimal exponent; exact integer comparisons correct it.
  Digits, bounds, membership and tie decisions use only integer arithmetic.
  The smart constructor accepts finite floats without formatting or coercion.

Verification: **62,221 accepted byte/SHA-256 parity cases and 55 rejected cases**
passed in both source-linked and fresh independently installed consumers. The
bounded suite includes 30,000 seeded random raw 64-bit patterns, both signs and
six significands for every finite binary exponent, decimal power boundaries and
adjacent values, exact decimal parsing midpoints and perturbations, shortest-output
ties, signed zero/underflow, minimum subnormal, maximum finite, overflow and
nonfinite rejection. Raw-bit input tests call the OCaml float constructor directly,
avoiding shared decimal parsing as a source of false agreement.

Captured real producer elapsed/duration numbers from the two checked-in
`evidence/librelane-observation/journal-event-timing*.json` records and existing
report metric numbers supplement hash-chain, unsigned envelope, and result-store
pretty-writer checks. These remain identity fixtures, not lifecycle/schema tests.

Final commands (sequential, all Dune invocations including installed checks `-j20`):

```sh
dune build -j20 @install @test/execution-identity
python3 -B test/check_execution_identity.py --installed
git diff --check
```

Source build/check took approximately 2 seconds; installed consumer build/check
took approximately 2.3 seconds. Installed META declares exactly `cryptokit zarith`
for this sublibrary; `dune-project` and generated `hardcaml_asic.opam` both declare
Zarith. The prior finite-number compatibility blocker is resolved: general finite
journal/checkpoint timing and metric identities can now use this boundary.
The handoff at that point was typed models/protocol and later migration under existing
identity/lifecycle invariants. No staging, commits, or Git mutations were performed.

## Typed execution plans and installed inspection (2026-10-13)

Delivered the next bounded model slice. The runtime Python planner/runner remains
the execution owner; the OCaml models can now validate and resolve the same
supported plans independently. This is partial infrastructure slice 3/4 work,
not completion of the backend adapter or lifecycle migration.

### Namespace, dependencies and exported API

`Hardcaml_asic_execution.Execution_plan` is installed in
`hardcaml_asic.execution`. It uses `Identity_json` for all parsing, exact-field
validation, JSON construction and canonical output; no second JSON codec was
introduced. The execution sublibrary now depends on `hardcaml_asic` as well as
Cryptokit/Zarith. Hardware-only consumers acquire no execution dependency.
The previously recorded `cryptokit zarith` META dependency describes the earlier
identity-only slice; current installed META is `cryptokit hardcaml_asic zarith`.

Exported boundaries in `lib/execution/execution_plan.mli`:

- `Action`: private inspectable records, typed operation/gate/phase variants,
  enabled state, semantic key, label, requirements, inputs/outputs and `to_json`.
  Executable contracts cannot be constructed or edited by consumers.
- `Coarse`: abstract schema-1 plans; `Synthesis`/`Full` endpoints, `resolve`,
  Unicode-checked `with_labels`, endpoint/actions inspection and JSON round-trip.
- `Stage_plan`: abstract schema-2/3 plans; `resolve` for legacy endpoint/resume,
  `resolve_sequence`, `through`, and `of_recipe` for checked schema-3 declarations;
  schema/endpoint/source/sequence/recipe/actions inspection and JSON round-trip.
- `Stage`/`Recipe` aliases reuse `Hardcaml_asic.Flow.Stage` and `.Recipe`.
  Recipe validation, declarations and source/endpoint semantics are reused rather
  than independently maintaining stage order or transition validation.
- Private top-level `Coarse`/`Stages` variant with `of_coarse`, `of_stages`,
  `of_json`, `parse`, `to_json`, `actions`, `capabilities` and `inspection`.

Schema versions must be integers, not booleans or numerically equal floats.
All plan/action fields are closed; malformed types and modified executable
contracts fail. Coarse disabled postcheck/archive actions remain in the plan,
with their original dependencies and `run_available`/`accepted` gates. Labels
are presentation-only and can be empty, duplicated, or contain Unicode/control
characters; the codec's Unicode scalar restriction still applies.

Schema 2 resumed plans start after synthesis and include every stage through the
endpoint. Schema 3 preserves the explicit initial boundary and contiguous recipe.
The first resumed action has a checkpoint input but no internal action dependency.
The standalone synthesis→placement capability remains advertised, while recipes
reject `[placement]` after synthesis because floorplan cannot be skipped.
Capabilities come directly from `Flow.Stage.capability`, retaining exact image,
path-bound closure and `not_evaluated` acceptance.

### Installed command usage

```sh
hardcaml-asic-experimental-plan-inspect plan.json
hardcaml-asic-experimental-plan-inspect < plan.json
hardcaml-asic-experimental-plan-inspect - < plan.json
hardcaml-asic-experimental-plan-inspect --help
```

This small native executable uses simple argument handling without a new CLI
dependency. It emits one canonical JSON object plus newline containing `plan`,
`actions`, `source_boundary`, `sequence`, and `capabilities`. Coarse source and
sequence are null; stage plans expose their resolved source and stage list.
Invalid plans, unreadable files and argument errors exit 2, write diagnostics to
stderr, and produce no stdout. Help exits 0. The command does not probe tools or
execute a flow. Its explicit experimental name is for installed differential
testing and later CLI integration; `hardcaml-asic-flow` still uses Python.

### Exact verification and handoff

`test/check_execution_plans.py` invokes the production inspector and compares
normalized plans, every action field, sources, sequences and capabilities with
actual Python `Plan.from_dict` / `StagePlan.from_dict`. Its valid/invalid corpus
covers all contiguous fresh/resumed ranges, legacy endpoints, all length-0–3
stage products across valid/invalid sources, longer repeated/reordered sequences,
all coarse contract fields, schema bool/int/float distinctions, arbitrary labels,
disabled actions, gate/dependency edits, unknown/missing fields and malformed
types. Strict parser negatives include duplicate fields, unpaired surrogates,
trailing data and invalid syntax. File/stdin, paths with spaces, help, missing
files and argument errors are checked. Command checks run with unusable PATH and
PYTHONPATH, establishing no tool/runtime lookup requirement.

`test/execution_plan_consumer.ml` exercises exported checked resolution APIs,
label validation, recipe conversion/composition, source inspection and wrapping.
Its resolved plans are independently compared with actual Python resolvers.
The `--installed` check installs into a disposable prefix, builds this consumer
in an unrelated directory against only the installed library, checks the META
dependency direction, and repeats the entire corpus through the installed native
command and installed Python planner. A Python audit hook denies checkout reads
and LibreLane/bridge imports during verification. No source lookup is needed by
the native command or independently built consumer.

Commands run sequentially, including nested Dune installation/consumer builds:

```sh
dune build -j 20 @install @test/execution-plans @test/execution-identity @test/ocaml-stage-recipes
python3 -B test/check_execution_plans.py --installed
python3 -B test/check_execution_identity.py --installed
git diff --check
```

Results: **164 accepted / 4,900 rejected** plan cases passed in both source-linked
and independently installed checks, along with API-resolution and command checks.
Identity regression passed **62,221 accepted / 55 rejected** byte/hash cases in
both linked and fresh installed consumers. The existing `ocaml-stage-recipes`
alias and `@install` passed. Full flow/physical suites were not needed for this
pure model/inspection slice.

Remaining blockers/handoff: define the versioned backend adapter protocol and
process outcome contracts; integrate these models into a future OCaml CLI/runner;
then migrate process supervision, storage/publication, observation and results
with one authoritative writer under the existing identity/lifecycle invariants.
Runtime checkpoint compatibility and actual backend readiness still belong to
the existing service. This slice adds no storage/protocol implementation,
new restart boundary, stage decomposition or modularized flow/profile support.
Accumulated work was preserved; no staging, commits or Git state mutations occurred.

## Bounded backend adapter protocol (2026-10-13)

Delivered the versioned boundary used by the existing Python `SegmentAdapter`
and isolated LibreLane-native bridge. This is infrastructure slice 2; process
supervision, storage/publication, CLI, observations and results retain their
existing authoritative Python owners.

### Typed and runtime boundaries

`Hardcaml_asic_execution.Backend_protocol` is installed in the existing
`hardcaml_asic.execution` library. The `.mli` exports typed operations
`Execute_segment` / `Validate_publication`, a private request record, validating
`make_request`, JSON parsers/serializers, canonical request identity, and private
reply/artifact records with `Completed`, `Validated`, or `Failed of string`
outcomes. All codec and identity operations use `Identity_json`; there is no
second OCaml JSON parser and no new library dependency. Byte counts are
arbitrary-precision nonnegative integer strings, never floats or machine-int
coercions. The module does no IO and explicitly requires callers to combine wire
evidence with successful process outcome, artifact verification and publication.

The stdlib-only Python `backend_protocol.py` implements the same closed schema:

- Requests carry integer `protocol_version: 1`, operation, occurrence/request ID,
  fresh reply path, project/PDK/candidate paths, boundary, tag, bridge SHA-256,
  nullable checkpoint path and source boundary. Paths are absolute and strings
  exclude empty values/NUL; SHA-256 is exactly 64 lowercase hex characters.
- Fresh execution is synthesis only, without a source. Continuation requires
  both checkpoint and source and a demonstrated standalone restart transition,
  including synthesis→placement. Publication validation has no continuation
  source. The OCaml validator uses `Flow.Stage.capability` for transitions.
- Replies correlate version, operation, request ID, boundary, candidate, bridge
  digest and **canonical SHA-256 of the entire request** (also binding input paths,
  source, tag and reply location). Success has null error and exact evidence:
  execute returns `state.json`, `resolved.json`, `closure.json`, `segment.json`;
  validation returns only `resolved.json` and `closure.json`. Each evidence record
  carries the expected candidate-relative absolute path, byte count and SHA-256.
- `failed` requires a nonempty diagnostic and **no artifact evidence**. Execute
  cannot return `validated`; validation cannot return `completed`. Neither success
  outcome claims readiness, publication or acceptance. Extra/missing fields,
  wrong types (including bool/float versions and byte counts), duplicates,
  malformed JSON, nonfinite numbers and unpaired Unicode surrogates fail closed.

The bridge uses the protocol before constructing Classic or creating candidates.
Execution still waits for successful `Flow.start`, closure stability, endpoint
and immediate-successor checks before writing the unchanged successful
`segment.json` fields and an exclusive fresh reply file. Ordinary backend
exceptions may write a correlated failed diagnostic reply and still exit
nonzero. Invalid requests/version/integrity failures have no usable reply.
`BaseException` interruption/signal/SystemExit is not converted into a completed
or ordinary failed response. Partial files are evidence of an attempt only.

The host preserves the launcher's existing exit/exception behavior: any nonzero
exit wins over success-looking files; `FlowInterrupted` remains interrupted with
its existing signal-derived status. Only zero exit plus strict correlated reply,
matching artifact bytes and existing outer-completion checks returns a completed
`SegmentResult`. The adapter remembers its completed request and rechecks reply
evidence and transported resources before publication. Image-only closure
validation additionally requires a strict `validated` reply before the existing
storage writer's atomic promotion. Missing/malformed/mismatched/failed replies
cannot publish, even with zero process exit. `checkpoint.py` and persisted
checkpoint schemas/writers are unchanged. Native state containing Infinity is
hashed as opaque file bytes and is never parsed by the protocol/identity codec.

### Transport closure, installation and compatibility

`flow/dune` installs `backend_protocol.py`; `stages.prepare` copies it alongside
the bridge into a fresh workspace. `PROTOCOL_SHA256` is an explicit literal pin
inside `librelane_bridge.py`. Thus the existing compatibility `bridge_sha256`
transitively binds the exact support resource, without weakening or changing
the persisted compatibility schema. The host checks the copied resource against
both that AST-extracted pin and the host validator's installed bytes. The isolated
bridge reads, verifies, compiles and executes exactly the pinned bytes, including
under `-I -B`; it neither edits `sys.path` nor consults a sibling bytecode cache.
Protocol edits must update the literal pin; resource drift fails closed in tests
and at runtime. The existing inert AST capability/table checks remain intact.

**Compatibility decision:** historical unversioned bridge requests can be read
as retained JSON/evidence but are rejected by v1 execution; no compatibility
reply or request is fabricated. Existing checkpoint inspection continues to use
its recorded compatibility. The changed bridge bytes invalidate old checkpoints
for new-adapter continuation through the existing compatibility comparison.
Fresh checkpoints in a fresh workspace are required. No retained workspaces,
requests, checkpoints or checked-in evidence were modified or upgraded.

### Verification delivered

`test/backend_protocol_driver.ml` is a real OCaml consumer, including validating
constructor/round-trip checks. `test/check_backend_protocol.py` compares actual
request/reply JSON and canonical output between OCaml and Python: **50 accepted /
886 rejected** cases. The corpus includes every source/endpoint/checkpoint
combination for both operations, all six real fixture-backed bridge execution
ranges, standalone synthesis→placement, both success operations, diagnostic
failures, unknown/missing fields, malformed nested evidence, wrong scalar types,
Unicode, large integer byte counts, mismatched correlation/hash, wrong version,
duplicate fields, malformed/trailing JSON and nonfinite syntax.

`test/bridge_protocol_fixture.py` replaces only native LibreLane APIs; the actual
transported bridge runs in subprocesses with `-I -B`. Checks cover ordinary/deferred
failure, incompatible initial State, successful configuration/closure validation
without `Flow.start`, validation mismatch, malformed/legacy/version requests,
retained reply rejection, hash-tampered support rejection before execution,
KeyboardInterrupt and real SIGTERM with no completion reply. These are protocol
fixtures, not evidence of physical-tool readiness.

The actual host adapter is also driven through fixture-backed bridge calls,
checking successful publication and no-publication for failures/corrupt replies
and mutated artifact bytes. `test/test_stages.py` now has **34 tests**, including
zero-exit missing/malformed/mismatched/out-of-version/failed/evidence responses,
publication-validation reply failures, support-resource mutation before launch,
and `FlowInterrupted` overriding a valid completed reply. Existing checkpoint
and lifecycle regression assertions are preserved.

`--installed` installs into a disposable prefix and builds a fresh consumer
outside the checkout against the installed execution library. It copies only
the fixture driver and uses installed resources under an audit hook denying
checkout reads. The installed-prefix suite separately copies the wire driver,
fixture and linked consumer outside the checkout and repeats the actual bridge
corpus with installed resources. Result: **57 installed-prefix tests** pass,
including the installed 34-test stage/checkpoint suite and existing CLI,
cancellation, observations, inspection and finalization checks.

Commands run sequentially; every Dune invocation, including nested installation
and consumer builds, uses `-j20` (equivalently `-j 20`):

```sh
dune build -j20 @test/backend-protocol @test/stage-checkpoint @test/ocaml-stage-recipes @test/flow-observation @test/default-journal @test/observation-watch @test/related-presentation @test/inspector-presentation @test/execution-transport @install
python3 -B test/check_backend_protocol.py --installed
python3 -B test/test_installed_prefix.py
python3 -B test/test_packaging.py
git diff --check
```

Other source regression results: flow-observation 45, default-journal 8,
observation-watch 11, related-presentation 10, inspector-presentation 11,
execution-transport 20 and packaging 17 tests passed. Capability AST checks
retained 33 deliberate drift negatives; recipe checks retained 36 accepted /
1,819 rejected cases. `@install` and whitespace checks passed.

### Handoff

The next integration slice should exercise fresh installed requests/checkpoints
against the selected exact LibreLane image and real physical tools, including
image-only closure validation and restart handoffs. That is where runtime
readiness of the changed bridge should be established. This dispatch ran no
physical EDA. Later bounded work can migrate process supervision and
storage/publication with one writer, then observations/results/CLI; the typed
plan inspector and protocol are available as foundations. No finer stage
decomposition or new restart/profile capability is claimed. Accumulated changes
were preserved; no staging, commits, push, stash or reset was performed.

## Installed protocol-v1 runtime integration (2026-10-13)

Bounded sole-agent integration used the consumer-owned refresh script with a new
private store, unchanged consumer dependency record, existing consumer `_flow_tools`,
and a new workspace. Curated evidence is
[`backend-protocol-v1-integration.json`](../../evidence/librelane-observation/backend-protocol-v1-integration.json).
The retained slice4-production and slice6-finalizations trees were not rewritten.

### Real runtime results

One ordinary consumer `run --endpoint signoff --bundle ... --json` invocation
reached **synthesis → floorplan → placement → CTS → routing** successfully. Each
boundary produced a protocol-v1 `completed` reply and a separate image-only
`validated` publication reply before atomic checkpoint promotion. All ten replies
were audited against canonical request identities and evidence byte counts/hashes;
all five checkpoints passed installed `checkpoint-inspect` with their immediate
restart target. The floorplan/placement calls started at the declared Classic
immediate successors, using the freshly published checkpoint states.

| Boundary | Seconds including publication | Checkpoint under fresh workspace |
| --- | ---: | --- |
| synthesis | 5.156551 | `checkpoints/synthesis-q9pbm20o` |
| floorplan | 5.004620 | `checkpoints/floorplan-kmyugkof` |
| placement | 11.490982 | `checkpoints/placement-clr_v4f9` |
| cts | 11.028633 | `checkpoints/cts-_tk5_n95` |
| routing | 65.620547 | `checkpoints/routing-238c48we` |

Workspace:
`/tmp/opencode/backend-v1-integration/results/signoff-1126383-2667d2be2e991b4119b0b8853a4e75da`.
Execution: `execution-e6a88901e659480a892d323fb3568378.json` inside it.
Observation: `/tmp/opencode/backend-v1-integration/results/observations/20261013T203722223410Z_e6a88901`.
Raw audit and exact wire/log pointers: `/tmp/opencode/backend-v1-integration/audit.json`.
Consumer stdout/stderr: `consumer.jsonl` and `consumer.stderr.log` in that root.

The transported `backend_protocol.py` digest is
`732c05a5009f0510ec2624f7ddc03e86bb2a20cf824a9bb9c96d947bc0f2e49d`,
matching both the bridge literal pin and installed host bytes. Bridge digest is
`e8dc9532c61010ae8699d3a6f27cdfd0d773ff3e24d06f9eefbe2d0f5b2da841`.
Runtime is the declared exact image, LibreLane 3.1.0.dev3, container Python
3.13.13, host flow Python 3.11.17 and Docker 29.8.1. An experiment-only Docker
delegator adds `--cpus=20`, `_OPENLANE_MAX_CORES=20` and `OMP_NUM_THREADS=20`.
Upstream OpenROAD nevertheless logs `None` threads/ORD-0032 for unset
`OPENROAD_THREADS`; CPU quota bounds execution, but a universal 20-thread count
is not established. No source bundle/configuration override was made.

**Full-flow limitation:** signoff entered Magic DRC and hit the consumer/provider
default 600-second segment timeout. Signoff duration was 600.760101 seconds;
whole consumer elapsed time was 699.939644 seconds, exit 2. There is no signoff
reply or publication, and owned-container cleanup was verified. The observation
records terminal failure with no active writer. The provider's current `stages`
CLI offers `--timeout`; the consumer's current `project run` does not forward it.
The expensive implementation was attempted once. This failed execution is not
eligible for six-stage finalization or acceptance; no physical rerun or stitched
history was used to claim otherwise.

### Direct integration defect and correction

Inspection found `finalization.runtime_validate` still sent the old mode-only
request and trusted process success without a wire reply. Calling that real
closure-only helper against the new routing publication reproduced the selected
image's `missing/unknown protocol fields` rejection. This is a direct missed
protocol caller, fixed in `flow/hardcaml_asic_flow/finalization.py`:

- Verify retained bridge/support hashes against the pinned installed protocol.
- Send a complete v1 `validate_publication` request with a fresh correlated reply.
- Require zero process exit, strict correlated `validated` reply and matching
  artifact bytes before declaring runtime validation complete.

The corrected provider was installed into a second immutable generation, and the
same real closure-only helper passed against the exact image with provider-checkout
opens denied. Before/after evidence lives in
`/tmp/opencode/backend-v1-integration/finalization-protocol-{before,after}/`.
This helper check uses the routing checkpoint's real shared configuration/closure;
it does not assert signoff boundary completion, finalization eligibility or acceptance.
Historical unversioned retained bridges do not satisfy the new v1 validation;
historical finalization receipt inspection remains supported and read-only.

`test/test_finalization.py` now covers a valid wire reply plus rejection of missing,
wrong request hash, wrong version, failed, altered artifact digest and nonzero-process
responses, and rejection of mutated transported support before launch.

### Installation, source denial and exact commands

Initial consumer-owned snapshot generation:
`/tmp/opencode/backend-v1-consumer-install/generations/0aa0c3d30e0f43068128a93c089ceeca`.
Corrected generation:
`/tmp/opencode/backend-v1-consumer-install/generations/46ca800a53aa45b18d5d5a33fbe2d162`.
Receipts/activation are retained there; the consumer's normal `.dev/asic` selection
and recorded pin were not edited. Fresh unrelated Dune consumer builds and
`project describe --json` passed against both installed generations. The refresh
script also compiles its independent API probe/consumer before publishing.

The real consumer selected `/tmp/opencode/backend-v1-integration/bin/hardcaml-asic-flow`,
an audit-hook launcher importing only the initial installed production CLI. It
denies provider-checkout opens before imports. Corrected finalization validation
uses the second prefix under the same denial policy. This establishes practical
source-denied Python integration, not a kernel-wide filesystem sandbox. Container
mounts include the new workspace/PDK and never the provider checkout.

Commands were sequential where Dune was involved; nested builds/installations
also use `-j20`. From the consumer checkout:

```sh
python3 -B scripts/asic_dependency.py --store /tmp/opencode/backend-v1-consumer-install refresh --source /home/wayne/devel/jane/hardcaml_asic --mode development
. /tmp/opencode/backend-v1-consumer-install/current/activate.sh
dune exec -j20 bin/project.exe -- run --help
dune build -j20 bin/project.exe acceptance/export_trace.exe
# launch.py invokes the built consumer with the audit/CPU-limit wrappers on PATH:
python3 -B /tmp/opencode/backend-v1-integration/launch.py
# Exact consumer argv (the script captures stdout/stderr and elapsed time):
_build/default/bin/project.exe run --endpoint signoff --bundle /home/wayne/devel/jane/hardcaml_asic_example/_flow_results/bundles/bbbda7ff53ea33cabf0063f7b26509bf601420ad5ab46c07e511fc8e9ee79477 --results-root /tmp/opencode/backend-v1-integration/results --toolchain /home/wayne/devel/jane/hardcaml_asic_example/_flow_tools --json
ocamlfind query hardcaml_asic
dune build -j20 --build-dir /tmp/opencode/backend-v1-integration/consumer-build bin/project.exe acceptance/export_trace.exe
```

Provider/check commands, including the real defect reproduction and corrected
reinstallation (the refresh command above was repeated after the fix):

```sh
python3 -B test/check_backend_protocol.py --installed
python3 -B test/test_installed_prefix.py
python3 -I -B /tmp/opencode/backend-v1-integration/audit.py
python3 -I -B /tmp/opencode/backend-v1-integration/check_finalization_protocol.py /tmp/opencode/backend-v1-consumer-install/generations/0aa0c3d30e0f43068128a93c089ceeca before
dune build -j20 @test/finalization @test/stage-checkpoint @install
python3 -I -B /tmp/opencode/backend-v1-integration/check_finalization_protocol.py /tmp/opencode/backend-v1-consumer-install/generations/46ca800a53aa45b18d5d5a33fbe2d162 after
python3 -B test/test_installed_prefix.py
git diff --check
```

After corrected activation, from the consumer:

```sh
dune build -j20 --build-dir /tmp/opencode/backend-v1-integration/consumer-build-fixed bin/project.exe
/tmp/opencode/backend-v1-integration/consumer-build-fixed/default/bin/project.exe describe --json
```

Results: installed protocol **50 accepted / 886 rejected** plus isolated-bridge
and no-publication checks; source finalization **16** and stage/checkpoint **34**
tests; corrected installed-prefix **57** tests in **22.509 seconds**; installation,
independent linkage and whitespace checks passed. No protocol wire/bridge change
was needed for the finalization-caller fix, so the fresh physical checkpoints
retain compatibility with the corrected installation.

Remaining runtime gate: completed fresh six-stage execution with an adequate
explicit signoff budget, then full finalization/external acceptance. Later process,
storage and CLI migration remains separate. No staging, commits, push or other Git
mutation was performed; accumulated user changes and retained physical evidence
were preserved.

Final read-only evidence consistency check:
`python3 -B /tmp/opencode/backend-v1-integration/verify_curated.py` passed, comparing
the compact JSON with retained execution/wire audits, checkpoint identities,
installation receipts and the corrected installed finalization helper. The final
consumer `git status --short` was empty and `git diff --check` passed.

## Bounded OCaml process supervisor (2026-10-13)

Delivered an actual synchronous process primitive in `hardcaml_asic.execution`,
namespace `Hardcaml_asic_execution.Process` / `.Process_supervisor`. This is the
process-ownership foundation for infrastructure slice 4. The Python public CLI,
`phase4.run_logged`, transport, result-store and publication writers remain the
owners of existing flow invocations; the next runner can delegate its launches to
this installed OCaml boundary. No physical flow was run for this slice.

### Exact APIs and behavior

- `Process.output = File of string | Descriptor of Unix.file_descr` and private
  inspectable `Process.t`. `Process.make ~prog ~argv ~cwd ~environment ~stdout
  ~stderr` validates absolute executable/cwd/file paths, nonempty full argv,
  NUL-free strings and unique `KEY=VALUE` environment entries. No shell or PATH
  lookup occurs; argv[0] is independently preserved. Environment is complete,
  not inherited/overlaid. Stdin is `/dev/null`.
- `Process_supervisor.run ?timeout ?term_grace ?cancel ?cleanup process` returns
  `outcome`, optional `pid` / `child_status`, monotonic `elapsed_seconds`, optional
  stdout/stderr paths and optional `cleanup_error`. Outcomes are `Exited of int`,
  `Signaled of int`, `Timed_out`, `Cancelled of int`, `Failed of string`.
  Signal values use OCaml `Sys` / `Unix` representations. `succeeded` requires
  exactly `Exited 0` and no cleanup error. Successful-looking protocol files alone
  cannot override this process outcome.
- File destinations are exclusive new 0600 files, retained on every outcome.
  Identical stdout/stderr paths share a descriptor as a merged log. Borrowed
  descriptors stay open in the caller. Output is streamed directly to descriptors:
  no pipe reader, subprocess capture or unbounded in-memory buffering. Borrowed
  descriptors should be regular files or independently drained streams.
- The installed Spawn interface was inspected: explicit argv/cwd/env/stdin/out/err,
  no PATH resolution, and `Pgid.new_process_group` set in the child before exec.
  The group is owned by the spawned PID; only that positive PID's negative group
  target is signalled, never the caller group. Dependencies are explicit `unix`
  and `spawn` in the execution Dune library and `spawn` in `dune-project` / generated
  opam. Hardware-only dependency direction is preserved.
- A small POSIX C shim uses `CLOCK_MONOTONIC` and `waitid(WNOWAIT)` because the
  inspected standard Unix interface lacks monotonic time and non-reaping exit
  observation. Keeping the leader unreaped pins its PID/group identity through
  final group cleanup, avoiding the reaped-leader/PID-reuse signalling race.
- Timeout sends TERM, waits one grace period, sends KILL and reaps the leader.
  Cancellation forwards SIGINT or SIGTERM to the whole group; SIGINT additionally
  escalates to TERM, then KILL. Normal leader exit also performs TERM/grace/KILL
  cleanup before reaping: leader success does not prove descendant exit. Default
  grace is 0.5 seconds; default timeout is absent. Durations must be finite positive
  values. Polling is 10 ms; cleanup adds its grace to the execution deadline.
- Scoped SIGINT/SIGTERM handlers record the first signal and are restored on
  return, including failures. They are not re-raised or passed to old handlers.
  Signals arriving during final cleanup still produce `Cancelled`, never success.
  Cancellation/IO/spawn callback exceptions become `Failed`; cleanup runs exactly
  once after local termination/reaping, even for launch failures. Cleanup-hook
  exceptions are retained separately and veto success without masking the primary
  failure. Nested use and invalid durations raise before launch/hook invocation.

### Scope and handoff constraints

This is a synchronous POSIX, main-thread-only boundary with exclusive ownership
of process-global signal handlers and child waiting during its scope. It is not
a parallel runner. Children must remain in their owned process group; a transport
must use the cleanup hook for external resources such as a uniquely named container
or processes that escape with setsid/setpgid. The library reaps its direct child;
orphan descendants are killed and subsequently reaped by their OS reaper, not by
turning the calling application into a global subreaper. SIGKILL wait can be delayed
by uninterruptible kernel IO. Arbitrary OCaml hooks cannot be forcibly bounded:
the future container cleanup implementation must supply its own bounded deadline.

The Python baseline was inspected before implementation: `result_store` restores
scoped handlers and preserves interruption; `phase4.run_logged` uses group
TERM/KILL and does not treat client reaping as proof of descendant exit;
`execution_transport.cleanup` targets an owned container name under a separate
deadline. A later OCaml transport should bind this hook to the same owned-name
invariant, account for in-flight container creation, and combine process success
with strict `Backend_protocol` reply/artifact validation before publication.

### Verification

`test/process_supervisor_consumer.ml` is an actual public API consumer.
`test/check_process_supervisor.py` and `process_child_fixture.py` exercise **22 real
disposable launch cases**: exact cwd/environment/argv and independent argv[0],
missing executable/cwd, retained output collision, nonzero and signalled exits,
stdin EOF, concurrent 1 MiB writes on both stdout/stderr in separate/merged/borrowed
descriptor modes, timeout with a TERM-resistant leader or descendant, successful
leader exit with a resistant descendant, real SIGINT and SIGTERM forwarding,
callback cancellation/failure, nested-use rejection, cleanup success/failure on
both successful and failed launches, and interruption in the cleanup hook.
All cases check exactly-once cleanup, borrowed descriptor ownership, returned
path/status evidence, leader reaping and actual restored caller handlers. Private
constructor negatives and invalid-duration cases run in each consumer invocation.
The Linux test harness alone temporarily acts as the subreaper to verify adopted
descendants died by SIGKILL and reap them without leaving disposable zombies.

`--installed` creates a disposable prefix and builds a fresh consumer in an
unrelated directory against only the installed library, checks installed META
dependencies, copies the child fixture outside the checkout and repeats all 22
cases with Python checkout file opens denied. No nested Dune occurs in the alias.

Commands (sequential; every Dune invocation, including installation and fresh
consumer compilation in the installed check, uses `-j20`):

```sh
dune build -j20 @test/process-supervisor @install
dune build -j20 @test/process-supervisor @test/execution-transport @test/result-store @test/backend-protocol @install
python3 -B test/check_process_supervisor.py --installed
git diff --check
```

Results: source-linked and independently installed **22/22** process cases passed;
existing execution-transport suite **45**, result-store **18**, and backend protocol
**50 accepted / 886 rejected**, actual bridge and no-publication checks passed.
`@install` and whitespace checks passed. Accumulated edits and retained physical
evidence were preserved; no Git staging/commit/push/stash/reset or agent spawning
occurred. Next bounded work is transport/runner integration and then authoritative
storage/publication migration, followed by observations/results/CLI ownership.

## Bounded OCaml execution transport (2026-10-13)

Delivered `Hardcaml_asic_execution.Execution_transport` in the existing installed
`hardcaml_asic.execution` library, using `Process_supervisor` for the primary
launch and every Docker removal attempt. This moves the explicit transport
primitive into OCaml; the production Python service still owns its invocations.
There are **no dependency additions** in this slice.

### APIs and preserved semantics

- Private typed `Native` / `Docker` bindings, validating `native` / `docker`
  constructors, and `of_json`, `parse`, `to_json` through `Identity_json`.
  Public parsing is closed schema 1, rejects unknown fields, duplicate keys,
  wrong scalar types, malformed syntax, NUL paths and non-scalar Unicode.
  Optional platform variant and engine daemon/server names preserve absent/null
  distinctions. Python's looser unknown-field acceptance is deliberately not
  reproduced at this new public parser boundary.
- `docker_command` exposes an inspectable argument-array prefix. The bound
  absolute engine executable and exact `sha256:` local image ID are authoritative;
  declared mutable references and repo digests remain evidence. `--pull=never`,
  `--rm`, fresh owned names, RW staged project and RO PDK mounts, explicit container
  workdir, optional PDK environment, and rootless-aware host UID/GID match Python.
  Colon-containing mount paths are rejected rather than misinterpreted by `-v`.
- `native_invocation` preserves the lexical absolute venv interpreter, always
  `-I -B`; `docker_invocation` supports the observed `-I -B` or `-B` interpreter
  flags and explicit non-interpreter entrypoints (e.g. simulator commands).
  Complete supplied environments are sanitized with the Python/Tcl/loader/runtime
  override exclusions from Python. Host cwd is independently explicit; stdin and
  output ownership/retention remain the process primitive's semantics. No shell,
  PATH executable resolution or realpath normalization is introduced.
- Abstract, single-use invocations expose `process_specification` and `container`.
  Reuse is rejected even after launch failure; invalid durations fail before use.
  `run` returns primary `Process_supervisor.result` plus inspectable bounded removal
  attempts and a separate cleanup error; `succeeded` requires both launch and
  cleanup success. Timeout, signal, cancellation and primary errors cannot become
  success because cleanup succeeded, or be masked by a removal failure.

### Owned cleanup and precise bounds

The supervisor rejects nested use. Transport therefore runs cleanup supervisors
after the launch supervisor has terminated/reaped its client and owned process
group, with an outer scoped SIGINT/SIGTERM handler bridging the supervisor scopes.
Signals during removal veto success, and original caller handlers are restored.
Main-launch cancellation does not cancel/skip the removal operations.

Removal uses only `[bound_engine; "rm"; "-f"; owned_name]`, cwd `/`, and the cleared
launch environment. A missing/deleted project or failed output-file creation
does not prevent cleanup. It repeats even after removal/absence, covering daemon
creation that commits after the first observation. The default independent budget
is 5 seconds, each attempt uses at most 1 second and 10ms TERM grace, and retries
wait up to 50ms. No new attempt starts in the final 150ms reserved for engine
startup. Budgets <=150ms report unproved cleanup. Only a nonzero **exited** engine
with Python-compatible absence diagnostics counts as absence; timeout/cancellation
text cannot falsely establish it. Diagnostics retained in memory are capped at
8192 bytes per attempt; command output streams to disposable exclusive temp files.

This is a bounded observation/retry protocol, not atomic daemon cancellation:
success reports the final removal/absence observation, and arbitrarily late daemon
creation after that observation/deadline cannot be ruled out. Uninterruptible
kernel IO has the same POSIX limitation as the underlying process supervisor.
An atomic Docker launch barrier/lease would be a separate future protocol.

### Verification and installed consumer

`test/execution_transport_consumer.ml` links only the public execution library and
Unix. `test/check_execution_transport.py` compares commands, serialized bindings,
and sanitized environments with the actual Python implementation: **34 accepted
differential cases and 105 rejected cases**. Coverage includes both flag policies,
rootless/rootful engines, interpreter/tool entrypoints, optional identity fields,
explicit/default workdir and PDK options, spaces/empty/metacharacter/Unicode argv,
native lexical paths, strict parser additions, wrong types and unknown fields.

`test/fake_docker_engine.py` supplies **18 real disposable engine cases**, including
an escaped daemon that creates a container after an initial removal reported
absence, on both timeout and nonzero client exits. Event evidence requires
absence → creation → later removal for those races.
Other checks cover normal/nonzero/signalled launch, TERM-resistant timeout,
transient removal errors, removal failure on primary success and primary failure,
TERM-resistant removal timeout emitting misleading absence text, missing engine,
retained log collision, missing cwd, real launch SIGINT/SIGTERM, signals during
cleanup, and cancellation callback/failure. All launches check single-use rejection,
duration validation and actual caller signal-handler restoration. The Linux test
harness alone acts as subreaper and kills/reaps disposable escaped fake daemons.
An additional genuine `venv --without-pip` command proves lexical interpreter
selection, cwd/env clearing, argv preservation and isolated Python execution.

The installed mode creates a disposable prefix and builds a fresh consumer in an
unrelated directory against the installed library, copies the fake engine outside
the checkout, and repeats the whole corpus using installed Python helpers with
checkout file opens denied. No nested Dune runs occur in the source alias.

Commands run sequentially, every Dune invocation including installed consumer
builds using `-j20`:

```sh
dune build -j20 @test/ocaml-execution-transport @test/process-supervisor @test/execution-transport @test/backend-protocol @install
python3 -B test/check_execution_transport.py --installed
python3 -B test/test_execution_transport.py
git diff --check
```

Results: source and fresh installed **34 / 105** binding/command corpus, **18** real
engine cases and genuine lexical venv passed. Existing Python transport **45** tests
passed; process supervisor **22** real cases and backend protocol **50 accepted /
886 rejected** with bridge/no-publication checks passed. Installation and whitespace
checks passed. No Docker/EDA smoke or physical flow was needed for this slice.

### Ownership and follow-up

Moved: installed OCaml explicit invocation models, command construction, sanitized
environment transport, supervised launch and bounded owned-container cleanup.
Still delegated: runtime policy/readiness/image and engine re-verification
(`runtime_observation.py` / Python transport, or caller-injected external probes),
backend protocol request/resource copying and pinning (`stages.prepare` and bridge),
reply/artifact validation, storage/checkpoint publication, observations/results and
the public CLI. Transport executes explicit commands only and does not advertise
native stage support: the currently demonstrated six-stage service remains
Docker-only. Future integration must combine its returned process/cleanup evidence
with strict wire/artifact validation before publication, and wire it into one
authoritative runner/writer. The late-daemon-commit limitation remains explicit.
Accumulated changes and previous evidence were preserved; no agents were spawned
and no staging, commit, push, stash or reset occurred.

## Bounded OCaml runtime policy and evidence resolution (2026-10-13)

Delivered `Hardcaml_asic_execution.Runtime_contract` and `.Runtime_evidence` in
the existing installed `hardcaml_asic.execution` library, with no additional
dependencies. The semantic sources are the actual Python `runtime_contract.py`,
the pure validation/evaluation portions of `runtime_observation.py`, and transport
image/server re-verification. All JSON parsing/construction uses `Identity_json`.

### Public APIs and authority

- `Runtime_contract`: private typed contract/source, bundle requested-tools and
  explicit string-valued provisioning-lock parsers, normalized-contract parser
  and serializer, image reference, adopted metadata constants, typed roles/statuses/
  comparisons/evaluation, and pure evaluation with canonical JSON output.
- Missing **runtime_policy alone** selects the explicit legacy contract. Missing
  required Python/LibreLane scalars, null/malformed policy, unknown fields inside
  policy, scalar contradictions, unsupported schema and metadata declarations
  fail closed. Unrelated requested-tools and lock fields remain additive. Locks
  are never consulted as fallback or allowed to replace bundle authority.
- Host Python is exact-minor; legacy container Python is exact-minor. Explicit
  official-image container Python adopts exactly `>=3.10` and unique minors
  3.10–3.14, normalized to the maintained order. Versions preserve the Python
  module's precise grammar, including full patch-level observations. Only valid
  legacy exact-minor mismatches admit an explicitly requested waiver. Malformed
  observations, LibreLane/metadata mismatches and explicit-policy mismatches
  cannot be waived. Native evaluation skips the container.
- `Runtime_evidence`: private typed metadata/Tcl records with retained additive
  raw fields, strict byte parser, observation evaluation (including exact host
  LibreLane and boolean Tcl readiness), container-only applicable subset, and
  inspection of comparisons/issues/waivers and policy satisfaction. Host and
  container LibreLane versions are compared with bundle-requested versions;
  explicit container Requires-Python is compared with the adopted declaration.
- Observations, policy satisfaction and executable binding are distinct. Metadata
  decoding does not establish readiness; Tcl readiness is retained honestly.
  `policy_satisfied` covers only the applicable runtime checks, not bundle/PDK/
  support-tool integrity, overall preflight readiness or successful backend work.
- `binding_from_observation` and `docker_binding` reuse the **existing**
  `Execution_transport.binding` validator. The latter decodes one image inspection
  and Docker info, including local-ID binding, RepoDigests/platform and observed
  engine identity. Missing rootless/server-version readiness fails binding creation.
  No second binding type, Podman runner support or native stage support is added.
- Pure `verify_image` compares supplied fresh output with the exact bound local
  ID (Python-compatible whitespace stripping); a mutable tag or RepoDigest cannot
  substitute. `verify_engine` compares fresh server version/rootless and non-null
  recorded daemon/server names with the bound server. Absent/null optional names
  are not asserted. Requested versions, mutable references and observed identities
  remain distinct evidence; none is substituted for an actual probe result.

The strict codec/transport boundary deliberately also rejects duplicate JSON keys,
nonfinite/overflow values, unsupported Unicode and unknown binding fields that
the older Python decoders leave unconstrained. Inside the supported domain,
normalized policy and full comparison/issue/waiver output match Python exactly.

### Differential and installed verification

`test/runtime_contract_consumer.ml` links the public library and exercises parsing,
serialization, typed metadata access, evaluation, binding extraction, inspection
decoding and image/engine checks. `test/check_runtime_contract.py` compares against
the actual installed/source Python modules rather than a reimplemented oracle.
It uses the existing runtime tests' requested-policy, host/container and image
fixtures and the actual provisioning lock. **2,961 accepted parity cases / 1,253
rejected cases** pass in both source-linked and independently installed consumers.

Coverage includes recursive missing/type/unknown/contradiction mutations of
requested and normalized contracts and locks; legacy vs explicit source; both
execution modes and waiver states; malformed/missing versions and observations;
all supported container minors and unsupported combinations; exact LibreLane and
Requires-Python checks; missing/false/malformed Tcl evidence; container subset;
metadata nullability/additive fields; malformed/duplicate/nonfinite JSON;
native lexical interpreter binding; image inspection and engine readiness; exact
local-ID mismatch and Unicode whitespace; engine rootless/server drift and optional
identity assertions. Docker inspection and re-verification oracles inject only
external probe responses into the real Python functions; no engine/native probe
or importlib/Tcl execution is performed by the differential suite.

Installed mode creates a disposable prefix and builds a fresh consumer in an
unrelated directory against only `hardcaml_asic.execution`, then repeats the corpus
with installed Python modules and copied fixtures. An audit hook denies checkout
reads and LibreLane/tkinter/_tkinter imports. The consumer runs with unusable PATH
and PYTHONPATH, establishing that pure API evaluation performs no runtime lookup.

Commands were sequential; all Dune invocations, including nested installation
and independent consumer compilation, use `-j20`:

```sh
dune build -j20 @test/ocaml-runtime-contract @test/runtime-contract @test/runtime-observation @install
dune build -j20 @test/ocaml-runtime-contract @test/runtime-contract @test/runtime-observation @test/ocaml-execution-transport @install
python3 -B test/check_runtime_contract.py --installed
git diff --check
```

Results: source and installed differential corpus passed; existing Python runtime
contract **8** and runtime observation **10** tests passed; OCaml transport retained
**34 accepted / 105 rejected**, **18** real disposable engine cases and lexical
venv verification. `@install` and whitespace checks passed.

### Handoff / outstanding probe runner

The bounded pure runtime-contract slice is complete. Python still owns isolated
importlib-distribution/headless-Tcl probes, Docker metadata launches and their
carefully restricted metadata-error-only image-packaging retry. This slice never
introduces a broad fallback. A future bounded OCaml probe runner must inject/launch
those external probes through explicit supervised commands, retain observation
and cleanup failures separately, reuse the chosen transport flags, and combine
these pure validators with overall preflight/prepare checks. File reading and
preflight orchestration also remain with their existing owners. No public CLI,
storage/publication, deferred-flow or physical-tool feature was migrated here.
Accumulated changes/evidence were preserved; sole-agent work used no spawning,
compaction, staging, commits, push, stash, reset or other Git mutations.

## Bounded OCaml allocation and atomic records (2026-10-13)

Delivered `Hardcaml_asic_execution.Result_store` in the installed
`hardcaml_asic.execution` library, using existing `Identity_json` and Unix
dependencies. The actual provider `result_store.py` was read before implementation;
the Python service remains its authoritative production caller/writer. This is a
storage primitive, not a preflight/postcheck service, observation journal or
checkpoint publication implementation.

### Public APIs and preserved behavior

- `allocate`: private inspectable allocation (`identity`, `directory`,
  `created_at`), caller-selected root, injectable UTC-seconds clock/UUID factory,
  and positive `max_attempts` (default eight). Defaults use Unix time and
  `/dev/urandom` UUIDv4. Names retain the provider's UTC microsecond timestamp and
  first eight UUID hex digits; full UUID identity is retained separately. UUID
  spelling normalizes like Python `uuid.UUID(str(...))`. Clock values are finite,
  years 1..9999, rounded to microseconds; the injectable clock accepts Unix seconds
  rather than Python timezone-aware datetime objects.
- Root paths resolve symlinks, dangling symlinks and dot components before parent
  creation. Child `mkdir` is exclusive. Only EEXIST retries, with a fresh
  timestamp/identity per attempt. Colliding files, directories and symlinks are
  retained, including unfamiliar runs. Exhaustion and other IO failures propagate;
  there is no adoption, destructive overwrite, deletion or rollback of attempts.
- `record_bytes`, `save_json`, `read_json`: sorted two-space-indented ASCII JSON
  plus newline; same-directory exclusive 0600 temporary; close then atomic rename;
  cleanup on ordinary IO/publication exceptions. Parent must already exist.
  Explicit `save_json` deliberately replaces the caller-selected entry, including
  a symlink itself, never its backend referent. Record reading preserves additive
  fields without imposing a service schema. IO failures propagate; codec failures
  return `Identity_json.error`.
- `validate_output`: absolute lexical explicit-output path, existing writable
  parent, no directory destination, no parent creation or tool probing. As in the
  Python provider, validation is advisory and cannot prevent later IO failure.
- `diagnostic`, `pending_report`, `classify_report`: provenance-preserving pending/
  failure/interruption record construction and the provider's exact minimal
  report check (ready boolean, issues array). Valid reports retain all fields and
  issue elements; readiness classification yields ready/0 or failed/1 without
  substituting policy observations or inferring process success.
- `operation_receipt`, `finish_receipt`, `begin_preflight`: existing schema-1
  `preflight_operation` shape, nullable pending end/exit fields, relative
  `preflight.json` report, full allocation ID and resolved bundle path. Beginning
  validates/resolves the bundle, then exclusively allocates under
  `results_root/operations` and publishes pending `operation.json`. It returns
  allocation/report/receipt paths and the exact receipt; a publication failure
  leaves the reserved attempt in place and does not retry. The optional injected
  save callback has the same publication-error propagation role as Python's.
  Finishing retains additive receipt fields and accepts the caller's actual
  status, exit code, end timestamp and optional error.

### Persisted domain, identity and ownership

The record writer is separate from canonical identity serialization. On the
supported finite domain its pretty bytes match the existing Python writer, rather
than replacing records with compact identity bytes. Identity hashing stays with
`Identity_json.identity`. The provider's broader default JSON allowance for
NaN/Infinity and unpaired surrogates is deliberately outside this new typed
boundary; parsing additionally rejects duplicate keys and malformed/overflow JSON.
LibreLane state containing Infinity must remain opaque backend file bytes and
must not be passed through this reader/writer. No Python writer or retained record
was migrated, and unknown finite backend record fields remain additive.

Atomic replacement establishes complete old-or-new visibility on the tested local
filesystem. There is **no fsync or crash-recovery guarantee**. Caller-selected
roots/outputs and their parents are caller-owned and must not be concurrently
renamed/modified by untrusted writers; this is not a hostile-filesystem sandbox.
Storage creates no signal handlers, runs no process/probe, and fabricates no
process outcomes. Reuse `Process_supervisor`/`Execution_transport` for those.

### Meaningful source and installed verification

`test/result_store_consumer.ml` exercises the exported installed API;
`test/check_result_store.py` uses real disposable files and independent OCaml
processes. Checks cover timestamp/UUID spelling parity, sequential collisions,
full-ID/prefix-name distinctions, exhausted retry budgets, file/symlink collisions,
invalid identity/attempt count, non-directory/unwritable roots, resolved and dangling
symlinks/dot components/loops, and **16 concurrent allocators** contending for the
same deterministic names. Default UUIDv4 identities are also checked.

Record tests compare exact Python `json.dumps(indent=2, sort_keys=True)` bytes,
including Unicode, signed zero, subnormal/scientific floats, large integers and
additive nested fields. The **actual existing `phase4.read_json` reader** reads
OCaml-written records; the OCaml reader also reads actual `result_store.save_json`
output. Pending diagnostics compare to the real provider constructor. Existing
receipt fields, minimal report validation and additive terminal receipt fields
are checked. Backend Infinity files remain byte-identical after rejected reads.

Failure tests exercise directory rename rejection with temporary cleanup,
missing/unwritable parents, noncollision allocation failure without retry,
destination-symlink replacement without referent mutation, and injected receipt
publication failure with retained allocation. Invalid bundle paths fail before
allocation, matching the provider's ordering. **Two simultaneous writers each
perform 100 replacements of distinct 64 KiB records**, while a reader asserts
every observed document is one complete old/new value and no temporary remains.

Installed mode installs a disposable prefix, builds a fresh independent consumer
outside the checkout using only the installed library, then repeats all checks
with installed provider modules and a Python audit hook denying checkout reads.
All Dune invocations were sequential and use `-j20` (including installed builds):

```sh
dune build -j20 @test/ocaml-result-store @test/result-store @test/process-supervisor @test/backend-protocol @install
python3 -B test/check_result_store.py --installed
git diff --check
```

Results: source-linked and freshly installed storage checks pass. Existing Python
result-store alias passes; process supervisor retains **22 real launch cases**;
backend protocol retains **50 accepted / 886 rejected**, actual bridge and
no-publication checks. Installation and whitespace checks pass.

### Integration handoff

A later single authoritative runner should call `begin_preflight` **before probes**,
save `pending_report` to the returned report path, then invoke its policy/probe
owner, classify and persist the exact returned report, and finish/save the receipt
using its actual outcome/time. Publication errors propagate and may leave only a
pending receipt/report, as today; do not invent partial observations. Explicit
output uses `validate_output` then pending/report replacement with no operation
allocation/receipt. Exceptions and scoped interruption conversion remain caller
orchestration work; this module does not duplicate Python `durable_preflight` or
install a competing supervisor. Interrupted signal names/exit codes must come
from that owner, not readiness or a success-looking file. Future result/run owners
must allocate before writing to avoid overwriting unfamiliar runs.

Observation journal semantics, checkpoint publication, postcheck orchestration,
backend-state decoding and public CLI migration remain later slices. Accumulated
edits and physical evidence were preserved; sole-agent work used no spawning,
staging, commit, push, stash or reset.

## Bounded OCaml checkpoint reader and host validator (2026-10-13)

Delivered `Hardcaml_asic_execution.Checkpoint` in the installed
`hardcaml_asic.execution` library, plus the installed native command
`hardcaml-asic-experimental-checkpoint-inspect`. Ancestor `AGENTS.md`, accumulated
progress and the actual Python `checkpoint.py` reader/validator/publisher were
read first. No dependency additions, physical execution or publication ownership
changes were needed. This is a real filesystem reading path; the public Python
`checkpoint-inspect` and publisher remain the production callers.

### APIs and validation domain

- Typed `Schema_1` / `Schema_2`, private file records (SHA-256 and arbitrary decimal
  byte count), and private inspectable checkpoint records carrying identity,
  location, `Flow.Stage` boundary/targets, compatibility, inventories, metrics and
  original finite public JSON. `of_json`, `parse`, `read`, `to_json` preserve the
  original supported manifest data. Parsing checks exact fields, declared
  capabilities and unsigned canonical identity; filesystem validation is separate.
- `file_record` streams opaque bytes through SHA-256 and checks a regular file;
  `absolute_path` returns checked lexical absolute paths without resolving away
  the checkpoint's recorded location. Public helpers return string errors.
- `validate ~compatibility ?restart ?restart_to ?check_external ?location path`
  checks the actual caller compatibility, exact recorded location, complete file
  inventory and bytes, required boundary views, nested/list/corner view paths,
  declared closure equality, public metric availability/finite numeric evidence,
  and host closure. The explicit location override matches Python's private
  candidate/final-location check; it is not relocation support for retained data.
- Schema 1 accepts only synthesis/floorplan/placement; only synthesis has its
  historical floorplan/placement restart targets. Schema 2 uses maintained
  `Flow.Stage.capability` for all six boundaries, exact target lists, exact tested
  image and path-bound closure. Schema 2 requires the exact image in the caller
  compatibility binding even without a restart request. Signoff remains terminal;
  all successful manifests retain `not_evaluated` acceptance.
- Compatibility compares actual values like Python, including finite numeric
  equality across integer/float/bool evidence. It is not replaced by a fabricated
  compatibility identity. Manifest hashing still preserves all type-significant
  canonical bytes. Recorded compatibility inspection does not compare historical
  bridge bytes to the current installed adapter or imply current restart readiness.
- Public metadata uses `Identity_json` / `Result_store.read_json`, with strict
  duplicate-key, Unicode, schema-type and finite-number checks. Native state is
  hashed verbatim and never canonicalized, written or returned as identity JSON.
  A private read-only syntax projection permits native Infinity, -Infinity, NaN
  and exponent overflow while checking only view leaves and the metrics-object
  container. It is not a native state serializer. The projection retains the
  codec's depth/Unicode/duplicate-key restrictions; permissive malformed native
  data is not promoted into the typed boundary.
- All internal file/directory symlinks, including manifest and dangling links,
  fail the closed inventory walk. This is an explicit conservative tightening
  over the old Python `is_file` walk, which can ignore dangling/directory links
  and accept a manifest symlink. Host external-file symlink following is preserved.
  As with existing storage primitives, parents/files must remain stable during
  validation; no hostile-concurrent-writer or crash-durability guarantee is added.
- `/nix/store/` records remain declared image-only evidence. Host inspection never
  verifies them, imports LibreLane, launches an engine/bridge or infers acceptance.
  Runtime/image closure validation stays with the existing protocol service.

### Installed inspection semantics

```sh
hardcaml-asic-experimental-checkpoint-inspect CHECKPOINT
hardcaml-asic-experimental-checkpoint-inspect --json CHECKPOINT
hardcaml-asic-experimental-checkpoint-inspect --compatibility expected.json --restart-to placement CHECKPOINT
hardcaml-asic-experimental-checkpoint-inspect --help
```

Success exits 0. JSON has precisely the existing `validation: host_only`,
`runtime_closure_validated: false`, `compatibility_source: recorded|expected`, and
complete `manifest` envelope; serialization uses canonical JSON plus newline.
The human view preserves existing headings/fields, supported/requested targets,
inventory counts, accumulated-metric distinction and acceptance limitation.
Validation/IO/argument failures exit 2 and write a stderr diagnostic. With `--json`
they emit a `validation: host_only` / `error` envelope and no success manifest.
Human errors state that no successful inspection/readiness conclusion is available.
Help exits 0. The explicitly experimental name leaves public CLI migration for a
later dispatch.

### Verification and retained real evidence

`test/checkpoint_consumer.ml` is an independently linkable public API consumer.
`test/check_checkpoints.py` compares results with **actual Python
`checkpoint.validate`**, and compares successful human output byte-for-byte with
`presentation.checkpoint`. It exercises schema 1/2 and every source/target pair,
restart-required terminal/historical cases, malformed schemas and field sets,
corrupt/re-signed identities and locations, compatibility/image mismatches,
bad/missing/extra inventories, malformed record types/digests/sizes, corrupt or
missing files, internal and external symlink behavior, closure mismatch/host
changes, public metric types, strict public JSON, native nonfinite metrics,
invalid/missing/escaping/uninventoried views, nested corners, lexical dot/slash
paths, private candidate location checks, and help/argument/error envelopes.

Both retained fixture generations are inspected **in their original locations**:

- Five checkpoints below
  `/tmp/opencode/backend-v1-integration/results/signoff-1126383-2667d2be2e991b4119b0b8853a4e75da/checkpoints/`.
- Seven older checkpoints below `/tmp/opencode/librelane-slice4-production/checkpoints/`,
  including signoff and both CTS publications.

All twelve pass host-only validation with their own recorded compatibility;
unsupported transitions and altered expected compatibility fail. Retained data
is read-only, never copied/repaired/re-signed/upgraded; manifest digests are checked
unchanged. Corruption and candidate-location tests use separate disposable data.
The explicit `@test/ocaml-checkpoints` alias requires these retained fixture trees
and is not attached to general `runtest`.

Installed mode installs a disposable prefix, builds a fresh consumer outside the
checkout against only `hardcaml_asic.execution`, and reruns the same corpus using
installed Python resources and the installed native CLI. Its audit hook denies
checkout reads and LibreLane/bridge imports. Native consumers/inspectors execute
with unusable PATH/PYTHONPATH; no physical tool lookup is required.

Commands run sequentially; every Dune invocation (including installation and the
independent consumer build inside installed mode) uses `-j20`:

```sh
dune build -j20 @test/ocaml-checkpoints @test/stage-checkpoint @test/ocaml-result-store @test/backend-protocol @install
python3 -B test/check_checkpoints.py --installed
git diff --check
```

Results: **67 accepted / 199 rejected** Python-validation parity cases pass in
both source-linked and fresh installed checks; **12 retained real checkpoints**,
API round-trips/file hashing, exact successful human/JSON output, strict symlink
checks and CLI errors/help also pass. Existing storage, stage/checkpoint and
backend-protocol aliases pass; backend protocol retains **50 accepted / 886
rejected** plus actual bridge/no-publication checks. Installation and whitespace
checks pass. No physical runtime/image validation was run in this dispatch.

### Exact publisher dependencies for the next dispatch

The reader/host-validator slice is complete. A future publisher still needs:

1. **One authoritative caller and completed-execution evidence.** Preserve the
   adapter's remembered completed request, successful actual process outcome,
   strict correlated `completed` reply and artifact verification, outer segment
   status/boundary/bridge checks, and transported bridge/protocol rechecks before
   publication. A success-looking `segment.json` is insufficient.
2. **Private staging and native view-copy serialization.** Allocate a fresh
   `.publishing-*` directory inside a caller-selected existing store, derive the
   fresh final boundary name, recursively copy official state view leaves into
   unique numbered `views/` files, and bind rewritten paths to that final name.
   Preserve native metric serialization including Infinity; neither Identity_json
   nor this private read-only projection is a native writer. That writer/copy
   traversal remains to be implemented or supplied by the native-state service.
   Recheck source/destination hashes for each copy and copy resolved/closure/segment
   metadata without inventing new evidence. `Checkpoint.file_record` is reusable.
3. **Manifest construction and host pre-promotion validation.** Construct the
   unchanged schema-2 manifest from actual files/closure/segment metrics and the
   maintained capabilities, sign the unsigned Identity_json object, write its
   canonical bytes, then call `Checkpoint.validate ~location:final` on staging
   with the actual expected compatibility. This reader exposes no ready-publication
   or completion claim.
4. **Explicit runtime/image-only validation.** If any image-only closure exists,
   require the protocol service's `validate_publication` operation through the
   chosen supervised transport. Require successful process outcome, correlated
   `validated` reply and artifact hashes; re-run host validation afterwards to
   reject mutation. The host inspector does not supply or simulate this callback.
5. **Owned atomic promotion, permissions and failure cleanup.** Set files 0444
   and directories 0555, reject existing/symlink destinations, atomically rename
   private staging, and preserve the current exception/interruption cleanup rules
   for only this attempt's owned paths. No overwrite, caching, relocation or
   fsync promise is implied. Return the existing publication summary only after
   promotion; advance the adapter's current checkpoint only on that success.

These are publisher/orchestration dependencies, not missing host-reader features.
Public CLI/runner replacement and finalization/acceptance remain later work.
Accumulated work/evidence was preserved; this sole-agent dispatch used no spawning,
staging, commit, push, stash or reset.

## Bounded OCaml checkpoint publisher (2026-10-13)

Delivered `Hardcaml_asic_execution.Checkpoint_publisher` and `Backend_state` in
the installed `hardcaml_asic.execution` library. Ancestor instructions, latest
checkpoint handoff, actual Python publisher/adapter and existing OCaml validator
were read before implementation. This is the candidate-to-immutable-publication
primitive; the Python production runner/CLI remains the authoritative caller.
No dependency additions or physical EDA execution were required.

### API and publication contract

- `publish ~candidate ~store ~compatibility ~boundary ?name ?validate_runtime ()`
  returns a private publication record only after promotion, with final `path`,
  validated `Checkpoint.t`, and explicit `Not_required`/`Validated` runtime status.
  `to_json` returns the existing Python publication reference format, without
  adding fields to persisted manifests or lifecycle records.
- `.mli` explicitly requires upstream remembered request, successful actual
  supervised process/cleanup, strict correlated protocol-v1 completed reply,
  reverified candidate artifact bytes, and transported bridge/support rechecks.
  This publisher does not authenticate execution from success-looking files.
  It checks outer completed status, boundary and compatibility bridge equality;
  all metadata/views/closure/public metrics are then checked before publication.
  Manifested checkpoint directories, including schema 1, are rejected as candidate
  inputs; there is no old-checkpoint restart or upgrade path in this API.
- Fresh 0700 `.publishing-*` staging under an existing store, exclusive 0600 file
  writes, streaming numbered copies of **every** nested/list/corner view leaf,
  final-location rewritten paths, and pre/post source stat/hash and destination
  checks. Original candidate metadata is copied without fabricating new evidence;
  candidate metadata and all source views are rechecked after runtime validation.
- Unchanged schema-2 manifest, maintained exact image/restart targets/path-bound
  scope and `not_evaluated` acceptance, canonical unsigned identity signature,
  actual `Checkpoint.validate ~location:final ~compatibility staging`, then runtime
  validation if `/nix/store/` closure exists. The callback takes private staging,
  intended location, boundary and compatibility. Its `Validated`, `Failed string`
  and `Interrupted signal` outcomes are explicit. Required callback evidence is
  successful exact-image supervised validation, fresh correlated validated reply
  and matching artifacts; host validation never supplies that evidence itself.
- Repeated host validation, exact original signed-manifest comparison (including
  rejection of callback mutation followed by re-signing), and source checks after
  callback and again after files/directories become 0444/0555. Atomic Linux
  `renameat2(RENAME_NOREPLACE)` promotion has no check-then-rename fallback.
  Existing empty directories, files and symlinks are never overwritten/adopted.
- Structured publication/runtime/interruption errors preserve primary diagnostics;
  owned-cleanup errors are attached separately. Callback exceptions retain their
  exception/backtrace after cleanup; simultaneous exception/cleanup failure exposes
  both via `Cleanup_error`. Only this attempt's staging is removed; collision
  entries and published checkpoints are never cleaned as rollback targets.

### Native State semantics

`Backend_state` is an explicit bounded native-state codec, not identity JSON.
It validates native structure with a syntax-only projection, traverses only view
leaves and retains the entire original metrics-object slice verbatim. Serialization
rewrites view strings while preserving metric token spelling/precision, Infinity,
-Infinity, NaN, exponent overflow, signed zero, big integers, strings and nested
metrics. Native nonfinite tokens are masked only in the throwaway syntax projection;
they are never passed to Identity_json as nonfinite numbers or serialized from
that projection. Strict duplicate-key/Unicode/depth restrictions match the reader.
No backend engine/state implementation was edited.

Real local LibreLane **3.1.0.dev3** `State.dumps -> publisher -> State.loads/validate`
passes for Decimal positive/negative Infinity, float NaN, finite Decimal, signed
zero, large integers, nested metrics and real registered ODB/DEF/library views.
The test imports native OpenROAD format registration but runs no step or tool.
This is native API compatibility, not exact-image runtime validation/readiness.

### Verification

`test/checkpoint_publisher_consumer.ml` is an independently installed public API
consumer. `check_checkpoint_publisher.py` passes **51 checks** source-linked and
freshly installed: all six boundaries/reference formats, actual previous Python
writer into the new reader and new writer into both actual readers, native metric
bytes, required callback, explicit failure/interruption and exception preservation,
cleanup-error preservation, staged/source/metadata/host/manifest/empty-directory mutation vetoes,
large regular-file mutation during streaming/hash passes, missing/invalid inputs,
exact-image rejection, schema-1 candidate rejection, collision entry preservation,
and **12 concurrent publishers** contending for deterministic staging/final names.
Empty-directory, file and symlink destinations created during validation veto
atomic promotion without modifying those entries. No readiness precedes promotion.

Installed mode builds fresh consumers outside the checkout against only the
installed library and runs the compatibility/failure corpus using installed Python
resources with checkout reads and backend imports denied. The separate optional
native-State test uses the explicit local native interpreter and an independently
installed OCaml publisher; it imports no provider Python resources.

Commands were sequential; every Dune invocation, including nested installation
and independent consumer compilation, uses `-j20`:

```sh
dune build -j20 @test/ocaml-checkpoint-publisher @test/ocaml-checkpoints @test/stage-checkpoint @test/ocaml-result-store @test/backend-protocol @install
python3 -B test/check_checkpoint_publisher.py --consumer _build/default/test/checkpoint_publisher_consumer.exe --reader _build/default/test/checkpoint_consumer.exe --native-python .toolchain/.venv/bin/python
python3 -B test/check_checkpoint_publisher.py --installed --native-python .toolchain/.venv/bin/python
python3 -B test/check_checkpoints.py --installed
git diff --check
```

Reader regression retains **67 accepted / 199 rejected** cases and **12 retained
real checkpoints**, in original locations with unchanged manifest digests, in
both source and installed checks. Existing stage/checkpoint, OCaml result-store
and backend-protocol aliases pass; protocol retains **50 accepted / 886 rejected**
plus bridge/no-publication checks. Installation and whitespace checks pass.

### Limits and next required inputs

Atomic no-clobber visibility is exercised on the local Linux filesystem. There
is **no fsync, power-loss durability or crash-recovery promise**. Unsupported
no-replace promotion fails closed. Parents must remain stable and caller-owned;
this is not a hostile-filesystem sandbox, and readonly permissions do not restrain
the owner. The library installs no signal handlers: caller-owned interruption
exceptions/outcomes trigger owned cleanup, while SIGKILL/default process termination
can leave private staging. A process interrupted at/after atomic promotion may
leave a complete final checkpoint without returning a publication to its caller.
No readiness is inferred from residual directories; recovery/lifecycle ownership
belongs to the future runner.

The next bounded integration needs one authoritative OCaml runner with explicit
candidate/request/process/reply/resource evidence and chosen native/Docker binding,
plus an actual supervised exact-image `validate_publication` callback and its
request/reply/log retention locations. It must advance its current checkpoint and
lifecycle publication record only from `Ok`, preserve explicit failed/interrupted
outcomes and cleanup errors, and use fresh candidates/workspaces for changed bridge
compatibility. Public CLI migration, runtime probing, completed six-stage execution
with adequate signoff budget, finalization and acceptance remain subsequent gates.
All accumulated changes and physical evidence were preserved. Sole-agent work
used no spawning, staging, commit, push, stash or reset.

## Bounded typed sequential runner (2026-10-13)

Delivered `Hardcaml_asic_execution.Runner` in the installed
`hardcaml_asic.execution` library. Ancestor instructions, accumulated progress,
actual Python `runner.py`, stage adapter, plans and existing storage/publisher
interfaces were inspected first. This is generic synchronous orchestration of
the existing checked five-action coarse plans and six-boundary stage plans.
Production Python callers remain authoritative. No dependencies were added.

### Typed API and lifecycle semantics

- `execute ~attempt_id plan callbacks` takes separately injected `validate`,
  `invoke` and `publish` callbacks. Payload parameters `'run`, `'segment` and
  `'checkpoint` are actual caller-selected OCaml types, allowing forthcoming
  service records containing remembered requests, process/reply/artifact/resource
  evidence rather than opaque JSON or string handles. Typed `context` carries
  occurrence ID, best-effort flag, available run and current checkpoint source.
- `Run_result`, `Segment_result`, `Service_result`, `Archive_result` must match
  the action operation. A completion carries typed status, actual exit code and
  optional explicit error. Successful completions cannot carry failure evidence;
  interruption/code/signal contracts are checked. An allocated failed run can
  return both its identity and structured process/cleanup error, permitting
  collection without masking the original failure. Report rejection remains
  a completed occurrence with `verdict=rejected` and overall `status=rejected`.
- Typed `Failure` / `Cancellation` diagnostics preserve actual code, message and
  secondary cleanup messages. Positive POSIX signal numbers are required;
  translate OCaml `Sys`/`Unix` signal representations in the service owner.
  Returned errors and `Callback_error` are explicit; ordinary callback exceptions
  become failure/2 facts. First non-best-effort failure wins, with subsequent
  errors retained in `secondary`. A run callback exception before returning an
  allocated run now returns a failed execution instead of Python's propagation;
  there is no fabricated run or collection target.
- Ordered actions, stable `attempt_id/action.key` IDs, disabled `skipped` and
  blocked `unreached` occurrences follow the Python contracts. After a failed or
  interrupted service, collection remains best effort if a run was returned,
  including Python's interrupted-run/postcheck behavior. An explicit cancellation
  poll vetoes all later actions, including collection. Polls occur before enabled
  actions and after invocation/publication; in-flight service cancellation belongs
  to its supervised process/publication owner. No competing signal handlers exist.
- Schema-2 resumed source is synthesis; schema-3 source is its actual explicit
  `initial_boundary`. Presence and boundary must match before callbacks execute;
  the service's `validate` still owns actual compatibility and restart checks.
  The current source advances only on successful publication. Labels never affect
  identity or ordering. No dependency graph or new scheduling capability is added.
- `Started` precedes invocation; `Published` is emitted only after the separate
  publisher callback returns evidence; `Finished` follows publication. Published
  hooks see the occurrence still running, as in Python. Finished hooks run even
  after started/invoke/publication failures. A promoted artifact is retained if a
  later hook, cancellation poll or save fails; there is no rollback or retry.
  `observe` receives only returned postcheck outcomes. No LibreLane fine-step
  events, readiness, acceptance or execution evidence are fabricated.
- The default clock reuses the existing monotonic C primitive. Injected clocks
  must be finite/nondecreasing; elapsed arithmetic is checked. Six-decimal rounding
  uses exact binary rational arithmetic with decimal ties-to-even and matches
  Python `round(duration, 6)`, including midpoint neighbors and extreme floats.

### Record compatibility decision

`to_json ~run_json` retains the existing finite `Execution.as_dict` summary:
attempt ID, unchanged plan schema 1/2/3, occurrences, status, code, optional actual
run, archive and publication references. Skipped/unreached zero duration retains
Python's integer `0`; completed durations are floats. `reference_json` matches
the publisher's existing reference fields, including exact tested image and
`not_evaluated` acceptance. **No execution-summary schema version or checkpoint
manifest changes were introduced.** `steps_json` exposes the existing separate
step-list format.

There are explicit orchestration extensions: early snapshots use overall
`status=running` rather than Python's in-memory premature `completed`; callback
failures are returned as execution facts; successful publications survive later
hook failures. The legacy summary cannot fully encode storage/hook and secondary
errors. `diagnostics_json` therefore uses a **separate explicit schema version 1**
envelope, `kind=runner_diagnostics`, with attempt ID, nullable primary and ordered
secondary diagnostics (action key, lifecycle point, kind, signal, code, error and
cleanup messages). This is an additive separate record, not a silent modification
of retained execution JSON. Callers select its path and persistence policy.

`persist` receives immutable snapshots before invocation, after each lifecycle
transition and at terminal status. Use `Result_store.save_json` for the existing
sorted/indented/newline record bytes. An initial save failure prevents execution;
subsequent save failures are explicit primary/secondary facts. A failed terminal
save cannot guarantee a terminal filesystem record: the returned execution and
diagnostics are authoritative, and the earlier on-disk snapshot may remain
running. No automatic retry, fsync/crash recovery or adoption of existing work is
claimed. Caller-selected paths and payloads remain caller-owned.

### Verification

`test/runner_consumer.ml` is a real linked public consumer; `check_runner.py`
passes **628 scenarios** in source-linked and independently installed modes.
Differential cases use actual Python `runner._execute` for all coarse endpoints/
archive choices and fresh/resumed schema-2 and contiguous schema-3 ranges:
successful results, each enabled action's nonzero result, ordinary invocation/
publication errors, interrupted run/postcheck outcomes, failed collection and
primary-versus-secondary failure precedence. Summaries, steps and real filesystem
record bytes match Python on this domain.

Additional fixtures exercise every action's started/invoke/finished hooks,
every segment's publish/published hooks, postcheck observation, validation,
returned errors, ordinary exceptions and explicit interruption; each persistence
transition, cancellation poll and clock call; invalid result/completion contracts,
wrong publication boundary, missing/mismatched initial source, empty diagnostics,
actual failed IO with retained user data/temporary cleanup, invalid IDs, immutable
initial snapshots and exact duration rounding. Publication fixture files exist
before `Published`, which precedes `Finished`; subsequent contexts use only the
published source. These synthetic attestations test orchestration, not checkpoint
authentication or physical execution. Existing actual publisher regressions test
the filesystem publication primitive separately.

Installed mode installs a disposable prefix, builds a fresh consumer outside the
checkout against only the installed library, and reruns the corpus using installed
Python semantics with checkout file reads denied. All Dune commands were sequential
and `-j20`, including the installed script's install and independent build:

```sh
dune build -j20 @test/ocaml-runner @test/execution-plans @test/ocaml-result-store @test/ocaml-checkpoint-publisher @test/backend-protocol @test/stage-checkpoint @test/default-journal @test/flow-observation @install
dune build -j20 @test/ocaml-runner @install
python3 -B test/check_runner.py --installed
python3 -B test/test_installed_prefix.py
git diff --check
```

Source and installed runner suites pass. Regressions pass: plans **164 accepted /
4,900 rejected**, actual checkpoint publisher **51 checks**, result-store filesystem
checks, protocol **50 accepted / 886 rejected** plus isolated bridge/no-publication
checks, stage/checkpoint and observation aliases. Installed-prefix suite retains
**57 passing tests**. `@install` and whitespace checks pass. Runner checks are also
attached to `runtest`; installed checks remain explicit to avoid nested Dune.

### Stage integration handoff

1. Instantiate `'segment` as the forthcoming service's completed-candidate record
   with actual request, successful supervised process/cleanup, strict correlated
   reply, verified artifacts and transported-resource digests. Return
   `Segment_result (candidate, {status=Completed; exit_code=0; error=None})` only
   after those checks. Failed/interrupted callbacks return explicit errors; no
   publisher is called for unsuccessful execution.
2. Instantiate `'checkpoint` as a real validated checkpoint/handoff record.
   Supply `initial={boundary; checkpoint}` for resumption. `validate` must check
   actual compatibility, path binding and first restart target. Use the supplied
   `context.source` for each segment; do not maintain a competing advance before
   publication.
3. In `publish`, reverify remembered completion/resources, invoke the actual
   `Checkpoint_publisher.publish` with the exact-image supervised runtime
   validation callback, and map structured runtime/interruption/cleanup errors to
   runner errors. On `Ok p`, return
   `{evidence=Runner.of_checkpoint_publication p; checkpoint=<typed handoff>}`.
   The runner's `reference` constructor is syntax validation only, not authority
   to infer publication from a directory.
4. Persist summaries with `Runner.to_json`/`Result_store.save_json` at a fresh
   caller-owned execution path. Persist `Runner.diagnostics_json` separately when
   detailed hook/storage/cleanup evidence is needed. Keep terminal save failures
   visible at the command boundary. Connect coarse lifecycle hooks to the future
   observation owner; finer backend observation needs actual backend evidence.

Production Segment_service/runtime/publication composition and full CLI ownership
remain the next bounded slice. Accumulated changes and retained physical evidence
were preserved; sole-agent work used no spawning, staging, commit, push, stash or
reset.

## Authoritative bounded OCaml prepared-path segment service (2026-10-13)

Delivered `Hardcaml_asic_execution.Segment_service` and `Segment_report` in the
installed `hardcaml_asic.execution` library, plus the installed executable
`hardcaml-asic-experimental-segment-execute`. Ancestor instructions, accumulated
progress, current execution interfaces, Python `SegmentAdapter`, wire protocol and
bridge/lifecycle implementation were read first. This is actual execution and
publication composition over **caller-PREPARED** paths. No new dependencies were
added. Sole-agent work preserved prior edits and retained physical evidence.

### Exact ownership

For invocations of this OCaml service:

- `Runner` remains the only sequential action/lifecycle owner. Its typed
  `context.source` selects each continuation checkpoint; it advances only from
  the successful publication callback. The service has no competing provider
  scheduler or mutable current-checkpoint advance.
- `Segment_service` owns validation/invoke/publish callbacks, fresh segment and
  validation requests, remembered actual completion evidence, and the selected
  runtime publication-validation call. Its abstract service and private segment
  record prevent callers from manufacturing completed execution attestations.
- `Execution_transport.run` / `Process_supervisor` own actual launches, process
  groups, timeouts, cancellation and owned-container cleanup. Nonzero exits,
  signals, timeout and cancellation win over success-looking replies. Primary
  exit codes (including 17, signal 141, timeout 124 and cancellation 143 in tests)
  survive cleanup/publication failures; secondary cleanup evidence is preserved.
  Publisher exception-plus-cleanup errors retain the primary Runner error.
- `Backend_protocol` owns strict v1 request/reply schema and full correlation.
  The service additionally checks regular-file artifact bytes and SHA-256,
  operation-specific success and the typed outer report. Publication rechecks the
  **remembered reply**, rejecting even a freshly re-signed/rewritten artifact reply
  after candidate mutation. Resources are checked before and after successful
  launches and again before publication.
- `Checkpoint_publisher` is the only checkpoint writer for these calls. It owns
  private staging, native view rewriting/copying, host closure/metric checks,
  schema-2 signing, permissions and atomic no-replace promotion. When image-only
  closure requires its callback, the service executes `validate_publication` in
  the selected runtime, with a fresh correlated validated reply and verified
  artifact evidence. Only then can the publisher promote. Host-only closure keeps
  the existing Python `Not_required` semantics; it does not fabricate runtime
  validation. No checkpoint readiness is inferred from retained candidate files.
- The existing Python production CLI, preparation/probes and observation service
  continue owning their own invocations. This slice supplies an actual installed
  OCaml execution path, not a replacement claim for those public callers.

### Prepared contract and ready-to-use APIs

`Segment_service.create ~binding ~workspace ~project ~pdk_root ~checkpoint_store
~compatibility ~environment ~timeout ?initial_checkpoint ()` returns the abstract
service or a structured `Runner.error`. Production requires a checked Docker
binding with the maintained exact tested image. The existing seven compatibility
fields are closed: `bundle_identity`, `target`, `requested_tools`, `binding`,
`bridge_sha256`, `project`, `pdk_root`. Selected binding and compatibility binding
must agree, including observed optional fields. Compatibility must bind the exact
project, PDK and compiled bridge hash. The two pins are:

- Bridge: `e8dc9532c61010ae8699d3a6f27cdfd0d773ff3e24d06f9eefbe2d0f5b2da841`.
- Protocol support: `732c05a5009f0510ec2624f7ddc03e86bb2a20cf824a9bb9c96d947bc0f2e49d`.

The service pins/checks both transported regular files. Exact bridge bytes also
bind its literal `PROTOCOL_SHA256`; the installed-resource tests exercise that
same bridge and support. A future bridge/support change must deliberately update
these OCaml pins alongside the bridge's support pin and fresh compatibility.
Historical evidence is not rewritten or upgraded.

Workspace, project, PDK, store, `project/bridge` and `project/candidates` must
already exist as canonical absolute directories without symlink aliases. Project
and store are disjoint descendants of the explicitly mounted workspace; the PDK
is outside that workspace. Initial and subsequent source checkpoints must belong
to the selected store. Initial checkpoint compatibility, complete inventory,
identity, boundary and first supported restart target are checked before work;
each continuation revalidates the real source and remembered identity. Coarse
plans, mismatched initial handoffs and unsupported transitions fail before backend
work. Complete environment and finite positive timeout are validated up front;
Docker mount syntax is checked without probing. Parent paths remain trusted,
stable and exclusively caller-owned, as required by the underlying primitives.

The actual APIs are immediately usable by a prepared-path consumer:

```ocaml
(* binding, compatibility, paths and complete environment are caller-prepared. *)
let service =
  match Segment_service.create ~binding ~workspace ~project ~pdk_root
    ~checkpoint_store ~compatibility ~environment ~timeout ?initial_checkpoint () with
  | Ok service -> service
  | Error error -> raise (Runner.Callback_error error)
in
let result =
  Segment_service.execute ~attempt_id plan service
in
Result_store.save_json summary_path
  (Runner.to_json ~run_json:(fun () -> Identity_json.null) result);
Result_store.save_json diagnostics_path (Runner.diagnostics_json result)
```

`callbacks service` exposes the actual `(unit, segment, checkpoint)
Runner callbacks for consumers needing existing Runner persistence/cancellation/
lifecycle hooks. `initial service` supplies the validated typed initial source.
`execute ?persist ?lifecycle` is convenience composition with the same Runner,
not a second scheduler. Checkpoint payloads contain real path and `Checkpoint.t`;
completed segment payloads contain actual request, transport/process result,
strict reply and typed report. Sources advance only on publisher success.

Requests/replies are retained in project as `TAG-request.json` and
`TAG-reply.json`; merged exclusive logs are retained in workspace as `TAG.log`.
Tags retain `BOUNDARY-32hex` / `validate-BOUNDARY-32hex`. Requests are canonical
v1 JSON plus newline, exclusively created. Successful `segment.json` retains the
current production bridge format. `Segment_report.of_json ~request` uses closed
fields, actual boundary/source/from/to/endpoint-step correlation, the current
metric-origin/gate/acceptance strings and configured-gate objects. Metrics expose
typed `Available of Identity_json.t` (finite numeric only) or `Unavailable` with
the bridge's exact reason/raw-string fields. Native `state.json`, including
Infinity, remains opaque execution evidence; publisher `Backend_state` alone
handles view-path rewriting while retaining native metric bytes.

The installed harness runs on caller-prepared paths:

```sh
hardcaml-asic-experimental-segment-execute prepared.json
hardcaml-asic-experimental-segment-execute --help
```

Its closed configuration fields are `workspace`, `project`, `pdk_root`,
`checkpoint_store`, `compatibility`, `binding`, `environment` (complete
`KEY=VALUE` string array), `timeout`, `initial_checkpoint` (path or null),
`attempt_id`, `plan` (existing schema 2/3), `summary_path`, `diagnostics_path`.
It reserves both caller-selected record paths exclusively, persists actual Runner
snapshots with `Result_store`, emits the unchanged execution-summary JSON on stdout,
and returns the actual execution exit code. Detailed errors persist separately as
the existing version-1 Runner diagnostics envelope. Invalid configuration/output
ownership exits 2 on stderr. Existing output paths are not adopted or overwritten;
if reserving the second record fails, the first fresh reservation remains owned
attempt evidence. There is no automatic retry or crash-recovery adoption.

### Fixture-backed verification and installed execution

`test/segment_service_consumer.ml` independently consumes the installed API.
`check_segment_service.py` passes **65 checks** in source-linked and freshly
installed modes. The real transported bridge runs under isolated Python with
only native LibreLane APIs replaced by `bridge_protocol_fixture.py`. It executes
the actual OCaml transport/supervisor/service/runner/publisher chain, not synthetic
Runner completion references. Native state Infinity remains present after publication.

Coverage includes fresh synthesis, all six sequential boundaries and exact source
advances, schema-2/3 resumption, initial source identity/boundary mismatch and
mutation, incompatible runtime/image/compatibility/resources, duplicate environment,
explicit path/store/symlink constraints, coarse/missing-handoff rejection, missing/
malformed/duplicate-key/wrong-version/miscorrelated/failed/extra-field replies,
wrong artifact hashes/bytes and mutation, closed report/step/source/metric checks,
process nonzero/signals/timeout/actual cancellation overriding completion files,
callback exceptions, host closure mutation, publication IO failure, and remembered
candidate/reply/resource mutation. Published checkpoints survive later hook failure.

Image-only validation uses an existing read-only regular `/nix/store/` fixture
dependency in the native API's typed configuration; the production bridge builds
and compares its real closure. No Nix/EDA flow is launched. Validation nonzero,
timeout, cancellation, missing/miscorrelated reply, configuration mismatch and
staged artifact/manifest mutation veto publication and clean only owned staging.
Successful validation evidence is checked against the promoted metadata bytes.

`Testing.create_native_fixture` is explicitly fixture-only: it invokes
`interpreter -I -B fixture bridge request` through actual transport/supervision.
It is not advertised native physical-stage support or runtime readiness. Production
`create` rejects native bindings. There is no public arbitrary launcher that can
return an invented success outcome.

The installed executable is also exercised through its **production Docker path**
using a disposable fixture engine. It constructs the exact-image mounted commands,
runs execution plus the distinct publication-validation operation, and performs
owned-name cleanup for both. Cleanup failure vetoes zero-exit success and preserves
a nonzero primary exit. This engine is fixture transport, not an observed real Docker
runtime. Fresh independent consumers and installed bridge/support resources run
outside the checkout; the Python verifier denies checkout file opens. This is
installed linkage/resource verification, not a kernel filesystem sandbox.

Commands were sequential; every Dune invocation, including nested installation
and fresh independent consumer compilation, uses `-j20`:

```sh
dune build -j20 @test/ocaml-segment-service @test/ocaml-runner @test/ocaml-checkpoint-publisher @test/backend-protocol @test/stage-checkpoint @test/process-supervisor @test/ocaml-execution-transport @install
python3 -B test/check_segment_service.py --installed
git diff --check
```

Results: service **65/65 source and installed checks**; Runner **628**; publisher
**51** including native metrics and concurrent no-clobber publication; protocol
**50 accepted / 886 rejected** plus actual bridge/no-publication checks; supervisor
**22** real launch cases; transport **34** differential cases, **105** negatives
and **18** real fixture-engine cases; stage/checkpoint regression, installation
and whitespace checks passed. The service alias is explicit: its image-only fixture
requires the existing readable `/nix/store` tree. No heavy physical flow ran.

### Next preparation/runtime handoff

The next bounded slice can directly call this service; its required inputs are now
concrete. Preparation must allocate a fresh caller-owned workspace/store and record
paths, validate bundle/runtime policy, execute and persist actual readiness/engine/
image probes, stage project/config/support references, create `project/bridge` and
`project/candidates`, copy the pinned installed resources, and construct the existing
compatibility plus selected binding/environment/timeout. Resumption must retain the
path-bound project/PDK/store and supply the actual initial checkpoint. The service
does not choose these paths, install tools, copy a bundle or supply probe evidence.

That next slice must verify this actual installed service against the selected
exact image and real runtime, including validation and restart, before claiming
physical readiness. Public CLI preparation/dispatch, durable preflight/transport
records, observation journal hooks, coarse run/postcheck/collection/finalization,
adequately budgeted real signoff and external acceptance remain their respective
later owners/gates. Existing physical evidence remains unchanged. No staging,
commit, push, stash, reset or agent spawning occurred.

## OCaml-owned bounded stage preparation and experimental CLI (2026-10-13)

Delivered `Stage_preparation` and `Runtime_probe` in `hardcaml_asic.execution`,
with public `.mli` interfaces and installed `hardcaml-asic-experimental-stages`.
Ancestor instructions, accumulated progress, `stages.prepare`, phase4 preflight
and staging, and the existing execution interfaces were inspected first. This
sole-agent slice adds preparation around the existing service, not a second
planner, transport, checkpoint writer or scheduler. The public
`hardcaml-asic-flow` command still owns its existing journal-aware invocations.

### APIs and ownership

`Stage_preparation.prepare ~bundle ~support_tools ~pdk_root ~python ~docker ~git
~resources ~workspace ~checkpoint_store ~evidence_root ~environment ~plan
?timeout ?probe_timeout ?initial_checkpoint ()` returns an inspectable private
prepared record or an error with the actual `Runner.error` and nullable preflight
path. Defaults remain **600 seconds per segment/publication call**, and 20 seconds
per probe; finite positive durations are required. These are not whole-plan
deadlines. `execute prepared plan` composes `Segment_service.execute`, preserving
the existing Runner summary plus separate version-1 diagnostics at fresh reserved
paths. The prepared record exposes `service`, compatibility, binding, evidence
paths and attempt ID for the later lifecycle/journal owner.

- `Result_store.begin_preflight` reserves a separate exclusive evidence directory.
  Pending receipt and pending readiness report precede tool lookup/probes. Failures
  retain terminal failed/interrupted records, original evaluation where available,
  actual probe stdout/stderr, argv/outcome/timing and partial newly owned workspace.
  Preflight success is readiness, not stage completion or acceptance.
- Bundle schema/adapter, identity syntax, inventory and file hashes, canonical
  collateral roots, requested Git revisions, reference existence/hashes/clean Git
  status, and strict bundle-requested runtime policy are validated in OCaml.
  The producer's order-sensitive bundle identity remains the bundle's authority;
  it is not re-signed with the checkpoint codec. No installed lock overrides it,
  and legacy exact-minor behavior is not waived by this CLI.
- `Runtime_probe` launches host metadata/Tcl, Git, Docker info/inspection and
  container metadata through existing supervision/transport. The only Python
  payload is import-dependent metadata/Tcl code: `stage_metadata_probe.py` has a
  closed protocol-1 envelope (`kind=stage_runtime_metadata`, role, metadata), no
  subprocesses, staging, policy or writes. Its digest/version are in readiness
  evidence. No Python `stages`, `prepare`, runner or public CLI is called.
- Container metadata binds to the inspected local image ID. Isolated `-I -B` is
  tried first; only distribution metadata import failure permits the image-owned
  `-B` fallback. Chosen flags, engine identity, platform and image identity are
  decoded by the existing runtime evidence/transport validators. Metadata probes
  reuse the owned Docker transport with only their fresh evidence directory and
  selected read-only PDK mounted; provider source is never mounted.
- Runtime policy, exact host LibreLane and headless Tcl readiness are evaluated by
  `Runtime_contract`/`Runtime_evidence`. Actual environment mismatch fails before
  stage execution. The demonstrated exact image is required. Engine and image are
  reverified after binding and **before and after every successful backend call**.
  The newly optional `Segment_service.create ~verify_runtime` callback supplies
  this obligation without embedding probes in the prepared-path primitive.
  `Segment_service.process_error` is now exported so probes reuse its actual
  exit/signal/timeout/cancellation/cleanup mapping.
- Fresh workspaces use exclusive mkdir; copying rejects links/special files and
  uses exclusive streaming copies with source/destination hash checks. Bundle
  files/manifest and external references are rechecked after staging. Support
  references go to `project/tt`; bridge, candidates and mounted store are created.
  Installed bridge/support bytes must match the existing OCaml pins before copy.
  Existing workspace entries, including empty directories, are refused.
- Resume uses the exact retained workspace/project/PDK/store and staged manifest,
  support bytes and pinned resources. Nothing is restaged or repaired. Existing
  checkpoint validation supplies actual compatibility/inventory/path/identity and
  first restart checks through `Segment_service.callbacks.validate`. Project/store
  disjointness, outside-workspace PDK and separate evidence-root ownership remain
  explicit. Compatibility keeps the existing seven fields unchanged.

`Runtime_probe.find_executable` resolves only an explicit executable or the supplied
complete environment's PATH. `Stage_preparation.installed_resources` derives
`lib/hardcaml_asic/flow/hardcaml_asic_flow` from the executable's installation prefix,
with no checkout search. `--resources` is an explicit override for source-linked
testing or a nonstandard installation. Host venv interpreter spelling is retained,
so resolving a venv symlink cannot accidentally select its base environment.

### Usable experimental command

```sh
hardcaml-asic-experimental-stages --no-observation \
  --bundle /absolute/bundle --toolchain /absolute/toolchain \
  --workspace /absolute/new-workspace --evidence-root /absolute/readiness \
  --through floorplan --timeout 120

# Exact retained resume; the initial boundary comes from the actual checkpoint.
hardcaml-asic-experimental-stages --no-observation \
  --bundle /absolute/bundle --toolchain /absolute/toolchain \
  --workspace /absolute/retained-workspace --evidence-root /absolute/readiness \
  --checkpoint /absolute/retained-workspace/checkpoints/floorplan-ID \
  --stages placement,cts --timeout 120
```

Toolchain defaults are `tt`, `pdk`, `.venv/bin/python`; explicit `--support-tools`,
`--pdk-root`, `--python`, `--docker` and `--git` are available. Store defaults to
`WORKSPACE/checkpoints`. `--through` and `--stages` use the existing checked stage
resolver. Stdout is the unchanged execution-summary JSON; stderr names preflight
and diagnostics; the command returns actual execution status. `--help` documents
the options. **`--no-observation` is required**, because observation journals are
not yet integrated. For a later signoff attempt use an explicit adequate budget,
for example `--timeout 3600`; the existing public default was not changed.

### Verification and real selected-image evidence

`test/stage_preparation_consumer.ml` independently consumes the installed public
API. `check_stage_preparation.py` passes **37 source-linked and 37 independently
installed checks**: fresh synthesis→floorplan, exact-workspace actual-checkpoint
resume (both API and CLI), bound injected bridge path and copied support, metadata fallback flags,
host/Tcl/policy/version/engine/image failures, timeout/nonzero probe code retention,
invalid bundles/inventories/paths/roots, changed collateral, missing executables,
missing/tampered resources, existing workspace refusal, staged support/bridge
mutation, incompatible resume PDK, coarse-plan rejection, runtime nonzero/missing
reply, post-execution engine mutation veto, installed prefix discovery and CLI
help/explicit observation opt-out. The actual transported bridge runs with only
native LibreLane APIs replaced by fixtures; production OCaml preparation,
supervision, runtime binding, Runner and publication are exercised.

Installed mode builds a new consumer outside the checkout, using only the installed
execution library, and runs installed runtime resources under Python checkout-open
denial. This is an audit-hook/resource/linkage check, not a kernel filesystem sandbox.

One real installed **synthesis→floorplan** smoke on the consumer bundle succeeded,
exit 0 in **55.721998 seconds**, with two distinct completed replies and two
image-only validated publication replies. Both schema-2 checkpoints passed the
installed Python validator in their original paths; identities/artifact hashes and
all four protocol correlations were audited. Image was
`sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a`,
Docker 29.8.1, LibreLane 3.1.0.dev3. Acceptance remains `not_evaluated`.
Curated evidence: [`ocaml-stage-preparation-smoke.json`](../../evidence/librelane-observation/ocaml-stage-preparation-smoke.json).
Raw evidence and immutable installed smoke prefix:
`/tmp/opencode/ocaml-stage-preparation-smoke/`. The smoke installation precedes
the final staged-support/payload rechecks, richer probe diagnostics and ISO receipt end-time
refinements; final source/installed fixture suites exercise those refinements.
No physical flow was repeated for these host-only changes.

Exact smoke command (new workspace only):

```sh
dune build -j20 @install test/stage_preparation_consumer.exe
dune install -j20 --prefix /tmp/opencode/ocaml-stage-preparation-smoke/prefix
python3 -I -B /tmp/opencode/ocaml-stage-preparation-smoke/launch.py
# launch.py executes exactly:
/tmp/opencode/ocaml-stage-preparation-smoke/prefix/bin/hardcaml-asic-experimental-stages --no-observation --bundle /home/wayne/devel/jane/hardcaml_asic_example/_flow_results/bundles/bbbda7ff53ea33cabf0063f7b26509bf601420ad5ab46c07e511fc8e9ee79477 --toolchain /home/wayne/devel/jane/hardcaml_asic_example/_flow_tools --workspace /tmp/opencode/ocaml-stage-preparation-smoke/workspace --evidence-root /tmp/opencode/ocaml-stage-preparation-smoke/readiness --docker /tmp/opencode/ocaml-stage-preparation-smoke/docker-20 --through floorplan --timeout 120 --probe-timeout 30
python3 -I -B /tmp/opencode/ocaml-stage-preparation-smoke/audit.py
```

`docker-20` delegates to `/usr/bin/docker`, adding `--cpus=20` and container
`_OPENLANE_MAX_CORES=20`, `MAX_CORES=20`, `OPENROAD_THREADS=20`, `OMP_NUM_THREADS=20`.
The launcher/installed-helper audit denies provider Python checkout reads. Consumer
pin SHA-256 before/after is
`90a5635e5a466d1c79ba4531b763c9effece3f8102f2bb388d26e234fd214eaf`;
consumer `git status --short` was empty. Existing consumer activation and prior
physical evidence remain intact.

Final checks (all Dune invocations sequential and `-j20`, including nested installed
consumer installation/build):

```sh
dune build -j20 @test/ocaml-stage-preparation @test/ocaml-segment-service @test/ocaml-runtime-contract @test/ocaml-execution-transport @test/stage-checkpoint @test/backend-protocol @install
dune build -j20 @test/ocaml-stage-preparation @install
python3 -B test/check_stage_preparation.py --installed
python3 -B test/test_installed_prefix.py
python3 -B test/test_packaging.py
git diff --check
```

The combined check exposed a test-only readonly Dune-resource-copy mutation; the
fixture now copies only its three resources into writable disposable files, and
the preparation alias passed on rerun. A first preparation check also exceeded the
terminal's 120-second command budget; it was rerun with an adequate harness budget.
Regressions pass: segment service **65**, runtime evidence **2,961 accepted / 1,253
rejected**, execution transport **34 differential / 105 negatives / 18 engine**,
stage/checkpoint **34**, protocol **50 accepted / 886 rejected** plus actual bridge
and no-publication checks. Existing public installed-prefix suite **57** and packaging
**17** also pass. Installed preparation, installation and whitespace pass.

### Journal/public CLI handoff

Use `prepared.service` with the existing `Segment_service.execute ?lifecycle` or
`callbacks`/`initial` and Runner hooks to port the actual observation owner. Preserve
early readiness records, one Runner source advance per successful publication,
actual process/request/reply/resource evidence and terminal save diagnostics.
`Stage_preparation.execute` already owns the fresh summary/diagnostics persistence;
the journal port must compose that ownership rather than add a competing writer.
Public CLI promotion waits for journal lifecycle integration. Coarse operations,
finalization, full slow signoff and external acceptance remain later work. This
dispatch did not attempt full signoff. Sole-agent work used no spawning or Git
staging, commit, push, stash or reset; accumulated changes/evidence were preserved.

Final read-only consistency check:
`python3 -I -B /tmp/opencode/ocaml-stage-preparation-smoke/verify_curated.py` passed,
matching curated evidence against retained launch argv, runtime binding, wire audit,
checkpoint identities, summary durations and unchanged consumer pin.

## Bounded observation reader/reducer migration (2026-10-13)

Delivered `Hardcaml_asic_execution.Observation` in the installed execution library,
with an exported `.mli` and `hardcaml-asic-experimental-observation-read`. Ancestor
instructions, accumulated progress, the complete bounded `flow_observation.py`,
schema-1/2 and incremental-reader tests, and the relevant execution interfaces
were inspected. No unrelated public CLI traversal or physical rerun was needed.
This sole-agent slice preserves accumulated work and historical record bytes.

### Ownership and compatibility

- `Observation` owns typed record/event decoding, the closed transition reducer,
  immutable validated prefixes, snapshot/results construction and host-only
  describe/inspect/read-updates readers for this experimental route. All JSON
  parsing, canonical signing verification and SHA-256 use `Identity_json`;
  filesystem JSON reads use `Result_store.read_json`. No additional dependencies
  or alternative JSON codec were added.
- `flow_observation.py` remains the authoritative production writer, public
  reader/watch and lifecycle composition. The experimental stage pipeline still
  requires `--no-observation`. Writer integration and live watch/delivery policy
  are deferred to the next dispatch; public stage-route promotion awaits that
  journal integration.
- Schemas 1 and 2 retain their exact closed envelopes and one schema per stream.
  Every sequence, stream binding, previous hash and canonical unsigned-record hash
  is checked before a prefix advances. Schema 2 requires actual Gregorian UTC
  `YYYY-MM-DDTHH:MM:SS.ffffffZ`, years 1..9999, and finite nonnegative nondecreasing
  elapsed numbers inside the hash. Wall-clock regression and equal elapsed values
  are allowed. Schema 1 has no timing fields; responses match the stream version,
  and no timestamps are synthesized. The foundation codec's Unicode scalar and
  finite JSON domain is inherited.
- Typed allocation, plan, preparation, occurrence, publication and outcome facts
  retain the Python lifecycle grammar. Publication must precede completed finish;
  only completed preceding occurrences permit the next start. Preparation/outer
  failure can terminate before planning or execution. Arbitrary integer exit codes
  are exposed as decimal strings, not narrowed through machine ints/floats.
  Numeric raw facts retain integer/float spelling for identity and serialization.
  Python value equality is reproduced for published/finished artifact equality:
  a finished reference may compare numeric `1`/`1.0` with a published boolean
  `true`, but **publication itself requires a boolean** `restart_supported`.
- Recorded checkpoint references do not trigger checkpoint reads, probes or
  readiness claims. Source boundary stays in the checked plan; resumption does
  not fabricate earlier occurrence/publication history. Signoff publication plus
  its completed occurrence establishes recorded physical completion independently
  of the outer outcome. Acceptance and external postcheck remain `not_evaluated`,
  including after physical completion or terminal persistence failure.
- Writer liveness uses a small C `open(O_RDONLY)`/nonblocking `flock` probe which
  interoperates with the existing Python writer. It creates/writes no lock file;
  acquisition is released by closing its own descriptor. Missing/unreadable lock
  returns unknown. Terminal outcome wins over liveness; absent outcome with an
  inactive/unknown lock remains `writer_lost_or_unknown`. Reader detach never
  completes, interrupts or revives an attempt.
- Incremental readers validate the complete attachment prefix and bind reconnect
  stream and cursor together. Idle polls perform metadata/liveness checks without
  reopening record content. A C `lstat` fingerprint preserves exact dev/inode/size
  and **nanosecond** mtime/ctime, avoiding Unix.stat float-time precision loss.
  Replaced/changed/deleted prefixes, nonregular/symlink records, malformed numeric
  record names, gaps and committed torn/corrupt tails fail closed. Hidden temporary
  files are ignored. New records are checked before/after reading; inactive/unknown
  liveness triggers a second refresh to drain the committed release tail. A failed
  reader is poisoned and must be discarded/reconnected. Metadata assumes the same
  trusted local immutable-prefix convention as Python, not a hostile filesystem.

### Installed command and API handoff

```sh
hardcaml-asic-experimental-observation-read describe
hardcaml-asic-experimental-observation-read inspect /absolute/observation
hardcaml-asic-experimental-observation-read read-updates /absolute/observation \
  --stream-id 32_lowercase_hex --after 4
```

The reader emits canonical JSON plus newline. Successful queries exit 0 even for
recorded failed/interrupted attempts. Invalid records/cursors exit 2 with the
existing schema-1 error envelope (`INVALID_RECORD`/`RESET_REQUIRED`). Help needs
no runtime. `describe` deliberately describes the **shared persisted Python
service contract**, including its watch schema, not implemented OCaml writer/watch
capabilities; help and the `.mli` explicitly identify the read-only command scope.

Ready-to-use writer foundations in `observation.mli`:

1. `event_of_json ~name data` produces a checked typed event;
   `event_to_json` round-trips its event data. `reduce_event old ~stream_id event`
   checks lifecycle transitions without IO or publication attestation. The future
   writer must supply actual `Runner` lifecycle facts and successful publisher
   references, rather than infer them from retained files.
2. `empty` / `append_record prefix record_json` return an immutable validated
   prefix. `records`, `state` and `cursor` expose the signed record list and private
   typed reduced state (allocation, phase, checked plan/source, occurrences,
   artifacts, runtime reference and nullable outer outcome). `state_json` retains
   the existing reduced-state model.
3. The writer can construct the unsigned schema-2 envelope, validate UTC/elapsed
   timing and sign via `Identity_json`, then call `append_record` **before**
   promotion. Retain the old prefix until its one authoritative atomic promotion
   succeeds; only then advance sequence/hash/state. This slice performs no writes
   and establishes no fsync guarantee or takeover/recovery policy.
4. `snapshot prefix ~writer_active` and `updates prefix ~stream_id ~after` are pure
   query constructors. `load`, `inspect`, `read_updates`, `writer_active` and
   `Reader.create`/`Reader.poll` compose actual host IO. `Reader.poll` returns the
   complete update payload and existing status payload, without a signal handler,
   foreground polling loop, delivery framing or watch exit policy.
5. Integrate with the existing `Stage_preparation` summary/diagnostics persistence
   and `Segment_service`/`Runner` hooks, preserving one execution/checkpoint writer
   and the existing authoritative source advance. Journal allocation must precede
   plan/preparation work, and ownership must span it through terminal recording.
   Locking, timestamps, atomic append, interruption/final-save behavior and public
   route promotion are the next writer/integration dispatch's responsibility.

### Exact verification

`test/observation_consumer.ml` independently consumes the exported API, including
event round-trip, direct reducer equivalence and old-prefix/state immutability.
`test/check_observation.py` uses actual Python `Writer`, `Runner`, record validation,
reducers and query functions; only physical backend operations are replaced.
Successful fixture production is explicitly asserted before differential use.

Final source and freshly installed results: **307 accepted / 2,077 rejected**
record/reducer cases; **173 source queries**, **217 installed queries** including
44 queries over **11 real historical observations**; **22 incremental checks**.
Coverage includes every prefix of all six fresh endpoints and resumed schema-2/3
plans, real production writer hashes/timestamps, legacy fixture replay, allocation
and preflight failure, ordinary/interrupt finish with later unreached actions,
out-of-order start, duplicate publication, unearned completion, outcome after
terminal, signoff completion with outer failure, closed/missing/extra/wrong-type
record and event fields, nested occurrences/references, re-signed bad hashes,
versions, calendar times and elapsed regression/overflow, stream/cursor errors,
active/inactive/unknown locks, append/reconnect and malformed filesystem tails.

Test-only syscall tracing with installed `/usr/bin/strace` confirms each initial
and newly appended record is opened exactly once across idle polls; only metadata
and liveness work repeats. Poisoned readers reject even after the test owner
repairs its disposable fixture. No historical fixture is converted or repaired.
The 11 real observations are read in place from
`/tmp/opencode/backend-v1-integration/results/observations` and the consumer's
`hardcaml_asic_example/_flow_results/observations`; directory file bytes are
compared before/after all queries. Historical testing is an explicit flag, not
an external dependency of the normal Dune alias.

Installed mode installs into a disposable prefix and compiles a new consumer
outside the checkout using only `hardcaml_asic.execution`. The entire differential
corpus runs against installed Python semantics and the installed native command,
with PATH/PYTHONPATH unusable for native queries, checkout Python opens denied,
and LibreLane/bridge imports denied. This establishes installed linkage/resource
independence, not a kernel filesystem sandbox.

Commands run sequentially; **all Dune commands, including nested installation and
independent consumer compilation, use `-j20`**:

```sh
dune build -j20 @install
dune build -j20 @test/ocaml-observation @install
dune build -j20 @test/ocaml-observation @test/flow-observation @test/observation-watch @test/default-journal @install
python3 -B test/check_observation.py --installed --historical
python3 -B test/test_installed_prefix.py
git diff --check
```

Early verification caught an unused consumer helper and then a test-only reference
fixture that included endpoint/successor capability fields instead of the closed
reference shape. Correcting the fixture and asserting successful production
expanded actual lifecycle coverage and exposed the finished-reference Python
numeric-equality edge above; it was corrected and all final checks were repeated.
Existing regressions pass: flow-observation **20**, default-journal **10**, watch
**11**, installed-prefix **57** (24.876 seconds). `@install` and whitespace checks
pass. No agents were spawned; no staging, commit, push, stash or reset occurred.
Writer/live watch integration and public promotion remain the explicit next handoff.

## Bounded journal writer and experimental stage lifecycle (2026-10-14)

Delivered `Hardcaml_asic_execution.Observation_writer` atop the existing typed
event decoder/reducer, integrated into `Stage_preparation` and the installed
`hardcaml-asic-experimental-stages` command. Ancestor instructions, this progress
record, current Observation interfaces, Python writer and public stages dispatch
were inspected before implementation. Public command routing is the next slice;
foreground native watch remains separate. No physical EDA was needed.

### Exact API and ownership

`Observation_writer.t` is abstract. `create ?wall_clock ?clock ~root ~workspace
~checkpoint_store ~request ()` resolves paths, refuses a store within the workspace,
acquires the existing Python-compatible **nonblocking workspace flock**, then starts
the monotonic clock and exclusively allocates a new `Result_store` attempt. It holds
both that ownership lock and the attempt's `writer.lock` activity flock until
`close`. Conflict raises `Observation_writer.Busy`; there is no takeover/adoption.
Descriptors are close-on-exec. Failed construction releases acquired descriptors
and preserves any allocated directory. Locks are advisory, under the existing
trusted, stable, local parent-directory convention.

Exports: `directory`, `stream_id`, `preflight_path`, `state`, idempotent `close`,
generic validated `append ~name`, typed `planned`, `prepared ~runtime_record`,
Runner-compatible `lifecycle`, `outcome ~status ~exit_code ~error`, and the existing
schema-1 `allocation_receipt` envelope. `close` writes nothing: lost/terminated
writers retain their last facts, with no recovered status or inferred completion.
Injectable wall/monotonic clocks support deterministic timing tests, not a second
timestamp schema or caller-synthesized historical timing.

Each event is decoded and reduced **before IO**. Producer UTC uses six fractional
digits and `Z`; elapsed seconds are finite/nonnegative/nondecreasing monotonic
seconds since creation. Wall clock may regress. Timing is included in the existing
schema-2 canonical unsigned SHA-256 envelope. The same `Identity_json` and
`Result_store` record bytes are used; schema-1 readers are untouched.

A closed exclusive same-directory temporary is atomically linked into the
`%012d.json` target with **no replacement**, then removed. Readers never see a
partial event. Chain/state/sequence advance only after promotion. Any append failure
poisons the writer; later hooks cannot retry, overwrite retained records or invent
an outcome. This is local atomic visibility, not fsync/power-loss durability.
Memory retains a reduced six-stage state and chain head, not the event history.

`Stage_preparation.prepare ... ?observation ~plan ()` writes readiness at the
writer's advertised `preflight_path`, retains its separate exclusively allocated
probe/operation evidence directory, and uses the writer's stream ID for reserved
execution/diagnostic filenames and Runner occurrence IDs. Without this option its
existing API behavior is retained. `execute ?observation prepared plan` attaches
the writer's Runner lifecycle hook while retaining existing persistence and actual
Segment_service publication ownership. Caller owns planned/prepared/outer-outcome
events. Actual checkpoint promotion precedes `Published`, which precedes
`Finished`; promoted references remain recorded even if a later hook/storage error
makes the occurrence fail. Failed/interrupted finishes carry null artifacts under
the existing grammar, while earlier published references remain in reduced state.

Runner diagnostics retain primary execution errors and secondary hook/storage
errors. A backend exit 17 still wins over a failing finish-record publication.
The command retains additional attempt-local `diagnostics.json` on runner failure
where storage permits. It verifies that the terminal execution summary actually
matches the returned result **before** exposing its reference and recording the
outer outcome. Failed summary storage exposes no terminal execution reference;
the explicit failed outer outcome and separate diagnostics are retained where
possible. Poisoned journal IO leaves an incomplete prefix and reports a distinct
`recording_error`, rather than converting it into completion.

### Experimental CLI

```sh
hardcaml-asic-experimental-stages --bundle /absolute/bundle \
  --toolchain /absolute/toolchain --workspace /absolute/new-workspace \
  --evidence-root /absolute/readiness --through floorplan --json
```

Journals now default to resolved workspace parent/`observations`.
`--observation-store PATH` selects an explicit root; `--no-observation` opts out,
and the two options are mutually exclusive. Allocation and its flushed receipt
precede checkpoint reading, plan resolution, tool-path selection and preflight
probes. Planning/path failures retain attempt-local diagnostic readiness records
where possible. Existing timeout/resource/toolchain/resume options are unchanged.

`--json` produces the existing schema-1 allocation envelope followed by the
unchanged execution summary on normal return. Preparation/command/recording
exceptions produce the existing `observation_terminal` envelope with nullable
attempt/stream/execution reference, inspection, primary error and `recording_error`.
These default JSONL envelopes are emitted only with `--json`; opt-out emits only
the execution JSON. Human mode names the observation and reports status, execution
reference, stage durations/errors, historical checkpoint references, and explicit
`not_evaluated` acceptance/postcheck. Scoped SIGINT/SIGTERM handling covers planning
and preparation; supervised callbacks retain their own cancellation semantics.
Finally releases ownership and restores handlers, without fabricating success.

### Verification and bounded handoff

`test/observation_writer_consumer.ml` and `check_observation_writer.py` exercise
**21 source and 21 independently installed checks**: actual subprocess native
reader while OCaml writer is live, Python reader of OCaml schema-2 journals,
native reader of live Python journals, exact canonical/hash parity, controlled
monotonic elapsed and regressing UTC wall time, cross-language workspace contention,
SIGTERM writer loss, fresh allocation after lock release, immutable target collision,
poisoning and temporary cleanup. No retained records are rewritten.

`check_stage_preparation.py` now passes **48 source and 48 installed checks**
(previously 37): default and explicit journal roots, JSON/human/opt-out behavior,
fresh synthesis and synthesis→floorplan lifecycle, allocation-before-probe fixture
assertions, terminal summary-before-outcome ordering, early invalid plan/checkpoint
diagnostics, preflight failure, flushed allocation during a blocked probe with real
SIGTERM/143, promoted checkpoint retained after observation failure, backend-17
precedence over observation failure, actual checkpoint-store publication obstruction,
and execution-summary storage failure with no terminal reference. Installed mode
builds fresh independent consumers and runs installed resources outside the checkout
with Python checkout opens denied. These are pipeline fixtures, not physical readiness.

Final commands were sequential, including all nested Dune commands, all `-j20`:

```sh
dune build -j20 @install @all @test/ocaml-stage-preparation @test/ocaml-observation-writer @test/ocaml-observation @test/ocaml-runner @test/flow-observation @test/default-journal @test/stage-checkpoint
python3 -B test/check_stage_preparation.py --installed
python3 -B test/check_observation_writer.py --installed
python3 -B test/test_installed_prefix.py
git diff --check
```

Focused checks, `@install` and `@all` passed. Existing installed-prefix suite:
**57 tests passed (22.932 seconds)**. Verification exposed and corrected the
post-promotion persistence-failure finish-reference edge described above.

Next slice: route public `hardcaml-asic-flow stages` to this installed OCaml
ownership path while preserving its existing argument/path/environment contracts,
default observation receipts, JSON flag placement, human presentation and execution
failure semantics. Public coarse run/postcheck/finalization dispatch is separate.
Then migrate public observation query dispatch; native foreground watch should be
its own bounded delivery/signal/interval/reconnect slice using `Observation.Reader`.
No bridge/checkpoint/resource pins or persisted schemas changed. Sole-agent work
preserved accumulated changes and retained evidence; no spawning, staging, commit,
push, stash or reset occurred.

## Bounded public CLI4 integration (2026-10-14)

The installed **public** `hardcaml-asic-flow` now delegates `stages` to actual
OCaml `Stage_preparation` / `Segment_service` / `Runner` / `Observation_writer`.
`checkpoint-inspect` invokes the actual OCaml `Checkpoint` inspector; observation
`describe`, `inspect` and `read-updates` invoke the actual `Observation` reader.
This is a public routing slice, not a top-level OCaml parser replacement.

### Ownership, installation and development adapters

The existing isolated shell launcher and Python argparse parser retain CLI4
help/version/options. `ocaml_backend.py` explicitly selects helper executables
from the imported package's **same installed prefix**, never from PATH or an
opam switch. Stage delegation uses `os.execv`: the public PID becomes the OCaml
process, without a Python execution supervisor, proxy pipeline or Python journal
writer. Only the isolated LibreLane bridge and metadata payload remain Python
backend resources. Read-only queries collect the native reader's JSON result and
use the existing Python presentation functions; validation/reduction belongs to
the typed modules. Dead public Python stages/checkpoint/cold-query dispatch was
removed, so an unavailable binary cannot silently fall back.

`flow/dune` additionally installs `ocaml_backend.py`. `bin/dune` still installs
the linked experimental-named helpers, now also used as the explicit public
backend. The shell launcher checks the delegation module along with its required
Python modules and reports an incomplete installation actionably. Runtime resources are supplied from the imported installed package
directory, independent of cwd/checkout; Dune's build-tree and checkout adapters
use their own `_build/default/bin/experimental_*.exe` equivalents and the same
OCaml implementation. `scripts/flow_cli.py` documents the build prerequisite.
Missing helpers produce an actionable reinstall/build diagnostic and exit 2;
help/version remain usable without helpers or physical tools.

### CLI4 compatibility decisions

- Public bundle remains **positional**. Required explicit support/PDK/interpreter/
  workspace/checkpoint-store options and exclusive `--endpoint` / `--plan` retain
  the current parser behavior. `--source` is not a public stages option: source
  boundary is inferred from `--checkpoint`, or declared in strict schema-2/3
  `--plan`. Unknown options remain errors rather than experimental aliases.
- Relative directory paths resolve against caller cwd; interpreters retain lexical
  venv/symlink traversal. Default journals are workspace-parent/`observations`;
  explicit store and `--no-observation` retain their mutual exclusion. JSON flag
  placements retain the parser's outer/nested precedence; verbose remains accepted
  without inventing new stage diagnostics.
- Allocation/terminal/execution/query envelope field sets and schema versions are
  unchanged. Allocation is flushed before planning/readiness. Execution summaries
  are persisted by the OCaml runner before outcome publication. Public request
  metadata retains the parsed options and caller cwd (rather than only native argv).
- `public_stage_presentation.ml` reproduces the existing public stage/allocation
  views. A real pipeline test compares **entire human stdout** against the existing
  Python renderer, including spacing, durations, historical publications and
  `not_evaluated` acceptance. Reader human views still use that renderer.
- Public timeout stays integer seconds, default **600 per backend call**; no
  experimental opt-out requirement or whole-plan deadline was introduced. Readiness
  probes retain their bounded 20-second budget. Separate retained probe/operation
  evidence is allocated under workspace-parent/`stage-preflight`, including opt-out
  runs; journal readiness remains at its advertised attempt-local path.
- Historical public exception semantics are preserved: readiness errors, segment
  timeouts and failed publication validation report exit **2**. Ordinary segment
  exit 17 remains 17. A caller-supplied `failure_exit_code` mapping preserves raw
  transport evidence and never overrides cancellation. Experimental/API defaults
  retain their process-derived statuses (including timeout 124). Scoped public
  SIGINT/SIGTERM remain interruption/130 and interruption/143 with released locks.
- Native validators retain their strict record parsing. Diagnostic detail strings
  now identify typed-reader/preparation failures and are not Python exception-text
  byte goldens; success payloads, error envelope shape/code and exit semantics are
  the maintained boundary. Negative records do not imply readiness or acceptance.
- OCaml Docker invocations now have `--cpus=20`, `_OPENLANE_MAX_CORES=20`,
  `OPENROAD_THREADS=20`, and `OMP_NUM_THREADS=20`. The transport differential test
  explicitly verifies the bounded command in addition to the historical baseline.
  This establishes requested caps/quota, not a measured physical-tool thread count.

CLI contract remains **4**; package version, persisted schemas and bridge/protocol
pins were not bumped by this slice.

### Boundary verification

`public_cli_fixture.py` answers only external collateral/runtime/engine processes;
the installed/public parser, linked OCaml control/storage and transported bridge
are real. `test_default_journal.py` now has **11 boundary tests**, replacing
Python-internal monkeypatches with fresh/resumed execution, strict plans, readiness
failure, allocation contention/missing parent, opt-out, actual filesystem storage
obstructions, promoted-publication preservation, exact human-output comparison,
reader payload parity/cursor negatives, parser/default/missing-helper checks,
explicit timeout/publication exit mapping, broken allocation stdout, and real
SIGINT/SIGTERM to the public PID. Related presentation tests now exercise native
stage subprocesses; unknown writer presentation is tested as a presentation case,
without monkeypatching the public reader implementation. A flaky incidental `499`
substring check was tightened to exclude the actual large serialized command list.

The installed-prefix suite copies the public lifecycle driver and all external
fixtures to an unrelated directory, installs into a fresh prefix and invokes the
**installed public launcher**. The parent audit hook denies checkout reads; exec'd
native/bridge processes use explicitly prefix-bound resources, not an inherited
Python audit sandbox. Publication-validation failure uses a read-only existing
`/nix/store` regular file as synthetic image-closure evidence, as the existing
segment-service fixture suite does; no Nix/physical tool is launched.

Verification results:

| Check | Result |
| --- | --- |
| Installed-prefix suite | **57 passed**, 341.008 seconds |
| Public default journaling | **11 passed** |
| Flow CLI | **43 passed** |
| Stage/checkpoint API and negatives | **34 passed** |
| Related / inspector presentation | **8 / 11 passed** |
| Foreground Python watch regression | **11 passed** |
| Stage recipe contract | **36 accepted / 1,819 rejected**, 33 drift negatives |
| OCaml prepared service | **65 pipeline checks passed** |
| OCaml preparation | **48 pipeline/API checks passed** |
| OCaml transport | **34 differential / 105 negatives / 18 engine cases passed**, lexical venv |
| Packaging | **17 passed** |
| Final launcher/module/helper absence, help and contract checks | **3 installed-prefix tests passed**, 1.402 seconds |

All Dune commands were sequential and used `-j20`, including suite-owned builds
and installations. Principal commands:

```sh
dune build -j20 @install @test/default-journal @test/related-presentation @test/inspector-presentation @test/observation-watch @test/flow-cli @test/stage-checkpoint @test/ocaml-stage-recipes
dune build -j20 @install @test/ocaml-segment-service @test/ocaml-stage-preparation @test/ocaml-execution-transport
python3 -B test/test_installed_prefix.py
python3 -B test/test_packaging.py
python3 -B test/test_installed_prefix.py InstalledPrefixTest.test_installed_required_transport_module_absence_fails_closed InstalledPrefixTest.test_help_needs_no_git_ocaml_pdk_docker_or_provisioning InstalledPrefixTest.test_installed_shared_cli_contract_version_is_separate_from_records
dune install -j20 --prefix /tmp/opencode/public-cli4-prefix
```

The existing consumer was independently built against that prefix in
`/tmp/opencode/public-cli4-consumer-build` with `OCAMLPATH` selecting its installed
library, using `dune build -j20 --build-dir ... bin/project.exe`. Then:

```sh
python3 -B test/check_public_consumer_route.py --consumer /tmp/opencode/public-cli4-consumer-build/default/bin/project.exe --source /home/wayne/devel/jane/hardcaml_asic_example --prefix /tmp/opencode/public-cli4-prefix
```

This passed consumer nested-root inference (`asic/` cwd), an explicit fixture
bundle, `run --endpoint floorplan` → installed public stages → OCaml readiness,
synthesis/floorplan publication and default journal, persisted execution parity,
and installed native observation inspection. The consumer source and its normal
dependency selection were not edited. No fresh physical EDA was run.

### Precise remaining Python ownership / handoff

Still Python-owned public families: `provision`, `preflight`, coarse `run`,
`postcheck`, `collect`, `report`, `archive`, coarse `execute`, `finalize`,
`finalization-inspect`, and **observation watch**. The launcher, top-level parser,
version report and cold-reader human formatting also remain Python. Python stage,
checkpoint, observation and runner APIs remain installed for existing callers,
finalization and cross-language fixtures; they are not a public migrated-command
fallback. Development adapters use the same explicit boundary.

Next bounded port: native foreground watch using `Observation.Reader`, preserving
CLI4 update/status envelopes, stream/cursor reconnect/reset rules, status-change
deduplication, intervals, EOF/broken output, completed vs lost-writer exits, and
reader SIGINT/SIGTERM behavior. Existing Python watch remains functional against
OCaml journals. Top-level OCaml parser and remaining command-family migration are
separate. Accumulated work and retained evidence were preserved; no agents were
spawned and no staging, commit, push, stash or reset was performed.

## Bounded native foreground watch / authoritative public route (2026-10-14)

Delivered native foreground `observation watch` through the **same installed
observation helper** used by cold queries. This supersedes the preceding watch
handoff and its historical Python ownership entry. Ancestor AGENTS, this progress
record, `Observation.Reader`'s current interface/implementation and Python CLI4
watch/presentation/tests were read before implementation. Work was sole-agent;
accumulated changes and physical evidence were preserved.

### APIs, files and delivery contract

- Existing installed API `Hardcaml_asic_execution.Observation.Reader.create
  ?stream_id ?after directory`, `Reader.poll`, and `Reader.prefix` remain the
  validating/incremental boundary. No new library API or persisted schema is
  needed. The `.mli` now describes the implemented installed watch protocol.
- `bin/observation_watch.ml` implements foreground polling and human/JSONL
  delivery; `bin/experimental_observation_read.ml` dispatches `watch DIRECTORY
  [--json] [--interval SECONDS] [--stream-id ID --after INTEGER]`.
  `bin/dune` includes the module and explicit Unix dependency in the installed
  `hardcaml-asic-experimental-observation-read` executable.
- Public `cli.py` delegates through `ocaml_backend.watch` using `os.execv`.
  PID/signal delivery is native after delegation, with no supervising Python
  reader or fallback. Helper lookup is prefix-bound when installed and explicitly
  Dune-build-bound in development. Missing helpers produce actionable reinstall
  or `dune build -j20 @install` diagnostics and exit 2.
- Complete retained-prefix validation and stream/cursor pairing happen on
  attachment. Only nonempty updates are delivered, then changed statuses;
  duplicate idle statuses are suppressed. Reconnect delivers only events after
  the saved cursor. Schema-1/2 envelopes and producer timestamp facts are retained.
  Human output matches the Python presentation, including all chronological
  events, checkpoint/error details, six-digit producer UTC and three-decimal
  elapsed seconds; no 20-event elision or synthesized timestamps.
- Reader metadata fingerprints and liveness checks are reused, so idle polling
  never reopens record content. Changed/replaced/deleted prefixes fail closed.
  Inactive/unknown lock observation drains again before delivery/exit. Existing
  terminal policy is unchanged: recorded outcome exits **0**, unresolved writer
  loss/unknown exits **3**, query/output failure exits **2**. Silence while the
  writer remains active implies no outcome and does not terminate watch.
- Scoped SIGINT records a local detach flag, checked during polling/delivery and
  bounded sleep slices, and returns **130**. SIGPIPE is locally ignored so broken
  stdout returns 2 cleanly; `/dev/full` likewise returns 2 without a second failed
  shutdown flush. SIGTERM retains normal process termination. No reader operation
  signals or mutates the producer, journal, checkpoints or workspace. No scheduler,
  daemon, recovery or takeover was added.

### Verification and meaningful installed boundary

`test/test_observation_watch.py` now has **16 tests**. Existing live subprocess
writers gate each actual lifecycle append on independent reader acknowledgement;
terminal-failed query success, reconnect/deduplication, SIGINT with the writer
still alive, broken pipe, `/dev/full`, abrupt writer death and all 22 human events
exercise the public native route. Added checks cover exact cold human parity and
byte-preserving reads, native cursor negatives, live prefix mutation, and
test-only strace proof of exactly one content open per initial/new record.
An additional live `Observation_writer` OCaml consumer subprocess verifies native
allocation, watcher SIGINT detach with the producer still alive, cursor reconnect,
actual terminal append, and terminal stop while the producer still holds its lock.
The installed suite copies this linked API consumer outside the checkout too.

A test-only compiled `LD_PRELOAD` flock gate pauses the **actual native liveness
probe after the first refresh**. The real writer commits outcome and releases its
lock before the probe proceeds; native watch must deliver both allocation and
outcome and final status, exit 0. This tests the terminal-release race without a
production injection API or timing luck. The original Python incremental tests
remain differential/reference coverage, not native implementation claims.

`test_installed_prefix.py` copies watch/stage fixture drivers to an unrelated
directory. Its public watch subprocesses install audit hooks denying checkout
reads **and Python observation-reader imports** before loading installed CLI.
The full live/cursor/mutation/output/interrupt/race/idle suite then runs against
the installed helper. This would reject the former Python watch implementation.
Direct native cold replay also uses unusable PATH/PYTHONPATH. Installed helper
absence and development missing-helper diagnostics are checked. Audit hooks are
Python boundary evidence, not a kernel filesystem sandbox for exec'd native code.

Results:

| Check | Result |
| --- | --- |
| Public/native watch | **16 passed** (source and fresh installed prefix) |
| OCaml observation reader/reducer | **307 accepted / 2,077 rejected; 173 queries; 22 incremental checks** |
| OCaml observation writer | **21 live/cross-language/lock/no-replace checks passed** |
| Existing flow observation / default journal | **20 / 11 passed** |
| Related / inspector presentation | **8 / 11 passed** |
| CLI / stage-checkpoint | **43 / 34 passed** |
| Stage recipe contract | **36 accepted / 1,819 rejected; 33 drift negatives** |
| Full installed-prefix suite | **57 passed**, 342.377 seconds (before the added OCaml writer test) |
| Final installed watch/helper-absence checks | **2 passed**, 4.531 seconds, including all 16 watch tests |
| Packaging | **17 passed** |
| `@install` / whitespace | Passed |

Commands ran sequentially; every Dune invocation, including suite-owned builds
and installations, used `-j20`:

```sh
dune build -j20 @install @test/observation-watch
dune build -j20 @install @test/observation-watch @test/ocaml-observation @test/ocaml-observation-writer @test/flow-observation @test/default-journal @test/related-presentation @test/inspector-presentation @test/flow-cli @test/stage-checkpoint @test/ocaml-stage-recipes
dune build -j20 @test/flow-observation @install
python3 -B test/test_installed_prefix.py
dune build -j20 @install @test/observation-watch @test/flow-cli
python3 -B test/test_packaging.py
python3 -B test/test_installed_prefix.py InstalledPrefixTest.test_installed_incremental_watch_suite InstalledPrefixTest.test_installed_required_transport_module_absence_fails_closed
git diff --check
```

The combined focused run exposed a missing native-helper sandbox dependency in
the existing `flow-observation` alias (three public cold-query tests failed).
`test/dune` now declares the actual observation helper for both watch and flow
observation aliases; the 20-test suite passed on rerun. An initial signal handler
that raised during Unix sleep was replaced by the scoped detach flag; final
source/installed interruption tests pass without an uncaught exception.

### Remaining owners / handoff

Python still owns public `provision`, `preflight`, coarse `run`, `postcheck`,
`collect`, `report`, `archive`, coarse `execute`, `finalize` and
`finalization-inspect`; the launcher, top-level parser, version reporting and
cold-reader human formatting also remain Python. Retained Python stage,
checkpoint, observation, incremental-reader and runner APIs serve existing
callers/finalization/reference fixtures; they are not migrated-command fallbacks.
Native watch owns both its foreground policy and presentation. Next bounded work
is top-level parser/remaining family migration under existing lifecycle contracts.
The separate real full-signoff/finalization/acceptance gate remains recorded above.
No fresh physical EDA was needed. No agents were spawned and no staging, commit,
push, stash or reset was performed.

## Bounded stage/step decomposition (2026-10-14)

Delivered discoverable actual OCaml domain modules under `lib/flow/stages/` for
all six existing groups, with dedicated placement global/design-repair/detailed
contracts and shared `lib/flow/analysis/timing.ml`. The installed
`hardcaml_asic.flow_domain` library uses namespace `Hardcaml_asic_flow_domain`,
wrapped with qualified subdirectories. It depends only on Core. Hardware's
`Flow.Stage.t` aliases domain `Stage_id.t`; `Flow.Stage`/`Flow.Recipe`, recipe
schemas, stage names and supported restart targets retain their contracts.

Dependency direction is IDs/operations → shared analysis/stage recipes → registry
→ backend mapping → public capability facade/execution. The domain registry
never imports `Flow_stage` or backend mapping. Backend endpoints/successors derive
from its maintained flattened composition, rather than another endpoint table.
The Python planner and bridge literal tables continue to be cross-language
checked; bridge bytes stay
`e8dc9532c61010ae8699d3a6f27cdfd0d773ff3e24d06f9eefbe2d0f5b2da841`.

`lib/flow/backends/librelane/mapping.{ml,mli}` supplies exact Classic step IDs,
implementation IDs, native artifact contracts, gates/defaults, and bounded
placement configuration descriptors. `lib/execution/classic_contract.{ml,mli}`
serializes these into installed plan inspection's additive `operation_groups`
and requested `operation_sequence`. Public capabilities retain their existing
fields. Occurrence IDs include stage/ordinal/backend ID; all four shared mid-PNR
STA occurrences are distinct. Defaults/configured gates remain distinct from
execution facts: `execution_evidence` is null and no individual occurrence
advertises a durable checkpoint.

Runtime plan validation in the actual segment service uses the trusted contiguous
composition. Preparation now validates an import-only Classic inventory from the
bound selected image, including artifact sets and boolean gates/defaults, plus
the declared placement setting types/units/defaults. Unsupported drift rejects
before fresh workspace staging. Step-native skip conditions and effective
configuration validation remain backend-owned. Artifact sets are sorted because
upstream diode outputs have process-dependent order; execution order is preserved.

Selected-runtime probe: consumer `_flow_tools/.venv/bin/python` and exact image
`sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a`
agree on **80 occurrences**, grouped **6/7/21/1/12/33** across synthesis,
floorplan, placement, CTS, routing, signoff. Container LibreLane is 3.1.0.dev3,
Python 3.13.13. The probe uses isolated `-I -B`, container network disabled,
and imports only (no Config/State/Flow construction or physical execution).
Metadata payload SHA-256:
`2ebbfcc8afafa83965471a94c14de7d0e388667175997198728d75f3c6cb1d85`.
Placement retains RC/macro/power/rows, taps/PDN obstruction lifecycle, routing
obstructions, skip-IO/IO/custom IO/template, global placement, header/grid check,
STA, post-GPL design repair, manual global placement and detailed placement.
Post-CTS STA/timing repair remains routing; post-routing checks/fill/extraction
remain signoff. No grouping changed.

Verification commands (all Dune invocations, including nested installs/builds,
sequential and `-j20`):

```sh
dune build -j20 @install @test/stage-domain @test/ocaml-stage-recipes @test/execution-plans @test/ocaml-stage-preparation @test/ocaml-segment-service @test/default-journal @test/related-presentation
python3 -B test/check_stage_domain.py --installed --selected
python3 -B test/check_execution_plans.py --installed
python3 -B test/test_installed_prefix.py
git diff --check
```

Checks cover exact six-group flattening, unique repeated-analysis identities,
14 inventory and 5 setting drift negatives, independent installed domain/API
linkage, recipe/public capability compatibility (33 AST drift negatives; 36
accepted/1819 rejected recipes), 164 accepted/4900 rejected source and installed
plans, 51 preparation/pipeline checks including real preflight drift rejection,
65 segment/publication checks, 8 default-journal tests, 11 related-presentation
tests, and the 57-test installed-prefix suite. The installed-plan check's old
identity-only META expectation was corrected to current spawn/unix dependencies.

Remaining physical finer-execution gate: per-operation backend invocation and
artifact handoffs need a separate protocol slice, then selected-runtime physical
execution/comparison against the runnable coarse composition. Current protocol v1
continues running the standard coarse segments; decomposition establishes no new
restart, arbitrary recipe/profile, or physical acceptance capability. Accrued
work and evidence were preserved; sole agent, no spawning or Git mutations.

## Bounded corrective slice: four reproduced P2 findings (2026-10-14)

Applied to the current public CLI4/OCaml pipeline after reading the ancestor
instructions, accumulated progress and current sources. Existing worktree code
and checked-in physical evidence were preserved. Sole agent; no spawning,
staging, commits, push, stash or reset. All Dune invocations (including nested
installed-consumer builds) were sequential and used `-j20`.

### Findings and corrections

1. **Completed Docker cleanup consumed the entire five-second window.** The
   reproduced public synthesis fixture had 88 removal calls and 17.4 seconds of
   elapsed time. `lib/execution/execution_transport.{ml,mli}` now distinguishes
   clean completed clients from uncertain/nonzero/failed/signalled/timed-out or
   cancelled clients. For clean completion, successful removal or an exited
   absence response ends cleanup immediately; transient removal failures still
   retry. Uncertain clients retain the bounded full-window retry needed for late
   daemon creation, even after an absence observation. Primary error precedence
   and the existing deadline/startup reserve remain. Fake-engine regressions in
   `test/check_execution_transport.py` / `test/fake_docker_engine.py` assert one
   removal and under 1.5 seconds with a **five-second** cleanup budget for both
   successful removal and already-absent completed launches, plus two attempts
   for a transient removal failure. Existing timeout/nonzero late-creation races,
   cleanup failures and interruption cases still pass. The public fixture also
   checks exactly one removal per actual physical-call container; no claim of a
   new whole-pipeline elapsed-time guarantee is made.

2. **Operation receipts referenced missing operation-local preflight files when
   a journal was enabled.** `lib/execution/stage_preparation.ml` now writes the
   same pending, evaluated and terminal diagnostic report to the receipt's
   operation-local `preflight.json` and the journal's preflight path using the
   existing atomic writer. The relative receipt convention remains intact; no
   symlink or historical-record migration is introduced. Success, readiness
   failure and real SIGTERM during a blocked probe verify both referenced files
   exist and have identical bytes in `test/check_stage_preparation.py`.

3. **Actual segment/publication transport invocations were not retained.**
   `lib/execution/segment_service.{ml,mli}` now writes unique exclusive immutable
   `TAG-transport.json` before each actual launch and `TAG-transport-result.json`
   after supervision/cleanup, for execution and publication validation. Both
   correlate request ID, request path/hash and record paths. Launch evidence
   retains actual argv/executable/cwd, checked engine/image binding, owned
   container name, host UID/GID, explicit container user/resource limits and
   timestamp/timeout. Terminal evidence retains primary outcome, child status,
   PID, timing/log paths and every removal outcome/diagnostic, including successful
   cleanup. Complete ambient environment and the fixture secret are not persisted.
   `transport_succeeded` describes transport only, never protocol validation or
   publication. Missing terminal evidence is incomplete recording, not success.

   Returned segment evidence exposes both paths; `transport_records` exposes all
   calls (including failed and validation calls). Additive references in service
   diagnostics are persisted through `Stage_preparation`,
   `bin/experimental_segment_execute.ml` and the journal diagnostic fallback in
   `bin/experimental_stages.ml`. Runner summaries/checkpoints retain their existing
   schemas for older readers. Recording failure before launch prevents launch;
   terminal recording failure vetoes otherwise-successful execution/publication
   and remains secondary to exit 17 or cancellation 143. Tests in
   `test/check_segment_service.py`, its OCaml consumer and native fixture cover
   native spawn failure, nonzero/signal/timeout/cancellation, missing/malformed
   replies, recording failures before/after launch, actual Docker argv/container
   correspondence, two distinct execution/validation records and cleanup failure
   precedence. Existing Python checkpoint/observation readers and installed public
   presentation suites continue reading the results.

4. **Public evidence-root default collided with a workspace named
   `stage-preflight`.** `flow/hardcaml_asic_flow/ocaml_backend.py` keeps the existing
   sibling default normally and selects `stage-preflight-evidence` for that exact
   collision. CLI4 options/contracts remain unchanged. The new public subprocess
   regression `test_workspace_named_stage_preflight` in
   `test/test_default_journal.py` completes synthesis, resolves operation/journal
   reports and correlates actual call/removal evidence. The installed-prefix
   wrapper's expected lifecycle suite count was updated to 12.

### Verification and handoff

Final successful commands:

```sh
dune build -j20 @install @test/ocaml-execution-transport @test/ocaml-segment-service @test/ocaml-stage-preparation @test/default-journal
python3 -B test/check_execution_transport.py --installed
python3 -B test/check_segment_service.py --installed
python3 -B test/check_stage_preparation.py --installed
python3 -B test/test_installed_prefix.py
git diff --check
```

Results: source and fresh independently linked installed transport consumers
passed **34 differential cases / 105 negatives / 19 real fake-engine cases** and
the lexical-venv check; segment service passed **70** fixture-backed cases in
source/installed modes; preparation passed **51** source/installed pipeline/API
cases; source public lifecycle passed **12** tests; full installed-prefix suite
passed **57** tests in **188.289 seconds**, including the installed 12-test public
lifecycle suite with checkout opens denied. Initial validation exposed an overly
tight five-second whole-pipeline assertion and stale wrapper test-count assertions;
these were corrected before the final successful checks. Cleanup time is measured
at its actual transport boundary, with public coverage asserting removal counts.

These are non-EDA external-process fixtures and installed compatibility checks.
No new physical runtime integration, six-stage completion, acceptance or signoff
claim is made. Next agent: exercise fresh installed physical execution and
publication validation against the selected exact image; audit the new actual
transport records, owned-container cleanup and both preflight references there.
Retained earlier physical evidence was not rewritten.

## Fresh installed native final integration and acceptance (2026-10-14)

Completed bounded sole-agent verification after reading ancestor instructions,
the latest native migration/decomposition progress and all four reviewer fixes.
Curated evidence is
[`native-final-integration.json`](../../evidence/librelane-observation/native-final-integration.json).
Detailed commands, immutable transport paths/hashes, logs and audit scripts are
retained under `/tmp/opencode/native-final-integration/`.

The actual example's development refresh installed current captured provider
bytes into private generation
`/tmp/opencode/native-final-consumer-install/generations/6018c6dbdc924a53886c90339f2368b5`.
Snapshot SHA-256 is
`dfa31575e08527330709319bb90c5f586cafa8456810beb2193d6409702b6bdf`.
The consumer linked against that generation in a fresh isolated build directory;
`ocamlfind` resolved its hardware and execution libraries there. `@all`,
`@acceptance-strict` and consumer `runtest` passed: core/wrapper directed and
seeded Cyclesim, resolution, CLI, 18 setup / 14 routing / 11 bootstrap tests,
and both generated RTL sets with 11,429 edges and negative-oracle rejection.
Every Dune invocation, including refresh-owned builds/install/probes, was
sequential and `-j20`. The orchestrator's successful provider full `runtest`
was not repeated; no implementation change was needed.

### One fresh complete execution

The preceding timed-out Magic DRC log/report were empty. Earlier successful
native Magic statistics showed **1,350.799 seconds, one thread**, supporting
one new six-stage attempt with an explicit **1,800-second per-segment budget**.
The independently built actual consumer emitted a fresh bundle and exec'd public
`stages`; an experiment-only installed launcher added `--timeout 1800` because
the consumer does not forward it. No signoff gates/configuration were overridden.
The producer's `/proc/PID/exe` was the installed native stages helper.

| Stage | Seconds including publication |
| --- | ---: |
| synthesis | 11.336407 |
| floorplan | 11.505152 |
| placement | 18.118906 |
| cts | 17.527960 |
| routing | 67.068963 |
| signoff | 1482.976326 |

Whole consumer elapsed **1,617.530909 seconds**, exit **0**. Fresh Magic DRC
finished in **1,361.833 seconds**, one thread. Workspace:
`/tmp/opencode/native-final-integration/results/signoff-1550319-34ac39c31d322c72008d8e5128521ecc`.
Execution: `execution-f0ae49b19fbd4e7dbbf9bd9e47d86721.json` inside it.

### Current refinements verified against physical tools

- Installed mapping and selected host/image import-only inventory agree on all
  **80 occurrences**, grouped **6/7/21/1/12/33**, including artifact contracts,
  gates/defaults and maintained placement setting descriptors.
- All **12** real execution/publication-validation transport launches and terminal
  records correlate request IDs/hashes, actual argv, engine/image and owned names.
  Zero process exit, strict `completed`/`validated` replies and artifact byte/hash
  checks pass separately. Native pre-publication state hashes match retained outer
  endpoint `state_out.json`; published state rewrites remain independently checked.
- Every completed physical-call cleanup has **one** removal attempt, taking
  **0.030669–0.040836 seconds**. All six schema-2 native checkpoint inspections
  pass; five actual continuation requests reference their preceding publication
  and use the declared Classic immediate successor.
- The operation receipt's relative `preflight.json` exists and is byte-identical
  to the default journal report. The default journal has **22 schema-2 events**,
  completed outcome/exit 0 and inactive writer.
- Native public watch attached live, detached on SIGINT with exit **130** while
  the producer stayed alive, then reconnected at cursor **13**, delivering exactly
  sequences **14–22** and exiting **0**. `/proc` identified the installed native
  reader. Cold inspections preserved every hashed checkpoint/journal file.
- Actual stage argv records `--cpus=20` and explicit core/thread settings. Live
  Docker inspection confirms **20,000,000,000 NanoCPUs**. Fifty retained upstream
  process-stat files report at most two peak threads; this is scoped tool evidence,
  not a claim that all upstream tools interpret every environment setting.

### Separate actual finalization and acceptance

After that one complete fresh execution, installed public finalization completed
in **677.279390 seconds**, exit **0**. Receipt:
`/tmp/opencode/native-final-integration/finalizations/20261014T040711301534Z_913453bd/operation.json`.
Runtime protocol validation, all external TT precheck checks and consumer gate
replay (**11,429 rows**) passed. Existing full policy reports **acceptance pass**:
DRC/LVS/antenna pass, mapped area **13,041.6048 µm²**, **673 cells**, setup slack
**11.675519548 ns**, hold slack **0.125028991 ns**.

An experiment-only wrapper around the installed Python finalization transport
added the same Docker caps and 1,800-second logged-command timeouts; inherited
host affinity was restricted to 20 CPUs (`nproc=20`). Live host precheck sampling
confirmed 20-CPU affinity and at most 20 threads. Acceptance/signoff policies and
collateral bytes were unchanged. Finalization request/reply artifact hashes and
receipt/results/postcheck hashes were rechecked; all **14** owned stage,
validation and simulator container names are absent. Checkpoints and the original
stage journal retain `not_evaluated` acceptance; the separate real finalization
receipt carries the earned pass. No stitched resumed history was selected.

Consumer `git status --short` remains empty, recorded pin
`1714764859274f80a9f5ad207421a04601824e99` is unchanged, and normal `.dev/asic`
activation was not altered. Older prefixes/workspaces remain retained. Python
integration used installed resources with provider-checkout opens denied; this
is an audit-hook boundary, not a kernel filesystem sandbox. Source/artifact
stamping remains unimplemented; the private development receipt is local
bookkeeping. The exact-image/path-bound scope and existing restart promises remain.
No unresolved integration blocker was found. No agents were spawned and no
staging, commits, push, stash or reset was performed.

Final consistency check: curated JSON equals the retained final audit facts;
all **18** referenced path/SHA-256 pairs and the unchanged consumer pin verify.
Provider/consumer `git diff --check` pass; consumer status remains clean.
