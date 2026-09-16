# hardcaml_asic Architecture Direction

## Tiny Tapeout First, Extensible Toward Commercial ASIC Flows

**Status:** Long-term direction aligned with the architecture plan, 2026-09-16.
The [accepted architecture and implementation plan](architecture.md) governs
current ownership, APIs to implement, and milestone order. The
[program-memory contract](program-memory-contract.md) governs the first resource.
The examples below follow those decisions; future API/module sketches remain
exploratory. Harness and technology are separate target axes, and the flow adapter
is selected independently. The first resource is 1RW `Single_port_ram` without
byte enables; the first project explicitly selects flop storage; macro support
requires a separate capability gate. Workbench is an optional external consumer
of project operations and build/run records. Commercial adapters remain deferred.
The companion PDF is a snapshot of the original direction note, not a maintained
contract.

**Primary implementation target:** Tiny Tapeout harness with IHP CMOS5L technology and the pinned LibreLane-based flow used by the reference application  
**Future direction:** Optional adapters for commercial EDA environments such as Cadence and Synopsys, without making those tools a requirement for the initial library

---

## 1. Purpose

`hardcaml_asic` should provide a common OCaml/Hardcaml-facing abstraction layer for ASIC-oriented design concerns that do not naturally belong in ordinary RTL construction.

The immediate motivation is practical: make Hardcaml designs easier to target at Tiny Tapeout and similar open ASIC flows. Examples include:

- instantiating SRAM and other technology-specific macros through a common interface;
- describing ASIC-specific implementation intent without scattering PDK-specific names and file paths throughout RTL;
- generating or coordinating the configuration required by Tiny Tapeout and LibreLane flows;
- exposing implementation results in a structured way that OCaml programs, CI systems, or a future RTL workbench can consume.

The library should be designed so that a later commercial-tooling layer is possible, but **commercial Cadence/Synopsys support is not an initial implementation requirement**.

The design objective is therefore:

> Build the right abstractions for Tiny Tapeout now, while avoiding assumptions that would make future industrial ASIC-flow adapters unnecessarily difficult.

---

## 2. Mental Model

A useful decomposition is:

```text
Hardcaml design
      |
      v
Logical ASIC abstractions
  - Single_port_ram initially; other resources later
  - clocks and constraints
  - implementation intent
      |
      v
Resolved target and resource implementations
  - harness: Tiny Tapeout initially
  - technology: IHP CMOS5L initially
  - PDK/library information
  - available macros
      |
      v
Flow adapter
  - LibreLane first
  - potentially other flows later
      |
      v
EDA tools
  - Yosys
  - OpenROAD
  - KLayout / verification tools
      |
      v
Artifacts / reports for the requested operation
  - netlists, or layout/GDS for physical implementation
```

The important architectural decision is that normal Hardcaml modules should describe **what hardware capability they need**, rather than hard-code the exact PDK cell or EDA command required to implement it.

---

## 3. PDK, Standard Cells, and Tooling Are Separate Concepts

`hardcaml_asic` should keep a clean conceptual distinction between the following layers.

### 3.1 PDK

The process design kit describes the fabrication technology. It contains information such as:

- process layers and routing stack;
- transistor and passive-device models;
- physical design rules;
- via definitions;
- parasitic models;
- DRC/LVS decks and associated technology data.

### 3.2 Standard-cell and macro libraries

Libraries built for the PDK provide reusable implementation blocks such as:

- inverters, NAND/NOR gates, AOI/OAI gates;
- flip-flops and latches;
- buffers and clock cells;
- SRAM or ROM macros;
- IO cells and other hard macros.

A cell may have multiple views of the same underlying object:

```text
                 NAND2_X1
                    |
      +-------------+-------------+
      |             |             |
      v             v             v
    Liberty        LEF           GDS
 timing/logic   abstract shape   physical layout
```

### 3.3 EDA flow

The EDA flow consumes RTL plus PDK/library information and produces the physical implementation.

For the open flow, a simplified picture is:

