# PT.7c A — native producer / reader handoff

## ACTIVE correction contract — native version 2 (review R1/R2/R3)

**Reader-only R1b correction:** qualified native SDC is now strictly LF-only.
Any CR byte rejects before lexical handling, including bare CR, CRLF and CR in
comments/quotes/braces. Producer, native profile/data schema 2, bundle member bytes,
runtime and outer schemas are unchanged. Existing genuine LF native-v2 evidence
is reusable byte-for-byte: capture the corrected reader provider and replay it;
no fresh EDA or native producer recapture is required for this reader-only change.

Published before correction integration, 2026-10-28. **B/C must use fresh capture.**
The version-1 contract below is historical; these version-2 changes supersede it:

- Producer `profile = "opensta-2.7-native-state-v2"`; manifest native declaration
  uses `schema:2` and that profile (same contract/path). Native data uses `schema:2`
  and that profile. Outer audit remains schema 2; receipt/event schemas remain 1.
- `Timing_native_coverage.inspect` adds mandatory `top:string`. The outer
  `Timing_intent_evidence` reader passes the identity-verified manifest top.
  Native SDC requires exactly one **leading** `current_design <literal top>`;
  missing, wrong, repeated or later design selection rejects.
- Raw check report starts with exactly
  `HC_ASIC_NATIVE_CHECKS_V2 opensta-2.7-native-state-v2`, then for each of the seven
  categories, in order, `HC_ASIC_NATIVE_CATEGORY_BEGIN <name>`, the unchanged
  native printer bytes, and `HC_ASIC_NATIVE_CATEGORY_END <name>`. It ends with
  `HC_ASIC_NATIVE_CHECKS_V2_COMPLETE`. Every marker occupies one LF-terminated line.
  Native diagnostic strings containing a reserved `HC_ASIC_NATIVE_` line prefix
  (including after leading space/tab/CR) reject as unsupported ambiguity, so marker
  injection cannot simulate another grouping. No English-message classification.
- Log producer completion is now `HC_ASIC_NATIVE_V2_COMPLETE`. Endpoint report
  spelling is unchanged, but is bound to native data/profile 2.
- Continued comments in retained native SDC reject as unsupported qualified Tcl
  grammar. Ordinary comment lines still accept; they cannot reveal a command
  which Tcl would treat as commented out. Independent `tclsh` controls are required.
  CR/CRLF are unconditionally unsupported (see reader-only R1b note above), never
  treated as whitespace or ignored comment content.
- Schema2 audits carrying native-v1 manifest/data/producers are **unsupported**,
  never relabelled as native-v2 or granted category-bound coverage. Inspection
  returns an explicit error requiring recapture. Audit-schema1 native-v1 optional
  manifest declarations retain their original ignored-native / SDC-replay semantics.
  No current renderer equality is added to schema2 inspection.

B integration action: accept manifest declaration schema/profile 2 and consume the
V2 completion marker in any generated/fixture logs; invoke the same producer proc
and retain the same five native roles. B-owned independent native-review adapters
calling the pure reader must pass the expected top explicitly. No B source is
edited by A. C must recapture changed producer/member/build identity and native
reports; do not patch or overwrite old captured evidence.

Implementation/check status for this correction is recorded in the final section.

## Historical version-1 handoff and earlier corrections (superseded)

2026-10-28. Published before implementation. B owns runtime/coarse/CLI integration;
C owns real native qualification. This contract does not qualify native execution.

## Concrete API / bundle seam

```ocaml
Hardcaml_asic.Elaboration.Timing_coverage_tcl.contract : string
Hardcaml_asic.Elaboration.Timing_coverage_tcl.profile : string
Hardcaml_asic.Elaboration.Timing_coverage_tcl.path : string
Hardcaml_asic.Elaboration.Timing_coverage_tcl.render : unit -> string
Hardcaml_asic.Elaboration.Timing_coverage_tcl.manifest : unit -> Yojson.Safe.t

Hardcaml_asic_execution.Timing_native_coverage.inspect :
  resolved:Evidence_json.t list -> native_sdc:string -> native_data:string ->
  native_checks:string -> native_endpoints:string ->
  (Evidence_json.t, string) result
Hardcaml_asic_execution.Timing_intent_evidence.inspect :
  directory:string -> unit -> (Evidence_json.t, string) result
```

