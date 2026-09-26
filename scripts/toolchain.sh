#!/usr/bin/env bash
# Development adapter for the shared provisioner, installed as
# "hardcaml-asic-flow provision" and shipped as package data at
# flow/hardcaml_asic_flow/data/toolchain.sh.
#
# This goes through the shared dispatcher rather than executing the packaged
# shell directly, so a checkout provisions through exactly the dispatch the
# installed command uses -- including the lock the package carries, which is a
# symlink to this repository's toolchain.lock, so there is still one maintained
# set of pins and no internal --lock-file plumbing spelled out here.
#
# The one thing kept for the checkout is the default location: this repository's
# own .toolchain/. The installed command gets that from its caller.
# bootstrap.sh calls this with --check/--offline/--no-container.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly repo_root

exec python3 "$repo_root/scripts/flow_cli.py" provision \
    --toolchain "${TOOLCHAIN:-$repo_root/.toolchain}" "$@"
