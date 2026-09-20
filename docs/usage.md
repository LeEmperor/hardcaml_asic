# Initial user workflow

This is the primary path from a Hardcaml design to preserved evidence for the
implemented ASIC flow. The supported physical path is deliberately narrow:
Tiny Tapeout `6x4`, IHP `ihp-sg13cmos5l`, and LibreLane. Registered memory is
available as a behavioral simulation model or explicit synthesizable flops;
there is no implemented SRAM macro backend.

The lifecycle has three separate layers:

1. Install the `hardcaml_asic` OCaml library to declare, elaborate, simulate,
   and emit a bundle.
2. Obtain flow scripts from a checkout of the same exact revision and explicitly
   provision the external PDK and toolchain. The package does not install a CLI
   or those scripts.
3. Run the immutable bundle, collect results, and preserve both the complete
   bundle and the selected run evidence.

## 1. Install an exact revision

Pin a full commit rather than a moving branch:

```sh
ASIC_REV=<full-hardcaml_asic-commit-hash>
opam pin add --no-action hardcaml_asic \
  "git+https://github.com/LeEmperor/hardcaml_asic.git#$ASIC_REV"
opam install hardcaml_asic
```

A consumer Dune stanza uses the installed wrapped library directly:

```lisp
(executable
 (name asic_bundle)
 (libraries core hardcaml hardcaml_asic))
```

This does not require a sibling directory named `../hardcaml_asic`. A local,
isolated-prefix installation is also supported and exercised by
[`test/package_consumer_smoke.sh`](../test/package_consumer_smoke.sh). See
[consumer installation](consumer-installation.md) for both installation routes
and exact collateral resolution.

## 2. Declare the project

A design implements `Project.Design`: Hardcaml input/output interfaces, a top
module name, and `create context inputs`. Resource constructors receive that
context. The following is a declaration excerpt, not a complete executable;
[`examples/tt_bundle_example.ml`](../examples/tt_bundle_example.ml) is the
maintained runnable example with the complete `Design` modules, all 24 pin
descriptions, bundle source enumeration, and error handling.

```ocaml
open Core
open Hardcaml
open Hardcaml_asic

let project (design : (module Project.Design)) pinout =
  Project.create
    ~name:"my_asic"
    ~metadata:
      { title = "My ASIC"
      ; author = "Example author"
      ; description = "Registered input and memory experiment"
      }
    ~design
    ~target:
      { harness = Tiny_tapeout { tiles = T6x4 }
      ; technology = Technology.ihp_sg13cmos5l
      }
    ~flow:(Flow.librelane ~overrides:(Tt_cmos5l.overrides ()) Hardening)
    ~clocks:[ { Clock.port = "clk"; period = Time_float.Span.of_sec (1. /. 48e6) } ]
    ~timing:Timing.empty
    ~pinout
    ~policy:(Resource_policy.create ~default:Flops [] |> Or_error.ok_exn)
    ()
  |> Or_error.ok_exn
```

`Tt_cmos5l.I` and `Tt_cmos5l.O` are optional conveniences for the required TT
boundary. `Tt_cmos5l.overrides ()` supplies the pinned template defaults, and
`Tt_cmos5l.synchronised_reset` and `Tt_cmos5l.gate` are opt-in helpers. The
consumer still owns reset semantics, behavior while `ena` is low, and arbitration
of `uio_out`/`uio_oe`; the harness only supplies the pins. Every `ui`, `uo`, and
`uio` bit needs a meaningful `Pinout.t` description. Declare the primary clock
and any real min/max I/O timing assumptions; do not fabricate board timing.
The [target reference](target-reference.md) defines the accepted boundary,
timing subset, protected settings, and optional helper behavior.

Resource policy is mandatory. Prefer explicit `Flops` for the currently
supported memory path. `Exact` rejects a shape without an exact technology
mapping. `Exact_or_flop_fallback` permits flops only as a recorded fallback;
it is not an implicit or silent choice.

## 3. Simulate and elaborate resources

`Project.elaborate project ~mode:Simulation` builds diagnostic behavioral
resources for Hardcaml simulation. `~mode:Implementation` selects and builds
synthesizable implementations. `Project.elaborate_for_flow project` performs
implementation elaboration plus target, interface, timing, and adapter
validation before emission. None invokes an EDA tool or reads a PDK.

Run the maintained PDK-free memory path:

```sh
dune exec examples/memory_example.exe
dune exec examples/memory_example.exe -- --rtl /tmp/memory_example.v
```

`Single_port_ram` is a whole-word 1RW memory with one-cycle registered reads.
When disabled, its output holds. Output after a write, reading an unwritten word,
and an out-of-range address are unspecified. The behavioral model uses poison to
make misuse visible; implementation flops have no reset or initialization.
The consumer must own validity, bounds checks, accepted-access gating, and
response validity. Reset consumer metadata rather than assuming reset clears
hardware storage. The [memory example](memory-example.md) and normative
[memory contract](program-memory-contract.md) give the complete behavior.

