# PT.7 B — independent evidence/CLI review

2026-10-28. Reviewer implemented slice A, **did not implement B**. This review
reads the latest A/B handoffs and reviews B independently. No B source, CLI,
tests, A implementation, example, provider selection, Workbench or Protemu files
were changed. No EDA or Git mutations. This file is the only repository edit.

## Current independent follow-up summary

The original R1/R2/R3/R4 repros are now independently verified as corrected on
the follow-up snapshot below, using a **genuine full ordinary-library-emitted
manifest and SDC**, not the initial minimal envelope. Object-order positives,
schema/minimal-envelope negatives, fatal-line grammar, native line budgets and
unchanged-build prefix tamper all behaved as intended. No passing native coverage
verdict was found.

**Final independent R5/R6 closure is also verified below.** Thirteen focused
negatives reject for their intended presence/role/policy/floorplan reason, and
seven truthful controls remain unavailable/non-pass, including read-only public
inspection of C's final retained native bit/scalar r3 audits. No reviewed repro
remains open. The historical R5/R6 findings and B's remediation notes are retained.
Rehashed clock/technology policy changes remain within the expressly
unauthenticated/base-policy-not-reconstructed limitation; they are not fixed-build
provenance breaks. See **Final independent R5/R6 closure and C retained-audit
inspection** at the end for the latest snapshot and actual results.

## Initial review conclusion (historical; remediation/follow-up below)

**No false passing coverage verdict was found.** Accepted probes consistently
return exit 1, `verdict: unavailable`, `resolved.status: producer_reported`, and
`applied.status: command_completed`. Those qualifications are important and are
implemented, not merely described.

Three medium-priority issues merit correction: order-sensitive JSON receipt
comparison, accepting an unsupported/non-bundle manifest envelope, and large
log-line memory amplification. A fourth, low-priority diagnostic-grammar issue
needs qualification against C's actual producer. SDC prefix and argv probes
demonstrate important existing scope limits; they are **not** presented as native
coverage false passes or as cryptographic provenance breaks.

### Reviewed source snapshot

SHA-256:

| File | Digest |
| --- | --- |
| `execution/results/timing_intent_evidence.ml` | `9110fb484d6d7e86cf267ca3370028a7cf65970ee8dea75b79c0a5b727d0f204` |
| `execution/results/timing_intent_evidence.mli` | `4ecd8108f3da79b551bfb7fe4b5801f9260ca903b4cad7a2de29df7225f778ea` |
| `bin/experimental_timing_intent_inspect.ml` | `24adbb5553000208747a28aaae6313b185c29d55f0ab293198935bbd55a11343` |
| `test/timing_intent_evidence/check.ml` | `cbd8894b735fad9fb7f715f2391bcc83daeec08418d30a0926ee6006a5ac738b` |

Also inspected the public parser/router/capability changes and the shared
`Identity_json` parser and `Bundle.verify_manifest_identity` implementation.
Line references below refer to this snapshot.

## Findings

### R1 — Medium: valid receipt JSON is rejected solely for object-key order

**Location:** `timing_intent_evidence.ml:220–223`.

The audit/receipt comparison uses OCaml structural equality on Yojson objects:
`get receipt k <> get audit k`. Source entries in `receipt.inputs` are also
compared directly to the source objects from `audit.sources`. Yojson represents
objects as association lists, making these comparisons sensitive to object-key
order. JSON object order is not semantically meaningful; B specifies array order
for the input closure, not object-key serialization order. The log/receipt check
at line 237 already uses canonical comparison instead.

**Independent repro:** starting from an otherwise accepted fixture, reverse only
the key order of `receipt.producer` from `{tool,version}` to `{version,tool}`.
Keep values identical; update the retained receipt hash, process receipt hash,
logged receipt and source hashes consistently. Result: exit 2,
`audit/receipt mismatch: producer`. Reversing each input source object's keys
while leaving the input array order and values untouched produces exit 2,
`receipt input closure mismatch`.

The baseline exits 1 with qualified unavailable evidence. These are two false
rejections, not forged source associations. They can affect independently written
producer wrappers that use different JSON serializers or sort object keys.

**Suggested correction:** compare canonical validated objects or compare their
known scalar fields. Preserve the required input **array** order. Add both
object-order permutations as positive tests.

### R2 — Medium: identity verification is mistaken for manifest-envelope validation

**Location:** `timing_intent_evidence.ml:241–247`; shared helper
`lib/elaboration/bundle.ml:148–158`.

`Bundle.verify_manifest_identity` checks JSON validity, the ordered-payload hash
and optional resource cross-links. It is not a complete bundle-envelope/schema
validator. B does not add an envelope check before describing this source as a
bundle manifest and using its identity as `build_identity`.

