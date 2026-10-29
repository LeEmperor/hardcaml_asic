# PT.7c — independent native producer / schema-2 reader review

2026-10-28. Reviewer: **B**, the ordinary-flow integration owner, not the author
of A's producer/parser/evidence extension. This review covers
`lib/elaboration/timing_coverage_tcl.ml`, `execution/results/timing_native_coverage.ml`
and the schema-2 branch of `execution/results/timing_intent_evidence.ml`.
It does not duplicate A's review of B's flow integration. C's actual corrected
native acceptance remains a separate activity.

The main findings below describe the original native-v1 source snapshot. The
native-v2 follow-up at the end records independent rechecks after A's corrections;
old review cases and their original disposition are retained as history.

## Final disposition — native-v2 corrections

**A-NATIVE-R1 (including R1b), R2 and R3 are independently verified closed for the
bounded native-v2 contract in parser snapshot
`f141b57575d48c4c09678fea34aa499f1adfc797a20b0839c3269928fd9b9f07`.**
The current **256-probe suite passes**, and all six original saved R1b inputs
reject through the corrected pure/schema-2 APIs with the explicit LF-only error.
CR is rejected before tokenization, so neither a comment boundary, an unsupported
masker nor a hidden design selection can bypass parsing through CR/CRLF bytes.
Ordinary LF positives, exact-top checks, category framing and schema1 backward
semantics remain positive. No A source was edited by this reviewer.

The earlier High-severity R1b result against `aa8554bd…` and its failed review
attempts remain preserved below as history, not overwritten or relabelled.
The final LF-only closure section and the separate `pt7c-final-review.md` record
the current recheck and independent inspection of C's retained real native-v2 run.

This disposition does not qualify live native execution: C's final native-v2
capture remains separate. Overall exhaustive exception-effect coverage and timing
closure remain unavailable; source receipts remain unauthenticated assertions.

## Initial native-v1 disposition (historical)

**Changes requested before accepting the supported native interpretation claims.**
Independent probes reproduced three gaps:

| ID | Severity | Finding |
| --- | --- | --- |
| A-NATIVE-R1 | **High** | A continued Tcl comment can hide a false-path command from Tcl while the reader counts it as a matching stored relation. Reproduced through both the pure API and complete schema-2 inspection. |
| A-NATIVE-R2 | **Medium** | Diagnostic groups can be reassigned between categories without changing the complete raw check report; the reader accepts the forged category summary. |
| A-NATIVE-R3 | **Medium** | Schema 2 accepts native SDC selecting a different current design from the identity-verified bundle top while reporting matched stored exception scope. |

The overall verdict correctly remains `unavailable` in every accepted schema-2
probe. These findings concern the newly interpreted **subdimensions**, not an
accidental overall timing-closure pass. No A-owned source was edited.

## Independent method and exact repro entry points

New isolated review harness:

- `test/pt7c_native_review/consumer.ml`: thin calls to the public pure native reader,
  public schema-2 inspector and actual producer renderer.
- `test/pt7c_native_review/probe.py`: independent request/audit construction,
  Python Cartesian oracle, actual Tcl language counterexample, and a separate
  Tcl native-API model. It imports no A tests or parser implementation.
- A genuine newly emitted bundle comes from B's existing small emitter. Synthetic
  mapped events/native report bytes are constructed independently by the reviewer.

