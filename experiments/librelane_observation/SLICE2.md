# Slice 2: official API and real checkpoint evidence

Executed 2026-10-13. **Real synthesis and fresh physical continuation passed** on
the sibling `hardcaml_asic_example` controlled FIFO, without provisioning or
changing its working tree. This establishes bounded backend composition, not
full implementation/signoff acceptance or a persistent observation protocol.

## Reproduction

Run from `/home/wayne/devel/jane/hardcaml_asic`:

```sh
python3 -B experiments/librelane_observation/run.py --consumer /home/wayne/devel/jane/hardcaml_asic_example --bundle /home/wayne/devel/jane/hardcaml_asic_example/_flow_results/bundles/bbbda7ff53ea33cabf0063f7b26509bf601420ad5ab46c07e511fc8e9ee79477
python3 -B experiments/librelane_observation/run.py --consumer /home/wayne/devel/jane/hardcaml_asic_example --bundle /home/wayne/devel/jane/hardcaml_asic_example/_flow_results/bundles/bbbda7ff53ea33cabf0063f7b26509bf601420ad5ab46c07e511fc8e9ee79477 --physical-to OpenROAD.DetailedPlacement --timeout 600
python3 -B experiments/librelane_observation/verify.py /tmp/opencode/librelane-slice2-2c7gsbb8
python3 -B experiments/librelane_observation/verify.py /tmp/opencode/librelane-slice2-cp1weqzt
python3 -B experiments/librelane_observation/cancellation.py
dune build -j 20 @test/coarse-runner @test/execution-transport @test/runtime-observation
```

`run.py` creates a fresh scratch store, prints its path, validates the existing
bundle/collateral/runtime using `phase4.preflight`, stages a bundle copy and the
declared support-tools references, and launches three separately owned containers.
Each launch has a 600-second deadline by default, with `phase4.run_logged` process
group handling and `execution_transport.cleanup`. The synthetic suite additionally
has a 50-second alarm and bounded five-second observer barriers. There are no Dune
commands inside these scripts, no consumer writes and no automatic installations.
The cancellation experiment has an eight-second launch deadline, a six-second
readiness deadline and bounded metadata/top/inspect/cleanup calls.

### Actual retained stores

| Store | Actual result |
| --- | --- |
| `/tmp/opencode/librelane-slice2-2c7gsbb8` | 12 synthetic cases; 6 real synthesis steps; 7 real continuation steps through `OpenROAD.Floorplan`; independent audit passed |
| `/tmp/opencode/librelane-slice2-cp1weqzt` | 12 synthetic cases; 6 real synthesis steps; 28 real continuation steps through `OpenROAD.DetailedPlacement`; independent audit passed |
| `/tmp/opencode/librelane-cancellation-tdf1qq17` | Real timeout of synthetic official-API subprocess body; owned container absent; observed parent and child host PID/start-time identities gone |

Each real-flow store retains `preflight.json`, `transport.json`, `summary.json`,
three launch logs, copied `project/bridge/` sources, `project/{synthesis,physical}.json`,
body event JSONL, a synthetic `project/librelane-observation-*/evidence.json`,
`project/checkpoint/`, `project/retained-synthesis/`, and
`project/src/runs/physical/`. Raw EDA files stay outside the checkout. Scratch paths
are machine-local and must be retained for re-auditing; the small checked-in
[summary](../../evidence/librelane-observation/slice2-real.json) is not a replacement
for them. `verify.py` checks hashes, checkpoint consumption, distinct launch names,
segment outcomes, body/returned-step agreement and the equal-valued metric case.

## Exact runtime and bridge transport

- Bundle identity `bbbda7ff53ea33cabf0063f7b26509bf601420ad5ab46c07e511fc8e9ee79477`,
  top `tt_um_controlled_fifo`, source revision `1fe6b17d428ef95281b19fb6fd70c27c119a4aac`.
  Read-only `git rev-parse HEAD` matched that revision, and consumer `git status
  --short` remained empty after the experiments.
  The existing identity symlink resolves to the `.objects/` path recorded in
  `transport.json`; the driver copies it, without re-emission or consumer refresh.
- Tool root `/home/wayne/devel/jane/hardcaml_asic_example/_flow_tools`;
  support tools `da63c9927411e3aca350977d653d24bbf5bca972`,
  PDK `2bbec755dc67ca3db0261c3d6163e15735d66710`, technology `ihp-sg13cmos5l`.
  Preflight passed without issues or waivers. Host flow venv Python **3.11.17**
  and headless Tcl readiness passed. The stale provider `.toolchain/toolchain-env.sh`
  and old 3.12/missing-Tcl venv were not used.
- Existing official tag `ghcr.io/librelane/librelane:3.1.0.dev3` resolved once to
  local image ID **`sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a`**,
  Linux amd64; the recorded RepoDigest happens to have the same hash. Launches bind
  the local ID, with `--pull=never`, rather than re-resolving a tag per segment.
- `/usr/bin/docker`, server **29.8.1**, non-rootless, daemon identity
  `c2b9dc66-02a4-488c-a183-198dfa35c280`; UID/GID **1000:1000**.
  Project scratch is mounted RW at the identical absolute path; consumer PDK is
  mounted RO at its absolute path. No source checkout is mounted.
