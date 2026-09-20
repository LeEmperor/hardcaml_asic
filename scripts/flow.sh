#!/usr/bin/env bash
# End-to-end TT/LibreLane flow for one example bundle: emit, preflight, run,
# postcheck, collect, report. Wraps scripts/phase4.py, which stays the interface;
# scripts/report.py prints the summary. See docs/flow.md.
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
# Whatever the steps do, the last thing printed is a summary: how long each step
# took, the end-to-end wall time, and the absolute path of every record and log
# the invocation produced. It prints on failure too, so an interrupted run still
# says where its diagnostics are.
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

# Wall time. SECONDS counts from the start of this shell, which is the start of
# the flow, so step durations and the end-to-end number come from one source.
step_names=()
step_seconds=()

# 1h 02m 03s / 23m 47s / 12s: the leading unit is dropped until it is nonzero,
# because a seven-hour hardening run and a one-second collect share this column.
format_duration() {
  local total=$1
  if [ "$total" -ge 3600 ]; then
    printf '%dh %02dm %02ds' $((total / 3600)) $((total % 3600 / 60)) $((total % 60))
  elif [ "$total" -ge 60 ]; then
    printf '%dm %02ds' $((total / 60)) $((total % 60))
  else
    printf '%ds' "$total"
  fi
}

# Every step goes through here, so the summary has a row even for the step that
# failed: its duration is how long it ran before giving up.
run_step() {
  local step=$1 started=$SECONDS status=0
  step_names+=("$step")
  step_seconds+=(-1)
  "step_$step" || status=$?
  step_seconds[${#step_seconds[@]} - 1]=$((SECONDS - started))
  return $status
}

# One line of the summary's path list, skipped when the file is not there: a
# failed run has no results.json, and naming a path that does not exist reads as
# an instruction to go look at it.
summary_path() {
  [ -e "$2" ] || return 0
  printf '  %-16s %s\n' "$1" "$2" >&2
}

# Printed from an EXIT trap, so it is genuinely the last output whether the flow
# finished, failed a step, or was interrupted.
summary() {
  local status=$?
  [ ${#step_names[@]} -gt 0 ] || return $status

  say "summary"
  local index
  for index in "${!step_names[@]}"; do
    if [ "${step_seconds[index]}" -lt 0 ]; then
      printf '  %-28s %s\n' "${step_names[index]}" 'did not finish' >&2
    else
      printf '  %-28s %10s\n' "${step_names[index]}" \
        "$(format_duration "${step_seconds[index]}")" >&2
    fi
  done
  printf '  %-28s %10s\n' 'end to end' "$(format_duration $SECONDS)" >&2

  printf '\n' >&2
  summary_path bundle "$BUNDLE"
  summary_path preflight "$OUT/preflight.json"
  if [ -n "$RUN" ]; then
    summary_path run "$RUN"
    summary_path 'run record' "$RUN/run.json"
    summary_path 'execution log' "$RUN/execution.log"
    summary_path results "$RUN/results.json"
    summary_path 'flow outputs' "$RUN/project/runs/asic"
    local check
    for check in "$RUN"/checks/*/; do
      summary_path 'postcheck' "${check}postcheck.json"
      summary_path 'postcheck log' "${check}postcheck.log"
      summary_path 'precheck reports' "${check}tt/precheck/reports/results.md"
    done
  fi

  printf '\n  %s\n' "exit status $status" >&2
  return $status
}

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
  # --output as well as stdout: the preflight report is the record of why this
  # run was allowed to start, and it is the P4 evidence shape (every external
  # hash, the actual tool versions, and any recorded version waivers). Seven
  # steps of scrollback is not a place to keep it.
  mkdir -p "$OUT"
  python3 scripts/phase4.py preflight "$BUNDLE" \
    --support-tools "$TT" --pdk-root "$PDK" --python "$FLOW_PY" "${mismatch[@]}" \
    --output "$OUT/preflight.json"
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
  # phase4.py owns the run directory's own records; this is the one thing it
  # cannot write, because preflight ran before the directory existed. Copying it
  # in makes the attempt self-contained, which is what gets archived as evidence.
  [ -f "$OUT/preflight.json" ] && cp "$OUT/preflight.json" "$RUN/preflight.json"
  return 0
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

# Validate the whole list before running anything: a typo in the last step is
# worth catching before, not after, a hardening run.
for step in "${steps[@]}"; do
  case "$step" in
    build|emit|preflight|run|postcheck|collect|report) ;;
    *) echo "flow: unknown step: $step (try --help)" >&2; exit 2 ;;
  esac
done

trap summary EXIT

for step in "${steps[@]}"; do
  run_step "$step"
done
