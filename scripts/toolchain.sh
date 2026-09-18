#!/usr/bin/env bash
# Flow layer of the bootstrap: the external collateral scripts/phase4.py needs before
# "flow.sh preflight" can pass. Everything it installs lives under one directory and is
# pinned by toolchain.lock. See bootstrap.sh, which runs this after the OCaml layer.
#
# Usage:
#   scripts/toolchain.sh                 # converge on the lockfile, fetching what is missing
#   scripts/toolchain.sh --check         # report every gap, change nothing
#   scripts/toolchain.sh --offline       # reuse what is installed, fetch nothing
#   scripts/toolchain.sh --no-container  # skip the Docker/Podman prerequisite and image
#
# What it creates, all under $TOOLCHAIN (default .toolchain/ in this repository):
#   tt/                 tt-support-tools, detached at support_tools_revision
#   pdk/                IHP-Open-PDK, detached at pdk_revision; this is PDK_ROOT
#   .venv/              librelane at librelane_version
#   .venv-precheck/     the TT precheck requirements, which cannot share .venv
#   toolchain-env.sh    generated; scripts/flow.sh reads it, and a shell can source it
#
# Safe to rerun. Every step checks first and does nothing when it is already satisfied,
# so this is the command after a pull that changes toolchain.lock as well as the command
# on a new machine.
#
# It installs nothing outside $TOOLCHAIN. The opam switch is the other script's business
# (scripts/ocaml-deps.sh), the container daemon and image are the host's, and the PDK is
# fetched but never written to by the flow.
#
# Careful: bootstrapping prepares an environment. It does NOT prove the design hardens,
# meets timing, or passes precheck. Those are scripts/flow.sh and its own exit codes.
#
# Both revisions are fetched by exact hash with --depth 1, not by branch. The
# support-tools branch head has already moved past the pinned revision, so a shallow
# clone of the branch would not contain it; the branch in the lockfile is only a hint for
# a reader and a fallback when a server refuses an unadvertised object.
#
# Exit codes, distinguishable so a caller can tell a missing tool from a bad network:
#   0  the toolchain matches the lockfile
#   2  a host prerequisite is missing, or --check found a gap
#   3  toolchain.lock is malformed
#   4  a fetch or install could not complete
#   5  something is present at the wrong revision or version
#   7  a tool ran and failed

set -euo pipefail

readonly EX_PREREQ=2
readonly EX_LOCKFILE=3
readonly EX_NETWORK=4
readonly EX_MISMATCH=5
readonly EX_TOOL=7

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly repo_root
readonly lock_file="$repo_root/toolchain.lock"

# One directory holds everything, so removing it undoes the whole flow layer and nothing
# else. Overridable for a shared or out-of-tree toolchain; .gitignore covers the default.
TOOLCHAIN=${TOOLCHAIN:-$repo_root/.toolchain}
readonly TOOLCHAIN
readonly tt_dir="$TOOLCHAIN/tt"
readonly pdk_dir="$TOOLCHAIN/pdk"
readonly venv_dir="$TOOLCHAIN/.venv"
readonly precheck_venv_dir="$TOOLCHAIN/.venv-precheck"
readonly env_file="$TOOLCHAIN/toolchain-env.sh"

check=0
offline=0
no_container=0

usage() {
    sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --check) check=1 ;;
        --offline) offline=1 ;;
        --no-container) no_container=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "toolchain: unknown option: $1 (try --help)" >&2; exit 1 ;;
    esac
    shift
done

step() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
# Counted so the closing summary can admit they happened. A warning is something the run
# survived but a later step may not, and the summary is the line people actually read.
warnings=0
warn() { warnings=$((warnings + 1)); printf '    warning: %s\n' "$*" >&2; }
net()  { printf '    [network] %s\n' "$*"; }

die() {
    local code=$1
    shift
    printf '\nerror: %s\n' "$1" >&2
    shift
    local line
    for line in "$@"; do printf '       %s\n' "$line" >&2; done
    exit "$code"
}

mutating() { [[ $check -eq 0 ]]; }

# In --check mode a gap is recorded and the run continues, so one invocation reports
# every one of them rather than the first. Outside --check nothing calls this: the step
# fixes the gap instead.
problems=()
gap() {
    problems+=("$1")
    printf '    missing: %s\n' "$1" >&2
}

