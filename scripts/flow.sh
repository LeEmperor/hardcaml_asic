#!/usr/bin/env bash
# This repository's development driver for one example bundle.
#
# It owns exactly two things: building and emitting the example this checkout
# maintains, and choosing which example, testbench and paths a development
# invocation uses. Everything after emission -- preflight, run, postcheck,
# collect, report, archive and the fixed execute sequence -- is the installed
# `hardcaml-asic-flow` command's, reached here through scripts/flow_cli.py so a
# checkout and a prefix run one implementation. There is no sequencing,
# acceptance, run-selection or archive policy in this file. See docs/flow.md.
#
# Usage:
#   scripts/flow.sh                       # this help; nothing is built or run
#   scripts/flow.sh --help
#   scripts/flow.sh COMMAND [ARGUMENT ...]
#
# One command per invocation. Arguments after it are passed to the shared CLI,
# so any option it accepts works here.
#
#   build                      dune build && dune runtest
#   emit                       dune exec the $KIND example into $BUNDLE
#   preflight                  validate $BUNDLE against the provisioned toolchain
#   run                        one attempt under $RUNS; prints its run identity
#   postcheck                  TT precheck and gate-level simulation of $RUN
#   collect                    $RUN/results.json
#   report                     the human summary of $RUN, or --json
#   archive                    package $RUN; needs --output DIR or --list
#   execute                    the CLI's fixed run -> postcheck -> collect ->
#                              report [-> archive] sequence for $BUNDLE
#
# The expensive commands are the ones you name: no argument prints this help,
# and `run`/`execute` start nothing until STAGE says how far to go.
#
# A typical development pass, each line its own invocation:
#   scripts/flow.sh build
#   OUT=/tmp/p4-observable scripts/flow.sh emit
#   OUT=/tmp/p4-observable STAGE=synthesis scripts/flow.sh execute
#
# Resuming, with the run directory the earlier command printed:
#   OUT=... RUN=$OUT/runs/<id> scripts/flow.sh report
#
# Environment, all optional except where noted:
#   KIND         observable | memory, the example to emit        (observable)
#   STAGE        synthesis | full; required by run and execute
#   OUT          holds one bundle and its runs                   (.../p4-$KIND)
#   BUNDLE       the emitted bundle                              ($OUT/bundle)
#   RUNS         run storage, one directory per attempt          ($OUT/runs)
#   RUN          required by postcheck, collect, report, archive
#   TOOLCHAIN    what ./bootstrap.sh provisioned                 (.toolchain)
#   TT           tt-support-tools checkout                       ($TOOLCHAIN/tt)
#   PDK          PDK root (IHP sg13cmos5l)                       ($TOOLCHAIN/pdk)
#   FLOW_PY      python of the LibreLane venv         ($TOOLCHAIN/.venv/bin/python)
#   PRECHECK_PY  python of the TT precheck venv       ($TOOLCHAIN/.venv-precheck/...)
#   TESTBENCH    gate-level wrapper testbench         (test/tt_bundle_tb.v)
#   TESTBENCH_TOP simulator top for that testbench    (tb_observable)
#
# Careful: "emit" refuses to write into a $BUNDLE directory that has any entry
# (Bundle.write, lib/bundle.ml), so a second emission into the same $OUT fails
# there. Use a new $OUT, or "rm -rf $BUNDLE" first. Run directories are fine:
# each attempt gets its own id under $RUNS.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
repo_root=$(pwd)

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() { echo "flow: $1" >&2; exit "${2:-2}"; }

KIND=${KIND:-observable}

# Installed collateral. ./bootstrap.sh provisions all of it under $TOOLCHAIN and writes
# toolchain-env.sh there; sourcing that is how this script learns where it went, so the
# two stay in step when the toolchain moves. Every assignment inside it yields to a value
# already in the environment, so "TT=... scripts/flow.sh" still wins over the generated
# file, and the fallbacks below cover a toolchain that was never bootstrapped.
#
# Absolute paths throughout: the flow command resolves relative paths against the
# caller's working directory, and a run directory is not this one.
TOOLCHAIN=${TOOLCHAIN:-$repo_root/.toolchain}
if [ -f "$TOOLCHAIN/toolchain-env.sh" ]; then
  . "$TOOLCHAIN/toolchain-env.sh"
fi

TT=${TT:-$TOOLCHAIN/tt}
PDK=${PDK:-$TOOLCHAIN/pdk}
FLOW_PY=${FLOW_PY:-$TOOLCHAIN/.venv/bin/python}
PRECHECK_PY=${PRECHECK_PY:-$TOOLCHAIN/.venv-precheck/bin/python}

OUT=${OUT:-/home/wayne/devel/jane/p4-$KIND}
BUNDLE=${BUNDLE:-$OUT/bundle}
RUNS=${RUNS:-$OUT/runs}
TESTBENCH=${TESTBENCH:-$repo_root/test/tt_bundle_tb.v}
# This default belongs to this repository's example adapter. The shared command
# requires both the testbench path and the simulator top, and has no default for
# either: a development bench is not a contract.
TESTBENCH_TOP=${TESTBENCH_TOP:-tb_observable}
RUN=${RUN:-}
STAGE=${STAGE:-}

