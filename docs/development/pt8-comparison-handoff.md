# PT.8 B — comparison contract (implementation handoff)

2026-10-29. Implements the bounded B slice of [the plan](pt8-variant-plan.md).

**R1–R4 correction handoff: ready for C recapture.** The independent review's
source-admission and generation findings are corrected and reverified below.
The earlier provider/comparison digests are historical; use the corrected source
hashes and post-correction comparisons in the final section.

Public module `Hardcaml_asic_execution.Variant_comparison`:

```ocaml
type target = Bundle of string | Coarse_run of string | Execution of string
type axis = Hardware | Resource_policy | Flow_configuration | Descriptive
val inspect : left:target -> right:target -> axis:axis -> unit ->
  (Evidence_json.t, string) result
```

CLI: `hardcaml-asic-flow compare --left-kind bundle|coarse_run|execution --left PATH
--right-kind bundle|coarse_run|execution --right PATH --axis
hardware|resource_policy|flow_configuration|descriptive --json`.
Capability `variant_comparison1`; standalone envelope
`hardcaml-asic.variant-comparison`, `schema_version:1`, policy `bounded-pair-v1`.
Exit0 means readable comparison (including failed source outcomes); exit2 means
invalid/corrupt/unsupported source or limit violation. No exit1 acceptance gate.

Whole response <=1MiB; no paging. Exactly two explicit targets. Each side retains
kind/target/source_digest, identities, hardware_variant, resource inventory and
measurements, frozen methodology/configuration, recorded controls and separate
outcomes. Missing metadata is null/unavailable, never inferred from names.
`differences` contains domain/key/left/right/state rows. `metrics` contains
metric_id, left/right measurement objects, comparison
(`comparable|confounded|unavailable`), reasons and `right_minus_left` (null unless
eligible). `workload` explicitly records unavailable firmware/performance evidence.
`comparison_digest` binds policy/axis and both verified projections/generations.

Each side's `metric_contexts` is a digest-keyed dictionary of exact controls;
measurement objects reference it through `controls_digest` to avoid duplicating
large frozen configurations. `resource_sources` is the validated resource source
catalog; resource metric sources reference its `resource_source_digest`. Native
metrics retain their exact log/State/ordered-Liberty references. `outputs` retains
mapped/implementation netlist references where existing timing APIs supply them;
output-byte difference rows compare hashes, not locators. `record_sha256` hashes
the exact selected record bytes, separately from bundle/attempt/plan/publication IDs.

Hardware controls use a checked declaration when recorded, explicitly labelled as
declared configuration, not semantic-use proof. Legacy hardware metadata remains
unavailable; equal retained synthesis-source hashes can establish equal emitted
inputs without inferring missing hardware parameters. Resource-policy comparisons
still require equal logical resource contracts. Source inventories remain recorded
source observations, not compiled-source/P6 attestation.

The axis declares intent, not proof. All relevant controls outside that intended
axis must be established equal; descriptive comparisons do not waive controls.
No overall winner. Estimates never have measured deltas. Counts use exact integers;
slack remains signed. Source, target, library/model, environment, RC, definition,
stage/corner and workload scope are retained where recorded. Required unknown
controls withhold deltas. Workload is required for performance, not area/counts.

Readers reuse resource inspection/reconciliation, strict stage snapshots, frozen
methodology, coarse reports and retained timing replay. No tool/report parser,
catalog lookup, renderer, runner or publication is added. Both side generations
are replayed/rechecked before return. Execution per-resource realization and named
physical timing remain unavailable in their existing unsupported scope.

Initial bounds: 4096 inventory/difference rows, 256 projected metrics per side;
existing source-reader admission limits remain authoritative. Oversize responses
reject rather than truncate. Full source closures are validated but not embedded.

The first transient A library dependency-cycle build failure is resolved. B's
execution metadata bridge decodes exact Evidence_json bytes through the strict
`Hardware_variant.of_string` codec: Evidence_json's small Intlit tokens must not
be passed directly to the identity JSON validator or rounded through floats.