Timing-intent bundles add identity-covered member
`constraints/pt7-native-coverage.tcl` and top-level manifest field
`timing_native_coverage` (the existing `timing_intent` schema/wire is unchanged):

```json
{"contract":"hardcaml-asic.timing-native-coverage","schema":1,
 "profile":"opensta-2.7-native-state-v1",
 "producer":"constraints/pt7-native-coverage.tcl"}
```

Producer bytes are generic native introspection, emitted only when resolved timing
intent exists. They do not re-resolve or rerender the design. No legacy member.
After loading the exact retained SDC ONCE, B sources the retained producer and calls:

```tcl
source constraints/pt7-native-coverage.tcl
::hc_pt7_native::write $output_directory
```

It writes four files (directory must already exist): `native-state.sdc`,
`native-data.json`, `native-checks.rpt`, `native-endpoints.rpt`. It prints exactly
`HC_ASIC_NATIVE_V1_COMPLETE` only after successful collection and output close.
No command overrides, report_exceptions, graph inventory or timing-path census.
B must catch producer failures AND check enclosing native process/step completion;
the hook marker alone is insufficient. Preserve stdout/stderr and failed attempts.

## Native wire, version 1

`native-data.json` has exactly:

```json
{"schema":1,"contract":"hardcaml-asic.timing-native-coverage",
 "profile":"opensta-2.7-native-state-v1","complete":true,
 "categories":[{"name":"no_input_delay","group_count":0,"groups":[]}],
 "endpoint_count":0,"endpoints":[]}
```

All seven categories, in order: `no_input_delay`, `no_output_delay`,
`multiple_clock`, `no_clock`, `unconstrained_endpoints`, `loops`,
`generated_clocks`. Each group is exactly `{message:string, details:string[]}`.
Messages/details are native strings, NOT English-inferred classifications.
Groups and details retain native order; endpoints are exact native full names,
sorted unique. `native-checks.rpt` is the complete public native
`check_setup -verbose -<category>` output for each category in the declared order
plus a final `HC_ASIC_NATIVE_CHECKS_COMPLETE` line. Reader reconstructs its full
pre-marker bytes from groups, checking native printing equality (category engine
order). `native-endpoints.rpt` is one JSON string per endpoint followed by
`HC_ASIC_NATIVE_ENDPOINTS_COMPLETE`; this is lossless for names with newlines.
The data and reports each have explicit completion even when there are no findings.

`write_sdc -no_timestamp -digits 12` uses native mode, no hierarchy mapping.
Reader interprets a bounded nonexecuting subset of native serialization: exact
get_ports/get_pins selectors and list combinations in false paths. Relations
normalize Cartesian source/target scopes, min/max and transitions. Split/merged
unrestricted relations compare semantically; restricted setup/hold/transition
forms are rejected, even when split restrictions could cover the same relation.
Nonexception base commands have a narrow explicit allowlist. Masking/unknown
constructs reject. No eval, subprocess, current producer/SDC rerender or source Tcl
execution occurs in inspection.

## Schema 2 audit additions for B

Same audit kind, scope, stage and envelope as schema 1; set `audit.schema = 2`.
Existing required roles remain. Add required singleton roles:

| role | retained bytes |
| --- | --- |
| `native_producer` | exact bundle producer member |
| `native_sdc` | `native-state.sdc` |
| `native_data` | `native-data.json` |
| `native_checks` | `native-checks.rpt` |
| `native_endpoints` | `native-endpoints.rpt` |