Executed:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/pt7c_native_review
```

**80 probes recorded**; expected positive/negative controls passed and the findings
below were observed. The harness intentionally records candidate outcomes rather
than asserting that their current incorrect acceptance is desired behavior.
No EDA, PDK/runtime discovery, Docker execution, installed-provider refresh or Git
mutation occurred. Tcl execution is `tclsh` over reviewer-created language/API
fixtures, not OpenSTA/OpenROAD. Dune used the existing `5.2.0+ox` switch, shared
ASIC lock and explicit `-j6`.

Retained output:

```
/tmp/opencode/pt7c-native-review-results.json
/tmp/opencode/pt7c-native-review-cases-es1v73mj/
```

Each candidate pure input is a JSON request; each schema-2 finding has a complete
retained synthetic audit directory with hash-consistent sources/receipts.
The results JSON contains their exact paths. From the ASIC checkout:

```sh
REVIEW=_build/default/test/pt7c_native_review/consumer.exe
CASES=/tmp/opencode/pt7c-native-review-cases-es1v73mj
"$REVIEW" native "$CASES/candidate-comment-hides-required-relation.json"
"$REVIEW" audit "$CASES/candidate-schema2-comment-hides-scope"
"$REVIEW" audit "$CASES/candidate-schema2-category-relabel"
"$REVIEW" audit "$CASES/candidate-native-current-design-mismatch"
```

These commands only inspect retained files. They return a JSON `ok` boolean and
the actual public-reader value/error. Current findings all return `ok:true`.

## A-NATIVE-R1 — continued comment creates false-positive stored scope

**High; blocks the correctness of the exact stored-scope interpretation.**

Location: `timing_native_coverage.ml:125–133`, especially the `'#'` branch at
line 131. It skips to the next physical newline without accounting for Tcl's
backslash-newline handling in comments. The later physical line is then parsed
as an executable command even though Tcl treats it as part of the comment.

Minimal native-state bytes (including final newline):

```tcl
# harmless-looking continued comment \
set_false_path -from [get_ports {ena}] -to [get_pins {u0/D}]
```

With resolved expectation `ena -> u0/D`, the pure reader returns:

```text
stored_exception_scope.status = matched
stored_exception_scope.relation_count = 1
```

The independent language check defines `get_ports`, `get_pins`, and
`set_false_path` as inert Tcl procedures, sources these exact bytes under
`tclsh`, and counts **zero** calls to `set_false_path`. This is a Tcl parsing
disagreement, not an inference about STA path effects or an English report parser.

The complete schema-2 repro retains the original emitted manifest/whole SDC,
producer/member, valid resolution/application block, receipt/version/process
records and diagnostics. Only the native-state report/source hash is changed.
It still returns `native_coverage.stored_exception_scope.status=matched` for the
commented-out relation. All outer source hashes/receipts remain consistent.

**Requested correction:** either reject continued native comments as unsupported
qualified grammar, or implement their correct continuation semantics. Keep the
nonexecuting parser. Add both the pure Tcl-language counterexample and a complete
schema-2 hash-consistent negative. Do not “fix” this by evaluating retained SDC.
The native writer need not normally emit this spelling for accepting it with the
wrong meaning to be a fail-closed parser defect.

## A-NATIVE-R2 — raw equality does not bind diagnostic category identity

**Medium; blocks treating raw/structured agreement as corroboration of category
assignment.**

Locations:

- Producer `timing_coverage_tcl.ml:47–69`: one-hot native calls and per-category
  `check_setup` calls are correct, but raw printer bytes are appended with no
  category boundaries.
- Reader `timing_native_coverage.ml:239–253`: reconstructs one undelimited
  concatenation of all groups, then compares it with the raw check report.

Repro starts with all seven ordered categories, one input-delay group, one
no-clock group, and the complete raw native-printer-style report. The mutation:

1. Move the first category's group to the adjacent initially empty
   `no_output_delay` category.
2. Set the corresponding group counts from `1/0` to `0/1`.
3. Leave **all raw report bytes unchanged**, including the completion marker.

The group/message/detail sequence across the concatenation is unchanged, so both
pure and full schema-2 readers accept it. The returned categories now falsely
claim no input-delay finding and an output-delay finding. This is not a request
to classify native English messages: the model independently knows which one-hot
native call returned the group, and the reader should preserve that association.

The full audit changes only `native_data` and its declared output hash; the
native check report, resolution/application log, producer member, receipt and
process context are unchanged. Thus this is a specific internal source-consistency
gap, not a demand for cryptographic authentication of all producer output.

**Requested correction:** retain unambiguous fixed per-category boundaries in
the raw check report (or separate category-specific raw sources), and validate
the same category association when reconstructing/comparing bytes. Preserve all
native message/detail bytes and ordering; do not replace this with English-message
classification. A producer-byte change must remain identity-covered and require
fresh C capture; old captured bytes must not be edited or relabelled.

## A-NATIVE-R3 — native design context is not associated with bundle top

**Medium; source/context association gap in schema-2 inspection.**

Locations: `timing_native_coverage.ml:208–209` validates only that a
`current_design` argument is a supported literal name. The schema-2 branch at
`timing_intent_evidence.ml:410–420` does not bind that name to the verified
manifest's `top_module`.

Repro keeps the genuine bundle, original input SDC, mapped stage/exception rows,
native diagnostic/endpoint sources and receipt/process context unchanged. The
native-state report is changed from:

```tcl
current_design tt_um_pt7_flow_fixture
set_false_path -from [get_ports {ena}] -to [get_pins {u0/D}]
```

to:

```tcl
current_design wrong_top
set_false_path -from [get_ports {ena}] -to [get_pins {u0/D}]
```

After updating the native-state source hash, complete schema-2 inspection accepts
the report as the original asserted build and reports one matched stored relation.
The port/pin spellings are relative to design context; matching anonymous strings
under another root does not establish the exact requested relation in the emitted
top. This is separate from the explicitly deferred equivalence of clock periods,
environment policy or timing closure.

**Requested correction:** expose/validate native design selection and bind it to
the schema-2 manifest top; reject a different or ambiguous selection. The pure
scope parser need not acquire a dependency on bundle rendering: it can return a
validated native context for the outer reader to cross-check. The actual writer
emits `current_design`, so omitted context should not silently establish a
build-associated native-state claim either.

## Controls and reviewed behavior that held

- **Split/merged Cartesian semantics:** two sources × two targets produce four
  relations. Split commands, duplicate unrestricted relations and nested selector
  lists agree. A two-pair zipped expectation rejects the merged Cartesian report.
  Exactly **65,536** expanded relations accept; **65,792** reject at the relation
  budget. This oracle is independently generated in Python.
- **Exact selectors/restrictions:** bit names accept; empty selectors, `*`, `?`,
  bracket classes/ranges and unsupported selectors reject. Setup-only, hold-only,
  rise/fall and through restrictions reject rather than being normalized to full
  min/max scope.
- **Unsupported masking:** disable timing, case analysis, clock groups, explicit
  min/max delays, reset-path and an unsupported inferred-clock-gating command all
  reject. These are in addition to the comment issue above, not a claim that any
  arbitrary clock/environment command is fully semantically validated.
- **Tcl nonexecution:** direct `exec`/`source`, nested executable queries, command
  separators and `eval` payloads reject. A sentinel file remains absent. There is
  no `eval`, Tcl subprocess or runtime launch in the production reader.
- **Diagnostic/raw completeness:** missing categories/counts, removed details,
  extra raw findings, missing completion, duplicate JSON keys and a forged
  precomputed summary reject. Raw equality preserves message/detail bytes but has
  the category-binding limitation R2.
- **Endpoint/record bounds:** 65,536 endpoints accept and 65,537 reject;
  65,536 total diagnostic message/details accept and 65,537 reject. Truncated or
  different endpoint reports reject; escaped newline/quote/backslash names retain
  their JSON identity. Deep SDC nesting and a missing final newline reject.
- **Actual producer against independent Tcl API model:** all seven exact diagonal
  one-hot vectors and the public printer category sequence are checked. Multiple
  groups within a category, multiple finding categories, multiline/Unicode detail
  strings and deduplicated endpoints round-trip. A supplementary-plane Unicode
  endpoint is preserved. Native-API/printer failure, an empty native group,
  diagnostic-record overflow, endpoint/string overflow and existing output files
  all produce no native completion marker.
- **Schema-2 source association:** changed whole-SDC/member bytes, wrong retained
  producer bytes, wrong data profile, audit/receipt corner disagreement, symlinked
  native sources, an asserted nonzero process despite completion, and an injected
  precomputed coverage summary all reject. Coherent audit/receipt wrong-build or
  wrong-stage claims, unrelated tool names, hash-consistent extra native scope,
  and omission of a required native role reject. The native producer is a receipt input;
  native files are required singleton roles and hash-checked before interpretation.
  Schema 2 does not call current Tcl/producer renderers during inspection.

### Characterizations, not additional blockers

- An explicitly coherent `producer.version=unqualified-99.0` with matching retained
  version bytes is accepted by the standalone schema-2 reader. A's handoff says
  native engine qualification is separate; B's ordinary-flow binding separately
  restricts the qualified image/OpenSTA version. This review does not treat the
  version-agnostic standalone decoder as qualification of another native tool.
- A self-consistent empty endpoint data/report pair accepts despite synthetic
  mapped-stage rows. Counts/completion/raw equality cannot independently prove the
  producer enumerated the whole linked graph. That remains a retained producer
  assertion, not independent netlist/Liberty reanalysis or authenticated execution.
  Cross-checking known mapped endpoint minima could strengthen this later, but is
  not substituted for native API qualification here.
- Forging every producer source, manifest, log and receipt consistently remains
  outside execution authentication. The three findings above are narrower parser
  meaning/internal association gaps detectable without authenticating execution.

## Reviewed source receipt

SHA-256 of the reviewed source (also matched after the independent probes):

```text
78e85d7503c8bc06714dbf9d1cf12838aee8ca5e1a2ce396d22ca5b4334e88a0  lib/elaboration/timing_coverage_tcl.ml
7d3c063bdd2bc8b8f53185e18c7a7a7a991f59f63e64338ec99322e63ca5b5a5  execution/results/timing_native_coverage.ml
239aa627858d1148d482b079a027c33128d7667c9f262a34ace93901d9fdca68  execution/results/timing_intent_evidence.ml
e6432f22b6acb119949e11bf6fb363d8e52a8a830a3f3b60fb172711a2895fdd  lib/elaboration/bundle.ml
```

The probe fixture's tool results, netlist and libraries are synthetic and labelled
as such. This report adds no native acceptance, P&R, timing closure, analog CDC,
reset-release or authenticated execution claim. B did not alter A's source, C's
retained attempts, provider selection or any Workbench/Protemu files.

## Follow-up — A's native-v2 corrections independently rechecked

After reading the active native-v2 handoff, B adapted only its own review adapter
and fixtures: mandatory expected `top`, native-data schema/profile 2, leading
native design selection, category-framed raw checks and V2 hook completion.
No A source was edited. The original native-v1 finding directories above remain
unchanged; they are not relabelled as native-v2 evidence or expected to pass the
new decoder. Historical native-v1 inspection requires its historical provider.

Re-executed the same isolated review command with **80 independent probes**.
Current results are retained separately at:

```
/tmp/opencode/pt7c-native-review-cases-wj1ia8ga/results.json
```

The result file explicitly labels the profile as `opensta-2.7-native-state-v2`.
Fresh repro inputs/audits are in that directory; the common latest-results JSON
also points to it. The three original counterexamples now reject for the intended
semantic diagnostics:

| Finding | Current independent result |
| --- | --- |
| A-NATIVE-R1 | Pure and complete schema-2 cases reject: `continued native SDC comment is unsupported`. Both now have the required correct leading design, so rejection is not an incidental missing-top error. The independent Tcl oracle still executes zero false-path calls. |
| A-NATIVE-R2 | Pure and complete schema-2 category reassignment rejects: `native check report differs from diagnostic groups`. The unchanged raw source now contains the original category boundaries. |
| A-NATIVE-R3 | Complete schema-2 wrong-top case rejects: `native current_design differs from manifest top`. |

Cartesian, masking/nonexecution, bounds, source-association and actual emitted
producer/API-model controls remain successful. Multiple groups/multiline Unicode
details and a supplementary-plane endpoint round-trip under the V2 producer.
Self-consistent empty endpoint assertions and standalone tool-version qualification
retain the previously documented limits; no additional proof is inferred.

**At that 80-probe follow-up, the three original counterexamples rejected.**
The later final review below adds the still-open R1b boundary case; the earlier
observation is not a claim that all native-v2 comment spellings are sound.
Fresh real native qualification of A's changed emitted member and
B's separately corrected consumed-source association still belongs to C's new
capture. Overall exhaustive coverage/timing-closure limitations are unchanged.

## Final independent verification — asserted corrections, compatibility and R1b

The final review updates only B-owned review code and this report. No A source
or captured C evidence was changed. The initial native-v1 findings and repros
remain preserved above; they are not retroactively relabelled as native-v2.

### R1: actual Tcl parity, conservative qualified-grammar rejection

The real `tclsh` oracle sources exact LF and CRLF fixture bytes with inert
`current_design`, object-query and false-path procedures. For **0–6 terminal
backslashes**, each of leading, indented and semicolon-following comments is
checked independently:

| Terminal backslash count | Actual Tcl: following false path | Native-v2 reader |
| --- | --- | --- |
| 0 | Executed once | Accepts ordinary comment |
| 1, 3, 5 | Hidden by comment continuation; zero calls | Rejects continued comment |
| 2, 4, 6 | Executed once; the newline is not continued | Rejects as unsupported qualified grammar |

Thus **even backslashes do not hide the next Tcl command**. The fix conservatively
rejects all terminal-backslash comment spellings; the review does not call every
such spelling a continuation in true Tcl semantics. This is a documented subset
restriction, not a false-positive stored-scope match. It needs no Tcl evaluation
inside the production reader.

Additional assertions cover a backslash followed by space/tab/text (ordinary
noncontinued comments remain accepted), quoted/braced backslash-newline parity,
and comment-like/false-path text inside literal values (never counted as a stored
relation). Native-writer command continuations without a preceding space remain
accepted. Both pure and complete schema-2 versions of the original hidden-scope
counterexample reject on the intended continued-comment diagnostic.

#### A-NATIVE-R1b — historical High finding: bare CR hides scope/masking

This finding was open against `aa8554bd…` and is now closed by the LF-only
pre-tokenization guard in `f141b575…`; see the final closure section below.

The additional oracle uses a **bare CR byte**, not an escaped backslash-`r` value
and not the already-tested CRLF pair. `tclsh source` treats that byte as a line
ending. The native parser's `'#'` branch at
`timing_native_coverage.ml:131–137` instead scans only to LF; embedded CR is skipped
as comment content. Outside comments, the parser also classifies CR as whitespace
at line 50. This is a remaining source-language disagreement.

Exact extra-scope bytes, where `<CR>` denotes byte `0x0d`:

```text
current_design top<LF>
# ordinary comment<CR>set_false_path -from [get_ports {ena}] -to [get_pins {u1/D}]<LF>
set_false_path -from [get_ports {ena}] -to [get_pins {u0/D}]<LF>
```

The independent real Tcl oracle executes **two** false paths. Given the one
requested relation `ena -> u0/D`, the pure reader nevertheless returns
`stored_exception_scope.status=matched` and `relation_count=1`: it ignored the
extra downstream exception. The corresponding complete schema-2 audit has the
correct leading manifest top, unchanged emitted input SDC and manifest identity,
valid receipt/process/version/wire records, and rehashed native output sources.
It is also accepted with one matched relation and overall verdict unavailable.

The second repro substitutes the observed native-style masking command after CR:

```text
# ordinary comment<CR>set_disable_timing -from {CLK} -to {Q} [get_cells {u0}]<LF>
```

The Tcl oracle counts **one disable command and one false path**. Pure and full
schema-2 readers accept it. An LF-only control exposing the exact same disable
command correctly rejects with `unsupported native SDC command: set_disable_timing`;
thus the acceptance is the comment boundary, not a permitted masking command.

The third variant uses `current_design wrong_top` after the bare CR. The real Tcl
oracle records **two selections with final design `wrong_top`**, whereas pure and
full-schema2 inspection accept and return the original expected `native_design`.
The same command exposed with LF rejects as repeated/ambiguous selection. This
is a cross-cutting lexer bypass of R3, not a failure of its direct name comparison.

Fresh retained, hash-consistent repros:

```
/tmp/opencode/pt7c-native-review-cases-agrom8uq/results.json
/tmp/opencode/pt7c-native-review-cases-agrom8uq/candidate-bare-CR-extra-scope.json
/tmp/opencode/pt7c-native-review-cases-agrom8uq/candidate-bare-CR-masking.json
/tmp/opencode/pt7c-native-review-cases-agrom8uq/candidate-bare-CR-design-selection.json
/tmp/opencode/pt7c-native-review-cases-agrom8uq/candidate-schema2-bare-CR-extra-scope/
/tmp/opencode/pt7c-native-review-cases-agrom8uq/candidate-schema2-bare-CR-masking/
/tmp/opencode/pt7c-native-review-cases-agrom8uq/candidate-schema2-bare-CR-design-selection/
```

Use the same review consumer's `native` / `audit` commands documented above.
`probe.py` records the exact oracle counts, preserves these cases, and asserts
that no such required-to-reject cases remain accepted **after writing results**.
The targeted Dune review therefore currently exits nonzero specifically for R1b.

**Required correction:** reject bare-CR native SDC as unsupported qualified
serialization, or normalize/interpret source-channel line endings faithfully
before lexical decisions. Keep hashing the original bytes and keep the reader
nonexecuting. Add the extra-relation, masking and design-selection variants, with LF/CRLF
positive controls and correct top/profile/receipt context so rejection cannot be
an incidental malformed envelope. The native writer's normal LF output need not
change; accepting adversarial unsupported spelling with the wrong meaning is the
defect. This is not an observed error in C's genuine LF-format native output.

### R2: category framing cannot be spoofed through accepted diagnostic strings

Independently exercised both sides of the new boundary:

- In the pure reader, fixed-header/category-begin/category-end/final/hook markers,
  including the old V1 hook marker, are injected into messages and details at
  line start, after space/tab/CR, and after an embedded LF followed by whitespace.
  Every case rejects with `diagnostic contains reserved marker line`, even when
  the forged structured data and raw printable bytes otherwise agree.
- JSON-escaped marker text (`\u0048C_ASIC_NATIVE_...`) is decoded and rejected;
  encoding does not bypass the line-prefix check.
- The **actual emitted producer** runs against an independent Tcl API model that
  returns the same injected native message/detail strings. Every marker injection
  fails before completed native data is written and emits no V2 completion marker.
- Category reassignment with unchanged raw bytes, missing/duplicate/misnamed
  category boundaries and missing final framing reject. Complete schema-2
  category reassignment is a hash-consistent intended-diagnostic negative.
- Marker words in the middle of ordinary text and a literal backslash-`n` sequence
  remain valid. These round-trip through both the reader and actual producer;
  they do not create a new raw LF boundary or undergo a second substitution.

The scope is **unambiguous category framing**, not authentication of arbitrary
producer output or a promise that human-readable diagnostic printing alone proves
all internal native group structure. English messages are not used for category
classification. A fully coherently forged collection of producer sources remains
outside execution authentication.

### R3: native top is exact and design selection is unique and leading

Pure and full schema-2 assertions reject wrong/prefix/case-mismatched design names,
missing or later selection, repeated selection of the same top, and selection of
another top after the correct one. No top is inferred from relative pin names.
The schema-2 expected top comes from the identity-verified manifest.

Ordinary leading comments/whitespace and braced/quoted **exactly equal** literal
top spellings remain positive. The supported zero-argument `[current_design]`
base query remains positive; a query with a design-changing argument rejects.
Successful schema-2 controls explicitly assert the returned `native_design` equals
the manifest top.

### Explicit native-v1 rejection and schema1 backward behavior

New independently built, fully hash-consistent controls establish each boundary:

- Pure native-data/profile 1 with otherwise matching scope and old complete raw
  reports rejects with the explicit legacy/recapture diagnostic.
- Outer audit schema2 with a legacy native producer declaration, matching retained
  member/hash, receipt/input closure, V1 data/raw reports and V1 log completion
  rejects explicitly for the unsupported producer profile. This is not an
  incidental missing-role, changed-hash or wrong-top rejection.
- V1 native data under a V2 manifest, a V1 hook marker under V2 data, and undelimited
  V1 raw checks merely relabelled by V2 JSON fields each reject. Field relabelling
  cannot qualify old category evidence.
- **Audit schema1** remains positive with a legacy-v1 optional native declaration,
  a v2 optional declaration, or no native declaration. It returns native coverage
  unavailable and retains the old uninterpreted unconstrained semantics.
- A schema1 SDC modification with its member hash, manifest identity, receipt and
  build context coherently resealed still rejects on **current serializer suffix
  replay**. Schema1 was not silently switched to schema2's no-rerender rule.

These schema1 positives use genuine emitted current-SDC bytes. They demonstrate
unchanged schema1 behavior, not stable replay of every older renderer version.
Inspection also accepts a hash-consistent retained driver containing an inertly
stored `exec touch <sentinel>` line while leaving the sentinel absent: retained
Tcl is not executed by source inspection. That is a nonexecution control, not
authentication that such a driver produced the asserted logs.

### Commands and results before the LF-only correction (historical)

Targeted review:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/pt7c_native_review
```

