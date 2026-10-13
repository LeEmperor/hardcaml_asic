# Human-readable flow command output

Status: all three slices delivered; independent integration, full provider tests,
installed-prefix suite, private consumer refresh and retained-output inspection
passed, 2026-10-13. Current CLI contract: **3**.

## Request and goal

Make interactive `hardcaml-asic-flow` output readable, following the existing
Classic `report` command's labeled fields, sections and explicit conclusions.
Preserve complete structured output when explicitly requested with `--json`.
The user's references to observation/check commands refer principally to
`observation inspect` and `checkpoint-inspect`; retain the existing command names.

The current inspectors can print thousands of bytes of execution state or hundreds
of kilobytes of checkpoint dependency hashes. The human default should show the
execution outcome, stage progress, published artifacts and validation scope rather
than recursively dumping the data structure.

## Output contract

- Human-readable text by default, usable in terminals and redirected plain logs.
  Prefer straightforward sections and aligned fields, without requiring ANSI,
  terminal detection, a pager, or new formatting dependencies.
- `--json` selects the complete existing machine representation. Do not remove
  fields or silently summarize machine output. Preserve command-specific JSON vs
  JSON-lines behavior, especially early allocation and terminal execution records.
- Support global and appropriate command-local flag placement consistently with
  existing CLI presentation flags. Resolve nested observation parser behavior
  explicitly and test it. Do not introduce a competing `--verbose-json` spelling.
- Keep diagnostics on stderr and exit codes/validation/execution semantics intact.
  Formatting must consume results from the existing operation, not rerun probes,
  revalidate a different selection, or mutate records.
- Update machine consumers, experiments, tests and documented pipelines to request
  JSON explicitly. Persisted schemas, hashes and evidence remain unchanged.
- Variable-length lists receive useful tables/sections; empty, missing, unavailable,
  failed and interrupted states must be understandable without invented values.
  Avoid emitting full external-file inventories by default.

## Command scope

1. `observation inspect`: identity, requested endpoint/plan, recorded outcome,
   writer/observation state, stage status/durations, checkpoint references, cursor,
   and acceptance scope. Distinguish completed requested placement from a completed
   full physical flow. Historical publication does not establish current readiness.
2. `checkpoint-inspect`: identity, boundary/path, validation scope, requested and
   supported continuation, file/dependency counts, and acceptance. Host validation
   is not runtime/image validation. `--restart-to` only validates a transition.
   Summarize accumulated metrics conservatively without claiming fresh production
   at the checkpoint boundary or treating unavailable values as passes.
3. Related currently JSON-default public commands: review `observation describe`,
   `observation read-updates`, `stages`, `finalize`, and `finalization-inspect` for
   coherent human defaults and explicit machine output. Preserve early allocation
   visibility for long operations. Existing Classic human output stays consistent.

No flow-engine redesign, new cancellation mechanism, journal-schema changes,
arbitrary custom stages, or Workbench application work is part of this feature.

## Sequential implementation and verification

1. Inspector formatting, reusable presentation helpers, explicit JSON selection,
   focused human/machine tests, and migration of immediate inspector consumers.
2. Related command presentation and complete machine-client/documentation audit.
   Keep formatting separate from provider operation implementations.
3. Independent integration review, installed-prefix and consumer checks, real
   inspection of retained example placement results, and final documentation.

One general agent works at a time. The parent context coordinates and performs
small documentation changes. Agents must preserve existing tracked/untracked work;
never stage, commit, amend or push, or create AI-attributed repository history.
Read-only Git and fixture-local Git required by tests are permitted. Every Dune
build/test/exec invocation, including nested scripts, must use `-j 20`.

Use `hardcaml_asic_example` for consumer validation. Existing example observation
and placement checkpoints can verify real presentation without repeating EDA.
Refresh its private development provider if needed, preserve its recorded pin,
and provide the activation command required in the user's own shell.

## Completion evidence

### Slice 1 — inspector presentation (2026-10-13)

