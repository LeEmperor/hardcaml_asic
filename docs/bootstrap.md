# Bootstrapping the toolchain

`./bootstrap.sh` prepares everything the implementation flow needs on a machine
that has none of it, and is safe to rerun on a machine that has all of it. It is
the command after a fresh clone, after a pull that changes a pin, and after a
reboot that leaves you wondering what is still installed.

Everything it fetches is pinned by [`toolchain.lock`](../toolchain.lock) and
lands under one directory, `.toolchain/`, which is gitignored. Deleting that
directory undoes the whole flow layer and nothing else.

This repository provisions its own toolchain and does not read another
checkout's. See [Pins and drift](#pins-and-drift) for where the revisions come
from.

## Quick start

```sh
git clone <this repository> hardcaml_asic && cd hardcaml_asic
./bootstrap.sh          # opam layer + .toolchain/; expect a few minutes and ~1.5 GB
./bootstrap.sh --check  # everything green
scripts/flow.sh         # build, emit, preflight, run, postcheck, collect, report
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
| 2. Flow | `scripts/toolchain.sh` | everything under `.toolchain/` | fetches and installs what is missing |

Layer 1 defaults to reporting because that switch is shared with every other
Hardcaml checkout on the machine, and installing into it affects them. Layer 2
has no such restraint: everything it touches is this repository's.

## What layer 2 creates

| Path | What | Size |
| --- | --- | --- |
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
./bootstrap.sh --help
```

`--check` and `--install-deps` contradict each other and are rejected together.
`--offline` turns any gap into an error instead of a fetch, which is what you
want when validating a machine that is supposed to be ready. `--no-container`
is for a run that will use `--native` with locally installed EDA executables.

Each script takes its own options too, documented in its `--help`:
`scripts/ocaml-deps.sh [--install]` and
`scripts/toolchain.sh [--check] [--offline] [--no-container]`.

## Checking a machine

`./bootstrap.sh --check` reports every gap in one pass rather than stopping at
the first. On a machine with the opam layer ready and nothing else:

```
==> Checking the OCaml layer (opam switch 5.2.0+ox)
    OCaml 5.2.0+ox
    all 9 opam packages installed

==> Checking host prerequisites
    git 2.43.0
    warning: python3.11 not found; using python3 3.12 for .../.toolchain/.venv
    warning: preflight needs --allow-python-mismatch, which flow.sh passes by default
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
    source .../.toolchain/toolchain-env.sh, or just run scripts/flow.sh
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

### `warning: python3.11 not found`

Expected on a host with a different Python. The bundle requests the minor version
in `toolchain.lock`; preflight rejects a mismatch unless the caller opts in, and
`scripts/flow.sh` passes `--allow-python-mismatch` by default. Set
`ALLOW_PYTHON_MISMATCH=0` to require the exact version. Installing `python3.11`
and re-running bootstrap removes the warning, since the venv is created with
`python<version>` when that interpreter exists.

### `<checkout> is at <hash>, not <hash>, and is dirty`

Bootstrap will not move a checkout that has uncommitted work in it, even one it
created, because a debugging edit to the PDK or support tools is not worth losing
silently. Commit, stash or discard the changes there and rerun. Nothing was
changed.

### `nix-shell not found`

Reported, never fatal. Upstream's TT precheck wants a pinned native KLayout and
Magic from its `default.nix`, which pip cannot supply. Precheck is a later step
than bootstrap; `scripts/flow.sh postcheck` re-checks it.

### `nix-shell is installed but Nix is not usable`

Also reported and never fatal, for the same reason, but it is the more expensive
one to ignore: postcheck is the last step of the flow, so a Nix that cannot
evaluate is discovered after the hardening run it follows. Bootstrap probes the
daemon with `nix-store --version` rather than looking for the binary on `PATH`,
because an installed `nix-shell` whose daemon socket the user cannot open fails
every evaluation.

A distro Nix restricts that socket to a group and does not necessarily add anyone
to it, so a fresh install reports a permission error on a socket its own daemon
is serving:

```
error: getting status of /nix/var/nix/daemon-socket/socket: Permission denied
```

Bootstrap reads the socket's group and prints the `usermod` line for it. Log out
and back in afterwards rather than using `newgrp`: postcheck shells out to both
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

Every assignment in it yields to a value already set in the environment, so an
override on the command line still wins:

```sh
TT=/some/other/tt-support-tools scripts/flow.sh preflight
TOOLCHAIN=/scratch/asic-toolchain ./bootstrap.sh    # provision somewhere else
```

The variables are `TOOLCHAIN`, `TT`, `PDK`, `PDK_ROOT`, `FLOW_PY` and
`PRECHECK_PY`. `scripts/flow.sh` adds its own (`OUT`, `BUNDLE`, `RUNS`, `KIND`,
`STAGE`, `TESTBENCH`, `RUN`, `ALLOW_PYTHON_MISMATCH`); see
[execution and results](phase4-execution.md).

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
timing, passes physical verification, or passes precheck; those are
`scripts/flow.sh` and its own exit codes.

It also installs nothing outside `.toolchain/` and the opam switch: not `opam`,
`python3`, `git` or a container runtime, not a container daemon, and nothing on
your `PATH`. Each of those is reported with the command that fixes it.
