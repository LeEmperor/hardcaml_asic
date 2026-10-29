# PT.8 first slice — declared hardware variants and checked pair comparisons

2026-10-29. Written before implementation. [phase_plan.md](../phase_plan.md) is
the only active queue. This is general-purpose library/CLI infrastructure accepted
through `hardcaml_asic_example`; Protemu parameterization/selection is not authorized
or implied. Preserve current physical-qualification changes and retained evidence.

**First bounded slice accepted 2026-10-29.** Original plan follows; the closeout
below records tested scope and remaining obligations rather than a second queue.

## Bounded scope

1. A small checked hardware-parameter declaration, passed to the project factory
   and carried into the existing project/elaboration/bundle/plan identity chain.
2. Read-only comparison of exactly two explicit bundles, coarse runs or execution
   JSON files, with an explicit intended axis: hardware, resource policy, flow
   configuration, or descriptive/uncontrolled comparison.
3. Parameter-specific example conformance and honest comparison acceptance, using
   fresh emitted variants and retained executed evidence. No new synthesis/P&R,
   sweeps, scheduling, UI or workload parser is allocated for this slice.

Reuse existing flow catalogs/profiles, resource policy/selection and evidence
parsers/replay. Hardware parameters are not backend `Flow.Parameter` assignments.
Do not claim that hashing a declaration or calling a getter proves its semantic
use by hardware. Constructor binding prevents independent label/input mixups;
reviewed adapter conformance tests establish actual parameter behavior.

## Exclusive ownership and dependencies

| Owner | Files/scope | Acceptance |
| --- | --- | --- |
| A: hardware contract and identity | New `lib/hardware_variant.*`, curated export, `Project`, elaborated metadata/bundle/methodology integration, focused old manifest gates by agreement; `test/hardware_variant/` | Strict complete typed assignments, canonical identity, factory binding, optional manifest metadata, legacy absence and one-render behavior |
| B: comparison service/CLI | New `execution/results/variant_comparison.*`, small shared projections if needed, execution manifest compatibility gates, CLI/capabilities/packaging; `test/variant_comparison/` | Verified explicit targets, separate identities/differences/outcomes, metric-specific context and eligible deltas, no independent tool parser |
| C: independent example | New example variant adapter/tests/scripts/docs/evidence and isolated `.dev/asic-pt8` / `_build_pt8` | Actual memory-depth parameter conformance and ignored-parameter negative, policy/profile separation, installed public comparisons and source preservation |
| Coordinator | This plan, phase queue/guide, orchestration and review | Frozen interfaces, timely todo progress, independent review and actual acceptance |

A publishes `pt8-variant-handoff.md` concrete schema/signatures before dependent
integration. B publishes `pt8-comparison-handoff.md` concrete public wire/policy.
A owns `lib/`; B owns execution manifest validators and root/bin test/build declarations.
Coordinate whitelist additions through B; do not edit the same files concurrently.
Prefer isolated test directories. C implements no production parser/comparison engine.

## Hardware declaration contract

- Unique design/schema/parameter identities; bounded integers, booleans and closed
  enums only. Complete assignments, no unknown/missing/duplicate keys, finite scalar
  limits and bounded schema size. No arbitrary JSON/expressions or default layers.
- Canonical encoding/digest via existing plan JSON infrastructure with a distinct
  contract/domain; input order doesn't change normalized declaration identity.
- A factory seam passes the exact immutable checked assignment to construction and
  attaches that same declaration to its result. Reject conflicting/repeated attachment.
  All parameter combinations still require consumer-side validation where necessary.
- Optional `hardware_variant` manifest member is validated and identity-covered;
  actual RTL/config/SDC/source inputs remain independently covered. Existing plan
  identity includes the resulting bundle. No independently writable second copy.
- Legacy absence means parameters not recorded, never inferred defaults. Legacy
  bundle identity and historical reader semantics remain unchanged when absent.
  Project declaration inspection/preparation must retain the association without
  inventing preparation-to-bundle or compiled-source/P6 attestation.

## Pair comparison contract

- Explicit targets `Bundle path`, `Coarse_run path`, `Execution exact_json_file`;
  exactly two, caller-specified axis. Do not infer target kind, latest run or current
  catalog selections. Frozen methodology/effective settings remain authoritative.
- Use existing source-aware resource, stage report and timing services. Invalid
  required evidence rejects; genuine historical absence/unsupported measurements
  remain unavailable. Never treat source corruption as a missing optional metric.
