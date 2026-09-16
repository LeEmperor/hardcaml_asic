# Architecture and implementation plan

Status: accepted high-level decisions, 2026-09-16. API sketches and artifact
names describe the intended design; they are not implemented interfaces.

This document develops the [original concept note](hardcaml_asic_concept_note.md)
into the current plan and takes precedence for architecture and sequencing.
The [program-memory contract](program-memory-contract.md) is authoritative for
`Single_port_ram` behavior. The
[architecture direction note](hardcaml_asic_architecture_direction.md) describes
long-term open/commercial-flow extensibility. The boundaries below incorporate
that direction; its broader sketches do not expand the first milestone.

## 1. Product direction

`hardcaml_asic` should be the foundation a new or existing Hardcaml project adopts
when targeting ASIC implementation and eventual tapeout. The primary experience
is declaring an ASIC project and carrying its design intent through elaboration,
implementation selection, generated flow inputs, and implementation results.

Existing FPGA-oriented projects may need substantial restructuring to integrate.
Their current APIs do not dictate this library's architecture. The protocol
emulator is the first reference application; broader use in projects such as
`hardcaml_networking` is a future consumer, not an initial compatibility layer.

The defining promise is that intended behavior and implementation requirements
stay together. The library wraps established tools; it does not replace synthesis
or physical design, and emitting a build does not establish tapeout readiness.

## 2. Three parts

| Part | Responsibilities |
| --- | --- |
| Design resources | Behavioral contracts and Hardcaml constructors; initially `Single_port_ram`, with additional resources driven by real designs |
| Technology implementations | Supported configurations, implementation selection, port mappings, cells, and simulation/timing/physical collateral |
| Project and flow support | Project declarations, harnesses, target resolution, elaboration, artifacts, flow adapters, optional invocation, and results |

Start with one package and clear module boundaries. Split packages later when
dependencies or distribution needs justify it. Process-specific conditionals
should not accumulate in portable resource contracts.

### Reference application and Workbench ownership

The [protocol emulator construction plan](../../scaf/docs/construction-plan.md)
owns its core, ISA, firmware, protocol mechanisms, small FIFOs/register file,
loader, host API, independent execution model, and protocol verification. It
declares the ASIC project using this library and owns its implementation choices,
wrapper behavior, timing assumptions, physical acceptance, and submission review.
The harness validates the wrapper interface; it does not implement the emulator's
reset/disable logic or pin arbitration. Program validity and fetch/load/readback
arbitration remain consumer responsibilities under the memory contract.

The [Workbench architecture](../../workbench/docs/hardcaml_workbench_architecture.md)
owns optional interactive project sessions, job supervision, logs, and artifact
views. An opened project's driver calls its own ASIC library version in its own
build environment. The Workbench manifest identifies entry points; ASIC target,
clock, resource policy, and resolved configuration facts come from the project
declaration/build rather than a second editable Workbench copy.

ASIC adapters own build rendering, tool-specific flow semantics, and result
interpretation. An external script or the optional runner can execute the emitted
bundle; Workbench supervises that operation as a job. Its job/artifact IDs link
to immutable ASIC build and separate execution identities without replacing them.
This does not require a GUI, a generic job scheduler in this library, or a second
ASIC configuration generator in Workbench. Exact driver/result schemas remain
integration work; ASIC support is not already implemented by the Workbench.

The sibling links use this workspace's checkout names, not required build paths.
Consumer packaging must pin/resolve the library and collateral without relying
on those names. Tool/PDK provisioning stays an explicit external operation during
initial adoption; its eventual reusable home is not decided by this architecture.

## 3. Target: harness and technology

A target combines two separately selected axes:

```ocaml
(* Conceptual shape, not a frozen API. *)
type target =
  { harness : Harness.t
  ; technology : Technology.t
  }
```

| Axis | Owns |
| --- | --- |
| Harness | Required top-level interface, tile or die requirements, pin placement, power interface and PDN requirements, submission metadata |
| Technology | Available cells and macros, supported resource shapes, Liberty/LEF/GDS and model references, process layers and corners |
| Resolved target | Compatibility of the pair, concrete die geometry, floorplan template, power connections, and permitted routing layers |

Not every pair is valid. A Tiny Tapeout floorplan template depends on both tile
selection and technology; a harness may restrict the layers available in the
process. Target resolution validates combinations and rejects unsupported ones.

