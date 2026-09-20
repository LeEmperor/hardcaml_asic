# ASIC P6 status and next handoff

Planning snapshot: 2026-09-20. Owner: shared tooling distribution in
`hardcaml_asic`. See the [bounded implementation plan](p6-implementation-plan.md)
and the authoritative [P6 gates](phase_plan.md#11-p6--shared-tooling-distribution).

## Worktree identity and scope

- Library HEAD inspected: `cf31e93305a7e11cdfb360c83eb2c0a16dbfbe3a`.
  It is **not** the identity of the inspected source snapshot. Existing modified
  files included `scripts/report.py`, `scripts/archive.py`, their tests,
  `docs/{README,flow,immediate_future,phase_plan,usage}.md`, and SRAM/memory
  documents. `docs/flow_legacy_migration.md` and `docs/sram-status.md` were
  untracked. P6.1/P6.2 are newer than HEAD and must survive any extraction.
- Consumer HEAD inspected: `61384c35e3b73cd198cb7ee82efc9c2c4cc34a5c` in
  `/home/wayne/devel/jane/scaf`. Existing modified/untracked work covers core
  implementation, models, tests, Dune wiring, and phase/verification documents.
  Its dependency lock still names ASIC
  `a257424c3ae31fd6ee10cea052cc7577f15d2677`. No consumer files were edited.
- Applicable instructions: `/home/wayne/devel/jane/AGENTS.md`; no repository-local
  or nested `AGENTS.md` was found in either checkout. Recheck on handoff.
- This planning task adds only this note and `p6-implementation-plan.md`. It does
  not change pins, installed environments, phase checkboxes, or SRAM status, and
  has not run synthesis, physical flows, bootstrap, or installation.

## Completed work

Read P6/P7/M4 and the overlap rules, migration brief, immediate priorities,
installation/flow/usage guides. Inspected package stanzas, shared scripts and
tests, consumer entry points/locks/emitter, orchestration tests and CI. Directly
diffed each `adopted_*.py` against the **current** library scripts. The plan now
contains the operation contract, ownership/deviation inventory, installation
layout, identity/provisioning authority, file map, implementation units,
fresh-prefix acceptance procedure, and P7 handoff conditions.

P6.3 remains **open** while P6.3b is implemented. P6.3a is complete:
`scripts/phase4.py` has explicit testbench-top plumbing, a structured internal
run outcome with absolute paths, actual in-run preflight persistence, and
consistent finalized SIGINT/SIGTERM behavior for run and postcheck. The
development adapter still prints one `run.json` path. Its PDK-free mocked-process
suite passes 12 tests; exact evidence is recorded in the implementation plan.
P6.4–P6.6 remain open designs, not delivered capabilities. P6.1/P6.2 and
P0–P5/M3 status are unchanged. M4 remains open.

## Decisions and coordination

The plan recommends Dune-installed private Python modules plus a launcher in the
same opam artifact; no separate pip package. It adds only `execute` orchestration
and explicit `--testbench-top`, dependency identity and named-waiver inputs.
There is no blocking user product decision. The owner should acknowledge the
documented migration-brief clarifications (native synthesis only, exact requested
Python minor, explicit testbench top, and reporting JSON exit behavior) before
P6.3 closes. A user-authorized commit/candidate publication is needed later;
this task grants no commit or pin-update authorization.

Shared files needing coordination:

- `docs/phase_plan.md`, `docs/immediate_future.md`, `docs/README.md`, `docs/usage.md`,
  `docs/flow.md`: reread before any narrow edits; phase plan owns parent task IDs.
- `scripts/report.py`, `scripts/archive.py`, corresponding tests: preserve the
  uncommitted P6.1/P6.2 base; migrate it, never the older consumer copies.
- `lib/bundle.ml`, `lib/target.ml`, `test/check_bundle.py`, `test/dune`: proposed
  additive generator identity and installation wiring can intersect SRAM work.
  Agree the optional provenance field/test ownership with the S owner before
  editing. No resource contract, backend, macro collateral, S-series status, or
  SRAM model test changes are part of P6.
- Consumer owner controls `scaf` bootstrap, lock, emitter, wrappers, and CI.
  Inventory/coverage planning is safe now; runtime replacement waits for the
  conditions in the implementation plan. Preserve working paths until covered.

## Current bounded task: P6.3b

Add the source-only parser/dispatcher and fixed injected composition regressions
needed to settle the matrix. Do not install or migrate it. P6.4a moves the single
source implementation into the package after this gate.

### Self-contained implementation prompt

> In `/home/wayne/devel/jane/hardcaml_asic`, implement **ASIC P6.3a only** from
> `docs/p6-implementation-plan.md`. Read applicable AGENTS.md, git status, this
> status note, the P6 section of `docs/phase_plan.md`, and the current versions of
> `scripts/phase4.py`, `scripts/report.py`, `scripts/archive.py` and their tests.
> Preserve the newer uncommitted P6.1/P6.2 work and all concurrent SRAM work.
> Add explicit testbench-top plumbing to the existing postcheck implementation;
> retain the old example script's documented default only in its development
> adapter, with the future public CLI requiring the argument. Refactor run
> execution to return an internal run outcome (absolute run/record paths, ID,
> status and exit code) without relying on stdout parsing, while preserving the
> current script's one-line run.json output. Save the actual in-run preflight
> report as RUN/preflight.json. Apply SIGINT/SIGTERM finalization to run and
> postcheck, preserving interrupted records and terminating child process groups;
> public signal statuses will be 130/143. Add PDK-free mocked-process tests for
> these boundaries, including failure before allocation, failure/interruption
> after allocation, explicit non-example testbench top, and no partial success.
> Do not change bundle bytes, acceptance policy, archive behavior, dependency
> pins, installed environments, or scaf runtime code. Do not provision or launch
> EDA tools. Do not commit/push/reset/discard. Run the targeted Python regressions
> and `git diff --check`; update the two P6 notes with exact commands/results.
> Keep P6.3 open until P6.3b's boundary cases also pass. Stop after P6.3a with a
> bounded continuation prompt.

## Validation of this planning change

Documentation-only checks passed:

```sh
git diff --check
git diff --no-index --check /dev/null docs/p6-implementation-plan.md
git diff --no-index --check /dev/null docs/p6-status.md
```

A local Markdown-link validation checked all 19 links in these two documents,
including heading fragments: all targets resolve. Final git status inspection in
both repositories showed the same pre-existing change inventory plus these two
new P6 documents in the library checkout. No phase-plan edit was necessary.
Existing test counts quoted in the plan are an inventory/previous phase evidence,
not a claim that implementation or installation gates were rerun by this planning
task. No implementation tests were required for these documentation-only changes.
