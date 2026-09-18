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

## Resolve TT/LibreLane collateral

The OCaml package contains the elaboration and bundle library. External flow
scripts and collateral are resolved from a checkout of **the same** source
revision, placed anywhere the consumer chooses:

```sh
ASIC_SOURCE=/path/for/pinned/asic-source
git clone https://github.com/LeEmperor/hardcaml_asic.git "$ASIC_SOURCE"
git -C "$ASIC_SOURCE" checkout --detach "$ASIC_REV"
TOOLCHAIN=/path/for/asic-toolchain
TOOLCHAIN="$TOOLCHAIN" "$ASIC_SOURCE/scripts/toolchain.sh"
source "$TOOLCHAIN/toolchain-env.sh"
```

`toolchain.lock` in that checkout supplies exact support-tools and PDK commits,
LibreLane and Python versions. Its values mirror the library's emitted
`manifest.json`; [`check_bundle.py`](../test/check_bundle.py) checks that copy for
drift. Keep the source checkout and package pin on the same commit. To validate
an emitted consumer bundle against the actual installed collateral:

```sh
python3 "$ASIC_SOURCE/scripts/phase4.py" preflight "$BUNDLE" \
  --support-tools "$TT" --pdk-root "$PDK_ROOT" --python "$FLOW_PY"
```

Preflight checks the bundle's file hashes, external reference hashes, and
requested tool revisions and versions. It will report a mismatch instead of
silently using nearby collateral. The [bootstrap guide](bootstrap.md) explains
provisioning and the [execution guide](phase4-execution.md) covers subsequent
run and collection commands. A consumer passes its own repository as
`Bundle.render`'s `source_root` and explicitly lists its own source inputs; it
does not pass the library source checkout as the consumer's source root.

## P5.1 check in this worktree

`test/package_consumer_smoke.sh` built the package into a temporary prefix, built
an independent Dune executable using `(libraries hardcaml_asic)`, and ran it:
`address=2 storage=32`. `opam lint hardcaml_asic.opam` passed. The source base
revision at this check was `53b8d8b5506a9215de7ad15b44eaa0286d0e3893`;
the package additions are uncommitted, so that hash alone does not identify the
checked snapshot. The first revision-pinned consumer install should use the
commit containing these files when one exists.