`native_producer` joins receipt input roles (same source-array order); all other
receipt/process schemas stay 1. Existing `exceptions`/`unconstrained` may retain
native state/check reports as separate copied files (paths must remain unique).
The receipt/log, complete SDC/member, producer/member, manifest identity, native
version, process and all sources remain hash-bound. Tool spelling remains OpenSTA
for standalone; schema2 also permits OpenROAD with its retained exact native
version (native engine API profile qualification is separate).

Schema2 validates the retained producer's manifest contract/profile/member/hash;
it MUST NOT compare producer or SDC bytes to the current renderers. Existing
requested/resolved/applied event schema1 semantic/order validation remains. Native
state is compared to that exact validated resolution. Manifest extension is
optional for schema1 bundles; schema1 keeps its current SDC suffix replay.

Schema2 output adds interpreted `native_coverage` dimensions and diagnostic /
endpoint inventories; overall `verdict` remains `unavailable`. Matched native
stored scope is NOT exhaustive exception effect, CDC approval or timing closure.
Raw downstream reports remain retained, uninterpreted witnesses. B can bind this
standalone per-corner audit to its separate ordinary-flow association contract.

## Bounds / qualification

Native files <= 8 MiB each (producer <= 1 MiB); <= 65,536 logical SDC commands,
<= 65,536 endpoints, <= 65,536 total groups/details, individual native strings <=
64 KiB; <= 65,536 expanded relations. Existing audit total/source/log bounds apply.
SDC has <= 262,144 tokens and nesting <= 16; native JSON structural punctuation
has a 524,288-token / depth-16 preallocation bound. Endpoint report line count is
checked before splitting, preventing blank-line amplification. Native SDC requires
a final newline and forbids NUL. These are rejection bounds, not truncation rules.
Missing/extra/broad/restricted/unsupported state is invalid evidence, not zero
findings. Schema1 still has no interpreted native coverage result.

C must confirm the actual
serializer grammar, native report bytes and API behavior on allocated real probes;
pure A fixtures are not native acceptance.

## Implemented integration — ready for B/C qualification

Implemented all published APIs and the schema2 additions. New producer/member
emission is conditional on resolved timing intent. No existing SDC serializer,
timing-intent schema, stage registration or normal base-SDC policy was changed.
The producer is generic; the resolved intent determines its inclusion and build
identity. Inspection executes no Tcl and does not call either current renderer
for schema2. Schema1 continues to call its original current-SDC suffix replay.

`native_coverage` output is exactly:

```text
status: interpreted_supported_dimensions
profile: opensta-2.7-native-state-v1
stored_exception_scope:
  status: matched
  method: native_write_sdc
  relation_count: <unique relation count>
  relations: [{source,target,min_max:"both",source_transition:"both",target_transition:"both"}]
diagnostics: {status:"complete_returned_native_groups",categories:<native categories>}
endpoints: {status:"complete_native_inventory",count:<n>,pins:[<exact names>]}
per_check_analysis: unavailable
exhaustive_exception_effect: unavailable
timing_closure: not_established
```

The enclosing schema2 evidence `verdict` remains `unavailable`. `requested`,
`resolved.status=producer_reported`, `applied.status=command_completed`, process,
source authentication and downstream limitations remain separate. The schema2
`unconstrained` field exposes the same diagnostics and endpoints with
`coverage=unavailable`; a finding is not a process failure or a fabricated
per-path classification. The existing sources array retains all raw references.

### Parser's exact supported subset