**Independent repro:** an object containing only `identity`, `files` (one SDC
entry), and `timing_intent` is accepted. Add `schema_version: 999`, recompute the
ordered-payload identity and dependent receipt/source hashes, and it is still
accepted: exit 1, `verdict: unavailable`, application `command_completed`.
It lacks the actual emitted bundle's project/top/target/adapter/operation/source
and configuration envelope. This is consistent with the existing B test helper
at `test/timing_intent_evidence/check.ml:17–19`, which creates a minimal hash object
instead of a real emitted bundle manifest.

This is a schema/provenance-classification gap, **not** a collision or acceptance
under a previously trusted immutable build identity: the recomputed identity is a
new identity. B correctly does not claim authenticated execution. Nevertheless,
unsupported bundle formats and arbitrary hash objects should not acquire the
same classification as a supported emitted bundle without an explicit policy.

**Suggested correction:** validate the supported bundle envelope/version and the
relevant source/SDC/configuration fields, or explicitly label a weaker generic
hash-manifest mode separately. Use at least one real A-emitted manifest/SDC pair
in positive tests; retain synthetic tool events without pretending they are EDA.
This does not require re-elaboration or authenticated source stamping.

### R3 — Medium: accepted byte budget permits severe log-line memory amplification

**Location:** `timing_intent_evidence.ml:232`, `111–121`, `252–255`.

The reader bounds file bytes, but splits the entire log into a list and later
constructs full `(index,line)` and filtered position lists repeatedly. There is
no log-line budget before those allocations. The event budget of 1028 applies
only to retained timing-wire records, not the native log.

**Independent repro:** prepend two million blank lines to the valid fixture log;
keep the receipt before the timing block and completion after it, and update its
source hash. The log remains approximately 2 MB, well below the 8 MiB text limit.

- Normal inspection accepted it, exit 1, about **0.77 seconds / 338,356 KiB peak
  RSS** on this host (fresh helper child, Python `RUSAGE_CHILDREN`). A separate
  fresh-child baseline measurement was **34,816 KiB / 0.011 seconds**, exit 1.
- An initial **256 MiB address-space-limit** experiment aborted with SIGABRT and
  `Fatal error: Not enough heap memory to reserve minor heaps`. A subsequent
  baseline control under that same cap **also aborted**. That cap is incompatible
  with this runtime's virtual-memory reservation even for the small fixture; the
  capped abort is **not evidence of an input-induced crash** and is excluded from
  this finding's impact claim.

No hangs, FIFO reads or EDA were involved. This is finite byte-bounded work, not
an unbounded-length read, but the amplification is significant for the advertised
bounded inspector. The allowed 8 MiB log budget permits substantially more lines.
The confirmed finding is avoidable resident-memory amplification, not a
demonstrated uncapped crash.

**Suggested correction:** scan log lines once with a line/record budget and retain
only the bounded wire/receipt/completion state and positions. Reject an excessive
line count before building lists, rather than relying on catching allocation
failure. Add a large blank-line fixture with a bounded-memory expectation.

### R4 — Low / producer-grammar qualification: bracketed fatal diagnostics are ignored

**Location:** `timing_intent_evidence.ml:239–240`.

Only trimmed lines beginning `Error` or `PT7_ERROR` invalidate the retained log.
A line `[ERROR STA-0001] synthetic fatal diagnostic` in an otherwise valid fixture
is accepted; a control line `Error: synthetic fatal diagnostic` is rejected.
The handoff's broad statement that B rejects retained log error lines is therefore
wider than the implementation's grammar.

This probe is synthetic. It does **not** establish that C's standalone OpenSTA
version emits bracketed diagnostics; OpenROAD-style diagnostics must not silently
be treated as qualified standalone OpenSTA grammar. The recorded process exit
and completion marker still have to claim success, and coverage remains
unavailable.

**Suggested correction:** qualify the actual C producer's error syntax and
document/check that grammar. If bracketed or ANSI-decorated errors can occur in
that supported producer, add them as negatives. Do not invent a broad parser
which rejects ordinary quoted report text without real producer evidence.

## Verified scope limits, not additional blocking defects

### L1 — SDC replay proves the generated suffix, not the whole constraint policy

`replay_sdc` at lines 167–183 checks `String.ends_with ~suffix:expected sdc`.
An SDC with this extra prefix is accepted after coherently updating its manifest
and receipt hashes:

```tcl
set_false_path -from [get_ports {*} ]
# followed by the exact current A-generated timing helper/invocation
```

The independent fixture returns exit 1 / unavailable, with command-completed
application records. This **matches B's current explicit suffix-only handoff**;
it must not be reported as whole-SDC replay or evidence that no other broad
exceptions exist. Missing/changed primary-clock/environment policy or extra Tcl
before the suffix is outside this check. The SDC checksum does correctly prevent
substitution while retaining an already fixed manifest identity.

