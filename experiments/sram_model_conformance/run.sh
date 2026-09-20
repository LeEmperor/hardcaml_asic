#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage: experiments/sram_model_conformance/run.sh [--pdk-root PATH] [--output-dir PATH]

Runs the bounded S.2a functional conformance test and timed-model diagnostics.
Defaults:
  --pdk-root   REPOSITORY/.toolchain/pdk
  --output-dir /tmp/hardcaml-asic-sram-model-conformance
EOF
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
pdk_root="$repo_root/.toolchain/pdk"
output_dir=/tmp/hardcaml-asic-sram-model-conformance

while [ "$#" -gt 0 ]; do
    case "$1" in
        --pdk-root)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            pdk_root=$2
            shift 2
            ;;
        --output-dir)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            output_dir=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

expected_pdk_revision=2bbec755dc67ca3db0261c3d6163e15735d66710
sram_dir="$pdk_root/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram"
macro="$sram_dir/verilog/RM_IHPSG13_1P_256x16_c2_bm_bist.v"
model="$sram_dir/verilog/RM_IHPSG13_1P_core_behavioral_bm_bist.v"
datasheet="$sram_dir/doc/RM_IHPSG13_1P_256x16_c2_bm_bist.txt"
lib_typ="$sram_dir/lib/RM_IHPSG13_1P_256x16_c2_bm_bist_typ_1p20V_25C.lib"
lib_fast="$sram_dir/lib/RM_IHPSG13_1P_256x16_c2_bm_bist_fast_1p32V_m55C.lib"
lib_slow="$sram_dir/lib/RM_IHPSG13_1P_256x16_c2_bm_bist_slow_1p08V_125C.lib"
wrapper="$script_dir/RM_IHPSG13_1P_256x16_portable_wrapper.v"
testbench="$script_dir/sram_model_conformance_tb.sv"
timing_probe="$script_dir/timing_support_tb.sv"
runner="$script_dir/run.sh"

for input in "$macro" "$model" "$datasheet" "$lib_typ" "$lib_fast" "$lib_slow" \
             "$wrapper" "$testbench" "$timing_probe" "$runner"; do
    [ -f "$input" ] || { echo "required input is absent: $input" >&2; exit 1; }
done
command -v iverilog >/dev/null || { echo "iverilog is required" >&2; exit 1; }
command -v vvp >/dev/null || { echo "vvp is required" >&2; exit 1; }
command -v timeout >/dev/null || { echo "timeout is required" >&2; exit 1; }

actual_pdk_revision=$(git -C "$pdk_root" rev-parse HEAD)
if [ "$actual_pdk_revision" != "$expected_pdk_revision" ]; then
    echo "PDK revision drift: expected $expected_pdk_revision, found $actual_pdk_revision" >&2
    exit 1
fi

check_hash() {
    expected=$1
    file=$2
    actual=$(sha256sum "$file" | cut -d' ' -f1)
    if [ "$actual" != "$expected" ]; then
        echo "model input drift: $file expected $expected, found $actual" >&2
        exit 1
    fi
}

check_hash 645c475787b077da4dbd15856c68bbae46aa9846a155239eb895ed2de7511053 "$macro"
check_hash d0a6258f8e9c93d1d5b1f78c0a1d66f30d28b1ad8037e5e07f53d1a4e3670b12 "$model"
check_hash 92b32189ff35af75e096e3faf8f85df9fe572f207d5f97405cc0ddf20ec2a609 "$datasheet"
check_hash 6f4cca1ed508f879a35bdc15a9de2d027f81ec0eeec0d6c8ab27d05f5edad445 "$lib_typ"
check_hash c28bb80737d7a7daea14b9d259380c7e1dfc27c71c3ad1223a5387d8515ebe4b "$lib_fast"
check_hash a04cff61cb4befb2290427db1ff2cb1c31c8d5990dca53ee3e5d1cc621679cd9 "$lib_slow"