## B implementation/qualification

Implemented public module, installed native helper, CLI grammar/routing/capability,
shared structured resource projection and execution metadata gates. Source replay
rechecks both complete side generations before return. Stored resource assertions
are verified before coarse reporting can replace them with fresh reconciliation.

The small registry includes existing classified resource area/count measurements,
explicitly accumulated boundary count/area snapshots (area remains estimate), and
companion2 checked native per-corner whole-design timing metrics. It never promotes
historical/named sampled witnesses. Required unknown controls withhold deltas;
resource metrics without established RC/model/environment context can remain
unavailable even in a readable comparison. Boundary snapshots do not establish
per-resource retention or per-step measurement attribution.

Read-only replay against retained actual records (no EDA):

- Named area/delay attempts `cb5e7cd92dbf43b4a6c00a74b61c6d72` and
  `9374823306a64897959e1b2295f52c84`: valid comparison, distinct identities,
  equal mapped-netlist SHA256 `1fa6fc0404ac31a5c435d9fc2f4b33dbe95749d53618c3a14c5455ea414876e1`;
  two accumulated boundary metrics, deltas withheld for unknown controls/estimate.
- Full coarse run `23a6954b852d4205b542d3815634d772` against itself: valid
  <=1MiB response; all 18 native corner metrics comparable with zero deltas;
  original closure pass and exhaustive coverage unavailable remain separate.
- All-corner synthesis `4821044b` versus that full run: 18 native metrics
  confounded by stage/environment/RC, with all deltas null. No P&R rerun.

Focused tests live in `test/variant_comparison/`; root alias
`@test/variant-comparison`. Every build/test uses switch `5.2.0+ox`, explicit
`-j6` and `/tmp/opencode/asic-pt7-build.lock`. Existing resource/schema1/stage,
CLI/packaging and historical/named timing fixture regressions are also exercised.
Installed C consumer acceptance remains a separate receipt.

Final B focused suite: **96** API/CLI/scope/negative checks pass, including all
nine kind pairs, all axes, exact large integer and signed-slack arithmetic,
strict optional metadata after coherent outer rehash, member-byte corruption,
verified-empty versus unavailable inventory, stale stored assertions, source-generation
mutation and explicit 1MiB rejection. Existing regressions pass: PT.5 public27,
independent-review19, physical56; stage-report contracts; CLI43/packaging17;
named timing282 and ordinary timing150 synthetic/native-boundary checks. No EDA.

Opt-in repeatable actual-reader acceptance is
`test/variant_comparison/retained.py --consumer ... --cli ... --area EXECUTION
--delay EXECUTION --synthesis RUN --physical RUN`. It launches only the public
consumer/CLI with tool lookup denied. Final run passes API/CLI parity and preserves
**1860** files (hash/size/mtime) across the four selected evidence trees. It checks
per-corner electrical goals, physical closure pass and separate exhaustive coverage
unavailable. The first harness invocation exceeded its outer120s timeout; repeating
with outer600s completed, without changing any source or launching EDA.

Pre-review comparison digests (historical, superseded below), in named /
physical-self / synthesis-physical order:

```
79a905b7ea380d7903e0af89cf8d086dc2ef67078c16e0f58a87dfee3721944d
7c4046dbc53781f45877dca76b81f1674a1adee6dc3dca7b10d69d5000cbb797
b6fab3d2599be1521394b0f6a35a75519d606d6a5f224240884e84f72640df68
```

`source_count` is explicitly the sum of reader reference-list lengths, not a
deduplicated source claim; `timing_source_count` separately preserves the native
outer closure count (1584 for each named profile). `timing_producers` preserves
recorded native provenance. `outcomes.timing.corners` retains separate setup,
hold, electrical and annotation goals where the source API supplies them.

A owns the optional `hardware_variant` lib contract; B owns every execution-side
manifest whitelist/validation addition. C should use this module and CLI directly;
do not implement a local comparison/parser. Original named paths remain path-bound.