- Container Python **3.13.13**, LibreLane **3.1.0.dev3**, `Requires-Python >=3.10`;
  preflight accepts this under the bundle's distribution-supported container policy.
  Interpreter flags **`-I -B`**, executable
  `/nix/store/6a08ghhhzl5a07nr0ly762yh1ah6m5bj-python3-3.13.13-env/bin/python3`.
  The synthetic report's legacy `declared_python: 3.11, mismatch: true` compares
  against the **host** reference, not the evaluated container policy. Its generated
  internal timeout command is a suggested local invocation; `transport.json`
  records the actual full Docker argv, including `-I`, mounts and image ID.
- Bridge files are explicit copies under `project/bridge/`, supplied by absolute
  script invocation through the existing owned transport. `backend_probe.py` is
  not installed in the image, injected via ambient `PYTHONPATH`, or supplied by
  LibreLane's host-mount mechanism. Isolated Python requires explicit sibling
  loading for the fixture. Host and container SHA256 agree for the bridge:
  `27e4874654ebf1b5792757dedff7d9b063358d6aa7274626123719adeb294c8b`.
  Both segment reports record the loaded bridge path, hash and upstream sources.
- Actual image tools: Yosys **0.66**, commit
  `86f2ddebce7e98ce7cacc27e8a5c14cb53b51b51`; Verilator **5.046**;
  `openroad -version` reports **`dcf36133a369abc8f3c5e5738cd4d82e4903c0e0`**.
  The latter version probe was a separate bounded invocation of the identical image:

  ```sh
  docker run --rm --pull=never --entrypoint sh sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a -c 'openroad -version && yosys -V && verilator --version'
  ```

## Supported segment endpoints and restart API

The helper uses `Flow.factory.get("Classic")`, supported
`SequentialFlow.Substitute` classes wrapping only `Step.run`, the normal validated
constructor, and unchanged final `Flow.start` / `Step.start` methods. It asserts
that `SequentialFlow.run` is unchanged. No `Flow.start_step` hook is used.

**Demonstrated synthesis endpoint:** `flow.start(tag="synthesis", to="Yosys.Synthesis")`.
All six initial Classic occurrences execute (lint/checkers/header/synthesis).
The segment ends with a mapped 673-instance netlist and a JSON header. Successful
return also includes final snapshot creation; a body callback alone does not.

**Demonstrated fresh restart:**

```python
state = State.loads(checkpoint_state_json)  # default validate_path=True
state.validate()
flow = ObservedClassic(staged_config_path, pdk_root=pdk_root)
result = flow.start(
    tag="physical", with_initial_state=state,
    frm="Checker.YosysUnmappedCells", to="OpenROAD.DetailedPlacement",
)
```

`to="OpenROAD.Floorplan"` was separately demonstrated. Continuation starts at the
**immediate successor**, preserving synthesis checkers, SDC/macro checks and
pre-PNR STA before floorplan. Starting directly at `OpenROAD.Floorplan` would omit
those checks and is not the recommended composition. `frm`/`to` are inclusive,
exact normalized occurrence IDs; repeated STA IDs carry suffixes.

Before restart the host renamed `src/runs/synthesis` to `retained-synthesis`.
All original absolute view paths therefore disappeared. The first physical
`state_in.json` equals the copied checkpoint state, and a new process/container,
run directory and toolbox regenerate transient liberty/blackbox intermediates.
There is no `last_run`, newest-file selection, reused step objects, or implicit
same-directory resume. Resolved config hashes match across segments.

### Handoff closure and path dependencies

At this synthesis boundary the state has two non-null views:

- `json_h`: copied `tt_um_controlled_fifo.h.json`, 125191 bytes,
  SHA256 `39eb104d93ef68c4334e456bc1f6da4ac937dffe13074b02ed9621627d16868e`.
- `nl`: copied `tt_um_controlled_fifo.nl.v`, 77826 bytes,
  SHA256 `d1f66165277bc7ee2255d68b2fd66f41e167c8dc7be814cd864c7e5456ba008c`.

`checkpoint()` copies typed state views, rewrites their paths in official state
serialization and reloads it through `State.loads`; it records a view inventory.
It also retains `resolved.json`. `State.save_snapshot` alone is **not** sufficient:
it copies views/metrics but does not provide a relocated restart state JSON.

The checkpoint still requires the complete staged configuration/input bundle,
`constraints/top.sdc`, TT DEF template under `project/tt/tech/...`, referenced
PDK/SCL Tcl, technology/cell LEFs, liberty/corner data and other configured PDK
paths, plus the bound compatible image and bridge. Original RTL/header paths in
resolved configuration may still be validated even though synthesis is not rerun.
Only the state view paths were relocated. This is **path-bound restart on this
machine**, not cross-machine portability, a public validated checkpoint schema,
atomic checkpoint publication, or a minimal proof for arbitrary designs/macros.
The experiment-local helper covers these demonstrated views and nested mappings;
future generic closure handling must account for lists, corners and collisions.

