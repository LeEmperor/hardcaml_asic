# Independent review of A's physical timing library policy

2026-10-29. **Verdict: no blocking defect found in the supported scalar CMOS5L /
checked-TT-interface scope.** This is an independent source, emitted-contract,
inert native-API-model and actual-Liberty review. It does not establish routed
timing closure, functional equivalence of arbitrary physical transforms, analog
CDC/reset correctness, or a new native/EDA acceptance result.

B reviewed A's library implementation separately from B's execution/readers.
No A implementation, A handoff or A test file was edited. C's reported198 passing
native controls and its first running full flow are separate evidence; this review
did not launch, restart or interfere with physical execution.

## Scope and reproducible evidence

Reviewed production boundaries:

- `lib/elaboration/timing_tcl.ml`: shared exact-object primitives, physical hop
  allowlist, backward walker, complete native register inventory, checked map and
  trace publication, resolve/application ordering.
- `lib/elaboration/timing_intent.ml`: original architectural validation, explicit
  physical policy/metadata and default serializer selection.
- `lib/elaboration/context.ml`: scalar-register registration, unique stage/Q UID,
  owned anchor/keep attribute.
- `lib/elaboration/bundle.ml` and interfaces: explicit opt-in, no-macro/nonempty
  intent admission, emitted SDC and identity-covered marker.

New independently authored review probes are isolated in
`test/timing_physical_library_review/`. They do **not** import A's graph fixtures,
A's resolver tests or A's collateral checker. They use public production emission
from a separate OCaml consumer and a separately implemented inert Tcl object graph.
The graph probes execute the exact resolver suffix of the emitted bundle SDC;
the unchanged clock/environment prefix is inspected as emission, not simulated as
timing by an inert model. Actual Liberty is inspected with a separate lexical /
balanced-group reader; no EDA tool or simulator is invoked.

Commands actually run:

```sh
opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  dune build -j6 test/timing_physical_library_review/review_emit.exe

opam exec --switch=5.2.0+ox -- flock /tmp/opencode/asic-pt7-build.lock \
  python3 -B test/timing_physical_library_review/review.py \
  --asic /home/wayne/devel/jane/hardcaml_asic \
  --pdk /home/wayne/devel/jane/hardcaml_asic/.toolchain/pdk
```

Successful retained receipt:
`/tmp/opencode/timing-library-independent-review-y1iq1892/results.json`.
Its directory also retains emitted bundles/SDC, per-probe Tcl scripts and complete
stdout/stderr. **83 graph observations** comprise42 valid graph cases,34
resolve-before-apply negatives, two application failures, failed-reload invalidation,
three legacy-policy rejection controls and one partial-declaration inventory case.
Separate public API/identity controls and three real Liberty inspections also pass.
These heterogeneous checks are not83 native EDA runs.

The first reviewer-harness iterations corrected only the new review probes:
recognizing that full bundle SDC has a clock/environment prefix, preserving a
duplicate query result rather than silently deduplicating it in the model, and
normalizing the actual inverter function's unary parentheses. No product finding
was inferred from those harness mistakes; earlier temporary directories remain.

## Source conclusions and bypass checks

### 1. Exact roots, cycles, aliases and bounded transforms

`timing_tcl.ml:257–294` walks backward from each sink/anchor. It checks every net's
visited full name before accepting a hop, rejects top-input contention before
traversing internal drivers, and requires exactly one internal output driver.
Port roots additionally require exactly the declared input port on that internal
net and zero internal drivers. It uses the checked Port→Pin→Term→internal-Net
conversion; it does not substitute the external top Pin.net or guess a root name.

The Q-root condition compares the actual unique driver with the already resolved
predecessor Q. A same-master flop in another chain is not accepted as a predecessor.
Anchor discovery accepts only the exact four supported reset-flop masters and
their noninverting Q pin. Two anchors resolving to one sequential cell reject.
`physical_hop` (`234–244`) uses an exact master set, exact A-input/X-output roles and
directions; there is no prefix admission, logic-polarity inference or wildcard
fallback. Eight hops accept, nine reject. Shared fanout is correctly permitted;
the constraint is unique upstream drive, not a single downstream sink.

