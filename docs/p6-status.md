# ASIC P6 status and next handoff

Planning snapshot: 2026-09-20. Owner: shared tooling distribution in
`hardcaml_asic`. See the [bounded implementation plan](p6-implementation-plan.md)
and the authoritative [P6 gates](phase_plan.md#11-p6--shared-tooling-distribution).

## Worktree identity and scope

- Library HEAD is `037e670f51a1d44dbba1a885d9c97e4fd4196a10`, unchanged by this
  session, and **dirty**. P6.3, P6.4a and P6.4b edits are uncommitted on it, and
  the same worktree carries separately owned SRAM and consumer-documentation work
  this session did not touch (`docs/sram-*.md`,
  `docs/sram-target-compatibility.md`, `evidence/sram-flow-feasibility/`,
  `experiments/sram_flow_feasibility/`). Nothing was committed, amended, reset
  or discarded. That hash does not identify what was tested.
- Consumer HEAD is `a0e47ceb096ab710ad5b4b08005dc753222c51d3`. Its modified
  files are consumer-owned protocol/host work. Its dependency lock still names
  ASIC `a257424c3ae31fd6ee10cea052cc7577f15d2677`. No consumer file was read for
  edit or changed.
- Applicable instructions: `/home/wayne/devel/jane/AGENTS.md`; no repository-local
  or nested `AGENTS.md` exists in either checkout. Recheck on handoff.
- No dependency pin, opam switch or installed environment changed. Installation
  happened only into disposable temporary prefixes, which were removed. No
  provisioning, synthesis, physical flow, Docker, Nix, LibreLane, PDK, bootstrap
  or consumer migration ran.

## Completed work

P6.1, P6.2, P6.3, **P6.4a** and **P6.4b** are complete. Parent P6.4 is not; the
one clause still without evidence is named below.

P6.4a moved the authoritative implementation into one installable package and
proved fresh-prefix discovery:

- `scripts/{phase4,report,archive,flow_cli}.py` and `scripts/toolchain.sh` moved
  into `flow/hardcaml_asic_flow/`, with regular package imports replacing the
  `importlib` sibling loads and the provisioner's repo-root derivation. The P6.3
  dispatcher moved intact; no operation logic was copied or reimplemented.
- `flow/dune` installs the library, a `hardcaml-asic-flow` launcher, the private
  modules and the runtime data — the generic provisioner and the **same**
  `toolchain.lock` the repository maintains — from one `hardcaml_asic` artifact.
- The installed command resolves its own modules and data from its prefix, works
  through `PATH` and a symlink, runs from a read-only prefix without writing
  bytecode, and reports a missing installation rather than searching for a
  checkout.
- `--version` reports the package version and states plainly that source
  identity is unstamped and the library/executor match unverified.

Exact files, installed layout, discovery behaviour, commands and results are in
[section 12 of the plan](p6-implementation-plan.md#12-p64a-completion-evidence).

P6.4b closed the two gaps that were left, and nothing else:

- **Routing.** `scripts/flow.sh` is now example build/emission plus path
  selection, one command per invocation, with every operation handed to
  `scripts/flow_cli.py`. Its own step sequencer, summary, newest-run lookup,
  default `--allow-python-mismatch` and expensive no-argument default are gone,
  each replaced by one diagnostic naming what to use instead. `scripts/toolchain.sh`
  now goes through `provision`, so a checkout provisions through the installed
  dispatch and the packaged lock. `bootstrap.sh` keeps its OCaml layer.
- **Installed-operation evidence.** 24 new `test_installed_prefix.py` cases drive
  the installed command through `provision`, `preflight`, `run`, `postcheck`,
  `collect`, `report`, `archive` and the fixed `execute`, with fixture bundles and
  stub external processes: argument and tool-location forwarding, explicit run
  selection against decoys, machine-readable paths on success, recorded failure
  and SIGTERM, no fabricated path before allocation, required bench inputs, no
  physical postcheck for synthesis, collection that is not acceptance, P6.1
  acceptance and P6.2 integrity through the installed command, and no implicit
  archive replacement or expensive default.
- The generic `nixpkgs_pin`/`command_output(env=...)` fix was ported from the
  consumer's copy, with unit cases and one installed case; no consumer lock check
  or design-specific assumption came with it.
- The generic orchestration assertions from `scaf/tinytapeout/scripts/check-flow.sh`
  were migrated into `test_flow_cli.py` as 11 driver cases. The consumer's thin
  forwarding and emitted-source checks stay with it.

The gap inventory these closed, the exact files, the per-operation coverage table,
the commands and the parent assessment are in
[section 13 of the plan](p6-implementation-plan.md#13-p64b-completion-evidence).

## Parent P6.4: what is left

Its evidence line asks for a fresh-prefix install that runs from an unrelated
directory **without source-checkout access**. Everything else in P6.4 now has
evidence. The checks deny the checkout through cwd, `PATH`, `PYTHONPATH` and a
decoy package, and prove where imports resolved from, but they do not make the
source tree unreadable to the process. That filesystem-denial gate is P6.6a's, so
P6.4 stays open rather than being closed on a weaker check. P6.5, P6.6 and M4 are
open; P0–P5, M3 and the S-series are untouched.

## Honest limits of what P6.4a and P6.4b deliver

- **No source-artifact identity.** `--version` reports `stamped: false`,
  `revision: null`, `state: "unknown"`, `inventory_digest: null` and
  `library_artifact_match: null`. The package version is an API label, not proof
  of a revision, a clean tree, or that the linked OCaml library came from the
  same artifact as the command. P6.5a implements the stamp.
- **No identity or waiver semantics.** `--dependency-lock` and `--waiver` parse
  and are then rejected with an explicit P6.5 diagnostic and exit 2. They are
  not silently accepted, and an installed test pins that.
- **No provisioning-policy change.** Pins are untouched. The `provision` tests
  replace `bash` with a stub and cover dispatch plumbing only — which script,
  which lock, which root, which exit status. They claim nothing about P6.5c's
  read-only, offline or exact-version semantics, and no real provisioning ran.
- **Source-denial is not proven**, as above.
- **Standard `--prefix` layout only.** Independent `--libdir` relocation stays
  deferred.
- **Stub processes are fixtures.** `git`, `docker`, `nix-shell` and both Pythons
  are a few lines of shell each in the installed-operation tests. They exercise
  the flow's own logic and say nothing about the real tools, a real PDK or a real
  physical result.

## Decisions and coordination

Settled by P6.4a, and worth not relitigating: private Python modules plus a POSIX
launcher in the same opam artifact, no pip package; `python3 -I -B` for isolation
and bytecode suppression; one maintained `toolchain.lock`, symlinked into the
package and installed by Dune; `conf-python-3` declared with the real >=3.9 bound
checked by the command, since the conf package cannot express a minor version.
A user-authorized commit/candidate publication is still needed later; this work
grants no commit or pin-update authorization.

Shared files needing coordination — reread each immediately before editing:

- `docs/phase_plan.md`, `docs/immediate_future.md`, `docs/README.md`,
  `docs/usage.md`, `docs/flow.md`: phase plan owns parent task IDs. `flow.md`,
  `usage.md`, `bootstrap.md` and `README.md` still document the `scripts/` entry
  points, which remain correct because the adapters remain; P6.4b corrected only
  the statements its own changes made false — the driver's interface, the required
  `STAGE`/`RUN`, the removed mismatch waiver and the no-longer-copied preflight.
  Replacing them with installed commands is still P6.6b, deliberately not done
  early.
- `test/dune`, `dune-project`: P6.4a touched both; P6.4b added
  `(source_tree ../scripts)` to the `test_flow_cli.py` rule, because that suite
  now also drives `scripts/flow.sh`. The Python rules depend on
  `(source_tree ../flow)` and `../toolchain.lock`.
- `scripts/flow.sh`, `scripts/toolchain.sh`, `bootstrap.sh`: P6.4b owns their
  current shape. Anything added to them belongs in the shared command instead
  unless it is example selection or a repository path.
- `flow/hardcaml_asic_flow/data/toolchain.sh`: P6.4b changed only comments and
  two messages, so installed data stops naming a repository script. P6.5c owns its
  behaviour; serialize edits with that unit.
- `lib/bundle.ml`, `lib/target.ml`, `test/check_bundle.py`: untouched by P6.4a and
  P6.4b.
  P6.5a's additive generator identity intersects SRAM work; agree the optional
  provenance field and test ownership with the S owner before editing. No
  resource contract, backend, macro collateral or SRAM model test change is part
  of P6.
- Consumer owner controls `scaf` bootstrap, lock, emitter, wrappers and CI.
  Runtime replacement still waits for the conditions in the implementation plan.
  Preserve working paths until covered.

## Next bounded task: P6.5a

Packaging and installed-operation evidence are done; do not redo either. P6.5a
gives the artifact an identity, which is what P6.5b/P6.5c and the recorded P7
candidate all wait on.

### Self-contained implementation prompt

> In `/home/wayne/devel/jane/hardcaml_asic`, implement **ASIC P6.5a only** — the
> source-artifact identity foundation — from `docs/p6-implementation-plan.md`.
> Read `/home/wayne/devel/jane/AGENTS.md`, the git status and HEAD of this
> repository and of `/home/wayne/devel/jane/scaf`, `docs/p6-status.md`,
> `docs/p6-implementation-plan.md` sections 4, 5, 7 and 13, and the P6 gates in
> `docs/phase_plan.md`. Concurrent SRAM and consumer work is in flight: treat the
> worktree as authoritative, reread shared files immediately before editing, and
> change no `scaf` file.
>
> What exists: one opam artifact installs the OCaml library, the
> `hardcaml-asic-flow` launcher, the private `flow/hardcaml_asic_flow/` modules
> and the runtime data; every operation has installed-command regression
> coverage; `scripts/flow.sh` and `scripts/toolchain.sh` route through the shared
> dispatcher. `--version` deliberately reports `stamped: false`,
> `revision: null`, `state: "unknown"`, `inventory_digest: null` and
> `library_artifact_match: null`. Do not repackage, re-move modules, change the
> install layout, rewrite the driver or redo that evidence.
>
> Scope: (1) a deterministic source stamp produced at build/export time, so one
> generated identity — the same values for the OCaml library and for the Python
> command — carries the full revision, whether the tree was clean, and an
> inventory digest over the files that make up the artifact. It must work in an
> opam source build with no `.git`, and must report an honest unknown rather than
> guessing when there is nothing to stamp. (2) The additive generator-identity
> field in emitted bundles. **Coordinate `lib/bundle.ml`, `lib/target.ml` and
> `test/check_bundle.py` with the S-series owner before editing them**: the
> optional provenance field and test ownership intersect SRAM work, and the phase
> plan makes that agreement a precondition. If agreement is not available, stop
> with the dependency recorded and deliver only the parts that do not touch those
> files. (3) Keep `--version --json` honest: a stamped artifact says so, an
> unstamped development tree still says `unknown`, and nothing infers a revision
> from a version string.
>
> Do not implement P6.5b's dependency-lock or waiver semantics — keep the current
> explicit "not implemented until P6.5" rejection at exit 2 — P6.5c's provisioning
> policy, P6.6's filesystem-denied acceptance, or any P7 consumer migration. No
> SRAM, backend or resource-contract change. Do not commit, push, reset, discard
> changes or move a pin.
>
> Evidence to produce: clean-Git, dirty-tracked, relevant-untracked, unknown-snapshot,
> stamped-Git-free-artifact, tampered-inventory and rebuild-determinism fixtures;
> library and CLI identity equality; manifest coverage. Validate the actual opam
> source-path stamping behaviour, not merely handcrafted JSON. Keep every check
> PDK-free: no provisioning, Docker, Nix, LibreLane, synthesis or physical flow.
> Installing into a newly created disposable temporary prefix is allowed; alter no
> shared opam switch or installed environment, and record a blocker rather than
> installing a missing build dependency.
>
> Verify with the six Python suites (`test_phase4`, `test_flow_cli`, `test_report`,
> `test_archive`, `test_packaging`, `test_installed_prefix`), `dune build`,
> `dune build @install`, `dune runtest`, `bash test/package_consumer_smoke.sh`,
> `opam lint hardcaml_asic.opam`, a documentation link check and
> `git diff --check`. Record exact commands and results, the dirty-snapshot
> caveat, and a self-contained prompt for the next unit in `docs/p6-status.md` and
> `docs/p6-implementation-plan.md`. Mark P6.5a complete only with its evidence;
> P6.4's outstanding source-denial clause, P6.5b/c, P6.6 and M4 stay open. Stop
> after P6.5a.

## P6.3 verification

Exact focused commands:

```sh
python3 test/test_phase4.py       # 13 tests, OK
python3 test/test_flow_cli.py      # 17 tests, OK
python3 test/test_report.py        # 15 tests, OK
python3 test/test_archive.py       # 20 tests, OK
dune build @test/runtest --force
git diff --check
```

All commands exit 0; the suites now load the package modules P6.4a installs
rather than files under `scripts/`, and still pass unchanged. External processes
in runner tests and all dispatcher operations are injected; reporter/archiver
policy and collector fixture handling execute their existing implementations. An
independent review found no remaining P6.3 gate blocker after clean execute JSON,
downstream-failure identity, archive-list integrity, atomic-save and malformed-
record regressions were added. P6.3 closure stands; P6.4a found no regression in
it.

## P6.4b verification

```sh
python3 test/test_phase4.py            # 16 tests, OK  (13 + 3 Nix cases)
python3 test/test_flow_cli.py          # 28 tests, OK  (17 + 11 driver cases)
python3 test/test_report.py            # 15 tests, OK
python3 test/test_archive.py           # 20 tests, OK
python3 test/test_packaging.py         # 17 tests, OK
python3 test/test_installed_prefix.py  # 35 tests, OK  (11 + 24 installed cases)
dune build && dune build @install && dune runtest
dune build @test/runtest --force
bash test/package_consumer_smoke.sh    # external consumer: address=2 storage=32
opam lint hardcaml_asic.opam           # Passed
git diff --check
```

The per-operation coverage table, the driver's routing contract and the removed
spellings are in
[section 13 of the plan](p6-implementation-plan.md#13-p64b-completion-evidence).
The 24 new installed cases run the installed launcher as a subprocess against
fixture bundles and stub external processes; the 11 driver cases replace `python3`
with a recording stub and prove routing, not operation behaviour. No PDK,
LibreLane, Docker, Nix, provisioning, synthesis or physical flow ran.

## P6.4a verification

```sh
python3 test/test_packaging.py         # 17 tests, OK
python3 test/test_installed_prefix.py  # 11 tests, OK
dune build && dune build @install && dune runtest
bash test/package_consumer_smoke.sh    # external consumer: address=2 storage=32
opam lint hardcaml_asic.opam           # Passed
git diff --check
```

The full command list, fresh-prefix isolation and import-origin results, and the
fixture-backed installed `report`/`collect`/`preflight` evidence are in
[section 12 of the plan](p6-implementation-plan.md#12-p64a-completion-evidence).