Delivered default plain-text reports for `observation inspect` and
`checkpoint-inspect`. `flow/hardcaml_asic_flow/presentation.py` is a separate,
installed presentation module: reusable labeled fields/sections and renderers
consume operation results without filesystem probes, revalidation or writes.
The CLI still invokes the same journal reader and checkpoint validator, with the
same compatibility selection, restart-transition checks and exit mapping.

Explicit JSON preserves the full previous payload, including failure envelopes.
All these placements work; command/nested parser defaults use `argparse.SUPPRESS`
so an omitted inner flag does not overwrite an outer selection:

```sh
hardcaml-asic-flow --json observation inspect ATTEMPT
hardcaml-asic-flow observation --json inspect ATTEMPT
hardcaml-asic-flow observation inspect --json ATTEMPT
hardcaml-asic-flow observation inspect ATTEMPT --json
hardcaml-asic-flow --json checkpoint-inspect CHECKPOINT
hardcaml-asic-flow checkpoint-inspect --json CHECKPOINT
hardcaml-asic-flow checkpoint-inspect CHECKPOINT --json
```

Observation output includes stream/cursor, endpoint and recorded plan (both plan
versions), outcome/exit, writer/observation state, stage statuses and finished
durations, and historical artifact identities/paths and other record references.
An unfinished occurrence does not present its initial zero as a measured duration.
Requested endpoint completion, full physical completion, acceptance and external
postchecks remain separate facts. Missing outcomes, unknown/lost writers, empty
lists, unreached/failed/interrupted stages and corrupt prefixes have explicit text.

Checkpoint output separates host validation from runtime/image closure, names
recorded versus expected compatibility, and shows restart capability and requested
transition. `--restart-to` performs validation only. File/dependency counts replace
the full hash inventory. Accumulated metric availability is counted, with at most
five unavailable names/reasons and a remainder count; there are no fresh-measurement,
unit or quality claims. Acceptance remains `not_evaluated`. Inspection errors remain
exit 2 and include stderr diagnostics; JSON stdout contains only the JSON payload.
Successful journal inspection remains exit 0 even for a recorded failed execution.

Immediate machine clients migrated to `--json`: the independent-process reader in
`test/test_flow_observation.py`, the public inspector call in
`test/test_installed_prefix.py`, and installed checkpoint checks in
`test/check_stage_recipes.py`. Immediate flow, OCaml recipe and quickstart guides
now show human and explicit-machine inspector examples.

#### Focused verification

All final commands below passed:

```sh
dune build -j 20 @test/inspector-presentation @test/flow-observation @test/stage-checkpoint @test/flow-cli @test/ocaml-stage-recipes @install
python3 -B test/test_packaging.py
python3 -B test/test_installed_prefix.py InstalledPrefixTest.test_installed_inspector_presentation_suite InstalledPrefixTest.test_installed_flow_observation_suite_and_public_cli InstalledPrefixTest.test_installed_stage_checkpoint_negative_and_composed_suite
python3 -B /tmp/opencode/check_slice1_installed_recipe.py
python3 -B /tmp/opencode/inspect_slice1.py
git diff --check
```

- New inspector suite: **11 passed**, covering flag positions/full payload equality,
  read-only journal inspection, placement versus full signoff/acceptance, explicit
  stage sequences, running/unreached duration handling, live/lost/unknown writers,
  execution failure/interruption with publication, unavailable metrics, missing and
  corrupt records, rejected transitions, clean JSON and stderr errors.
- Existing observation **16**, stage/checkpoint **30**, CLI **43**, packaging **17**
  passed. Recipe contract: **36 accepted / 1,819 rejected**.
- Fresh temporary installed prefix: **3 focused installed tests passed**, including
  the installed 11/16/30-case suites and isolated launcher calls. The new module is
  explicitly included in `flow/dune`; the packaging suite checks all Python files.
- The temporary installed-recipe helper builds/installs using the existing
  `build_prefix` helper (`dune build -j 20 @install` and `dune install -j 20`), then
  runs `check_stage_recipes.py --emitter _build/default/test/stage_recipe_contract.exe
  --provider-prefix TEMP_PREFIX`. Installed read-only success and compatibility,
  transition and changed-host-closure rejection passed.