The harness does not implement internal design logic, but it does inspect the
elaborated top-level interface to validate ports, widths, and directions.
Technology selection does not independently choose the project's die size.

Tiny Tapeout is the first harness integration. Future harnesses, including a
bare-die configuration, should fit this separation without putting TT submission
conventions into core resource APIs.

### Flow selection and compatibility

The flow adapter is selected separately from the harness/technology target. Tiny
Tapeout is a harness, CMOS5L is a technology, and LibreLane is the initial flow
adapter. A technology does not imply one tool vendor, and a flow adapter does not
define resource behavior or replace target requirements.

Validate the selected adapter's support for the resolved target, requested flow
operation, constraints, and resource collateral before emitting runnable inputs.
A valid harness/technology pair is not proof that every adapter can implement it.
Unsupported requirements must produce diagnostics rather than silently disappear.
This flow capability check is separate from exact resource implementation
selection in section 5.

## 4. Project declaration and elaboration lifecycle

The user declares an immutable project containing:

- Project identity and metadata, including descriptive pin meanings as needed.
- A design constructor that receives an elaboration context and builds the top.
- Harness and technology selections.
- Flow adapter and requested operation, initially the TT/LibreLane path.
- Clocks and other supported timing constraints.
- Resource implementation policies, optionally scoped to individual instances.
- Physical settings not fixed by the target.
- Flow overrides, each with an explanatory reason.

Resources are discovered through constructors during elaboration. There is no
second manually maintained list of instantiated memories or macros in the project
declaration. A policy list controls selection; it does not duplicate inventory.

```text
immutable Project declaration
  -> resolve target and validate policies
  -> create a fresh Elaboration_context for one elaboration
  -> run design constructor; resources select implementations and register
  -> validate top-level interface, resources, constraints, and configuration
  -> validate adapter support for target, operation, constraints, and collateral
  -> finalize immutable Build description
  -> emit artifacts
  -> optionally run a flow against those artifacts
```

`Elaboration_context` is temporarily mutable and belongs to one elaboration.
Resource constructors receive this narrower context, not a mutable global project.
It carries implementation selection and collects instance and collateral records.
Finalization closes registration. Failed or repeated elaborations cannot leak
resources into another build.

Instances need stable hierarchical identities, duplicate detection, and
deterministic manifest ordering. Selection must not depend on incidental
registration order. Integration with Hardcaml `Scope.t` and the exact identity API
remain interface-design work.

The same design constructor can be elaborated for behavioral simulation or an
implementation target. This does not promise arbitrary post-elaboration rewriting
of an already constructed generic circuit.

## 5. Resource selection and registration

Initially support exact resource mappings and explicitly permitted fallback.
Do not silently round width or depth, alter latency or behavior, select a larger
macro, combine macros, or replace a required macro with registers. Automatic
composition is deferred until concrete uses justify it.

A project can explicitly select a flop implementation, or permit it as fallback
when the preferred exact implementation is unavailable. A request with no allowed
implementation fails during elaboration with the instance identity, requested
contract, and selection failure reason. Backend capability describes what is
possible; project policy controls what is acceptable.

Each resource registers:

- Stable instance identity and requested configuration/behavior.
- Selected implementation and selection policy, including any fallback reason.
- Port mapping and any required wrapper or black-box declaration.
- Simulation model or behavioral implementation references.
- Timing and physical collateral, including applicable corners.
- Provenance needed by the build manifest.

Constructors may still return `Signal.t` or an ordinary Hardcaml interface.
Registration provides project information without adding nonarchitectural output
ports. A small internal macro/collateral description belongs in the first
milestone; a general public macro API can grow from subsequent real resources.

Simulation and synthesis source sets are distinct. Behavioral models and black-box
declarations must not be indiscriminately compiled together or produce duplicate
module definitions. Wrappers are emitted only when the implementation needs them.

## 6. Configuration ownership and escape hatches

Keep a typed core and explicit adapter-specific escape hatches. In the initial
LibreLane adapter, each configuration override contains a key, JSON value, and
nonempty reason; record it with its adapter identity in the manifest. This is a
LibreLane representation, not a universal configuration format for every flow.
The initial adapter must accommodate the emulator's existing flow settings
without requiring a typed API for every LibreLane option.

Future Tcl/SDC or structured vendor extensions belong to their adapter and must
declare their application stage and reason, with their contents captured in build
provenance. Reject extensions for a different adapter. Raw scripts cannot be
assumed to be fully understood by typed validation: define supported insertion
points and validation limits, and preserve the script for review. They do not
silently supersede protected project, resource, or target facts.