commands="build emit preflight run postcheck collect report archive execute"

# Removed spellings get one explicit line naming what replaced them, rather than
# a compatibility alias that quietly keeps the old behaviour alive. Remove these
# after one documented migration window (docs/flow.md).
if [ -n "${ALLOW_PYTHON_MISMATCH:-}" ]; then
  echo "flow: ALLOW_PYTHON_MISMATCH is gone; a run no longer waives the bundle's" >&2
  echo "flow: requested Python by default. Provision the requested interpreter" >&2
  echo "flow: (./bootstrap.sh), or wait for the recorded --waiver python-version=REASON" >&2
  echo "flow: that P6.5 delivers. Unset it to continue." >&2
  exit 2
fi

for argument in "$@"; do
  case "$argument" in
    -h|--help) usage; exit 0 ;;
  esac
done

[ $# -gt 0 ] || { usage; exit 0; }

command=$1
shift

case " $commands " in
  *" $command "*) ;;
  *) die "unknown command: $command (try --help)" ;;
esac

# The old form took a list of steps and ran them in order. Sequencing is the
# shared command's now: "execute" is the fixed one, and anything else is one
# invocation per operation.
for argument in "$@"; do
  case " $commands " in
    *" $argument "*)
      die "one command per invocation; '$command $argument' was a step list. Use scripts/flow.sh execute for the fixed sequence, or one invocation per operation" ;;
  esac
done

# The shared dispatcher, through the checkout's adapter: same parser, same
# operations and same exit statuses as the installed hardcaml-asic-flow.
flow=(python3 "$repo_root/scripts/flow_cli.py")

tools=(--support-tools "$TT" --pdk-root "$PDK")

need_toolchain() {
  [ -d "$TT" ] && [ -d "$PDK" ] && [ -x "$FLOW_PY" ] && return 0
  echo "flow: toolchain not provisioned under $TOOLCHAIN; run ./bootstrap.sh" >&2
  echo "flow: (or ./bootstrap.sh --check to see which parts are missing)" >&2
  return 2
}

# A resumed operation names its run. The newest directory under $RUNS is not it:
# run ids are random hex, two attempts can overlap, and attaching evidence to the
# wrong attempt is worse than an error message.
need_run() {
  [ -n "$RUN" ] || die "set RUN=<run directory> for $command; the newest run under $RUNS is never guessed. 'run' and 'execute' print run_dir in their JSON"
  [ -f "$RUN/run.json" ] || die "not a run directory (no run.json): $RUN"
}

need_stage() {
  case "$STAGE" in
    synthesis|full) ;;
    "") die "set STAGE=synthesis or STAGE=full for $command; there is no default stage" ;;
    *) die "STAGE must be synthesis or full, not '$STAGE'" ;;
  esac
}

case "$command" in
  build)
    dune build
    dune runtest
    ;;

  emit)
    # Bundle.write refuses a nonempty directory; say so here rather than letting
    # the example fail with its own message.
    if [ -d "$BUNDLE" ] && [ -n "$(ls -A "$BUNDLE" 2>/dev/null)" ]; then
      die "$BUNDLE already has files; use a new OUT or: rm -rf $BUNDLE"
    fi
    mkdir -p "$OUT"
    dune exec "examples/tt_bundle_example.exe" -- "$KIND" "$BUNDLE"
    cat "$BUNDLE/constraints/top.sdc"
    ;;

  preflight)
    need_toolchain
    exec "${flow[@]}" preflight "$BUNDLE" "${tools[@]}" --python "$FLOW_PY" "$@"
    ;;

  run)
    need_toolchain
    need_stage
    exec "${flow[@]}" run "$BUNDLE" --runs "$RUNS" --stage "$STAGE" \
      "${tools[@]}" --python "$FLOW_PY" "$@"
    ;;

  postcheck)
    need_toolchain
    need_run
    exec "${flow[@]}" postcheck "$RUN" "${tools[@]}" \
      --precheck-python "$PRECHECK_PY" \
      --testbench "$TESTBENCH" --testbench-top "$TESTBENCH_TOP" "$@"
    ;;

  collect|report)
    need_run
    exec "${flow[@]}" "$command" "$RUN" "$@"
    ;;

  archive)
    need_run
    # No destination is supplied here on purpose: an archive goes where the
    # caller says, and --force is theirs to spell out.
    exec "${flow[@]}" archive "$RUN" "$@"
    ;;

  execute)
    need_toolchain
    need_stage
    arguments=(execute "$BUNDLE" --runs "$RUNS" --stage "$STAGE"
               "${tools[@]}" --python "$FLOW_PY")
    if [ "$STAGE" = full ]; then
      arguments+=(--precheck-python "$PRECHECK_PY"
                  --testbench "$TESTBENCH" --testbench-top "$TESTBENCH_TOP")
    fi
    exec "${flow[@]}" "${arguments[@]}" "$@"
    ;;
esac
