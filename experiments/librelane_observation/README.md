# Bounded LibreLane observation experiment

**Current result (slice 2, 2026-10-13): PASS in the existing official container.**
Twelve synthetic official-API lifecycle cases ran, and the sibling consumer passed
real synthesis → copied checkpoint → fresh floorplan and detailed-placement
continuations. A separate synthetic-subprocess experiment proves real owned
container timeout/removal. See [slice 2 evidence and backend strategy](SLICE2.md)
for exact reproduction, runtime/bridge provenance, artifacts and limitations.

The remainder records the **historical local blocker**, not current capability.
In particular, its missing-path validation assumption was corrected by execution:
this version validates view types in `Step.start`, while missing files can fail
later in final snapshot copying. The corrected probe has twelve cases.

## Historical local result

**Historical result: BLOCKED in the official constructor. Zero sequencing cases ran.**
The local LibreLane `3.1.0.dev3` imports successfully under venv Python `3.12.3`,
but its PDK Tcl loader fails on `import tkinter`. This occurs before `Flow.start`.
The synthetic configuration has therefore **not passed validation** either.

## Reproduction and evidence

From the repository root, opt in explicitly:

```sh
timeout --signal=TERM --kill-after=3s 60s /home/wayne/devel/jane/hardcaml_asic/.toolchain/.venv/bin/python -B experiments/librelane_observation/probe.py
```

Keep the interpreter spelling: resolving its symlink loses the venv. Do not source
the stale `.toolchain/toolchain-env.sh`. This is separate from the shared CLI
interpreter-resolution defect. The declared Python version is **3.11**, so even a
successful local probe would establish only available 3.12/local sequencing.

The captured invocation exited **2**, reporting `ModuleNotFoundError: No module
named 'tkinter'`. It creates a fresh `/tmp/opencode/librelane-observation-*`
directory and writes `evidence.json` there, including the full traceback, runtime
identity and source/fixture hashes. The actual scratch is
`/tmp/opencode/librelane-observation-72pve6uu`; the initial invocation in
`/tmp/opencode/librelane-observation-ghd_2wv2` exited 1 at the same point before
blocker capture was added. The concise retained record is
[`blocked-local.json`](../../evidence/librelane-observation/blocked-local.json).

`fixture.py` generates tiny PDK/SCL Tcl files, a design JSON and one placeholder
file, all under scratch. **These are synthetic config values, not usable physical
technology.** The normal flow constructor calls `Config.load`; no bare `Config`,
validation bypass, monkeypatch or replacement orchestration is used.

## Implemented cases and actual execution status

All eleven cases below are implemented but **unexecuted**, blocked by the first
constructor. They are not accepted tests or evidence of lifecycle behavior.

| Case | Assertions intended after constructor succeeds |
| --- | --- |
| Success/live/origin | Real propagated metric; repeated type normalized to distinct occurrences; empty update versus explicit equal update; earlier states readable while later body held |
| Gate false | No body hook for gated occurrences |
| Explicit skip | Selected occurrence absent from body callbacks |
| From skip | Earlier occurrences absent |
| To skip | Later occurrences absent |
| From/to range | Only selected middle occurrence enters |
| Immediate StepError | Outer FlowError; later body not entered; earlier output retained |
| DeferredStepError | Later body runs with earlier state, then final FlowError |
| Post-body validation | Body returned; in-memory state assigned; missing view causes failure before output file |
| Post-body runtime write | Synthetic `runtime.txt` directory collision causes write failure despite valid `state_out.json` |
| Injected interruption | Explicit KeyboardInterrupt from body, not a real process signal or descendant cancellation proof |

The live case uses a thread solely as a structured-file observer: an entry event
and release event hold the later body until reads complete. This is a deterministic
test barrier, not proposed production reader backpressure. No sleeps establish
ordering. Barrier waits are bounded at five seconds; sequencing has a 50-second
alarm plus the external 60-second timeout. The first successful constructor has
not yet been reached, so all assertions behind that boundary remain unverified.

Actual pre-constructor assertions did pass: substituted classes retain identical
`Flow.start`, `SequentialFlow.run` and final `Step.start` methods. The blocker
handler asserts that the missing module is specifically `tkinter` and no body
callbacks or observed objects exist. No Dune test dependency is added.

## Source-derived mechanism recommendation and boundaries

These conclusions are **source observations, not demonstrated runtime results**:

- Supported `SequentialFlow.Substitute` plus a `Step.run` mixin is the candidate
  seam for body entry/return/exception and raw metric-update origins. Empty updates
  inherit values; an explicit equal value is a distinct update. File metric diffs
  cannot distinguish those two cases. A raw update alone does not establish all
  contract provenance (units, constraints, evidence readiness, etc.).
- A returned body is not a completed `Step.start`. Input validation can fail
  before entry; output validation, state writes and runtime writes follow return.
  In-memory `state_out` assignment and even a complete output file precede remaining
  failure points. Direct upstream writes are not atomic publication.
- Gate and skip decisions occur in `SequentialFlow.run`, outside `Step.start`.
  Callback/file absence supplies neither an exact decision nor a reason, and
  does not distinguish skipped, unreached and pre-body failed occurrences.
- The outer return/exception supplies a flow-level outcome, not every occurrence's
  lifecycle. On failure, `Flow.start` does not publish the local sequential
  `step_list` into `step_objects`. Human logs are not a structured event stream.
- Structured per-step files are candidate diagnostic inputs, not commit records.
  Precise full-step completion, exact skip decisions and durable publication need
  a demonstrated additional seam or narrow upstream instrumentation before mapping
  them to the provisional provider contract. Do not label body returns completed.

The only native path actually exercised is local Python import, supported class
substitution and normal construction through the real config loader up to its
missing Tcl prerequisite. No live filesystem-observation capability was proven.
Container module visibility, the intended 3.11 runtime, actual full-flow execution
and descendant cancellation all remain unvalidated. Runtime repair requires
separate scope; this experiment stops at the concrete prerequisite blocker.