- Initial new interruption test expected an exception but the runner returns an
  interrupted outcome; corrected that expectation and reran successfully. One
  concurrent fresh-prefix rerun collided with Dune's workspace lock before tests
  began; its sequential rerun passed. No test failures remain.

#### Retained example inspection

Used the current source CLI, `python3 -B -m hardcaml_asic_flow` from `flow/`, for
both human and JSON calls against:

- `/home/wayne/devel/jane/hardcaml_asic_example/_flow_results/observations/20261013T162352616479Z_f0ae62fe`
- `/home/wayne/devel/jane/hardcaml_asic_example/_flow_results/placement-20261013T162305/checkpoints/placement-szaicr8h`
  (with `--restart-to cts`).

| Inspector | Human UTF-8 bytes / lines | JSON UTF-8 bytes / lines |
| --- | ---: | ---: |
| Observation | 2,219 / 37 | 5,648 / 1 |
| Placement checkpoint | 1,614 / 36 | 372,213 / 1 |

Both modes returned exit 0 with empty stderr. Parsed full JSON matched the direct
domain-operation results. Top-level observation keys remain `contract`, `cursor`,
`final_results`, `observation_status`, `schema_version`, `state`, `stream_id`,
`writer_active`; checkpoint keys remain `compatibility_source`, `manifest`,
`runtime_closure_validated`, `validation`. SHA-256 verification before/after showed
all **30 retained files unchanged**. The helper scripts live under `/tmp/opencode`
and are verification aids, not installed project resources.

Representative actual report excerpts:

```text
cursor                 13
requested endpoint     placement
outcome                completed
observation status     final
writer active          no

STAGES (recorded durations)
  implementation.synthesis     completed    4.633 s   exit 0
  implementation.floorplan     completed    4.447 s   exit 0
  implementation.placement     completed    10.882 s   exit 0

COMPLETION AND ACCEPTANCE
requested completion   completed (recorded outcome)
full physical flow     not_recorded
acceptance             not_evaluated
external postcheck     not_evaluated

host validation        passed (host_only)
runtime validated      no
supported targets      cts
requested restart-to   cts
transition validation  passed; no execution performed
checkpoint files       14
external dependencies  1509
host dependencies      1508
image-only dependencies 1

ACCUMULATED METRICS (not fresh boundary measurements)
available values       118
unavailable values     6
```

#### Handoff

At the slice-1 handoff, slice 2 owned presentation of `observation describe`,
`observation read-updates`, `stages`, `finalize`, and `finalization-inspect`, plus
the remaining machine-client/documentation audit (completed below).
Use the presentation helpers with existing returned results and explicit command
context; preserve allocation JSON-lines semantics when updating long operations.
Slice 3 owns full integration, installed-consumer refresh and activation guidance.
No example consumer refresh was performed in slice 1. Prior dirty/untracked work
was preserved; no staging or repository-history operations were performed.

### Slice 2 — related presentation and machine-client audit (2026-10-13)

Implemented human defaults for `observation describe`, `observation read-updates`,
`stages`, `finalize`, and `finalization-inspect`, using `presentation.py` with the
existing returned payloads. Shared stage/duration and publication sections also
serve observation inspect. No persisted schema, provider operation, validation or
selection changed. Formatting performs no probes or additional operation calls.

- Describe summarizes capabilities, events and writer/retention policy, without the
  recursive schema inventory. `--json` returns the full descriptor unchanged.
- Updates retain chronological event order, summarize stage status and publication
  paths, show stream/requested-after/complete-response cursor, and bound output to
  20 events (first/last ten plus omitted count). Empty reads explicitly establish
  no new outcome. JSON returns every complete event, including hashes and data.
- Observed stages flush allocation before recipe/preparation/execution, then show
  execution record path, endpoint/plan, stage statuses and finished durations,
  checkpoint paths/identities and separate requested completion/full physical flow/
  acceptance. Unobserved stages retain the existing one-result JSON behavior.
