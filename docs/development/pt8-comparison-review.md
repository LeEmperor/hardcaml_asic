# PT.8 comparison — independent A review of B

2026-10-29. **Final correction review: R1–R4 closed; B's bounded corrections
independently verified.** See [final disposition](#final-correction-verification-and-disposition).
The initial review below found two high-severity and two medium-severity issues.
B's original 96 focused checks and retained positive matrix passed, but did not
cover the source-admission failures reproduced below.
C's reported 204 initial assertions are separate evidence, not a substitute for
this review. No B production/test source was edited by A.

Scope is exactly [the bounded plan](pt8-variant-plan.md): pair comparisons,
optional execution metadata, CLI, metric eligibility, numeric arithmetic,
source-generation integrity and bounded read-only behavior. No new workload,
scheduler, physical flow, parameter selection or constraint system is requested.

## Findings

### R1 — HIGH: coarse comparison promotes unchecked declared source inputs to controls

**Locations:** `execution/results/variant_comparison.ml:168–170,203–218,300–303`;
`resource_inspection_service.ml:75–78,387–411`. Bundle acquisition at
`resource_inspection_service.ml:50–70` verifies every inventoried bundle member;
the coarse branch instead replays the narrower resource-observation closure.

The coarse manifest is hash-checked and its resource inventory validated, but
its complete `files`/`source_inputs` closure is not checked. Nevertheless the
comparison copies `manifest.source_inputs` into the required `source` control.
Replaying the same narrower resource/timing services four times does not add the
missing input-member checks.

**Actual source-rebound reproduction:** copy retained full run
`23a6954b852d4205b542d3815634d772` into a disposable directory. The normal copied
run compares successfully against itself. Change, then delete, the existing
`project/inputs/asic-dependency.json`, without changing its declared digest or
any execution/analysis evidence. Public `compare --left-kind coarse_run ...`
still exits0 in both cases, with **all 18 native metrics comparable, zero deltas,
and the same comparison digest as the intact copied run**. Treat that project
as a `bundle` target and corruption rejects exit2 (`bundle member hash mismatch`).
A smaller ordinary resource fixture reproduces both corrupt and missing members
without any native fixtures or timings.

This is a demonstrated spurious controlled-source claim over invalid required
input bytes, not merely a missing optional display field. No declaration hash,
toolchain label, valid native metric or equal self-comparison can repair it.

**Bounded correction requested of B:** before admitting declared source/RTL/config
facts as controls, verify their required existing bundle inventory and bytes for
the selected coarse target, using the existing bundle/inventory services and
their bounds. Include that verified closure in generation replay. Missing or
corrupt required members must reject; they cannot be reported as historical
absence or an unavailable metric. Preserve genuinely historical absent metadata.

**Evidence:** `test/pt8_comparison_review/receipts.json`, cases
`physical.relocated-baseline`, `physical.corrupted-declared-input`,
`physical.missing-declared-input`, `physical.bundle-corruption-control`;
`race-receipts.json` contains the independent small-fixture reproduction.

### R2 — HIGH: stored results bypass bounded regular-file admission and can hang

**Locations:** `variant_comparison.ml:52,176–177,182` calls unbounded
`Evidence_json.read`; `evidence_json.ml:85–89` uses blocking `open_in_bin` and
`in_channel_length` with no file-type or size admission. The comparison's own
regular-file/32MiB `read` helper is not used here. `Report_service.run` also
reopens results and renders supplementary report inputs through its existing
unbounded paths (`report_service.ml:275–279,313`).

**Reproduction:** start with the valid rebound small coarse fixture; restore its
valid declared input; create a FIFO at `results.json`; call the public CLI.
The process blocks opening the FIFO and must be killed by the review harness's
two-second timeout. This is deterministic blocking, not a slow native closure
replay. A 1MiB response check after constructing/parsing the result cannot bound
this input path or its allocations.

**Correction requested:** admit consulted metadata with contained, bounded,
regular-file reads before handing it to existing services. Ensure service
reopens cannot bypass that admission. Do not add an EDA launcher, general
scheduler or replacement report parser. This is enforcement of the already
promised bounded host-only operation.

**Evidence:** `race-receipts.json`, `coarse.results-fifo-admission`,
`timed_out:true`. The temporary FIFO is removed and the child terminated.

### R3 — MEDIUM: final replay does not bind the raw generation of stored results

**Locations:** `variant_comparison.ml:234–246,300–303`. The generation digest
covers parsed resource/record/report/timing values. Resource references cover
the run/manifest and observation sources, but not the raw consulted
`results.json`; the explicit raw `record_sha256` covers only run/execution JSON.

**Reproduction:** valid small coarse source and an actual
`Collect_service.collect` result saved to `results.json`. An inotify barrier on
the right target's manifest triggers a whitespace-only rewrite of the left
stored results after left capture, before the final replay. Both raw SHA256s
differ, the mutation completes, and public comparison still exits0. The final
semantic digest is unchanged because key ordering/whitespace normalize away.

No metric-value change is demonstrated here. The defect is the stronger promise
that captured source generations are raw-byte-bound and rechecked, not the
legitimacy of JSON semantic equality. Keep that distinction explicit.

**Correction requested:** retain/check the raw identity of consulted stored
metadata as part of its existing source generation; reuse bounded snapshot
readers. A coherent byte change should either yield a newly captured identity
or reject/retry. Do not silently call it the same captured raw generation.

**Evidence:** `race-receipts.json`, `coarse.raw-results-generation-race`, with
`mutation_completed:true` and distinct `old_results_sha256`/`new_results_sha256`.
The corrected review harness restores the declared input before this probe, so
R1 is not a precondition for R2/R3.

### R4 — MEDIUM: archive optional-metadata validation occurs after duplicate loss

**Locations:** `execution/archive/archive_service.ml:9,51,77–85`;
`execution/results/manifest_metadata.ml:1–12`;
`evidence_json.ml:44–48,85–89`.

`Manifest_metadata.validate` correctly rejects duplicate fields if it receives
them. Archive's `Evidence_json.read` uses the historical last-wins decoder first,
which removes both top-level and nested duplicates. Serializing the resulting
value and invoking strict `Hardware_variant.of_string` cannot recover them.

**Actual public service reproduction:** use a valid declaration produced by the
public library codec. Coherently bind manifest identity and run manifest SHA256.
Insert either two `hardware_variant` fields (null followed by the valid object)
or two `assignments.depth` fields (128 followed by256). Read-only
`Archive_service.inspect` succeeds for both malformed manifests; the public
bundle comparison correctly exits2 for the exact same source bytes. Legacy
absence and valid new metadata succeed in both; present null rejects in both.

This is a new optional-field strictness gap in a B-owned validator seam, not a
request to change historical absent-record semantics globally.

**Correction requested:** preserve/admit raw manifest duplicates before the
last-wins historical transformation for manifests carrying the new metadata;
then reuse the existing strict hardware codec. Test duplicate optional and nested
assignment fields through actual archive inspection, not only the helper on
already-parsed JSON. Do not weaken the A schema or hash algorithm.

**Evidence:** `test/pt8_comparison_review/metadata-receipts.json`, all ten calls;
read-only public API shim in `review_api.ml`.

## Eligibility and numerical audit

### What is currently supported correctly

- Production projections reuse `Resource_inspection_service`, resource source
  replay, `Stage_report_service`, `Report_service` and linked native timing
  readers. There is no second Liberty/Yosys/STA parser in B comparison code.
- Per-metric comparison checks definition, unit, stage, scope, classification
  and quantity. Native scope includes the exact corner and whole-design metric
  designation. Native library controls use ordered retained Liberty hashes;
  post-PNR RC references come from verified SPEF selection. Ordinary/named sampled
  witnesses are not promoted to worst-slack scalars.
- The intended hardware axis waives hardware identity/resource contracts; the
  policy axis waives policy while still requiring logical contracts; the flow
  axis waives flow configuration. Other required controls remain checked;
  descriptive does not waive them. There is no winner or causal-optimization gate.
- Estimates have no measured delta. Signed slack remains signed. Exact integer
  deltas use Zarith; mixed integer/real representations are conservatively
  withheld instead of being silently rounded.
- Actual retained named area/delay comparison preserves distinct attempts,
  bundles and publications despite equal mapped-netlist hashes. It supplies two
  boundary metrics with no measured delta. Physical-self exposes18 native zero
  deltas; synthesis/physical exposes18 confounded metrics with stage/RC reasons
  and no deltas. Closure pass and exhaustive coverage unavailable stay separate.
- Missing advertised physical `timing-intent/analysis.json` rejects exit2 rather
  than becoming optional/unavailable (`receipts.json`).

### Meaningful source-rebound arithmetic checks

`metric_probes.py` makes two disposable copies of the actual accepted physical
record. It changes the typical-corner native metric log AND its corresponding
output-State metric, then rebinds inner audit, selected-audit/progress and outer
closure hashes. It does not inject `compare_metric` projections or execute STA.
These are deliberately producer-assertion fixtures, not new physical evidence.

The actual public CLI accepts the coherent reader fixture and reports:

- typical hold slack: left `0.2766860707751655`, right `-0.25`, comparable,
  **right-minus-left `-0.5266860707751655`**;
- hold-violation count: left0, right7, exact delta7;
- after replacing the native count with `2^53+1`, that count becomes unavailable
  with null delta, rather than accepting the float-rounded token. Other valid
  metrics remain independently classified.

Both projections preserve their recorded run IDs; distinct captured source
generations remain distinct. This is not an invented new execution attempt.
See `metric-receipts.json` for exact source references, values and reasons.

### Environment/labels: explicit qualification

`nonempty` in `variant_comparison.ml:54,88–95,152–155` is only a structural
presence check, not a general semantic environment validator. A copied run with
`environment:{"status":"unknown","ready":false}` still obtains comparable
native metrics. **Do not interpret that object equality as established toolchain
control.** That first exploratory receipt also follows the missing-member probe;
it is not used as a separate integrity-negative acceptance claim.

Importantly, this is not proof that production accepts a wholly unknown native
executable/image: the lower physical reader separately validates the recorded
execution binding, supported pinned image, process argv and OpenSTA2.7 producer.
The independent arithmetic script removes the authoritative execution binding
and supplies the unknown environment object: public comparison rejects exit2
(`physical runtime binding mismatch`). Thus no missing-native-toolchain bypass
was demonstrated. The current pure tests' arbitrary `same-recorded-fact` strings
are not evidence for this production property; the rebound reader probe is.

B should keep eligible controls tied to those validated facts and distinguish
unknown environment containers from them; matching labels are insufficient.
Do not add unrelated host fingerprint/signoff requirements. Also, current
resource/area controls always carry `rc:null`, so those production metrics have
no deltas even in self-comparison. This is conservative limited usefulness,
already disclosed in B's handoff, not an unsafe delta or a new feature request.

## Bounds, generation and read-only audit

- The code has per-side256 metric and4096 inventory bounds, existing resource/
  native closure limits and an exact whole-response1MiB rejection. CLI requires
  two explicit kind/path pairs and an axis; duplicate arguments/unknown flags
  reject. No latest-run resolution, implicit selection or output publication.
- Final source replay rejects ordinary semantic source changes, as B's focused
  race test demonstrates. It does not repair R1's absent input closure or R3's
  omitted raw report generation.
- Bounds are not a time/memory guarantee before input admission: R2 bypasses the
  bounded reader. One traced actual physical-self comparison made277842 traced
  file/process/network syscall entries. Repeated deep replay is substantial work;
  this is measured cost, not a requested new performance feature or scheduler.
- Independent `strace -f` of the public physical-self query observed exactly two
  execs: the public CLI and its installed-layout native comparison helper. No EDA,
  Python, Git, shell/tool probe, mutation-opening flags, filesystem mutation or
  network syscalls were observed. Output was399536 bytes. The trace harness itself
  wrote only its temporary trace and review receipt. See `trace-receipt.json`.

## Actual checks, provenance and reproduction

Review-created files are confined to this document and
`test/pt8_comparison_review/`. The shim calls public archive inspection; scripts
call the existing public CLI/consumer. All query subprocesses use `PATH=/no-tools`
or `/no-external-tools`; all source rewrites are in disposable `/tmp/opencode/`
copies. No original physical/named evidence, provider/config, Protemu or Workbench
was modified. No Git mutations or EDA were performed.

Built under switch `5.2.0+ox`, with the common
`/tmp/opencode/asic-pt7-build.lock` and explicit `-j6`:

```sh
dune build -j6 @test/variant_comparison/runtest
dune build -j6 test/pt8_comparison_review/review_api.exe
```

Additionally ran B's check script directly, bypassing Dune's cached action:
**96 checks passed**. Ran its retained-reader script directly against original
named area/delay and coarse synthesis/physical targets: **passed**, preserving
**1860 files** by hash/size/mtime. Comparison digests exactly match B's handoff:

```
79a905b7ea380d7903e0af89cf8d086dc2ef67078c16e0f58a87dfee3721944d
7c4046dbc53781f45877dca76b81f1674a1adee6dc3dca7b10d69d5000cbb797
b6fab3d2599be1521394b0f6a35a75519d606d6a5f224240884e84f72640df68
```

The independent copy/rebound suite separately preserved1196 original physical
files by hash/size/mtime. Original baseline run:
`hardcaml_asic_example/.dev/asic-timing-physical/full-runs/20261029T075052976305Z_23a6954b`.
The arithmetic and syscall probes read that same original without changing it.

Minimal reproduction commands, from the ASIC checkout after the build above:

```sh
python3 -B test/pt8_comparison_review/probes.py \
  --cli _build/default/bin/flow_cli.exe \
  --consumer _build/default/test/variant_comparison/consumer.exe \
  --output /tmp/opencode/pt8-review-races.json

python3 -B test/pt8_comparison_review/metadata_probes.py \
  --cli _build/default/bin/flow_cli.exe \
  --consumer _build/default/test/variant_comparison/consumer.exe \
  --review-api _build/default/test/pt8_comparison_review/review_api.exe \
  --output /tmp/opencode/pt8-review-metadata.json
```

Add `--physical /absolute/path/to/the/retained/full-run` to `probes.py` for the
actual native R1 reproduction; the same flag is required by `metric_probes.py`
and `trace_probe.py`. All scripts take explicit `--output` receipt locations.
Full initial raw-case receipts retain CLI SHA256
`226dd0df19e503e86ec192d450d8d23741ab9ee863a8034f5657f7a15da45fa2`
and consumer SHA256
`d06f06ed766950e7664e9e60950f06082cf728c2a8244a05e049741e5fd66cb4`.

## Initial disposition (superseded by correction verification below)

Request B corrections and focused reruns for R1–R4 before accepting this slice.
Keep the passing real-reader arithmetic, attempts, corner/stage/RC, required-
companion and no-tools/no-writes controls. No A or B production fix is made in
this independent review, and no source-stamp or execution-authentication claim
is implied by the rebound fixtures.

## Final correction verification and disposition

2026-10-29. **R1–R4 are closed for this bounded comparison slice.** This is A's
independent correction verification, not a restatement of B's own recheck
receipts. No B source or original probe script was edited. Original failure
receipts above remain intact; new results have distinct `corrected-*` names.
No new broad feature audit, EDA or functional simulations were allocated.

### Actual correction checks

| Finding | Independent result | Disposition |
| --- | --- | --- |
| R1 | Unchanged `probes.py`: intact ordinary/retained physical copies pass; corrupt and missing declared source copies reject exit2 for coarse and bundle targets. No comparable rows or old digest are returned for invalid source. Original physical-self still has18 comparable native zero deltas. | Closed |
| R2 | Original FIFO probe rejects exit2 with `timed_out:false`. B's actual-service admission43 also passes FIFO/symlink/directory/oversize and open-time replacement cases. Independent deterministic pre-open and post-open descriptor fences both reject promptly. | Closed |
| R3 | Original inotify race completes a real raw formatting rewrite, records different old/new SHA256s, and rejects with `comparison source generation changed`. Independent stable formatting control keeps all metrics identical but changes comparison digest; consulted run/results/manifest references exactly match their original byte hashes and lengths. | Closed |
| R4 | All ten calls in unchanged `metadata_probes.py` now agree across archive and comparison: historical absence/valid metadata pass; duplicate optional/assignment fields and present-null reject. Additional archive-role/legacy controls and losing duplicates of every hardware envelope scalar reject as appropriate. | Closed |

Correction evidence is under `test/pt8_comparison_review/`:

- `corrected-receipts.json`: original ordinary and actual physical source probes,
  static FIFO, completed raw-generation race and required companion rejection.
- `corrected-metadata-receipts.json`: original ten archive/comparison calls.
- `corrected-metric-receipts.json`: original native-source rebound arithmetic and
  missing authoritative execution-binding negative.
- `correction-controls-receipts.json`:15 additional narrow calls/controls for actual
  descriptor-open boundaries, original raw bytes, original/staged archive roles,
  genuine historical duplicate semantics and strict new envelope duplicates.
- `corrected-trace-receipt.json`: actual public physical-self syscall audit.

### Why this is descriptor admission, not a vulnerable precheck/reopen

Inspected `retained_file_stubs.c` and `Retained_file.read`: parent components are
opened with `openat(O_DIRECTORY|O_NOFOLLOW)` from pinned directory descriptors;
the leaf uses `O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC`. The **opened descriptor**
is checked for regular type and byte bound before allocation/read. Post-read
descriptor device/inode/type/size/mtime/ctime and named-path identity must agree.
This is not a path stat followed by a potentially blocking normal open.

`Report_service.run` now consumes its stored document once through this reader,
records SHA256 and full byte length from those actual bytes, and uses a64MiB
aggregate metadata budget. Comparison requests `render_human:false` and
`strict_sources:true`; it no longer performs the original unbounded pre-read or
unused human supplementary render. No unchecked second stored-results reopen
remains in that changed path. Existing ordinary report rendering defaults remain.

The independent `fence_open.c` is a **review-only** LD_PRELOAD interposer, built
in the review test directory and never linked into production. Its pipe barrier
stops the actual libc leaf open, rather than relying on inotify scheduling:

1. Replace `results.json` with a FIFO immediately **before** the actual open:
   exit2, `retained source must be a regular file`, no timeout. This would expose
   a stat-only admission followed by a blocking open.
2. Replace it immediately **after** the actual regular descriptor is acquired,
   before control returns to the OCaml reader: exit2,
   `retained source changed during read`, no timeout. The old readable descriptor
   does not mask named-path replacement.

Both barriers were explicitly reached. The first interposer attempt did not
reach a barrier because this switch calls libc `openat64`; that failed harness
attempt is not counted as production evidence. Adding the matching review-only
symbol wrapper made both exact-boundary tests execute and pass. No production
change was needed.

### Complete original stored bytes and retained bundle sources

Verified `Report_service.metadata_sources` derives path/hash/length from the same
raw document passed to `Evidence_json.parse`. `Variant_comparison` includes those
references in both its generation binding and public `consulted_metadata`; final
pair replay therefore checks raw formatting generations as well as parsed values.
The independent true control checks all three actual run/results/manifest byte
references, not a reserialization of their parsed objects.

For R1, `comparison_snapshot` locates the manifest reference already selected by
resource replay, invokes the existing bounded bundle reader on **that manifest's
directory**, compares its consumed manifest SHA256 with the selected reference,
and retains the verified member references. Source path/copy/digest links,
duplicate copies, complete `inputs/` enumeration and synthesis/simulation inventory
membership are validated. Both capture generations include these references;
the comparison is no longer relying solely on the narrower resource closure.

Reran the real retained matrix with `--check-declared-inputs`. Both API and CLI
reject corruption/deletion of an actual declared input in a copied physical run.
The original selected named/synthesis/physical trees preserve **1860 files** by
hash/size/mtime. The independent original-script copy probe separately preserves
**1196 original physical files**. No historical manifest receives new metadata.

### Archive roles, strict raw metadata and unchanged native semantics

Inspected both `Archive_service.verify` (staged manifest) and
`validate_bundle` (original and fallback staged candidates): both call
`read_manifest`. It retains the consumed original document bytes and checks their
SHA256 against the run record. If the new hardware field is present, strict
`Identity_json.parse raw` runs on **those original bytes** before the hardware
codec, so top-level, escaped-key and nested duplicates cannot disappear through
last-wins parsing. The shared path covers every candidate role, not only the
direct helper input.

Independent controls select a valid **original** bundle and then a valid
**staged fallback**, and accept valid optional metadata. They retain genuine
absent-metadata schema1 last-wins decoding of an unrelated legacy duplicate.
Losing duplicate hardware `contract`, `design_id`, `schema_id`, `schema_version`
and `identity` fields reject exit2 even with correctly rebound semantic identity
and original-byte run hash. The original optional/assignment duplicates reject;
B's independently executed43-case suite additionally covers escaped aliases,
descriptor duplicates and genuine failed resource evidence remaining archivable.

Unchanged `metric_probes.py` still passes coherent native log/State/closure
rebinding through the real readers: signed hold delta
**-0.5266860707751655**, exact violation-count delta7, and no delta for a native
count of `2^53+1`. Removing the authoritative runtime binding still rejects.
Matching unknown environment containers alone are not executable/image authority;
the existing checked binding/process/producer evidence remains required.

Unchanged original named area/delay comparisons preserve distinct attempts and
publications with equal mapped output hashes and no fabricated measured delta.
Physical-self has18 comparable native zero deltas; synthesis/physical has18
confounded native metrics with null deltas. Original closure-pass and exhaustive-
coverage-unavailable outcomes remain separate. Resource metrics with missing
context remain unavailable. No physical improvement, workload or winner is inferred.

### Independently executed commands and final hashes

Builds used switch `5.2.0+ox`, shared `/tmp/opencode/asic-pt7-build.lock` and
explicit `-j6`:

```sh
dune build -j6 @install @test/variant-comparison test/pt8_comparison_review/review_api.exe
dune build -j6 test/pt8_comparison_review/fence_open.so
```

Ran the original four A scripts unchanged against the corrected binaries, saving
the correction receipts above. Also directly executed B's **96 focused** and
**43 correction** checks, bypassing cached Dune results, plus its retained matrix
with the actual declared-input negative enabled. All passed.

Actual public physical-self tracing: **279598 syscall entries**, exactly the
public CLI/native-helper exec pair, no filesystem mutation/write-capable opens,
network or external tools. Response **406112 bytes**; no EDA or source writes.
The injected fence harness is separate and is not used to make that trace claim.

Final retained comparison digests (named / physical-self / synthesis-physical):

```
7cf3dd62688e5835fcb30437380d280c401243f9a4535803f1801022a0c2d991
755ffb7a8b8dc6caeda8eceda4c432d0957bc2c377c807ecce0ced1857f342e3
0969f1b9450053eda28502bad1a964b5fb60a8e31deac127c6a7f268092e00d7
```

Independently hashed tested correction sources (local bytes, not P6 attestation):

```
37d593d884f7d093ce3312dcce69bfedce03e6a2a4c1e4dada82bab0b93f2bed  execution/results/variant_comparison.ml
53bd488c040859cef6c6f7178ac7265f8d79bd6a6ba671b50122459654f46b1d  execution/results/resource_inspection_service.ml
83e4981d97ce92fd257f3c6fdbe4424194ff852e9469187a44a54a41eb53b0b5  execution/results/report_service.ml
66a24e0b97b043fe1a88e55c9002ba801f5f3c5a137362a8ff4bc09b62da1aec  execution/results/report_service.mli
c858c5f4c772150095d3066e3831aac679d3ab158fe3abfff8e7aa8889a5ec39  execution/results/retained_file.ml
b457319c617feb44511c737a244713e4c01e8a0d61a799ea062e4dba2e1e49cf  execution/results/retained_file.mli
5247984585b41510e3ae301713e9b7d2956f5c378b256ec683d3667bd23d09b0  execution/retained_file_stubs.c
2fc179c30abfa0ce4b4a1eaf0885da9d944b3e13ed1a6609699424991caed6bc  execution/results/evidence_json.ml
693cc1807e723ff1e6a04011bdb7227673ebe4cc34de731f16c09f8ebe57432f  execution/results/evidence_json.mli
dab674a84fa07d8cdf4ae16594d7016eee37b129e0a83c84ed37c342f52aef2d  execution/archive/archive_service.ml
```

Tested executable SHA256s, independently matching B's correction handoff:

```
7b7c63d924341e215028318354980312176a80362ad64c5fe5c327ea851cc52e  experimental_compare.exe
226dd0df19e503e86ec192d450d8d23741ab9ee863a8034f5657f7a15da45fa2  flow_cli.exe
3427d75a754d2b7e88d30c1b3395f44fce04fce846bb12a2fc7a01ad54814f76  test/variant_comparison/consumer.exe
```

Correction receipt SHA256s, relative to `test/pt8_comparison_review/`:

```
e4afa78e11772ea9812c74f3975622c8147b4f19cdf43d2c1680955aa3f4e816  corrected-receipts.json
87833d4964462f23c5b06a0df30ba3f5a4db3ab5e308529cb4523961bf3a83e0  corrected-metadata-receipts.json
1e0e3550edc766671d7366661a990c06317779e483e30ef1680ea1163366134c  corrected-metric-receipts.json
9a662edcfe27ba022064958bf6394ad70629503d5dbc125524993ad9880ca703  corrected-trace-receipt.json
47fe0e110e8902c8a29b394a0635763ec8c72c982a75babd3ec113a1f3ac5520  correction-controls-receipts.json
```

Original A probe SHA256s (unchanged during correction verification):

```
0fc062170f327cb227cb4820a574fa916456fcd1242bfa0fb10489e1677eb7b8  probes.py
703b1942c74475e5ce85edc056021c0e6464d1106f70b0e40970ab8c6f58fba2  metadata_probes.py
438d1e694b0d47c8149ab34fe875a8917c16eb559d86073da71efe2428ab7d56  metric_probes.py
86c69df5197147e5a7e8291f39da0fd677b02079e0eef5c5930532ccd2a6caf8  trace_probe.py
```

**Final disposition:** accept B's R1–R4 corrections for the bounded plan. No
remaining blocker was found in these corrections. C must recapture the corrected
provider and rerun its final installed example checks against that capture; its
earlier `d36e6cd...`/204-assertion result is not reattributed to these binaries.
At this verification, C's published `docs/pt8_final.md` still identifies that
earlier capture. This review does not change its provider selection or claim the
corrected C recapture complete. Physical/named histories, old provider/config,
dirty physical work, Protemu and Workbench remain preserved; no Git mutations.