# One value out of toolchain.lock. The file is parsed as data and never sourced, so a
# stray line in it cannot run anything.
lock() {
    local key=$1 value
    value=$(sed -n "s/^${key}=//p" "$lock_file" | head -1)
    [[ -n $value ]] || die "$EX_LOCKFILE" "toolchain.lock has no '${key}=' entry" \
        "Expected at $lock_file"
    printf '%s' "$value"
}

# ---------------------------------------------------------------------------
# Lockfile
# ---------------------------------------------------------------------------
read_lockfile() {
    step "Reading $lock_file"
    [[ -f $lock_file ]] || die "$EX_LOCKFILE" "no toolchain.lock at $lock_file"

    support_tools_repository=$(lock support_tools_repository)
    support_tools_branch=$(lock support_tools_branch)
    support_tools_revision=$(lock support_tools_revision)
    pdk_name=$(lock pdk)
    pdk_repository=$(lock pdk_repository)
    pdk_branch=$(lock pdk_branch)
    pdk_revision=$(lock pdk_revision)
    librelane_version=$(lock librelane_version)
    python_version=$(lock python)

    # The image name is derived exactly as scripts/phase4.py derives it, rather than
    # pinned separately, so the two cannot disagree about which image a run uses.
    librelane_image="ghcr.io/librelane/librelane:$librelane_version"

    local revision
    for revision in "$support_tools_revision" "$pdk_revision"; do
        [[ $revision =~ ^[0-9a-f]{40}$ ]] || die "$EX_LOCKFILE" \
            "not a full 40-character commit hash: $revision"
    done

    info "pdk $pdk_name, librelane $librelane_version, python $python_version"
    info "toolchain root $TOOLCHAIN"
}

# Does the group list $2 contain the group $1? The lists come from `id -nG`, which is
# space-separated and unordered, so the surrounding spaces are what keep "docker" from
# matching "docker-users".
has_group() { [[ " $2 " == *" $1 "* ]]; }

# Why a socket the user was told to gain access to is still refusing them. Three states
# look identical in the error text and want opposite advice, so they are separated here:
# `id -nG` reports the credentials this process is actually running with, while
# `id -nG "$USER"` re-reads the group database. They disagree precisely when usermod has
# already run and every process in this login session predates it -- the state where
# repeating the usermod advice sends people in circles, because the membership is already
# on disk and only a fresh set of credentials can pick it up.
#
# The advice goes to stdout one line per line, unindented, because the two callers route
# it differently: info indents by two more spaces, die by seven. $2 overrides the command
# that joins the group, since Docker's group may not exist yet and joining it is then two
# commands; $3 adds a command to check the daemon with when the group is not the problem.
group_gap_advice() {
    local group=$1
    local join=${2:-"sudo usermod -aG $group \$USER"}
    local daemon_check=${3:-}

    if ! has_group "$group" "$(id -nG "$USER" 2>/dev/null)"; then
        echo "Join '$group' with:"
        echo "  $join"
        echo "  exec sg $group bash      # then pick it up without logging out"
        return 0
    fi

    if has_group "$group" "$(id -nG 2>/dev/null)"; then
        echo "You are in '$group' and so is this shell, so the refusal is not about groups."
        [[ -z $daemon_check ]] || echo "  $daemon_check"
        return 0
    fi

    # Groups are set once by PAM at login and inherited across fork(), so nothing in an
    # existing session re-reads them. Restarting a shell, or tmux, under that session
    # inherits the stale set and looks like the fix failing.
    echo "You are already in '$group'; this login session predates the change and still"
    echo "carries the old group set. Pick it up with either of:"
    echo "  exec sg $group bash          # this shell, keeping its other groups"
    echo "  # a brand-new SSH connection  (restarting tmux is not enough: a new server"
    echo "  #   forked from this session inherits the same stale credentials, and ssh"
    echo "  #   ControlMaster will silently reuse the old session too)"
}

