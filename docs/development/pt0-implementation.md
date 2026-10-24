# PT.0 implementation: corrected SRAM probe and consumer testbed

Status: first slice verified 2026-10-24; PT.0a/b complete, PT.0c partial. The [phase plan](../phase_plan.md)
owns completion status. This record divides the first implementation slice into
bounded agent assignments and records verification as it happens.

## Scope and acceptance

Correct the retained 256×16 SRAM feasibility probe's power bridge geometry and
macro Liberty corner bindings, rerun meaningful physical checks, and prepare a
registered-memory specimen in `hardcaml_asic_example` for subsequent production
backend work. The example's existing FIFO remains a useful independent baseline.
Production macro selection is PT.1–PT.2; this slice must not disguise experimental
RTL as support in the public resource API.

Known corrections from the [S.3 disposition](../sram/sram-s3-disposition.md):

- Both VPWR Metal4 bridges move from x=111830–113930 to 113700–115800 DBU;
  their y coordinates and the VGND bridge remain unchanged.
  **Superseded by physical feedback:** that proposed right edge leaves only
  0.13 µm to the adjacent ground stripe. The implemented and rerun right edge is
  **115650 DBU**, giving 1.95 µm pin contact and 0.28 µm ground clearance.
- Exact `nom_fast_1p32V_m40C`, `nom_slow_1p08V_125C`, and
  `nom_typ_1p20V_25C` keys select fast, slow, and typical macro Liberty respectively.
  Remove wildcard fallback: LibreLane collects all matching views.
- Explicitly retain the fast standard-cell −40 °C / macro −55 °C difference.
- Retain new evidence independently of the original S.3 archive and its digest.

## Agent-sized assignments

### A — ASIC probe correction and bounded execution tooling

**Owner:** implementation agent A. **Files:**
`experiments/sram_flow_feasibility/` (excluding historical run outputs).

1. Correct bridge geometry and exact corner bindings.
2. Add a reproducible bounded runner for corrected-corner STA on retained routing,
   Magic-on-GDS, and a fresh corrected physical probe. Validate arguments, require
   explicit modes, use fresh output tags, and cap tool parallelism explicitly.
3. Make TT precheck invocation honor a thread allocation without editing pinned
   tool/PDK sources; if provided, use a recorded launcher for KLayout `threads`.
4. Preserve power-only versus corner-only attribution where practical, with
   immutable input snapshots rather than edits to historical run configuration.
5. Verify tooling without launching heavy EDA; hand off exact run commands and
   limitations to the coordinator.

### B — Independent registered-memory consumer specimen

**Owner:** implementation agent B. **Files:** `hardcaml_asic_example` only.

1. Add a small 256×16, 1RW, latency-one memory specimen using the public resource
   API and stable `program` identity. Keep the existing FIFO workflow usable.
2. Expose explicit flop and exact-mapping requests through a small specimen CLI
   or the existing project conventions, whichever is least invasive.
3. Add meaningful PDK-free load/read/hold checks and bundle/resource-policy checks.
   Today exact selection should fail clearly; it becomes the future SRAM adoption
   test once PT.1–PT.2 lands, not a local bypass of unsupported macro selection.
4. Document commands and dependency selection. Use the current ASIC source via an
   isolated development install if necessary; preserve existing active generations
   and Workbench configuration.

### C — Review and verification handoff

**Owner:** verification agent C after A's changes are available. **Files:** focused
new regression checks in ASIC `test/`, plus a review report to the coordinator.

1. Independently check the geometry against actual LEF and configured placement,
   and prove exactly one correct macro Liberty per corner.
2. Exercise negative argument/thread-budget cases and check the runner's immutable
   output/retained-input behavior. Avoid duplicating implementation-only assertions.
3. Review example acceptance and any backend assumptions; report defects with
   concrete reproductions. No heavy EDA runs without coordinator allocation.

### Coordinator — integration and physical evidence

1. Allocate the shared job pool; maintain this record and the phase plan.
2. Run corrected-corner STA and GDS-based DRC from retained inputs, then the fresh
   corrected physical probe if prerequisite checks pass.
3. Record actual loaded Liberty files, setup/hold and electrical violations,
   physical bridge geometry, extraction/LVS/power findings, and precheck outcomes.
4. Preserve sufficient new artifacts (including DEF, P&R netlist and extracted
   SPICE) to reproduce the analysis. Diagnose residuals before marking PT.0 complete.

## Execution policy

- No git add, commit, push, or other authorship/publication actions.
- Shared maximum **20 jobs**. Initial allocations: A up to 4 for lightweight
  checks; B up to 6 for builds; C up to 4 for checks. The remaining 6 are reserved.
  Builds within one checkout are serialized. Heavy EDA starts only after agents
  stop competing builds; initial EDA allocation is 10, with `STA_THREADS=1` and
  `OPENROAD_THREADS=10`. Explicitly bound KLayout as well as LibreLane's executor.
- No original evidence/run overwrite, automatic toolchain pin changes, or edits
  to installed PDK/TT sources. New output must have a fresh identity/location.
- Ordinary checks remain PDK-free where possible. Physical results and functional
  model results are distinct; this work does not close timed-model conformance.

## Initial inspection

The retained `attempt-005-full` live run has the databases, DEF, P&R netlist,
SPICE, GDS, SPEF and stage state needed for bounded checks. Referenced state views
exist. The original configuration, archive and GDS hashes match their recorded
values. The pinned LibreLane image is available locally. These are availability
checks, not fresh EDA acceptance.

