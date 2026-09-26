# TT/CMOS5L flow execution and results

Status: operating guide, 2026-09-20. P4.1–P4.5 and the consumer reproduction are
closed with evidence; see
[phase plan section 7](phase_plan.md#7-p4--execution-results-and-physical-integration)
for what each gate rests on. Nothing below is outstanding work. This is the
standing account of how the flow is run and how a run becomes an evidence
directory, and the only documentation of `flow.sh`, `report.py` and
`archive.py`: [bootstrapping](bootstrap.md) ends where this begins, and
[bundle emission](bundle-emission.md) produces its input. The same sequence is
used for this repository's examples and consumer-owned adopted bundles.

The P3 bundle is immutable input. `scripts/phase4.py` is an external consumer:
it verifies the emitted file hashes and pinned target references, creates a
unique run directory for each attempt, executes LibreLane, and collects results
from either new or existing run directories. It does not install tools or change
`manifest.json`.

## Running it

`scripts/flow.sh` fills in this repository's example, testbench and reference
paths and hands every flow operation to the shared dispatcher — the same
implementation the installed `hardcaml-asic-flow` command runs — so there is one
account of sequencing, acceptance, run selection and archiving. It takes one
command per invocation, and no argument prints its help rather than starting
anything:

```sh
scripts/flow.sh                      # help; nothing is built or run
scripts/flow.sh build                # dune build && dune runtest
OUT=/tmp/try KIND=memory scripts/flow.sh emit
OUT=/tmp/try STAGE=synthesis scripts/flow.sh execute   # run -> collect -> report
OUT=/tmp/try RUN=/tmp/try/runs/<id> scripts/flow.sh report
scripts/report.py "$RUN"             # a specific run directory
scripts/report.py --runs "$RUNS"     # development only: newest run under a store
```

`execute` is the shared command's fixed sequence: run, then postcheck for a full
stage, then collect, then report, then an archive only if one was asked for. The
individual commands (`preflight`, `run`, `postcheck`, `collect`, `report`,
`archive`) are the same operations on their own, and any option the shared
command accepts can be passed straight through, for example
`scripts/flow.sh archive --output /tmp/evidence` or `scripts/flow.sh report
--json`.

Every path is an overridable environment variable (`TOOLCHAIN`, `TT`, `PDK`,
`FLOW_PY`, `PRECHECK_PY`, `OUT`, `BUNDLE`, `RUNS`, `KIND`, `STAGE`, `TESTBENCH`,
`TESTBENCH_TOP`, `RUN`). The defaults come from `.toolchain/toolchain-env.sh`,
which `./bootstrap.sh` writes and `flow.sh` sources; anything already set in the
environment wins over it, so `TT=... scripts/flow.sh preflight` still points the
run at another checkout. Two of them are required rather than defaulted, because
guessing either is how an expensive run or a misattributed record happens:
`STAGE` for `run` and `execute`, since there is no default stage, and `RUN` for
every resumed operation, since the newest directory under `$RUNS` is never
assumed to be the one you meant — run ids are random hex and do not sort by time,
and `run`/`execute` print `run_dir` in their JSON. `ALLOW_PYTHON_MISMATCH` is
gone: nothing waives the bundle's requested Python by default, and the driver
says so and stops if it is still set.
`report.py --runs "$RUNS"` selects newest by modification time; use an
explicit run path for durable evidence. `report.py` derives its acceptance scope
from the requested stage recorded consistently in `run.json` and `results.json`.
For a full run it prints timing per corner, signoff checks, the TT precheck rows,
and what the post-CTS resizer did about hold. It exits nonzero when required
evidence is missing or malformed, a required check fails, the requested stage
did not complete, the records contradict each other, or a full run leaves a
timing mode unconstrained. The `phase4.py` subcommands below remain a supported
development spelling of the same operations: `phase4.py`, `report.py` and
`archive.py` are adapters onto `flow/hardcaml_asic_flow/`, which is what the
installed `hardcaml-asic-flow` command runs, so there is one implementation under
all of them.

`execute` ends with an account of what it did: one stderr line per step with its
status and duration, the absolute run directory, and the archive path when one
was published, followed by a single JSON object on stdout carrying the run
identity, per-step statuses and the final outcome. It prints that on failure and
on interruption too, so an attempt that stopped still names the run holding its
diagnostics, and a failed step keeps its own status rather than being flattened
into the sequence's. For scale, the reference observable bundle is roughly 24
minutes to harden and 8 more to postcheck.

`$OUT` — one bundle and its runs — defaults to `../p4-$KIND`, **outside this
repository**, and should stay outside it. A completed `full` run directory is
around 235 MB of OpenROAD, Magic, and KLayout output: ODB and DEF snapshots per
step, fill insertion, GDS streamout, SPICE extraction. That is tool output, not
a result, and it does not belong in a git working tree. What belongs in the
repository is the curated record under [`evidence/`](../evidence): the complete
immutable input bundle, manifest, preflight, run, postcheck, and results JSON,
plus the logs and signoff reports the acceptance criteria are actually read
from. The run store is scratch and can be deleted once `archive.py` has produced
and verified that complete evidence directory.

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
meets timing, or passes precheck: those are the flow operations and their own
exit codes. `scripts/phase4.py preflight` then checks the particular emitted bundle
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
with the bundle's requested version. `scripts/phase4.py` keeps an explicit
`--allow-python-mismatch` for a development compatibility run, and it records the
actual version rather than changing the requested one in the build manifest;
nothing passes it for you, and the shared command has no such option at all —
a recorded `--waiver python-version=REASON` replaces it in P6.5. A run prints its `run.json` path even
if it fails. Its `execution.log` and partial `project/runs/asic` contents remain
available, and retries receive distinct IDs.

`preflight` prints its report as JSON on stdout, and `--output` writes the same
report to a file. Use it: the report is the record of why a run was allowed to
start — every external file hash, the actual tool and container versions, and
any version waivers — and scrollback does not survive as evidence. A run no
longer needs that file copied into it: `run` performs its own preflight and
saves that one as the attempt's `preflight.json`, so the record in a run is the
one that actually gated it. The report is the same structure `run.json` stores
under `environment`.

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
settings, supplied as reasoned overrides. `Tt_cmos5l.overrides` supplies them, so
a declaration gets them by asking rather than by copying. Without
`FP_PDN_MULTILAYER=0` and the template's PDN and LEF-pin settings, LibreLane's
defaults put the power grid on `TopMetal1`, and TT precheck rejects the layout
even though LibreLane's own DRC, LVS, and antenna checks pass.

`run.json` records build identity, manifest hash, actual environment, command
arguments, requested/completed stage, status, timestamps, and output paths.
`results.json` separates process completion from timing goals and physical
checks. Synthesis area is mapped standard-cell area in µm², and the cell-type
inventory comes from Yosys `stat.json`. Setup and hold slack are in ns, reported
with the worst corner when available. Missing metrics have reasons. Raw reports
remain linked by paths relative to the run directory. The collector is a separate
command and also works on a failed or partially completed run.

A synthesis-only run passes `report.py` only when both records consistently say
that synthesis was requested and completed, collection has no errors, mapped
cell and area metrics are finite and valid, and unmapped instances, synthesis
errors, and inferred latches are all explicitly present and zero. Zero mapped
area or cells is valid evidence for a design that legitimately maps that way; it
is not rejected by a generic positive-area rule. Physical timing, antenna, DRC,
LVS, postchecks, and hold repair are reported as not evaluated and not required
for this operation, never rewritten as passes. The final verdict says
`synthesis acceptance passed` rather than claiming physical signoff.

A requested full run remains subject to the complete policy: both records must
show full completion; synthesis evidence must meet the same requirements; setup
and hold metrics must be finite, cornered, and constrained with a passing timing
goal; DRC, LVS, and antenna must each be present and pass; and a completed
postcheck must explicitly pass both TT precheck and gate-level verification. A
full request that stops after synthesis therefore fails rather than being
reclassified as synthesis-only. Unknown, missing, or contradictory stage fields
also fail with diagnostics. Missing metrics remain unavailable, not zero or
pass.

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
for P4.5, which closes P4's exit gate. Each historical directory contains the
immutable records — manifest, preflight, run, postcheck, results — plus an
archive of the logs and reports its claims are read from, and a note stating the
result and any waivers. Archives made before complete-input preservation was
added may not contain `input-bundle.tar.gz` and cannot be reconstructed from
`reports.tar.gz`; do not infer otherwise. New archives use the complete shape
below. Note that the P4.5 run used this repository's own example: it proves the
physical path, and it is deliberately not reusable as P5.4 consumer-adoption
evidence.

### Building one

`scripts/archive.py` writes that shape from a finished run directory:

```sh
scripts/archive.py RUN_DIR --list                       # the selection, writes nothing
scripts/archive.py RUN_DIR --output evidence/p4/NAME    # records and both tarballs
```

It copies the immutable records out and writes two archives. `reports.tar.gz`
contains the logs and reports an acceptance decision is read from together with
`final/gds` and `final/nl`. `input-bundle.tar.gz` contains the original
`manifest.json` bytes plus exactly every path in `manifest.files`: copied source
inputs, synthesis and simulation RTL, configuration, constraints, and metadata.
`input-bundle.sha256` pins that tarball. `archive.json` names every member and
absence, records the bundle archive digest and size, and states whether the
verified bytes came from the original or staged bundle.

The final GDS and netlist are included on purpose. Everything else in the archive
is evidence that a check passed; those two are the run's actual output, the only
inputs to a precheck or gate-level rerun that cannot be regenerated without
hardening again, and together they cost about 500 KB compressed. The compiled
simulator (`checks/*/gate.out`) and the intermediate stage directories — `odb`,
`mag`, `mag_gds` — stay out: they are rebuildable and nothing reads them.

Every hash the run already pinned is re-checked on the way in: the staged
manifest against `run.json`, build identity against the manifest, every bundle
file against the manifest, source-input copies against both manifest inventories,
and the GDS, netlist and testbench against `postcheck.json`. Paths must be unique,
relative, contained regular files; symlinks and traversal are rejected. The
archiver prefers the original path in `run.json`. If that directory no longer
exists or is invalid, it accepts `RUN_DIR/project` only when that staged copy is
independently complete and valid. Added `tt/`, `runs/`, tool trees, and other
undeclared staging files are never included.

All validation and archive construction finish in a sibling temporary directory
before publication. A failure leaves an existing evidence directory unchanged.
`--force` replaces files owned by the archiver, including both input-bundle files,
while retaining `README.md` and other user-owned files. An absent reports input
is still reported rather than skipped, which is how a synthesis stage run
archives without pretending it has a layout. The input tarball uses stable member
ordering, timestamps, ownership, and modes, so unchanged input bytes produce the
same compressed archive digest.

The archiver does not write the `README.md` beside the records. That note is the
human account of what the run showed, and a generated stand-in would read as
though someone had checked the result.

Restore and verify the complete bundle using only the evidence directory:

```sh
EVIDENCE=/absolute/path/to/evidence-directory
RESTORE=$(mktemp -d)
(cd "$EVIDENCE" && sha256sum --check input-bundle.sha256)
tar -xzf "$EVIDENCE/input-bundle.tar.gz" -C "$RESTORE"
python3 - "$RESTORE/bundle" "$EVIDENCE/run.json" <<'PY'
import hashlib, json, pathlib, sys
bundle, run_path = map(pathlib.Path, sys.argv[1:])
manifest_bytes = (bundle / "manifest.json").read_bytes()
manifest = json.loads(manifest_bytes)
run = json.loads(run_path.read_text())
assert hashlib.sha256(manifest_bytes).hexdigest() == run["manifest_sha256"]
assert manifest["identity"] == run["build_identity"]
for entry in manifest["files"]:
    data = (bundle / entry["path"]).read_bytes()
    assert hashlib.sha256(data).hexdigest() == entry["sha256"], entry["path"]
print("verified", len(manifest["files"]), "bundle files for", run["run_id"])
PY
```

This verification needs no checkout, original bundle, run directory, PDK, or
opam switch. Re-executing or preflighting the restored design still requires the
separately recorded toolchain and external collateral. The consumer's historical
[clean-staging archive](../../scaf/flow_results/20260920-081325-ccecd9ed/README.md#preservation-and-restoration)
demonstrates the earlier manual preservation procedure; its record is not
rewritten by this capability. Do not edit emitted inputs to make restoration or
preflight pass.

The pinned LibreLane flow has a known ABC timing-print limitation: its renderer
passes `cell/pin` where ABC expects a cell name. The consumer's
[analysis](../../scaf/tinytapeout/reports/2026-09-20-p0.7-memory-synthesis.md#abc-diagnostics)
shows why that print is not timing evidence. It does not invalidate mapped
cell/area evidence or the independently reported post-route OpenSTA timing.