- Finalize flushes allocation before validation and shows selected checkpoints,
  operation/results/postcheck/acceptance paths and acceptance request versus verdict.
  Receipt inspection uses that same view. Running/missing exits and unpublished
  results are explicit; interruption is distinct from actual `acceptance: fail`.
  Diagnostics go to stderr, including caught failures and operation errors.
- Global, command and all nested observation-query `--json` placements are supported,
  including repeated outer/inner flags. Parser defaults preserve outer selections.
  Observed stages and finalize retain allocation/terminal JSONL, exact payloads,
  ordering and early `flush=True`; readers return one complete object.

#### Migration and contract detection

`--version --json` now advertises **CLI contract 3**, additive `json_commands`,
`json_lines_commands` and `json_flag_placements`. Package version and persisted
record versions remain separate. Changing default stdout is intentionally not CLI
backward compatible: every parsing caller must request `--json`.

Migrated remaining repository machine invocations in `test/test_finalization.py`
and `test/test_installed_prefix.py`. Audited Python/shell/OCaml scripts, tests,
experiments and documentation for public command invocations and JSON parsers.
Experiments call domain APIs directly rather than these public CLI commands, so
needed no migration. The historical development adapters remain outside this
public presentation change. Guides/index/architecture now describe human defaults,
explicit machine payloads, JSONL and cursor polling pipelines.

At the historical slice-2 handoff, searched sibling `hardcaml_asic_example` sources/scripts/docs: no machine calls to
the changed additive commands were found, so no sibling files were edited. Its
`bin/project.ml` and `scripts/asic_dependency.py` require exactly contract 2 and will
reject contract 3 until the final integration agent reviews/updates compatibility
detection and routing tests. **Do not refresh the consumer before that review.**
No consumer refresh or repository-history operation occurred in slice 2.

#### Focused verification

```sh
dune build -j 20 @test/related-presentation @test/inspector-presentation @test/finalization @test/flow-observation @test/stage-checkpoint @test/flow-cli @install
python3 -B test/test_packaging.py
python3 -B test/test_installed_prefix.py InstalledPrefixTest.test_installed_related_presentation_suite InstalledPrefixTest.test_installed_finalization_suite_and_receipt_cli InstalledPrefixTest.test_installed_flow_observation_suite_and_public_cli InstalledPrefixTest.test_installed_shared_cli_contract_version_is_separate_from_records
python3 -B /tmp/opencode/check_slice2_retained.py
git diff --check
```

Related presentation **8**, inspector **11**, finalization **15**, observation **16**,
stage/checkpoint **30**, CLI **43**, packaging **17** pass. The related suite checks
full parsed JSON/JSONL equality to operation/persisted results, global/command/nested
flags, repeated flags, error envelopes, early visibility/explicit flush, single
operation invocation, bounded/empty/reset reads, failed/interrupted stages,
unobserved execution, running/accepted/rejected/interrupted receipt presentation,
and rejected parser combinations. Four fresh-prefix installed tests pass, including
isolated launcher queries and installed related/finalization/observation suites.
Nested prefix build/install commands use `-j 20`. One initial new fixture omitted
the synthetic workspace directory; fixed the fixture and reran successfully.

Read the retained slice-1 example observation and placement execution without EDA:
human updates **1,867 bytes / 29 lines**, full JSON **11,258 bytes / 1 line**;
parsed JSON equals `read_updates`. The stage renderer displays the retained actual
durations, publications and separate `not_evaluated` acceptance. SHA-256 checks
confirmed **16 journal/execution files unchanged**. Temporary verification helper
is under `/tmp/opencode`, outside installed resources.

Representative human excerpts (paths abbreviated):

