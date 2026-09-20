# Legacy flow consolidation

Status: migration specification, 2026-09-20.

This document is an implementation brief for replacing the remaining legacy and
consumer-vendored ASIC flow paths with one authoritative flow maintained by
`hardcaml_asic`. It is intentionally prescriptive enough for an autonomous coding
agent to execute. It covers this repository and the reference consumer at
`../scaf`.

The migration is complete only when a clean consumer can install one pinned
`hardcaml_asic` revision, emit a bundle, execute and assess that bundle with the
tooling installed by the same revision, and preserve restorable evidence without
copying flow implementation into the consumer. Keeping an old path available
"just in case" is not completion.

## 1. Problem statement

The declaration and bundle boundary is sound. The remaining problem is delivery
and coexistence:

- `hardcaml_asic` installs the OCaml library but not its Python flow tooling.
- `scaf` vendors `phase4.py`, `report.py`, and `archive.py` under `adopted_*`
  names and carries a separate orchestration/provisioning implementation.
- Normal `scaf` bootstrap path-pins the sibling `hardcaml_asic` worktree,
  including uncommitted changes, instead of enforcing
  `tinytapeout/asic-dependencies.lock`.
- The old staged Tiny Tapeout project remains buildable from a hand-written
  wrapper, `info.yaml`, and `config.json`.
- Generic-looking commands and some routine tests still select the legacy inputs.
- The strongest adopted-bundle check is not part of the canonical build or CI.

This has produced real drift. The vendored `scaf` reporter rejects its valid
synthesis-only P0.7 result because it always requires physical timing and signoff.
The newer reporter in this repository accepts the same result under explicit
synthesis-only criteria. The newer archiver also preserves and verifies a complete
input bundle, while the vendored archiver does not do so automatically.

The legacy staged project does **not** currently contaminate an adopted emitted
bundle. Do not redesign the declaration/bundle API to solve that nonexistent
problem. Remove the duplicate execution paths and distribution gap instead.

## 2. Target architecture

There is one source implementation for each responsibility.

### `hardcaml_asic` owns

- Typed project, target, timing, resource-policy, and bundle APIs.
- The immutable bundle schema and validation rules.
- Generic TT/LibreLane preflight, execution, postcheck, collection, reporting,
  and evidence archiving.
- Generic toolchain provisioning and exact collateral checks.
- Operation-aware acceptance for `synthesis` and `full` runs.
- Installation of the library and flow CLI from one versioned source artifact.
- Tests for bundle compatibility, malformed evidence, interrupted runs, archive
  integrity, and restoration.

### A consumer owns

- Its Hardcaml design and top-level project declaration.
- Its explicit implementation and simulation source inputs.
- Its design-specific testbench and any design-specific postcheck data.
- The exact `hardcaml_asic` source revision it depends on.
- A small bundle emitter and, if desired, a thin repository-local command that
  invokes the installed CLI.
- Human interpretation notes beside archived machine evidence.

### A consumer must not own

- Copies or forks of the generic runner, reporter, archiver, or provisioner.
- A second interpretation of synthesis/full acceptance.
- Duplicated support-tools, PDK, LibreLane, or Python pins that can disagree with
  the emitted bundle or installed flow tooling.
- Hand-maintained flow configuration that duplicates generated bundle content.
- A second orchestration state machine.

Thin wrappers are allowed only when they translate stable consumer concepts such
as output directory, design kind, emitter command, and testbench path into the
installed CLI. They must contain no flow validation, run selection, acceptance,
or archive logic.

## 3. Required public interface

Install a command named `hardcaml-asic-flow` with the `hardcaml_asic` package.
The exact internal Python packaging layout is an implementation choice, but the
command and all of its imported modules must work outside a source checkout.

At minimum, preserve these operations:

```text
hardcaml-asic-flow provision
hardcaml-asic-flow provision --check
hardcaml-asic-flow preflight BUNDLE [tool locations]
hardcaml-asic-flow run BUNDLE --runs DIR --stage synthesis|full
hardcaml-asic-flow postcheck RUN --testbench FILE
hardcaml-asic-flow collect RUN
hardcaml-asic-flow report RUN
hardcaml-asic-flow archive RUN --output DIR
```

An `all` or `execute` orchestration command may compose these operations from an
already emitted bundle. Individual operations remain useful for schedulers,
recovery, and diagnosis. There must still be only one implementation underneath.

Interface rules:

