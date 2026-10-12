# Consumer dependency selection and local refresh

Implementation contract and command reference, 2026-10-12, for
`hardcaml_asic_example`. The [central phase plan](../phase_plan.md)
owns current status and [closeout evidence](../phase_plan.md#consumer-refresh-and-real-checkout-emitter-closeout).
The original brief below defines the implemented bounded workflow.

## Goal and ownership

An ordinary example build should use the deliberately selected ASIC library,
rather than accidentally finding an older package in the shared opam switch.
Local library edits must be testable without a commit or a release version bump.
The owner accepts an explicit refresh step followed by shell activation.

The example owns its dependency record, refresh command, private installation
store and activation instructions. Its OCaml code continues to depend on
`hardcaml_asic` by package name; it contains no handwritten dependency digest.
The provider supplies its existing Dune installation and CLI. Authoritative
embedded source identity remains ASIC P6.5a, not a second identity system here.

## Two explicit source modes

| Mode | Inputs | Meaning |
| --- | --- | --- |
| Recorded revision | Consumer dependency record plus an explicit available source repository | Build the recorded committed source, without silently using working-tree edits |
| Local development | Explicit source checkout path | Build a captured snapshot of current files, including relevant uncommitted changes; leave the recorded revision unchanged |

The record contains a schema version, package/repository identity and full commit
revision. Select a real available revision containing the renamed API; do not
invent a release or claim the dirty tree is that revision. No dependency fetch,
opam pin, package installation into a shared switch, or project commit is implicit.
The implementation requires an existing local repository for both modes and
diagnoses a missing recorded revision rather than fetching it.

## Refresh and publication

1. Validate arguments and acquire a consumer-store writer lock. Report conflicting
   refreshes explicitly; never let two writers publish inconsistent selections.
2. Capture the selected source into private staging. Recorded-revision mode reads
   committed bytes; development mode includes relevant tracked/untracked inputs
   without `.git`, build products or provisioned toolchains. Preserve required
   internal symlinks. Do not compile a moving source tree and call it a snapshot.
3. Build with the existing compiler/dependencies and install **both library and
   CLI** into a fresh generation under a consumer-owned ignored directory.
4. Validate that the generation contains the expected public API/runtime data and
   that a small consumer can resolve it. Save a refresh receipt describing mode,
   source location, recorded dependency, observed base revision/source state and
   refresh time. Any snapshot checksum is local bookkeeping, not P6.5 artifact
   identity or proof of a release. The installed CLI may still report unstamped.
5. Publish the selected generation atomically only after success. A failed build,
   install or verification leaves the previous usable selection and receipt intact.

The example uses the last successfully refreshed generation. Subsequent edits to
the library checkout do not change that installation. Keep old generations while
shells may still reference them; automatic destructive cleanup is out of scope.
Never delete or overwrite arbitrary user directories as part of refresh recovery.

## Activation and inspection

Provide a shell activation file for the selected generation. It sets the package
search path and CLI PATH with correct shell quoting, preserves unrelated entries,
and avoids accumulating stale managed prefixes on repeated activation. Ordinary
`dune build` (and the owner's `db` wrapper if it preserves the environment) then
uses that library. Explicitly document reactivation after a successful refresh;
an already activated shell must not silently jump between generations.

A read-only status command reports the recorded dependency, selected generation,
development override/mismatch and refresh receipt. Distinguish the published
selection from an older generation still active in the caller's environment.
Do not treat the source checkout's current state as the installed generation's
identity. Missing/incomplete setup produces an actionable diagnostic.

## Bounded implementation slices

1. **Setup tool and tests:** record format, source modes, snapshotting, isolated
   build/install, publication, status and activation. Tests inject build/install
   processes and failures; fixture Git commits use a synthetic test identity.
2. **Real dependency and emitter acceptance:** refresh the actual provider,
   activate in a subprocess, build the FIFO emitter without the previous manual
   `_build/install` override, run existing tests and emit twice from the real
   example checkout. Verify recorded revision/input state, bundle equality and
   generated RTL. Capture honest dirty-input provenance when applicable.
3. **Documentation/review:** record actual commands and evidence in the consumer
   README and central plan. No provider observation implementation or physical
   flow is part of this work.

## Acceptance

- Refreshing local edits requires no source commit, network or shared switch change.
- Recorded mode uses the exact recorded revision despite local working-tree edits.
- Both modes reject missing/incompatible inputs without replacing a good selection.
- Failed build/install/validation and conflicting refreshes preserve the last good
  generation; source changes after capture do not alter it.
- Activation selects the same prefix for library and CLI; repeated activation and
  paths with spaces work. A small consumer proves resolution against that prefix.
- FIFO build, simulation, bundle and strict generated-RTL acceptance pass after
  activation. Normal real-checkout emission records actual source provenance.
- Agents issue no direct Git commands or project mutations. Setup/test scripts
  may inspect source repositories and create disposable fixtures. Only fixtures
  commit, with author and committer `Bundle test <bundle@test.invalid>`, no remotes
  and no model attribution. No project staging, commits, pushes or shared opam pin changes.

Release source stamping, compatibility waivers, external EDA provisioning and full
source-access-denied installation acceptance retain their existing ASIC P6 gates.

## Implemented commands

Run in `hardcaml_asic_example` with the existing compiler, Dune, ocamlfind and
dependencies. To use the current successful installation:

```sh
. .dev/asic/current/activate.sh
dune build @all
python3 scripts/asic_dependency.py status --json
```

The owner's `db` wrapper can replace the build command if it preserves the
activated environment. To capture future local provider edits:

```sh
python3 scripts/asic_dependency.py refresh \
  --source /home/wayne/devel/jane/hardcaml_asic --mode development
. .dev/asic/current/activate.sh
dune build @all
python3 scripts/asic_dependency.py status --json
```

Use `--mode recorded` instead to install the committed baseline selected by
`asic-dependency.json`. Its initial package/repository are `hardcaml_asic` and
`https://github.com/LeEmperor/hardcaml_asic.git`, revision
`1714764859274f80a9f5ad207421a04601824e99`. Neither refresh mode edits the record.
It is an explicit consumer expectation, not a shared opam pin or full environment
lock, and still awaits owner commit.

The global `--store PATH` and `--record PATH` options precede the subcommand.
`--remove-source-build-override` on refresh explicitly retires the exact selected
source's old `_build/install/default/lib` override during activation; unrelated
paths are preserved. Spaces/apostrophes are supported; symlinked store paths and
colons/newlines in store paths are rejected. Old/failed generations are retained.

Status reports `published_generation`, `environment_active_generation`,
`active_is_published`, `active_is_older` and `active_library_path_is_first`, plus
development/base differences and the receipt. These describe selection and the
caller's environment, not an embedded identity check. An already activated shell
keeps its old library/CLI until re-sourced. Subsequent provider documentation edits
do not require refreshing: the installed generation captures refresh-time bytes.

Setup tests: `python3 scripts/test_asic_dependency.py` (also in ordinary
`dune runtest`). Full consumer checks are `dune build @all`, `dune runtest --force`
and `dune build @acceptance-strict --force`. The
[consumer emitter instructions](../../../hardcaml_asic_example/README.md#bundle-and-generated-rtl-acceptance)
give the real-checkout command with `--require-rtl --real-checkout --work-dir`;
always choose a fresh work directory. The central plan records the completed
passes and preserved outputs, including the initial Dune path fixes. The local
receipt and copied dependency record do not deliver ASIC P6.5 source stamping.