# ---------------------------------------------------------------------------
# Host prerequisites: what this script cannot install for you
# ---------------------------------------------------------------------------
check_prerequisites() {
    step "Checking host prerequisites"

    command -v git >/dev/null 2>&1 || die "$EX_PREREQ" "git is not installed"
    info "git $(git --version | awk '{print $3}')"

    command -v python3 >/dev/null 2>&1 || die "$EX_PREREQ" "python3 is not installed"
    local have
    have=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')

    # The bundle asks for one Python minor version and the host often has another. That
    # is a real difference, not a formality: preflight rejects it unless the caller opts
    # in, which scripts/flow.sh does by default (ALLOW_PYTHON_MISMATCH). Reported here so
    # the reason is visible at bootstrap time rather than four steps into a flow run.
    venv_python=python3
    if command -v "python$python_version" >/dev/null 2>&1; then
        venv_python="python$python_version"
        info "python $python_version (matches the lockfile)"
    else
        warn "python$python_version not found; using python3 $have for $venv_dir"
        warn "preflight needs --allow-python-mismatch, which flow.sh passes by default"
    fi

    python3 -c 'import venv' >/dev/null 2>&1 || die "$EX_PREREQ" \
        "the python3 venv module is missing" \
        "Install it with your package manager (apt install python3-venv)"

    if [[ $no_container -eq 1 ]]; then
        warn "container check skipped; a run will need --native and local EDA tools"
        return
    fi

    container=""
    if command -v docker >/dev/null 2>&1; then
        container=docker
    elif command -v podman >/dev/null 2>&1; then
        container=podman
    else
        die "$EX_PREREQ" "neither docker nor podman is installed" \
            "The LibreLane runner is Dockerized by default." \
            "Install one, or rerun with --no-container to skip this."
    fi

    # An installed client with an unreachable daemon is the common case after a fresh
    # install: the socket is root-owned and the user is not in its group yet. The fix is a
    # group change, so say so rather than reporting "docker is missing". Which of the three
    # group states applies is worth separating for the same reason it is in
    # check_precheck_nix, and the socket answers a question the group names cannot: a
    # socket that does not exist means the daemon is down, not that a group is missing.
    if ! "$container" info >/dev/null 2>&1; then
        local socket_group="" advice=()
        if [[ $container == docker ]]; then
            socket_group=$(stat -c '%G' /var/run/docker.sock 2>/dev/null) || socket_group=""
        fi

        if [[ -n $socket_group && $socket_group != root ]]; then
            advice=("Its socket is group-restricted to '$socket_group'.")
            mapfile -t -O "${#advice[@]}" advice < <(group_gap_advice "$socket_group" \
                "sudo groupadd -f $socket_group && sudo usermod -aG $socket_group \$USER" \
                "systemctl status $container")
        elif [[ $container == docker ]]; then
            advice=("Start it, or add yourself to its socket group:"
                "  sudo groupadd -f docker && sudo usermod -aG docker \$USER"
                "  exec sg docker bash      # or open a new login session")
        else
            # Rootless Podman gates its socket on the user, not a group, so none of the
            # Docker advice transfers.
            advice=("Start it, or rerun with --no-container to skip the container steps.")
        fi

        # A snap-installed Docker keeps its own view of the user's groups and picks a
        # change up only when the snap restarts, so the advice above is incomplete for it
        # in exactly the group cases. Naming it only when that Docker is the one installed
        # keeps it out of the way of everyone else.
        if [[ $container == docker ]] && snap list docker >/dev/null 2>&1; then
            advice+=("Docker here is a snap, which also needs:"
                "  sudo snap disable docker && sudo snap enable docker")
        fi

        die "$EX_PREREQ" "$container is installed but its daemon is not reachable" \
            "${advice[@]}"
    fi
    info "$container $("$container" info --format '{{.ServerVersion}}' 2>/dev/null)"
}

# ---------------------------------------------------------------------------
# Is $dir the top level of its own git repository? A bare `-d $dir/.git` test is not
# enough. An interrupted `git init` or fetch leaves behind a .git directory whose HEAD is
# empty, which git does not recognise as a repository at all; discovery then walks *up*,
# and every later `git -C "$dir"` silently operates on the enclosing checkout instead.
# That is not hypothetical: it repointed this repository's own origin at the PDK and
# detached its HEAD onto a PDK commit. Nothing below aims a git command at $dir until
# this has returned true.
is_own_repo() {
    local dir=$1
    [[ -d $dir/.git ]] || return 1
    GIT_DIR="$dir/.git" GIT_WORK_TREE="$dir" git rev-parse --git-dir >/dev/null 2>&1
}

# Every git command aimed at a pinned checkout goes through here. Setting GIT_DIR and
# GIT_WORK_TREE explicitly turns repository discovery off, so a damaged or half-built
# .git fails loudly against $dir instead of quietly resolving to a parent repository.
repo_git() {
    local dir=$1
    shift
    GIT_DIR="$dir/.git" GIT_WORK_TREE="$dir" git "$@"
}

