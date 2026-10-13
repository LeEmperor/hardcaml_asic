# Consuming `hardcaml_asic` from another project

The Dune project version is `0.1.0`. It installs one wrapped library named
`hardcaml_asic`; a consumer writes `(libraries hardcaml_asic)` in its Dune stanza
and uses modules such as `Hardcaml_asic.Project` and
`Hardcaml_asic.Single_port_ram`. The generated [`hardcaml_asic.opam`](../../hardcaml_asic.opam)
lists the library's OCaml dependencies. Registry publication is unnecessary.

Before adopting the current development provider, apply the
[source-breaking API migration](../phase_plan.md#public-api-rename-migration-and-evidence):
`Build` → `Elaborated_project`, `Resolved_build` → `Resolved_flow`, resolved
field `build` → `elaborated_project`, and `Bundle.render ?simulation_build` →
`?simulation_project`. There are no aliases. The FIFO specimen is migrated;
`hardcaml_protemu` still requires separate migration before adopting this provider.
This checkpoint publishes no new release or dependency pin.

The project-centered API adds constructor `?source_inputs`, the inventory getter,
declaration-only `Project.describe`, shared `Project.emit_bundle` and
`emit_bundle_to_store` / `Bundle.publish`. The migrated FIFO owns
`Fifo_asic.project ()` and `project describe|emit|preflight|run`; see the
[entrypoint guide](bundle-emission.md#project-centered-entry-point).
Its recorded `1714764859274f80a9f5ad207421a04601824e99` baseline cannot supply this
API. Recorded refresh now rejects it without replacing the current selection.
Use explicit [development refresh and activation](../development/consumer-dependency-workflow.md#implemented-commands)
until the owner commits a suitable provider candidate and deliberately adopts it
in the consumer record. The successful local refresh is not a published release
or P6 source stamp.

## Pin the library source

Choose a full commit hash containing the package files and record it in the
consumer's dependency documentation or lockfile. A branch name alone can move.
From any directory, with an opam switch that has the OxCaml/Hardcaml toolchain:

```sh
ASIC_REV=<full-hardcaml_asic-commit-hash>
opam pin add --no-action hardcaml_asic "git+https://github.com/LeEmperor/hardcaml_asic.git#$ASIC_REV"
opam install hardcaml_asic
```

The consumer's `dune` file can then name `hardcaml_asic` directly. Pinning changes
that opam switch; use a project-local switch if the consumer should have an
isolated dependency set. Upgrade by changing `ASIC_REV` deliberately and
rebuilding. This package does not need to live in a sibling directory with a
specific name.

For a build from a local source snapshot, install to an isolated prefix instead:

```sh
cd /path/to/hardcaml_asic
PREFIX=/tmp/asic-package-prefix
dune build @install
dune install --prefix "$PREFIX" hardcaml_asic
cd /path/to/consumer
OCAMLPATH="$PREFIX/lib${OCAMLPATH:+:$OCAMLPATH}" dune build
```

That route installs no package into the shared opam switch. The source snapshot
used for the prefix must be recorded separately; a dirty worktree cannot be
represented by a Git commit hash. [`test/package_consumer_smoke.sh`](../../test/package_consumer_smoke.sh)
checks this path with a fresh prefix and an unrelated Dune project under `/tmp`.

## The installed `hardcaml-asic-flow` command

Since P6.4a the same package installs the flow tooling beside the library, so a
consumer pins one revision for both:

```text
$PREFIX/bin/hardcaml-asic-flow                            the command
$PREFIX/lib/hardcaml_asic/flow/hardcaml_asic_flow/        its private modules
$PREFIX/lib/hardcaml_asic/flow/hardcaml_asic_flow/data/   toolchain.sh, toolchain.lock, managed-python.json
```

The command works through `PATH` and through a symlink to it. It finds its
modules and data relative to its own installed location only; it does not search
for a source checkout, and an incomplete installation is reported rather than
worked around. `--help` and `--version` need no Git, OCaml toolchain, PDK,
container or provisioning.

Host requirements: Python 3.9 or newer (declared as `conf-python-3`; the minor
bound is checked by the command, since the conf package cannot express it) and a
POSIX shell. Provisioning also needs Bash, Git and the usual Unix utilities.
Running and postchecking a design need Docker, LibreLane and Nix. Installing the
package fetches none of those, and `--version`, `--help`, `collect`, `report` and
`archive` need none of them.

**Installing the package only supports the standard `--prefix` layout.** Placing
the library and the command under independently chosen directories is not
supported; the launcher expects `../lib/hardcaml_asic/flow` relative to itself.

Two things are not yet true of `--version`, and will not be until P6.5: it does
not report a source revision or checkout state, and it does not verify that the
linked OCaml library was built from the same artifact as the command. It says so
in both its human and `--json` output rather than implying otherwise.

### CLI contract 4 migration

The current provider advertises `cli_contract.version = 4` in `--version --json`.
This is distinct from package 0.1.0, record schema 1 and unstamped source identity.
Human summaries are now the default: active machine calls must explicitly pass
`--json`. `--verbose` writes diagnostics only to stderr. Run/execute no longer
require `--runs`: the default is `<caller-cwd>/_flow_results/runs`, with explicit
`--results-root` and `--runs` overrides. Standalone preflight saves an operation
and report by default; `--output FILE` writes only that file, requiring its parent.
`collect --json` still writes normal results; legacy `collect --stdout` and report
remain read-only. Archive JSON list is unsupported. The example accepts exactly
contracts 2 and 3 before dispatch and selects project-relative defaults; unknown
versions remain rejected. Contract 3 extends human defaults to stages, all observation
queries, checkpoint and finalization inspectors, and finalize. Add `--json` to every
parsing invocation; observed stages and finalize remain JSONL, including the flushed
early receipt. This stdout-default change is intentionally not CLI backward compatible.
See the [full command/storage matrix](flow.md#default-result-store-and-cli-contract-3).
Contract 4 makes fresh/resumed `stages` journal by default under
`<resolved-workspace-parent>/observations`. Parse allocation/terminal JSONL or
explicitly use `--no-observation`; `--observation-store` remains an override.
Caught preparation failures/interruption now deliver the defined terminal envelope
with recorded observation facts and a result path only when actually published.
The example's contract-2/3 gates must migrate to 4 in flow-journal slice 3 before
refreshing; slice 1 does not refresh the sibling installation.
After that migration, development consumers refresh the private prefix through their existing
dependency script, then source `current/activate.sh` in the shell running Dune and
the CLI. Refresh cannot activate its parent shell. The example's recorded pin is
still historical and lacks the required Project API; use explicit development
mode until owner adoption. See [integration evidence](../development/human-readable-flow-output.md#slice-3--independent-integration-2026-10-13).
`scripts/phase4.py` retains its historical development path-only run spelling.

## Resolve TT/LibreLane collateral

`toolchain.lock` supplies exact support-tools and PDK commits, LibreLane and
Python versions, and ships as the installed command's runtime data. Its values
mirror the library's emitted `manifest.json`;
[`check_bundle.py`](../../test/check_bundle.py) checks that copy for drift. Once a
bundle exists, the bundle is authoritative and preflight rejects collateral that
disagrees with it.

```sh
TOOLCHAIN=/path/for/asic-toolchain
TOOLCHAIN="$TOOLCHAIN" hardcaml-asic-flow provision
source "$TOOLCHAIN/toolchain-env.sh"
```

Normal provisioning uses the installed provider's pinned **managed Python** when
new venvs need a base. It retains the runtime under `$TOOLCHAIN/python/`; the
LibreLane and precheck venvs remain separate user environments. Existing venvs
are checked in place and need no base acquisition when both already exist.
A wrong existing Python version requires explicit repair, never automatic recreation.

`provision --python /path/to/python3.11` is the explicit **external base override**
for new venvs; both bootstraps forward it. Its actual major/minor must match the
lock, with `venv`, `ensurepip` and working headless Tcl. An invalid override fails
before managed acquisition or collateral writes; there is no host-discovery or
other-minor fallback. No public `--python-only` mode exists.

### Managed Python integrity and initial platform

The installed [archive pin](../../flow/hardcaml_asic_flow/data/managed-python.json)
selects CPython **3.11.17 / PBS 20261009**, `x86_64-unknown-linux-gnu`,
`install_only_stripped`: **30,808,475 bytes**, SHA-256
`89db7607ebadb77a64709d159b86555d995368ec385a2ab33b00477790c543b0`.
Official release digest and SHA256SUMS matched. Acquisition verifies size/digest
before extraction or execution, bounds extraction and rejects unsafe paths/links
and special members. It probes the private stage and relocated final runtime,
then publishes a receipt. Generation directories are retained and never replaced,
including failed/unready generations; repair is an explicit owner action.

Initial support is **Linux glibc x86_64 >= 2.17**, not universal portability.
Atomic no-replace publication uses x86_64 Linux `renameat2` syscall 316 and
requires kernel/filesystem support; unsupported publication fails explicitly.
The actual accepted host used glibc **2.39**, kernel **6.8**. This distribution
supplies Python/Tcl resources without Python 3.11 or Tcl system packages. The host
CLI still requires Python **>= 3.9**; OS libraries/certificates and Docker/Nix
remain separate prerequisites/storage.

`--check` only inspects the receipt and probes readiness: no lock/cache creation
or archive acquisition. `--offline` permits acquisition from the verified archive
cache, fails on a cache miss and never falls back to another interpreter; it is
not generally read-only. Archive integrity plus a local receipt is **not P6.5
source/runtime attestation** or proof of the current extracted tree's every byte.

The [actual runtime evidence](../../evidence/managed-python/actual-runtime.json)
records Tcl **9.0.4**, Tk **9.0**, OpenSSL **3.5.9**, two disposable pip venvs and
wheel-only LibreLane **3.1.0.dev3** with official `TclUtils._eval_env` returning 42.
This is Tcl smoke acceptance, not official Flow-case or physical acceptance.
To reproduce that experiment from the provider root, explicitly opt in to archive
acquisition and wheel downloads (this is not a read-only check or Dune test):

```sh
python3 -I -B experiments/managed_python/accept.py \
  --example /absolute/path/to/hardcaml_asic_example --acquire-and-install
```

`provision --check --no-container --toolchain "$TOOLCHAIN"` performs bounded
read-only checks: no downloads, installation, root creation, env rewrite,
container execution or Nix evaluation. It checks LibreLane metadata/import and
Tcl, and precheck Python, exact-pinned requirement metadata and the `klayout`
import when support-tools requirements are available. Unsupported requirement
syntax is diagnosed without pip resolution. Python probes use `-I -B`; Git
probes disable optional locks. Imports execute installed package code, so these
checks assume trusted installed tools. The host also needs Bash and `timeout`.
Nix availability remains a nonfatal bootstrap diagnostic, not proof of evaluation
or daemon access. `--no-container` skips both engine and image queries and does
not certify native EDA readiness. Preflight now checks host Tcl readiness; native
capabilities beyond these probes remain unmodeled. With container checks enabled,
the shared observer checks the official image's distribution-supported Python
and exact LibreLane metadata. See [runtime policy](flow.md#runtime-policy-and-launch-binding).

The generated shell file exports `ASIC_TOOLCHAIN`, `TT`, `PDK`, `PDK_ROOT`,
`FLOW_PY`, and `PRECHECK_PY`. Single-quoted literal defaults safely preserve
spaces and apostrophes, and existing nonempty values win. Checks inspect this
file as data for expected paths; matching previous-format files are retained.
In contrast to provisioning, **preflight/run `--python` selects the flow venv
interpreter**, normally `$TOOLCHAIN/.venv/bin/python`.
Interpreter paths retain their lexical spelling, including venv and parent
symlinks, so execution does not accidentally select the base Python.

The example's thin bootstrap uses the installed provider, with no required source
checkout, copied pins, source fallback or automatic refresh. Root precedence is
explicit `--toolchain` > `TOOLCHAIN` > absolute example `_flow_tools/`.
Provider library refresh is separate. In the user's shell, first
`source .dev/asic/current/activate.sh`, then `./bootstrap.sh --check`;
the final actual check including container exits 0. The earlier five-gap result
is historical. See [consumer check](bootstrap.md#consumer-check) and
[dated acceptance](../phase_plan.md#hostcontainer-runtime-policy-closeout).

To validate an emitted consumer bundle against the actual installed collateral:

```sh
hardcaml-asic-flow preflight "$BUNDLE" \
  --support-tools "$TT" --pdk-root "$PDK_ROOT" --python "$FLOW_PY"
```

Preflight checks the bundle's file hashes, external reference hashes, and
requested tool revisions and versions. It will report a mismatch instead of
silently using nearby collateral. The [bootstrap guide](bootstrap.md) explains
provisioning and the [execution guide](flow.md) covers subsequent
run and collection commands; both still describe the repository's own
`scripts/` entry points, which are development adapters onto these same modules.
A consumer passes its own repository as `Bundle.render`'s `source_root` and
explicitly lists its own source inputs; it does not pass the library source
checkout as the consumer's source root.

Installed-operation integration (ASIC P6.4b) is delivered. Source-artifact
identity and the remaining independent-installation gates are ASIC P6.5/P6.6.
Historical consumer migration is ASIC P7; it is not a prerequisite for a new
consumer such as `hardcaml_asic_example`.

## P5.1 check in this worktree

`test/package_consumer_smoke.sh` built the package into a temporary prefix, built
an independent Dune executable using `(libraries hardcaml_asic)`, and ran it:
`address=2 storage=32`. `opam lint hardcaml_asic.opam` passed. The source base
revision at this check was `53b8d8b5506a9215de7ad15b44eaa0286d0e3893`;
the package additions are uncommitted, so that hash alone does not identify the
checked snapshot. Protemu subsequently pinned
`a257424c3ae31fd6ee10cea052cc7577f15d2677`; the P5.4 clean-staging record in
the [phase plan](../archive/phase-plan-through-p6.4b.md#8-p5--reference-consumer-adoption-and-initial-usage)
builds that exact revision into an isolated prefix and resolves it without a
sibling path dependency.
