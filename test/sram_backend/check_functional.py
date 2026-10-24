#!/usr/bin/env python3
"""Replay generated production RTL against the stock vendor functional model.

Explicit opt-in: --fixture BUILT_EXE --pdk-dir CMOS5L_DIR. No Dune, provisioning,
EDA flow or installed-PDK mutation. All outputs live in a temporary directory.
"""

import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def run(argv, *, success=True):
    result = subprocess.run(argv, text=True, capture_output=True, timeout=60)
    if success != (result.returncode == 0):
        raise RuntimeError(f"unexpected status {result.returncode}: {argv}\n"
                           f"{result.stdout}\n{result.stderr}")
    return result.stdout + result.stderr


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--pdk-dir", type=Path, required=True)
    args = parser.parse_args()
    fixture = args.fixture.resolve(strict=True)
    models = args.pdk_dir.resolve(strict=True) / "libs.ref/sg13cmos5l_sram/verilog"
    sources = [models / "RM_IHPSG13_1P_256x16_c2_bm_bist.v",
               models / "RM_IHPSG13_1P_core_behavioral_bm_bist.v"]
    for source in sources:
        if not source.is_file():
            raise RuntimeError(f"missing exact vendor source: {source}")
    for tool in ("iverilog", "vvp"):
        if not shutil.which(tool):
            raise RuntimeError(f"required functional simulator tool missing: {tool}")
    tb = Path(__file__).resolve().with_name("contract_tb.sv")
    with tempfile.TemporaryDirectory(prefix="asic-sram-functional-") as tmp:
        root = Path(tmp)
        for mode in ("behavioral", "flops", "macro"):
            rtl = root / f"{mode}.v"
            run([str(fixture), "--rtl", mode, str(rtl)])
            for negative in (False, True):
                executable = root / f"{mode}-{negative}.vvp"
                argv = ["iverilog", "-g2012", "-s", "contract_tb", "-o", str(executable)]
                if negative:
                    argv += ["-DINJECT_FAILURE"]
                if mode == "macro":
                    argv += ["-DFUNCTIONAL", "-DCHECK_MACRO"] + [str(p) for p in sources]
                run(argv + [str(rtl), str(tb)])
                output = run(["vvp", str(executable)], success=not negative)
                marker = "read/latency failed" if negative else "PASS contract:"
                if marker not in output:
                    raise RuntimeError(f"missing expected oracle {marker}: {output}")
                print(f"{mode} {'negative oracle' if negative else 'functional'}: {output.strip()}")


if __name__ == "__main__":
    main()