False paths require exactly one `-from` and one `-to`, in either order. Source
selectors are `get_ports`, target selectors `get_pins`; selector lists support
native `[list [get_... ...] ...]` and simple space-separated literal name lists.
Names support ASCII alphanumeric, `_ / . : $` and decimal bracketed bus indices;
arbitrary escaped identifiers, wildcard/class selectors, general Tcl lists,
compound words, variables, unknown queries and general scripts reject. Braces,
simple quoted/bare words, qualified backslash escapes and line continuations are
parsed without evaluation. Outside braces/quotes, backslash-newline plus
indentation separates words even without a preceding space (the actual native
`set_false_path\` newline form); inside braces/quotes it folds to a space within
the word. Bare newlines/semicolons inside queries reject, rather than being
flattened into a guessed single command. Equivalent unrestricted split/merged/duplicate
relations normalize to the same set; merging multiple sources/targets expands the
actual Cartesian relation, never a guessed pairwise relation. Setup/hold/rise/fall
restrictions reject even when multiple restricted commands could cover both.

Nonexception allowlist: `current_design`, `create_clock`,
`set_clock_uncertainty`, `set_clock_latency`, `set_clock_transition`,
`set_input_delay`, `set_output_delay`, `set_driving_cell`, `set_load`,
`set_input_transition`, `set_operating_conditions`, `set_max_transition`,
`set_max_fanout`, `set_max_capacitance`, `set_min_capacitance`, `set_voltage`,
`set_units`, `set_wire_load_mode`, `set_wire_load_model`,
`set_wire_load_selection_group`, `set_port_fanout_number`, `set_drive`,
`set_resistance`. Top-level `current_design` requires one literal supported design
name; the zero-argument `[current_design]` query is also supported, including the
observed `set_max_fanout ... [current_design]` baseline. Query arguments, nested
scripts or multiple commands are not supported.

Additionally, `set_timing_derate -early FACTOR` and
`set_timing_derate -late FACTOR` accept exactly these global two-argument forms.
FACTOR must be a finite, positive decimal literal, with early <= 1 and late >= 1.
Zero, negative, nonfinite, overflow, wrong-direction, scoped-object,
incremental/check-type/other-option, extra/missing-argument and substituted-value
forms reject. This qualifies the actual native 0.949999988079 / 1.049999952316
baseline without adding a general derate command allowlist entry.

Only literal values, list construction and basic object queries are accepted
within the other allowlisted commands. This does not certify base-clock/environment
policy equivalence. All other commands (including disables, case analysis, clock
groups, min/max path delays and arbitrary `set`) reject. C must report any native
serializer addition rather than stripping it or silently extending acceptance.

### Verification

First A execution-library build/test attempts encountered B's in-progress
`Timing_intent_flow.publish` interface mismatch (implementation has final `unit`
argument, interface initially omitted it). B subsequently corrected its interface;
no B-owned file was changed by A. Final checks passed:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/timing_native_coverage
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/timing_intent_evidence test/timing_intent
```

- **60 pure native reader/schema checks**, including genuine deterministic bundle
  member/contract/hash emission; scalar/bit exact scopes; truthful split/merged/
  Cartesian positives; missing/extra/broad/restricted/unsupported state; disable,
  case analysis, clock groups and min-delay masking negatives; nonexecuting nested
  script rejection; bounds/truncation/JSON and all-seven-category controls.
- Schema2 positive uses different retained historical SDC and producer bytes,
  correctly resealed to the emitted envelope. It is accepted without current
  renderer equality. Schema1 current replay passes; historical-SDC mismatch still
  rejects. Native member/hash, missing report, completion/order and scope negatives
  reject for their intended diagnostics.
- Actual emitted Tcl runs against a **modeled native API**: JSON escaping and
  Unicode, deduplicated endpoints, independent raw/structured agreement, output
  collision rejection, deliberate native failure and endpoint/string budget
  failures, with no completion on failure. This is not EDA/native acceptance.
- Existing evidence suite: **54 checks + 27 independent review regressions**.
  Existing timing suite: **34 library negatives**, **8 Tcl positives / 41
  resolve-before-apply negatives**, application failure and literal-name/native
  boundary checks. Large-log regression remains within its RSS bound.
- `git diff --check` passed. No EDA, Git mutation, histories/provider selection or
  Protemu/Workbench work was performed by A.

### Source receipt (SHA-256)

```text
78e85d7503c8bc06714dbf9d1cf12838aee8ca5e1a2ce396d22ca5b4334e88a0  lib/elaboration/timing_coverage_tcl.ml
6d97f963ccbf15caafcdadef78602a2ce7513c6ab29d41d792182c6285193ba3  lib/elaboration/timing_coverage_tcl.mli
e6432f22b6acb119949e11bf6fb363d8e52a8a830a3f3b60fb172711a2895fdd  lib/elaboration/bundle.ml
7d3c063bdd2bc8b8f53185e18c7a7a7a991f59f63e64338ec99322e63ca5b5a5  execution/results/timing_native_coverage.ml
4b1a08303ac410dec97d332ea689cc3679895a0f7b7f0849e637da0dd87edbf4  execution/results/timing_native_coverage.mli
239aa627858d1148d482b079a027c33128d7667c9f262a34ace93901d9fdca68  execution/results/timing_intent_evidence.ml
10b411a7923e52f4dfde9a94c52dd69bfff8c99d9e31193ff8600582f3eacee3  execution/results/timing_intent_evidence.mli
```

Next acceptance belongs to B/C: actual retained native grammar/printer/API
qualification and ordinary synthesis-to-linked-STA/source-archive association.
No graph inventory, per-check census, exhaustive exception effect, timing closure
or reset-release/CDC adequacy is claimed by this slice.

## C native-grammar correction — ready for fresh reader qualification

Read example `docs/pt7c_native_findings.md` and exact retained
`producer-probe-01-baseline/native-state.sdc`,
`native-diagnostics-01/setup-only.sdc` and `native-diagnostics-01/masking.sdc`.
The earlier preliminary reader rejection remains a failed historical attempt.
The original bare-word escape handler absorbed the no-preceding-space native
continuation and `-from` into the command token. Corrected tokenization leaves
that continuation to whitespace processing. Derates and the zero-argument
current-design query now have the narrowly qualified forms documented above.
No producer, bundle/SDC bytes, API, wire or audit schema changed in this correction.

Durable local fixtures are in `test/timing_native_coverage/*-excerpt.sdc`.
`NATIVE_EXCERPTS.md` records exact source line ranges and full native source hashes;
fixtures preserve the copied native bytes and do not require the example checkout
at test time. The positive has six exact relations with native target order
different from requested order. Setup-only and masking negatives reject on the
intended semantic diagnostic, not ordinary-policy or tokenizer failure.

Final correction checks:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/timing_native_coverage test/timing_intent_evidence
```

Passed **97 pure native reader/schema checks**, existing **54 evidence checks**
and **27 independent review regressions**. New controls cover real native excerpts,
continued masking/broad/extra/restricted scope, derate value/scope/options, current
design query arity/substitution, newline/semicolon query injection, and correct
distinction between continuations, quoted folding and escaped spaces/backslashes.
One first test iteration found that an older truncated-query fixture now rejected
earlier for its bare query newline; its input now ends with an explicit continued
line to isolate the intended missing-close diagnostic. No acceptance was weakened.
`git diff --check` passed. No EDA or Git mutation was performed; B's environment
startup correction remains separately owned and C must recapture/requalify the
corrected reader against fresh retained producer evidence.

Exact local excerpt SHA-256:

```text
bd22008a9d0f3437751e4f682f1934e4790a112299aa62ac7eb8160cfa449c30  native-baseline-excerpt.sdc
9e20bc3e067c34ac9813ec0e5fe7936f932385f60f99ed01d4ade266e10c8477  native-setup-only-excerpt.sdc
42d35bb3e8b8eac567a81167807449577db403d8d46c3cddfaa1f69403e6f852  native-masking-excerpt.sdc
```

Overall coverage remains unavailable. Passing retained excerpt interpretation is
not fresh native execution, exhaustive exception-effect coverage or timing closure.

## Implemented native-v2 review corrections — A-NATIVE-R1/R2/R3

The **ACTIVE correction contract at the top of this file is implemented**. The
v1 material above remains historical and must not be used for fresh capture.

### Final API / output changes

```ocaml
Hardcaml_asic_execution.Timing_native_coverage.inspect :
  top:string -> resolved:Evidence_json.t list -> native_sdc:string ->
  native_data:string -> native_checks:string -> native_endpoints:string ->
  (Evidence_json.t, string) result
```

The unchanged outer `Timing_intent_evidence.inspect ~directory ()` passes
`manifest.top_module` only after envelope and bundle identity validation. Native
SDC must select that exact top in its first noncomment/nonempty command. A second
selection rejects, even if it repeats the same top; absence or a later selection
also rejects. `[current_design]` remains the qualified zero-argument base query.
Interpreted `native_coverage` adds `native_design:<verified native top>` and uses
profile `opensta-2.7-native-state-v2`. No top is guessed from native relative
pin/port spellings, stage rows, endpoints or current source.

The emitted manifest declaration and native-data object are now:

```json
{"contract":"hardcaml-asic.timing-native-coverage","schema":2,
 "profile":"opensta-2.7-native-state-v2",
 "producer":"constraints/pt7-native-coverage.tcl"}
```

```json
{"schema":2,"contract":"hardcaml-asic.timing-native-coverage",
 "profile":"opensta-2.7-native-state-v2","complete":true,
 "categories":[{"name":"no_input_delay","group_count":0,"groups":[]}],
 "endpoint_count":0,"endpoints":[]}
```

The categories array always contains all seven original names in their original
order. Their object/group shapes are unchanged. This is **native-data schema 2**,
distinct from the already-existing **audit schema 2**. No third outer audit
schema or extra source role was introduced. The producer member path, `write`
procedure, four filenames, source roles, receipt schema/input ordering, SDC
resolution/application event schema and retained-process contract are unchanged.
The enclosing completion `PT7_AUDIT_COMPLETE` remains unchanged; the native hook
completion is now `HC_ASIC_NATIVE_V2_COMPLETE` and must precede it.

Raw diagnostics now carry the profile header, fixed begin/end category lines and
V2 completion specified at the top. The reader reconstructs those exact bytes
around preserved native group/message/detail bytes. Reassigning a group to an
adjacent empty category while keeping raw bytes unchanged rejects. Reserved marker
lines inside diagnostic messages/details reject in both producer and reader,
including multiline injection, instead of being interpreted as category framing.
Native English warnings are never used to infer category identity.

### R1 comment grammar

The LF-only parser deliberately **rejects** comment lines ending in backslash
immediately before LF. Since R1b, CR/CRLF bytes reject unconditionally before any
comment handling. It does not attempt to recover
commands from continued comments, guess escape parity or source retained Tcl.
Ordinary comments and comments after command separators remain supported.
This is a qualified-grammar restriction, not a claim that continued comments are
invalid Tcl. The `tclsh` oracle confirms that the reviewed continued comment hides
the false-path call, while the ordinary-comment control executes one inert call.

### Legacy handling and required B/C integration

- Audit schema1 retains original replay and unavailable-native semantics. Its
  optional native declaration may be v1 or v2; no native subdimension is promoted.
- Audit schema2 requires native producer declaration schema/profile 2. Older v1
  declarations reject explicitly with an unsupported-legacy/recapture diagnostic
  before log interpretation. Pure native decoding also rejects data/profile 1.
- Relabelling only the JSON profile cannot qualify undelimited raw reports or a
  V1 completion marker: both reject under the V2 contract. Old captures must remain
  byte-identical and available to their historical provider; they are not recast
  as category-bound native evidence.
- B must update its manifest profile gate and synthetic native wire to V2, and
  pass `~top` from B-owned direct pure-reader adapters. Runtime calls/roles remain
  the same. No B-owned file was edited by A for this correction.
- C must capture the changed producer/emitted member and new build identity,
  then re-run native production and inspection. No recapture or EDA was run by A.

### Verification

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/timing_native_coverage
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/timing_intent_evidence test/timing_intent
```

Passed:

- **120 pure native reader/schema checks**. New intended-diagnostic controls cover
  the exact continued-comment counterexample (including indented/semicolon and
  masking variants), full hash-consistent schema2 hidden scope, pure/full-schema2
  diagnostic-category reassignment with unchanged raw bytes, marker injection,
  wrong/missing/late/repeated native top, full-schema2 manifest-top disagreement,
  explicit v1 rejection, old undelimited raw/V1-marker rejection, and schema1 with
  a legacy v1 optional declaration retaining its original replay semantics.
- Independent **real `tclsh` language controls** use only inert object/exception
  procedures over the durable `native-continued-comment-excerpt.sdc` fixture.
  Zero calls for the continued comment and one for the ordinary-comment control
  are asserted; semicolon/indented cases also hide the command as expected.
- The **actual emitted V2 producer** passes modeled native API / raw-marker
  agreement and error/budget/collision/marker-injection controls. No completion
  is emitted on modeled failure. This is not OpenSTA/OpenROAD qualification.
- Existing **54 evidence checks + 27 independent review regressions** pass.
  Existing timing suite passes its **34 library negatives**, **8 Tcl positives /
  41 pre-application negatives**, application-failure and native-boundary controls.
- `git diff --check` passed. No EDA, old evidence/provider edits or Git mutation.

The independent B review is not relabelled as a passing v2 review: B should adapt
its separate adapters to the mandatory `top` and V2 framing, then recheck these
corrections independently. Overall coverage and exhaustive exception effects
remain **unavailable** even for matched native-v2 stored scope and diagnostics.

### Native-v2 source receipt (SHA-256; supersedes earlier A receipts)

```text
4240095a12a44c9f30a085b5713f7db3dfcc02967a9dfb2efdba5818c096e33a  lib/elaboration/timing_coverage_tcl.ml
6d97f963ccbf15caafcdadef78602a2ce7513c6ab29d41d792182c6285193ba3  lib/elaboration/timing_coverage_tcl.mli
e6432f22b6acb119949e11bf6fb363d8e52a8a830a3f3b60fb172711a2895fdd  lib/elaboration/bundle.ml
aa8554bd945d1877ae36f6148371cac5ba909de6a5c1c58e849b68a2dcb0e0c3  execution/results/timing_native_coverage.ml
6b1518644aef7ff5914dcfd08c277a0c60703972221f458754146a2ac3ec91e9  execution/results/timing_native_coverage.mli
2fe9015335a631d4d4697c6a325d54a992e8ac2912c760a226a0dbd82a637c55  execution/results/timing_intent_evidence.ml
53147628872b0f34d722356ef7f77ed2d7e611e3f96526fb78b4ef776ecfb17d  execution/results/timing_intent_evidence.mli
```

## A-NATIVE-R1b — reader-only LF grammar correction and retained-v2 replay

Read B's concrete bare-CR follow-up in `pt7c-native-review.md:366–432`. Tcl source
channels terminate comments at bare CR, whereas the earlier reader scanned only
to LF. That could hide extra relations, a disable or another design selection.

Implemented the conservative qualified-serialization fix in
`Timing_native_coverage.commands`: **any CR byte rejects immediately after the
file-size bound and before tokenization, comment scanning or design selection**.
This includes CRLF and CR inside quoted/braced values. Original retained bytes
are still hash-checked without newline normalization; the reader neither sources
Tcl nor rewrites reports. Native output is LF, so this requires no producer,
runtime, API, native-data/profile, emitted member or bundle change. Schema1
unavailable-native/replay semantics remain unchanged.

### Focused verification

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune runtest -j6 test/timing_native_coverage
```

Passed **154 pure reader/full-schema2 checks**, including 34 new checks over the
17 newline cases, plus **17 independent real `tclsh` source-channel controls**.
Durable cases are `test/timing_native_coverage/native-newline-cases.json`; the
independent oracle is `newline_check.py`. It writes exact decoded source bytes in
binary mode, avoiding Python universal-newline normalization. Extra-scope,
masking and wrong-top bypasses reject in both pure and hash-consistent complete
audits. LF ordinary-comment/native-continuation controls accept; LF-exposed
extra/masking/design-change controls reject semantically. CR, CRLF and mixed
source forms explicitly reject as unsupported LF-only serialization even where
Tcl itself accepts them. The existing producer/API-model and LF comment-language
tests remain part of the focused alias (unchanged dependencies may be cached).

### New corrected-reader provider capture (no native recapture)

Captured the corrected sources into a **new `/tmp`-only provider store** through
the existing dependency capture/install mechanism, without activating it or
touching any example/current provider selection:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  python3 -B /tmp/opencode/pt7c-r1b-capture-replay.py
```

The script invokes `scripts/asic_dependency.py --store <new tmp store> refresh
--source <ASIC checkout> --mode development --jobs 6`. Its captured-source build,
installation and small installed-API probe use explicit six-job Dune limits,
sequentially under the same shared lock. No test broadening or EDA is involved.
This is a locally recorded development source/build association, not authenticated
execution or a clean-checkout source stamp. Final handoff text postdates the
capture; installed production parser bytes were directly checked against the
corrected source hash below.

```text
generation:
  /tmp/opencode/pt7c-r1b-reader-provider/generations/ab26b8c838aa4db2b8ab28531be41a26
snapshot_sha256:
  2b62af5232ba4cf55ae184a2d541f1360aaafba6e410602eb7beb223cdb441f9
receipt_sha256:
  40cb8cfbe8c11c65d7e4c32a0a307c6347b7d45a3ddb06076aeae069838ac3f9
```

The new provider's public CLI replayed C's **existing exact accepted native-v2
sources**, with no emission or native tool launch:

1. Original coarse run
   `hardcaml_asic_example/.dev/asic-pt7c/runs/20261028T183412758171Z_83a02bdc`.
2. Its restored evidence at `acceptance/pt7c/public-v2-01/restored`.
3. The original run's standalone `nom_typ_1p20V_25C` native audit.

All three return **exit 1 / unavailable**; original/restored coarse views are
`status=completed`, and each JSON equals C's accepted retained reference
(`public-v2-01/inspect/stdout.log`, or its inner corner for standalone). Six exact
stored relations remain matched. **67 source hashes per run root**, including
the advertised closure plus run/companion records, match before and after replay.
The original provider, producer, bundle, netlist, SDC, native reports and process
receipts were not patched or re-produced. C's original native-v2 execution remains
its original execution; this is a corrected-reader replay of it.

Capture commands/logs, installed parser identity, source pre/post inventories,
three public process/stdout/stderr receipts and summary are retained under
`/tmp/opencode/pt7c-r1b-reader-replay/`. B can now rerun its independent R1b probes
against the corrected reader; this handoff does not relabel B's earlier failing
review or assert independent closure on B's behalf.

```text
f141b57575d48c4c09678fea34aa499f1adfc797a20b0839c3269928fd9b9f07  execution/results/timing_native_coverage.ml
ca08595de1d7e88dff99481b1ebeafd8f7b12193da5199bbfabc57e7acdb0193  execution/results/timing_native_coverage.mli
4240095a12a44c9f30a085b5713f7db3dfcc02967a9dfb2efdba5818c096e33a  lib/elaboration/timing_coverage_tcl.ml (unchanged)
7d74777fef51d9818d2f1696d940fabf08d09544cb839e6e8fdbd5ca531d7c3f  /tmp/opencode/pt7c-r1b-capture-replay.py
c9eda7e1862902e56459aae3277a072b90994eed25282d4b2b5bc4e413dd5b92  /tmp/opencode/pt7c-r1b-reader-replay/summary.json
```

`git diff --check` passed. Zero EDA runs, zero design rerenders, no provider
activation or existing selection change, no historical-evidence or Git mutation.
Overall exhaustive exception-effect and timing-closure coverage remain unavailable.