mkdir -p "$output_dir"
rm -f "$output_dir"/*.vvp "$output_dir"/*.log "$output_dir"/*.sha256

log_command() {
    log=$1
    shift
    {
        printf 'working_directory=%q\n' "$repo_root"
        printf 'command='
        printf '%q ' "$@"
        printf '\n'
        "$@"
    } >"$log" 2>&1
}

{
    printf 'repository=%s\n' "$repo_root"
    printf 'pdk_root=%s\n' "$pdk_root"
    printf 'pdk_revision=%s\n' "$actual_pdk_revision"
    printf 'pdk_status_begin\n'
    git -C "$pdk_root" status --short
    printf 'pdk_status_end\n'
    printf 'iverilog_path=%s\n' "$(command -v iverilog)"
    iverilog -V
    printf 'vvp_path=%s\n' "$(command -v vvp)"
    vvp -V
} >"$output_dir/environment.log" 2>&1

sha256sum "$macro" "$model" "$datasheet" "$lib_typ" "$lib_fast" "$lib_slow" \
    "$wrapper" "$testbench" "$timing_probe" "$runner" >"$output_dir/inputs.sha256"

common=(-g2012 -Wall -s sram_model_conformance_tb -o)
sources=("$model" "$macro" "$wrapper" "$testbench")

log_command "$output_dir/functional-compile.log" \
    iverilog "${common[@]}" "$output_dir/functional.vvp" -DFUNCTIONAL "${sources[@]}"
log_command "$output_dir/functional-run.log" \
    timeout 30s vvp "$output_dir/functional.vvp"

log_command "$output_dir/failure-sanity-compile.log" \
    iverilog "${common[@]}" "$output_dir/failure-sanity.vvp" \
    -DFUNCTIONAL -DINJECT_FAILURE "${sources[@]}"
set +e
log_command "$output_dir/failure-sanity-run.log" \
    timeout 30s vvp "$output_dir/failure-sanity.vvp"
failure_status=$?
set -e
if [ "$failure_status" -eq 0 ]; then
    echo "failure-path sanity test unexpectedly returned success" >&2
    exit 1
fi

set +e
log_command "$output_dir/timed-default-compile.log" \
    iverilog "${common[@]}" "$output_dir/timed-default.vvp" -DTIMED_MODEL "${sources[@]}"
timed_default_compile=$?
if [ "$timed_default_compile" -eq 0 ]; then
    log_command "$output_dir/timed-default-run.log" \
        timeout 30s vvp "$output_dir/timed-default.vvp"
    timed_default_run=$?
else
    timed_default_run=not-run
fi

log_command "$output_dir/timed-specify-compile.log" \
    iverilog -gspecify "${common[@]}" "$output_dir/timed-specify.vvp" \
    -DTIMED_MODEL "${sources[@]}"
timed_specify_compile=$?
if [ "$timed_specify_compile" -eq 0 ]; then
    log_command "$output_dir/timed-specify-run.log" \
        timeout 30s vvp "$output_dir/timed-specify.vvp"
    timed_specify_run=$?
else
    timed_specify_run=not-run
fi

log_command "$output_dir/timing-probe-default-compile.log" \
    iverilog -g2012 -Wall -s timing_support_tb \
    -o "$output_dir/timing-probe-default.vvp" "$timing_probe"
timing_probe_default_compile=$?
if [ "$timing_probe_default_compile" -eq 0 ]; then
    log_command "$output_dir/timing-probe-default-run.log" \
        timeout 30s vvp "$output_dir/timing-probe-default.vvp"
    timing_probe_default_run=$?
else
    timing_probe_default_run=not-run
fi

log_command "$output_dir/timing-probe-specify-compile.log" \
    iverilog -g2012 -gspecify -Wall -s timing_support_tb \
    -o "$output_dir/timing-probe-specify.vvp" "$timing_probe"
timing_probe_specify_compile=$?
if [ "$timing_probe_specify_compile" -eq 0 ]; then
    log_command "$output_dir/timing-probe-specify-run.log" \
        timeout 30s vvp "$output_dir/timing-probe-specify.vvp"
    timing_probe_specify_run=$?
else
    timing_probe_specify_run=not-run
fi
set -e

{
    printf 'functional_compile=0\n'
    printf 'functional_run=0\n'
    printf 'failure_sanity_run=%s (expected nonzero)\n' "$failure_status"
    printf 'timed_default_compile=%s\n' "$timed_default_compile"
    printf 'timed_default_run=%s\n' "$timed_default_run"
    printf 'timed_specify_compile=%s\n' "$timed_specify_compile"
    printf 'timed_specify_run=%s\n' "$timed_specify_run"
    printf 'timing_probe_default_compile=%s\n' "$timing_probe_default_compile"
    printf 'timing_probe_default_run=%s\n' "$timing_probe_default_run"
    printf 'timing_probe_specify_compile=%s\n' "$timing_probe_specify_compile"
    printf 'timing_probe_specify_run=%s\n' "$timing_probe_specify_run"
} >"$output_dir/outcomes.log"

rm -f "$output_dir"/*.vvp
echo "functional conformance passed; complete evidence is in $output_dir"