- No-argument invocation prints help. Starting a multi-hour physical run requires
  an explicit command.
- A resumed operation takes an explicit run directory. It never guesses the
  newest run.
- `run` creates a unique run directory and prints or records its path in a
  machine-readable way.
- `synthesis` acceptance requires mapped area/cells and zero unresolved synthesis
  failures. It explicitly marks physical timing, DRC, LVS, antenna, and physical
  postchecks as not evaluated.
- `full` acceptance requires timing, signoff checks, and required postchecks.
- Partial, contradictory, malformed, or unknown-stage records fail; they are not
  reinterpreted as a smaller operation.
- Preflight verifies every bundle file hash, external reference, collateral
  revision, supported schema, adapter, and requested tool version.
- Archive verifies run/manifest identity, every declared bundle file, copied
  source linkage, and postcheck inputs before publication.
- Archive contains a deterministic `input-bundle.tar.gz` and digest in addition
  to the result records and selected reports.
- Archive publication is atomic and does not destroy a previous good archive on
  failure. A human-owned `README.md` is preserved.
- Diagnostics distinguish missing evidence, failed evidence, and evidence not
  required for the requested operation.
- `--version` reports the installed package/tool version. Run and archive records
  record it.

Do not silently retain incompatible old command behavior. A short, explicit error
that names the replacement is preferable to a compatibility alias. Remove such
errors after one documented migration window if there are no external users that
need them.

## 4. Version and lock authority

The OCaml library and flow CLI must be installed from the same package artifact.
This removes the current requirement to install the library and separately clone
an exactly matching repository revision for scripts.

The consumer records one full `hardcaml_asic` Git revision. Normal consumer setup
must install that revision. A sibling path pin is a development override, never
the default, and must be explicit, for example:

```text
./bootstrap.sh --hardcaml-asic-path ../hardcaml_asic
```

When a path override is used, print and record:

- the checkout's `HEAD`;
- whether it is dirty;
- whether it differs from the consumer lock;
- that the result is a development build if either comparison fails.

Release/evidence operation should reject a wrong or dirty revision unless the
caller supplies a named waiver. Waivers are written into preflight, run, and
archive records; they are never only console output.

There must also be one authority for external collateral:

- The emitted bundle records its requested support-tools revision, PDK revision,
  LibreLane version, and Python version.
- The installed flow package ships any defaults needed before a bundle exists.
- Once a bundle exists, preflight treats the bundle as authoritative and rejects
  provisioned collateral that disagrees.
- Delete duplicate consumer pin files or fields that merely copy these values.
  Keep only genuinely consumer-owned dependencies.

Do not claim exact Python reproducibility while allowing a mismatch by default.
Make exact matching the default for evidence-producing runs. A mismatch must be
an explicit, recorded waiver.

## 5. Current inventory

Review this inventory against the worktrees before editing. Do not remove a file
until its useful tests or behavior have moved to the authoritative path.

### Authoritative implementation candidates in this repository

- `scripts/phase4.py`
- `scripts/report.py`
- `scripts/archive.py`
- `scripts/toolchain.sh`
- `scripts/flow.sh`, currently an example-oriented wrapper rather than a portable
  consumer CLI
- `test/test_phase4.py`
- `test/test_report.py`
- `test/test_archive.py`
- `test/check_bundle.py`

The current worktree contains uncommitted operation-aware reporter and complete
archive work. Preserve and review those changes; do not overwrite them with the
older `scaf` copies.

### Vendored adopted implementation in `scaf`

- `tinytapeout/scripts/adopted_phase4.py`
- `tinytapeout/scripts/adopted_report.py`
- `tinytapeout/scripts/adopted_archive.py`
- `tinytapeout/scripts/adopted-flow.sh`
- `tinytapeout/scripts/bootstrap-toolchain.sh`

Only design-specific behavior should survive in `scaf`, notably selection of its
testbench and its design/bundle emitter. Express that behavior through CLI options
or a small consumer adapter rather than retaining a fork.

### Legacy staged flow in `scaf`

- `tinytapeout/src/project.v`
- `tinytapeout/info.yaml`
- `tinytapeout/src/config.json`
- `tinytapeout/scripts/stage-project.sh`
- `tinytapeout/scripts/harden-cmos5l.sh`
- `tinytapeout/scripts/precheck.sh`
- `tinytapeout/scripts/check-p0.sh`
- legacy portions of `tinytapeout/test/dune` and
  `tinytapeout/test/Makefile`