Detailed placement output: `src/runs/physical/28-openroad-detailedplacement/`
contains real DEF and ODB (paths/hashes in the retained summary); the final state
also carries cumulative metrics and other generated views. No CTS, route, GDS,
DRC, LVS, gate-level postcheck or acceptance report was exercised in this slice.
An endpoint reached inside a segment is not a demonstrated independent restart
boundary: only **synthesis → fresh physical** was tested.

## Observation seam, measured limitations and next strategy

The 12 synthetic cases passed: successful live-file observation and equal-valued
measurement origin; false gate; explicit skip; from/to/range; immediate error;
deferred error; wrong-type post-body validation; missing-view final snapshot;
post-body runtime-write failure; injected `KeyboardInterrupt`. Earlier state files
are readable while a later body is held. Equal metric values cannot distinguish
inheritance from explicit remeasurement; raw updates `[{value:7}, {}, {value:7}, {}]`
do. Repeated types get distinct normalized occurrence IDs.

Important exact seams:

1. `Step.run` entry/return/exception and raw metric updates are supported body facts.
   Input checks precede entry; merge/type validation/state/runtime writes follow
   return. A body return is not full-step completion. The wrong-type case fails
   before state output; a runtime-write fault leaves a state file although start
   failed. A missing Path can survive `State.validate` and fail final snapshot.
2. Flow gates, explicit skips and out-of-range decisions occur outside body hooks
   in `SequentialFlow.run`. Callback absence does not identify reason or separate
   skipped/unreached/pre-body failure. The tests know reasons from test inputs;
   the adapter does not observe a structured decision event. On outer failure,
   local executed steps are not published into `flow.step_objects`.
3. Internal body no-ops are different again: `OpenROAD.IOPlacement`, obstruction
   steps and manual-placement steps can enter/return with `{}` while emitting a
   human “Skipping” message. A returned occurrence is neither proof of useful work
   nor a flow-gated skip. Human log parsing is not a lifecycle protocol.
4. Real STA raw updates retain corner-specific keys and body origin. They do not
   supply a complete units/constraint/tool/evidence-readiness contract. Raw backend
   metrics contain `Infinity` and large sentinels; these scratch diagnostics use
   upstream-compatible Python JSON, not strict finite public JSON. A public metric
   extractor needs explicit unavailable/nonfinite representation and provenance.
5. Segment `Flow.start` return/exception plus process/transport outcome is the
   demonstrated **whole-segment** completion seam. Structured files are diagnostic
   evidence, directly written upstream; they are not atomic commit records.
6. Real timeout/removal passed separately using an official synthetic body calling
   `Step.run_subprocess` with a real Python sleeping child. Readiness markers and
   `docker top` captured both host PID/start-time identities before timeout; after
   `run_logged` cleanup the container and those processes were absent, with no
   body return or state output. This proves forced transport cleanup on the local
   daemon, not graceful signal acknowledgement, EDA-specific descendant behavior,
   a full-step interrupted callback, or crash recovery. The earlier injected
   `KeyboardInterrupt` case proves only exception propagation.

**Next bounded implementation:** add a LibreLane segment adapter behind the shared
runner using the demonstrated `start(... frm/to, with_initial_state=...)` API.
First expose synthesis and synthesis-checkpoint → physical composition, preserving
the full default Classic sequence/checks and existing acceptance semantics. The
runner should own checkpoint publication after segment success, validate hashes,
configuration/collateral/runtime/bridge compatibility, and declare retained path
dependencies. Bind the runtime once across composed segments. Reject mismatched or
missing checkpoint closure before launching continuation. Add negative contract
checks for missing views, altered config/SDC/collateral and incompatible runtime.

Use body events for metric origins and progress only. If the next slice needs
exact per-step completion or gate/skip reasons, pursue narrow upstream structured
instrumentation around the existing `step.start` call and skip decision branch;
there is no demonstrated supported full-lifecycle callback today. Do not override
final start methods, copy `SequentialFlow.run`, infer lifecycle from missing files,
or implement the full journal in the configurable-stage slice.

## Checks and failed development attempts

Both independent audits passed. The targeted Dune command above passed (transport
10 and result-store dependency 45 tests visibly executed; other selected aliases
were already up to date). Existing runner/transport/runtime modules were reused.
Final `git diff --check` passed, AST syntax checks passed for all six experiment
Python modules, and the retained concise evidence passed strict JSON parsing.
`docker ps -a --no-trunc` showed no remaining containers.

Retained failed driver attempts: `w1oxwdg8` (isolated sibling fixture import),
`t3vey5a4` (stale missing-path validation assertion), `fg54_ckx` (DesignFormat keys
needed conversion in body-event JSON). All exited 1; the fixes preserve official
engine methods, and the later complete runs passed. These were helper defects,
not physical prerequisites. Cancellation attempts `lv4y8qdm` (fixture generated
under RO mount), `da6ru4fo` (fixture setting needed declared config variable),
`826pjd0b` (case-sensitive absent-container diagnostic) failed assertions; the final
`tdf1qq17` run passed. Scratch directories use the full prefixes listed above.
No Git history changes, staging, installations, or consumer modifications occurred.
