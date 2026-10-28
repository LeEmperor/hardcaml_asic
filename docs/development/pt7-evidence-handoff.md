# PT.7 B evidence producer contract (schema 1)

Scope: **standalone retained synthesized-netlist STA audit**, not normal flow,
preparation, or post-PNR integration. Read-only public API:
`Hardcaml_asic_execution.Timing_intent_evidence.inspect ~directory ()` returning
`(Evidence_json.t, string) result`; CLI:
`hardcaml-asic-flow timing-intent-inspect DIRECTORY [--json]`.
Invalid evidence exits 2; valid evidence with unavailable coverage exits 1.
No declared exception or successful `set_false_path` is proof of path effect.

## Contract for C (published early; A wire binding below)

Retain `audit.json` with exactly these keys:

```
schema: 1
kind: "hardcaml-asic.timing-intent-audit"
scope: "standalone_synthesized_netlist_sta"
build_identity: <bundle manifest identity>
audit_id: <nonempty exact attempt identifier>
stage: "synthesized_netlist"
producer: {tool: "OpenSTA", version: <nonempty exact version>}
corner: <nonempty exact corner>
sources: [{role, path, sha256}, ...]
```

All paths are audit-directory-relative regular files, no symlinks, traversal,
duplicate roles (except `liberty`) or duplicate paths. SHA-256 is lowercase hex.
Required source roles: `manifest`, `sdc`, `netlist`, `liberty` (one or more),
`driver`, `log`, `resolution`, `exceptions`, `unconstrained`, `downstream_min`,
`downstream_max`, `process_result`, `producer_version`. Every source is read and
hash checked: 64 MiB each for netlist/Liberty, 1 MiB for metadata/version, 8 MiB
for other text, 256 MiB total, 64 sources. At most 256 stages and 256 exceptions.
Log scanning is single-pass over hash-checked retained bytes: at most 65,536 log
lines, 64 KiB per line, 1,028 wire events and 2 MiB total wire-record bytes. The
resolution stream has the same line/wire bounds and at most 1,028 lines. Exceeding
these limits is invalid evidence; preserve the failed attempt instead of truncating
the producer's output into an apparently complete audit.
Retain exact emitted manifest/SDC, mapped netlist, linked libraries, executed Tcl,
complete tool log, and A's raw resolution/application output (`resolution`).
Do not use historical SRAM evidence or a different run's producer output.

Reports `exceptions`, `unconstrained`, `downstream_min`, `downstream_max` are
**native bytes**, even when the public reader cannot interpret them. Unsupported
native exception coverage is explicitly `unavailable`, never pass. The first
reader conservatively exposes application command completion separately from
native path-effect coverage; no supported exhaustive coverage parser is promised.
Thus the successful bounded audit initially exits 1 (coverage unavailable).

Retain `receipt.json` as role `receipt` (also required): exactly
`{schema:1, build_identity, audit_id, stage, producer, corner, inputs:[...]}`.
`inputs` is the exact list of `{role,path,sha256}` entries from `sources` whose
roles are `manifest`, `sdc`, `netlist`, `liberty`, `driver` (same order).
Receipt object-key order is immaterial, including producer and source-entry
objects; input **array** order remains significant. Bundle identity continues to
use the library's existing order-sensitive payload algorithm.
The driver must print a single line `PT7_AUDIT_RECEIPT <compact receipt JSON>`
to the retained log before reading SDC. This binds recorded producer context and
inputs by source replay, not by trusting an inspection summary. This is a
producer assertion, not authenticated execution attestation.

The driver should catch STA failures and terminate nonzero; preserve those logs.
Print a final single `PT7_AUDIT_COMPLETE` only after SDC and all reports complete.
Do not emit it on errors. B rejects missing/duplicate completion, log error lines,
missing/empty/truncated resolution, changed source hashes, or mismatched receipt.
Fatal-line grammar includes `Error:` / `Error ` / standalone `Error`, `PT7_ERROR`,
and leading `[ERROR ...]`, `[ERROR]`, `[FATAL ...]`, `[FATAL]`. Leading whitespace
and bounded ANSI SGR color decoration are ignored for this diagnostic check.
Ordinary INFO/quoted report text containing such strings is not a fatal line.
This is an explicit conservative rejection grammar, not a claim that C's exact
OpenSTA version emits every supported spelling.

