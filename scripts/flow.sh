#!/usr/bin/env bash
# End-to-end TT/LibreLane flow for one example bundle: emit, preflight, run,
# postcheck, collect, report. Wraps scripts/phase4.py, which stays the interface;
# scripts/report.py prints the summary. See docs/phase4-execution.md.
#
# Usage:
#   scripts/flow.sh [step ...]          # no step means all of them, in order
#   scripts/flow.sh --help
#
# Typical use, with a fresh output directory per bundle:
#   OUT=/home/wayne/devel/jane/p4-observable-minmax scripts/flow.sh
#   OUT=... scripts/flow.sh postcheck collect report   # pick up after a finished run
#   export OUT=...; scripts/flow.sh                    # or set it once for the shell
#
# Steps, in order, all of them when none is named:
#   build      dune build && dune runtest
#   emit       dune exec the example into $BUNDLE
#   preflight  phase4.py preflight, read-only
#   run        phase4.py run --stage $STAGE (the long one), sets $RUN
#   postcheck  phase4.py postcheck: TT precheck + gate-level simulation
#   collect    phase4.py collect into $RUN/results.json
#   report     scripts/report.py, the human summary; nonzero exit on any problem
#
# Environment, all optional; the defaults are the reference setup:
#   KIND         observable | memory, the example to emit        (observable)
#   STAGE        synthesis | full, how far the flow runs         (full)
#   OUT          holds one bundle and its runs                   (.../p4-$KIND)
#   BUNDLE       the emitted bundle                              ($OUT/bundle)
#   RUNS         run storage, one directory per attempt          ($OUT/runs)
#   TOOLCHAIN    what ./bootstrap.sh provisioned                   (.toolchain)
#   TT           tt-support-tools checkout            ($TOOLCHAIN/tt)
#   PDK          PDK root (IHP sg13cmos5l)            ($TOOLCHAIN/pdk)
#   FLOW_PY      python of the LibreLane venv         ($TOOLCHAIN/.venv/bin/python)
#   PRECHECK_PY  python of the TT precheck venv       ($TOOLCHAIN/.venv-precheck/...)
#   TESTBENCH    gate-level wrapper testbench   (test/tt_bundle_tb.v)
#   RUN          an existing run directory for steps after "run"
#   ALLOW_PYTHON_MISMATCH  0 to require the bundle's exact Python minor version (1)
#
# Careful: "emit" refuses to write into a $BUNDLE directory that has any entry
# (Bundle.write, lib/bundle.ml), so a second full run into the same $OUT fails
# there. Use a new $OUT, or "rm -rf $BUNDLE" first. Run directories are fine:
# each attempt gets its own id under $RUNS.
#
# A step after "run" needs a run directory. It reuses the one this invocation
# produced, else $RUN from the environment, else the newest under $RUNS. The run
# directory always comes from the run.json path phase4.py prints, never from
# "ls | tail -1": run ids are random hex, so they do not sort by time.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
repo_root=$(pwd)

KIND=${KIND:-observable}
STAGE=${STAGE:-full}

# Installed collateral. ./bootstrap.sh provisions all of it under $TOOLCHAIN and writes
# toolchain-env.sh there; sourcing that is how this script learns where it went, so the
# two stay in step when the toolchain moves. Every assignment inside it yields to a value
# already in the environment, so "TT=... scripts/flow.sh" still wins over the generated
# file, and the fallbacks below cover a toolchain that was never bootstrapped.
#
# Absolute paths throughout: phase4.py resolves some of these against its own working
# directory, and a run directory is not this one.
TOOLCHAIN=${TOOLCHAIN:-$repo_root/.toolchain}
if [ -f "$TOOLCHAIN/toolchain-env.sh" ]; then
  . "$TOOLCHAIN/toolchain-env.sh"
fi

TT=${TT:-$TOOLCHAIN/tt}
PDK=${PDK:-$TOOLCHAIN/pdk}
FLOW_PY=${FLOW_PY:-$TOOLCHAIN/.venv/bin/python}
PRECHECK_PY=${PRECHECK_PY:-$TOOLCHAIN/.venv-precheck/bin/python}

# Where this invocation writes; OUT holds one bundle and its runs.
OUT=${OUT:-/home/wayne/devel/jane/p4-$KIND}
BUNDLE=${BUNDLE:-$OUT/bundle}
RUNS=${RUNS:-$OUT/runs}
TESTBENCH=${TESTBENCH:-test/tt_bundle_tb.v}