The historical precheck defaults to 32 KLayout threads despite a different `thr`
argument: relevant decks use `threads`. Explicit thread control is therefore a
prerequisite to executing that check under the user's job policy.

## Implementation and verification record

### Delivered agent assignments

- **A:** corrected probe config/PDN; `run_pt0.py` with explicit STA, GDS-Magic,
  power-only, corrected-full and precheck-only modes, immutable input snapshots,
  fresh output identities, exact provenance and bounded tool threads.
- **B:** independent `hardcaml_asic_example/memory/` specimen and CLI, using public
  ASIC APIs, a stable `program` identity and explicit flop/Exact policy. Existing
  FIFO workflows and active provider/Workbench configuration are preserved.
- **C:** independent geometry/corner/runner regression coverage, physical report
  review and `collect_pt0.py` evidence collection/restoration. Review found and
  drove fixes for malformed retained-state handling, missing precheck reports
  directory, and bridge-to-ground-grid spacing omitted by the first geometry oracle.

### Checks and actual runs

ASIC checks:

```sh
python3 -B -m unittest discover -s test -p 'test_pt0_*.py' -v
python3 -B experiments/sram_flow_feasibility/collect_pt0.py \
  --verify evidence/sram-pt0/pt0-artifacts.tar.gz
git diff --check
```

All **33 regression tests** passed, with no skips or expected failures in this
environment. They include PDK-free runner failures and geometry checks plus
optional installed-PDK/retained-DEF oracles. The archive was collected twice
byte-identically, every member hash verified, and restored geometry/supply checks
passed in a fresh directory. The original S.3 archive hash is unchanged.

The example used existing isolated ASIC generation
`3c70c76700764a58974ef7d969adba36`; no provider installation was necessary.
`dune runtest -j6 test memory --force`, `dune runtest -j6 .` and the bundle checker
with `--require-rtl` passed. Memory checks cover **1,792 edges per elaboration
mode** and **1,280 word checks per emitted RTL set**, with negative oracles.
`dune build -j6 @all` passed with the existing Workbench SDK additionally selected.
The broad routing tests retain one explicit opt-in native-provider fixture skip.
See the [consumer commands and receipt](../../../hardcaml_asic_example/memory/README.md).

Physical commands, from the ASIC checkout, in execution order:

```sh
python3 -B experiments/sram_flow_feasibility/run_pt0.py sta \
  --tag corners-01 --jobs 8
python3 -B experiments/sram_flow_feasibility/run_pt0.py magic-gds \
  --tag magic-01 --jobs 4
python3 -B experiments/sram_flow_feasibility/run_pt0.py power-only \
  --tag power-01 --jobs 10 --precheck --tt-root .toolchain/tt
python3 -B experiments/sram_flow_feasibility/run_pt0.py corrected-full \
  --tag corrected-grid-02 --jobs 10 --precheck --tt-root .toolchain/tt
```

Tags identify retained attempts, not reusable commands: choose fresh tags for
new executions. All STA used `STA_THREADS=1`; OpenROAD and KLayout allocations
were explicitly bounded. Concurrent STA/Magic allocated 8+4; later power work
allocated 10 alongside the still-running 4-job Magic check. No other builds ran
alongside heavy EDA. At no point did allocations exceed 20.

| Attempt | Actual outcome |
| --- | --- |
| `corners-01` | Exit 0; correct single Liberty per corner, setup/hold pass; electrical violations remain |
| `magic-01` | Completed stage in 21m51.867s; outer shell timed out, so outer exit unavailable. 29,294 internal macro rectangles; original abstract M2/M3 boundary categories absent |
| `power-01` | Flow exit 2: 16 Magic rectangles including 12 genuine new M4 spacing markers. Precheck exit 1 due missing output directory; both defects subsequently fixed |
| `corrected-grid-02` | Flow exit 2 on three abstract M3.f markers; zero extraction overlap, unique black-box LVS match, correct supplies/corners; all nine current TT prechecks pass (exit 0) |

The external shell timeout did not stop the Magic container. It was monitored to
completion; no container remained running afterward. Use a sufficient foreground
timeout and check owned containers after interruption. Automatic cancellation is
not implemented by this experimental runner.

### Evidence and next bounded work

The [retained evidence](../../evidence/sram-pt0/README.md) includes reports,
commands, identities, GDS/DEF/netlists/SPICE/SPEF and restoration instructions.
Archive SHA-256:
`0c32607e16d3bb5e3c313033a53db0883167b3ab6b44c5f30bac0e3066546b9a`.
It is an analysis/replay set, not an arbitrary-stage checkpoint or bundled toolchain.

PT.0a/b are complete on that evidence. PT.0c remains open:

1. Repair macro-boundary slew/capacitance with explicit buffering/placement work,
   preserving library limits; rerun corrected-corner STA and affected physical checks.
   Final fresh slew counts are fast/slow/typical **12/25/21**, cap **12 each**.
2. Disposition the 29,294 retained-GDS Magic macro-internal findings against the
   PDK/deck and reconcile remaining abstract boundary markers. Current TT precheck
   success is separate evidence, not a waiver of these findings.
3. Add further evidence as those repairs land; retain failed attempts and their
   attribution. Production wrapper/CDL-backed LVS and timed-model conformance
   remain PT.1–PT.2 work, not claims made by this probe.
