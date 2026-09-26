# Consuming `hardcaml_asic` from another project

The Dune project version is `0.1.0`. It installs one wrapped library named
`hardcaml_asic`; a consumer writes `(libraries hardcaml_asic)` in its Dune stanza
and uses modules such as `Hardcaml_asic.Project` and
`Hardcaml_asic.Single_port_ram`. The generated [`hardcaml_asic.opam`](../hardcaml_asic.opam)
lists the library's OCaml dependencies. Registry publication is unnecessary.

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
represented by a Git commit hash. [`test/package_consumer_smoke.sh`](../test/package_consumer_smoke.sh)
checks this path with a fresh prefix and an unrelated Dune project under `/tmp`.

## The installed `hardcaml-asic-flow` command

Since P6.4a the same package installs the flow tooling beside the library, so a
consumer pins one revision for both:

```text
$PREFIX/bin/hardcaml-asic-flow                            the command
$PREFIX/lib/hardcaml_asic/flow/hardcaml_asic_flow/        its private modules
$PREFIX/lib/hardcaml_asic/flow/hardcaml_asic_flow/data/   toolchain.sh, toolchain.lock
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

## Resolve TT/LibreLane collateral

`toolchain.lock` supplies exact support-tools and PDK commits, LibreLane and
Python versions, and ships as the installed command's runtime data. Its values
mirror the library's emitted `manifest.json`;
[`check_bundle.py`](../test/check_bundle.py) checks that copy for drift. Once a
bundle exists, the bundle is authoritative and preflight rejects collateral that
disagrees with it.

```sh
TOOLCHAIN=/path/for/asic-toolchain
TOOLCHAIN="$TOOLCHAIN" hardcaml-asic-flow provision
source "$TOOLCHAIN/toolchain-env.sh"
```

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

Migrating the reference consumer off its vendored copies onto this command is
P7, and the remaining installed-operation integration is P6.4b: until those
land, a consumer that is working today should keep its current path.

## P5.1 check in this worktree

`test/package_consumer_smoke.sh` built the package into a temporary prefix, built
an independent Dune executable using `(libraries hardcaml_asic)`, and ran it:
`address=2 storage=32`. `opam lint hardcaml_asic.opam` passed. The source base
revision at this check was `53b8d8b5506a9215de7ad15b44eaa0286d0e3893`;
the package additions are uncommitted, so that hash alone does not identify the
checked snapshot. Protemu subsequently pinned
`a257424c3ae31fd6ee10cea052cc7577f15d2677`; the P5.4 clean-staging record in
the [phase plan](phase_plan.md#8-p5--reference-consumer-adoption-and-initial-usage)
builds that exact revision into an isolated prefix and resolves it without a
sibling path dependency.
