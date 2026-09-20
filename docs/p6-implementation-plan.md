# ASIC P6.3–P6.6: bounded implementation plan

Status: P6.3a implementation checkpoint complete; P6.3b in progress, 2026-09-20.
No installed CLI has been implemented.

The [phase plan](phase_plan.md#11-p6--shared-tooling-distribution) owns task IDs,
dependencies and evidence gates. The [migration brief](flow_legacy_migration.md)
owns consolidation requirements. This document refines those requirements into
small implementation units, not a competing architecture. Current worktree
caveats and the next-agent prompt are in [P6 status](p6-status.md).

## 1. Recommendation and boundaries

Install one `hardcaml_asic` Dune/opam artifact containing the OCaml library, an
installed `hardcaml-asic-flow` launcher, private standard-library-only Python
modules, the existing generic shell provisioner and its lock data. **Move and
adapt the current library implementation; do not copy the consumer forks or
maintain a separately released Python distribution.**

Keep the manifest/run/results/archive formats and P6.1/P6.2 policies. Add optional
provenance fields rather than changing historical bytes. Expose the eight
operations in the brief and one fixed `execute` sequence from an already emitted
bundle. Build, emission, design choice and verification semantics remain consumer
owned. Provisioning is explicit, never a dependency of elaboration/emission or
execution. No workflow language, scheduler, general plugin interface, new target,
or SRAM work is required.

P6.3 is not complete on the strength of this document: its required executable
boundary regressions are still missing. Proposed suffixed IDs below refine their
parent goals without changing the phase plan or claiming parent completion.

## 2. Current-state audit

### Operation and call-site inventory

Paths in the consumer column are relative to `scaf/` in this workspace.

| Operation | Current authoritative code and library callers | Consumer callers / ownership consequence |
|---|---|---|
| Install library | `dune-project`, generated `hardcaml_asic.opam`, `lib/dune`; `test/package_consumer_smoke.sh` builds `@install`, installs a temporary prefix and links a RAM-config executable | `scripts/ocaml-deps.sh` path-pins sibling checkout; CI separately checks out fixed ASIC SHA. Replace setup in P7, not here |
| Provision/check | `bootstrap.sh` calls `scripts/ocaml-deps.sh` then `scripts/toolchain.sh`; lock is root `toolchain.lock` | Root `bootstrap.sh`, `bin/protemu.ml` bootstrap/doctor and transitional flow bootstrap step call `tinytapeout/scripts/bootstrap-toolchain.sh`; generic provisioning moves to installed command; OCaml switch setup stays consumer-owned |
| Emit | `examples/tt_bundle_example.ml`, selected by `scripts/flow.sh` | `bin/asic_bundle.ml`, called by adopted-flow `step_emit` and `check-adopted-bundle.py`; keep consumer-owned, including protected-config conflict checks and source enumeration |
| Preflight | `scripts/phase4.py:preflight/main`; example flow `step_preflight`, documented direct invocations | `adopted_phase4.py`, invoked by adopted-flow `step_preflight`; adds checkout-relative `consumer_pins` validation |
| Run | `phase4.py:execute/run_logged`; example flow `step_run`; unique UUID directories, script prints `run.json` path | Adopted flow captures last stdout line, preserves failure exit, copies preflight; root `flow.sh` and `protemu flow/harden` forward to it |
| Postcheck | `phase4.py:postcheck`; example flow passes `test/tt_bundle_tb.v` | Adopted flow always passes `tinytapeout/test/tb.v`; consumer runner hard-codes top `tb`, library hard-codes `tb_observable` |
| Collect | `phase4.py:collect/main`; example flow writes `RUN/results.json`; report computes in memory if absent | Adopted flow `step_collect`; vendored reporter uses vendored collector |
| Report | Current `scripts/report.py`; example wrapper; tests exercise synthesis/full acceptance | Older `adopted_report.py` via adopted flow; rejects valid synthesis evidence because it always applies physical criteria |
| Archive | Current `scripts/archive.py`; direct documented invocation | Older `adopted_archive.py` via adopted flow `step_archive`; automatic destination from run timestamp/ID and implicit `--force`; no standard complete-input archive |
| Restore | `archive.py` verification helpers, `test/test_archive.py`, documented checksum/extract/hash procedure in `docs/flow.md` | Historical manual complete-bundle preservation; do not rewrite it. No restore CLI is needed for P6 |
| Orchestrate | Example-only `scripts/flow.sh` owns sequencing, summaries and implicit latest-run lookup | Root `flow.sh` forwards to `adopted-flow.sh`, which owns sequence, explicit resume, summaries, failures/signals, output/archive naming. Move generic sequencing once; keep build/emit and explicit path selection in thin consumer wrapper |

Relevant source links: [runner](../scripts/phase4.py),
[reporter](../scripts/report.py), [archiver](../scripts/archive.py),
[provisioner](../scripts/toolchain.sh), [example driver](../scripts/flow.sh),
[consumer driver](../../scaf/tinytapeout/scripts/adopted-flow.sh),
[consumer emitter](../../scaf/bin/asic_bundle.ml),
[consumer provisioner](../../scaf/tinytapeout/scripts/bootstrap-toolchain.sh).

### Confirmed dependencies and assumptions

- Package version is `0.1.0`. Only `lib/dune` currently supplies a public library;
  there are no CLI/data install stanzas. Opam metadata is generated from
  `dune-project`; edit the authority, not only the generated file.
- Reporter and archiver dynamically import a sibling `phase4.py` with
  `importlib.util`/`__file__`. Their tests similarly load checkout files.
  `phase4.py` itself uses only Python's standard library and explicit paths.
  The provisioner derives both lock and default storage from its repository root.
  Neither package version nor exact executing package revision is currently
  recorded by library flow scripts.
- Bundle/preflight pins are emitted from `lib/target.ml` and `lib/bundle.ml`.
  `toolchain.lock` is the shell-readable mirror checked by
  `test/check_bundle.py`. Fetch URLs/branch hints exist only in the lock. P6
  should retain this tested authority arrangement rather than create another
  target configuration source.
- Preflight checks schema 1/LibreLane, declared file hashes, external reference
  paths/hashes/Git status, collateral Git HEADs, Python and LibreLane versions,
  and Docker image/server/container Python. It invokes Git, the supplied Python,
  and (unless native) Docker. It is not a PDK-free metadata-only command and may
  start a lightweight version-probe container; it never pulls one.
- Run stages the bundle and support floorplan, invokes `python -m librelane`,
  stores manifest/build/run identities and actual environment. It creates a run
  before checking prerequisites, records failure/interruption, then prints the
  path. SIGTERM handling is installed for `run` but not equivalently for
  `postcheck`. Missing/malformed manifest before allocation has no run path.
  Preflight already reruns inside execution: the wrapper's claim that only it
  can save `preflight.json` is obsolete; save the actual in-run check there.
- Postcheck is the delivered **TT/CMOS5L** implementation: Nix `default.nix`,
  pinned native KLayout probe, separate Python KLayout 0.28.x environment,
  support `precheck/` and `tech/`, PDK IO/UDP/stdcell models, Docker Icarus/vvp,
  `-g2012 -DFUNCTIONAL -DSIM`, and one testbench file. It records and copies the
  testbench and hashes GDS/netlist/testbench. The target-specific paths are
  adapter requirements, not consumer configuration to duplicate in a CLI.
- Generic flow Python requires modern Python APIs (`removeprefix`,
  `Path.is_relative_to`); recommend host Python >=3.9, distinct from the bundle's
  requested **flow** Python `3.11` minor. No pip dependency is needed for offline
  report/archive/collect. Shell provisioner additionally uses Bash, Git, Unix
  utilities, Python venv/pip and network fetching; execution/postcheck add Docker,
  LibreLane and Nix. Bootstrap does not install host prerequisites.
- Library example flow hard-codes `/home/wayne/devel/jane/p4-$KIND`, defaults to
  full expensive execution on no arguments, defaults to Python mismatch waiver,
  uses implicit newest-run selection, and defaults an example bench. It is not
  an appropriate installed entry point.
- Consumer root no-argument flow starts `--full`, while its nested driver prints
  help. Nested driver already requires `PROTEMU_RUN` for separate invocations.
  It defaults Python mismatch on, defaults full stage, always selects observable
  postcheck bench, and includes postcheck even when the stage variable says
  synthesis. Its archive destination policy/implicit force is consumer wrapper
  behavior, not a generic acceptance rule.
- Library provisioner falls back to system Python when the requested minor is
  absent; existing environments need exact-minor checks too. It accepts Podman
  while runner/postcheck explicitly call Docker. Nix readiness can be a warning,
  not proof full postchecks can run. Consumer provisioner rejects Podman for
  adopted execution, accepts Python >=3.11 rather than the exact requested minor,
  and has additional repository-specific legacy staging/config-generation paths.
- Consumer `asic-dependencies.lock` contains package revision plus copied EDA
  pins; `toolchain.lock` duplicates those plus legacy template/action pins,
  floorplan, tiles and runner. `consumer_pins()` compares the bundle's embedded
  dependency lock against the *current* scaf checkout and both lock files. It
  does not prove which OCaml library actually emitted the bundle.
- Emitter records both locks in `input_paths`, consumer sources and its own
  declaration. It supports observable/memory and conflict checks. Removing a
  lock in P7 requires updating this source inventory; historical bundles retain
  their old copies. Current observable and memory benches each use top `tb`;
  targeted search found no include/readmem/plusarg input requirement in either.
- CI `verification.yml` duplicates ASIC SHA in a sibling checkout, installs host
  HDL tools, then runs `@verification` = recursive `runtest` plus `rtl`.
  `tinytapeout/test/dune` still checks committed legacy wrapper RTL as well as
  newer unrelated core RTL tests. Do not delete the latter during P7.
  Neither `check-flow.sh` nor `check-adopted-bundle.py` is wired into these Dune/CI
  paths. The adopted checker has `--metadata-only` and separate Docker-based
  implementation/simulation traces, lint and generic synthesis.

### Actual consumer Python deviations: move, retain, retire

Direct diffs of all three copies were inspected, rather than trusting their
"only import name differs" comments.

| Deviation | Disposition |
|---|---|
| `consumer_pins()` reads current/embedded dependency locks and checkout toolchain lock | Replace with explicit generic dependency expectation and recorded generator/executor identities. Consumer supplies lock path; no implicit scaf layout in library |
| `runner_sha256` in preflight/run/postcheck | Retain historical field when reading; replace new production with package/source identity covering all modules/data and linked library, not one script hash |
| `nixpkgs_pin()` derives `NIX_PATH` from the pinned precheck `default.nix`; `command_output` accepts env | Port this small generic fix with its own tests. It removes channel-dependent wrapper-shell lookup; it is not a consumer design feature |
| Hard-coded `tb` versus `tb_observable` | Explicit required public `--testbench-top`; consumer chooses `tb`, repository example chooses `tb_observable` |
| Reporter lacks P6.1 finite/numeric/stage/required-evidence checks | Retire consumer implementation after installed coverage; preserve newer library policy |
| Archiver lacks P6.2 bundle validation/deterministic tarball/transactional replacement | Retire consumer implementation after installed restoration and replacement coverage; preserve newer library policy |
| Wrapper summaries, explicit resumed run, failure/signal behavior | Implement once in fixed shared `execute`; individual commands stay usable. Transfer generic assertions, not the shell implementation wholesale |
| Emitter/design selection, testbench semantics, build/switch commands, chosen output root | Stay consumer-owned |
| Legacy wrapper/config/info/stage/precheck/harden paths and copied provisioning | Retire only in P7 after coverage mapping and replacement checks; historical evidence stays |

### Confirmed gaps versus questions still requiring evidence

Confirmed: no installation, checkout imports/data, hard-coded bench tops, duplicate
pins, automatic mismatch waiver, asymmetric native support, no installed source
identity, and no boundary/preflight/postcheck tests in the four-test collector
suite. Existing 15 reporter and 19 archive tests are valuable foundations, not
installed-command coverage. `report --json` currently bypasses acceptance and
returns zero; `collect` returns zero for a successfully produced partial record.

Needs implementation-time verification: Dune launcher/install behavior under
custom prefixes and symlinks; Git-pin versus exported-artifact stamping in opam's
build tree; sandbox availability; provisioner read-only behavior with missing
Nix/venvs; and all signal/output contracts. No real provisioning or EDA execution
was performed for this audit. The plan does not infer an installed success from
source inspection.

## 3. P6.3 proposed command contract

### Common rules

- No arguments and `--help`: help, exit 0, no directories created, no tools
  probed. Invalid arguments: exit 2 before expensive work. Paths resolve against
  the caller's cwd, never a repository. `RUN` is always explicit; no `--runs`
  newest lookup on report/collect/postcheck/archive.
- `run` and `execute` require both `--runs DIR` and `--stage synthesis|full`;
  no full-stage default. Neither provisions. `postcheck` is also explicitly
  expensive. Individual resumed operations do not retry a flow stage; a retry
  of `run` is a new attempt. No LibreLane internal-resume API is added.
- Tool locations: explicit `--support-tools`, `--pdk-root`, `--python`,
  `--precheck-python` as appropriate. Optional `--toolchain DIR` fills absent
  locations from `DIR/{tt,pdk,.venv/bin/python,.venv-precheck/bin/python}`.
  Precedence: explicit location > `--toolchain` > `TOOLCHAIN` root. With no root,
  all needed locations must be supplied. Do not implicitly source shell files.
  No `PROTEMU_*`, `KIND`, `STAGE`, `RUN`, or Python-mismatch environment defaults.
  PATH selects the host Python/system executables; HOME/Nix/Docker environment
  still affect those tools and relevant actual versions are recorded.
- Execution identity inputs: optional `--dependency-lock FILE` with the existing
  `asic_repository`/full `asic_revision` keys. Ignore legacy EDA fields as
  authority (record the file digest); do not require the lock to be inside a
  checkout. Bundle and collateral pins remain authoritative. P7 wrappers must
  pass this option. New bundles also carry generator identity, described below.
- Named exceptions: repeatable `--waiver CODE=REASON`, nonempty reason, only
  recognized codes (`python-version`, `tool-source`, `dependency-revision`,
  `generator-tool-mismatch`, `legacy-generator-identity`). These waive only the
  named provenance/version condition and record expected/actual/reason. Hash,
  schema, stage and acceptance failures cannot be waived. No bare default
  `--allow-python-mismatch` in the installed CLI.
- Exit 0 means success **for that operation**, 1 means a completed evaluation
  failed its policy or a started operation failed, 2 means usage/unreadable or
  structurally invalid input/prerequisite error before useful evaluation.
  Detailed errors stay in records/stderr. Provisioning retains its differentiated
  codes below. SIGINT/SIGTERM yield 130/143 after child cleanup and record
  finalization; do not flatten signals into success or ordinary failure.

### Operation matrix

`T` below means applicable explicit tool locations/root resolution above; `I`
means dependency-lock and named waivers. No option reads a hidden consumer lock.

| Command | Arguments / defaults / environment | Outputs and side effects | Exit and scope |
|---|---|---|---|
| `--version [--json]` | No target/toolchain required | Package/tool version; JSON also source revision, digest, dirty/unknown state, identity schema, supported record schemas and installed data path | 0 even for visibly unknown development identity; no Git/EDA runtime probe |
| `provision` | `--toolchain DIR` > `TOOLCHAIN` > caller's `.toolchain`; `--check`, `--offline`, `--no-container`; optional named Python waiver. Installed lock only; no arbitrary alternate EDA lock | Explicit fetch/install of managed collateral/venvs/image; generated env file and provisioning record identify defaults and deviations. `--check` writes nothing (including no env/record/cache creation) | Existing 0 match, 2 prerequisite/check gap, 3 bad shipped lock, 4 fetch/install failure, 5 mismatch, 7 tool failure. Waived mismatch visibly qualified. `--no-container` prepares native-synthesis subset, not full-flow readiness |
| `preflight BUNDLE` | T: support, PDK, flow Python; I; `--native`; optional `--output FILE` | JSON stdout, same JSON optionally saved. Validates immutable inputs and actual environment; probes only, no download. Missing/changed evidence enumerated | 0 ready, 1 not ready, 2 unusable input. Waivers are in JSON. Native only means skip Docker checks, not certification of every native EDA binary |
| `run BUNDLE --runs DIR --stage STAGE` | Same T/I; `--native` allowed for synthesis only | Allocates UUID run; manifest staging, `run.json`, **actual in-run** `preflight.json`, logs and outputs. Stdout is one JSON object `{run_id, run_dir, run_record, status}` with absolute paths, on success/failure/interruption after allocation. Diagnostics on stderr | 0 requested process completed, not acceptance; 1 recorded failed attempt; 2 failure before allocation; 130/143 interrupted. Before allocation there is no fabricated path. `--native --stage full` fails before allocation |
| `postcheck RUN --testbench FILE --testbench-top MODULE` | T: support, PDK, precheck Python; I for executing tool/dependency checks. Both bench arguments required; no default design; validate adapter and recorded requested collateral | Unique `checks/ID`, copied `testbench.v`, preserved hashes/top, precheck/gate simulation command logs and JSON; stdout JSON check identity/path | 0 both checks passed, 1 started check failed, 2 not a completed full run or missing inputs; 130/143 interrupt. Delivered backend requires Docker+Nix; unsupported native-full promise is not made |
| `collect RUN` | `--output FILE`, default `RUN/results.json`; `--stdout` is read-only alternative, mutually exclusive with output | Existing results schema including unavailable reasons and partial errors. Atomic output file write; stdout JSON in read-only mode | 0 collection produced a valid result structure, even for failed/partial run; 2 invalid input/collection exception. Never claims synthesis/full acceptance |
| `report RUN` | `--json` optional; no tools/env required | Existing human report, or exact collected/stored results JSON with acceptance diagnostics on stderr. Computes absent results in memory; writes nothing | 0 P6.1 scope acceptance; 1 missing/failed/contradictory/malformed required evidence; 2 unreadable/unparseable record. JSON mode uses **same acceptance**, not a bypass |
| `archive RUN --output DIR` | `--list` instead of output (read-only); `--force` explicit, never default | Existing complete input and report tarballs, digest, original records, archive manifest with archiving-tool identity; transactional publication, user files preserved | 0 integrity-preserving publication/list; 2 invalid input, incomplete run or publication failure. Archive is preservation, not a substitute for `report`; keep current completed-run requirement |
| `execute BUNDLE --runs DIR --stage STAGE` | T/I, same native restriction; full requires bench/top/precheck Python up front. Optional `--archive DIR` and explicit `--force` only with archive | Fixed run (includes preflight) → postcheck iff full → collect → report → optional archive. Same underlying functions, no subprocess parsing of own CLI. JSON final outcome includes new run path, per-step statuses and optional archive path; human durations/artifact summary stderr, including failure | 0 only successful sequence/acceptance; first failure or signal retained. Best-effort collect after a recorded failed run/check, but no report-success or archive promotion after upstream failure. No build, emit, provision, auto-latest selection, arbitrary step list or auto retry |

For `execute --stage synthesis`, postcheck inputs are rejected as irrelevant rather
than suggesting physical checks ran. A full invocation validates all argument
requirements before starting run. `--archive` is an exact caller-chosen directory;
no hidden timestamp policy or `--force`. If consumer chooses an experiment output
root, its archive can simply be a subdirectory of that root. Individual commands
cover diagnosis and recovery without a general orchestration engine.

The retained repository adapters must also print help on no arguments, require
explicit resumed `RUN`, and remove automatic mismatch waivers. Incompatible old
flags such as implicit-newest `--runs` get a short replacement diagnostic for one
documented migration window; do not silently preserve old expensive defaults.

### Brief clarifications / proposed amendments

These are specific inspection-driven refinements to section 3/4 of the migration
brief, to acknowledge in P6.3 evidence, not changes to its architecture:

1. `--testbench FILE` alone is insufficient: library and consumer require different
   simulator tops. Require `--testbench-top MODULE`. Current benches need no
   additional files; do not invent a verification plugin or arbitrary command.
   If a concrete future bench needs includes/readmem data, coordinate a separately
   hashed/copied verification-input extension before supporting it.
2. Full postcheck is Docker-specific despite `run --native`. Support native
   synthesis only in the new public contract; reject native full early instead
   of advertising an end-to-end native path. Historical records remain readable.
   `provision --no-container` describes this limited preparation explicitly.
3. Requested Python is a **major.minor** value today, not an exact patch pin.
   Require that requested minor by default for host flow and container probes;
   record patch versions. No new patch pin and no default waiver.
4. New public `report --json` must not bypass acceptance. `collect --stdout`
   provides raw inspection without an acceptance promise. This deliberately
   tightens the old script behavior, while preserving stored JSON shape.
5. Provision readiness is not physical success; full prerequisites need explicit
   checks/gaps. Use Docker for the delivered container route; remove misleading
   Podman fallback unless a separately tested Docker-compatible invocation is
   later agreed. No container abstraction is needed for P6.

## 4. P6.4 installation and module/data layout

Recommended source layout (new paths are proposals):

```text
flow/
  dune                         # bin + lib/data install stanzas, one package
  hardcaml-asic-flow            # small POSIX launcher: python3 -I
  hardcaml_asic_flow/
    __init__.py
    __main__.py
    cli.py                     # parsing/output/exit mapping
    phase4.py                  # moved authoritative implementation
    report.py                  # moved current P6.1 implementation
    archive.py                 # moved current P6.2 implementation
    execute.py                 # fixed orchestration only
    identity.py                # installed metadata and explicit expectations
    data/
      toolchain.sh             # moved generic shell implementation
      toolchain.lock           # Dune-installed root lock, not a maintained copy
      source-identity.json     # build/export-generated immutable identity
scripts/
  phase4.py, report.py, archive.py, toolchain.sh  # thin development adapters
  flow.sh                      # example build/emit + shared CLI invocation
```

Install the launcher to `$PREFIX/bin/hardcaml-asic-flow`; private modules/data
to `$PREFIX/lib/hardcaml_asic/flow/hardcaml_asic_flow/` through explicit Dune
`install` stanzas associated with `hardcaml_asic`. Runtime data is found relative
to that package, never cwd, source tree, `.git`, or a sibling checkout. No package
installation step invokes pip, provisions EDA, or executes tests with hardware
tools. Upstream templates/precheck/default.nix remain external pinned collateral;
there is no extra local template to vendor.

The launcher resolves its own installed location, prepends only the private
module root, and calls `hardcaml_asic_flow.cli.main`. Support standard Dune/opam
prefix layout, including invocation through a PATH symlink; verify actual Dune
symlink/copy behavior rather than assuming the build-tree layout matches install.
Use Python isolated mode (`-I`) or equivalent safe launcher startup and disable
bytecode writes so read-only prefix operations do not create `__pycache__`.
Host interpreter is `/usr/bin/env python3` with an explicit >=3.9 check; a
lightweight POSIX shell launcher executing `python3 -I` is acceptable if needed
to make isolation portable. It adds no package-discovery dependency on OCaml at
runtime. **Recommendation:** use that POSIX launcher plus Python entry module;
do not introduce an OCaml runtime wrapper or findlib lookup for offline reports.

Dune installation supports custom libdir locations, but the first supported CLI
contract is the standard `--prefix` layout. Diagnose missing private modules with
the expected install location and state this restriction in installation docs;
do not search a source checkout as fallback. Custom independent `--libdir`
relocation is deferred unless the P6.4a opam/prefix prototype proves it necessary.
Source-absolute paths are unacceptable.

Repository adapters load the same source package (one path addition only) and
translate legacy arguments where explicitly retained. Dune tests depend on that
package source tree. `bootstrap.sh` still handles the OCaml development layer,
then delegates flow provisioning to the shared implementation. The root lock can
stay where `check_bundle.py` reads it; installation renames/places that **same
file**, not a second handwritten lock. The shell implementation accepts internal
explicit `--lock-file`/root inputs supplied by the Python entry, rather than
computing repo root. Public users cannot silently override target pins through
that internal plumbing.

Declare host Python through opam's `conf-python-3` prerequisite and document/check
the actual >=3.9 bound (the conf package alone does not prove a minor version).
Document POSIX shell, Bash for provision, Git and basic Unix utilities. Docker,
Nix, venv/pip and LibreLane are operation-specific external requirements, not
dependencies downloaded by `opam install hardcaml_asic`. Keep pure operations
usable without them. Test a read-only installed prefix.

An isolated prefix remains:

```sh
dune build @install
dune install --prefix "$PREFIX" hardcaml_asic
PATH="$PREFIX/bin:$PATH" hardcaml-asic-flow --version --json
OCAMLPATH="$PREFIX/lib${OCAMLPATH:+:$OCAMLPATH}" dune build --root "$CONSUMER"
```

No pip/wheel alternative is needed: a second package/release would reintroduce
the synchronization problem. No embedding all Python as OCaml strings: that
would obstruct direct testing of the existing code. Installation from one Dune
artifact also makes library and CLI upgrades atomic at the package-manager level.

## 5. P6.5 identity and provisioning authority

### Authorities

| Fact | Authority and policy |
|---|---|
| Pre-bundle provisioning defaults | Installed `toolchain.lock`, originating in this package and checked against emitted library pins by existing bundle tests; never consumer copied EDA pins |
| Bundle-requested tools/collateral | Original manifest `requested_tools` and target external references, even for a supported historical pin; preflight does not substitute current installed defaults |
| Target/config/RTL | Typed declaration and emitted immutable bundle; CLI adds no target-selection config |
| Package version | Dune project version, identical for library/CLI; useful API label, **not proof of exact source revision** |
| Source identity | Export/build-generated metadata embedded in both OCaml library and CLI from the same artifact |
| Consumer dependency expectation | Explicit consumer lock's full package revision/repository; P7 setup installs it, CLI verifies expectation rather than installing it |
| Actual environment | Measured revisions/hashes/version probes plus explicit recorded waivers, not merely provisioning success |

### Artifact identity without runtime Git

Implement a deterministic source-manifest stamping step at **source artifact
creation/build time**. It records identity schema, package version, full Git
revision when known, clean/dirty/unknown state, and SHA-256 of an enumerated
package source inventory. The inventory covers OCaml, Python, shell, lock and
build metadata; excludes `.git`, build output and the stamp itself to avoid
self-reference. Relevant untracked source must be included for a development
snapshot. Do not use only `git diff` (it misses untracked files) or only one
runner hash. Record artifact tarball digest separately when exporting; a tarball
cannot contain its own digest.

For a clean Git source pin, generate metadata while the source checkout is
available. For a tar/source artifact without `.git`, include the generated
metadata and inventory in the artifact, validate its content digest when building,
and use it unchanged. An export helper can use Git archive metadata to identify
the revision, but must not rely on opam preserving `.git` or on version
substitution happening for every build mode. Make the opam Git-pin/export path
part of P6.5 tests. An unmarked source snapshot remains buildable with explicit
`revision: null`, `state: unknown` and a computed content digest; never invent
a clean revision from package version or a supplied environment string.

This is reproducibility provenance, not a cryptographic attestation of publisher
trust. Exact revision claims require a recorded source artifact/export mapping,
not merely a user-entered SHA. Stamp fields and source-manifest hashing must be
specified and tested before treating an installed candidate as clean evidence.

Generate one OCaml `Tool_identity` value/module and the installed JSON from the
same validated stamp. Add optional `generator_identity` to **new** bundle
manifests through `Bundle.render`, using the linked library's embedded identity.
Consumers cannot accidentally obtain this value by querying a different CLI on
PATH. The new field is naturally included in new manifest/build identity; no
old manifest is modified. Coordinate this small shared bundle extension with
the SRAM owner before editing it. A sidecar alone would fail to bind generator
identity into the immutable bundle; this additive field is justified.

### Minimal record extensions and comparisons

- New preflight: `flow_tool_identity`, observed `generator_identity`, optional
  `dependency_expectation` (requested SHA/repository + supplied lock digest),
  identity comparison results, and structured waiver details. Keep existing
  `waivers` string list for old consumers and add `waiver_details` rather than
  changing its element type.
- New run: executing `flow_tool_identity`, actual environment/preflight and
  explicit expectation/waiver results. Save that same preflight under the run.
- New postcheck: executing identity, explicit testbench top, dependency checks
  and waivers; retain existing `inputs.testbench_sha256` and copied filename.
- New results: collector identity can be additive, distinct from executor;
  never replace run identity with the collector's. Existing scope fields stay.
- New archive manifest: `archiver_identity`; original run/preflight/postcheck
  records remain byte-preserved with their original executor/generator identities.
  An archive created by a newer tool must not claim it originally ran the design.

Keep schema 1 readers tolerant of these optional fields; reject unsupported
schema versions, do not guess. Pin explicit fixture tests for old schema-1
records without identity, consumer records with `runner_sha256`/`consumer_pins`,
and new extended records. If inspection reveals a strict reader, add compatibility
there before emitting the field rather than silently bumping all formats.

Normal new execution requires clean known tool/generator identity, equality of
their artifact identity, and agreement with an explicit dependency lock when
supplied. With no consumer lock, generator/tool agreement is still checked and
expectation is recorded as absent. An explicit development path override belongs
in P7 bootstrap: stamp HEAD + dirty state + content digest, print lock mismatch,
then pass expectation to CLI. A named waiver is required for evidence-producing
use of dirty/unknown/wrong revisions; unknown does not mean clean. Supplying a
path never silently substitutes for the consumer's recorded dependency.

Historical analysis is distinct from new execution. `collect`, `report` and
`archive` must read supported old records with absent identity and old pins
without requiring they equal the currently installed version. Report scope and
archive hash guarantees still apply. New preflight/run of an old bundle with
missing generator identity needs an explicit `legacy-generator-identity` waiver;
it still checks that bundle's requested collateral exactly. Postchecking an old
run records the new tool and explicit compatibility waiver without rewriting the
run. Reports-only historical archives remain non-restorable; do not synthesize
missing inputs or rewrite history to satisfy P6.2.

Provisioning ships defaults and exact-minor checks; no implicit system-Python
fallback. A Python compatibility waiver must be explicit both when provisioning
such an environment and when preflighting it; a stored provisioning waiver is
not automatic authorization for future runs. `--check` reads/probes without
fetching, installing, sourcing untrusted shell config, writing an environment
file or refreshing caches. Full-mode checks surface missing Nix/precheck tools as
gaps. Offline convergence must not network-fetch; check and offline are not
synonyms. Preserve managed-versus-external path safety while extracting shell
logic. No pin values change in P6.

## 6. File-level change map

| Files | Planned bounded change |
|---|---|
| `scripts/phase4.py`, `test/test_phase4.py` | Explicit bench top, structured internal outcome, preflight persistence, signals, generic Nix environment fix, boundary fixtures; then move authoritative implementation |
| `scripts/report.py`, `test/test_report.py` | Preserve P6.1; expose acceptance independently of output formatting; public JSON verdict and explicit-run cases |
| `scripts/archive.py`, `test/test_archive.py` | Preserve P6.2; regular package imports, additive archiver identity and fixture reuse; no redesign of archive publication |
| New `flow/` package and Dune stanzas | Single CLI parser, fixed execute composition, installed modules/data/launcher |
| `scripts/toolchain.sh`, `bootstrap.sh`, `scripts/flow.sh` | Move generic provisioning implementation, parameterize installed data/root, thin repository adapters, remove implicit expensive/newest/waiver behavior |
| `toolchain.lock`, `test/check_bundle.py` | Install same lock; preserve pin-equality assertion and extend to installed defaults; no pin update |
| `dune-project`, generated `hardcaml_asic.opam` | Python/runtime metadata and install description; generation remains Dune-owned |
| New stamp/export helper and generated identity data/module, `lib/dune`, `lib/bundle.ml` | Shared source-artifact identity and additive generator field, coordinated before edits |
| `test/dune`, new `test/test_flow_cli.py`, small reusable fixture helper | Canonical fast CLI/identity/provision/read-only tests; reuse existing policy fixtures |
| `test/package_consumer_smoke.sh`, small standalone consumer fixture | Fresh-prefix bundle emission, isolated CLI and restore tests; separate explicit install-smoke alias to avoid recursive `@install` during ordinary runtest |
| `docs/consumer-installation.md`, `docs/flow.md`, `docs/usage.md`, bootstrap guide | Update actual installed commands after they work; do not prematurely replace current operating instructions |
| `docs/p6-implementation-plan.md`, `docs/p6-status.md`, phase plan navigation/status | Exact evidence and next bounded prompt; phase plan edits narrow and reread first |
| `scaf` runtime files | No edits during P6. Consumer owner performs P7 changes after handoff |

## 7. Ordered bounded implementation units

Each unit is one fresh-context task with its own evidence note; stop at its gate.
Parent completion still requires the full phase-plan acceptance, not just a suffix.

| Unit | Work / dependencies | Tests and completion evidence |
|---|---|---|
| **P6.3a — explicit operation boundaries** (complete) | Existing runner only: bench-top argument, internal run outcome (keep legacy script stdout adapter), save actual run preflight, run/postcheck signal finalization. No installed dispatcher yet | `python3 test/test_phase4.py`: 12 tests pass. Mocked-process cases cover non-example top forwarding, missing inputs before allocation/check creation, recorded failure, SIGINT/SIGTERM 130/143, child-group terminate/wait, exact preflight persistence, absolute structured run identity, and the one-line development-adapter path |
| **P6.3b — contract regression specification** | After 3a, executable table-driven boundary cases/harness for public parser and fixed sequence, using injected operation functions; settle amendments above. A minimal source dispatcher seam is sufficient, not full installation | Cover every command's argument forwarding and success/failure exit mapping, including provision/check and archive/list. Cases: no-arg help no effects, required stage/run/bench/top, no newest even with decoy runs, stdout JSON path on recorded failure, raw collect vs verdict report JSON, synthesis omits postcheck, full cannot omit bench, fail/interrupt stops downstream promotion, native-full rejection. Record passing cases and inventory/matrix; only now consider parent P6.3 complete |
| **P6.4a — one source package and prefix install** | After 3b: move modules/provisioner, regular imports, launcher and Dune assets; resolve standard/custom installation lookup prototype, metadata generation. Retained script adapters import same implementation | Existing suites via new imports; fresh disposable prefix `--help/--version` from unrelated cwd, read-only prefix and PATH symlink, all module/data imports originate in prefix. No pip or EDA invoked. This is packaging evidence, not P6.6 closure |
| **P6.4b — installed commands and fixed execute** | After 4a: complete dispatcher, shared orchestration, operation-specific exits, generic Nix fix and repository adapters. Keep identity pluggable for 5b | `test_flow_cli.py` subprocess cases using fixtures/stubs, migrated generic `check-flow.sh` assertions, report/archive policy suites through CLI; failure/interrupt outcome and preflight persistence, explicit archive paths/force, no accidental expensive default. Parent 4 remains open until every operation is installed and tested |
| **P6.5a — artifact identity foundation** | After layout agreed in 4a; implement deterministic source stamp/export, same generated OCaml/JSON identity, no-.git builds and additive generator field. Coordinate `lib/bundle.ml` first | Clean Git, dirty tracked, relevant untracked, unknown snapshot, stamped Git-free artifact, tampered inventory, rebuild determinism, library/CLI identity equality and manifest coverage fixtures. Validate actual opam source path stamping behavior, not merely handcrafted JSON |
| **P6.5b — explicit dependency/waiver records** | After 5a and command seam: comparisons, CLI expectation options, additive record fields, historical reading rules | Matching/wrong/dirty/unknown/waived fixtures; wrong generator vs CLI; historical report/archive without current lock; old bundle reexecution waiver; record persistence through archive. No current scaf checkout lookup; Python mismatch fails by default |
| **P6.5c — provisioning/data authority** | After 4a; parameterized shared shell, strict Python minor, Docker/native scope, read-only/check/offline semantics and generic prerequisite tests. Can overlap 5a in disjoint files | Stub executable/process fixtures assert no network/write under `--check`, absent and mismatched envs fail correctly, no default fallback, installed lock path used, malformed lock rejected, no opam activity; lock-vs-emitted bundle regression retained. Full provisioning real tools not part of this PDK-free gate |
| **P6.6a — independent installation acceptance** | After 4b, 5a/b/c: extend existing package smoke and fixtures as section 8 | Fresh prefix, unrelated emitter, source access denied, installed version/data path, positive/negative preflight/report/archive/restore; exact command log and source artifact identity. No Docker/PDK/EDA |
| **P6.6b — documentation and recorded candidate** | After 6a: installation/usage/bootstrap/flow docs, normal library/script checks, final source identity/evidence and P7 handoff | `dune build`, `dune runtest`, explicit package smoke, `opam lint`, doc links and `git diff --check`. Record user-authorized committed candidate revision/artifact plus passing gate; a dirty prefix is development evidence only. Do not commit without authorization |

Safe overlap: consumer inventory/coverage work throughout; 5c versus 5a after
layout agrees; 4b CLI/composition versus 5a source stamping after interfaces agree.
Serialize edits to `phase4.py`, shared tests/Dune, generator identity and shared
docs. P7.1/P7.2 runtime migration may overlap 6a only once 3 is agreed and working
4/5 have a recorded candidate revision. No request to spawn agents is implied by
this dependency graph.

## 8. P6.6 PDK-free fresh-prefix acceptance

Extend [package smoke](../test/package_consumer_smoke.sh), not another install
harness. Extract reusable synthetic fixture builders from
[collector tests](../test/test_phase4.py), [report tests](../test/test_report.py)
and [archive tests](../test/test_archive.py); do not fork the acceptance policy in
tests. Keep [bundle tests](../test/check_bundle.py) for determinism, provenance
and lock equality. Generic consumer orchestration assertions originate in
[check-flow.sh](../../scaf/tinytapeout/scripts/check-flow.sh); P7 retains tests of
its thin argument forwarding and its design-specific emitted-source checks.

Acceptance procedure:

1. Capture exact source revision/state/inventory digest and commands. Use a
   disposable source artifact/build tree, not a sibling path pin or mutation of
   the installed opam switch. Build/install both library and CLI to a fresh
   temporary prefix using the available OCaml dependency switch.
2. Build an unrelated minimal consumer using only `(libraries ... hardcaml_asic)`
   and prefix `OCAMLPATH`. Extend the current RAM-config test with a tiny TT
   declaration, explicit Flops policy, source list and emitter. Give the fixture
   a real temporary Git source root because `Bundle.render` requires committed
   source provenance; any fixture commit is confined to that disposable test
   repository, never the workspace. Confirm dependency resolution points at the
   prefix and linked generator identity equals installed CLI identity. Emit a
   bundle with no EDA/PDK/network access.
3. Stage test fixture data/tools outside both repositories. Remove the disposable
   source/build tree after installation and consumer build. For installed-command
   tests, use a Linux filesystem sandbox (e.g. Bubblewrap, a **test-only**
   prerequisite) exposing OS runtime, prefix and scratch while making both
   workspace checkouts and original build/source paths unavailable. Probe denial
   explicitly. Do not rename/chmod the live concurrent checkouts. Merely changing
   cwd or unsetting PYTHONPATH is insufficient. If sandbox support is unavailable,
   report incomplete gate rather than silently counting a weaker check as pass.
4. Invoke installed no-arg help/version from unrelated cwd with Python environment
   contamination removed, prefix read-only, and no checkout on PATH/PYTHONPATH.
   Verify version/identity/data path; test provision `--check --no-container`
   against an empty scratch root and stub host probes. It must fail read-only,
   without creating that root or starting a real provisioner download.
5. Preflight fixture: use synthetic manifest/collateral/expected versions and
   deterministic fake Git/flow-Python executables on fixture PATH, pass explicit
   locations and `--native`. These fixtures exercise the installed preflight
   implementation; no special public `--skip-validation` flag. The real emitted
   bundle's bytes/hash inventory are separately checked, and a fixture may model
   its requested refs/pins with synthetic contents where pinned production hashes
   cannot be fabricated. Label this environment evidence **synthetic**, never a
   real PDK readiness claim. Positive case ready; changed file, bad external ref,
   wrong collateral/version/schema/identity and unnamed mismatch must fail.
6. Fixture-only run/postcheck dispatch tests use stub processes, never LibreLane,
   Docker or Nix. Exercise UUID/path/failure/signal behavior and explicit bench
   top. Keep this bounded; P6.6 does not need a physical result. Existing result
   fixture files drive installed `collect` and `report`: valid synthesis passes
   with physical checks unevaluated; full complete fixture passes; partial full,
   contradictory stages, missing metrics/checks, NaN/sentinel values fail.
7. Installed archive packages a completed synthetic run with complete emitted
   input bundle, final-artifact/check fixtures and preserved testbench. Verify
   manifest/run/build linkage, digest, exact member set, deterministic input
   bytes and preservation of README on explicit force. Tampered RTL/source copy,
   manifest, testbench, GDS/netlist, duplicate/traversal/symlink paths and failed
   publication must still fail/preserve previous archive, using existing suite
   coverage plus representative installed negative cases.
8. Copy only evidence to a second scratch area. Delete fixture original bundle,
   source and run; verify tar digest, restore manifest-declared regular files,
   check each hash and run identity without original inputs. Use existing
   restoration helpers/procedure, not a new public restore feature. Do not claim
   this recreates external PDK/tools. Assert historical reports-only archives
   cannot provide this restoration guarantee.
9. Save exact package/artifact identity, installed command/version output,
   sandbox access-denial checks, fixture test counts/statuses and ordinary
   library/script test results. No bootstrap, real Docker, PDK, synthesis or
   physical flow is necessary. Then update operating documentation.

## 9. Risks, unresolved checks and P7 handoff

### Bounded risks

- **Identity bootstrap:** no-.git opam/source builds must get honest metadata.
  The stamp/export prototype and tamper/unknown tests are an evidence gate, not
  a reason to conflate version and revision. Candidate publication waits for it.
- **Packaging relocation:** standard prefix/symlink/custom-libdir discovery must
  be tested before freezing launcher code. Prefer explicit standard-prefix
  support to an untested universal relocation claim.
- **Policy drift on refactor:** current uncommitted P6.1/P6.2 are the base. Keep
  their tests intact and distinguish collect/archive success from report success.
- **Historical compatibility:** no lock from a current checkout may invalidate
  reading old legitimate records. New execution provenance checks must not leak
  into offline historical reporting.
- **Read-only provisioning:** current shell warnings/fallbacks do not establish
  the proposed exact/check semantics. Stub tests must prove them before claiming
  provisioning ready; network/PDK testing is outside this plan's fast gate.
- **Verification scope:** one bench/top suffices for inspected observable/memory
  consumers. Additional bench data, native full flow, another target or changed
  SRAM collateral require explicit coordination, not speculative options here.
- **Source isolation:** sandbox support is a test prerequisite; an unavailable
  sandbox blocks independent-install evidence, not ordinary offline use.

No blocking product-choice question needs user input now. Acknowledge the explicit
brief refinements during P6.3; technical details above have bounded prototype
gates. The user must authorize eventual commit/candidate recording and any future
consumer pin changes separately. This planning task authorizes neither.

### Exact consumer readiness conditions

1. **Safe now:** consumer command/import/bootstrap inventory, coverage mapping,
   installed-CLI requirements and design/testbench enumeration. Keep working
   paths. No speculative CLI migration or deleting copies before replacement
   coverage exists.
2. **Design migration after P6.3:** operation matrix/amendments agreed and boundary
   regressions recorded. P7 can plan concrete forwarding/config removal.
3. **Runtime migration after P6.4/P6.5:** working one-artifact library/CLI install,
   runtime assets, version/source identity, explicit locks/waivers/provisioning,
   plus a **recorded candidate revision**. Hand off exact CLI contract, artifact
   locator/digest, candidate SHA, installation commands and test results. This
   may overlap P6.6, but is not final acceptance.
4. **Final P7 acceptance:** P6.6 and entire P6 exit gate passed with recorded
   source artifact/revision; consumer setup resolves its recorded committed
   dependency; P7 replacement coverage and legacy retirement gates pass. Then
   P7.5 runs its own clean consumer mapped memory synthesis + observable full
   physical/postcheck/archive/restoration evidence. Old M3 evidence is not a
   substitute for changed delivery/orchestration. P7.6 closes documentation and
   M4 only after these gates.

SRAM S.1–S.4 proceeds under its separate owner. P6 proposes only additive
generator/tool provenance at shared interfaces; agree ownership before touching
bundle/adapter tests. No S-series status or investigation changes, no P0–P5/M3
reopening, and no SRAM or memory-hardening prerequisite is introduced.

## 10. P6.3a checkpoint evidence

Completed before P6.3b work began. `scripts/phase4.py` now returns an internal
`RunOutcome` containing run ID, absolute run directory, absolute record path,
status and exit code. The development script adapter alone retains the historical
one-line `run.json` output. Failure before manifest validation allocates no run;
failure or interruption after allocation finalizes one. The actual preflight
object used by the attempt is written to both `run.json.environment` and
`RUN/preflight.json`; the example shell adapter no longer copies its earlier
standalone report over that evidence.

Postcheck requires and records `--testbench-top`; only `scripts/flow.sh`, clearly
labelled as the repository example adapter, defaults it to `tb_observable`.
Run and postcheck use the same SIGINT/SIGTERM exception path, finalize records,
return 130/143, and `run_logged` terminates and waits for the active child process
group.

Exact checkpoint commands and results:

```text
python3 test/test_phase4.py
Ran 12 tests in 0.032s - OK

python3 -m py_compile scripts/phase4.py test/test_phase4.py
exit 0
```

All external process behavior in these new cases is injected. Existing collector
logic executes directly on fixture files. No PDK, Docker, Nix, provisioning,
synthesis or physical flow was invoked. P6.3 remains open until P6.3b's public
parser and fixed-composition regressions pass.