Then **one forced integration regression**, justified by the native-v2 wire /
mandatory-top change crossing the library, evidence reader, public result path
and archive boundary:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 --force @install @test/pt7c_native_review/runtest \
  @test/timing_intent/runtest @test/timing_intent_evidence/runtest \
  @test/timing_native_coverage/runtest @test/timing_intent_flow/runtest \
  @test/ocaml-collect @test/ocaml-report @test/ocaml-archive @test/flow-cli \
  @test/ocaml-coarse-run @test/ocaml-preflight
```

The forced integration run passed the following groups **before** the later
bare-CR extension. It was run once, not repeated or relabelled after discovering
R1b:

- **248 independent review probes**, including the new asserted correction matrix.
- Library timing intent: **34 negatives**; emitted Tcl **8 positives / 41
  resolve-before-apply negatives**, application-failure/escaping controls and
  literal-pattern/native-boundary models.
- A native-v2 reader: **120 checks**, actual producer API model and independent
  Tcl comment-language controls.
- Existing timing evidence: **54 checks + 27 review regressions**; large-log RSS
  remains below the recorded baseline +32 MiB bound.
- B flow: **150 orchestration/replay checks + 11 Tcl startup checks**.
- Legacy collection **131** differentials, report **585**, archive **16**,
  coarse **15** record/outcome differentials plus aggregate/cancellation controls,
  preflight **24** differentials plus **72** publication/cancellation cases, and CLI
  regression groups. These are heterogeneous groups, not one additive count.
- `@install` packaging builds. One optional historical retained-finalization
  fixture remains unavailable and was not counted as passed.

The forced run's immutable review results/repro directory is:

```
/tmp/opencode/pt7c-native-review-cases-o6r61rqq/results.json
```

The subsequent targeted review, using the same targeted command above, records
**256 probes** and fails on six accepted R1b cases (pure/full-schema2 ×
extra-scope/masking/design-selection). Its remaining correction, framing, legacy and model controls
complete successfully. `/tmp/opencode/pt7c-native-review-results.json` is the
latest-results convenience copy and now identifies those open findings; its
immutable case directory is `pt7c-native-review-cases-agrom8uq`, listed above.
Earlier review case directories remain intact. All runs used the existing
switch, shared lock and explicit `-j6`; no EDA or provider operation was performed.

### Reviewed native-v2 source receipt before the LF-only correction

```text
4240095a12a44c9f30a085b5713f7db3dfcc02967a9dfb2efdba5818c096e33a  lib/elaboration/timing_coverage_tcl.ml
aa8554bd945d1877ae36f6148371cac5ba909de6a5c1c58e849b68a2dcb0e0c3  execution/results/timing_native_coverage.ml
2fe9015335a631d4d4697c6a325d54a992e8ac2912c760a226a0dbd82a637c55  execution/results/timing_intent_evidence.ml
e6432f22b6acb119949e11bf6fb363d8e52a8a830a3f3b60fb172711a2895fdd  lib/elaboration/bundle.ml
```

**Historical recommendation before the LF-only correction: changes requested for
R1b.** The R2 category-frame and
direct R3 exact-top corrections pass their independent checks, as do R1's
backslash-parity controls. Do not close comment/source-boundary or complete
design-selection safety until bare CR is rejected or handled correctly. C's
actual native-v2 capture must independently
qualify execution and its exact retained products. No additional native coverage,
clock/environment policy equivalence, graph completeness, authenticated execution,
post-PNR preservation, CDC/reset adequacy or timing closure is inferred here.

## Final R1b closure — LF-only guard independently verified

The reviewed parser now rejects **any CR byte before tokenization**. Its exact
source SHA-256 is:

```text
f141b57575d48c4c09678fea34aa499f1adfc797a20b0839c3269928fd9b9f07  execution/results/timing_native_coverage.ml
```

Only B-owned expected outcomes were updated to the announced LF-only policy.
The real Tcl oracle is unchanged: it still establishes that CRLF is a valid Tcl
source-channel newline, that odd comment backslash counts hide the following
command, and that even counts do not. **All CRLF native-state variants now reject
as unsupported serialization**, including ordinary comments; this is deliberate
qualified-grammar rejection, not a claim about Tcl language invalidity. LF ordinary
comments, quoted/braced LF continuations, native-writer LF command continuations
and all other previously asserted truthful LF positives remain valid.

Executed only the targeted review/build needed for the current read-only helpers:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 @test/pt7c_native_review/runtest bin/flow_cli.exe \
  bin/experimental_timing_intent_inspect.exe bin/experimental_collect.exe \
  bin/experimental_report.exe bin/experimental_archive.exe
```

**256 probes pass**, with `open_findings=[]`. Final targeted results are retained
at `/tmp/opencode/pt7c-native-review-cases-bwzx1a4p/results.json`.
The original, unchanged `agrom8uq` pure inputs and complete hash-consistent audit
directories were additionally invoked through the corrected APIs: all three
variants × two APIs return `Error ... qualified serialization is LF-only`.
They are not merely regenerated equivalents or incidental envelope/hash failures.

The independent actual-evidence review then verified C's original LF native run
using both the current helper and C's separately captured corrected reader,
including source-hidden archive replay. See `pt7c-final-review.md`. The original
execution provider remains the original execution identity; the newer parser is
not retrospectively attributed to that run.

**Final disposition: no remaining blocker from R1/R1b/R2/R3 in this corrected
reader snapshot.** No EDA, provider mutation or C evidence edit occurred. No broad
regression was repeated for this final reader-only recheck. The prior forced
integration result remains its separately recorded earlier result. Native stored
scope/diagnostic interpretation remains distinct from exhaustive exception effect,
authenticated execution, reset/CDC adequacy and timing closure.