```text
RTL
 |
 v
Yosys
  synthesis and technology mapping
 |
 v
gate-level netlist
 |
 v
OpenROAD
  floorplan / placement / CTS / routing
 |
 v
layout + extracted implementation data
 |
 v
KLayout / physical verification stages
 |
 v
GDS
```

LibreLane coordinates these tools and the files passed between them.

---

## 4. LibreLane's Role

For architectural purposes, LibreLane can be treated as the **flow owner/orchestrator** for the current open ASIC target.

A useful FPGA analogy is:

```text
FPGA world                         Open ASIC world
-----------                        ----------------
Vivado synth                       Yosys
Vivado implementation              OpenROAD
Vivado overall flow ownership      LibreLane + underlying tools
```

The analogy is not exact: Vivado contains most of its own implementation engines, whereas LibreLane primarily coordinates independent tools.

`hardcaml_asic` therefore should not attempt to replace LibreLane. It should make it easier to **describe, configure, invoke, and consume** such flows from OCaml.

---

## 5. Initial Scope: Tiny Tapeout First

The first useful version of `hardcaml_asic` should focus on concrete needs encountered when targeting Tiny Tapeout.

The first milestone implements the path in the
[architecture plan](architecture.md#8-first-implementation-milestone):

1. **One portable design resource**
   - context-registered 1RW `Single_port_ram`;
   - behavioral model and explicitly selected synthesizable flop implementation;
   - a small internal resource/collateral description, without a broad public macro API.

2. **Separate harness and technology bindings**
   - resolve and validate the TT harness with the selected technology;
   - select exact resource implementations under explicit project policy;
   - reject unsupported configurations and record any explicitly permitted fallback;
   - investigate SRAM availability, behavior, collateral, and shuttle permission
     separately before implementing a physical macro backend.

3. **LibreLane/Tiny Tapeout flow integration**
   - generate required project/configuration files;
   - identify RTL sources and top-level modules;
   - pass clocks and other implementation constraints;
   - emit an immutable build bundle for existing scripts or an optional runner.

4. **Artifact and report handling**
   - locate generated netlists, DEF/GDS, timing reports, area reports, and logs;
   - provide a small typed result with units, stage/context, and raw report references;
   - distinguish unavailable metrics, execution completion, and physical checks.

5. **Simulation models**
   - provide the diagnostic behavioral model required by the memory contract;
   - permit Hardcaml simulations without requiring an ASIC flow to be installed.

ROM, additional memory shapes, clock/reset resources, and public custom-macro APIs
follow demonstrated needs. A behavioral simulation model is not an implicit
synthesis fallback. The goal is to prove the Tiny Tapeout path before broadening it.

---

## 6. SRAM as the Model Abstraction

SRAM is a good example of the abstraction style the library should encourage.

A design should ideally be able to request something conceptually like:

```ocaml
(* Planned context-taking API; only Config is implemented today. *)
let config =
  Single_port_ram.Config.create_exn ~depth:256 ~width:16 ~read_latency:1
in
Single_port_ram.create context config
  ~clock ~enable ~write_enable ~address ~write_data
```

rather than directly instantiate a name such as:

```text
some_pdk_specific_sram_256x16_1rw
```

The request describes logical requirements:

```text
256 words (an example, not a required macro shape)
16 bits per word
one read/write port
whole-word writes, no byte enables
read latency 1; hold on disable; unspecified output after a write
```

The elaboration context selects an implementation under project policy and
registers the instance and collateral. Behavioral simulation and implementation
elaborations use the same design constructor:

```text
                       logical memory request
                                |
                  +-------------+-------------+
                  |                           |
                  v                           v
          implementation mode          behavioral simulation
                  |                           |
          explicitly selected flops     diagnostic behavioral model
          or verified exact macro       (separate source set)
```

In a future proprietary process, the same request might map to a foundry or
memory-compiler-generated macro that satisfies the contract. Technology capability
alone does not authorize a choice: missing exact mappings fail unless project
policy explicitly permits a fallback. No implicit resizing, composition, latency
changes, initialization guarantees, or byte enables are introduced.

This separation is valuable even if commercial flows are never implemented: it makes the Tiny Tapeout code cleaner and isolates technology-specific details.

---

## 7. Proposed Layering

A reasonable long-term module structure is:

```text
hardcaml_asic
|
+-- Single_port_ram         [first resource]
+-- Macro                   [internal description first; public API later]
|   +-- Rom                 [future]
|   `-- Custom_macro        [future]
|
+-- Project / Elaboration_context / Build
|
+-- Harness
|   `-- Tiny_tapeout
+-- Target                  [resolves harness + technology]
|
+-- Technology
|   +-- macro capabilities
|   +-- standard-cell / library metadata
|   +-- process corners
|   +-- physical views
|   `-- process/library-specific bindings
|
+-- Constraint
|   +-- clocks
|   +-- IO delays
|   +-- false paths
|   +-- multicycle paths
|   `-- clock uncertainty
|
+-- Flow
|   +-- adapter capabilities and input rendering
|   +-- synthesis intent
|   +-- implementation intent
|   `-- result collection
|
+-- Runner                  [optional execution of emitted inputs]
|
+-- Tool
|   +-- LibreLane
|   +-- Yosys             [possibly internal/detail-level]
|   +-- OpenROAD          [possibly internal/detail-level]
|   `-- future adapters
|
`-- Report
    +-- Timing
    +-- Area
    +-- Power
    +-- Utilization
    `-- Diagnostics
```

This does **not** mean every module needs to exist in version 1. It is a direction for keeping boundaries clear as the project grows.

---

## 8. Constraints as Typed Intent

Another useful abstraction is timing/implementation constraints.

Instead of forcing design code to emit raw SDC everywhere, `hardcaml_asic` could eventually expose typed OCaml constructs such as:

```ocaml
Constraint.Clock.create
  ~name:"core_clk"
  ~period:(Time.ns 1.0)
  clk
```

A backend can then serialize this into the representation expected by the active flow, typically SDC or Tcl.

The advantage is not merely syntax. Typed constraints can:

- validate units;
- associate constraints with Hardcaml ports/signals;
- make flow generation reproducible;
- permit future backend changes without rewriting design intent;
- provide structured information to visualization or analysis tools.

The initial constraint subset follows the first project's needs; this sketch does
not commit the first milestone to every constraint listed above. Constraints need
stable endpoint identity and validation against the elaborated design. The active
adapter must reject unsupported intent rather than silently omit it.

Raw SDC can be added as an adapter-specific escape hatch with a defined insertion
stage, reason, provenance, and documented validation limits. It must respect the
[configuration ownership rules](architecture.md#6-configuration-ownership-and-escape-hatches),
including the authoritative typed clock declaration.

---

## 9. Tool Adapters Should Be Process-Oriented, Not FFI-Oriented

A future commercial-tool integration should probably **not** begin as C bindings into Cadence or Synopsys internals.

Most industrial EDA tools are naturally driven through batch commands and Tcl scripts. A practical adapter architecture is therefore:

```text
OCaml
  |
  +-- generate Tcl / SDC / manifests / config
  |
  +-- launch external EDA executable
  |
  +-- monitor process and collect logs
  |
  +-- collect output artifacts
  |
  `-- parse reports into typed OCaml values
```

These are separate operations, not one mandatory launch path. For example, a
future synthesis adapter could have a conceptual interface resembling:

```ocaml
module type Synthesis_tool = sig
  type config

  val validate : config -> Build.t -> Diagnostic.t list
  val emit : config -> Build.t -> Emitted_bundle.t
  val collect : Emitted_bundle.t -> Execution_record.t -> Flow_result.t
end
```

Possible implementations could be:

```ocaml
module Yosys : Synthesis_tool

(* Future, optional adapters *)
module Genus : Synthesis_tool
module Design_compiler : Synthesis_tool
```

All types here are sketches. A runner or external launcher executes the emitted
bundle separately; the adapter supplies tool-specific invocation requirements.
The build includes resolved libraries, resources, and source roles as well as RTL
and constraints. Neither emission nor collection should require a live licensed
tool session. The first adapter wraps LibreLane; a standalone Yosys adapter is
not a prerequisite.

---

## 10. Future Commercial EDA Support

Commercial support should be treated as an **additional layer down the road**, not as a requirement for the Tiny Tapeout implementation.

The architecture can nonetheless avoid choices that would make this future direction impossible.

Potential future adapters include:

```text
Cadence
  Genus       - synthesis
  Innovus     - physical implementation
  Tempus      - timing signoff
  Quantus     - extraction
  Voltus      - power / IR analysis

Synopsys
  Design Compiler / Fusion Compiler - synthesis / implementation
  IC Compiler II                    - physical implementation
  PrimeTime                         - timing signoff
  StarRC                            - extraction
```

The important point is that supporting these tools is not just a matter of changing an executable path. Tool invocation itself is easy; representing the surrounding ASIC environment is harder.

---

## 11. Why `install_location` Alone Is Not Enough

A simplistic adapter might look like:

```ocaml
type tool =
  { install_directory : string }
```

That is unlikely to be sufficient in a real industrial environment.

A tool may depend on:

- a particular executable version;
- license-server configuration;
- environment variables;
- shell/module setup;
- site-specific initialization Tcl;
- PDK/library locations;
- compute-farm or scheduler wrappers;
- company-owned launch scripts.

A more flexible process layer might eventually support concepts such as:

```ocaml
type executable =
  | Path of string
  | Command of string

type launcher =
  | Direct
  | Shell_wrapper of string
  | Environment_module of string
  | Slurm of ...
  | Lsf of ...
```

This need not be implemented now. The important architectural lesson is simply:

> Do not bake the assumption that every EDA tool is a binary at a fixed absolute path directly into higher-level flow APIs.

For the current Tiny Tapeout implementation, a much smaller execution model is sufficient.

---

## 12. The Hard Part of Commercial Support Is Flow Semantics

Launching `genus`, `innovus`, or `dc_shell` is relatively straightforward. The difficult problem is expressing the design environment they consume.

A serious commercial flow can involve:

```text
RTL
|
+-- SDC timing constraints
+-- standard-cell libraries
|   +-- multiple voltage / temperature / process corners
|
+-- physical libraries
|   +-- LEF
|   +-- GDS / vendor database formats
|
+-- RC technology files
+-- SRAM / PLL / IO macro libraries
+-- power intent such as UPF
+-- multiple modes and multiple corners
+-- floorplan constraints
+-- pin constraints
+-- power-grid strategy
+-- CTS strategy
+-- routing constraints
`-- tool-specific optimization settings
```

A future `hardcaml_asic` commercial layer therefore becomes interesting not because it can run an executable, but because it can provide a coherent, typed model of this implementation intent.

This is also why the initial Tiny Tapeout implementation should remain modest: attempting to fully model industrial MMMC, power intent, signoff, DFT, and proprietary databases before the open-flow API is proven would likely overcomplicate the project.

---

## 13. Avoid the Lowest-Common-Denominator Trap

A future multi-tool API should not pretend that OpenROAD, Innovus, ICC2, and Fusion Compiler all have exactly the same capabilities.

The desirable structure is:

```text
portable high-level API
        +
backend-specific extensions / escape hatches
```

For example, a common flow could expose portable concepts such as:

- target utilization;
- clock definitions;
- die/core areas;
- macro placement constraints;
- timing goals.

A future Cadence backend should still permit raw or structured Cadence-specific extensions when an advanced Innovus feature is needed.

Conceptually:

```ocaml
Flow.vendor_extension
  (Innovus (...))
```

or, at the lowest level:

```ocaml
Innovus.raw_tcl "set_db ..."
```

The abstraction should simplify common work, not make advanced work impossible.

Extensions belong to a named adapter, carry a reason and application stage, and
are recorded in build provenance. Reject unsupported adapter/target/operation
combinations and extensions for the wrong backend. LibreLane's JSON overrides
are its own representation; they must not become a universal vendor API. Raw Tcl
has validation limits and cannot be treated as automatically preserving all typed
intent; insertion points and protected-value rules must be explicit.

---

## 14. Normalized Reports May Be One of the Most Valuable Features

A particularly useful cross-flow abstraction is a normalized result/report API.

Different tools emit timing, area, power, and utilization information in different formats. A typed OCaml representation could allow users to write:

```ocaml
let%bind result = Flow.run flow in

printf "WNS: %s\n"
  (Time.to_string result.timing.wns);

printf "Area: %s\n"
  (Area.to_string result.area)
```

without caring whether the underlying data came from OpenROAD today or a commercial signoff tool in the future.

This is illustrative result consumption, not a guaranteed flat record or evidence
that the analyses are interchangeable. The caller must handle unavailable values.
Each metric retains its units, definition, producing tool/version, flow stage,
applicable mode/corner, and original report reference. Distinguish setup from hold
timing, cell area from core area, and differing power assumptions. Missing or
unparseable data is unavailable with a reason, never zero or a passing check.

Potential normalized fields include:

- WNS and TNS;
- critical paths;
- cell count;
- combinational/sequential area;
- total core area;
- utilization;
- macro inventory;
- clock information;
- power, when available;
- DRC/error counts;
- congestion metrics;
- generated artifact paths.

This would also make `hardcaml_asic` a natural backend for CI dashboards or a future Hardcaml RTL workbench.

---

## 15. Relationship to a Future RTL Workbench

A flow/result API could eventually support a higher-level interface such as:

```text
+--------------------------------------------------+
| Hardcaml ASIC Run                               |
|                                                  |
| Target:      Tiny Tapeout / SG13...              |
| Backend:     LibreLane                           |
|                                                  |
| WNS:         ...                                 |
| Area:        ...                                 |
| Utilization: ...                                 |
| Cells:       ...                                 |
|                                                  |
| [Timing] [Floorplan] [Logs] [Artifacts]          |
+--------------------------------------------------+
```

Later, a commercial backend could populate the same high-level UI while preserving access to tool-specific details.

This possibility is another reason to return structured results rather than only shell exit codes and text logs.

The [Workbench integration boundary](architecture.md#reference-application-and-workbench-ownership)
keeps configuration in the opened project's ASIC declaration and build. Workbench
owns job supervision and presentation; adapters own flow semantics and result
interpretation. Its jobs link to the immutable build and separate execution record.
Neither the UI nor a commercial adapter is required for the initial ASIC path.

---

## 16. Recommended Development Phases

These are long-term stages. The library's [implementation phase plan](phase_plan.md)
subdivides the initial Tiny Tapeout workflow into actionable P0–P5 tasks, with
intermediate milestones and a separate SRAM capability investigation. Its phase
numbers are local to that plan, not the four stages below.

### Phase 1 - Tiny Tapeout fundamentals

Focus exclusively on making the current target pleasant and reliable.

- establish core package/module structure;
- implement context-registered `Single_port_ram` with behavioral and explicitly
  selected flop implementations against the memory contract;
- establish harness/technology separation and independent flow selection;
- integrate with the chosen Tiny Tapeout/LibreLane flow;
- generate deterministic project/configuration artifacts;
- collect useful output artifacts and errors with build/run identity;
- keep physical SRAM support behind its separate capability gate.

### Phase 2 - Stabilize the technology and flow abstractions

After real projects have exercised Phase 1:

- refine the existing separation of resource requirements, harness, technology,
  flow adapter, and execution;
- extend typed clocks/constraints where this proves useful;
- stabilize the target/technology interfaces exercised in Phase 1;
- broaden normalized timing/area/utilization reports;
- improve flow graph/artifact tracking.

### Phase 3 - Additional open processes/flows

Use another open target to verify that abstractions are actually portable rather than merely renamed Tiny Tapeout assumptions.

This is a useful portability test. The order of additional integrations is
need-driven; it does not add a gate to the first milestone.

### Phase 4 - Optional commercial tooling adapters

After real use has exercised the common boundaries:

- add environment/executable discovery abstractions;
- prototype one narrow commercial integration, such as synthesis-only Genus or Design Compiler support;
- generate Tcl from common constraints/flow intent;
- parse reports into the existing result representation;
- retain backend-specific escape hatches.

Commercial EDA support should remain optional and should not force proprietary software, files, or licenses on users of the open-source Tiny Tapeout path.

---

## 17. Suggested Repository Direction

One possible future organization is:

```text
hardcaml_asic/
|
+-- lib/
|   +-- single_port_ram.ml
|   +-- project.ml
|   +-- elaboration_context.ml
|   +-- build.ml
|   +-- target.ml
|   +-- harness/
|   |   `-- tiny_tapeout.ml
|   |
|   +-- macro/
|   |   +-- rom.ml
|   |   `-- black_box.ml
|   |
|   +-- technology/
|   |   +-- technology.ml
|   |   `-- ihp_cmos5l.ml
|   |
|   +-- constraint/
|   |   +-- clock.ml
|   |   `-- constraint.ml
|   |
|   +-- flow/
|   |   +-- flow.ml
|   |   +-- artifact.ml
|   |   `-- result.ml
|   |
|   +-- tool/
|   |   `-- librelane.ml
|   |
|   `-- report/
|       +-- timing.ml
|       `-- area.ml
|
+-- examples/
|   `-- tiny_tapeout/
|
`-- test/
```

This is a future module sketch, not a required directory or package split. Start
with the existing `lib/` and one package; split packages only when dependencies or
distribution justify it. The exact hierarchy should follow real implementation
needs; empty architectural layers should not be created merely for symmetry.

---

## 18. Design Principles

The project should favor the following principles.

### Tiny Tapeout is the product target now

Do not delay a useful TT implementation in order to design a hypothetical universal interface for tools that are not currently available or required.

### Extensibility should shape boundaries, not inflate scope

It is worth separating concepts such as logical SRAM requests, technology bindings, and flow execution now because those boundaries improve the current design as well as future portability.

It is not worth implementing industrial MMMC, DFT, UPF, or signoff abstractions merely because a commercial flow may need them someday.

### Keep technology names out of design logic where practical

Hardcaml modules should describe hardware behavior and capability requirements. PDK-specific macro names and physical files belong in target-specific bindings.

### Treat external EDA tools as processes

Generate their scripts and inputs, invoke them, collect their outputs, and parse their reports. Avoid unnecessary dependencies on private APIs.

### Prefer typed intent, but preserve escape hatches

Typed OCaml representations are valuable for validation, refactoring, and tooling. Raw Tcl/SDC/configuration hooks remain necessary for unusual or backend-specific requirements.

### Normalize outputs before trying to normalize every input

A stable `Result.t` for timing, area, artifacts, and diagnostics can provide immediate value and is often easier to make portable than a universal representation of every possible implementation knob.

### Let the abstractions emerge from real designs

The Tiny Tapeout implementation should be the proving ground. Generalize only after concrete examples reveal which concepts are truly common.

---

## 19. Summary

The near-term vision for `hardcaml_asic` is not to reproduce an industrial ASIC CAD stack in OCaml. It is to provide the missing layer between Hardcaml designs and practical Tiny Tapeout ASIC implementation:

```text
Hardcaml
   |
   v
hardcaml_asic
   |
   +-- portable resources, initially Single_port_ram
   +-- Tiny Tapeout harness + separate technology bindings
   +-- constraints / implementation intent where useful
   +-- LibreLane flow integration
   `-- structured artifacts and reports
   |
   v
Tiny Tapeout / LibreLane
   |
   v
Yosys + OpenROAD + physical verification
   |
   v
GDS
```

The architecture should, however, leave a credible path toward:

```text
hardcaml_asic
   |
   +-- open-flow adapters
   |
   `-- optional future commercial adapters
          +-- Cadence
          `-- Synopsys
```

Commercial EDA support is therefore best viewed as a **future layer enabled by good boundaries today**, rather than a current feature requirement.

The most important architectural bets are:

1. represent logical macro requirements separately from PDK-specific implementations;
2. keep flow/tool invocation behind explicit adapters;
3. avoid assuming tools live at fixed paths or have identical capabilities;
4. return structured reports and artifacts to OCaml;
5. preserve backend-specific escape hatches;
6. allow the Tiny Tapeout implementation to drive and validate the abstractions before expanding outward.

That gives `hardcaml_asic` a focused immediate mission while leaving room to grow into a broader Hardcaml-oriented ASIC implementation interface if real use cases justify it.