```text
requested after        0
cursor                 13
updates returned       13
    10 started implementation.placement: running
    11 published implementation.placement: running
       published placement: .../checkpoints/placement-szaicr8h
    12 finished implementation.placement: completed
    13 outcome completed; exit 0

requested endpoint     placement
status                 completed
STAGES (recorded durations)
  implementation.synthesis     completed    4.633 s   exit 0
  implementation.floorplan     completed    4.447 s   exit 0
  implementation.placement     completed    10.882 s   exit 0
requested completion   completed
full physical flow     not_recorded
acceptance             not_evaluated

status                 failed
phase                  validation
acceptance requested   yes
results                not published
external postcheck     not_evaluated
acceptance             not_evaluated
```

#### Slice 3 handoff (historical)

Independent integration review and consumer compatibility/refresh remain pending;
this is not final feature completion. Review contract-3 detection versus the
example's exact contract-2 gates before installation/activation, and verify other
external clients explicitly select JSON and parse JSONL per line. Inspect retained
real finalization results if available, preserving all inputs. All initial dirty/
untracked work remains; no staging, commits, amendments or pushes were performed.

See also [execution ownership and utilization decisions](workbench-execution-boundary.md)
and [explicit-stage implementation](explicit-stage-refactor.md).

### Slice 3 — independent integration (2026-10-13)

Completed the sequential integration review of presentation/CLI/identity and both
earlier slices. Human defaults and explicit JSON are consistent; existing tests
exercise complete object/JSONL equality, allocation visibility and explicit flush,
stderr diagnostics, failures/interruption/unavailable and unfinished values,
single operation invocation/read-only rendering, and global/local/nested parser
flags. No consequential provider rendering defect was found. Persisted schemas,
record hashes and production operation semantics remain unchanged.

Fixed the consequential consumer integration blockers:

- `hardcaml_asic_example/bin/project.ml` and `scripts/asic_dependency.py` now accept
  exactly integer CLI contracts **2 or 3**. Older, unknown future, null, string,
  boolean and floating versions are refused. Project refusal precedes emission;
  refresh refusal preserves the selected generation. Existing API/file/link gates
  remain in force, and the recorded dependency pin is preserved.
- The existing private refresh script's nested `dune install` now also uses `-j 20`.
  Its regression checks every emitted Dune command's job bound.
- New setup/routing regression cases prove both supported versions, human/JSON
  forwarding and unknown/malformed-version refusal. Setup **18**, routing **11**.
- Audited sibling scripts and acceptance clients: metadata uses
  `--version --json`; current emission/description/preflight parsers explicitly
  select `--json`. Bootstrap forwards human `provision` without parsing stdout.
  Historical saved-emitter baseline modes retain their old protocol intentionally.
  No sibling parser consumes the changed additive-command default output.

#### Exact final verification

Commands ran sequentially, with no concurrent Dune workspaces:

```sh
# Provider
dune runtest -j20 --force
python3 -B test/test_installed_prefix.py

# Example
python3 -B scripts/test_asic_dependency.py
python3 -B scripts/asic_dependency.py refresh --source /home/wayne/devel/jane/hardcaml_asic --mode development
source /home/wayne/devel/jane/hardcaml_asic_example/.dev/asic/current/activate.sh
ocamlfind query hardcaml_asic
command -v hardcaml-asic-flow
dune runtest . -j20
python3 -I -B /tmp/opencode/check_slice3_installed_retained.py
hardcaml-asic-flow --version --json
python3 -B scripts/asic_dependency.py status --json

# Both checkouts
git diff --check
```

All exited **0**. Full forced provider tests include inspector **11**, related
presentation **8**, observation **16**, finalization **15**, stages/checkpoints
**30**, CLI **43**, packaging **17**, all other Python/OCaml and bundle/RTL checks;
recipe contract **36 accepted / 1,819 rejected**. The full fresh-prefix suite ran
**53 tests**, including installed presentation/domain suites and isolated launchers.
Its nested build/install commands use `-j 20`.
Exact example `dune runtest . -j20` passed under the refreshed private installation,
including new setup/routing tests, CLI purity, bundle checks, both RTL source sets
at **11,429 edges** and their rejected negative oracles. Other unchanged aliases
were Dune-cached; no new EDA or provisioning was required.