# Pinned checkouts
# ---------------------------------------------------------------------------
# Bring one checkout to one exact revision, idempotently. Fetches by hash with --depth 1,
# so what lands is the pinned commit and nothing else; `git rev-parse HEAD` afterwards is
# the revision itself, which is what phase4.py preflight compares against.
fetch_pinned() {
    local dir=$1 repository=$2 revision=$3 branch=$4 label=$5
    local actual=""

    is_own_repo "$dir" && actual=$(repo_git "$dir" rev-parse HEAD 2>/dev/null || true)

    if [[ $actual == "$revision" ]]; then
        info "$label at ${revision:0:12} (present)"
        return 0
    fi

    if [[ -n $actual ]]; then
        # Careful: never move a checkout with work in it. This directory is ours by
        # convention, but a reader may well have edited the PDK or support tools to debug
        # a run, and losing that silently to a bootstrap is not a tradeoff worth making.
        if [[ -n $(repo_git "$dir" status --porcelain 2>/dev/null) ]]; then
            die "$EX_MISMATCH" "$dir is at ${actual:0:12}, not ${revision:0:12}, and is dirty" \
                "Commit, stash or discard the changes there, then rerun." \
                "Nothing was changed."
        fi
    fi

    # Returns nonzero here so the caller can skip the checks that only make sense once
    # the checkout exists; two lines for one missing directory is noise, not detail.
    if [[ $check -eq 1 ]]; then
        if [[ -n $actual ]]; then
            gap "$label is at ${actual:0:12}, lockfile wants ${revision:0:12}"
        else
            gap "$label is not present at $dir"
        fi
        return 1
    fi

    [[ $offline -eq 0 ]] || die "$EX_NETWORK" \
        "$label is not at ${revision:0:12} and --offline was given"

    mkdir -p "$dir"

    # A .git that exists but is not a repository is the wreckage of an interrupted run,
    # and rerunning has to clear it rather than build on top of it. Discarding it is free:
    # $dir holds provisioned state, re-fetchable by definition, and this line is only
    # reached once the dirty check above found no work to lose.
    if [[ -d $dir/.git ]] && ! is_own_repo "$dir"; then
        warn "$dir/.git is not a valid repository (interrupted fetch?); reinitialising"
        rm -rf "$dir/.git"
    fi
    is_own_repo "$dir" || git init --quiet "$dir"
    is_own_repo "$dir" || die "$EX_MISMATCH" \
        "could not initialise a git repository at $dir" \
        "Remove $dir and rerun."

    repo_git "$dir" remote remove origin 2>/dev/null || true
    repo_git "$dir" remote add origin "$repository"

    net "fetching $label ${revision:0:12} from $repository"
    if ! repo_git "$dir" fetch --depth 1 --quiet origin "$revision"; then
        # Some servers refuse an unadvertised object. Falling back to the branch costs
        # history but still lands on the pinned commit, which is verified below either way.
        warn "fetch by hash refused; falling back to branch $branch"
        repo_git "$dir" fetch --quiet origin "$branch" || die "$EX_NETWORK" \
            "could not fetch $label from $repository"
    fi

    repo_git "$dir" checkout --quiet --detach "$revision" || die "$EX_NETWORK" \
        "$label fetched but revision ${revision:0:12} is not in it"

    actual=$(repo_git "$dir" rev-parse HEAD)
    [[ $actual == "$revision" ]] || die "$EX_MISMATCH" \
        "$label checked out $actual, lockfile wants $revision"
    info "$label at ${revision:0:12}"
}

fetch_support_tools() {
    step "Resolving tt-support-tools"
    if ! fetch_pinned "$tt_dir" "$support_tools_repository" "$support_tools_revision" \
        "$support_tools_branch" "tt-support-tools"; then
        return 0
    fi

    # The one file the emitted bundle actually points at; its hash is pinned in
    # lib/target.ml and re-checked by preflight, so a wrong revision is caught twice.
    local floorplan="$tt_dir/tech/$pdk_name/def/tt_block_6x4_pgvdd.def"
    if [[ -f $floorplan ]]; then
        info "floorplan present: tech/$pdk_name/def/tt_block_6x4_pgvdd.def"
    elif [[ $check -eq 1 ]]; then
        gap "floorplan not found at $floorplan"
    else
        die "$EX_MISMATCH" "floorplan not found at $floorplan" \
            "The revision is right but the layout is not what the bundle expects."
    fi
}