Distinguish overridable defaults from protected derived values:

1. Resolve target and flow defaults.
2. Apply explicit user settings and permitted overrides.
3. Validate protected requirements and generated facts. A conflicting assignment
   is an error explaining the owning declaration; it is not silently ignored.
4. Emit one resolved configuration with provenance for its values.

Generated source lists, target die bounds, required power connections, and other
fixed target requirements remain authoritative. Typed clock declarations must
not disagree with raw clock settings. Resource-owned collateral configuration
must not be silently replaced by a raw `MACROS` override; conflicts must be
diagnosed or handled by a deliberate supported merge.

The Tiny Tapeout reference at revision `da63c99`, `project.py:create_user_config`
and `create_merged_config`, demonstrates the ownership rule: generated
configuration overlays `src/config`. It derives `DESIGN_NAME`, `VERILOG_FILES`,
`DIE_AREA`, `FP_DEF_TEMPLATE`, `VDD_PIN`, `GND_PIN`, and `RT_MAX_LAYER`, then adds
technology configuration. The library adopts authoritative derived values with
explicit conflict errors.

In that revision the CMOS5L generated configuration does not set `MACROS`, so
project-supplied macro configuration survives the merge. This is an integration
hook, not evidence that an SRAM is available or accepted by the shuttle.

## 7. Build artifacts and provenance

The immutable build description is useful without invoking tools. Keep portable
design intent, resolved target/resources, and adapter-specific rendering inputs
distinct within it; a LibreLane configuration file is an output, not the core
project model. A flow adapter renders it into inputs that external scripts or an
optional library runner can consume. Commands, logs, and underlying tool inputs
remain inspectable.

An illustrative output layout is:

```text
_build/asic/protemu/
  rtl/protemu_top.v
  rtl/macros/                 wrappers/black boxes, when required
  simulation/                model references and simulation source list
  constraints/protemu.sdc
  flow/config.json
  flow/info.yaml             TT adapter output
  manifest.json              immutable build provenance and source sets
  runs/<run-id>/             execution record, logs, reports, and results
```

The TT integration owns `info.yaml` generation and its schema. Source lists, top
module, tiles, and clock information come from the project and resolved build.
Author, description, and pin meanings are declared metadata, not independently
maintained in a second source document. Clock declarations need one authoritative
representation and a defined conversion to each output's units.

The layout is conceptual: adapters must stage files and relative paths as their
pinned tools expect, including TT's project/source conventions.

The build manifest records source revision and content hashes (including dirty
or untracked inputs used by the build), generated RTL hashes, resource requests
and selections, source sets, collateral hashes, harness/technology revisions,
resolved configuration and override reasons, adapter identity/version and requested
operation, and requested tool versions. A Git commit alone is insufficient to
identify a dirty source tree. Referenced inputs
must also remain retrievable; hashes alone do not preserve their contents.

Each execution has a separate record of actual tool and environment versions,
commands, build-manifest identity, completion status, logs, and output/report
locations. Execution does not mutate the original build's provenance. Reports
distinguish an emitted build, a successful run, and physical verification still
required.

### Adapter and execution boundaries

An adapter owns capability validation, input rendering, tool-specific invocation
requirements, and interpretation of outputs. Rendering and result collection must
remain usable independently of execution. The runner or external launcher owns
process execution; a site wrapper or Workbench can supervise it without duplicating
flow semantics. Ordinary elaboration and input generation must not require a
commercial executable or license.

Do not require every flow to follow one fixed Yosys/OpenROAD stage sequence or to
produce GDS. A future synthesis-only adapter can produce a netlist and reports;
implementation or signoff adapters can have different inputs and outputs. Record
the requested operation and actual completed stages so synthesis success cannot
be mistaken for physical closure. The first adapter can remain a single
LibreLane flow; a generic workflow engine is not required.

Keep launcher/environment settings separate from design intent. A direct local
command is sufficient initially, but higher-level APIs must allow an external
wrapper to supply site setup, licenses, or scheduler integration later. Record
reproducibility-relevant tool/environment identities without copying credentials
or license secrets into manifests. Provisioning remains external and explicit.

Technology collateral must identify its role, format, applicable corner, and
provenance rather than assume every library is one Liberty/LEF/GDS file triplet.
Adapters validate the views required for their operation. Additional formats and
mode/corner models can be introduced with real adapters; proprietary collateral
can stay externally supplied without becoming a dependency of the open flow.