## 4. Emit and inspect an immutable bundle

From this repository, this maintained command needs no PDK and writes only to a
new or empty directory:

```sh
BUNDLE=$(mktemp -d)/bundle
dune exec examples/tt_bundle_example.exe -- memory "$BUNDLE"
```

A consumer provides an equivalent executable in its own project. It passes the
consumer repository as `Bundle.render ~source_root` and enumerates every source
input needed to reproduce generation. Do not use the library checkout as the
consumer source root.

Inspect `manifest.json` before execution. The bundle contains synthesis RTL in
`src/`, independently elaborated behavioral RTL in `simulation/`, generated SDC
and LibreLane configuration, TT metadata, and exact copies of declared generator
inputs under `inputs/`. Never compile the two RTL source sets together.

The manifest identity is the build identity. It covers emitted bytes, source
input bytes and Git status, and source revision. A formatting-only source change
or a new commit can therefore change the identity while generated RTL/config/SDC
remain byte-identical. A later flow attempt receives a separate random run ID in
`run.json`; do not use that execution identity as the build identity. The
[bundle guide](bundle-emission.md) is authoritative for layout and provenance.

Treat the emitted directory as immutable. If configuration or constraints are
wrong, fix the declaration and emit a fresh bundle; never patch `config.json`,
SDC, RTL, metadata, or the manifest before a run.

## 5. Prepare the external environment

Keep a checkout at the same `ASIC_REV` to obtain the current checkout-distributed
scripts and lockfile. This is separate from the installed OCaml package:

```sh
ASIC_SOURCE=/absolute/path/to/hardcaml_asic-source
git clone https://github.com/LeEmperor/hardcaml_asic.git "$ASIC_SOURCE"
git -C "$ASIC_SOURCE" checkout --detach "$ASIC_REV"
TOOLCHAIN=/absolute/path/to/asic-toolchain
TOOLCHAIN="$TOOLCHAIN" "$ASIC_SOURCE/bootstrap.sh"
source "$TOOLCHAIN/toolchain-env.sh"
```

Provisioning fetches substantial external collateral and the LibreLane image;
it is never part of elaboration or emission. `bootstrap.sh --check` is read-only.
See [bootstrapping](bootstrap.md) for prerequisites, disk use, pins, offline and
native options. There is currently no separately installed/versioned flow CLI;
shared-tool distribution remains future work.

## 6. Preflight, execute, and collect

Use the scripts from `$ASIC_SOURCE`. These are the supported entry points and
flags for an arbitrary emitted bundle:

```sh
RUNS=/absolute/path/to/run-storage

python3 "$ASIC_SOURCE/scripts/phase4.py" preflight "$BUNDLE" \
  --support-tools "$TT" --pdk-root "$PDK_ROOT" --python "$FLOW_PY" \
  --output "$RUNS/preflight.json"

# Expensive: mapped synthesis.
python3 "$ASIC_SOURCE/scripts/phase4.py" run "$BUNDLE" \
  --support-tools "$TT" --pdk-root "$PDK_ROOT" --python "$FLOW_PY" \
  --runs "$RUNS" --stage synthesis

# More expensive: replace synthesis with full for place, route, and signoff.
```

The run command prints the new `run.json` path even on failure. Set `RUN` to its
parent, then collect any completed or partial attempt:

```sh
RUN=/absolute/path/printed-run-directory
python3 "$ASIC_SOURCE/scripts/phase4.py" collect "$RUN" \
  --output "$RUN/results.json"
python3 "$ASIC_SOURCE/scripts/report.py" "$RUN"
```

For a completed full run, the required postchecks are also expensive:

```sh
python3 "$ASIC_SOURCE/scripts/phase4.py" postcheck "$RUN" \
  --support-tools "$TT" --pdk-root "$PDK_ROOT" \
  --precheck-python "$PRECHECK_PY" --testbench /absolute/path/to/testbench.v
python3 "$ASIC_SOURCE/scripts/phase4.py" collect "$RUN" \
  --output "$RUN/results.json"
python3 "$ASIC_SOURCE/scripts/report.py" "$RUN"
```

`scripts/flow.sh` is the convenience driver for this repository's maintained
examples. With no arguments it builds, emits, preflights, performs a **full
expensive run**, postchecks, collects, and reports. Select steps explicitly when
resuming. A post-run step uses the run made in that invocation, then `$RUN`, then
the newest run under `$RUNS` by modification time. `report.py --runs "$RUNS"`
uses the same newest-by-modification-time policy. Prefer an explicit `RUN` for
evidence. The [flow guide](flow.md) owns full command details, version waivers,
native execution, failure records, and the wrapper's environment variables.

## 7. Interpret and preserve results

Keep these claims distinct:

- `process_status: completed` means the requested flow stage completed.
- Mapped synthesis additionally needs mapped cells/area and zero synthesis
  errors, inferred latches, and unmapped instances.
- Physical timing needs a full run with setup and hold results at the reported
  corners and no unconstrained modes.
- Physical acceptance also needs antenna/DRC/LVS plus TT precheck and the
  design-specific final-netlist verification.

Missing metrics remain `null`/`unknown` with an unavailable reason; they are not
passes or zeroes. The reporter checks the requested stage against both the run
record and collected result. A completed synthesis-only run exits zero only with
valid mapped cell/area evidence, no collection errors, and explicit zero values
for all three synthesis checks; it labels physical timing, signoff, and
postchecks as not evaluated. A full request never falls back to that policy: it
must complete the full stage and additionally provide constrained setup/hold
timing, passing DRC/LVS/antenna, and passing TT precheck and final-netlist
verification. Unknown or contradictory stages and absent or malformed required
evidence exit nonzero.

Archive one explicit run. The standard archiver retains both selected run
evidence and the complete immutable input bundle:

```sh
EVIDENCE=/absolute/path/to/evidence-directory
python3 "$ASIC_SOURCE/scripts/archive.py" "$RUN" --list
python3 "$ASIC_SOURCE/scripts/archive.py" "$RUN" --output "$EVIDENCE"
```

The result contains `reports.tar.gz`, `input-bundle.tar.gz`,
`input-bundle.sha256`, the plain JSON records, and `archive.json`. The input
tarball contains the original manifest bytes and exactly its declared files,
including copied source inputs and both RTL source sets. The archiver verifies
manifest/run identity, every declared hash, and source-copy metadata. It prefers
the original `run.json.bundle`; if that path has disappeared, the staged
`RUN/project` is used only when it is an exact complete copy. Undeclared run,
tool, PDK, and support files are excluded.

Restore and verify without the original checkout, bundle, run directory, PDK, or
opam switch:

```sh
RESTORE=$(mktemp -d)
(cd "$EVIDENCE" && sha256sum --check input-bundle.sha256)
tar -xzf "$EVIDENCE/input-bundle.tar.gz" -C "$RESTORE"
python3 - "$RESTORE/bundle" "$EVIDENCE/run.json" <<'PY'
import hashlib, json, pathlib, sys
bundle, run_path = map(pathlib.Path, sys.argv[1:])
manifest_bytes = (bundle / "manifest.json").read_bytes()
manifest = json.loads(manifest_bytes)
run = json.loads(run_path.read_text())
assert hashlib.sha256(manifest_bytes).hexdigest() == run["manifest_sha256"]
assert manifest["identity"] == run["build_identity"]
for entry in manifest["files"]:
    assert hashlib.sha256((bundle / entry["path"]).read_bytes()).hexdigest() == entry["sha256"], entry["path"]
print("verified", len(manifest["files"]), "bundle files for", run["run_id"])
PY
```

Running preflight or executing the restored bundle still needs the exact
separately recorded toolchain and external collateral. Archives produced before
this capability may lack `input-bundle.tar.gz`; reports alone cannot reconstruct
the omitted generated RTL or source copies. The consumer's
[clean-staging P5.4 record](../../scaf/tinytapeout/reports/2026-09-20-p0.5c-clean-staging-physical.md)
documents the earlier manual procedure and remains historical evidence.

## Diagnostics and limits

- Unsupported target or shape: only TT `6x4` with IHP CMOS5L resolves for flow;
  unsupported combinations fail before emission.
- Missing/conflicting policy: every resource needs one applicable policy;
  duplicate selectors, unused rules, unsupported `Exact`, and unavailable exact
  mappings are errors rather than implicit fallback.
- Override conflicts: clock, generated source list, die/floorplan/PDK values,
  target constraints, and `MACROS` are protected. Change their typed owner, not
  a raw LibreLane override.
- Bundle input errors: `input_paths` must be nonempty, relative, present files
  inside a committed Git source root. Output must be new or empty.
- Environment errors: preflight reports missing/mismatched tools, revisions,
  hashes, PDK views, support tools, Python, and container image without installing
  or silently substituting them.
- Memory: no SRAM macro backend is implemented. Explicit flop synthesis evidence
  does not prove memory placement/routing feasibility, and the successful
  observable physical run does not prove memory physical feasibility.
- The pinned LibreLane ABC renderer passes a `cell/pin` token where ABC expects a
  cell name. This invalidates ABC's printed delay estimate, not the recorded
  mapped cells/area or the separate post-route OpenSTA result; see the consumer's
  [P5.3 analysis](../../scaf/tinytapeout/reports/2026-09-20-p0.7-memory-synthesis.md#abc-diagnostics).
- Commercial adapters, additional targets/flows, a packaged shared-tool CLI,
  and broader memory/resource support remain future work.

The phase-by-phase records remain in the [implementation plan](phase_plan.md),
but they are evidence and history rather than the onboarding route.
