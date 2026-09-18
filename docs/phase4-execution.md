# Phase 4: TT/CMOS5L execution and results

The P3 bundle is immutable input. `scripts/phase4.py` is an external consumer:
it verifies the emitted file hashes and pinned target references, creates a
unique run directory for each attempt, executes LibreLane, and collects results
from either new or existing run directories. It does not install tools or change
`manifest.json`.

## Running it

`scripts/flow.sh` runs the whole sequence with the reference paths already
filled in, and `scripts/report.py` summarizes a finished run. Both take the
place of assembling the `phase4.py` command lines by hand:

```sh
scripts/flow.sh                      # build, emit, preflight, run, postcheck, collect, report
scripts/flow.sh report               # just the summary, on the newest run under $RUNS
OUT=/tmp/try KIND=memory scripts/flow.sh
scripts/report.py "$RUN"             # a specific run directory
scripts/report.py --runs "$RUNS"     # the newest run under a run store
```

Every path is an overridable environment variable (`TOOLCHAIN`, `TT`, `PDK`,
`FLOW_PY`, `PRECHECK_PY`, `OUT`, `BUNDLE`, `RUNS`, `KIND`, `STAGE`, `TESTBENCH`).
The defaults come from `.toolchain/toolchain-env.sh`, which `./bootstrap.sh`
writes and `flow.sh` sources; anything already set in the environment wins over
it, so `TT=... scripts/flow.sh` still points the run at another checkout.
`flow.sh` takes the run directory from
the `run.json` path `phase4.py` prints, since run ids are random hex and do not
sort by time. `report.py` prints timing per corner, signoff checks, the TT
precheck rows, and what the post-CTS resizer did about hold; it exits nonzero
when a check fails, when a run did not complete, or when a timing mode was left
unconstrained. The `phase4.py` subcommands below remain the interface; the two
scripts only drive them.

`flow.sh` ends with a summary: how long each step took, the end-to-end wall
time, and the absolute path of every record and log the invocation produced —
bundle, preflight report, run record, execution log, results, postcheck record
and log, precheck reports, and the LibreLane run directory. It prints from an
`EXIT` trap, so a failed or interrupted flow still ends by saying where its
diagnostics are, and a step that was killed mid-way is listed as `did not
finish` rather than given a misleading duration. For scale, the reference
observable bundle is roughly 24 minutes to harden and 8 more to postcheck.

`$OUT` — one bundle and its runs — defaults to `../p4-$KIND`, **outside this
repository**, and should stay outside it. A completed `full` run directory is
around 235 MB of OpenROAD, Magic, and KLayout output: ODB and DEF snapshots per
step, fill insertion, GDS streamout, SPICE extraction. That is tool output, not
a result, and it does not belong in a git working tree. What belongs in the
repository is the curated record under [`evidence/`](../evidence): the manifest,
preflight, run, postcheck, and results JSON, plus the logs and signoff reports
the acceptance criteria are actually read from — under 200 KB for the run it
describes. Curate it by hand when a gate closes; the run store is scratch and
can be deleted once its evidence is extracted.

## Environment

`./bootstrap.sh` provisions everything the flow needs, pinned by
`toolchain.lock`, and nothing else on the machine:

```sh
./bootstrap.sh                  # converge both layers
./bootstrap.sh --check          # report the state of both, change nothing
./bootstrap.sh --install-deps   # also install missing packages into the opam switch
```

It provisions `.toolchain/{tt,pdk,.venv,.venv-precheck}` and the LibreLane
container image, and writes `.toolchain/toolchain-env.sh` for `flow.sh` to read.
The [bootstrap guide](bootstrap.md) covers the layers, the options, overriding
paths, and what to do when a check fails.

There is no dependency on a sibling checkout, in either direction. The pins are
this repository's own, in `lib/target.ml` and `lib/bundle.ml`; `toolchain.lock`
is a copy of them for the shell, and `test/check_bundle.py` fails `dune runtest`
if the two ever disagree.

Bootstrapping prepares an environment. It does not prove the design hardens,
meets timing, or passes precheck: those are `scripts/flow.sh` and its own exit
codes. `scripts/phase4.py preflight` then checks the particular emitted bundle
against the installed files, and never fetches or installs anything itself.

The runner uses Dockerized LibreLane by default and needs an accessible Docker
daemon; see [bootstrap troubleshooting](bootstrap.md#troubleshooting) when it is
installed but unreachable. The runner copies the pinned floorplan into its
per-run staging directory so the container can resolve `dir::../tt/...`. It reads
PDK views from `PDK_ROOT`.

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
  --python "$FLOW_PYTHON" --output "$RUNS/preflight.json"

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

`preflight` prints its report as JSON on stdout, and `--output` writes the same
report to a file. Use it: the report is the record of why a run was allowed to
start — every external file hash, the actual tool and container versions, and
any version waivers — and stdout from a seven-step flow does not survive as
evidence. `flow.sh` passes it by default and, once the run directory exists,
copies the report into it as `preflight.json`, so an attempt is self-contained.
The report is the same structure `run.json` stores under `environment`.

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

Both gates now have records:
[`evidence/p4/memory-synthesis`](../evidence/p4/memory-synthesis/README.md) for
P4.4 and
[`evidence/p4/observable-physical`](../evidence/p4/observable-physical/README.md)
for P4.5, which closes P4's exit gate. Each is a directory of the small
immutable records — manifest, preflight, run, postcheck, results — plus an
archive of the logs and reports its claims are read from, and a note stating the
result and any waivers. Follow that shape for a new gate. Note that the P4.5 run
used this repository's own example: it proves the physical path, and it is
deliberately not reusable as P5.4 consumer-adoption evidence.