If the intended claim becomes “this is exactly A's emitted constraint policy,”
full-file reconstruction/validation needs an A-owned stable contract for the
base SDC plus PT.7 block. Native coverage remains a separate question regardless.
No native effect of the synthetic prefix was measured here.

### L2 — process argv and netlist/driver association remain producer assertions

A coherent retained fixture with process argv `[/bin/true, unrelated-driver.tcl]`
is accepted. There is no executable/driver-path semantic binding in lines
225–231 beyond nonempty bounded argv, receipt hash and zero exit. The reader also
deliberately does not parse/relink netlists or libraries. These observations are
consistent with the source-authentication label and the handoff's stated trust
boundary. They are not evidence of a real tool run and must not become such in
human output or future acceptance logic.

### L3 — concurrent filesystem mutation is explicitly excluded

`member` uses `lstat` path traversal followed by a separate `openfile`; this is
not descriptor-relative, no-follow race protection. The interface explicitly
requires that sources not mutate concurrently. Stable symlink members are
correctly rejected by the independent control. I did not race symlink swaps
against inspection and do not classify an excluded concurrent-mutation attack as
a demonstrated current-contract violation. If the reader later claims hostile or
concurrently writable directory safety, this read path needs stronger primitives.

## A shortcomings exposed by B integration

1. **Shared manifest helper scope (R2).** A's public
   `Bundle.verify_manifest_identity` name must not be read as full envelope
   validation. A should document that distinction clearly or supply a separate
   pure envelope validator for readers. B needs an explicit policy at its call
   site; no A/B code was changed during this review.
2. **No full-SDC replay seam (L1).** A provides a pure PT.7 suffix renderer, not
   reconstruction of the complete SDC from retained manifest facts. That is enough
   for the currently documented suffix claim, not a full policy-equivalence claim.
3. **Bound mismatch.** A's resolver accepts nonblank reasons and inventories
   without B's 4096-byte string / 256-stage / 256-exception bounds. B documents
   these reader limits, so this is an interoperability limitation rather than an
   unsafe acceptance. A emission can therefore succeed for declarations B cannot
   inspect. Coordinate shared bounds or document the smaller supported audit
   subset. This observation is static; no giant circuit was built.
4. **Synthetic A fixtures do not qualify native object-query compatibility.**
   B's serializer replay is not a real-tool test of A. C must still establish
   actual preservation, exact pin queries, mapped topology and downstream min/max
   paths using the emitted SDC. Nothing in this review promotes that pending work
   to acceptance.

## Verification and retained repros

Built fresh review executables under the shared lock and correct switch:

```sh
flock /tmp/opencode/asic-pt7-build.lock opam exec --switch=5.2.0+ox -- \
  dune build -j6 bin/flow_cli.exe bin/experimental_timing_intent_inspect.exe \
  test/timing_intent/check.exe

flock /tmp/opencode/asic-pt7-build.lock opam exec --switch=5.2.0+ox -- \
  dune runtest -j6 test/timing_intent_evidence
```

B's existing suite passed **40 checks**. No source/test modifications were used
to make it pass.

Independent script: `/tmp/opencode/pt7-evidence-review-probes.py`.
Run from any directory with `python3 -B` after the above build. It obtains the
actual current A fixture's JSON and emitted Tcl, independently constructs the B
receipt/wire/source closure, and invokes the compiled helper/public CLI. Synthetic
netlist/report content is explicitly labelled; no EDA is invoked. The script's
first development invocation had a local Python keyword-argument collision; that
probe-script mistake was fixed before the retained completed run.

Completed retained run:
`/tmp/opencode/pt7-evidence-review-3wqhe7qi/results.json`.
Each named directory retains its exact audit and sources; sibling `.out`/`.err`
files retain CLI output. There are **13 independent probe invocations**:

| Probe | Observed |
| --- | --- |
| Baseline with A-generated block | exit 1, unavailable |
| Unsupported manifest schema 999 | exit 1, unavailable (R2) |
| Equivalent producer object key order | exit 2, mismatch (R1) |
| Equivalent source-entry object key order | exit 2, closure mismatch (R1) |
| Broad extra SDC prefix | exit 1, unavailable (L1) |
| Bracketed error diagnostic | exit 1, unavailable (R4) |
| `Error:` control | exit 2, retained STA error |
| Unrelated argv | exit 1, unavailable (L2) |
| Public CLI `timing-intent-inspect -- --help` targeting a real `--help` directory | exit 1, actual inspection; no option-injection bug |
| Absolute-path helper control for that directory | exit 1, unavailable |
| Two-million-line log under 256 MiB cap | SIGABRT / `-6` (R3) |
| JSON nesting depth 257 | exit 2, nesting limit |
| Stable symlink source | exit 2, not a regular file |