- New standalone comparison schema1 and capability, deterministic comparison digest
  bound to both captured source generations, intended axis and comparison policy.
  Bounded whole JSON response (target<=1 MiB and explicit row/work limits); no new
  paging/source-byte API in this first CLI-first slice. Reject limits, never silently
  truncate into a complete comparison. Existing per-target source limits still apply.
- Retain separate hardware declaration, resource policy/contract/selection,
  methodology/profile/effective settings, source/environment/corner/model differences
  and exact bundle/run/attempt/occurrence/publication identities. Equal output bytes
  never merge attempts. Netlist differences are expected for hardware variants,
  not alone a reason to reject all comparison.
- Each metric has provider-owned definition/classification/unit/stage/scope and
  source references, with `comparable`, `confounded` or `unavailable` plus reasons.
  Only finite observed/derived values with matching required context get an exact
  `right_minus_left` delta. Estimates remain estimates without measured deltas.
  Preserve signed slack; exact integers must not silently round through floats.
- Supported first metric projection is small: existing verified resource/cell/area
  measurements and native whole-design timing metrics where existing APIs expose
  them. No new Yosys/Liberty/STA parser for comparison, no promotion of sampled paths
  to worst slack, no mixing synthesis and physical or unmatched corners/models/RC.
- If a required control/context is unknown, withhold the delta. An axis describes
  intended differences, not causal proof or a blanket waiver for other differences.
  Execution success, resource retention, physical/timing acceptance and exhaustive
  coverage remain separate outcomes. No overall winner, scoring or auto-selection.
- Workload/firmware size/fetch count/latency/throughput comparison remains explicitly
  unavailable: no verified generic workload contract exists yet. Labels alone prove
  neither common workload nor hardware use. No PT.8 consumer selection completion.
- CLI exit0 means a valid readable comparison, including confounded/unavailable or
  failed source outcomes; exit2 means invalid/corrupt/inconsistent input. Comparison
  never executes tools, rerenders, publishes, rewrites histories or probes PDKs.

## Acceptance

1. Library/schema negatives, normalization, complete type/bound checks, semantic
   source/factory association, one-render/deterministic bundle, strict historical
   absence and manifest/plan compatibility.
2. Example memory parameters width16/latency1 and depth128 vs256 under explicit
   Flops; check actual registered request, memory capacity/address boundary and
   read latency/behavior. A deliberately ignored depth parameter must fail the
   conformance oracle despite valid declaration/bundle hashes. Exact256 succeeds;
   unsupported Exact128 rejects; no rounding/banking/fallback invented.
3. Fresh variant bundles through public installed APIs and policy/profile-only
   changes. Existing executed named area/delay pair remains separate attempts with
   equal netlists; old records without hardware metadata stay metadata-unavailable.
4. Compare accepted coarse physical vs itself and synthesis vs physical, keeping
   source/stage/corner/environment/model differences and measured-vs-estimate rules.
   Retained physical closure pass cannot become exhaustive coverage pass.
5. Semantic negatives and cross-attempt/source substitutions, alias/full-PDK closure
   bounds, captured-generation changes, nonfinite/large-count arithmetic, CLI/API
   parity and no-write/tool-launch/source-preservation tests.
6. Independent cross-review after initial suites; fix/retest findings and final
   installed example checks. Broaden affected existing tests once justified.

## Execution policy

Maximum20 jobs globally, three agents<=6 each, two reserved. Every Dune invocation
explicit `-j6` or lower, switch5.2.0+ox. Keep the existing shared checkout locks
`/tmp/opencode/asic-pt7-build.lock` and `/tmp/opencode/example-pt7-build.lock` to
serialize all builds, including separate directories and private capture work.
Nested captures count within their owner's allocation. **EDA allocation zero**:
use pure/functional tests, new emitted bundles and retained native evidence.
No Git mutations, old provider/config/daemon changes, Protemu or Workbench actions.

## Implementation and acceptance closeout

Implemented `Hardware_variant`, factory binding through `Project.of_variant`,
optional elaboration/bundle/methodology metadata, and public
`Variant_comparison.inspect` / `hardcaml-asic-flow compare`. The complete contract
and commands are in the [guide](../guides/variant-comparison.md),
[hardware handoff](pt8-variant-handoff.md) and
[comparison handoff](pt8-comparison-handoff.md).

The first schema has complete bounded int/bool/enum assignments with canonical
ordering/digest. Project construction gets the same immutable checked value once;
repeated/conflicting attachment rejects. Actual RTL/config/SDC/source identity
remains separate from declaration identity. Legacy absence stays omitted with its
original identity; no defaults inferred. Restored resource-preparation declarations
remain opaque tagged metadata, not a second typed hardware-conformance proof.