The external wrapper (after waiting for the STA process) retains `process_result`
as exactly `{schema:1, receipt_sha256:<hash of retained receipt bytes>,
exit_code:0, argv:[<actual executable>, <actual arguments>...]}`. Nonzero or missing
exit is invalid evidence; completion text alone is insufficient. `producer_version`
is exact retained native version-command stdout, with its surrounding whitespace
trimmed equal to `producer.version`. This addition closes the process-exit and
native-version source requirements before C integration. Both are retained
producer assertions, not cryptographic execution authentication.

Requested/resolved/application assertions are reconstructed from A's emitted
manifest and actual Tcl wire through B's public API. C does not need a local
parser or a hand-authored evidence summary.

## A wire binding (handoff read 2026-10-28)

`resolution` is the exact concatenation (including final newline) of all
`HC_ASIC_TIMING_V1\t{...}` lines in `log`. Exactly **one** begin-to-complete
block per audit/corner is supported; repeated SDC loads require separate audits.
No banners or other lines in `resolution`. Preserve full native output in `log`.
The receipt line precedes the block; `PT7_AUDIT_COMPLETE` follows the block and
report generation. All events are checked against A's schema-1 handoff, exact
sorted stage/exception inventory, mapped master/pin roles, requested input and
target scopes, and resolve-all-before-apply ordering. Application events must
exactly replay resolved events. All stages must map to distinct cells.
Supported masters follow A's corrected inventory: `sg13cmos5l_dfrbpq_1`, `_2`,
`sg13cmos5l_dfrbp_1`, `_2`, with Q/D and optional RESET_B. A stage's null async
pin is valid for data-only declarations, but can never satisfy a reset target.
The reader reconstructs typed Timing declarations and replays the library-owned
`Elaboration.Timing_tcl.render`; the retained SDC must end with those exact
generated bytes. This rejects coherent manifest/log claims against unrelated
SDC bytes and corroborates async-control presence without a second Tcl parser.
Separately, the **complete SDC bytes**, including all prefixes, must hash-match
the `constraints/top.sdc` entry of the identity-verified supported manifest.
This does not reconstruct the complete base-SDC policy from declarations. A
coherently rehashed different manifest is a different asserted build, never an
authenticated A-emission/producer claim.

The manifest must have the supported **schema-1 LibreLane bundle envelope**,
including project/top/source revision, input-copy and member inventories,
resources/resource snapshot, target references, operation, resolved/generated
settings, configuration and requested tools. The reader validates the schema/field
structure and selected cross-links: safe unique member paths, input/source closure,
configuration/top/SDC links and the config member hash; the shared library verifies ordered payload identity and
resource cross-links. Minimal self-hash objects and schema 999 are rejected.
Other bundle members' bytes need not be retained in this standalone audit and
are not described as disk-verified merely because their manifest entries validate.
This does **not** re-resolve an A project, prove target compatibility, or reconstruct
clock/environment policy equivalence to the base SDC. A completely rehashed new
manifest is a new unauthenticated assertion, not authenticated producer evidence.

Output `requested` is the identity-checked manifest timing-intent object; `resolved` is labelled
`producer_reported`; `applied` is labelled `command_completed`. Hashing netlist
and libraries binds exact bytes but does not independently re-run object queries
or authenticate their association with execution. Forging all producer sources
is outside receipt authentication, and must never be described as proven tool
execution. Native unconstrained and downstream reports are retained with
`retained_not_interpreted` / unavailable coverage in the initial reader.

## Slice B implementation and checks

Implemented `execution/results/timing_intent_evidence.{ml,mli}`, the isolated
`bin/experimental_timing_intent_inspect.ml` helper, additive public CLI routing /
capability / Dune entries, and `test/timing_intent_evidence/`.