Additional uncapped fresh-helper measurements of the same large-log shape in
`/tmp/opencode/pt7-evidence-review-98wdjla0/large-log` produced the R3 RSS/time
measurement above, and of the retained baseline produced the baseline RSS/time.
An additional capped baseline control established that the initial cap experiment
was not a valid crash differential; see R3. Independent probes ran serially, with a 10-second child CPU
limit and 20-second subprocess deadline; the RSS measurement had a 15-second
deadline. No Dune/EDA subprocesses are nested inside these probes.

## Recommended disposition

Fix R1 and make the R2 envelope policy explicit before treating independent
producer interoperability as closed. Bound/stream the native log in R3. Resolve
R4 against C's actual native grammar. Retain the existing unavailable/non-pass
semantics and the careful producer-assertion labels. Suffix-only replay and
unauthenticated execution are deliberate limitations; do not silently upgrade
those claims when C's real-tool fixture succeeds.

## B remediation (2026-10-28; appended by B, original review retained)

- **R1 fixed:** receipt context and input closure comparisons now use strict
  canonical semantic equality. Object field order is ignored; array order is
  preserved. Both independent order permutations are positive regressions.
- **R2 fixed:** a separate supported schema-1 LibreLane envelope validator precedes
  the existing identity verifier. It requires/validates the actual emitted
  project/top/source/target/settings/configuration/tool envelope and inventories,
  input/member hash closure and configuration/top/SDC bindings. Minimal self-hash
  objects and a genuine envelope with schema 999 are negative regressions.
- **R3 fixed:** native log scanning is single-pass over retained bounded bytes,
  capped at 65,536 lines and 64 KiB/line. It retains only receipt/completion state
  and at most 1,028 / 2 MiB wire records; resolution scanning is also bounded
  before line-list construction. Full-log split and repeated position lists were
  removed. Independent fresh-child measurement: baseline **35,072 KiB**, rejected
  two-million-line case **38,656 KiB**, below baseline + 32 MiB. No address-space
  cap was used.
- **R4 addressed:** explicit bracketed ERROR/FATAL and leading ANSI SGR grammar
  now rejects fatal lines. INFO/quoted text controls remain accepted. This is a
  conservative supported rejection grammar, not invented evidence about C's
  exact standalone producer output.
- **L1 hardened without expanding the trust claim:** the entire SDC is directly
  hashed against the identity-covered `constraints/top.sdc` entry of a validated
  full bundle envelope. A prefix edit with updated source/receipt hashes but the
  original manifest/build identity is rejected. PT7 suffix replay is additional;
  the reader does not reconstruct full base-SDC policy. A coherently rehashed
  different manifest remains a different unauthenticated asserted build.

Regression files are retained in `test/timing_intent_evidence/`, including
`bundle_fixture.ml` (ordinary real library emission) and `review_regression.py`
(independent source/receipt rebinding and fresh CLI/RSS checks). No actual tool
events or native reports are fabricated as execution proof: those test bytes
remain explicitly synthetic. Focused suites passed **54 OCaml checks and 13
independent repro cases**, plus the focused A suite. Public coverage remains
unavailable / CLI exit 1; invalid evidence exits 2. API/event/source-role schemas
are unchanged; see updated B handoff for C recapture against A's corrected Tcl.

## Independent follow-up of B corrections — 2026-10-28

This section is the independent reviewer's verification, separate from B's
remediation statement above. No B production or test source was edited, and B's
broad ASIC regression was **not duplicated**. The only repository edit in this
follow-up is this review document. No EDA, provider/config changes, example edits,
Workbench/Protemu access or Git mutations.

### Follow-up snapshot and genuine baseline

| File | SHA-256 |
| --- | --- |
| `execution/results/timing_intent_evidence.ml` | `923095f6df831770aa24fc9156346fdb0c24913ba39928a088ca51c9313edb7b` |
| `execution/results/timing_intent_evidence.mli` | `52a6638ccd0b65f8f041393aff2a60b18108b4cc06423546e0b3b105ab84acd5` |
| `bin/experimental_timing_intent_inspect.ml` | `24adbb5553000208747a28aaae6313b185c29d55f0ab293198935bbd55a11343` |
| `test/timing_intent_evidence/check.ml` | `754ae601b4329cf04e214692a841e33f2b649b724912be43edec3110eec3f411` |
| `test/timing_intent_evidence/bundle_fixture.ml` | `2f80d3dbc1340b76cf06557c78ebe779b43e0107407763357e85f6375e3198a1` |

I inspected the fixture generator: it constructs an ordinary `Project`, two
original scalar registers with actual registration, resolves it, and calls real
`Bundle.render`. Its exported baseline manifest/full-SDC bytes are unchanged by
the independent script. STA events, netlist/library/report placeholders remain
**synthetic**, and are not execution proof.

