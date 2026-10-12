# hardcaml_asic phase plan

Current checkpoint: 2026-10-12 consumer refresh/activation and real-checkout emitter
acceptance completed, following public API rename, interface hardening and the FIFO specimen.
This is the **only active queue**. [Architecture](architecture.md) owns boundaries;
[P6 details](development/p6-implementation-plan.md) retain the detailed specification
and exact delivery evidence. Proposed new work below awaits design discussion.

## Start here

1. Resolved-build boundary hardening is implemented with the recorded
   [acceptance evidence below](#resolved-build-boundary-hardening-evidence).
2. The [independent Dune specimen](../../hardcaml_asic_example/README.md) delivers
   the fixed FIFO contract/core, scoreboard, TT wrapper/declaration and emitter,
   with [PDK-free acceptance evidence below](#controlled-fifo-development-specimen-evidence).
   It now uses a recorded ASIC baseline plus an explicit development override,
   with isolated library/CLI installations and plain activated builds; see the
   [refresh/emitter closeout](#consumer-refresh-and-real-checkout-emitter-closeout).
   Read the [source-breaking migration and rename evidence](#public-api-rename-migration-and-evidence)
   before adopting this provider.
3. Next agreed work: concrete provider observation contract examples for
   runs/operations/steps/results, then prove the LibreLane seam; follow the
   dependencies below for subsequent P6 identity/installation work.

This queue records future ordering, not authorization to proceed beyond the
current bounded review/documentation slice.

The earlier blanket "finish P6, then migrate scaf" queue is superseded. Do not
execute archived handoff prompts. No feature, source stamp, specimen, observation
contract or new test pass was claimed by the earlier documentation-only checkpoint.
The subsequent FIFO delivery is recorded below; provider examples remain
unimplemented.

## Status and preserved history

| Track | Current status | Evidence / detail |
| --- | --- | --- |
| ASIC P0–P5, M1–M3 | Complete; retain the working lifecycle/resources/bundle/flow foundation | [Original tasks and completion records](archive/phase-plan-through-p6.4b.md) |
| ASIC P6.1/P6.2 | Complete: operation-aware acceptance and complete input preservation | [Original P6 records](archive/phase-plan-through-p6.4b.md#11-p6--shared-tooling-distribution), reporter/archive suites |
| ASIC P6.3 | Complete: shared dispatcher contract | [P6.3 completion](development/p6-implementation-plan.md#11-p63b-completion-evidence) |
| ASIC P6.4a/P6.4b | Complete: packaging, shared routing and installed-operation coverage | [P6.4a](development/p6-implementation-plan.md#12-p64a-completion-evidence), [P6.4b](development/p6-implementation-plan.md#13-p64b-completion-evidence) |
| ASIC P6.4 parent | Open only for source-access-denied installation evidence | ASIC P6.6a supplies it; do not redo packaging |
| ASIC P6.5a/b/c, P6.6a/b | Open | Scope and dependencies below |
| ASIC P7.1–P7.6 / M4 | Open historical migration; deferred from current queue | [Original tasks](archive/phase-plan-through-p6.4b.md#12-p7--consumer-migration-and-legacy-retirement), [backlog](backlog/README.md) |
| ASIC S.1/S.3 | Complete, with qualified S.3 interpretation | [SRAM index](sram/README.md) |
| ASIC S.2 | Open; S.2a complete, S.2b research partially resolved | [SRAM checkpoint](sram/sram-status.md) |
| ASIC S.4 | Gated, unimplemented | Requires S.2 capability gates |
| ASIC T.1 | Open, independent toolchain follow-up | Scope below |
| Provider observation | Proposed, not implemented | [Architecture](architecture.md#8-provider-observation-direction) |
| Resolved-build boundary hardening | Implemented; full runtest passes | [Evidence below](#resolved-build-boundary-hardening-evidence) |
| Public API rename | Implemented; provider and FIFO acceptance passed, active documentation migrated | [Migration and evidence below](#public-api-rename-migration-and-evidence) |
| Controlled-FIFO development specimen | Contract/core, scoreboard, TT wrapper/declaration and emitter delivered; PDK-free acceptance | [Original evidence](#controlled-fifo-development-specimen-evidence), [consumer README](../../hardcaml_asic_example/README.md) |
| Consumer dependency refresh / emitter | Delivered: recorded ASIC baseline, explicit development override, isolated library/CLI, activation and real-checkout acceptance; record awaits owner commit | [Closeout below](#consumer-refresh-and-real-checkout-emitter-closeout), [commands](development/consumer-dependency-workflow.md#implemented-commands) |

The earlier source-review baseline was clean ASIC `f6e8fd7` before documentation
consolidation. Workbench has owner changes in its active architecture and construction
plan; those files are not modified here. Its P0–P7 numbering is independent.

Historical task text remains in the archive rather than being rewritten to match
new goals. For example, old P2/P3 records describe maximum-only I/O constraints;
current `Timing.Delay` and rendering support both minimum and maximum. The
[target reference](reference/target-reference.md) describes the implemented API.

## Core review before further implementation

Recommendation for discussion: **bounded hardening, not a P0–P5 rewrite**.

- Keep declaration/elaborated-project/resolved-flow/bundle separation, explicit resource policy,
  deterministic identities, behavioral/flop conformance and ordinary CLI operation.
- Implemented `Resolved_flow.mli`: only resolution constructs a resolved flow.
  An external consumer can inspect/use results but cannot construct or update
  them; both existing example bundles remain byte-identical to the pre-change
  emitter for identical inputs. Invalid target/timing/override tests still pass.
- Define the optional generator identity and artifact inventory for ASIC P6.5a
  before coding it. Later internal file moves change an inventory digest normally;
  they do not make source stamping throwaway work.
- Refactor runner/collector publication boundaries with the observation slices,
  preserving the current CLI and report/archive acceptance tests. Do not first
  rewrite the whole runner or generalize every target/resource API.

The bounded interface slice and subsequent FIFO specimen are delivered, without
changing historical M3 or P6 completion criteria. Provider observation contract
examples remain next work; no provider observation or further P6 implementation
is included.

### Resolved-build boundary-hardening evidence

Historical names and commands in this record are preserved as executed. The
subsequent [API migration](#public-api-rename-migration-and-evidence) gives current
module and checker paths; it does not retroactively rename this hardening pass.

2026-10-12, starting from clean `main` at `12a428b`:

- `Resolved_build.t`, `Setting.t` and `Delay_ns.t` are private records. Public
  readers, owner constructors, S-expression printers, `resolve`, expected ports,
  protected-key inspection and capability diagnostics remain available. Internal
  assembly/validation helpers are hidden; no unchecked constructor is exported.
- `dune build` and `dune build @install`: pass using the existing `5.2.0+ox`
  environment, with no dependency or pin changes and no installation.
- `python3 test/check_resolved_build_api.py --baseline-emitter
  /tmp/opencode/resolved-build-baseline.exe`: pass. The independently compiled
  temporary Dune consumer uses this checkout's public install tree, exercises
  resolution, record reads/patterns, JSON inspection and bundle render/write.
  Eight negative compilations reject construction and updates of the result,
  target/settings replacement, and setting/delay construction or updates. Each
  checks the compiler's private-type diagnostic, not just a failed exit code.
- Before editing, `dune build` produced the baseline emitter, copied from
  `_build/default/examples/tt_bundle_example.exe` to the temporary path above.
  The test runs that saved executable and the newly compiled consumer against
  the **same current declared source bytes and Git state**. Both observable and
  memory bundles have all **43 files byte-identical**, including copied inputs,
  synthesis/simulation RTL, SDC, configuration, info.yaml and manifest/identity.
  This compares old and new implementations, not merely same-build determinism.
  Manifest SHA-256: observable
  `62dbfe222e6e8a833058f6d6daf5de3ddb3cd27d3c4f3fa3fcff8e1c597e8d32`;
  memory `04391e190bcfb061a0fa137244591e823ec824dd1ee748cfc0970b4025789870`.
  These hashes describe this source-input snapshot, not a published release.
- `dune build @test/runtest-hardcaml_asic_test --force`: pass, including unchanged
  invalid target, timing and protected-override rejection tests.
- Initial attempt, `PATH="/tmp/opencode:$PATH" dune runtest --force`: OCaml tests
  and all 96 Python flow/report/archive/CLI/packaging tests passed. The full command
  was blocked by the session's read-only Git guard rejecting `check_bundle.py`'s
  `git init`; that suite also requires temporary `add`/`commit`. No Git mutation
  was allowed under the initial interpretation. The before/after comparison above
  supplied separate bundle evidence at that point.
- Follow-up on 2026-10-12: the owner clarified that normal test scripts may perform
  their own Git operations, including synthetic temporary fixture commits; agents
  must not invoke Git directly. The full `dune runtest --force` then **passed
  (exit 0)** with the subprocess-only environment below. The fixture lives in
  `TemporaryDirectory(prefix='asic-bundle-test-')`; its synthetic author and
  committer are both `Bundle test <bundle@test.invalid>`, with commit message
  `baseline`. No project-code commit or push was performed.
  Python suites reported **17 + 16 + 20 + 28 + 15 = 96 tests, all OK**; OCaml
  tests also passed. Bundle integration reported:
  `bundle determinism, provenance, staging, hashes, RTL and toolchain.lock passed`.
  `/usr/bin/iverilog` and `/usr/bin/vvp` were available, so all four generated-RTL
  simulations ran (observable and memory, each synthesis and simulation source
  sets); none were skipped. This resolves the earlier full-suite qualification.

Exact successful invocation from the repository root (only the old guard directory
is removed from the child PATH; the installed OCaml toolchain remains available):

```sh
python3 - <<'PY'
import os
import shutil
import subprocess

env = os.environ.copy()
env['PATH'] = os.pathsep.join(p for p in env['PATH'].split(os.pathsep) if p != '/tmp/opencode')
env.update(GIT_AUTHOR_NAME='Bundle test', GIT_AUTHOR_EMAIL='bundle@test.invalid',
           GIT_COMMITTER_NAME='Bundle test', GIT_COMMITTER_EMAIL='bundle@test.invalid')
for tool in ('dune', 'git', 'iverilog', 'vvp'):
    print(f'{tool}: {shutil.which(tool, path=env["PATH"])}', flush=True)
raise SystemExit(subprocess.run(['dune', 'runtest', '--force'], env=env).returncode)
PY
```

The boundary still trusts Build's declaration/elaboration invariants and does
not freeze exposed Hardcaml circuit internals. Target references are not checked
against physical files. No EDA flow, fresh physical run, shared installation or
installed-release completion is claimed. Historical IDs and gates below remain.

### Controlled-FIFO development-specimen evidence

Historical pre-refresh evidence follows. The later
[closeout](#consumer-refresh-and-real-checkout-emitter-closeout) supersedes its
unpinned/manual-override and missing-real-checkout qualifications, preserving the
original commands and results.

2026-10-12, preceding sequential implementation/acceptance passes, using explicit
`OCAMLPATH=/home/wayne/devel/jane/hardcaml_asic/_build/install/default/lib` to
select the hardened public development tree:

- In the example, `dune build @all`, `dune runtest --force` and
  `dune build @acceptance-strict --force` passed. Core and TT wrapper each passed
  7,330 directed and 20,017 seeded/reset/drain edges; public resolution passed.
  Earlier core seed 42 with 100,000 traffic cycles passed 100,018 total edges.
- Actual emitted synthesis and simulation RTL were compiled separately; each
  passed 11,429 edges (7,330 directed plus seed 20261012 with 4,096 traffic cycles
  and reset/drain) and rejected a deliberately corrupted expected response.
- Bundle repeat bytes, inventory/hashes/config/SDC, two dirty-source probes and
  five failure cases passed. Temporary fixture checks assert both author and
  committer `Bundle test <bundle@test.invalid>`, message `baseline`, and no remotes.
- This bounded source review found no substantial defect in full old-head
  replacement, empty no-bypass, disabled reset priority, pre-/post-edge sampling,
  independent list-based scoring, emitted-RTL replay or fixture attribution.
  Already-passing suites were not repeated for this documentation slice.

See the [consumer README](../../hardcaml_asic_example/README.md) for the delivered
contract, pin map, commands and acceptance details. Owner initial ref
`8e4577f6c72cc689cbc92daeb5f8ae083cf970e0` now exists. That ref alone proves neither
a clean working tree nor a dependency pin. The acceptance above used an explicit
synthetic fixture source root; genuine example-root emission acceptance has not
been recorded here. A committed dependency pin remains absent.
This evidence establishes an unpinned development specimen, not source-artifact
identity, independent installed/pinned-provider acceptance or physical acceptance.
Provider observation contract examples and ASIC P6 gates remain open.

### Public API rename: migration and evidence

2026-10-12, subsequent bounded rename and consumer migration:

| Previous OCaml API | Current OCaml API |
| --- | --- |
| `Build` | `Elaborated_project` |
| `Resolved_build` | `Resolved_flow` |
| Resolved record field `build` | `elaborated_project` |
| `Bundle.render ?simulation_build` | `Bundle.render ?simulation_project` |

This is **source-breaking, with no compatibility aliases**. `Project.elaborate`
and `Project.elaborate_for_flow` keep their names, as does `Target.Resolved`.
`Elaborated_project.t` remains abstract; `Resolved_flow.t`, `Resolved_flow.Setting.t`
and `Resolved_flow.Delay_ns.t` remain private records. The lifecycle is declaration
→ elaborated project (Hardcaml circuit plus metadata, intent and resources, no
synthesis) → resolved flow (validated concrete TT/LibreLane facts plus that
elaborated project) → bundle → separate execution.

True emitted build/bundle/run identities and persisted `identity`, `build_identity`,
schema, field ordering and hashing remain unchanged. Workbench's build/run identity
types describe different concepts and are untouched. Source moves or revisions
legitimately change provenance; byte-equality evidence below holds both executable
inputs to the **same source bytes, paths, revision and state**.

Current source navigation: [`elaborated_project.mli`](../lib/elaborated_project.mli),
[`resolved_flow.mli`](../lib/resolved_flow.mli),
[`test_resolved_flow.ml`](../test/test_resolved_flow.ml), and
[`check_resolved_flow_api.py`](../test/check_resolved_flow_api.py).
The current external checker command is
`python3 test/check_resolved_flow_api.py --baseline-emitter PATH`.
Old commands, hashes, task IDs and hardening names above and in the historical
archive remain evidence of their original passes, not current command instructions.

Recorded completed acceptance from the implementation passes (not rerun for this
documentation review):

- Provider `dune build @all @install`, focused OCaml tests, the independent public
  consumer and eight private-API rejection cases passed. Full `dune runtest --force`
  passed: 96 Python tests, OCaml tests and four Icarus simulations.
- Saved pre-rename provider emitter
  `/tmp/opencode/api-slice1-baseline-6lta960s/provider-prechange.exe`, SHA-256
  `f61dcc698f74bf7d88f62f10c1420e9a6f700944b05412d4d5d13c529881b948`,
  versus the independently built new consumer: all 43 files byte-identical for
  each observable/memory bundle on the same input snapshot. Source-token comparison
  with the original snapshot found only intended identifiers, comments, whitespace
  and simulation-build diagnostic wording; persisted serialization was unchanged.
- FIFO migrated `bin/emit_bundle.ml`, `asic_test/resolution_test.ml`, README and
  optional acceptance `--baseline-emitter`. With explicit
  `OCAMLPATH=/home/wayne/devel/jane/hardcaml_asic/_build/install/default/lib`,
  `dune build @all`, `dune runtest --force`, `dune build @acceptance-strict --force`
  and the baseline comparison passed. Core and wrapper each passed 7,330 directed
  plus 20,017 seeded edges. Separately compiled synthesis/simulation RTL each
  passed 11,429 edges and rejected a corrupted oracle.
- Saved FIFO emitter
  `/tmp/opencode/api-slice1-baseline-6lta960s/fifo-prechange.exe`, SHA-256
  `6110e955119d0d0b9c78bfd2435a862d2ec58ff5b8f82fcddc61c1ef23609ed1`,
  was hash-verified before execution. Old/new emitters used the same synthetic
  fixture, with author and committer `Bundle test <bundle@test.invalid>`.
  All 18 files, including manifest, were byte-identical: each generated RTL file
  11,851 bytes, config 1,343, SDC 1,275 and info.yaml 1,656.
  Fixture revision: `773f9511eb48414cc87399adcb3ebedcd02a3f94`;
  bundle identity: `41094b14026bb8040fc82ad9d59de38325e1b06bfe8a864573b00b179291310f`.
  These identify the tested snapshot, not a published release or pin.

Independent consistency review of the renamed library and current FIFO source
found no functional rename defect: resolution still gates rendering, simulation
is elaborated separately, and serialization/identity handling retains its existing
meaning. Existing limitations of the conventional `Private.create` and exposed
Hardcaml circuit internals remain as described in the architecture.
One pre-existing comment typo remains at `lib/project.ml`'s Private-convention
explanation (`Built.t`); it is not a public type or compatibility alias.

Final read-only review checks: 41 Markdown files and 369 local link destinations,
no broken anchors on available files and no whitespace errors in the ten changed
documents. The 39 unavailable link occurrences all refer to historical scaf
material. Archive edits change only link destinations (eight moved-source links
and one renamed heading anchor); labels, prose, commands and hashes are preserved.
Active old-API matches are historical hardening records, explicit migration notes
or ordinary English, not stale current instructions. Independent token comparison
of all 33 library OCaml files against the saved original confirms only the intended
identifier/diagnostic changes after excluding comments and whitespace. Migrated
FIFO OCaml tokens likewise match; its core, wrapper, scoreboard and other baseline
files retain their bytes. All 2,535 baseline-tracked flow, script, evidence,
experiment, toolchain and package/dependency files checked retain their SHA-256.
This final slice changes documentation only and reruns no build or test suite.

The absence of a consumer record and genuine-root emission in this rename pass
is superseded by the later [closeout](#consumer-refresh-and-real-checkout-emitter-closeout).

**External migration blocker:** `hardcaml_protemu` still uses `Build` and
`simulation_build`. It requires a separate source migration before adopting this
provider. Its source and dependency pin have not been changed. No published
release/pin, genuine example-root emission or physical acceptance was claimed by
that rename pass.

### Consumer refresh and real-checkout emitter closeout

2026-10-12, completed bounded workflow from the
[implementation contract](development/consumer-dependency-workflow.md):

- Consumer `asic-dependency.json` records package `hardcaml_asic`, repository
  `https://github.com/LeEmperor/hardcaml_asic.git`, revision
  `1714764859274f80a9f5ad207421a04601824e99`. Recorded mode captures committed bytes;
  development mode explicitly captures relevant current files without moving the
  baseline. The record is not yet committed by the owner.
- `scripts/asic_dependency.py` installs both library and CLI into consumer-owned
  isolated generations using the available toolchain. Locking, capture checks,
  public API/runtime validation, exact ocamlfind resolution and an external Dune
  link probe precede atomic selection publication. Failed refresh leaves the
  previous selection/receipt usable; old and failed generations are retained.
- Initial real refresh exposed two Dune issues, fixed before successful publication:
  `-p` already supplies `--root .`, and an absolute `--build-dir` produced invalid
  installed archive paths. The build now uses capture cwd and relative `_build`;
  validation rejects temporary-source metadata and links an external executable.
  All **13 setup tests passed**, covering failure preservation, source modes,
  contention, unsafe paths, spaces/apostrophes and repeated/stale activation.

Actual successful generations under example `.dev/asic/generations/`, each with
`receipt.json`, `activate.sh`, installed library and CLI:

| Mode | Generation | Selection |
| --- | --- | --- |
| recorded | `2cd5adeb421c4b58b288f1f29e802932` | Preserved baseline installation |
| development | `481514db03934614a1ca4e25815e2bac` | Published `current` |

Both observed provider base `1714764859274f80a9f5ad207421a04601824e99`.
`.dev/provider-inputs.json` records that the development capture differed only in
`docs/README.md` and the newly added development note; no provider code or source
commit changed. After publication, a stale activated shell still resolved the
recorded library/CLI. Re-sourcing selected development via ocamlfind, `command -v`
and status (`active_is_published` / `active_library_path_is_first` true).
Receipts describe refresh-time bytes; this later provider documentation closeout
does not require another refresh.

Completed acceptance (not rerun for this final documentation review):

- After recorded activation, plain `dune build @all`, `dune runtest --force` and
  `dune build @acceptance-strict --force` passed. Core and wrapper each passed
  **7,330 directed + 20,017 seeded edges**; resolution and synthetic bundle checks
  passed. Separately compiled synthesis/simulation RTL each passed **11,429 edges**
  and rejected the corrupted oracle.
- Development refresh ran fresh API/link probes; activated plain build passed.
  The docs-only capture difference did not justify another full functional suite.
- Real-checkout acceptance used the development-built emitter, with this exact
  invocation from `/home/wayne/devel/jane/hardcaml_asic_example`:

```sh
python3 acceptance/check_bundle.py \
  --emitter _build/default/bin/emit_bundle.exe \
  --exporter _build/default/acceptance/export_trace.exe \
  --source-root /home/wayne/devel/jane/hardcaml_asic_example \
  --bench acceptance/replay.v --require-rtl --real-checkout \
  --work-dir .dev/emitter-checks/slice2
```

It passed **all 19 files byte-identical**, every copied input/hash, actual revision
and input status, plus 11,429 RTL edges and negative-oracle rejection for each
source set. Preserved `.dev/emitter-checks/slice2/` contains `first/`, `second/`,
`evidence.json`, `trace.txt`, `bad.txt` and compiled replays. Choose a fresh directory
for future runs. Actual example revision:
`b68a68a08214adc6d35fbb7d28effc9d475d3b74`; declared dirty inputs were `README.md`
and `asic/declaration.ml`, with untracked `asic-dependency.json`. Bundle identity:
`ce78b2ff5b66cf1d4c0a2e0c11c0257cc51230880ecda816254a1dc2247eb2c7`.
The example README/input bytes were preserved during this final review.

Independent review of implementation, tests, activation, receipts and emitter
acceptance found no blocking defect in the bounded workflow. Installed metadata
uses final-generation sections and relative archive names; prior plain builds
passed after capture cleanup. Status distinguishes published selection from the
caller's activation marker/path, not proof of arbitrary executable linkage.

Final non-Git read-only checks passed: five changed documents, 89 local link
destinations/anchors and whitespace; preserved 19-file bundle equality and
manifest hashes/provenance; every declared input still matches its preserved copy;
both installed generations retain their archives and final-prefix metadata.
No build/test suite was repeated for this documentation-only closeout.

Both installed CLI version reports remain `0.1.0`, unstamped, source state
`unknown`. The receipt is honest local selection metadata; the copied dependency
record is a source expectation, not proof of linked-library identity. Full
environment locking, clean release/publication, embedded P6.5 identity,
source-access-denied P6.6 and physical acceptance are not delivered by this work.
Provider observation remains proposed. No blocker remains for explicit refresh,
activation, plain consumer builds and emission; see the
[user commands](development/consumer-dependency-workflow.md#implemented-commands).

## ASIC P6 — Shared tooling distribution

Keep existing IDs. The detailed acceptance matrix and original commands are in
[development/P6](development/p6-implementation-plan.md#7-ordered-bounded-implementation-units).

- [x] **P6.1** — Operation-aware reporting. Synthesis and full-flow policies remain
  distinct; missing/contradictory evidence cannot become a pass.
- [x] **P6.2** — Complete immutable-input archives with integrity and restoration.
- [x] **P6.3** — Shared installed-command contract and fixed execute semantics.
- [ ] **P6.4** — Installed CLI/runtime assets; **P6.4a/b delivered**, parent waits
  for P6.6a's filesystem source-denial check.
- [ ] **P6.5a — Source-artifact identity.** One deterministic validated source stamp
  embedded in OCaml and Python, Git-free source builds and additive bundle
  `generator_identity`. Test clean/dirty/untracked/unknown inputs, actual opam
  source/export behavior, tampered inventory, determinism, library/CLI equality
  and manifest coverage. No runtime Git guessing or version-as-revision shortcut.
- [ ] **P6.5b — Dependency and waiver records.** After P6.5a: explicit expectations,
  generator/executor comparison, recorded exceptions and historical-read behavior.
  Old analysis does not require matching the current executor's identity. Preserve
  existing records through archive/restoration.
- [ ] **P6.5c — Provisioning/data authority.** After delivered P6.4a: strict requested
  Python behavior, installed lock authority, explicit Docker/native scope and
  read-only/check/offline semantics. PDK-free stub tests prove no implicit network
  or writes in check mode; no baseline pin change is implied.
- [ ] **P6.6a — Independent installation acceptance.** After P6.4b and P6.5a/b/c:
  fresh prefix, unrelated consumer, source access denied, positive/negative
  validation/report/archive/restoration and exact artifact identity. PDK-free.
- [ ] **P6.6b — Documentation and recorded candidate.** After P6.6a: align operating
  commands, run applicable build/test/package checks and record the deliberately
  published candidate. Commit/publication/pin changes remain explicit owner actions.

**P6 exit:** one identified source artifact installs library and generic flow
tooling, works independently of the checkout and preserves P6.1/P6.2 guarantees.
This is still worthwhile when internal observation implementation evolves.

## Proposed provider sequence — not a new phase numbering scheme

After the core/specimen discussion, adopt bounded task IDs here rather than in
another planning document. Every provider slice must work without Workbench.

| Slice | ASIC deliverable and acceptance | Other repository ownership |
| --- | --- | --- |
| Contract and feasibility | Two-run examples with distinct operation/occurrence/attempt/result IDs, versions and capabilities; demonstrate an internal-step seam without copying the flow engine | Workbench decoder/reducer fixtures; example design/constraint selection |
| Durable catalog and outer observation | Explicit stores, list/inspect, early request correlation, stored operation outcomes, consistent snapshot/cursor and replay; late independent readers observe two runs | Workbench P1 adapter/P2 derived catalog and early run display |
| Internal step lifecycle | Actual starts/completions/failures/skips/interruption and repeated occurrences, including deferred errors; earlier steps visible while a later one runs | Workbench execution feature/views |
| Incremental results | Synthesis resources, then one intermediate timing result, then checks; origin/constraints/corner/units preserved and data complete before publication | Workbench timing/resources/check projections |
| Preservation and installed acceptance | History and referenced evidence survive later failure, archive/restore and scratch cleanup; independent readers, conflicting operations, duplicate/truncated updates and crash tests | Workbench restart/reconnect and cache invalidation |
| Real specimen handoff | Validate actual supported runtime/container and descendant cancellation; retain final-JSON compatibility and existing acceptance policy | Example pins deliberate provider revision, supplies real flow/test evidence; Workbench live acceptance |

The contract/probe must settle writer ownership/locking, ordering, snapshot/cursor
consistency, duplicate requests/updates, incomplete writes, stale producers and
preservation policy before durable implementation. There is no chosen interception
mechanism yet. Metric equality cannot establish measurement origin. Archive policy
must cover advertised evidence, not just final metrics. Failed-run diagnostics
need an explicit export contract separate from completed-run archives.

Example fixture: build B has runs R1/R2. R1 publishes synthesis and intermediate
timing, then fails routing; R2 skips a gated step and is interrupted at a later
occurrence. A later collection attempt revises R1 without rerunning implementation.
Include inherited timing and equal-valued new measurements with different origins.

## Dependency triage

| Milestone | Genuine blockers |
| --- | --- |
| Contract fixtures, Workbench reducers/window behavior | Agreed identity/state examples; not P6 completion or a real EDA environment |
| Example Dune/design/unit tests | Delivered with recorded ASIC baseline plus explicit development refresh/activation; no PDK required; consumer record awaits owner commit, full environment lock absent |
| Early discovery and coarse live progress | Catalog/correlation/durable outer observation |
| Truthful internal progress | Demonstrated LibreLane seam; file absence alone is insufficient |
| Intermediate timing/resources | Step-aware extraction, producer provenance and complete snapshot publication |
| Dependable installed provider release | Applicable P6.5/P6.6 gates plus new installed observation acceptance |
| Real-flow handoff | Usable supported runtime, example pin/constraints and real evidence; local Python 3.12 source inspection does not validate requested 3.11 execution |

ASIC P6.5a does not technically block observation prototypes. P6.5b needs its
identity, while P6.5c may progress independently. Old consumer migration, SRAM,
Nix environment redesign and unrelated tool fixes are not blanket prerequisites.

## ASIC P7, S and T — retained independent tracks

**P7.1–P7.6:** retain their original migration goals and M4 relationship in the
[historical definitions](archive/phase-plan-through-p6.4b.md#12-p7--consumer-migration-and-legacy-retirement).
P7.1 installs the consumer's recorded revision; P7.2 replaces vendored operations;
P7.3 migrates coverage before deletion; P7.4 makes adopted checks routine; P7.5
validates synthesis/full/restoration; P7.6 closes migration documentation.
They are deferred for that consumer, not renamed as the new example's tasks.

**S.1–S.4:** capability inventory, behavioral/target compatibility, bounded flow
feasibility, then a conditional exact backend. The [SRAM area](sram/README.md)
retains detailed gate status and all investigations. S.3's acceptance allows a
qualified feasibility or evidence-backed deferral decision; it is not signoff.

**T.1:** correct the upstream ABC driving-cell constraint boundary (cell name vs
OpenSTA-style cell/pin), with a focused regression, explicit corrected revision
and mapped-synthesis comparison. Historical area results retain their stated
qualification. It blocks only measurements demonstrably dependent on that defect;
no shared venv patch or silent baseline pin advance.

## Recording future work

Keep completed IDs and evidence links stable. Add acceptance to the owning task
when work lands; do not create another session handoff/status queue. Ordinary
tests stay PDK-free; physical acceptance is explicit and separately recorded.
Provider observation contract examples remain next work; the first FIFO example
implementation is delivered. This review stops before provider features or ASIC P6.

### Consolidation verification

2026-10-12: read-only documentation audit checked local Markdown targets and
heading anchors, the presence of all 29 relocated originals, unchanged bytes of
both historical PDFs, and identical executable source content after excluding
comments/docstrings. The 17 unavailable external targets are historical scaf
references; no replacement evidence was invented. `git diff --check` passes.
No build, unit suite, provisioning or EDA flow was run for this documentation pass.
