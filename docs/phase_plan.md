# hardcaml_asic phase plan

Current checkpoint: 2026-10-13 bounded explicit-stage implementation, independent
review and documentation closeout delivered. Coarse runner, six sequential physical
boundaries, schema-3 OCaml/Python recipes, exact-runtime path-bound checkpoints,
default CLI per-attempt observation, foreground watch and separate existing-policy finalization passed.
Actual physical and external acceptance evidence is retained as curated repo JSON.
The earlier blocked probe remains history; later official cases succeeded.
Default stores, human/explicit-JSON CLI 4, project endpoint routing, role-specific runtime policy, managed
Python/Tcl and thin bootstrap remain delivered. ASIC P6.5c is partially addressed;
broader P6.5/P6.6 identity/installation gates and committed-pin adoption remain open.
This is the **only active queue**. [Architecture](architecture.md) owns boundaries;
[P6 details](development/p6-implementation-plan.md) retain the detailed specification
and exact delivery evidence. Proposed new work below awaits design discussion.

## Start here

1. Resolved-build boundary hardening is implemented with the recorded
   [acceptance evidence below](#resolved-build-boundary-hardening-evidence).
2. The [independent Dune specimen](../../hardcaml_asic_example/README.md) delivers
    the fixed FIFO contract/core, scoreboard, TT wrapper/declaration and project CLI,
   with [PDK-free acceptance evidence below](#controlled-fifo-development-specimen-evidence).
   It now uses a recorded ASIC baseline plus an explicit development override,
   with isolated library/CLI installations and plain activated builds; see the
   [refresh/emitter closeout](#consumer-refresh-and-real-checkout-emitter-closeout).
   Read the [source-breaking migration and rename evidence](#public-api-rename-migration-and-evidence)
    before adopting this provider. The [project-centered entrypoint](#project-centered-entrypoint-acceptance)
    is delivered: consumer `Fifo_asic.project ()`, shared `Project.emit_bundle`, and
     project `describe|emit|preflight|run`; run is implementation only and requires
     Classic `--stage` or explicit-stage `--endpoint`. Current recorded refresh rejects the old API;
    development refresh works pending owner adoption of a committed candidate.
3. The provisional provider observation fixtures/model are accepted with
    [evidence below](#provider-observation-fixture-acceptance). The authorized
    [LibreLane probe review](#librelane-feasibility-probe-review) retains its historical
     blocker as history. Later [explicit-stage delivery](#explicit-stage-refactor-closeout)
     supplies successful official/physical evidence and bounded installed readers.
     Follow the dependencies below for P6 identity/installation.

This queue records future ordering, not authorization to proceed beyond the
completed bounded implementation. The [quickstart](guides/stage-quickstart.md) and
[detailed recipes](guides/ocaml-stage-recipes.md) describe the delivered interfaces.

### Default flow journal closeout

2026-10-13: [feature and independent review](development/flow-journal.md#final-independent-review-and-closeout)
delivered. Fresh/resumed CLI `stages` allocate before plan/preflight by default;
contract 4 advertises flushed allocation/terminal JSONL. Explicit store override and
`--no-observation` remain available; standalone APIs and Classic do not default-journal.
The example's mutually exclusive `project run --endpoint` route requires contract 4,
validates before emission and selects a nonexistent workspace under results.

Foreground incremental watch validates cold prefixes, checks cached record metadata,
validates only new content and drains the terminal publication/release race. Independent
readers can stop/reconnect without controlling execution. Reader exit 0 is query
success for any recorded terminal outcome, not acceptance. Review fixed non-pipe
stdout delivery failure; comprehensive forced provider and fresh installed-prefix
suites passed, followed by one private refresh and activated example checks.
Exact commands/current generation and retained compatibility checks are in the feature record.
[Existing real synthesis/watch/Ctrl-C/reconnect evidence](../evidence/librelane-observation/flow-journal-slice3.json)
remains valid; no additional EDA was needed.

Remaining: trusted local immutable-prefix/filesystem advisory-lock assumptions,
O(prefix) metadata work and cached memory, caller-owned cursors/retention, no
fsync/power-loss guarantee, daemon-crash process-survival promise, Workbench cancellation,
store-wide service, backend-step progress or execution takeover/recovery.

### Explicit-stage refactor closeout

2026-10-13: slices 1–7, final independent integration review and documentation
reconciliation complete. The [refactor record](development/explicit-stage-refactor.md)
retains exact commands, defects/fixes and historical slice limits.

- Shared `execution_plan`/`runner` modules preserve coarse Classic sequencing,
  best-effort collection and primary failures. Opt-in six-stage recipes use the
  same runner; implementation is modules in the existing package.
- Pure `Flow.Stage` / `Flow.Recipe` and Python schema-3 plans agree on contiguous
  composition, capabilities and checkpoint input/output declarations. Endpoint
  shorthand/schema-2 readers remain compatible. No new project/per-stage settings.
- Exact tested Docker image/engine/bridge and path-bound input/support/PDK closure
  are validated before atomic no-clobber checkpoint publication and continuation.
  Standalone transitions: synthesis → floorplan/placement, floorplan → placement,
  placement → cts, cts → routing, routing → signoff. Recipes never elide intervening
  boundaries; signoff is terminal and host-only inspection is not runtime readiness.
- Opt-in observation supplies early attempt allocation, publication-before-finish,
  inspect and reconnectable cursor reads. Separate finalization selects one completed
  fresh six-stage execution, maps real synthesis/signoff evidence, and optionally
  runs external checks and the existing acceptance policy. Physical completion,
  checkpoint publication, external postcheck and acceptance are separate facts.

Actual evidence, not synthetic fixtures or only external scratch paths:

| Record | Proven scope |
| --- | --- |
| [Blocked local probe](../evidence/librelane-observation/blocked-local.json) | Historical missing Tcl/Tk; zero of eleven authored cases in that attempt |
| [Slice 2](../evidence/librelane-observation/slice2-real.json) | 12 official-API cases; real synthesis → fresh physical handoff and bounded cancellation proof |
| [Slice 3](../evidence/librelane-observation/slice3-production.json) | Production checkpoint publication/runtime closure and synthesis resume |
| [Slice 4](../evidence/librelane-observation/slice4-physical.json) | Full six-stage physical execution, fresh successors with producer runs renamed, matching config/1509 external hashes, 21 final view leaves; 1550.116548 occurrence seconds |
| [Slice 5](../evidence/librelane-observation/slice5-observed.json) | Real observed synthesis/floorplan, ten records, independent post-exit cursor/closure audit |
| [Slice 6](../evidence/librelane-observation/slice6-finalization.json) | Separate 675.606435-second accepted operation, nine TT checks and 11,429-edge exact-image replay |

Worst setup/hold are 11.67551954830797 ns at `nom_slow_1p08V_125C` and
0.12502899069955042 ns at `nom_fast_1p32V_m40C`; DRC/LVS/antenna passed. Six
disconnected pins and one max-fanout violation remain raw evidence outside existing
acceptance gates. Earlier missing-metadata/timeout operations remain failed or
interrupted, not rewritten. The final review re-audited retained physical/observed/
accepted evidence without repeating costly EDA/external checks or reproving current
image-only closure in a new container.

Full successful verification (exact invocations in the
[review](development/explicit-stage-refactor.md#exact-successful-verification)):
`dune runtest -j 20 --force`, build/install, installed-prefix, external Project and
resolved-flow API checks, OCaml/Python recipe comparison, retained physical and
finalization verifiers, shell syntax, whitespace and container cleanup checks.
Forced suites: stage 30, finalization 15, observation 16, runner 11, CLI 43,
store 45, transport 10, runtime contract 8, runtime observation 18, phase4 26,
report 15, archive 20, packaging 17, managed Python 48, toolchain 25, provider
fixture 50, plus OCaml inline/bundle checks. Recipe checks: 36 accepted / 1819
rejected, capabilities/handoffs/composition. Installed-prefix: 51 top-level cases
including installed stage/finalization/observation suites. Independent sibling
`stage_recipe` and existing project CLI linkage passed all 42 endpoint/source
combinations and installed host-only reader checks. **Isolated installed linkage
is not adoption of a committed consumer pin.**

Remaining scope: full Workbench application integration; store-wide catalog/journal/
idempotency/fsync; detailed backend-step observation; arbitrary DAG/custom steps or
per-stage settings; execution takeover/recovery; native/macros/other images and
relocation; resumed-attempt or standalone signoff finalization; segmented artifact
archive/GC. Retention remains caller-owned. Broader P6 gates below are not silently
closed. Earlier closeouts below are dated history, superseded only by explicit later
evidence. This final slice checked documentation links/commands and whitespace only.

### Default result store and CLI 2 closeout

Historical CLI-contract-2 closeout, 2026-10-13; completed implementation acceptance
and independent review. Current interface is contract 4; this section preserves contract-2/3 history:

- Delivered default `_flow_results/{bundles,runs,operations}`, verified immutable
  identity publication/reuse, durable bounded readiness diagnostics, human defaults,
  explicit `--json` raw payload and stderr `--verbose`. CLI contract **2** deliberately
  breaks JSON-default presentation; package 0.1.0 and record schema 1 stay separate.
- Project `describe|emit|preflight|run` owns discovery/emission and routes to the
  installed provider. Run requires a stage and performs implementation only;
  collect/report require an explicit existing run. No newest guess or project execute.
  See the [detailed command/storage matrix](guides/flow.md#default-result-store-and-cli-contract-3).
  The completed human-output feature extends explicit JSON selection to all
  additive commands and advertises CLI contract 3. Independent integration,
  consumer supported-contract migration/private refresh and installed retained
  inspection passed. See [completion evidence](development/human-readable-flow-output.md).
- Accepted provider checker: **325 Python tests**, OCaml, external public/private
  checks and high-/lower-level bundle equivalences. Installed-prefix **47**;
  example **11 bootstrap + 8 routing + 17 dependency = 36 Python**, core/wrapper
  and strict synthesis/simulation RTL **11,429 edges each**, plus corrupt oracle.
- Actual selected generation `f74ce0f369fd41b5b99811e0769dc756`; recorded
  `1714764859274f80a9f5ad207421a04601824e99` pin unchanged. Real no-flag emit created
  then reused bundle `4839450af746fca149271e20f79e57843ae32ad4bc21ab093dcc2f40275dec2f`,
  **21 files**, bytes/metadata unchanged on reuse. Its declared inputs are the
  stored acceptance snapshot, preceding this final routing fix/docs update.
- Two default preflights saved `ready=true` operations
  `20261013T024836762190Z_e4132285` / `20261013T024837648561Z_c2112d53`, human
  three-line summaries, no default implementation runs. Provider JSON matched its
  saved report byte-for-byte; explicit output made only that file, missing parent
  exited 2 before probes. Saved bundle paths canonicalize the public symlink to
  `.objects`; both name the same immutable data.
- Private-root nonexistent-Python run exited 1: full ID
  `6e18d1076b0f45e89e69c10fee0cb3bc`, failed run/readiness, empty commands, no completed
  stage or staged project. Collect JSON wrote results without another run; report
  JSON rejected read-only, legacy collect stdout stayed read-only. No ASIC tools ran.
- [Local ignored evidence](../../hardcaml_asic_example/.dev/results-workflow-checks/20261013T024610Z-8c0ac8c3/)
  retains logs, path inventory and preservation snapshots. Final review corrected
  directory symlink-parent/`..` misrouting; focused example build and **9 routing
  tests** passed. Accepted full suites were not repeated for this closeout.
- Non-Git closeout helper passed **9 docs / 212 local links/anchors**, whitespace
  and final LF; eight unavailable links are historical scaf references. It reverified
  all 21 bundle files/hashes, 29 metadata entries, operation/run evidence and pin.

This is storage/CLI ergonomics, not live event catalog/internal step observation,
autoexecution, full postcheck or signoff. P6 identity/installation and live
observation gates remain open; older acceptance below is dated history.

### Host/container runtime-policy closeout

Final 2026-10-12 acceptance (reviewed 2026-10-13; not rerun here):

- Provider `check_project_api.py --provider-checks`: **278 Python tests**, OCaml,
  RTL, **8** external private-boundary and **4** high-level manual checks passed.
  Installed-prefix **44**, consumer **27 Python tests**, build/strict/describe and
  FIFO/wrapper **7,330 + 20,017 edges each**, RTL **11,429 each** plus negative
  oracles passed. No real ASIC flow executed; source/probe readiness is not
  physical compatibility. Earlier tiny transport help, RW/RO mount and sleep
  cleanup smoke passed, separately from flow execution.
- Installed generation at that acceptance was `caa4d18002274defb5eebb15e35a9042`; CLI remains
  unstamped and recorded consumer pin `1714764859274f80a9f5ad207421a04601824e99`
  is unchanged. This source candidate awaits owner adoption; no pin was advanced.
- [Local acceptance summary](../../hardcaml_asic_example/.dev/runtime-contract-checks/acceptance-20261012-01/acceptance-summary.json)
  records fresh bundle identity
  `95510e3e0e8b2883c901de43e5e53c4ae2ca907ce81f7dfcbbde05bb0030537b`:
  installed preflight **exit 0**, `ready=true`, no issues/waivers, six passing
  comparisons. Host **3.11.17**, container **3.13.13**, both LibreLane
  **3.1.0.dev3**, container `Requires-Python >=3.10`, host Tcl ready.
- Docker **29.8.1**, Linux/amd64, flags `-I -B`; observed local image ID
  `sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a`.
  RepoDigests are recorded separately even though their hash happens to coincide.
  The official tag is mutable across machines, not a new registry digest pin.
- Old `/tmp/fifo-project-bundle-01` identity
  `c2e4d438aaa7c803c711712e22d278f293accb82cfe0f4160d7a3bda650144a9` retains
  all **21 files / 29 entries**, bytes/modes/mtimes; installed preflight exits **1**
  solely for container 3.13.13 versus legacy requested 3.11. New semantics require
  fresh emission, never editing that bundle. The fresh bundle honestly records
  dirty README input; it remains the recorded snapshot before this docs closeout.
- Actual `./bootstrap.sh --check` including container exits **0**. Final scoped
  source/tool-root/cache/env/index snapshots are unchanged by preflight/bootstrap.
  This applies **after** the narrow `GIT_OPTIONAL_LOCKS=0` collateral-probe fix,
  verified with a real temporary-repository regression; the initial failing
  attempt is not claimed read-only.

See [runtime policy and launch binding](guides/flow.md#runtime-policy-and-launch-binding).
Next bounded task: separately authorize the observation-probe rerun or synthesis;
neither was run for this closeout. Historical acceptance below remains dated.

### Tool-environment ownership: first slice

Settled scope: installed OCaml library/stdlib Python CLI independent of source
checkout; consumer-owned configurable `_flow_tools/` default for LibreLane and
precheck venvs plus PDK/support collateral and managed Python/Tcl; host CLI Python,
external overrides and Docker/Nix stores remain separate. Thin consumer bootstrap delegates to the installed provider without
copied pins, source fallback or automatic refresh. Provider refresh is separate
from tool provisioning. Readiness, example default-root/bootstrap and
`provision --python BASE` are now implemented; broader P6.5c gates remain open.
The example selects explicit `--toolchain` > `TOOLCHAIN` > absolute
`hardcaml_asic_example/_flow_tools`; provider/development adapters retain their
legacy fallback. See [ownership and commands](guides/bootstrap.md#tool-directory-ownership).

Delivered on 2026-10-12: lexical absolute interpreter paths preserve explicit
absolute/relative spelling (including parent symlinks and `..`) and inferred
`.venv/bin/python` / `.venv-precheck/bin/python` selections. Other directory
canonicalization and existing records, schemas, final JSON and exit semantics
are retained. Downstream phase4 preflight/run/check audited; no changes required.

Acceptance commands, all passed:

- `python3 -B -m unittest discover -s test -p test_flow_cli.py`: **29 tests**;
  preflight/run/postcheck/full-execute dispatch, explicit absolute/relative paths
  with spaces, toolchain-root and `TOOLCHAIN` inference for both interpreters.
- `python3 -B -m unittest discover -s test -p test_phase4.py`: **17 tests**;
  quoted precheck shell command executes a real venv through its lexical path.
- `python3 -B test/test_installed_prefix.py`: **36 tests**, including local Dune
  build and isolated temporary-prefix install. Real symlinked no-pip venvs execute
  synthetic LibreLane/precheck fixtures through the installed full-execute command
  for all four selection modes; runtime `sys.prefix != sys.base_prefix`, argv,
  `PATH`, and recorded interpreter selection are verified. No dependencies fetched.

Venvs use stdlib `venv.EnvBuilder(symlinks=True, with_pip=False)` in temporary
directories. External EDA tools are fixtures, not physical acceptance. Production
runtime was neither sourced nor changed. The prior audit remains Python 3.12.3 /
LibreLane 3.1.0.dev3 lacking `tkinter`/`_tkinter`, versus the Python 3.11 pin, with
stale generated environment references to `jane/asic`. Tcl repair, Python 3.11
availability, full live provider acceptance and P6.5c closure are not established.

### Tool-environment closeout acceptance

Latest 2026-10-12 managed-runtime closeout (completed acceptance, not rerun by
this documentation review):

- Provider `check_project_api.py --provider-checks`: **220 Python tests**, OCaml,
  Icarus, eight external private-boundary checks and four bundle equivalences
  passed. Installed-prefix **40**, example bootstrap **11** and dependency **16**
  give **287 reported unit tests**, excluding consumer RTL. The earlier disposable
  read-only Dune-copy permission failure was fixed by chmod of only that copy;
  **23 toolchain regression tests** and the final full suite passed.
- Current installed generation `fd7a5326ca7647a7a4f8803740e570be` contains the helper
  and pin/assets; installed-path checks prove no source-checkout search. Exact
  actual-runtime inspection passed with network audit guards. CLI remains 0.1.0
  unstamped; recorded provider `1714764859274f80a9f5ad207421a04601824e99` remains
  unchanged and needs development mode until owner adoption of a committed candidate.
- Activated example build/runtest/strict/describe passed: core/wrapper each
  **7,330 + 20,017 edges**; synthesis/simulation RTL each **11,429**, plus negative
  oracles. No new FIFO rerun is needed for this documentation closeout.
- [Actual acquisition evidence](../evidence/managed-python/actual-runtime.json):
  CPython **3.11.17 / PBS 20261009**, Tcl **9.0.4**, Tk **9.0**, OpenSSL **3.5.9**;
  two disposable pip venvs, wheel-only LibreLane **3.1.0.dev3**, official Tcl
  evaluation returned **42**. Main-root `.venv`, precheck, TT and PDK were not
  created; old source `.toolchain/` is unchanged. No official Flow case or physical
  signoff is claimed. See [integrity/platform and opt-in reproduction](guides/consumer-installation.md#managed-python-integrity-and-initial-platform).
- Actual `./bootstrap.sh --check --no-container` exits **2**, exactly **five gaps**:
  TT, PDK, flow venv, precheck requirements and env file. No host-Python mismatch
  or managed-runtime gap. All **5,166 tool-root entries** retain mode/size/mtime/link
  and receipt/cache hashes (atime ignored). Fresh missing-root check and invalid
  external `/usr/bin/python3` provision control both failed without root creation,
  download or fallback.
- Preserved local ignored [logs and result files](../../hardcaml_asic_example/.dev/managed-bootstrap-checks/acceptance-20261012-a/),
  including [read-only comparisons](../../hardcaml_asic_example/.dev/managed-bootstrap-checks/acceptance-20261012-a/readonly-comparisons.json)
  and [five-gap log](../../hardcaml_asic_example/.dev/managed-bootstrap-checks/acceptance-20261012-a/bootstrap-real-check.log).

P6.5c is partially addressed. Identity/waivers, source-denial installation,
runtime preflight Tcl/native/container and physical gates stay open. Next bounded
task is the official observation rerun with the verified scratch LL venv; explicit
full bootstrap is a separate owner action that provisions collateral/network.
The consumer README is bundle-declared source: these doc edits legitimately change
future bundle identity; preserved earlier snapshots remain historical evidence.

Earlier readiness-only acceptance follows as historical evidence:

- Provider `check_project_api.py --provider-checks`: **160 Python tests**, OCaml,
  eight private-boundary external failures, four high-level/manual whole-bundle
  equivalences and Icarus passed. Full `test_installed_prefix.py`: **37 passed**;
  example setup **16** and bootstrap **11** passed.
- Final actual development refresh: generation `9d0035d4c9fb4fafb7295733cb0807a9`,
  **10.44 seconds**. ocamlfind and CLI select the same prefix; `helperprobe.py`
  is present; `active_is_published` and `active_library_path_is_first` are true.
  CLI remains **0.1.0 unstamped**, without P6 identity. Consumer record remains
  `1714764859274f80a9f5ad207421a04601824e99`.
- Activated plain example `build @all`, `runtest --force`, strict acceptance and
  `describe` passed: core and wrapper each **7,330 directed + 20,017 seeded**;
  both generated RTL variants **11,429 each**, plus corrupt-oracle rejection.
- Actual activated `./bootstrap.sh --check --no-container`: default exit **2**,
  six gaps (absent root / Python 3.12 versus requested 3.11); `_flow_tools` was
  not created. Explicit `--toolchain /home/wayne/devel/jane/hardcaml_asic/.toolchain`
  also exited **2** (existing 3.12 venvs / stale `jane/asic` environment).
  Each before/after inventory covered **16,195 entries**, with zero differences
  in modes, sizes, mtimes, symlinks and key env/index hashes (atime excluded).
- Preserved **local, ignored** evidence: [results](../../hardcaml_asic_example/.dev/bootstrap-checks/20261012T215315-370846/results.json),
  [default log](../../hardcaml_asic_example/.dev/bootstrap-checks/20261012T215315-370846/bootstrap-default.log),
  [existing-root log](../../hardcaml_asic_example/.dev/bootstrap-checks/20261012T215315-370846/bootstrap-existing.log),
  and `*comparison.json` alongside them. These are environment-specific paths,
  not permanent published evidence.

That earlier slice required the requested Python minor (3.11), probed host
venv/ensurepip/headless Tcl before writes, checks existing flow/precheck metadata,
and safely quotes/data-checks generated env files. `--check` is bounded with no
writes, bytecode, index changes or env rewrite; `--no-container` makes no engine
queries. Current readiness rejects the Python mismatch first; it does **not**
establish a new Tcl test beyond the prior missing-Tk probe. No host repair or
tool provisioning occurred; source/destination tool stores are unchanged.
Runtime preflight Tcl policy, native EDA readiness and Podman runner generalization
remain unimplemented. P6.5c and live observation remain open, with zero probe cases.
The current user's workflow is [activate then check](guides/bootstrap.md#consumer-check);
the latest five-gap result above supersedes that earlier prerequisite diagnosis.

The earlier blanket "finish P6, then migrate scaf" queue is superseded. Do not
execute archived handoff prompts. No feature, source stamp, specimen, observation
contract or new test pass was claimed by the earlier documentation-only checkpoint.
The subsequent FIFO delivery and provisional provider fixture acceptance are
recorded below; later bounded live stage observation is delivered in the
[explicit-stage closeout](#explicit-stage-refactor-closeout).

## Status and preserved history

| Track | Current status | Evidence / detail |
| --- | --- | --- |
| ASIC P0–P5, M1–M3 | Complete; retain the working lifecycle/resources/bundle/flow foundation | [Original tasks and completion records](archive/phase-plan-through-p6.4b.md) |
| ASIC P6.1/P6.2 | Complete: operation-aware acceptance and complete input preservation | [Original P6 records](archive/phase-plan-through-p6.4b.md#11-p6--shared-tooling-distribution), reporter/archive suites |
| ASIC P6.3 | Complete: shared dispatcher contract | [P6.3 completion](development/p6-implementation-plan.md#11-p63b-completion-evidence) |
| ASIC P6.4a/P6.4b | Complete: packaging, shared routing and installed-operation coverage | [P6.4a](development/p6-implementation-plan.md#12-p64a-completion-evidence), [P6.4b](development/p6-implementation-plan.md#13-p64b-completion-evidence) |
| ASIC P6.4 parent | Open only for source-access-denied installation evidence | ASIC P6.6a supplies it; do not redo packaging |
| ASIC P6.5a/b/c, P6.6a/b | Open | Scope and dependencies below |
| Tool-environment first slices | Delivered: managed Python/Tcl default, lexical paths, bounded readiness, external base override and thin bootstrap; P6.5c partially addressed/open | [Current acceptance](#tool-environment-closeout-acceptance), [bootstrap guide](guides/bootstrap.md) |
| ASIC P7.1–P7.6 / M4 | Open historical migration; deferred from current queue | [Original tasks](archive/phase-plan-through-p6.4b.md#12-p7--consumer-migration-and-legacy-retirement), [backlog](backlog/README.md) |
| ASIC S.1/S.3 | Complete, with qualified S.3 interpretation | [SRAM index](sram/README.md) |
| ASIC S.2 | Open; S.2a complete, S.2b research partially resolved | [SRAM checkpoint](sram/sram-status.md) |
| ASIC S.4 | Gated, unimplemented | Requires S.2 capability gates |
| ASIC T.1 | Open, independent toolchain follow-up | Scope below |
| Provider observation / explicit stages | Bounded per-attempt journal/readers, checkpoint restarts and separate finalization delivered; full checks and real physical/external acceptance passed; store-wide/fine-step/Workbench scope remains open | [Current closeout](#explicit-stage-refactor-closeout), [historical probe](#librelane-feasibility-probe-review), [fixture acceptance](#provider-observation-fixture-acceptance), [architecture](architecture.md#8-provider-observation-direction) |
| Resolved-build boundary hardening | Implemented; full runtest passes | [Evidence below](#resolved-build-boundary-hardening-evidence) |
| Public API rename | Implemented; provider and FIFO acceptance passed, active documentation migrated | [Migration and evidence below](#public-api-rename-migration-and-evidence) |
| Project-centered entrypoint | Delivered: declaration/inventory, immutable emission, `describe|emit|preflight|run`; run is implementation only, Classic stage or explicit-stage endpoint; current CLI contract 4 | [Journal closeout](#default-flow-journal-closeout), [presentation history](development/human-readable-flow-output.md), [original acceptance](#project-centered-entrypoint-acceptance) |
| Controlled-FIFO development specimen | Contract/core, scoreboard, TT wrapper/declaration and emitter delivered; PDK-free acceptance | [Original evidence](#controlled-fifo-development-specimen-evidence), [consumer README](../../hardcaml_asic_example/README.md) |
| Consumer dependency refresh / emitter | Delivered: isolated library/CLI, activation and real-checkout acceptance; development works, old recorded API refused pending owner candidate adoption | [Original closeout](#consumer-refresh-and-real-checkout-emitter-closeout), [current acceptance](#project-centered-entrypoint-acceptance), [commands](development/consumer-dependency-workflow.md#implemented-commands) |

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
- Runner/collector publication boundaries are now refactored in the bounded
  explicit-stage delivery, preserving Classic CLI and existing acceptance policy.
  Broader target/resource generalization remains separate scope.

The bounded interface slice and subsequent FIFO specimen are delivered, without
changing historical M3 or P6 completion criteria. The separate provisional provider
observation fixture/model slice is accepted; later per-attempt stage observation is
delivered, while store-wide/fine-step observation and further P6 work remain open.

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

### Project-centered entrypoint acceptance

2026-10-12, subsequent bounded implementation and independent documentation review.
Earlier commands, generations and snapshots above remain historical evidence;
they are not assertions about today's refs or current API compatibility.

- Provider `Project.create ?source_inputs` defaults to `[]`, with an unchanged-list
  getter and declaration-only `describe : t -> Sexp.t`. Description performs no
  elaboration, resolution or I/O and is not a Workbench protocol.
- `Project.emit_bundle ?inputs ?include_simulation t ~source_root ~output_dir`
  rejects empty inventory before constructing the design, then composes resolution,
  optional Simulation (default true), rendering and writing. False skips Simulation
  construction and uses synthesis sources for simulation. Rendering must succeed
  before output writes; Bundle's non-atomic new/empty-directory rules still apply.
- FIFO `asic/project.ml/mli` owns the declaration/inventory; `fifo_asic.ml/mli`
  exposes `project ()` and `Tt_wrapper`. One `bin/project.ml` implements `describe`
  and `emit` using the shared operation. Inventories and tests are migrated. There
  is no runtime project `run` or `inspect` command yet. Concrete code, shell commands
  and consolidated test coverage live in the [bundle guide](guides/bundle-emission.md).

Completed implementation-pass evidence supplied to this review (suites not repeated):

- `python3 test/check_project_api.py --provider-checks` passed: **146 Python tests**,
  OCaml tests, **four Icarus simulations**, the external public consumer with
  **eight private-record negative checks**, and four high-level/manual complete
  bundle comparisons (observable/memory, Simulation true/false). The helper now
  preserves normal PATH and isolates Git configuration/identity only; the earlier
  optional-RTL-skip instruction was stale and has been removed. Disposable fixture
  commits use `Bundle test <bundle@test.invalid>` for author and committer.
- Actual development refresh published example generation
  `69a5db1892234a28b0884442ab0291f1` as default `current`, observing provider base
  `82c0d7f7fbaa2d1796427de1037644946ceb2294` and snapshot checksum
  `64b10f0e17e348105053f2f0c095d97bf2a8397a096b135b603c45ca43b2b6ce`.
  API validation applies to selected bytes; the old record is loaded for comparison.
  Actual recorded `1714764859274f80a9f5ad207421a04601824e99` refresh failed with
  `Project.create` incompatibility, preserving current and the unchanged record.
- Activated plain `dune build @all`, `dune runtest --force`,
  `dune build @acceptance-strict --force` and `describe` passed. **16 setup tests**
  and CLI purity checks passed. Core/wrapper each passed **7,330 directed + 20,017
  seeded edges**; separate synthesis/simulation RTL each passed **11,429 edges**
  and rejected the corrupted oracle.
- Saved old executable `/tmp/opencode/project-api-baseline-k9wvcigz/emit_bundle.exe`
  was independently hash-verified:
  `739024f92ae88bf45d48e63ed67673b83a73c5fb4c5078db16efe8bbdcfe7cc1`.
  The union fixture independently validated old **13-input** and new **15-input**
  inventories. Five hardware artifacts were byte-identical and nonprovenance
  manifest facts equal. Input-file lists, provenance and identity intentionally
  differ; this is not old/new whole-tree equality. Repeated new whole trees match.
- Actual example-root output is preserved in
  `.dev/emitter-checks/project-entrypoint-slice3/{first,second,evidence.json,...}`
  with sibling `project-entrypoint-slice3.log`. Snapshot revision:
  `b3cd3b0095593f4a5c1bac645c6a3e2c2e387e7c`; declared dirty inputs include README
  and `bin/dune`, with five untracked renamed/added sources. **15 inputs → 21
  files**, identical first/second trees and all copied-input hashes verified.
  Bundle identity:
  `27410b51ee1df628e1906d8a7cbe7f10279bdb23f440f326c0e227377a2eb64e`;
  manifest SHA-256:
  `2d5730493b95c22d9e50179d4db6e52e55d7989373b10ae7d9e3c004d210aed4`.

Independent source review found no blocking defect in orchestration, private/acyclic
boundaries, the FIFO facade/CLI, selected-API versus baseline refresh validation,
or inventory-aware baseline comparison. No bug fix or new regression was needed.
The example README is a declared input and its finalized bytes remain preserved.
Current pin compatibility remains blocked until the owner commits and adopts a
suitable candidate; explicit development refresh works. CLI identity remains
unstamped. This is neither a clean/release/signoff claim nor ASIC P6 completion.
Project run routing and LibreLane observation feasibility are separately agreed
next scope, not authorized implementation in this closeout.

Final review checks actually run: non-Git read-only
`python3 /tmp/opencode/check-project-entrypoint-docs.py` passed seven documents'
whitespace/final-LF and local links/anchors (only two pre-existing historical scaf
links unavailable). It reverified both preserved 21-file trees, manifest hash and
recorded provenance, all 15 current source copies including README, saved baseline
executable hash, current generation/record, 16 setup-test code paths and four
comparison combinations, and absence of lower-layer Project callbacks. The new
agent-owned `test/project-api.md` was consolidated into the existing bundle guide
and removed; no links to it remain. No build/test suite was repeated in this review.

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

## Provider sequence — delivered subset and remaining proposals

The original broader sequence below is not wholly delivered. The bounded
[explicit-stage implementation](#explicit-stage-refactor-closeout) works without
Workbench and provides the subset called out below; remaining proposals require
their own contracts and acceptance.

| Slice | ASIC deliverable and acceptance | Other repository ownership |
| --- | --- | --- |
| Contract and feasibility | Synthetic model accepted; later official cases and six-stage physical handoffs demonstrated; blocked probe retained as history | Workbench decoder/reducer fixtures; example design/constraint selection |
| Durable catalog and outer observation | Per-attempt early allocation, inspect/cursor prefix and stored outcomes delivered; store-wide list/catalog/idempotency/fencing remains proposed | Workbench P1 adapter/P2 derived catalog and early run display |
| Internal step lifecycle | Actual starts/completions/failures/skips/interruption and repeated occurrences, including deferred errors; earlier steps visible while a later one runs | Workbench execution feature/views |
| Incremental results | Stage checkpoint publications and final synthesis/signoff origin mapping delivered; per-step measurement origin/units and general incremental result protocol remain proposed | Workbench timing/resources/check projections |
| Preservation and installed acceptance | Installed readers, corruption/conflict/signal tests delivered; caller-owned path-bound retention, no segmented archive/GC/fsync/recovery | Workbench restart/reconnect and cache invalidation |
| Real specimen handoff | Actual physical/external acceptance and isolated installed recipe/project linkage passed; deliberate committed pin and Workbench live acceptance remain separate | Example owns pin adoption; Workbench owns application integration |

The fixtures provisionally specify store-wide ordering, idempotency/BUSY ownership,
fencing, snapshot/cursor consistency, transitive readiness and retention. The probe
proved body-hook limits; runner callbacks now supply bounded stage lifecycle facts
and observed writers use local advisory locks. Store-wide fsync/data durability,
crashed-writer reconciliation and preservation remain open. Full backend-step
interception is not delivered. Metric equality cannot establish measurement origin. Archive policy
must cover advertised evidence, not just final metrics. Failed-run diagnostics
need an explicit export contract separate from completed-run archives.

Delivered [synthetic fixture](../test/fixtures/provider_observation/v1/README.md):
build-B/config-B has runs A/B. A publishes synthesis and intermediate timing, then
fails routing; B skips a gated step and is interrupted at a later occurrence, with
an unreached step preserved. A later collection publishes a new snapshot without
rerunning implementation; postcheck is rejected before execution. Inherited timing
and equal-valued fresh measurements retain distinct origins. Deeper hierarchy is
unmodeled, and a snapshot file is not a resumable checkpoint.

### Provider observation fixture acceptance

Historical fixture-only acceptance; later installed stage observation is recorded
in the [current closeout](#explicit-stage-refactor-closeout). Its original limits
and commands below describe that earlier pass, not current production scope.

2026-10-12, independent single-agent review/final acceptance of the provisional
test-only [v1 contract](../test/fixtures/provider_observation/v1/README.md),
`test/provider_observation_contract.py`, `test/test_provider_observation.py` and the
new `test/dune` alias integration:

- Fixed execute failed/interrupted outcomes releasing BUSY before implementation
  became explicitly terminal; completed implementation can still outer-fail or
  interrupt. Fixed collect success without a result published by that operation.
- Recovery copies the supplied snapshot, independently validates the full retained
  prefix, compares exact typed state, then applies the suffix to the restored reader.
  Malformed earlier transitions cannot hide behind matching last facts. No expected
  JSON is generated by the reducer; all seven documents and five evidence files
  retain their authored bytes.
- **50 tests** pass (43 initial plus seven review regressions): unchanged 34 store
  events, six hand-authored snapshots, 13 queries, 15 replay cases and 21 recovery
  pairs, plus targeted negative branches. Producer/time/run closure and transitive
  error/result readiness are checked. Silence/disconnect does not generate facts.
- `python3 test/test_provider_observation.py`: `Ran 50 tests in 0.219s`, `OK`.
  `dune build @test/provider-observation`: `Ran 50 tests in 0.207s`, `OK`.
- Full `dune runtest --force`: **exit 0**, Python suites **17 + 16 + 20 + 50 + 28 +
  15 = 146**, all `OK`; OCaml inline tests and bundle integration passed. Exact
  bundle output: `bundle determinism, provenance, staging, hashes, RTL and toolchain.lock passed`.
  `/usr/bin/iverilog` and `/usr/bin/vvp` were available; all four generated-RTL
  simulations ran, none skipped. No provisioning or physical flow was run.

The full-suite child environment was isolated as follows (no direct Git command;
the existing bundle script alone creates its temporary synthetic repo, without
remotes or model attribution):

```python
import os, shutil, subprocess
env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
env["PATH"] = os.pathsep.join(
    p for p in env["PATH"].split(os.pathsep) if p.rstrip("/") != "/tmp/opencode")
env.update(
    GIT_AUTHOR_NAME="Bundle test", GIT_AUTHOR_EMAIL="bundle@test.invalid",
    GIT_COMMITTER_NAME="Bundle test", GIT_COMMITTER_EMAIL="bundle@test.invalid",
    GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_SYSTEM="/dev/null",
    GIT_CONFIG_GLOBAL="/dev/null", GIT_ATTR_NOSYSTEM="1", GIT_TEMPLATE_DIR="",
    GIT_CONFIG_COUNT="2", GIT_CONFIG_KEY_0="core.hooksPath",
    GIT_CONFIG_VALUE_0="/dev/null", GIT_CONFIG_KEY_1="commit.gpgsign",
    GIT_CONFIG_VALUE_1="false")
for tool in ("dune", "git", "iverilog", "vvp"):
    print(tool + ": " + str(shutil.which(tool, path=env["PATH"])), flush=True)
raise SystemExit(subprocess.run(["dune", "runtest", "--force"], env=env).returncode)
```

The successful invocation used `python3 -c` with this body. An earlier wrapper
attempt had a Python quoting SyntaxError before starting Dune; corrected above.
Final non-Git verification (`python3 /tmp/opencode/check-provider-observation-review.py`)
passed: seven scoped files' whitespace/final LF, two Python ASTs, four Markdown
documents and 82 local links/anchors (none unavailable), plus fixture/test counts.
The provisional store-wide cursor, idempotency/BUSY/fencing/readiness/retention
decisions are logical assertions, not live locking/fsync or data-durability proof.
No live catalog, early correlation, step/result publication or deeper hierarchy is
delivered. Prefix validation requires the full catalog/journal; no durable snapshot
store or execution resumption is implemented. The next bounded task is the
LibreLane observation feasibility probe. This acceptance stops before that probe
and ASIC P6 work and preserves the successful dependency/emitter closeout above.

### LibreLane feasibility probe review

2026-10-12, authorized local official-API experiment, followed by a sequential
read-only runtime/source review. [Experiment and eleven authored cases](../experiments/librelane_observation/README.md);
[retained evidence](../evidence/librelane-observation/blocked-local.json).

- Actual bounded command used literal
  `/home/wayne/devel/jane/hardcaml_asic/.toolchain/.venv/bin/python -B` with
  `timeout --signal=TERM --kill-after=3s 60s`; exit **2**. Python **3.12.3**,
  LibreLane **3.1.0.dev3**, requested Python **3.11**.
- Official flow construction reached `Config.load` → `TclUtils._eval_env` →
  missing `tkinter`. **BLOCKED: zero sequencing cases executed.** Synthetic PDK
  configuration has not passed validation. Only class-method identity and
  missing-module/no-callback guards passed; authored case assertions did not run.
- Targeted `/usr/lib/python3.12`, `/usr/local/lib/python3.12`, venv site-packages
  and venv configuration checks found no compatible Tcl/Tk module; the literal
  venv resolves neither `tkinter` nor `_tkinter`. No runtime retry was warranted.
- Current upstream, experiment and scratch fixture hashes match the raw report
  `/tmp/opencode/librelane-observation-72pve6uu/evidence.json` and retained record.
  Probe/fixture syntax compiles in memory without `.pyc` writes.
- Source review supports only a candidate substitution/`Step.run` body/raw-update
  hook. Body return precedes full-Step validation/writes/completion; gates/skips
  are outside it. No live observation interface, durable publication, container
  visibility or real descendant cancellation has been demonstrated.

**Historical next bounded action:** the later [managed-runtime closeout](#tool-environment-closeout-acceptance)
supplies compatible Python/Tcl and a scratch LibreLane venv. Rerun the same
official constructor/probe under its bounds using
`hardcaml_asic_example/.dev/managed-python-acceptance/real-av_wxhlt/librelane-smoke/bin/python`.
At that checkpoint no official case had yet run. Later selected-image official
cases and real physical/observed/external acceptance succeeded; see the
[explicit-stage closeout](#explicit-stage-refactor-closeout). The blocked record
above remains unchanged.
Do not bypass configuration validation. Full collateral provisioning is separate.

**Separate installed-launch fix delivered:** CLI interpreter paths formerly used
`Path.resolve`, losing venv selection to `/usr/bin/python3.12`. The
[bounded lexical-path fix and real-venv evidence](#tool-environment-ownership-first-slice)
cover this defect, separately from SRAM and other runtime defects.
[Tool-directory ownership and dated local inventory](guides/bootstrap.md#tool-directory-ownership)
describe configurable managed children and the stale generated environment;
neither inventory nor this blocked probe closes **P6.5c**.

Final non-Git verification:
`.toolchain/.venv/bin/python -B /tmp/opencode/check-librelane-final-review.py`
passed retained/raw evidence consistency, all **12** recorded current
upstream/experiment/fixture hashes, two in-memory Python compilations, and
whitespace/final-LF plus **101** local links/anchors across the four updated docs
and experiment README (none unavailable). Raw report SHA-256:
`4fb16517b0dced266a18161d51e614415fc38291e653c8f43633d97b8842d535`.
These checks do not execute any of the eleven probe cases.

## Dependency triage

| Milestone | Genuine blockers |
| --- | --- |
| Contract fixtures, Workbench reducers/window behavior | Agreed identity/state examples; not P6 completion or a real EDA environment |
| Example Dune/design/unit tests | Delivered via explicit development refresh/activation; recorded baseline lacks new Project API pending owner candidate adoption; no PDK required, full environment lock absent |
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
Provider observation fixture/model acceptance, the FIFO example and project-centered
entrypoint are delivered. The authorized LibreLane probe remains blocked as
recorded above; runtime prerequisite work requires user authorization. Project
run routing, live provider features and ASIC P6 implementation remain future scope.

### Consolidation verification

2026-10-12: read-only documentation audit checked local Markdown targets and
heading anchors, the presence of all 29 relocated originals, unchanged bytes of
both historical PDFs, and identical executable source content after excluding
comments/docstrings. The 17 unavailable external targets are historical scaf
references; no replacement evidence was invented. `git diff --check` passes.
No build, unit suite, provisioning or EDA flow was run for this documentation pass.
