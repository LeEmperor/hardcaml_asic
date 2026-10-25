# PT.4: Elaborate & Resolve Resources preparation

Status: **CLI/library and independent-consumer acceptance complete, 2026-10-25**.
The [phase plan](../phase_plan.md)
owns status. This record defines the CLI-first operation, identity boundaries and
agent-sized implementation slices. No Workbench code or tests are in scope.

## User-facing contract

Preparation is a first-class operation in the overall ASIC workflow, **not** a
LibreLane physical stage. A project-owned executable constructs its OCaml project
and invokes the ASIC preparation service; the installed generic provider inspects
the retained result. The generic provider does not deserialize or build a Project.

```text
project prepare → source observation → implementation elaboration → resolution
                → immutable resource snapshot → terminal operation record

hardcaml-asic-flow preparation-inspect ATTEMPT [--current-identity ID] [--json]
```

Success means the declared project elaborates/resolves and its snapshot has been
published. It does not mean collateral files exist, tools are ready, synthesis has
retained the resources, or physical acceptance passed. No PDK/toolchain discovery,
EDA, bundle rendering/publication or simulation elaboration is needed.

The operation advertises a stable kind, phases and prerequisites suitable for a
future checklist. Its result can be inspected headlessly. It does not add a global
workflow scheduler or modify existing implementation-stage/checkpoint enums.

## Resource snapshot

Versioned structured JSON must preserve:

- Project/top, elaboration mode and inspection scope.
- Generic resource ID, request kind and exact contract, requirement, matched policy,
  implementation selection and reason, and actual elaboration role.
- Generated source roles and collateral role/reference/corner. References remain
  explicitly unresolved/unverified; they are not measured physical facts.
- Actual macro instance names verified against the circuit, and declared/resolved
  placement/supply intent. Flops have no invented dedicated macro instance.
- Explicit unavailable/not-applicable fields where linkage does not exist.

Arbitrary contracts use a tagged S-expression atom/list tree, preserving order and
structure rather than guessing a dictionary schema. Unknown resource kinds remain
inspectable without claiming backend support. Simulation snapshots may select a
macro yet elaborate the behavioral model; retain that distinction.

No fabricated partial inventory on failure: a failed elaboration is not a successful
empty design. A legitimately resource-free FIFO is a successful empty inventory.

## Identity and provenance

Keep these separate:

1. Source observation identity: normalized declared inputs, exact working bytes/
   hashes and recorded Git context. This is observation of declared files, not
   proof a compiled constructor came from those bytes.
2. Configuration identity: versioned effective declaration, target inputs, policy,
   methodology and operation. Include effective defaults; don't hash pretty text
   or only a project name as if it were an exact design identity.
3. Circuit identity: deterministic implementation RTL/circuit representation from
   the actual elaboration. Cover design changes even if resource inventory is equal.
4. Preparation identity: domain-separated identity over the above and the complete
   resource snapshot/schema. Exclude timestamps, attempt IDs and output paths.
5. Attempt identity: one execution of preparation, successful or not.

Preparation has **no bundle identity**. It must not invent one or reuse a hash from
an unrelated prior emission. Declared-source observation does not solve the pending
P6 source-artifact-stamping gate; identity coverage/limits must be explicit.

Observe declared inputs around preparation to detect changes during the operation,
or reject another equally well-defined unstable-input condition. Do not claim a
freshness check proves whole-repository or compiled-source consistency.

Historical inspection is read-only and needs no current source checkout. Default
comparison is `not_requested`. An explicit current **preparation identity** produces
`matches`, `differs`, or `unavailable` (e.g. no successful snapshot). It never rewrites
old evidence. Configuration changes require new preparation; old snapshots remain
valid historical facts. Reuse of elaboration after only a flow-profile change is
future work until dependency rules exist; v1 can conservatively recompute.

## Lifecycle and failure

```text
running → completed | failed | interrupted
```

Allocate and persist `operation.json` before calling the consumer callback, then
flush an allocation event. Execute actual reported phase boundaries, atomically
publish `resources.json`, and only then publish terminal completion with its digest,
byte count and content identity. Retrying always allocates another attempt.

Use stable phase/code/message diagnostics and preserve original structured error
detail. Do not infer resource IDs by parsing rendered errors. Successful snapshot
publication followed by failed terminal publication does not count as completion.
Inspectors verify record lifecycle, exact snapshot bytes and identity; reject corrupt
or unsupported data. Reading a valid failed attempt returns reader success, while
launching a failed preparation returns nonzero.