- `protemu check`, `stage`, `legacy-harden`, and legacy `precheck` command wiring
  in `bin/protemu.ml`
- `bootstrap.sh --legacy-project`
- compatibility-only bootstrap flags and no-op aliases

Some tests around wrapper behavior remain valuable. Migrate them to compile or
simulate the emitted implementation and simulation source sets before deleting
their legacy inputs.

### Consumer code to retain

- `bin/asic_bundle.ml`, after removing any repeated CLI boilerplate if useful.
- The observable and memory designs and their bundle declarations.
- Design-specific testbenches under `tinytapeout/test/`.
- Root `flow.sh`, reduced to a thin build/emit/invoke wrapper, or replaced by a
  documented direct installed-CLI command.
- `flow_results/` historical evidence. Do not rewrite old evidence to look as if
  it was produced by the new flow.

## 6. Migration sequence

Execute the migration in dependency order. Keep each phase testable.

### Phase A: stabilize the shared tools

1. Finish and test operation-aware reporting in `scripts/report.py`.
2. Finish and test complete input preservation and atomic publication in
   `scripts/archive.py`.
3. Add adversarial tests for contradictory stage/status records, malformed
   numeric evidence, changed bundle files, path traversal, symlinks, interrupted
   publication, and restoration without the original source tree.
4. Keep `phase4.py`, reporter, and archiver behavior independent of repository
   layout and example names.
5. Resolve stale docstrings or usage text that still describes full-only
   acceptance.

Exit gate: the shared test suite passes, and the shared reporter accepts the
committed `scaf` P0.7 synthesis evidence while still rejecting partial or forged
evidence.

### Phase B: install one reusable CLI

1. Create the installed `hardcaml-asic-flow` entry point and package its Python
   modules/data with `hardcaml_asic`.
2. Remove assumptions that companion scripts are found relative to a repository
   checkout; locating installed package data is allowed.
3. Make provisioning consume shipped lock/default data and make execution consume
   the bundle's requested tool data.
4. Add an installation smoke test that installs into a fresh prefix and invokes
   `hardcaml-asic-flow --version`, `--help`, report, archive, and a PDK-free
   preflight fixture from outside the source tree.
5. Extend the existing separate-project smoke test beyond
   `Single_port_ram.Config`: emit a minimal bundle and exercise the installed
   tooling that does not require external EDA software.
6. Update package metadata and `docs/consumer-installation.md`; consumers must no
   longer clone a matching checkout to obtain scripts.

Exit gate: deleting or hiding the source checkout does not break the installed
CLI or smoke tests.

### Phase C: migrate `scaf` to the installed flow

1. Change normal bootstrap to install the exact revision from
   `tinytapeout/asic-dependencies.lock`.
2. Add an explicit local-path development override with dirty/revision reporting.
3. Replace `adopted-flow.sh` logic with calls to the installed CLI. Prefer one
   root entry point and no second nested wrapper.
4. Pass the selected emitted bundle and design-specific testbench explicitly.
5. Remove the copied runner, reporter, archiver, and generic provisioner.
6. Move fast adopted metadata/bundle validation into `dune runtest`, the flow's
   build step, or both. Keep container lint/synthesis under a clearly named slower
   alias if necessary.
7. Make separate invocations require an explicit run directory everywhere.
8. Remove or implement native execution consistently. Do not advertise
   `--no-container` if the canonical flow and postcheck cannot honor it.
9. Correct `docs/flow.md`, `docs/environment.md`, `docs/asic-adoption.md`, and
   `tinytapeout/README.md` to describe only the new path.

Exit gate: no `scaf` file imports or executes an `adopted_*.py` copy, and the
canonical flow passes from a clean detached consumer worktree with no sibling
`hardcaml_asic` checkout.

### Phase D: migrate tests, then delete the legacy staged flow

1. List every assertion currently provided by `check-p0.sh`, `@rtl`, wrapper
   simulation, lint, generic synthesis, and precheck.
2. Re-home still-relevant assertions against emitted bundle sources or the shared
   flow CLI.
3. Make `protemu check`, if retained, check the adopted declaration and emitted
   bundle. Otherwise remove it and document the direct command.
4. Delete legacy command wiring and `bootstrap.sh --legacy-project`.
5. Delete the hand-written wrapper, metadata, configuration, staging, hardening,
   and precheck implementation listed above.
