# Bootstrapping the toolchain

The installed `hardcaml-asic-flow provision` checks host prerequisites and
provisions managed flow collateral. A consumer needs no provider source checkout.
The example's thin `./bootstrap.sh` delegates to this installed command;
this provider repository's bootstrap also checks its OCaml development layer.
It requires host tools to be available; provisioning is an explicit environment
operation, not proof that the resulting runtime can execute the flow.

Requested revisions/versions come from [`toolchain.lock`](../../toolchain.lock).
The example defaults to its absolute gitignored `_flow_tools/`; provider
development adapters retain `.toolchain/` as their fallback.
Docker images, host prerequisites, Nix storage and the provider installation have
separate ownership; deleting `.toolchain/` does not remove those.

This repository provisions its own toolchain and does not read another
checkout's. See [Pins and drift](#pins-and-drift) for where the revisions come
from.

## Tool-directory ownership

The shared command supports an arbitrary normal tool root:
`hardcaml-asic-flow provision --toolchain /chosen/path`, or `TOOLCHAIN=/chosen/path`.
The source wrapper accepts `TOOLCHAIN=/chosen/path ./bootstrap.sh` too.
The example selects explicit `--toolchain PATH` > `TOOLCHAIN` > absolute
`hardcaml_asic_example/_flow_tools`. Its bootstrap uses installed provider pins,
with no copied pins, source fallback or automatic refresh. `.toolchain/` and
`_flow_tools/` are directory choices, not required locations. Normal provisioning
may create/update managed children. `--check` is bounded and read-only, including
existing external roots; broader ASIC P6.5c gates remain open. See
[interpreter and readiness semantics](consumer-installation.md#resolve-ttlibrelane-collateral).

### Consumer check

In the user's own shell, from `hardcaml_asic_example`:

```sh
source .dev/asic/current/activate.sh
./bootstrap.sh --check
```

Activation selects the installed library/CLI generation; it does not refresh or
provision tools. Final 2026-10-12 actual check including container exits **0**;
the earlier five-gap result is historical. The final scoped snapshots show
`_flow_tools/`, caches, env and collateral indexes unchanged after the optional
Git-lock fix. Container checks use shared structured metadata observations and
role-specific policy: host 3.11, official-image Python 3.10..3.14 / >=3.10.
`--no-container` skips all engine/image queries and does not certify native EDA.
See [local closeout evidence](../phase_plan.md#hostcontainer-runtime-policy-closeout)
and [fresh bundle preflight](flow.md#runtime-policy-and-launch-binding).

| Storage | Owner / configuration |
| --- | --- |
| Provider library and `hardcaml-asic-flow` CLI | Installation prefix/opam or consumer isolated generation; separate from tool collateral |
| `python`, `tt`, `pdk`, `.venv`, `.venv-precheck`, generated environment | Shared provisioner under `--toolchain PATH` / `TOOLCHAIN` |
| Host CLI Python >= 3.9, explicit external Python/Tcl, OCaml/opam, Git, container runtime | Host/user installation; a venv still depends on its base interpreter and libraries |
| Container images | Docker/Podman-managed image store, not a child selected by `--toolchain` |
| Nix packages used by precheck | Nix-managed store, normally `/nix/store`, not relocated by `--toolchain` |
| Bundles, runs and archives | Consumer-selected output/evidence stores; separate from provisioned tools |

Thus one directory can group the managed collateral, but this API cannot put
literally every tool, system library, daemon/image and Nix object beneath it.

### Local observation — 2026-10-12

The audited ASIC root is `/home/wayne/devel/jane/hardcaml_asic/.toolchain/`, with
`tt/`, `pdk/`, `.venv/` and `.venv-precheck/`. The audit found no installed tool
directories at the usual parent-workspace or `hardcaml_protemu` paths; protemu
retains legacy vendored bootstrap/adopted scripts, which are not an installation.
This is a bounded local inventory, not a machine-wide absence claim.

The literal `.venv/bin/python` imports LibreLane **3.1.0.dev3** under Python
**3.12.3**, whereas bundles request **3.11**. Both venv configuration files name
Python 3.12.3 with `/usr/bin` as home. The generated `toolchain-env.sh` still names
`/home/wayne/devel/jane/asic/.toolchain`; do not treat it as current-path evidence.
Matching package/source versions do not establish environment acceptance.

The prior [official-API observation probe](../../experiments/librelane_observation/README.md)
was **historically BLOCKED** by missing `tkinter` in that old 3.12 venv
([unchanged record](../../evidence/librelane-observation/blocked-local.json)). Zero
of eleven official sequencing cases ran; they have **not yet been rerun**.
The old source `.toolchain/` remains unchanged. A verified managed 3.11 runtime
and disposable LibreLane venv are now available for the next bounded rerun;
official Tcl evaluation smoke passed, but synthetic Flow configuration remains
unvalidated. See [managed-runtime evidence and reproduction](consumer-installation.md#managed-python-integrity-and-initial-platform)
and [current closeout](../phase_plan.md#tool-environment-closeout-acceptance).
Preflight now checks host Tcl readiness. P6.5c is partially addressed; native EDA,
Podman runner generalization and physical gates remain open.

## Quick start

```sh
git clone <this repository> hardcaml_asic && cd hardcaml_asic
./bootstrap.sh          # opam layer + .toolchain/; expect a few minutes and ~1.5 GB
./bootstrap.sh --check  # everything green
scripts/flow.sh         # its help; then build, then emit, then execute
```

If the opam switch is missing packages, `bootstrap.sh` stops and prints the
`opam install` line rather than changing a switch shared with your other
checkouts. `./bootstrap.sh --install-deps` opts in to that change.

## The two layers

They are separate scripts because they fail for unrelated reasons and are fixed
by unrelated commands. Either runs on its own, and `bootstrap.sh` only orders
them; each layer is checked exactly once per invocation.

| Layer | Script | Owns | Default behaviour |
| --- | --- | --- | --- |
| 1. OCaml | `scripts/ocaml-deps.sh` | the `5.2.0+ox` opam switch and the packages the dune files name | reports; installs only with `--install` |
| 2. Flow | `scripts/toolchain.sh` | managed collateral under the selected tool root | fetches and installs what is missing |

Layer 1 defaults to reporting because that switch is shared with every other
Hardcaml checkout on the machine, and installing into it affects them. Layer 2
manages the selected collateral root and may pull into the container image store.
An externally selected root may be shared by several consumers.

## What layer 2 creates

| Path | What | Size |
| --- | --- | --- |
| `.toolchain/python/` | retained pinned Python/Tcl generation and verified archive cache | ~31 MB archive plus extracted runtime |
| `.toolchain/tt` | tt-support-tools, detached at `support_tools_revision` | ~9 MB |
| `.toolchain/pdk` | IHP-Open-PDK, detached at `pdk_revision`; this is `PDK_ROOT` | ~1.3 GB |
| `.toolchain/.venv` | `librelane` at `librelane_version` | ~200 MB |
| `.toolchain/.venv-precheck` | the TT precheck requirements | ~100 MB |
| `.toolchain/toolchain-env.sh` | generated; see [Overriding paths](#overriding-paths) | — |

Plus the container image `ghcr.io/librelane/librelane:<librelane_version>`, which
lives in Docker's own storage rather than under `.toolchain/`. The image tag is
derived from the lockfile exactly as `scripts/phase4.py` derives it, so the two
cannot disagree about which image a run uses.

The precheck environment cannot share `.venv`: upstream's
`precheck/requirements.txt` pins its own KLayout, and installing both into one
environment resolves to a single version that satisfies neither. Two
environments is upstream's arrangement, not a choice made here.

Both checkouts are fetched **by exact hash** with `--depth 1`, never by branch.
The `ihp-sg13cmos5l` branch head has already moved past the pinned
support-tools revision, so a shallow clone of the branch would not contain it.
After checkout, `git rev-parse HEAD` in each directory is the pinned revision
itself, which is what `phase4.py preflight` compares against. The `*_branch`
entries in the lockfile are a hint for a reader and a fallback for a server that
refuses an unadvertised object.

## Options

```sh
./bootstrap.sh                  # converge both layers
./bootstrap.sh --check          # report the state of both, change nothing
./bootstrap.sh --install-deps   # also install missing packages into the opam switch
./bootstrap.sh --offline        # reuse what is installed; fetch nothing
./bootstrap.sh --no-container   # skip the Docker/Podman prerequisite and the image
./bootstrap.sh --python /path/to/python3.11 # explicit external base override
./bootstrap.sh --help
```

`--check` and `--install-deps` contradict each other and are rejected together.
`--offline` turns any gap into an error instead of a fetch, which is what you
want when validating a machine that is supposed to be ready. `--no-container`
is for a run that will use `--native` with locally installed EDA executables.
It does not test those executables. `provision --python BASE` selects the base
interpreter for **new venvs**, not execution Python. Its actual major/minor must
match the lock (currently 3.11); no silent 3.12 fallback is accepted. Before writes,
creation probes `venv`, `ensurepip` and headless Tcl support. Existing venvs are
checked in place, including LibreLane/precheck metadata, and require explicit
repair if mismatched. Preflight/run `--python` instead selects the **flow venv
interpreter**, normally `$TOOLCHAIN/.venv/bin/python`.

Each script takes its own options too, documented in its `--help`:
`scripts/ocaml-deps.sh [--install]` and
`scripts/toolchain.sh [--check] [--offline] [--no-container] [--python BASE]`.

## Checking a machine

`./bootstrap.sh --check` reports gaps without downloads, installations, root
creation, bytecode, index updates or environment rewrites. Python probes are
bounded and use `-I -B`; imports assume trusted installed tools. Generated
environment files are checked as data, not sourced for validation.

The following **historical output** predates strict Python readiness; its warning
and fallback are no longer current behavior. It is retained as an earlier record:

```
==> Checking the OCaml layer (opam switch 5.2.0+ox)
    OCaml 5.2.0+ox
    all 9 opam packages installed

==> Checking host prerequisites
    git 2.43.0
    warning: python3.11 not found; using python3 3.12 for .../.toolchain/.venv
    warning: preflight requires the requested minor version; install python3.11
    docker 29.6.1

==> Resolving tt-support-tools
    missing: tt-support-tools is not present at .../.toolchain/tt
...
==> Summary
    5 gap(s):
      ...
error: the toolchain does not match toolchain.lock
       Rerun without --check to converge it.
```

A fully provisioned machine ends with:

```
==> Summary
    the toolchain matches toolchain.lock
    source .../.toolchain/toolchain-env.sh, or pass these locations to the flow command
```

Exit codes are distinguishable, so a caller can tell a missing tool from a bad
network:

| Code | Meaning |
| --- | --- |
| 0 | the toolchain matches `toolchain.lock` |
| 2 | a host prerequisite is missing, or `--check` found a gap |
| 3 | `toolchain.lock` is malformed |
| 4 | a fetch or install could not complete |
| 5 | something is present at the wrong revision or version |
| 7 | a tool ran and failed |

## Troubleshooting

### `docker is installed but its daemon is not reachable`

The socket is `root:docker` and your session is not in the `docker` group. Check
in this order:

```sh
id -nG | tr ' ' '\n' | grep -x docker        # is this session in the group?
docker info --format '{{.ServerVersion}}'    # can it reach the daemon?
docker run --rm hello-world                  # can it actually run a container?
```

If the group is missing entirely:

```sh
sudo groupadd -f docker && sudo usermod -aG docker "$USER"
sudo snap disable docker && sudo snap enable docker   # snap installs only
```

If the group exists and lists you but `id -nG` does not, the session predates
the change: log out and back in. `newgrp docker` fixes one shell only, so a
program started earlier (an editor, and anything it spawns) still will not have
it until it restarts.

### Python 3.11 missing or an existing venv has the wrong minor

The bundle requests the minor version in `toolchain.lock`; provisioning and
preflight reject a mismatch. Normal provisioning acquires the pinned managed
Python/Tcl base when needed; `--python BASE` explicitly selects an external base.
There is no host-discovery fallback. Nothing waives a mismatch for you:
the shared command has no `--allow-python-mismatch`, and a recorded
`--waiver python-version=REASON` is P6.5's. `scripts/phase4.py` keeps the flag as
an explicit development opt-in. New venvs require a matching managed or external
base; acquiring that base alone does not change an existing venv's Python.
Existing mismatched environments need explicitly authorized repair and validation.

### `<checkout> is at <hash>, not <hash>, and is dirty`

Bootstrap will not move a checkout that has uncommitted work in it, even one it
created, because a debugging edit to the PDK or support tools is not worth losing
silently. Commit, stash or discard the changes there and rerun. Nothing was
changed.

### `nix-shell not found`

Reported, never fatal. Upstream's TT precheck wants a pinned native KLayout and
Magic from its `default.nix`, which pip cannot supply. Precheck is a later step
than bootstrap; `RUN=<run> scripts/flow.sh postcheck` re-checks it.

### `nix-shell is installed but Nix is not usable`

Bootstrap reports Nix executable/version availability as a nonfatal diagnostic;
it does not evaluate Nix or prove daemon access. Postcheck needs a usable Nix
environment, so resolve evaluation or permission failures before a physical run.

A distro Nix restricts that socket to a group and does not necessarily add anyone
to it, so a fresh install reports a permission error on a socket its own daemon
is serving:

```
error: getting status of /nix/var/nix/daemon-socket/socket: Permission denied
```

After an explicitly authorized group change, log out and back in rather than
using `newgrp`: postcheck shells out to both
`nix-shell` and `docker`, and `newgrp` sets one primary group, so a shell that
gains `nix-users` that way can lose `docker`.

### `could not list installed packages in switch`

An opam failure, reported as one, with opam's own message attached. It is not the
same thing as a missing package: `opam list` exits nonzero with empty output when
it fails at all, and reading that as data would report every package as missing.

## Overriding paths

Layer 2 writes `.toolchain/toolchain-env.sh`, which `scripts/flow.sh` sources and
a shell can source by hand to run `librelane` or `python` directly:

```sh
source .toolchain/toolchain-env.sh
```

Generated defaults use safely quoted literals, including spaces/apostrophes;
existing **nonempty** values win. Matching previous-format files are retained.
An override on the command line still wins:

```sh
TT=/some/other/tt-support-tools scripts/flow.sh preflight
TOOLCHAIN=/scratch/asic-toolchain ./bootstrap.sh    # provision somewhere else
```

The variables are `TOOLCHAIN`, `TT`, `PDK`, `PDK_ROOT`, `FLOW_PY` and
`PRECHECK_PY`. `scripts/flow.sh` adds its own (`OUT`, `BUNDLE`, `RUNS`, `KIND`,
`STAGE`, `TESTBENCH`, `TESTBENCH_TOP`, `RUN`), of which `STAGE` and `RUN` are
required rather than defaulted; see [execution and results](flow.md).

## Pins and drift

The authority for every pin is this repository's OCaml source, because that is
what ends up in an emitted bundle and what `phase4.py preflight` checks installed
collateral against:

| Pin | Defined in |
| --- | --- |
| `support_tools_revision` | `lib/target.ml`, `Inputs.reference_cmos5l_6x4` |
| `pdk_revision` | `lib/target.ml`, `Inputs.reference_cmos5l_6x4` |
| `librelane_version` | `lib/bundle.ml`, the `requested_tools` object |
| `python` | `lib/bundle.ml`, the `requested_tools` object |

`toolchain.lock` is a **copy** of those values. It exists because
`scripts/toolchain.sh` provisions the toolchain before anything here can be
built, so it cannot ask the library what to fetch. The copy cannot drift:
`test/check_bundle.py` compares it against the emitted manifest's
`requested_tools` and fails `dune runtest` when they disagree, naming both
values:

```
AssertionError: toolchain.lock librelane_version=9.9.9, manifest requested_tools
librelane=3.1.0.dev3; the lockfile is a copy of lib/, update it
```

The repository and branch entries have no counterpart in a manifest and are not
checked. A bundle pins revisions, not where to fetch them from, on purpose: the
same declaration means the same thing on any machine and behind any mirror.

To change a pin:

1. change it in `lib/target.ml` or `lib/bundle.ml`;
2. change it in `toolchain.lock`;
3. `dune runtest` — this fails if you did only one of the two;
4. `./bootstrap.sh` — the affected checkout or environment is re-resolved, and
   the rest is left alone.

## What bootstrapping does not do

It prepares an environment. It does **not** prove that the design hardens, meets
timing, passes physical verification, or passes precheck; those are the flow
operations and their own exit codes.

It does not install host `opam`, `python3`, `git`, a container runtime or daemon.
Those are prerequisites. Managed collateral goes under the chosen tool root;
container image pulls use the runtime's separate storage. Opam dependency changes
require the explicit opt-in described above.