fetch_pdk() {
    step "Resolving the $pdk_name PDK"
    if ! fetch_pinned "$pdk_dir" "$pdk_repository" "$pdk_revision" "$pdk_branch" "PDK"; then
        return 0
    fi

    # PDK_ROOT is the clone root and the flow reads views from $PDK_ROOT/$PDK/..., the
    # same layout phase4.py resolves the manifest's technology references against.
    if [[ -d $pdk_dir/$pdk_name ]]; then
        info "PDK_ROOT $pdk_dir contains $pdk_name"
    elif [[ $check -eq 1 ]]; then
        gap "$pdk_dir has no $pdk_name directory"
    else
        die "$EX_MISMATCH" "$pdk_dir has no $pdk_name directory" \
            "PDK_ROOT must contain the process by name."
    fi
}

# ---------------------------------------------------------------------------
# Python environments
# ---------------------------------------------------------------------------
# The installed version of a package inside a venv, empty when it is not installed.
installed_version() {
    local python=$1 package=$2
    "$python" -m pip show "$package" 2>/dev/null | sed -n 's/^Version: //p'
}

install_flow_environment() {
    step "Preparing the LibreLane environment"

    local python="$venv_dir/bin/python"
    local have=""
    [[ -x $python ]] && have=$(installed_version "$python" librelane)

    if [[ $have == "$librelane_version" ]]; then
        info "librelane $have (present)"
        return 0
    fi

    if [[ $check -eq 1 ]]; then
        if [[ ! -x $python ]]; then
            gap "no Python environment at $venv_dir"
        else
            gap "librelane ${have:-absent}, lockfile wants $librelane_version"
        fi
        return 0
    fi

    [[ $offline -eq 0 ]] || die "$EX_NETWORK" \
        "librelane ${have:-is not installed} and --offline was given"

    if [[ ! -x $python ]]; then
        "$venv_python" -m venv "$venv_dir" || { rm -rf "$venv_dir"; \
            die "$EX_TOOL" "failed to create $venv_dir"; }
        info "created $venv_dir"
    fi

    net "installing librelane==$librelane_version"
    "$python" -m pip install --quiet --upgrade pip >/dev/null || die "$EX_NETWORK" \
        "could not upgrade pip inside $venv_dir"
    "$python" -m pip install --quiet "librelane==$librelane_version" || die "$EX_NETWORK" \
        "failed to install librelane==$librelane_version"

    have=$(installed_version "$python" librelane)
    [[ $have == "$librelane_version" ]] || die "$EX_MISMATCH" \
        "librelane resolved to $have, lockfile wants $librelane_version"
    info "librelane $have"
}

# Precheck cannot share the LibreLane environment: upstream's precheck/requirements.txt
# pins its own KLayout, and installing both into one venv resolves to a single version
# that satisfies neither. Two environments is upstream's arrangement, not a choice here.
install_precheck_environment() {
    step "Preparing the precheck environment"

    local requirements="$tt_dir/precheck/requirements.txt"
    local python="$precheck_venv_dir/bin/python"

    if [[ ! -f $requirements ]]; then
        # Only reachable when the support-tools checkout is absent, which is already a
        # recorded gap in --check mode; outside it, fetch_support_tools has run.
        if [[ $check -eq 1 ]]; then
            gap "precheck requirements not found (needs tt-support-tools)"
            return 0
        fi
        die "$EX_MISMATCH" "precheck requirements not found: $requirements"
    fi

    if [[ -x $python ]] && "$python" -c 'import klayout' >/dev/null 2>&1; then
        info "precheck environment present ($precheck_venv_dir)"
        return 0
    fi

    if [[ $check -eq 1 ]]; then
        gap "no precheck environment at $precheck_venv_dir"
        return 0
    fi

    [[ $offline -eq 0 ]] || die "$EX_NETWORK" \
        "no precheck environment and --offline was given"

    if [[ ! -x $python ]]; then
        "$venv_python" -m venv "$precheck_venv_dir" || { rm -rf "$precheck_venv_dir"; \
            die "$EX_TOOL" "failed to create $precheck_venv_dir"; }
        info "created $precheck_venv_dir"
    fi

    net "installing precheck requirements"
    "$python" -m pip install --quiet --upgrade pip >/dev/null || die "$EX_NETWORK" \
        "could not upgrade pip inside $precheck_venv_dir"
    "$python" -m pip install --quiet -r "$requirements" || die "$EX_NETWORK" \
        "failed to install $requirements"

    "$python" -c 'import klayout' >/dev/null 2>&1 || die "$EX_TOOL" \
        "klayout did not install into $precheck_venv_dir"
    info "precheck environment ready"
}