#### Private installation and activation

Published generation:
`/home/wayne/devel/jane/hardcaml_asic_example/.dev/asic/generations/90770d6ce6f04696b3b0082fb3898944`.
Receipt `receipt.json` records observed provider base
`ebdcfbfec88cc05f433bec8d289d98b7ad76d4cf` and captured snapshot SHA-256
`be2db93d3f1b92a8b240167ebadd0b4c0a81484e78356c56cec867f5b19f8e4a`.
These are dirty development capture facts, not P6.5 source stamping. The unchanged
recorded pin remains `1714764859274f80a9f5ad207421a04601824e99`; global opam was
not changed. Final documentation edits follow the installed snapshot.

Activation was actually sourced in the verification shell. Library and launcher
resolved this generation; status reported `active_is_published: true`,
`active_is_older: false`, `active_library_path_is_first: true`. Installed identity
reports contract **3**, package **0.1.0**, record schemas **[1]**, `stamped: false`.
The user must also activate in their own shell (refresh cannot do that):

```sh
source /home/wayne/devel/jane/hardcaml_asic_example/.dev/asic/current/activate.sh
```

#### Actual installed retained-record inspection

The helper used the activated installed launcher from `/tmp/opencode`, and domain
modules imported from that same immutable generation, for the exact slice-1
observation and placement checkpoint paths above (`--restart-to cts`). It also
inspected the retained accepted finalization
`/tmp/opencode/librelane-slice6-finalizations/20261013T053638859111Z_5059094a`,
plus observation describe and reads after cursors **0** and **13**. All human and
JSON calls returned **0** with empty stderr. Full parsed JSON equals the installed
domain results, including nested manifests, dependency hashes, event data and
finalization evidence; global JSON and nested observation JSON were also checked.

| Command | Human bytes / lines | Complete JSON bytes / lines |
| --- | ---: | ---: |
| Observation inspect | 2,219 / 37 | 5,648 / 1 |
| Placement checkpoint inspect | 1,614 / 36 | 372,213 / 1 |
| Observation describe | 864 / 22 | 3,426 / 1 |
| Updates after 0 | 1,867 / 29 | 11,258 / 1 |
| Updates after 13 | 517 / 11 | 159 / 1 |
| Accepted finalization inspect | 1,578 / 27 | 25,695 / 1 |

Observation/checkpoint top-level keys remain those listed in slice 1. Describe
retains `schemas`; updates retain all **13** events and cursor **13**. Finalization
retains all **24** top-level keys, including `binding`, `commands`, `mapped_files`,
`postcheck_collateral`, `selected_evidence`, results and acceptance.
Before/after SHA-256 equality proved **531** retained observation, entire placement
workspace and accepted finalization files unchanged, plus byte-equal dependency pin.

Actual installed excerpts (paths omitted here; full reports retain them):

```text
requested endpoint     placement
outcome                completed
  implementation.placement     completed    10.882 s   exit 0
requested completion   completed (recorded outcome)
full physical flow     not_recorded
acceptance             not_evaluated

host validation        passed (host_only)
runtime validated      no
supported targets      cts
transition validation  passed; no execution performed
external dependencies  1509
available values       118
unavailable values     6

requested after        13
updates returned       0
  none after the requested cursor; no new outcome is implied

status                 completed
phase                  acceptance
acceptance requested   yes
runtime validation     not established
external postcheck     completed
acceptance             pass
acceptance report      not recorded
```

The historical accepted receipt lacks the newer optional runtime-validation and
acceptance-report fields; the human report correctly avoids inventing them. Its
recorded acceptance is still `pass`; inspection does not rerun acceptance.

No feature integration failures remain. Existing limits remain owner adoption of
the committed consumer pin, unstamped source identity/P6.5–P6.6 gates, and proposed
Workbench supervision/integration. Earlier contract-2 closeouts and handoffs are
historical; the current interface is contract 3. All preexisting tracked/untracked
work was preserved. No repository staging/history or shared-opam changes occurred.