SIGINT/SIGTERM handling is scoped to the explicit operation runner and restored
afterward. Interruption should be retained when possible; SIGKILL/crash may leave
`running`, which must not be reclassified as completed. Cooperative phase boundaries
do not imply an arbitrary OCaml constructor is safely preemptible. There is no
cancel-by-persisted-PID command. Local atomic visibility is not an fsync guarantee.

## Agent assignments and API seam

### A — Library preparation and structured snapshot (6 jobs)

Own new `lib/elaboration/resource_snapshot.*`, `source_snapshot.*`, root
`resource_preparation.*`, Project additions, public exports and focused library
tests. Reuse/share source-observation helpers with Bundle only if existing bundle
bytes/identities remain unchanged.

- Pure `Resource_snapshot.of_elaborated/of_resolved`, JSON encoding/strict decoding.
- `Project.prepare_resources` implementation: source observation, Implementation
  elaboration once, resolution once, circuit/resource/config identities; no bundle.
- Structured phase-specific failure and an optional phase callback for B's lifecycle.
- Identity verification/strict loading reusable by B without re-hashing via a
  different JSON codec. Cover deterministic identities, arbitrary resource contracts,
  simulation roles, flop/exact/fallback/unsupported requests and input mutation.
- Write `resource-preparation-handoff.md` early with concrete signatures/wire shape.

### B — Durable execution service and generic inspector (6 jobs)

Own new preparation execution/storage/reader modules, installed inspection command,
CLI capability, and focused execution/public-protocol tests. Do not edit physical
stage enums or A's library files.

- In-process typed consumer seam: allocate first, then invoke a closure that builds
  the project and calls A's API. Project-specific selection metadata is caller data,
  not instructions to launch shell commands.
- Durable running/terminal records, atomic snapshot publication, scoped interruption
  and flushed allocation/terminal JSONL. Public errors remain structured.
- `hardcaml-asic-flow preparation-inspect ATTEMPT --json` and optional
  `--current-identity ID`; human-readable summaries too. Capability `preparation1`.
- Historical readers call A's strict identity verifier; snapshot digest covers exact
  retained bytes independently of execution-record serialization.
- Versioned overall-workflow operation descriptor marks this as preparation and
  states the result/readiness boundary. No generic scheduler or driver subprocess
  protocol is required in this slice.
- Tests: allocation-before-failure, publication interruption, corruption, invalid
  lifecycles, historical independence, match/difference, two retries and signal cases.

### C — Independent project CLI acceptance (6 jobs)

Own `hardcaml_asic_example` CLI, focused acceptance and documentation. Preserve
the existing memory/evidence/FIFO work and all active SRAM/Workbench generations.

- Thin memory and resource-free FIFO preparation commands using A/B APIs; historical
  inspect delegates to the public reader. No consumer selection/schema/storage clone.
- Cover explicit flops, exact SRAM, fallback and unsupported 128×16 Exact, plus
  no-resources FIFO and a simulation-role view where provided.
- Capture a provider in separate `.dev/asic-prepare` and build `_build_prepare`
  at six jobs after A/B handoff. No physical EDA, PDK or Workbench needed.
- CLI acceptance: deterministic snapshots, source/config/circuit changes, preserved
  historical results, failure diagnostics, no output from live view, corruption
  rejection and source-unavailable inspection. Retain a compact acceptance record.

### Coordinator

Resolve shared seams, keep docs current, serialize shared-checkout Dune, review
integration and run required broader tests after focused checks. No mutation of
Git publication state. Three agents at six jobs each plus two reserved; all ASIC
Dune uses `flock /tmp/opencode/asic-preparation-build.lock` and explicit `-j6`.
Independent captured example builds stay within the same 20-job pool.

## Acceptance / progress

### Delivered

- `Resource_snapshot.of_elaborated/of_resolved` provides generic structured
  inventory, tagged contracts, selection/reason/policy, actual elaboration role,
  resolved instance linkage, collateral references and physical intent.
- `Project.prepare_resources` observes declared sources around one Implementation
  elaboration/resolution, retaining separate source/configuration/circuit identities
  and the deterministic full preparation identity. No bundle is rendered or emitted.
- `Preparation_service.run/run_cli` allocates durable attempts before project
  construction and publishes checked success or failure/interruption evidence.
- `hardcaml-asic-flow preparation-inspect` verifies retained results independently
  of current project/source/PDK/tool availability. Optional explicit identity
  comparison does not mutate history. Public capability: `preparation1`.
- The memory and FIFO example CLIs provide `prepare`, nonpublishing `preview`,
  and pure `resources` inspection, including explicit Simulation mode. A successful
  FIFO has zero registered resources; failure has no successful inventory.