# --allow-python-mismatch by default: the bundle requests 3.11 and the venv is
# 3.12, an intentional compatibility run. ALLOW_PYTHON_MISMATCH=0 turns it off.
mismatch=()
[ "${ALLOW_PYTHON_MISMATCH:-1}" = 1 ] && mismatch=(--allow-python-mismatch)

RUN=${RUN:-}

say() { printf '\n== %s\n' "$1" >&2; }

# The newest run under $RUNS, by modification time
latest_run() {
  local newest
  newest=$(ls -td "$RUNS"/*/ 2>/dev/null | head -1 || true)
  [ -n "$newest" ] || { echo "flow: no run found under $RUNS" >&2; return 1; }
  printf '%s' "${newest%/}"
}

need_run() {
  [ -n "$RUN" ] || RUN=$(latest_run)
  echo "flow: run directory $RUN" >&2
}

# Everything from "preflight" on needs the provisioned toolchain. phase4.py reports a
# missing checkout perfectly well, but it reports it as a bad argument; when the whole
# toolchain is absent the answer is one command, so say that instead.
need_toolchain() {
  [ -d "$TT" ] && [ -d "$PDK" ] && [ -x "$FLOW_PY" ] && return 0
  echo "flow: toolchain not provisioned under $TOOLCHAIN; run ./bootstrap.sh" >&2
  echo "flow: (or ./bootstrap.sh --check to see which parts are missing)" >&2
  return 2
}

step_build() {
  say "build and tests"
  dune build
  dune runtest
}

step_emit() {
  say "emit bundle into $BUNDLE"
  # Bundle.write refuses a nonempty directory; say so here rather than letting the
  # example fail with its own message halfway down a seven-step run.
  if [ -d "$BUNDLE" ] && [ -n "$(ls -A "$BUNDLE" 2>/dev/null)" ]; then
    echo "flow: $BUNDLE already has files; use a new OUT or: rm -rf $BUNDLE" >&2
    return 2
  fi
  mkdir -p "$OUT"
  dune exec "examples/tt_bundle_example.exe" -- "$KIND" "$BUNDLE"
  cat "$BUNDLE/constraints/top.sdc"
}

step_preflight() {
  need_toolchain
  say "preflight"
  python3 scripts/phase4.py preflight "$BUNDLE" \
    --support-tools "$TT" --pdk-root "$PDK" --python "$FLOW_PY" "${mismatch[@]}"
}

step_run() {
  need_toolchain
  say "run --stage $STAGE (long)"
  local record
  # phase4.py prints the run.json path as its last stdout line, even on failure;
  # tee keeps the live output on the terminal while capturing it.
  record=$(python3 scripts/phase4.py run "$BUNDLE" \
    --support-tools "$TT" --pdk-root "$PDK" --python "$FLOW_PY" "${mismatch[@]}" \
    --runs "$RUNS" --stage "$STAGE" | tee /dev/stderr | tail -1)
  [ -f "$record" ] || { echo "flow: no run.json printed" >&2; return 1; }
  RUN=$(dirname "$record")
  echo "flow: run directory $RUN" >&2
}

step_postcheck() {
  need_toolchain
  need_run
  say "postcheck: TT precheck and gate-level simulation"
  python3 scripts/phase4.py postcheck "$RUN" \
    --support-tools "$TT" --pdk-root "$PDK" \
    --precheck-python "$PRECHECK_PY" --testbench "$TESTBENCH"
}

step_collect() {
  need_run
  say "collect"
  python3 scripts/phase4.py collect "$RUN" --output "$RUN/results.json"
}

step_report() {
  need_run
  say "report"
  python3 scripts/report.py "$RUN"
}

# --help prints this file's header comment, so the usage text has one home
for argument in "$@"; do
  case "$argument" in
    -h|--help)
      sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done

steps=("$@")
[ ${#steps[@]} -gt 0 ] || steps=(build emit preflight run postcheck collect report)

for step in "${steps[@]}"; do
  case "$step" in
    build|emit|preflight|run|postcheck|collect|report) "step_$step" ;;
    *) echo "flow: unknown step: $step (try --help)" >&2; exit 2 ;;
  esac
done