Genuine baseline identity:
`9b5732155bf53fb263be38146132123acd16592e78a3c13aa89ec646aa4c0955`.

Retained baseline:
`/tmp/opencode/pt7-evidence-recheck-nax5k1cq/genuine-manifest.json` and
`genuine-top.sdc`. Full retained result inventory:
`/tmp/opencode/pt7-evidence-recheck-nax5k1cq/results.json`.

### Original findings: independent correction verification

| Original issue / control | Independent follow-up result |
| --- | --- |
| Full genuine manifest + full emitted SDC | Helper and public CLI both exit 1, unavailable; producer-reported / command-completed labels retained |
| R1: reverse only receipt producer object's keys | Accepted, exit 1 |
| R1: reverse keys in receipt input-entry objects, preserve array order | Accepted, exit 1 |
| Reverse receipt input **array** order | Rejected, exit 2, input closure mismatch |
| R2: real full envelope with schema 999 and recomputed identity/closure | Rejected, exit 2, unsupported envelope/schema/adapter/operation |
| R2: minimal correctly self-hashed object | Rejected, exit 2, invalid fields |
| R4: `[ERROR STA-0001]` diagnostic | Rejected, exit 2, retained STA error |
| R4: leading ANSI SGR + `[FATAL ...]` | Rejected, exit 2, retained STA error |
| Quoted error in INFO text / `Errorless report heading` | Accepted, exit 1; no false rejection by broad `Error` prefix |
| R3: two million blank lines, correct hashes/receipt/order | Rejected, exit 2, line budget exceeded |
| Exactly 65,536 total log lines | Accepted, exit 1 |
| 65,537 total log lines | Rejected, exit 2, line budget exceeded |
| 65,537-byte native log line | Rejected, exit 2, 64 KiB line bound |
| Prepend broad false-path command, update source/receipt hashes, retain original manifest/build | Rejected, exit 2, SDC differs from emitted bundle |
| Same prefix with coherently changed manifest SDC entry/new build identity | Accepted, exit 1; explicitly a **different asserted build** (existing L1 limit), not fixed-build tampering |

R3 RSS was independently measured using fresh helper children under
`/usr/bin/time`, without an address-space cap:

- baseline: **35,328 KiB**;
- rejected two-million-line log: **38,656 KiB**, about 0.033 s;
- delta: **3,328 KiB**, within the independent baseline + 32 MiB bound.

This confirms the memory-amplification repro is addressed. The earlier invalid
256 MiB virtual-address-space experiment was not reused. Streaming/budgeted
scanning in `iter_lines` / `scan_log` (current lines 112–158) explains the result.

The unchanged-build prefix check confirms the complete-byte integrity binding;
it does not prove complete base-SDC semantic replay. The initial implementation
already bound source hashes transitively to the manifest entry; the new direct
whole-SDC hash check makes that binding explicit. Do not describe it as source
authentication or as rejecting a completely rehashed new declared build.

### Remaining finding R5 — Medium: generated/configuration presence contradiction

**Current location:** `timing_intent_evidence.ml:288–296`, especially line 292;
`get` at line 5 returns null for an absent key.

On the genuine manifest, add only:

```json
"generated_settings": {"...existing entries...": "...", "REVIEW_MISSING_KEY": null}
```

Leave `flow_configuration` without that key; recompute the ordered manifest
identity and the audit/receipt/input closure correctly. Retain genuine complete
SDC bytes. Independent case `generated-missing-null` is **accepted**, exit 1.

`equal (get config k) v` compares missing-as-null to explicit null, so it claims
generated/configuration consistency despite the property being absent from the
configuration. This is a concrete internal envelope contradiction, not merely
failure to authenticate a purported generator. It requires a new asserted build
identity; it does not defeat an already pinned manifest or produce native pass.

**Recommended correction:** require membership in `flow_configuration` before
semantic value comparison, using strict key lookup rather than the sentinel
getter. Test missing key vs explicit null separately; do not reject legitimately
present null values merely to avoid the distinction.

### Remaining finding R6 — Low: envelope validation is still partial by role/type

All cases below start from the genuine emitted manifest; mutate the listed field,
recompute its ordered identity and receipt/source bindings, and retain the same
genuine complete SDC. They are **accepted**, exit 1 / unavailable:

| Independent case | Contradiction / missing validation | Current location |
| --- | --- | --- |
| `simulation-is-sdc` | `simulation_sources = ["constraints/top.sdc"]` is accepted as a simulation source inventory; only member existence is checked | lines 263–268 |
| `empty-runtime-policy` | `requested_tools.runtime_policy = {}` is accepted as a supported requested policy; only object-ness is checked | lines 306–309 |
| `fp-template-contradiction` | Replace resolved `FP_DEF_TEMPLATE.value` with an object `{"not":"a template reference"}` while generated/configuration/target facts remain unchanged; exemption skips all value checks | lines 297–305, especially 303 |

