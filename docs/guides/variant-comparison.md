# Declare hardware variants and compare retained evidence

The first PT.8 slice records hardware parameters in ordinary project/bundle
identities and compares two explicit retained targets through public library/CLI
interfaces. It does not launch experiments or choose a winning design.

## Keep the three configuration domains separate

| Domain | Example | Existing owner |
| --- | --- | --- |
| Hardware assignment | Memory depth128 versus256 | `Hardware_variant`, consumed by the project factory |
| Resource policy | Explicit flops versus Exact SRAM | `Resource_policy` |
| Backend configuration | Balanced versus delay-focused synthesis | Existing flow catalog, profile and typed parameters |

`Hardcaml_asic.Hardware_variant` supports bounded integers, booleans and closed
enums. Schemas have unique stable keys; assignments supply every key exactly once.
The checked codec normalizes ordering and identity, rejects duplicates/unknown
keys/types/limits, and bounds serialized input to128KiB. Integer domains are
inclusive ranges; consumers still reject unsupported tuples or gaps in a range.

Use `Project.of_variant ~variant ~create` to pass the same immutable assignment
to the project factory and attach it to its result. The factory is called once;
already-attached projects reject. Ordinary `Project.create` stays compatible.

```ocaml
let open Core.Or_error.Let_syntax in
let module H = Hardcaml_asic.Hardware_variant in
let%bind parameter = H.Parameter.create ~key:"depth"
  ~kind:(Integer { minimum = 128; maximum = 256 }) in
let%bind schema = H.Schema.create ~design_id:"example_memory"
  ~schema_id:"example_memory.v1" ~parameters:[parameter] in
let%bind variant = H.create ~schema ~assignments:["depth", Int 128] in
Hardcaml_asic.Project.of_variant ~variant ~create:(fun checked ->
  let%bind depth = H.get_int checked ~key:"depth" in
  if depth <> 128 && depth <> 256 then Core.Or_error.error_string "unsupported depth"
  else make_project ~depth ())
```

Here `make_project` is the consumer's normal project constructor. See the complete
reviewed adapter in
[`variants/variant_memory.ml`](../../../hardcaml_asic_example/variants/variant_memory.ml).

The optional `hardware_variant` manifest object is identity-covered alongside
actual RTL, SDC, configuration and declared source copies. Existing methodology
identities cover the resulting bundle. Historical absence means **parameters not
recorded**, not inferred defaults. Resource preparation includes the declaration in
its configuration provenance; its restored generic declaration is opaque metadata,
not independent typed hardware-use validation or preparation-to-bundle proof.

**A valid declaration is not proof the circuit uses it.** A factory could ignore
depth and always construct256 words. The example intentionally does that in a
negative test: metadata and hashes remain valid, but independent registered-request
and address-boundary checks fail. Supported adapters need such semantic checks.
No compiled-source/P6 or authenticated execution claim follows from these identities.

## Compare two explicit targets

```sh
hardcaml-asic-flow compare \
  --left-kind bundle --left "$DEPTH128_BUNDLE" \
  --right-kind bundle --right "$DEPTH256_BUNDLE" \
  --axis hardware --json

hardcaml-asic-flow compare \
  --left-kind execution --left "$AREA_EXECUTION_JSON" \
  --right-kind execution --right "$DELAY_EXECUTION_JSON" \
  --axis flow_configuration --json
```

Kinds: `bundle`, `coarse_run`, `execution` (exact execution JSON file).
Axes: `hardware`, `resource_policy`, `flow_configuration`, `descriptive`.
No kind/most-recent run/current-catalog inference is performed. Named inputs keep
their existing path-bound reference requirements.

Public API:

```ocaml
Hardcaml_asic_execution.Variant_comparison.inspect
  ~left:(Bundle left_path) ~right:(Bundle right_path)
  ~axis:Hardware ()
(* (Evidence_json.t, string) result *)
```

Capability `variant_comparison1`, envelope `hardcaml-asic.variant-comparison`,
schema1, policy `bounded-pair-v1`. The whole response is bounded at1MiB, with
4096 inventory/difference rows and256 projected metrics per side. Limits reject
rather than truncate. There is no paging/sweep/publication service in this slice.

## Interpret the result

The response retains left/right source digests and exact bundle/attempt/plan/
publication identities, frozen settings, resource observations, actual output
hashes, separate outcomes, domain-keyed differences and a comparison digest.
Different attempts remain different even if netlist bytes match.

Each metric is independently classified:

- **Comparable:** observed/derived values with established matching required
  context receive `right_minus_left`. Counts preserve exact integer arithmetic;
  slack stays signed.
- **Confounded:** values exist but required stage/model/corner/RC/environment or
  other controls differ; delta is null with reasons.
- **Unavailable:** a value or required control is missing/unsupported; no delta.
  Estimates stay estimates and receive no measured delta.

The axis states intended differences, not causality or permission to ignore other
controls. A bundle/netlist change is expected for hardware variants, but irrelevant
model/workload/environment differences still matter. The small metric registry
uses existing source-aware resource and native timing readers; it does not parse
new STA/Yosys reports or promote sampled witnesses to whole-design worst slack.

For example, comparing the accepted physical run to itself yields18 native
per-corner zero deltas. Comparing its synthesis baseline to the routed run yields
18 **confounded** native rows, because stage/RC/environment differ. Physical closure
pass, historical negative hold, and unavailable exhaustive coverage remain separate
facts. Equal profile-pair netlists do not imply equal attempts or a performance winner.

Exit0 means a readable comparison, including confounded/unavailable measurements
or failed source outcomes. Exit2 means invalid/corrupt/inconsistent/unsupported
input or a limit violation. Neither exit is design acceptance.

Readers verify actual retained member/input bytes, source-aware evidence and both
captured generations before returning. Consulted stored metadata bytes are part
of the generation fence; even a formatting-only change changes its digest.
Regular-file admission is bounded and nonblocking, rejecting FIFOs/symlinks and
concurrent replacement. Reads launch no tools/renderers, write no evidence and
perform no network/current-PDK discovery. Existing source-reader limits still apply.

## Accepted scope and limits

[Corrected installed acceptance](../../../hardcaml_asic_example/docs/pt8_corrected_final.md)
covers fresh depth128/256 and Flops/Exact256 bundles, profile-only changes, ignored
parameters, actual historical named profiles, physical self and synthesis/physical
comparisons, API/CLI parity and corruption/race negatives. No EDA was run.

Exact256 bundle emission is supported; **Exact macro `Methodology_plan.prepare`
remains a pre-existing unsupported named-macro boundary**. This feature does not
enable it. Historical records are never retrofitted with hardware metadata.

Firmware size, fetch count, latency/throughput and common-workload evidence remain
unavailable until a verified workload-result contract exists. There is no automatic
winner, experiment scheduler, Protemu configuration selection or UI integration.
The [PT.8 queue](../phase_plan.md#pt8--reproducible-design-variant-comparisons)
owns those remaining consumer/workload obligations.