## R1–R4 corrections and final B qualification

Addresses [A's independent comparison review](pt8-comparison-review.md). Its
original repro code and receipts in `test/pt8_comparison_review/` were **not
edited**. B added `test/variant_comparison/admission.py` and extended the existing
B native-reader acceptance for the correction controls.

### Exact corrections

| Finding | Correction and actual control |
| --- | --- |
| R1 — unchecked coarse source declarations | `Resource_inspection_service.comparison_snapshot` runs the existing bounded bundle-member verifier on the **selected retained manifest's directory**, not a guessed/current source tree. It binds that exact manifest hash, verifies all declared member bytes, and checks source `path`/`inputs/<path>`/copy-hash associations, duplicate copies and complete copied-input enumeration. The verified bundle references enter both captures and final source-generation replay. Corrupt/missing inputs now reject exit2 instead of reusing the intact digest or deltas. |
| R2 — unsafe stored results opens/reopens | New shared `Retained_file` admits the **actual opened descriptors**: component-by-component `openat` with `O_NOFOLLOW`, a nonblocking read-only leaf, regular-file `fstat`, preallocation byte bounds, and descriptor/path post-read consistency checks. This is not a stat-only precheck. `Report_service.run` consumes stored results once through that path; comparison no longer opens an unbounded pre-read and then lets report reopen unchecked. FIFO, symlink, directory, oversized sparse file and open-time FIFO replacement reject promptly. |
| R3 — raw stored-generation omission | The actual metadata consumer records raw SHA256/byte length/path for each consulted run/results/manifest document. Those `metadata_sources` enter comparison's `consulted_metadata`, source digest and final replay. A stable formatting-only rewrite yields a new digest with unchanged metrics; the same rewrite after left capture rejects the pair with `comparison source generation changed`. |
| R4 — optional metadata duplicate loss | Archive reads retain original manifest bytes. Presence of `hardware_variant` triggers strict duplicate-free parsing of those **original bytes before the hardware codec**, including escaped-key aliases and nested assignment/descriptor duplicates. The run manifest hash is compared with the bytes actually consumed. Genuine absent schema1 metadata retains historical evidence semantics; valid new metadata and genuine failed evidence remain readable/archivable. |

`Report_service.run` adds optional `render_human` (default true) and
`strict_sources` (default false). Comparison uses false/true respectively, avoiding
unused supplementary human-report reads and rejecting corrupt stored resource
assertions before fresh reconciliation. Genuine failed resource/timing outcomes
are still data, not query errors. Ordinary report verdict/rendering defaults retain
their existing behavior. Actual report metadata is bounded at32MiB/file and64MiB
aggregate; supplementary report text uses the descriptor-safe bounded reader.

Wire schema/capability and the1MiB whole-response limit remain unchanged.
Additive side fields:

- `verified_bundle_sources`: raw-bound full bundle-member references (coarse and
  bundle targets); this supplements, rather than relabels, resource-observation refs.
- `consulted_metadata`: actual report metadata path/SHA256/byte-length references.
- `source_count` now includes those reference lists and still explicitly reports
  `sum_of_reader_reference_lists_not_deduplicated`.

Full comparison-source replay remains substantial work; these corrections do not
claim a scheduler or an absolute wall-clock bound. Native toolchain authority
continues to come from the checked execution binding/process/producer evidence,
not merely equality of producer-reported environment labels.

### Durable tests and unchanged independent repros

All builds used switch `5.2.0+ox`, explicit `-j6`, and
`/tmp/opencode/asic-pt7-build.lock`. No EDA, additional functional simulation,
provider/configuration mutation, Git mutation, Protemu or Workbench changes.

- **B focused96 + new correction43 checks pass** through actual API/CLI services.
  The43 cover corrupt/missing declared inputs, source/copy mismatch and duplicates,
  safe actual Report opens, FIFO/symlink/directory/oversize admission, a symlink
  ancestor, open-time results-to-FIFO replacement, stable and racing raw formatting
  changes, escaped/unescaped archive duplicates, and true failed evidence accepted.
- **Regression passes:** report585 policy/human differentials; archive16
  differentials plus its15/19 unit suites; PT.5 public27/review19/physical56;
  stage reporting; CLI43 and packaging; ordinary timing150/named timing282
  synthetic-native fixture controls. `@install` builds successfully.
- Unchanged A `probes.py`: intact coarse control exit0; corrupt/missing coarse
  source exit2; results FIFO exit2 with `timed_out:false`; raw formatting race exit2
  with `mutation_completed:true` and distinct old/new results hashes. Receipt:
  `/tmp/opencode/pt8-b-r1-r3-recheck.json`.
- Unchanged A `metadata_probes.py`: all ten archive/compare calls agree: genuine
  absence and valid metadata exit0; duplicate optional, duplicate assignment and
  present-null cases exit2. Receipt: `/tmp/opencode/pt8-b-r4-recheck.json`.
- Unchanged A `metric_probes.py`: coherently rebound native signed hold slack and
  count still compare (negative right-minus-left slack, exact count delta7);
  native count `2^53+1` remains unavailable. Removing the authoritative binding
  still rejects exit2. Receipt: `/tmp/opencode/pt8-b-metric-recheck.json`.
- Unchanged A syscall tracer: public physical-self response406112 bytes,
  **no mutation/network syscalls**, exactly the same-process public CLI/helper
  exec pair; no external tools or renderer. Receipt:
  `/tmp/opencode/pt8-b-trace-recheck.json`.

Repeatable B commands:

```sh
flock /tmp/opencode/asic-pt7-build.lock \
  opam exec --switch=5.2.0+ox -- dune build -j6 \
  @install @test/variant-comparison test/pt8_comparison_review/review_api.exe

python3 -B test/variant_comparison/admission.py \
  --consumer _build/default/test/variant_comparison/consumer.exe \
  --cli _build/default/bin/flow_cli.exe
```

The opt-in `retained.py` command above now also accepts
`--check-declared-inputs`: it first checks a clean disposable copy of the actual
physical run, then requires both API and CLI to reject corruption/deletion of its
actual declared input. Final run passes that control plus the original named,
physical-self and synthesis/physical API/CLI matrix. **All1860 original selected
files retain their exact hashes, sizes and mtimes.**

Post-correction comparison digests (named / physical-self / synthesis-physical):

```
7cf3dd62688e5835fcb30437380d280c401243f9a4535803f1801022a0c2d991
755ffb7a8b8dc6caeda8eceda4c432d0957bc2c377c807ecce0ced1857f342e3
0969f1b9450053eda28502bad1a964b5fb60a8e31deac127c6a7f268092e00d7
```

Physical-self still has18 comparable native zero deltas; synthesis/physical has18
confounded native metrics with null deltas. Separate closure and exhaustive-coverage
outcomes remain intact. Preparation declarations remain opaque provenance, not
typed hardware-use proof. Exact macro `Methodology_plan.prepare` remains the
reviewed **pre-existing unsupported named-macro boundary**; it was not enabled.

### Final corrected source hashes for recapture

Local SHA256 bookkeeping, not a P6/source-artifact attestation:

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
f1833995d985df483a057141bb7fbf8a254179f1291d05f9777900da384dcc40  execution/dune
b3992afa4300f7f506629d5fc3adc37005ba8ad4090155ea6aab869fb739b573  test/variant_comparison/admission.py
```

Actual tested executables (C should build its own private capture):

```
7b7c63d924341e215028318354980312176a80362ad64c5fe5c327ea851cc52e  experimental_compare.exe
226dd0df19e503e86ec192d450d8d23741ab9ee863a8034f5657f7a15da45fa2  flow_cli.exe
3427d75a754d2b7e88d30c1b3395f44fce04fce846bb12a2fc7a01ad54814f76  test/variant_comparison/consumer.exe
```