These fields are peripheral to the standalone STA audit, so this is not a new
timing-acceptance blocker or proof of unsafe execution. The latest handoff says
the supported emitted envelope's requested tools, source inventories and
configuration links are validated; that must be qualified as structural/partial
until these role/type checks exist. A legitimate library emission does not name
the SDC as its simulation RTL or emit an empty runtime-policy object.

The `FP_DEF_TEMPLATE` exemption has a legitimate reason: resolved declaration and
rendered bundle-relative configuration use different representations. That is
not a reason to accept a non-reference JSON object in the resolved setting.
Validate the raw reference type and, where feasible, its target/member mapping.
For runtime policy, reuse the existing provider-owned policy validator rather
than introduce a second incompatible schema here. Keep unsupported policy
inspection distinct from execution readiness.

### Additional tested semantic limits (not additional critical findings)

- Changing `target.technology` alone to `different_technology`, while config/PDK
  and references retain CMOS5L, is accepted after rehashing a **new** manifest.
- Changing `CLOCK_PERIOD` to zero in configuration and the corresponding
  resolved/generated setting, recomputing the actual Yojson config-member hash,
  but leaving the retained emitted 20 ns SDC unchanged, is accepted after rehashing
  a **new** manifest.
- Conversely, changing configuration `DESIGN_NAME` alone is rejected with
  `bundle configuration/top mismatch`; changing the resource snapshot's project
  alone is rejected by the shared manifest verifier. These rejection controls
  show the mutation probes were exercising actual checked cross-links rather
  than simply failing to rebuild valid identities.

The accepted clock/technology changes demonstrate that the new envelope checks
do not establish target compatibility or clock-policy equivalence to the SDC.
That is within L1's explicitly unreconstructed base-policy limit and the
unauthenticated producer-assertion model. The correct claim is **selected envelope
structure/cross-links plus exact bytes**, not “revalidated as an A-resolved
project.” B need not re-elaborate or run STA to remain useful, but neither its
documentation nor consumers should upgrade the claim. No forged timing pass or
unchanged-build association was found.

### Focused execution and reproducibility

Only necessary executables were rebuilt, no broad ASIC suite:

```sh
flock /tmp/opencode/asic-pt7-build.lock opam exec --switch=5.2.0+ox -- \
  dune build -j6 bin/flow_cli.exe bin/experimental_timing_intent_inspect.exe \
  test/timing_intent_evidence/check.exe
```

Independent mutation/rebinding/RSS script:
`/tmp/opencode/pt7-evidence-recheck.py`.
Exact Yojson serializer helper (temporary reviewer source, no B changes):
`/tmp/opencode/pt7-review-json.ml`, built serially with `ocamlfind ocamlopt`
under the same lock and switch. Its three operations are compact serialization,
pretty serialization and ordered-payload rehashing; it contains no B validators.
The compiler emitted a benign module-name warning for this temporary hyphenated
filename; the helper built and ran. Using this serializer prevents Python float
or pretty-print differences from turning a contradiction test into an unrelated
hash failure.

Run `python3 -B /tmp/opencode/pt7-evidence-recheck.py` after the build. The script
exports B's genuine ordinary-library fixture in export-only mode (does not run
B's broad/default tests), independently reseals mutations, and makes **25 focused
helper/public CLI calls**. Each source/audit attempt and sibling stdout/stderr
is retained under the result directory above. Probes ran serially with a
10-second child CPU limit, 15-second deadline and no core dumps; no EDA or nested
Dune calls. All exercised outcomes and the RSS bound matched the script's checks.

### Final disposition

Original R1 and the concrete R2 version/minimal-envelope repros are verified
closed. R3's allocation issue and R4's explicit fatal grammar are verified
addressed. Whole-SDC integrity under an unchanged build is confirmed. R5 remains
a concrete consistency defect; R6 and the clock/technology probes bound the
meaning of the stronger envelope claim. No review source fix was made, no broad
regression result is claimed, and C's corrected-provider real-tool recapture
remains independent pending acceptance.

## B R5/R6 remediation (2026-10-28; original independent findings retained)

**Implemented by B; independent reviewer confirmation of this new correction is
not claimed here.**

- R5: selected generated/resolved setting comparisons now use required key lookup
  before semantic equality. This rejects missing-as-null contradictions while
  preserving a genuinely present null. Repro regressions include missing generated
  null, matching present null, mismatched present null and missing resolved null.
- R6: simulation RTL is restricted to the top module's emitted synthesis fallback
  or separate simulation source, each already closed by the member inventory.
  The SDC-as-simulation-source repro rejects. Both genuine emission forms pass.