Verification (opam switch `5.2.0+ox`, shared ASIC build lock, at most six jobs):

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/timing_intent_evidence
```

Initial implementation passed **40 positive/negative checks**, including helper/public CLI routing,
capability output, scalar/bit capture and enumerated reset, data-only stages,
changed/missing/empty/symlink/escaping sources, duplicate/nonfinite JSON,
build/audit/stage/corner/producer mismatches, nonzero process despite completion,
version mismatch, requested-only/repeated/reordered/truncated streams, merged
stages, wrong pin roles, coherent resolved/applied scope forgeries, and coherent
manifest/hash claims against unrelated SDC. `git diff --check` passed.

Fixtures use actual library-generated Tcl but synthetic tool events; **no EDA
was run by B and no genuine native report is claimed by these tests**. Real
synthesis/STA evidence remains C's separate acceptance responsibility. The reader
does not independently re-elaborate sources, parse/relink netlists/Liberty, assess
CDC/reset correctness, prove native exception effect, or assess downstream timing
completeness. The current schema deliberately has no passing coverage outcome.

## Independent-review fixes — ready for C recapture

The public API, audit schema 1, event schema 1 and source-role list are unchanged.
A's R1/R2/R3 correction handoff explicitly retains event/manifest schema 1; B's
shared serializer replay uses its corrected current Tcl automatically. C must
re-emit and recapture the corrected **whole SDC**, original full manifest and new
build identity, then bind the fresh exact input closure and actual log/process
result/version. Old suffix-only/minimal-manifest fixtures are not acceptable
substitutes. The manifest file itself is not canonicalized/reordered before
checking the library's ordered-payload identity.

Post-review focused checks: **54 OCaml positive/negative checks plus 13 independent
Python repro regressions**, using a genuine ordinary-library `Bundle.render`
manifest/full-SDC pair and synthetic STA records. Cases include equivalent object
orders (accepted), reordered input arrays (rejected), real schema 999 and minimal
self-hash objects (rejected), altered SDC prefixes under the unchanged genuine
build identity (rejected), bracketed/ANSI fatal lines, quoted INFO controls, native
line-length and two-million-blank-line budgets. Fresh-helper peak RSS for the
large-log case was **38,656 KiB**, versus **35,072 KiB** baseline (regression bound:
baseline + 32 MiB). No EDA or authenticated execution claim is involved.

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/timing_intent_evidence test/timing_intent
```

## R5/R6 envelope correction and A-REAL-2 coordination

No public API, evidence/audit/event schema or source-role change. Additional
selected envelope checks now enforce:

- A generated or resolved setting's configuration key must be **present** before
  semantic value comparison. Absent and explicit null differ; an explicitly
  present null on both sides remains valid.
- `simulation_sources` is exactly the emitted top's synthesis RTL fallback or its
  separate `simulation/<top>.v` member. The SDC cannot be simulation RTL.
- Requested runtime policy is checked by the existing pure
  `Runtime_contract.policy_from_requested` validator. Empty, unsupported and
  contradictory policies reject. This checks the declared policy, not execution
  readiness, tool presence or native-stage qualification.
- The resolved `FP_DEF_TEMPLATE` must be a string naming the unique target
  `Support_tools` / `Floorplan_def` reference, and configuration must contain its
  exact `dir::../tt/<path>` rewrite. Objects, missing settings and mismatched paths
  reject; the corresponding config member hash is still checked.

Focused regression now has **54 OCaml checks and 27 independent repro cases**.
The added cases use a genuinely emitted manifest and reseal the ordered payload,
config member hash and receipts using exact Yojson serialization. Matching null
values, reordered runtime-policy objects and a genuinely emitted separate
simulation RTL bundle are positive controls. R5/R6 negatives reject for their
intended presence/role/policy/reference diagnostic, not an incidental hash error.
The shared runtime corpus also passed **2,961 accepted / 1,253 rejected** cases.
No broad suite was repeated for these bounded fixes.

C's native **A-REAL-2** invalidated the previous fixture's assumption that a top
Pin's direct net was the connected design net. A's latest handoff now checks
Port -> matching top Pin -> one non-NULL Term -> one non-NULL internal Net, both
for root caching and source tracing; no schema changes. B's owned independent
fixture was corrected against C's actual `timing/probe_port_net.py` and retained
findings: top Pin.net/get_nets returns NULL, only Term.net exposes the internal
net. It now passes eight positive graphs and 34 pre-application negatives, with
explicit zero-production-external-net-query checks. The anchor-output tap is now
a positive after A's filter fix. These are **model/code checks, not native
acceptance**; the old captured provider's failures remain failures.

**Ready for C's fresh recapture:** retain the latest emitted complete SDC,
manifest/new build identity and fresh native process/log/report receipts. Current
A Tcl SHA-256 is
`9c53a5b75313adacd979ea5b559fd17ad0c51d2961c4df6dc0a41813a88d25d2`.
Do not reuse the failed provider's identity or override its SDC. Native success
and meaningful mutation negatives remain C's separate pending acceptance, and a
valid B inspection still exits 1 / unavailable, never passing coverage.