Comparison uses explicit target kinds/axis and existing source-aware services.
It preserves exact identities, declaration/policy/profile/context differences,
separate outcomes and metric definitions. Only eligible observed/derived quantities
get right-minus-left deltas. Unknown or different required context withholds them;
estimates and sampled reports are not promoted to measured physical/worst-path
results. Whole responses are bounded at1MiB; corruption/limit violations reject.
No workload parser, winner, scheduler, new EDA or current-catalog lookup was added.

### Independent findings and corrections

[Variant review](pt8-variant-review.md) found no blocking library defect across
173 adversarial wire and45 integration controls. A coherently rehashed opaque
preparation declaration can remain readable as opaque metadata; no typed semantic
validation of that generic historical field is claimed. Exact macro named-plan
preparation rejection was independently confirmed as pre-existing, not a new PT.8
regression; it remains unsupported.

[Comparison review](pt8-comparison-review.md) found four real defects after initial
suites passed: unchecked actual coarse input-copy bytes, blocking/unsafe stored
results admission, missing raw consulted-generation hashes, and duplicate fields
lost before optional archive metadata validation. Fixes verify actual bundle bytes,
use bounded nonblocking descriptor-bound regular-file reads with path replacement
checks, bind raw consulted metadata generations, and validate original manifest
bytes before decoding. FIFO open races, whitespace-only generation changes and
coherently rebound duplicate metadata now reject for their intended reasons.
The original reviewer scripts were rerun unchanged; all findings are closed.

### Corrected installed example

Final generation: `f205e0d66f8d4f2b8d1e5f098171bb21`.
Captured source snapshot:
`1f5ac45882b29c7d577937b4ba2eb8960a899bd2221eaae5b3e115a111de3213`.
[Final installed acceptance](../../../hardcaml_asic_example/docs/pt8_corrected_final.md)
and `acceptance/pt8/final-corrected-seal.json` bind actual source/executable hashes,
commands, source comparisons and preserved earlier failures. This documentation
closeout postdates the tested capture, without replacing its identity.

- Six actual functional simulations: five positives over depth128/256/Exact256
  supported modes and one intentionally ignored-depth negative. Independent
  registered-request and address-boundary tests both detect the ignored parameter.
  Exact128 rejects with no fallback; unsupported depth192 rejects in the factory.
- 204 installed comparison assertions repeated on the corrected capture, including
  public API/CLI equality, hardware/policy/profile separation, actual old named
  attempts with equal netlists, physical self and synthesis/physical comparison.
  Physical self has18 native zero deltas; synthesis versus physical has18 confounded
  native rows with null deltas. Missing historical hardware/workload metadata stays
  unavailable; a closure pass never becomes exhaustive-coverage pass.
- 18 targeted correction cases across38 traced invocations cover actual retained
  coarse inputs, descriptor-open FIFO races, symlink/directory rejection, inclusive
  32MiB metadata boundary/+1 rejection, raw-generation changes and archive duplicates.
  Separate matrix uses26 traced invocations. No service subprocess beyond native
  CLI/helper replacement, renderer/tool, filesystem mutation or network call occurs.
- 108,338 prior files and65 symlinks remain unchanged, including earlier PT.8
  generation/evidence and physical/named/resource histories. Constructor/oracle
  source equality justified no repeat of the six functional simulations after
  reader corrections. Source observations are not P6/execution authentication.

Provider verification includes85 schema/41 integration library checks,96 original
comparison plus43 durable correction checks, independent reproduction/true controls,
and affected resource, named/coarse timing, report/archive/CLI/packaging/install
regressions. Counts describe different test groups, not a summed universal test
total. No final forced whole-repository suite or new EDA is claimed.

### Remaining work and operating bounds

Consumer-specific parameters/workloads and final selection remain PT.8a–c in the
phase plan. A verified workload-result contract is needed before firmware size,
fetch counts, latency and throughput comparisons. Macro bundle emission is
supported, but existing Exact macro `Methodology_plan.prepare` is not enabled.
Named relocation/archive and additional native timing scopes retain their existing
limits; this reader does not repair or enrich historical producers.

All builds used explicit six-job limits, switch5.2.0+ox and shared checkout locks;
nested captures count within the owner allocation. No Git mutations, old provider/
app/daemon changes, Protemu or Workbench work. EDA allocation/use remained zero.