- R6: empty/unsupported/contradictory runtime policy rejects through the existing
  pure `Runtime_contract.policy_from_requested` validator. No replacement runtime
  policy schema/parser was introduced. Reordered object keys remain accepted.
- R6: `FP_DEF_TEMPLATE` is no longer exempt from type/link checking. The unique
  target support-tools floorplan reference must match its resolved string value
  and exact rendered configuration rewrite. Object-valued, wrong-path,
  wrong-rewrite and missing-setting cases reject for that association.

Independent Python regression fixtures invoke a test-only Yojson serialization /
resealing mode (no validators) so float spelling and config pretty-printing cannot
mask the intended semantic contradiction. The focused B suite passed **54 OCaml
checks plus 27 independent mutation/control cases**. The existing runtime-policy
corpus passed **2,961 accepted / 1,253 rejected**. No broad regression was repeated.

The claim is deliberately **selected envelope structure/role/cross-links plus
exact retained bytes**, not revalidation as an A-resolved project, full base-SDC
semantic replay or authenticated production. Fully coherent newly asserted builds
remain outside source authentication. Existing unavailable/non-pass verdicts and
producer-assertion labels remain unchanged. Updated B handoff records the fixed
checks and schema-stable C recapture requirement after A-REAL-2.

## Final independent R5/R6 closure and C retained-audit inspection

2026-10-28. This section supersedes the earlier provisional R5/R6 disposition.
The reviewer did not implement B's correction. No B code/tests were edited; no
broad suite, EDA process, provider capture/selection, example build or Git mutation
was run. This document is the only repository edit in this final review task.

### Exact final review snapshot

| Reviewed artifact | SHA-256 |
| --- | --- |
| `execution/results/timing_intent_evidence.ml` | `74718f8df0e893894f339286c36520f1f7abd5d89aeae59ff7307eab02900a16` |
| `_build/default/bin/flow_cli.exe` | `f280fa1ff1084390028862de8a6e1762787677520ce42e332dc3f6d5dedfcb2e` |
| `_build/default/bin/experimental_timing_intent_inspect.exe` | `1c0ae619795b519cd133663855c4c40a0ebed0355f7d96ba5945ea81fcb636c0` |

These are the local final source/build bytes used for this review, not a claim
that this rebuilt executable is byte-identical to C's separately captured binary.

Only the necessary executables were rebuilt:

```sh
flock /tmp/opencode/asic-pt7-build.lock opam exec --switch=5.2.0+ox -- \
  dune build -j6 bin/flow_cli.exe bin/experimental_timing_intent_inspect.exe \
  test/timing_intent_evidence/check.exe
```

The focused script is `/tmp/opencode/pt7-evidence-final-closure.py`. It reuses only
the earlier independent fixture/rebinding/Yojson utility definitions, excluding
all previous probe invocations. It obtains fresh genuine ordinary-library full
manifest/SDC pairs from export-only fixture modes, independently mutates/reseals
the ordered manifest and actual config member hash, and invokes **only the public
CLI** for inspection. STA events/reports in these mutation fixtures remain
explicitly synthetic. The fallback bundle baseline identity was
`199f9b303ef49cc12e2c40e044d389cea84835ecbe85135930c484be7b912afe`.

Completed run and exact per-case inputs/stdout/stderr:
`/tmp/opencode/pt7-evidence-recheck-udpdr033/final-closure-results.json`.
Run again with `python3 -B /tmp/opencode/pt7-evidence-final-closure.py`; each run
uses a fresh temporary directory. Probes ran serially, with 10-second child CPU
and 15-second wall deadlines, no address-space cap and core dumps disabled.

### R5: absent versus explicit-null distinction — verified closed

Current source `required` (lines 6–9) distinguishes a missing configuration key
from a present null. Both generated and resolved setting comparisons use it
(lines 303 and 314). Independent public-CLI results:

| Exact mutation / control | Exit | Actual diagnostic or qualified result |
| --- | --- | --- |
| Generated `REVIEW_MISSING_KEY:null`, absent in configuration | 2 | `missing bundle configuration key: REVIEW_MISSING_KEY` |
| Generated `REVIEW_NULL:null`, configuration contains that key with null | 1 | valid / unavailable |
| Generated null, same configuration key present with string `not null` | 2 | `bundle generated/configuration mismatch` |
| Resolved `REVIEW_RESOLVED_NULL:null`, absent in configuration | 2 | `missing bundle configuration key: REVIEW_RESOLVED_NULL` |
| Resolved null, configuration contains the same key with null | 1 | valid / unavailable |

All affected configuration member hashes and receipt/source closure hashes were
correctly updated. The matching-null positives prove the fix does not simply
reject every null. The negative assertions require their exact semantic reason
and explicitly reject incidental hash/identity/process-binding errors.

### R6: simulation, runtime-policy and floorplan checks — verified closed