Independent negatives include self/two-buffer cycles, a cyclic moved anchor,
direct/buffered wrong-stage roots, merged roots, input/input and input/Q aliases,
intermediate input contention, multiple Q drivers, Q_N anchors, wrong pin roles,
unsupported flop/size names and unknown delay/buffer suffixes. Every such case
rejected before any `set_false_path` attempt. Direct and eight-hop positives,
including moved anchors, exercise the same guards rather than removing the guard
to manufacture a pass.

### 2. Complete sequential inventory and checked endpoints

At `296–330`, every run first invalidates maps/traces. All declared anchors resolve
to distinct supported sequential cells with checked Q/D/CLK/RESET_B pins and a
noninverting trace to the primary clock. The full result of native
`all_registers -cells` is sorted and compared with the resolved cell list. The
comparison does not discard duplicate native entries or merely compare counts.
An extra hidden FF/latch, missing cell or duplicate inventory entry rejects; an
arbitrary native iteration order accepts.

The inventory claim is **native implementation inventory**, not an elaboration-time
claim that source declarations alone prove all state survived. An independently
emitted partial declaration is allowed through bundle rendering but then rejects
against the model's full native register inventory, before applying exceptions.
That is the documented boundary, not an admission bypass.

`context.ml:248–266` also rejects two stage IDs registered against the same scalar
register UID, preowned reserved anchors and competing keep attributes. The original
`Timing_intent.resolve` validation remains unchanged relative to HEAD: actual
register presence, rising primary clock, unsupported enable/clear rejection,
contiguous chain indices, direct architectural predecessor data and requested
capture/reset connectivity/polarity checks remain in place. Independent public
API controls reject duplicate-Q registration, a reserved-anchor conflict and a
wrong architectural predecessor.

The published checked map contains the actual resolved cell/q/data/clock/reset
objects plus declared stage identity. The model verifies every stage's map against
its native objects, including all four supported flop variants. Access from inside
each exception-application callback remains unavailable. After successful resolution
and application it becomes available; a later failed physical reload invalidates
both map and trace access rather than returning the prior result.

This is a per-resolution native-context map, not a guarantee that opaque objects
remain valid after arbitrary later database mutation. The qualified flow's fresh
analysis/SDC/hook lifecycle and C's real object controls remain the execution seam.

### 3. Resolve all before apply; narrow scopes remain narrow

`timing_tcl.ml:331–374` first validates all downstream predecessor traces and all
enumerated capture/reset sources, then emits `validated`, then applies exceptions.
No topology check is deferred until after the first application. Capture remains
one external input→first-stage D; reset remains the enumerated RESET_B set.
There is no chain-wide false path, Q-target exception or guessed reset inversion.

The independent model records actual application attempts separately from emitted
events. All34 topology/inventory failures—including a mismatch at the final reset
target after earlier capture resolution—have zero attempts and no validated/applied/
complete success events. For successful cases, validated precedes every native
application; applied follows a successful return. Exact capture/reset source and
target sets are compared with the emitted declaration in every valid case.

When application itself fails at attempt1 or2, checked access remains unavailable
and no complete event is emitted. The second-failure case truthfully retains one
successful native application: exception application is not transactional and A
does not claim rollback. B's failed-process/receipt handling must continue to
prevent that partial application from becoming completed coverage.

### 4. Explicit opt-in, identity and historical synthesis behavior

`bundle.ml:616–631,710,780–784` makes physical qualification explicitly opt-in and
rejects missing timing intent or selected macros. The marker and physical-v2
resolution policy enter the bundle payload, while the actual physical SDC enters
its file hash inventory. `timing_intent.ml:141–166` selects physical rendering only
when requested; default behavior remains v1.

Independent public emission verifies:

- default and explicit false bundles/SDC/identity are identical;
- physical true changes identity and policy/marker, while emitted RTL and native-v2
  producer bytes remain identical;
