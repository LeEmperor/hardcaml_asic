# Exact SRAM public bundle and synthesis slice

Assignment B, 2026-10-24. This slice supplies public declaration, resolution,
bundle emission, preflight and **fresh coarse synthesis launch** for the stock
`RM_IHPSG13_1P_256x16_c2_bm_bist`. The coordinator subsequently ran the installed
provider against the independent example: mapped synthesis and zero-delay
gate-functional replay pass. See the [integration evidence](sram-example-integration.md#evidence).
Synthetic runtime tests additionally cover failures and mutation rejection;
neither those tests nor synthesis establish physical acceptance.

## Consumer API

```ocaml
val Macro_intent.tt_cmos5l_r0
  : resource:Resource.Id.t
  -> x_um:float
  -> y_um:float
  -> ?halo_um:float (* default 2. *)
  -> unit
  -> Macro_intent.t

val Flow.librelane
  : ?overrides:Flow.Librelane.Override.t list
  -> ?macros:Macro_intent.t list
  -> Flow.Operation.t
  -> Flow.t
```

For example:

```ocaml
let program_intent =
  Macro_intent.tt_cmos5l_r0
    ~resource:(Resource.Id.of_string_exn "program")
    ~x_um:42. ~y_um:81. ~halo_um:2. ()

let flow =
  Flow.librelane ~macros:[ program_intent ] Flow.Operation.Synthesis
```

This constructor explicitly requests R0, `VDD!`/`VDDARRAY! -> VPWR`, and
`VSS! -> VGND`. These are **intent**, not proof of physical power access. No
probe-position-specific bridge geometry is emitted. Physical execution is gated
until a placement-aware strategy and checker policy are verified.

Intent is optional for synthesis. Duplicate or unknown IDs, references to flop
resources, nonfinite values, negative halos, out-of-bounds footprints and overlapping
declared halos fail. The nominal 236.8 by 118.78 um footprint is declarative stock
geometry; synthesis does not claim actual-LEF physical validation.

The existing `Project.render_bundle` / `emit_bundle` / store-publication APIs
require no additional arguments. Ordinary elaboration and rendering read no PDK
files and invoke no EDA tools. Source-inventory/Git reads remain at bundle rendering.

## Resolved and emitted contract

`Resolved_flow.t.macros` is a private checked list with resource ID, stock module,
actual legalized Verilog instance name, collateral and optional intent. Resolution
uses `Circuit.instantiations` and `Circuit.Name_for_rtl.instantiation_exn`; merely
predicting a name from `Resource.Id.rtl_instance_name` is insufficient. Unknown
implementations, missing/disconnected registered instances and unregistered stock
instances fail. The request must be the canonical exact 256x16 latency-one contract.

The bundle generates:

- `macros/RM_IHPSG13_1P_256x16_c2_bm_bist.blackbox.v`, an empty synthesis stub.
- `MACROS` with deduplicated LEF/GDS/CDL and exact Liberty bindings.
- `EXTRA_VERILOG_MODELS` pointing at the generated stub, using the current pinned
  LibreLane variable rather than its deprecated `VERILOG_FILES_BLACKBOX` alias.
- Explicit `STA_CORNERS` and `DEFAULT_CORNER`.
- `macro_contract` manifest data: logical IDs, actual names, complete typed
  collateral inventory, intent, synthesis-only execution, physical policy scope,
  and the fast-model temperature difference.

Corner keys are exact, with no wildcard fallbacks:

| Flow corner | Macro file suffix |
| --- | --- |
| `nom_fast_1p32V_m40C` | `fast_1p32V_m55C.lib` |
| `nom_slow_1p08V_125C` | `slow_1p08V_125C.lib` |
| `nom_typ_1p20V_25C` | `typ_1p20V_25C.lib` |

The fast standard-cell -40 C / macro -55 C difference is recorded, not resolved.
The adapter validates all 11 stock collateral entries, including both the macro
Verilog and shared behavioral core in each functional/timed source role.

`macro_contract.implementation_simulation.models` holds the two PDK-relative
functional-model references and `defines: ["FUNCTIONAL"]`. Compile these with the
implementation RTL, separately from generated behavioral simulation RTL and
separately from the synthesis stub. Timed-model references remain distinct in each
macro's collateral inventory; functional replay does not establish timing checks.

## Execution boundary

Preflight validates the raw macro/configuration contract, inspects and hashes
declared PDK files, checks the pinned PDK revision and file cleanliness, and records
macro references in its normal evidence. Shared SRAM symlinks may resolve across
technology directories **within the selected PDK checkout**, but not outside it.
Cleanliness checks include technology-exposure symlinks. After the tool returns,
the coarse route rechecks bundle bytes, recorded collateral hashes and macro alias
resolution; changing a Liberty or stub during execution fails the attempt.

The supported public route after installing/capturing these bytes is:

```sh
hardcaml-asic-flow preflight "$BUNDLE" \
  --toolchain /home/wayne/devel/jane/hardcaml_asic/.toolchain --json

hardcaml-asic-flow run "$BUNDLE" \
  --toolchain /home/wayne/devel/jane/hardcaml_asic/.toolchain \
  --stage synthesis --json
```

The fresh coarse SRAM launch automatically caps LibreLane jobs at 6, OpenROAD at 6,
STA corner parallelism at 1, KLayout DRC/XOR at 6, and OMP/default cores at 6.
Its recorded backend argv includes:

```text
-m librelane --pdk-root PDK_ROOT --pdk ihp-sg13cmos5l --manual-pdk
--run-tag asic --force-run-dir runs/asic --to Yosys.Synthesis
--jobs 6 -c OPENROAD_THREADS=6 -c STA_THREADS=1
-c KLAYOUT_DRC_THREADS=6 -c KLAYOUT_XOR_THREADS=6 src/config.json
```

The container's existing transport CPU ceiling is 20; effective tool concurrency
for this SRAM route is bounded by the explicit 6/1 settings. Jobs still require
coordinator allocation. `--native` may be added for a provisioned native synthesis
runtime; it does not provision tools.

**Unsupported operations fail explicitly:**

- Macro `Hardening` at public resolution.
- Coarse `--stage full`, before run allocation.
- Segmented `stages` / `run --endpoint`, including synthesis checkpoint publication.
  The existing checkpoint capability advertises physical restart targets; this slice
  does not mint that unsupported capability. Use fresh coarse synthesis.
- Macro physical postcheck/finalization.

The bridge's conservative closure validator admits only the public stock contract
and includes typed config paths, bundle inputs and the target PDK tree. Tests verify
Liberty/stub mutations alter it. Stage preparation and the bridge both reject macro
checkpoint execution; no closure check or compatibility comparison is bypassed.
The transported bridge digest is updated, so old segmented compatibility identities
cannot be reused as though bridge bytes were unchanged.

## Physical policy and remaining gate

The declared policy requires the pinned CMOS5L KLayout deck on final assembled
**real GDS**, backed by the organizer-linked [walkthrough](https://kdp1965.github.io/ihp-um-janestreet-prism/ihp_sram_macro.html).
That article uses a different macro/floorplan. Its blanket Magic/illegal-overlap
switches are not adopted. All raw extraction findings and Liberty electrical limits
remain material; no architectural registers, retiming or relaxed limits are added.

CDL is registered and preflight-verified, but **CDL consumption and extraction scope
are unverified**. This slice claims neither CDL-backed LVS execution nor transistor
LVS. Hardening remains gated on placement-aware Metal4 power access, actual LEF and
grid checks, real-GDS deck execution/reporting, and verified CDL consumption with
explicit abstract/device-level scope. Existing electrical and Magic/deck residuals
remain open.

## Checks

All ASIC Dune commands are serialized with A:

```sh
flock /tmp/opencode/asic-sram-build.lock opam exec --switch=5.2.0+ox -- \
  dune runtest -j6 test/sram_bundle
```

The PDK-free suite checks deterministic two-resource bundles, exact corners,
actual-name validation, placement failures, source separation, malformed contracts,
missing/modified synthetic collateral, shared-PDK symlink handling, coarse synthesis
launch and caps, physical rejection before run allocation, and closure mutation.
Synthetic successful tool exits with a mutated Liberty or staged stub are rejected.
Existing backend-protocol, preflight, coarse-run and postcheck fixture regressions
also pass. No physical EDA was run for assignment B.