API/wire details are in the [handoff](resource-preparation-handoff.md), operating
semantics in the [public guide](../guides/resource-preparation.md), and consumer
commands in [the example guide](../../../hardcaml_asic_example/docs/resource_preparation.md).

### Review corrections and lifecycle guarantees

Independent review found and corrected five concrete issues before final acceptance:

1. Terminal-publication cancellation now has an explicit commit cutoff. SIGINT/
   SIGTERM are blocked during the final save/readback, previous handlers/mask are
   restored, and pending signals are delivered normally rather than discarded.
   A default handler can terminate delivery after a valid terminal commit. This
   does not rewrite committed success as interruption.
2. Evidence leaves must be bounded regular files, not symlinks/FIFOs. Nonblocking
   open and pre/post type/identity checks prevent a substituted pipe hanging a reader.
3. Malformed callback failures are normalized inside the protected operation to
   durable `preparation_exception`, not left as an unexplained running attempt.
4. Workflow descriptor v2 records actual phase order: `circuit → snapshot →
   source_after`. Exact original v1 descriptors remain readable as history.
5. Terminal publication is reread byte-for-byte and strictly decoded before an
   outcome returns. Silent writer corruption cannot return completed/0.

An independent follow-up reran the original repros against the corrected modules:
all five findings are resolved, including pending-signal delivery on verification
failure and deterministic regular-file-to-FIFO/symlink replacement races.

Source comparison observes declared files and recorded Git context; it does not
prove the binary was compiled from those source bytes. Circuit identity covers
the actual elaboration. No P6 source-stamp, bundle identity, collateral readiness,
synthesis realization or physical acceptance is implied by preparation success.
Schema identity verification is integrity checking, not producer authentication.

### Final installed consumer evidence

Provider generation:
`hardcaml_asic_example/.dev/asic-prepare/generations/a5de7cbfcc464e13ae1b5a5db6e39068`.
Captured development source SHA-256:
`549cf74e17b4c8af34a7133ea3d983786adf5ce6c4d4e8914f62aff0a05e2f2a`.
No tracked pin or existing SRAM/Workbench generation was changed.

[Retained acceptance](../../../hardcaml_asic_example/acceptance/preparation/README.md)
contains original and final captures, portable successful/failed/FIFO attempts,
ordered events, executable/provider receipts and historical byte/mtime comparisons.
Final capture: **89 focused checks pass**. Exact synthesis preparation identity:
`fd456fbf5035f7b86d0816d78a6d6323932f73c761ae4d522d0a0cc5e7593fbb`.
Resource-free FIFO identity:
`8cedb61350e9bf3d9d22ed93a0af8295dd3433886a9bd0d23563ed10a7709d9b`.
Both payload identities/bytes remain unchanged across the descriptor/lifecycle fix.

The final reader inspected original v1 Exact/failure/FIFO records, compared matching,
different and unavailable identities, and preserved all original archive hashes,
sizes, modification times and paths. Consumer acceptance also exercises independent
source/config/circuit changes, source removal, corrupt data, FIFO-file rejection,
durable failures, fresh retries and publication refusal. No physical EDA is involved.

### Verification commands and outcomes

```sh
# ASIC checkout; targeted aliases were also run during implementation/review.
flock /tmp/opencode/asic-preparation-build.lock \
  opam exec --switch=5.2.0+ox -- dune runtest -j12

# Example checkout, with the isolated preparation provider selected in OCAMLPATH.
opam exec --switch=5.2.0+ox -- dune runtest --build-dir _build_prepare -j6
```

Both full suites pass. The ASIC suite reports an unavailable historical retained
finalization fixture separately; the example retains one explicit opt-in installed-
native fixture skip. Focused provider checks include library snapshot/identity
tests, actual public CLI/lifecycle tests, **43 CLI tests** and **17 packaging tests**.
The final example acceptance ran directly and through `@scripts/preparation-test`.
The coordinator also inspected the final Exact result through the installed human
CLI, observing resource `program`, stock SRAM selection and actual instance
`hc_resource_7_program` with unresolved-reference and intent labels intact.

Maximum concurrent build allocation was **18** (ASIC 12 + isolated example 6),
with shared-checkout Dune serialized. No EDA/PDK provisioning, Workbench changes or
tests, git staging/commit/push, or historical physical-evidence changes occurred.

### Scope boundary / next work

PT.4a–c are complete for the CLI/library preparation contract. The overall-operation
descriptor is ready for a client checklist, but no Workbench rendering, scheduler,
provider-owned project subprocess launcher or automatic caching/invalidation was
implemented. Preparation is recomputed conservatively; there is no implicit link
to a separately emitted bundle. PT.5 owns general requested-versus-realized mapping
and implementation measurements; Workbench views remain PT.6.