### Structured results

Preserve raw reports and expose a small typed result surface as the first adapter
is exercised. Metrics need units and analysis context: tool/version, stage,
applicable corner or mode, and a link to the source report. Missing, unsupported,
or unparseable metrics stay unavailable with a reason; they are not zero or pass.
Area definitions, timing setup/hold analyses, and power assumptions must remain
distinguishable before comparing values across tools or runs.

Keep process completion, timing goals, and required verification checks separate.
Backend-specific results may extend the common representation without forcing all
flows to pretend to support the same reports. A broad normalized report schema is
deferred; these interpretation rules apply to the initial results too.

## 8. First implementation milestone

The [implementation phase plan](phase_plan.md) breaks this milestone into P0–P5
tasks with dependencies, deliverables, and evidence-based exit gates. Its separate
SRAM investigation track does not block the initial flop-backed workflow. This
section retains the architectural scope and high-level sequence.

Build one complete path using the protocol emulator's program-memory requirement:

1. Sketch `Project`, `Elaboration_context`, `Target.resolve`, and immutable `Build`
   together, then connect `Single_port_ram.create` to that context.
2. Implement the behavioral model and an explicitly selected synthesizable flop
   implementation against the memory contract. Verify defined results and hold
   behavior without imposing poison values on physical implementations.
3. Elaborate a small reference design with registered program memory, validate
   its TT target/interface, and emit RTL, constraints, TT configuration/metadata,
   resource selections, and provenance.
4. Consume that bundle using existing flow tooling, record execution/results,
   and refine the adapter from integration findings. An optional library runner
   consumes the same bundle.
5. Apply that path to the emulator and use measured results to guide further work.

Coordinate with the emulator's [P0.6/P0.7 adoption items](../../scaf/docs/phase_plan.md#3-p0--make-the-tool-path-real):
P0.6 adopts declarations and emitted artifacts for its existing observable design;
P0.7 exercises a small registered load/readback memory design and mapped synthesis
before P3 integrates the full core/loader. Library implementation and backend
conformance stay here; emulator integration evidence stays there. Existing P0
scripts remain useful bundle consumers, with full physical/precheck/gate-level
checks required for the emulator's P0 exit. Do not reclassify the earlier RTL-only
P0 results as proof of ASIC-library adoption.

First-milestone library evidence should cover deterministic resource identity and
manifest ordering, fresh contexts on repeated/failed elaboration, interface and
configuration-conflict and adapter-capability diagnostics, explicit implementation
selection, distinct simulation/synthesis source sets, and contract-correct
behavioral/flop memories.
Consumer evidence adds whole-word load/readback, validity/bounds checks, and lack
of dependence on unspecified memory outputs. ISA width/depth/packing are study
parameters supplied by the consumer, not decisions made by the RAM constructor.

The first emitted project does not depend on a physical SRAM macro. A flop-backed
build is explicitly selected and reported as such, not presented as macro support.

CMOS5L macro support is a separate capability gate. The investigation recorded in
the memory contract has not established a usable SRAM. Inspect the bootstrapped
PDK and candidate collateral, then establish behavioral compatibility, target
permission, and flow integration before starting that backend. PDK presence alone
does not establish shuttle acceptance. Ordinary project elaboration should not
implicitly bootstrap or fetch a PDK.

## 9. Deferred work and remaining interface questions

Automatic memory composition, additional memory port shapes, clock gates, other
special primitives, multiple PDKs, a broad public macro API, and richer physical
planning APIs follow demonstrated needs. They are not prerequisites for the first
project workflow. Commercial EDA adapters, industrial power/signoff abstractions,
and Workbench UI integration are also later, need-driven work.

Future Cadence/Synopsys integration should exercise the same declaration, resource,
rendering, execution, and result boundaries, starting with one narrow adapter when
needed. Another open target is a useful portability test, not a new prerequisite
for the first milestone. Commercial adapters and their proprietary tools,
collateral, and licenses must remain optional. No industrial MMMC, power-intent,
DFT, scheduler, or signoff framework is required in the initial package.

The four high-level defaults are settled: immutable project plus temporary
registration context; declarative build plus optional runner; TT-owned metadata
generation; one initial package. Remaining design work includes exact OCaml
interfaces, hierarchical identity/`Scope.t` integration, timing endpoint identity
and validation, initial constraint coverage, and adapter staging conventions.
