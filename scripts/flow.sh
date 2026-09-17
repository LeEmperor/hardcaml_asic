#!/usr/bin/env bash
# End-to-end TT/LibreLane flow for one example bundle: emit, preflight, run,
# postcheck, collect, report.
#
# Every path is an environment variable with a default, so a plain
# "scripts/flow.sh" reproduces the reference setup and
# "OUT=/tmp/try KIND=memory scripts/flow.sh" runs a different one. The run
# directory is taken from the run.json path phase4.py prints, never from
# "ls | tail -1": run ids are random hex, so they do not sort by time.
#
# Usage:
#   scripts/flow.sh [step ...]
#
# Steps, in order, all of them when none is named:
#   build      dune build && dune runtest
#   emit       dune exec the example into $BUNDLE (must not exist yet)
#   preflight  phase4.py preflight, read-only
#   run        phase4.py run --stage $STAGE (the long one), sets $RUN
#   postcheck  phase4.py postcheck: TT precheck + gate-level sim
#   collect    phase4.py collect into $RUN/results.json
#   report     scripts/report.py, the human summary
#
# A step after "run" needs a run directory. It reuses the one this invocation
# produced, else $RUN from the environment, else the newest under $RUNS.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

KIND=${KIND:-observable}
STAGE=${STAGE:-full}

# Installed collateral; see docs/phase4-execution.md.
TT=${TT:-/home/wayne/devel/jane/tt-support-tools-cmos5l}
PDK=${PDK:-/home/wayne/devel/jane/scaf/tinytapeout/pdk}
FLOW_PY=${FLOW_PY:-/home/wayne/devel/jane/scaf/.venv/bin/python}
PRECHECK_PY=${PRECHECK_PY:-/home/wayne/devel/jane/scaf/.venv-precheck/bin/python}

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

step_build() {
  say "build and tests"
  dune build
  dune runtest
}

step_emit() {
  say "emit bundle into $BUNDLE"
  mkdir -p "$OUT"
  dune exec "examples/tt_bundle_example.exe" -- "$KIND" "$BUNDLE"
  cat "$BUNDLE/constraints/top.sdc"
}

step_preflight() {
  say "preflight"
  python3 scripts/phase4.py preflight "$BUNDLE" \
    --support-tools "$TT" --pdk-root "$PDK" --python "$FLOW_PY" "${mismatch[@]}"
}

step_run() {
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

steps=("$@")
[ ${#steps[@]} -gt 0 ] || steps=(build emit preflight run postcheck collect report)

for step in "${steps[@]}"; do
  case "$step" in
    build|emit|preflight|run|postcheck|collect|report) "step_$step" ;;
    *) echo "flow: unknown step: $step" >&2; exit 2 ;;
  esac
done
