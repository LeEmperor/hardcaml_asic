# Phase 4: TT/CMOS5L execution and results

The P3 bundle is immutable input. `scripts/phase4.py` is an external consumer:
it verifies the emitted file hashes and pinned target references, creates a
unique run directory for each attempt, executes LibreLane, and collects results
from either new or existing run directories. It does not install tools or change
`manifest.json`.

## Environment

Provision the revisions recorded by `manifest.json` explicitly. The reference
application's `tinytapeout/scripts/bootstrap-toolchain.sh` can prepare its
support-tools checkout, PDK, and LibreLane environment; use its output paths as
arguments below. The bundle itself has no sibling-checkout dependency. The
runner uses Dockerized LibreLane by default and needs an accessible Docker daemon.
It copies the pinned floorplan into its per-run staging directory so the
container can resolve `dir::../tt/...`. It reads PDK views from `PDK_ROOT`.

For an existing reference-application checkout, the setup is explicit:

```sh
REFERENCE_APP=/absolute/path/to/reference-application
"$REFERENCE_APP/tinytapeout/scripts/bootstrap-toolchain.sh"
"$REFERENCE_APP/tinytapeout/scripts/bootstrap-toolchain.sh" --check
docker pull ghcr.io/librelane/librelane:3.1.0.dev3
```

The second command is read-only; `scripts/phase4.py preflight` then checks the
particular emitted bundle and installed files. A clean setup need only fetch the
container image once. Preflight never fetches or installs it.

From this repository root, after emitting a bundle as in
[bundle emission](bundle-emission.md):

```sh
SUPPORT_TOOLS=/absolute/path/to/tt-support-tools
PDK_ROOT=/absolute/path/to/IHP-Open-PDK
FLOW_PYTHON=/absolute/path/to/librelane-venv/bin/python
BUNDLE=/absolute/path/to/emitted-bundle
RUNS=/absolute/path/to/run-storage

python3 scripts/phase4.py preflight "$BUNDLE" \
  --support-tools "$SUPPORT_TOOLS" --pdk-root "$PDK_ROOT" \
  --python "$FLOW_PYTHON"

python3 scripts/phase4.py run "$BUNDLE" \
  --support-tools "$SUPPORT_TOOLS" --pdk-root "$PDK_ROOT" \
  --python "$FLOW_PYTHON" --runs "$RUNS" --stage synthesis

python3 scripts/phase4.py collect "$RUNS/<printed-run-id>" \
  --output "$RUNS/<printed-run-id>/results.json"
```

Use `--stage full` for place and route and LibreLane physical checks. The
`--native` run option uses locally installed EDA executables, when their versions
and interfaces are compatible. Preflight rejects a Python minor-version mismatch
with the bundle's requested version; `--allow-python-mismatch` records the actual
version and permits an intentional compatibility run. It does not change the
requested version in the build manifest. A run prints its `run.json` path even
if it fails. Its `execution.log` and partial `project/runs/asic` contents remain
available, and retries receive distinct IDs.

After a completed full run, check TT's layout rules and simulate the final
gate-level netlist with the observable wrapper testbench:

```sh
python3 scripts/phase4.py postcheck "$RUNS/<printed-run-id>" \
  --support-tools "$SUPPORT_TOOLS" --pdk-root "$PDK_ROOT" \
  --precheck-python /absolute/path/to/precheck-venv/bin/python \
  --testbench test/tt_bundle_tb.v

python3 scripts/phase4.py collect "$RUNS/<printed-run-id>" \
  --output "$RUNS/<printed-run-id>/results.json"
```

Postcheck uses the pinned support-tools `precheck/default.nix` and a separate
Python environment with its KLayout dependency. The gate-level simulation runs
Icarus from the run's pinned LibreLane image, because the CMOS5L flop models
depend on `$setuphold` delayed nets that Icarus 12 leaves undriven. It compiles
the PDK I/O, UDP, and standard-cell models with the final `nl` netlist. It
records the GDS, netlist, and testbench hashes, simulator image and version,
command log, and both verdicts under `checks/<id>/`.

The bundle's LibreLane settings must include the TT template's physical
settings, supplied as reasoned overrides. Without `FP_PDN_MULTILAYER=0` and the
template's PDN and LEF-pin settings, LibreLane's defaults put the power grid on
`TopMetal1`, and TT precheck rejects the layout even though LibreLane's own DRC,
LVS, and antenna checks pass.

`run.json` records build identity, manifest hash, actual environment, command
arguments, requested/completed stage, status, timestamps, and output paths.
`results.json` separates process completion from timing goals and physical
checks. Synthesis area is mapped standard-cell area in µm², and the cell-type
inventory comes from Yosys `stat.json`. Setup and hold slack are in ns, reported
with the worst corner when available. Missing metrics have reasons. Raw reports
remain linked by paths relative to the run directory. The collector is a separate
command and also works on a failed or partially completed run.

## Evidence and remaining acceptance

The [phase plan](phase_plan.md#7-p4--execution-results-and-physical-integration)
tracks which P4 gates have actual run evidence. Mapped synthesis requires zero
unmapped instances and synthesis errors, a standard-cell mapping inventory, and
the memory bundle's explicit flop selection. A completed full LibreLane run alone
does not close P4.5: retain the TT precheck and gate-level wrapper check alongside
the physical reports before marking that gate complete.