Current selected envelope validation checks the top's two supported simulation
source forms, calls the existing `Runtime_contract.policy_from_requested`, and
links the unique support-tools floorplan reference to the resolved string and
rendered configuration path. Independent public-CLI results:

| Exact mutation / control | Exit | Actual diagnostic or qualified result |
| --- | --- | --- |
| `simulation_sources:["constraints/top.sdc"]` | 2 | `bundle simulation RTL/top mismatch` |
| Existing manifest member `simulation/wrong.v` used as simulation RTL | 2 | `bundle simulation RTL/top mismatch` |
| Genuine separately emitted `simulation/<top>.v` bundle | 1 | valid / unavailable |
| Empty runtime policy `{}` | 2 | `invalid bundle runtime policy: malformed: object fields` |
| Runtime policy schema 999 | 2 | `invalid bundle runtime policy: contradictory or unsupported runtime policy` |
| Contradictory host Python version `3.12` | 2 | `invalid bundle runtime policy: contradictory or unsupported runtime policy` |
| Recursively reorder runtime-policy object keys, preserving array order/values | 1 | valid / unavailable |
| Resolved `FP_DEF_TEMPLATE` object instead of reference string | 2 | `bundle FP_DEF_TEMPLATE/floorplan reference mismatch` |
| Resolved floorplan string `wrong/template.def` | 2 | `bundle FP_DEF_TEMPLATE/floorplan reference mismatch` |
| Wrong rendered `dir::../tt/...` configuration rewrite, with consistent generated value/config hash | 2 | `bundle FP_DEF_TEMPLATE/floorplan reference mismatch` |
| Remove resolved `FP_DEF_TEMPLATE` setting | 2 | `missing bundle FP_DEF_TEMPLATE resolved setting` |
| Duplicate target `Floorplan_def` reference | 2 | `missing/ambiguous audit floorplan reference` |

The wrong simulation-top case includes that file in the sorted member inventory,
so rejection is the intended role/top check rather than a missing-file shortcut.
The wrong floorplan rewrite consistently updates generated/configuration facts
and the exact Yojson config hash, so it reaches the intended association check.
The genuine unchanged fallback bundle is also a valid/unavailable control. No
new R5/R6 acceptance bypass was observed in these exact repros and controls.

### C final retained native evidence: final public-reader compatibility verified

I read C's `docs/pt7_timing_final.md` and retained closeout receipt/summary. They
identify the user-specified final candidate:

- generation `74e9a52b43a14c69bff2763325b39522`;
- captured source SHA-256
  `a6723afb6a88bce6152d7b05662ea614a6e1a75352b870b4e20391e7c2d3f684`;
- renderer SHA-256
  `9c53a5b75313adacd979ea5b559fd17ad0c51d2961c4df6dc0a41813a88d25d2`.

Both retained audit directories were inspected through the final public CLI:

```sh
_build/default/bin/flow_cli.exe timing-intent-inspect \
  /home/wayne/devel/jane/hardcaml_asic_example/acceptance/timing/sta-bit-r3 --json
_build/default/bin/flow_cli.exe timing-intent-inspect \
  /home/wayne/devel/jane/hardcaml_asic_example/acceptance/timing/sta-scalar-r3 --json
```

Both exited **1**, with empty stderr and `verdict: unavailable`,
`resolved.status: producer_reported`, `applied.status: command_completed`, and
`native_coverage.status: unavailable`. The reader hash-checked and replayed the
retained audit closure; these commands did not rerun synthesis or STA and did not
modify C's evidence. Public output is retained in the final-review result tree.

This verifies that the final B corrections accept the actual C final retained
audit inputs without weakening their qualified verdict. C owns the native
execution/fixture acceptance. Its closeout reports successful bit/scalar
Pin->Term->internal-Net tracing, connectivity/tap controls and preserved
downstream setup/hold paths; the documented **negative hold slack remains a
violation**, not timing closure. Typical-corner standalone STA is not post-PNR,
all-corner, analog metastability, reset-protocol or Protemu qualification.

### Final actual disposition

**All exact R1–R6 review repros are now independently verified addressed.** This
last run contains **20 focused public-CLI calls: 13 intended semantic rejections
and seven valid/unavailable controls**, including C's two retained final native
audits. Every accepted result retained unavailable coverage; no passing native
coverage verdict was manufactured.

The remaining limits are deliberate: selected envelope structure/role/cross-links
and exact retained bytes, not re-elaboration of an A-resolved project, complete
base-SDC semantic reconstruction, authenticated execution, or exhaustive native
coverage. Earlier clock/technology policy mutation observations are within that
explicit limit and are not unchanged-build provenance breaks. Historical findings,
failed native attempts and B remediation notes remain intact. No further B code
change is requested for the reviewed R5/R6 repro closure.