# Upstream's precheck also wants a pinned native KLayout and Magic from its default.nix,
# which pip cannot supply. Precheck is a later step than bootstrap, so this is reported
# and never fatal; scripts/flow.sh postcheck re-checks it.
#
# Probe the daemon rather than the binary. An installed nix-shell whose daemon socket the
# user cannot open fails every evaluation, and a distro Nix restricts that socket to a
# group it does not add anyone to, so "nix-shell is on PATH" says nothing about whether
# precheck can run. Finding that out here costs a subprocess; finding it out in postcheck
# costs the whole hardening run that precedes it.
check_precheck_nix() {
    step "Checking Nix for the TT precheck"

    if ! command -v nix-shell >/dev/null 2>&1; then
        warn "nix-shell not found; the TT precheck needs Nix for its pinned KLayout and Magic"
        return 0
    fi

    local probe
    if probe=$(nix-store --version 2>&1); then
        info "${probe%$'\n'*}"
        return 0
    fi

    warn "nix-shell is installed but Nix is not usable; the TT precheck will fail"
    info "  $probe"

    # The group-permission case is worth naming: the fix is one command, and the symptom
    # (a permission error on a socket the daemon is happily serving) reads like a broken
    # install rather than a missing group membership.
    local socket_group
    if [[ $probe == *daemon-socket* && $probe == *"Permission denied"* ]] \
        && socket_group=$(stat -c '%G' /nix/var/nix/daemon-socket 2>/dev/null); then
        info "  The daemon socket is group-restricted to '$socket_group'."
        local line
        while IFS= read -r line; do info "  $line"; done \
            < <(group_gap_advice "$socket_group" "" "systemctl status nix-daemon")
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Container image
# ---------------------------------------------------------------------------
pull_container_image() {
    [[ $no_container -eq 0 ]] || return 0
    step "Resolving the LibreLane image"

    if "$container" image inspect "$librelane_image" >/dev/null 2>&1; then
        info "$librelane_image (present)"
        return 0
    fi

    if [[ $check -eq 1 ]]; then
        gap "container image not pulled: $librelane_image"
        return 0
    fi

    [[ $offline -eq 0 ]] || die "$EX_NETWORK" \
        "$librelane_image is not pulled and --offline was given"

    net "pulling $librelane_image"
    "$container" pull "$librelane_image" || die "$EX_NETWORK" \
        "failed to pull $librelane_image"
    info "$librelane_image"
}

# ---------------------------------------------------------------------------
# Generated environment file
# ---------------------------------------------------------------------------
# Written for two readers: scripts/flow.sh, which sources it to learn where the toolchain
# went, and a person who wants to run librelane or python by hand. Assignments use
# ":${VAR:=...}" so anything already set in the caller's environment wins; flow.sh is
# built on overridable variables and sourcing this must not take that away.
write_env_file() {
    step "Writing $env_file"

    if [[ $check -eq 1 ]]; then
        [[ -f $env_file ]] || gap "no environment file at $env_file"
        return 0
    fi

    mkdir -p "$TOOLCHAIN"
    cat >"$env_file" <<ENVIRONMENT
# Generated by scripts/toolchain.sh from toolchain.lock. Do not edit.
#
# Source it to run the flow's tools by hand; scripts/flow.sh reads it automatically.
# Every assignment yields to a value already set in the environment.

: "\${ASIC_TOOLCHAIN:=$TOOLCHAIN}"
: "\${TT:=$tt_dir}"
: "\${PDK:=$pdk_dir}"
: "\${PDK_ROOT:=$pdk_dir}"
: "\${FLOW_PY:=$venv_dir/bin/python}"
: "\${PRECHECK_PY:=$precheck_venv_dir/bin/python}"

export ASIC_TOOLCHAIN TT PDK PDK_ROOT FLOW_PY PRECHECK_PY
ENVIRONMENT
    info "wrote $env_file"
}

# ---------------------------------------------------------------------------
read_lockfile
check_prerequisites
fetch_support_tools
fetch_pdk
install_flow_environment
install_precheck_environment
check_precheck_nix
pull_container_image
write_env_file

if [[ ${#problems[@]} -gt 0 ]]; then
    step "Summary"
    printf '    %d gap(s):\n' "${#problems[@]}"
    for problem in "${problems[@]}"; do printf '      - %s\n' "$problem"; done
    die "$EX_PREREQ" "the toolchain does not match toolchain.lock" \
        "Rerun without --check to converge it."
fi

step "Summary"
info "the toolchain matches toolchain.lock"
if [[ $warnings -gt 0 ]]; then
    info "$warnings warning(s) above; a later step can still fail on them"
fi
info "source $env_file, or just run scripts/flow.sh"
