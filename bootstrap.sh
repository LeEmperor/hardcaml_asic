#!/usr/bin/env bash
# The one command for a fresh clone of hardcaml_asic. Safe to rerun at any time: every
# layer is checked and only what is missing or out of date is changed.
#
#   1. OCaml layer   scripts/ocaml-deps.sh   the opam switch and the packages dune needs
#   2. Flow layer    scripts/toolchain.sh    .toolchain/{tt,pdk,.venv,.venv-precheck}
#
# Usage:
#   ./bootstrap.sh                  # converge both layers
#   ./bootstrap.sh --check          # report the state of both, change nothing
#   ./bootstrap.sh --install-deps   # also install missing packages into the opam switch
#   ./bootstrap.sh --offline        # reuse what is installed; fetch nothing
#   ./bootstrap.sh --no-container   # skip the Docker/Podman prerequisite and image
#
# Then:
#   scripts/flow.sh                 # build, emit, preflight, run, postcheck, collect, report
#
# The two layers are separate scripts because they fail for unrelated reasons and are
# fixed by unrelated commands: layer 1 by opam, against a switch shared with every other
# Hardcaml checkout on the machine, and layer 2 by git and pip, against a directory owned
# entirely by this repository. Either can be run on its own; this script only orders them,
# and each layer is checked exactly once per invocation.
#
# Layer 1 defaults to reporting rather than installing, because the switch is shared:
# --install-deps is the opt-in for changing something another checkout depends on. Layer 2
# has no such restraint, since everything it touches is under .toolchain/.
#
# What this does NOT do: install opam, python3, git or a container runtime, start a
# container daemon, or put anything on your PATH. Each of those is reported with the
# command that fixes it.
#
# Exit codes are the layers' own, so a caller can tell them apart: see the two scripts.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly repo_root

usage() {
    sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

deps_args=()
toolchain_args=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --install-deps) deps_args+=(--install) ;;
        --check) toolchain_args+=(--check) ;;
        --offline) toolchain_args+=(--offline) ;;
        --no-container) toolchain_args+=(--no-container) ;;
        -h|--help) usage; exit 0 ;;
        *) echo "bootstrap: unknown option: $1 (try --help)" >&2; exit 1 ;;
    esac
    shift
done

# --check promises to change nothing, so it cannot be combined with an option whose whole
# purpose is to install. Caught here rather than letting layer 1 install and layer 2 then
# report it would have.
if [[ " ${toolchain_args[*]-} " == *" --check "* && ${#deps_args[@]} -gt 0 ]]; then
    echo "bootstrap: --check and --install-deps contradict each other" >&2
    exit 1
fi

"$repo_root/scripts/ocaml-deps.sh" "${deps_args[@]}"
"$repo_root/scripts/toolchain.sh" "${toolchain_args[@]}"