6. Delete obsolete Makefile/Dune rules after their useful coverage has moved.
7. Search code, CI, and operating documentation for every removed filename and
   command. Historical reports may retain references when clearly labelled as
   historical and not presented as instructions.

Exit gate: a fresh checkout has no runnable legacy flow and no editable duplicate
of generated bundle configuration.

### Phase E: prove and document the consolidated path

Run at least:

```text
fresh-prefix package/CLI installation smoke test
hardcaml_asic unit and script tests
scaf dune build and runtest
scaf adopted bundle determinism/conflict checks for observable and memory
scaf observable full physical flow and postchecks
scaf memory synthesis-only flow and operation-aware report
archive, delete original experiment/source access, restore, and revalidate
```

Record exact commands, revisions, waivers, bundle identities, run IDs, and archive
digests. One clean full physical run is sufficient to retire the old physical
path; do not require equivalence to old timing because the legacy run lacked the
adopted SDC and is not timing-comparable.

## 7. Required tests and CI

Fast required checks:

- Bundle emission is byte-for-byte repeatable from identical clean inputs.
- Observable and memory bundles have distinct expected source sets.
- Protected configuration conflicts are rejected.
- Every manifest path remains inside the bundle and matches its hash.
- Installed CLI works outside both repositories.
- Consumer lock and installed package revision agree in normal mode.
- A dirty/wrong local override is visible and rejected for unwaived evidence.
- Synthesis-only acceptance passes valid synthesis evidence and does not require
  physical checks.
- Full acceptance rejects absent timing, DRC, LVS, antenna, or postchecks.
- Unknown/contradictory stages and malformed values fail.
- Archive detects changed manifests, sources, netlists, GDS, and testbenches.
- Archive replacement failure preserves the previous archive and human README.
- Restored input bundle revalidates without the original source tree.

Slow explicit checks:

- Wrapper implementation and simulation traces.
- Verilator lint and generic Yosys synthesis of emitted RTL.
- Mapped LibreLane synthesis for observable and memory designs.
- Full physical flow, TT precheck, and gate-level simulation for the observable
  design.

CI should run all fast checks. Slow checks may be scheduled or self-hosted, but
their command must use the same installed flow CLI rather than a CI-only path.

## 8. Deletion and search checklist

Before declaring completion, searches outside historical evidence should return
no active references to:

```text
adopted_phase4.py
adopted_report.py
adopted_archive.py
adopted-flow.sh
stage-project.sh
harden-cmos5l.sh
check-p0.sh
legacy-harden
--legacy-project
tinytapeout/src/project.v
tinytapeout/src/config.json
tinytapeout/info.yaml
```

Also check for semantic leftovers rather than names alone:

- selecting the newest run implicitly;
- full-flow checks applied to synthesis-only results;
- default Python mismatch waivers;
- sibling-path pinning without an explicit development option;
- copied support-tools/PDK/LibreLane pins;
- two no-argument behaviors for nominally equivalent flow commands;
- docs that describe completed adoption as planned work;
- CI that validates only committed legacy RTL.

## 9. Non-goals

- Do not redesign `Project`, `Build`, `Resolved_build`, or `Bundle` merely because
  both low-level and convenience APIs exist.
- Do not add commercial-flow abstractions without a real consumer.
- Do not make `hardcaml_asic` own consumer RTL, source enumeration, or testbench
  semantics.
- Do not preserve legacy commands indefinitely through hidden aliases.
- Do not rewrite historical evidence directories.
- Do not make physical execution part of ordinary fast `dune runtest`.
- Do not weaken immutable bundle or evidence checks to simplify migration.

## 10. Completion criteria

All of the following must be true:

- One installed `hardcaml_asic` artifact supplies both the OCaml API and generic
  flow CLI.
- `scaf` records and normally installs one exact `hardcaml_asic` revision.
- No consumer-vendored generic flow implementation remains.
- No runnable legacy staged-project flow remains.
- There is one documented command path for build, emission, execution, reporting,
  and archiving.
- Synthesis-only and full-flow acceptance are both tested and correctly scoped.
- Every evidence archive contains and verifies its complete immutable input
  bundle.
- Fast adopted-boundary checks run in CI.
- A clean detached `scaf` worktree completes the workflow without a sibling
  checkout or generated-input edits.
- Current operating docs contain no instructions for the removed flow.

When these criteria pass, update the documentation index and phase plans to mark
the migration complete. Preserve this document as the decision and execution
record, changing its status from migration specification to completed migration
record and linking the final evidence.
