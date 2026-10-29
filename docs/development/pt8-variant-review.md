# PT.8 A — independent B library review

2026-10-29. Review of A's hardware declaration, factory, identity and library
propagation against [the agreed plan](pt8-variant-plan.md) and
[A's concrete contract](pt8-variant-handoff.md). B owns comparison/execution, not
A's library implementation. **No A implementation or A test files were edited.**

## Disposition

**No new blocking defect found in the bounded A implementation.** Independently
executed **173 adversarial wire checks and 45 factory/propagation controls** pass.
A's existing 85 schema and 41 integration checks also pass when executed directly.
This is library/metadata qualification, not proof that arbitrary factories use
their parameters or that a consumer has passed functional/physical acceptance.

Two boundaries deserve explicit recording:

| ID | Severity / disposition | Actual result |
| --- | --- | --- |
| R1 | Informational: pre-existing unsupported named macro capability; not a PT.8 regression | Exact256 public rendering succeeds both without and with a hardware declaration. `Methodology_plan.prepare` rejects both at the old manifest whitelist. Additional existing named-classic input gates also forbid macro sources/settings. |
| R2 | Low, nonblocking trust-boundary qualification; inherited preparation format, not a new typed-codec bypass | Preparation stores a generic tagged S-expression declaration. A self-consistently rehashed malformed hardware-claim atom remains readable as an opaque declaration; it is **not** decoded as a checked `Hardware_variant.t`. Typed hardware, bundle and methodology-plan readers reject the malformed claim. |

No macro named-flow/checkpoint support was enabled. Existing physical changes,
source histories, providers/configuration and other repositories were preserved.
EDA allocation/use was zero; no new functional simulation was run.

## R1 — Exact macro Methodology.prepare is an existing boundary

### Reproduction and controls

The independent probe declares an actual stock 256×16, latency-one RAM under
explicit `Exact` policy, with normal TT ports, source inventory and a synthesis
catalog. It exercises **two projects**:

1. Plain `Project.create`, `hardware_variant = None`.
2. `Project.of_variant` wrapping that same plain project.

For **both**, `Project.render_result ~methodology ~include_simulation:false`
succeeds and the resulting bundle contains `macro_contract`. For **both**:

```text
Methodology_plan.prepare ~catalog ~endpoint:Synthesis
  ~include_simulation:false project ~source_root
=> Error (Invalid_argument "object fields do not match versioned schema")
```

This uses elaboration/rendering in memory, not an implementation run, publication,
PDK probe or tool launch. The exact absence/presence controls appear in the
`exact_prepare` object printed by the probe.

### Source attribution

- Current `lib/methodology_plan.ml:155–205`, `verify_associations`, only adds
  `hardware_variant` to its optional field list. It still excludes `macro_contract`.
- Read-only `git show HEAD:lib/methodology_plan.ml` confirms the **same exclusion
  before PT.8**. The feature diff adds the hardware getter and optional hardware
  field; it does not introduce a macro exclusion.
- `lib/flow/methodology_inventory.ml:25–27,97–107,127–132` already forbids
  `MACROS`/`EXTRA_VERILOG_MODELS` and other additional input settings and requires
  the single provider-generated synthesis RTL source. `git diff --
  lib/flow/methodology_inventory.ml` is empty.
- Segmented execution has a separate existing macro/checkpoint restriction in
  `execution/backends/librelane/stage_preparation.ml`; accepting a plan header
  would not qualify that execution path.

**Conclusion:** C's retained Exact256 preparation failure is not caused by hardware
metadata. The supported public resolve/render/publication path remains suitable
for the requested new bundle comparisons. Do not add `macro_contract` to a whitelist
alone or delete its marker: additional inventory, collateral, checkpoint and
execution qualifications would still be needed for named macro support. C's
`docs/pt8_handoff.md` / `docs/pt8_final.md` correctly retain that limitation.

## R2 — preparation declaration integrity is not typed hardware validation

### Reproduction and actual controls

The independent probe first obtains a real `Project.prepare_resources` result.
It then performs an **in-memory** negative:

1. Replace only its tagged-S-expression `hardware_variant` atom with
   `{"contract":"hardcaml-asic.hardware-variant","schema_version":999}`.
2. Recompute the existing configuration identity using
   `Preparation_json.hash "configuration" configuration`.
3. Recompute the outer preparation identity using its unchanged preparation hash
   algorithm, excluding the outer identity field.
4. Call `Resource_preparation.of_json`.

Result: the preparation reader accepts the valid generic declaration/hash envelope.
The **same atom rejects** through `Hardware_variant.of_string`. Separate controls
show that bundle/methodology-plan `hardware_variant = null`, unknown hardware
fields and invalid inner identities reject even after coherent outer rehashing.

### Why this is nonblocking in the agreed slice

`lib/resource_preparation.ml:66–88` already treats `configuration.declaration` as
an opaque tagged S-expression and verifies its configuration/outer hashes. It
does not reconstruct any typed `Project.t` or `Hardware_variant.t`, and has no
typed hardware-variant accessor. This file has **no feature diff**. Normal
producer-side preparation still carries the exact checked Project declaration
through `Project.describe` and its configuration identity.

The current coverage explicitly keeps `compiled_source_proven=false` and
`p6_source_stamp=false`. Comparison's typed targets exclude preparation records.
Therefore this does not bypass the strict hardware codec or current comparison
target validation. It does mean that a statement such as “every restored
preparation contains a typed-validated hardware declaration” would be too strong.
Any future preparation consumer exposing such a typed field must explicitly run
the hardware codec rather than trust the opaque atom.

## Strict schema and stable identity review

Reviewed `lib/hardware_variant.ml`, its public `.mli`, and
`lib/flow/plan_json.ml`. Independent `review_variants.py` invokes only the public
hardware string codec through a native probe with external tool lookup denied.
It independently signs records, including malformed ones, using the documented
domain-separated canonical SHA256 algorithm. Negatives are not explained merely
by stale digests.

Actual controls:

| Area | Probed result |
| --- | --- |
| Canonical ordering | All 72 combinations of parameter order, assignment order and enum order, with reversed outer object order, normalize to the original declaration/digest. |
| JSON escaping | Escaped ASCII key/value spellings normalize identically; duplicate keys expressed through `\u` aliases reject at outer, assignment and descriptor levels. |
| Integer bounds | Inclusive −1,000,000,000, zero and +1,000,000,000 succeed. Adjacent out-of-range values, OCaml-int extremes, 2^63, 10^300 and a 10,000-digit token reject without rounding or unsafe conversion. |
| Bound descriptors | Inverted ranges, out-of-domain min/max, float/bool/null/string bounds reject with independently recomputed identities. |
| Scalar types | Float/exponent integer lookalikes, numeric strings, boolean-as-integer, integer-as-boolean, null and object/list assignments reject. Closed enums reject nonmembers and wrong types. |
| Completeness/shape | Missing/unknown assignments, duplicate parameters/enums, missing/unknown descriptor fields, empty schemas and unsupported versions reject. 64 parameters/enum members succeed; 65 reject. |
| Identifiers | Empty/uppercase/numeric-leading/non-ASCII/NUL/path-like/command-like and overlength identifiers reject. No identifier is evaluated as a path, expression or command. |
| Syntax/admission | Leading/embedded comments, trailing object, leading plus/zero, numeric underscore, nonfinite exponent, invalid UTF-8, unpaired surrogates, invalid escape and raw control character reject. |
| Limits | Exactly 128 KiB including permissible trailing whitespace succeeds; one additional byte rejects. Overdeep input rejects. A's additional constructor-size test rejects a descriptor set whose legal individual fields exceed the whole declaration limit. |

Independent constructor/signing control identity:

```text
35b91fcd974219432424b4c2305b155ab21324a53eb6a6f1af6af2f726d7c4d2
```

`Parameter`, `Schema` and the final value are abstract immutable records with no
safe mutation API. Construction bounds and normalizes before calculating the
identity. Decoding checks the full object schema, nested duplicate keys, complete
assignments, types/domains and recomputed normalized identity. Large `Intlit`
ASTs are rejected by the shared identity grammar; this never promotes an
out-of-domain bigint into an OCaml int or a rounded float. B's Evidence_json bridge
uses exact JSON bytes through `of_string`, since Evidence_json deliberately uses
Intlit even for small integer tokens.

## Factory, propagation, legacy and source-association controls

Independent `variant_review_probe.ml` adds 45 public-API controls beyond source
inspection and A's own tests:

- The factory receives the **physically identical** checked value, is called
  exactly once on success/failure/exception, and causes no design elaboration.
  Successful attachment is that same object; the original plain project stays
  unbound. Returning an already-bound project rejects equal and conflicting
  attachments, with its original value unchanged.
- `Project.describe` runs no design, appends the declaration only when present,
  and after removing just that member equals the plain project's exact S-expression.
- Elaboration carries the same assignment object. The tested render constructs
  one implementation; `Methodology_plan.of_rendered` does not rerender.
- A distinct immutable object with an equal normalized identity is accepted as
  the simulation declaration. Absent or different simulation declarations reject.
  This is declaration equality, not an assertion of hardware equivalence.
- Removing only `hardware_variant` from the emitted manifest and recomputing the
  **unchanged order-sensitive legacy bundle hash** produces byte-for-byte the
  plain project's manifest. Absence is not encoded as null or inferred defaults.
- Canonical assignment clones give equal preparation identities. An intentionally
  ignored changed parameter gives a different configuration identity but the same
  actual circuit identity. Plain preparation retains that same circuit and its
  own declaration/configuration identity. The public preparation reader roundtrips.
- A malformed inner declaration/present null rejects through a fully rehashed
  methodology plan. Changing a recorded source hash without the copied-member
  association, or using `../outside`, `/outside` or `inputs/../../outside` source
  copies, also rejects after coherent outer bundle/plan rehashing.
- A **valid** different hardware declaration with all outer identities coherently
  rehashed can decode against unchanged RTL. This is an expected metadata-boundary
  control: hash/schema integrity is not proof of semantic hardware use or producer
  authenticity. There is no semantic-use/compiled-source/P6 attestation field.

`Methodology_plan` retains the exact bundle manifest string and configuration,
verifies the existing inventory/source/configuration/effective-parameter
associations, and derives the plan identity from that inseparable render result.
Its hardware getter decodes the already-validated frozen manifest, without a
current schema/catalog lookup or an independently writable declaration copy.
The pre-existing conventional `Elaborated_project.Private` setters remain internal
API conventions, not a security boundary or a semantic conformance proof.

## Reproduction

From the ASIC checkout, build under the shared lock and switch:

```sh
flock /tmp/opencode/asic-pt7-build.lock \
  opam exec --switch=5.2.0+ox -- dune build -j6 \
  test/variant_comparison/variant_review_probe.exe \
  @test/hardware_variant/runtest

python3 -B test/variant_comparison/review_variants.py \
  --probe _build/default/test/variant_comparison/variant_review_probe.exe

_build/default/test/variant_comparison/variant_review_probe.exe integration \
  /home/wayne/devel/jane/hardcaml_asic

_build/default/test/hardware_variant/schema_tests.exe
_build/default/test/hardware_variant/integration.exe
```

Actual final results: independent wire173, independent integration45, A schema85,
A integration41, all passing. The independent probes live in B's existing isolated
test directory; they are opt-in, not edits to A's tests. Two initial reviewer-probe
compile errors (deprecated `Sys.argv`/unused helper, then Core's integer-only `=`)
were corrected in that probe before these successful runs; they were not A defects.

No source file, bundle, preparation, run, provider or catalog was published or
rewritten by the probes. Render/preparation controls are memory-only; the existing
Git calls only read the actual checkout's declared `dune-project` and revision/status.
No fixture Git repository, native EDA tool, simulator, provisioning or daemon is used.

## Reviewed source fingerprints

Local SHA256 bookkeeping, **not** a P6 stamp:

```text
5380fc7da41034bad696ee2bdc83733b85e61da8682f772718896f102424d61f  lib/hardware_variant.ml
08ca73ce78f5a984993a22f48a965342f60c0e174e2fc47fa4efb9b56c545f1e  lib/hardware_variant.mli
a183f881433afecc22a44a993aa1299912bd9c2d91ff3c971c3eca1812de8bf7  lib/project.ml
cca849201ac840548df1c33c65d230b7a3ca3361cdc8687615e0bb4a80a74254  lib/project.mli
e223a2289983b71da5cc66569182b0253f5ccf997c3da11dd6cbeb1b6ba0d67e  lib/elaboration/elaborated_project.ml
5feb34c09979a759708a7e578149da9d971b3f16c896f33477f23260e6acf03c  lib/elaboration/bundle.ml
fff894ad1014e30b887beb826ea02a87096d056541409b00c105b62e766f4e24  lib/methodology_plan.ml
a24c74bbbc3aa2f65c2490d61d158d2c63696d3bc7de4787b94188b5b0c2ebde  lib/flow/plan_json.ml
d9fd6cb6cddd2e932aa25ab1f9e91e22622aa8ab0b041489ad5cd104f16ee2ab  lib/resource_preparation.ml
daafe2df28d6ea61226e574239ecd65729ecb4c7765446655ee4db3700ab4967  lib/flow/methodology_inventory.ml
```