- SDC bytes match their recorded SHA256 in both variants;
- changing marker hop budget, endpoint-map name or corner policy, removing the
  marker, or relabeling physical intent to v1 without a new identity rejects via
  the public manifest verifier;
- empty intent rejects physical rendering;
- v1's shared primitive Tcl block is byte-identical to `HEAD`, and v1 still rejects
  newly qualified interstage buffers, delay transforms and moved anchors.

Read-only source diff inspection confirms that the original architectural resolver
and registration implementation were not loosened, the legacy Tcl body stayed
frozen, and the new default-false branch preserves the former serializer call.
The physical marker is requested analysis/preservation intent, not execution or
timing closure evidence.

## Independent actual Liberty table validation

The review inspected actual supplied standard-cell Liberty at all three configured
PVTs, with each file's hash checked unchanged before/after inspection:

| Standard-cell corner | SHA256 |
| --- | --- |
| fast_1p32V_m40C | `af12d75a72d19648fa690027d29843fbae550aa91f4e40dd3339c7116d6e425d` |
| typ_1p20V_25C | `34163f3e7de9f854afac57332ba06f1739b78e7ac35660a8a5ddd39c570124ad` |
| slow_1p08V_125C | `3ee222c580ba33acb2131ac2bf224ff8ee9700751835b73aaec72b670bb31d3c` |

For **all24 cell/corner combinations** of the five exact
`sg13cmos5l_buf_{1,2,4,8,16}` masters and three exact
`sg13cmos5l_dlygate4sd{1,2,3}_1` masters, the independent parser found only signal
pins A/X, A=input, X=output, function exactly `A`, A-related positive-unate timing
arcs, and no ff/latch/statetable group. This checks supplied function and pin/arc
data rather than inferring behavior from the master name or a drive suffix.

The actual `sg13cmos5l_inv_1` control has Y=`!A` and negative-unate timing arcs.
It is not in the allowlist; both one and two inverter clock paths reject. The
walker does not guess that an even number of inversions is a qualified clock path.

All12 supported-flop/corner combinations were also checked for one ff state group,
rising `CLK`, next state `D`, active-low `RESET_B` clear and no preset. Native Q
corresponds to the noninverted state variable, with D/CLK/RESET_B input directions.
Together with the exact-master and unique-cell checks, this supports the bounded
sequential/pin semantics; it does not establish reset-release protocol safety.

## Reviewed source identities and limits

The receipt verifies these A-owned source bytes unchanged across the review:

```text
4668e8a571b12adfb79841e1ea0e0d00f384f00b98d7b80be8dbadf6e9dae59e  timing_tcl.ml
d02750efe28a53de64316152075d778fc19eab9e52e87fbcbd020e7a024905f5  timing_intent.ml
75651c9ed4a4625eff775ab1db42ece76130b93958fd065dbe53a1a0e0c9cb77  timing_intent.mli
897e03816953019fc709ce16cff603eb7cfd242a6fe51c5844c35dd76bdf5e5c  bundle.ml
8e3e36114559fd985a9151cf5e275535fe7f4cf812c058c74803717a589900e3  bundle.mli
a6738335934c8161ac05db00d00284c7461a319723af2d230d4ad1b54adf6722  context.ml
```

No blocker or required A correction was found for this bounded contract. These
checks complement C's198 native controls; they do not replace actual library/model
binding, routed preservation, extracted all-corner setup/hold/electrical closure,
functional final-netlist replay, or independent review of C's actual full evidence.
Fresh process/single-SDC audit association remains B's responsibility; arbitrary
mixed-policy Tcl reloads or database mutation are not certified by this review.

The one checkout build used switch5.2.0+ox, explicit-j6 and the shared ASIC lock.
Subsequent review probes and Liberty parsing were synchronous under the same lock.
No EDA, Git mutation, provider selection, supplied collateral modification,
Workbench/Protemu change, or edit to A's implementation/tests was performed.
