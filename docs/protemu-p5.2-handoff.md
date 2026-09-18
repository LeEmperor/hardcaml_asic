# Protemu handoff: adopt `hardcaml_asic` (ASIC P5.2 / protemu P0.6)

## What is available now

`hardcaml_asic` is an installable OCaml/Dune package (`0.1.0`, library name
`hardcaml_asic`). An independent project can pin a library commit and use
`(libraries hardcaml_asic)` without a sibling checkout. See the
[consumer installation guide](consumer-installation.md) for the pin and the
matching external toolchain revision.

- `Project.create` declares a design, metadata, TT pin meanings, a primary
  clock, optional I/O delays, resource policy, and LibreLane flow settings.
  `Project.elaborate ~mode:Simulation` builds behavioral RTL;
  `Project.elaborate_for_flow` validates an implementation build for the
  supported Tiny Tapeout `6x4` / IHP CMOS5L target. Each elaboration has a
  fresh `Elaboration_context` and produces an immutable build.
- `Bundle.render` and `Bundle.write` emit generated synthesis RTL, optional
  separate simulation RTL, `info.yaml`, `src/config.json`, `constraints/top.sdc`,
  copied source inputs, and a content-hashed `manifest.json`. The bundle does
  not run EDA tools. Target, clock, source list, and protected LibreLane settings
  are validated as one configuration; other overrides require a reason.
- `Single_port_ram` provides registered 1RW, whole-word memory with a
  diagnostic simulation model and explicitly selected synthesizable flops.
  There is no CMOS5L SRAM macro backend yet. External preflight, LibreLane
  execution, result collection, and postchecks can consume an emitted bundle.

The working [TT bundle example](../examples/tt_bundle_example.ml) shows the
declaration and emission calls. The [bundle guide](bundle-emission.md) describes
the files; the [target reference](target-reference.md) lists the validated TT
interface and configuration ownership.

## The first consumer test

Adopt the library in protemu's **current observable top and protemu-owned TT
wrapper** (protemu P0.6), keeping the hardware modules ordinary Hardcaml.
Use a `Project.Design` at the top, declare the TT `6x4` / CMOS5L target, real
clock and pin meanings, metadata, a resource policy, and only reasoned
LibreLane overrides. Pin the package and matching collateral revisions in
protemu's own dependency record. Have protemu emit the bundle from its own
repository and enumerate its own source inputs; the old `tinytapeout/`
configuration should cease to be a second authority for this path.

**What we want to learn:** can a separate, real design use `hardcaml_asic` as
the source of truth for ASIC build inputs and still pass its existing wrapper
behavior? The acceptance evidence is:

1. A clean independent build and repeatable emission of the same bundle and
   manifest identity from the same protemu inputs.
2. A validated TT top interface, generated metadata/SDC/LibreLane config,
   separate simulation and synthesis source sets, and a manifest that records
   the actual protemu inputs and dependency revisions.
3. The existing protemu wrapper regression rerun against emitted RTL, plus
   checks that conflicting clock, source-list, or target-owned overrides fail
   with useful diagnostics.

This is the library's ASIC P5.2 evidence and protemu's P0.6 evidence. The
library's own observable physical run proves the flow path, but it does not
substitute for this independent consumer test. After P0.6, protemu P0.7 /
ASIC P5.3 exercises `Single_port_ram` with an explicitly selected flop store,
consumer validity and access gating, read latency/hold checks, and mapped
synthesis. A later adopted-bundle physical run closes ASIC P5.4.
