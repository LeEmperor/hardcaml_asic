# hardcaml_asic phase plan

Status: working implementation plan, 2026-09-18. P0–P4 have evidence and P4's
exit gate is satisfied; P5 and the separate SRAM investigation remain open.

## 1. Purpose and use

This is the actionable breakdown of the
[first implementation milestone](architecture.md#8-first-implementation-milestone).
The [architecture plan](architecture.md) governs system boundaries and scope;
the [program-memory contract](program-memory-contract.md) governs RAM behavior.
This document owns task sequencing, dependencies, and completion evidence. Update
the governing document first if implementation reveals a required design change.

The initial usable system lets an independently built Hardcaml project declare
its TT/CMOS5L target and LibreLane flow, construct registered resources, emit a
reproducible bundle, and consume execution results. It includes behavioral and
explicitly selected flop memory. It does not require a physical SRAM macro,
Workbench, commercial tools, or a library-owned process runner.

- Keep task IDs stable. Use `ASIC P1.3` when discussing work alongside the
  emulator's separate phase plan; its `P0.6` is not an ASIC-library task ID.
- Each checkbox is a reviewable implementation slice with completion evidence.
  Split a large task into suffixed IDs while preserving its acceptance goal.
- Check an item only when its deliverable and evidence exist; link the relevant
  code, test, or experiment record beside it. A sketch or scaffold is insufficient.
- Record blockers and missing prerequisites beside unchecked tasks. A phase exits
  only when its required tasks and exit gate are satisfied.
- Keep source in the existing `lib/` package initially. Add example, executable,
  and test directories when their first working contents land. Do not scaffold
  empty future adapter packages.
- Use `dune build` and `dune runtest` for implementation checks. Physical-tool
  evidence is a separate, explicitly provisioned integration activity; ordinary
  library tests must not require a PDK or licensed tools.

### Starting state

Before P0, [`Single_port_ram.Config`](../lib/single_port_ram.ml) validated width,
depth, and latency and exposed address/storage sizes; `Single_port_ram.create` was
a stub without the planned elaboration context. No project/context/build API,
memory implementation, technology binding, or flow adapter existed.

After P1, the project lifecycle, elaboration context, resource identity, selection
policy, immutable build, and registered single-port RAM exist. The behavioral
model and explicit flop implementation pass contract checks, including a generated
RTL simulation. No target resolution, bundle emission (P3), or flow execution
(P4) existed at that checkpoint. P2 now provides a separate validated
`Resolved_build` boundary for TT/LibreLane emission. P3 now emits TT bundles;
flow execution and results (P4) remain open.

## 2. Phase map and dependencies

| Phase | Deliverable | Main prerequisites |
| --- | --- | --- |
| P0 — Project foundations | Compiling declaration/context/build path with deterministic registration | Existing package and accepted contracts |
| P1 — Program memory | Verified behavioral and explicit flop implementations | P0 context, resource records, and selection interface |
| P2 — Target and constraints | Validated TT/CMOS5L target, timing intent, and flow configuration | P0 project/target interfaces; memory checks integrate with P1 |
| P3 — Build emission | Deterministic RTL, constraints, TT configuration/metadata, and manifest | P0/P2; P1 for the memory example |
| P4 — Execution and results | Bundle consumption, run records, report collection, and physical evidence | P3 bundle and explicitly prepared tool environment |
| P5 — Consumer adoption | Independently built emulator consumes the library and reproduces the path | P3 for initial adoption; P1/P4 for full closure |
| S — SRAM capability investigation | Evidence-backed support or deferral decision; conditional macro implementation | Candidate PDK/collateral access; no dependency for P0–P5 |

These phases subdivide the architecture's first milestone. They are not the four
long-term phases in the direction note. P0–P5 together establish initial usage;
later open targets and commercial adapters follow demonstrated needs.

Phases can interleave. P1 and P2 can proceed once the relevant P0 interfaces are
available. P3 can first emit a resource-free observable design, then add the P1
memory example. Prepare the external tool environment early. Start P5 dependency
packaging and consumer integration as soon as the required library slice exists;
consumer feedback can close P3/P4 rather than wait for every library phase to exit.

The useful intermediate milestones are:

| Milestone | What a user can do | Completion boundary |
| --- | --- | --- |
| M1 — Resource usage | Construct and simulate registered program memory and elaborate its explicit flop implementation | P0 and P1 exit |
| M2 — Project bundle | Generate validated TT/LibreLane inputs from a project declaration, including the memory example | P2 and P3 exit, with M1 |
| M3 — Initial ASIC workflow | Build a separate consumer, execute emitted inputs, and inspect traceable results | P4 and P5 exit, with M2 |

### First implementation queue

1. P0.1–P0.3: establish a compiling lifecycle and registration with a small
   fixture, resolving naming and selection interfaces through that example.
2. P1.1–P1.3: connect the real RAM constructor and make behavioral/flop memory
   work. Start the P1.4 conformance suite alongside those implementations.
3. P2.1–P2.5: bind the reference target and implement the actual interface,
   constraint, override, and adapter capability subset needed by its existing flow.
4. P3.1–P3.4: emit and validate the first complete bundle; begin P5.1/P5.2 adoption.
5. P4 and the remaining P5 tasks: execute, collect evidence, fix integration
   failures, and reproduce the consumer path from its recorded dependencies.

Finish each phase's remaining validation before declaring its milestone complete.

## 3. P0 — Project and elaboration foundations

**Entry:** the existing package, architecture, and RAM contract. Resolve concrete
OCaml interfaces here without freezing a broad public framework.

- [x] **P0.1 — Establish the project lifecycle.** Introduce the minimum
  `Project`, `Elaboration_context`, target/flow selection types, and immutable
  `Build` description together. The constructor receives a fresh context;
  simulation and implementation elaboration modes are explicit. Define where
  validation and finalization occur. Evidence: a compiling small design goes
  from declaration to finalized build without invoking an external tool.
  *Done:* [`Project`](../lib/project.mli) (declaration validation in `create`,
  elaboration/finalization in `elaborate`), [`Elaboration_context`](../lib/elaboration_context.mli),
  [`Elaboration_mode`](../lib/elaboration_mode.ml), [`Target`](../lib/target.ml)/
  [`Harness`](../lib/harness.ml)/[`Technology`](../lib/technology.mli),
  [`Flow`](../lib/flow.ml), [`Build`](../lib/build.mli). Evidence:
  [`test_lifecycle.ml`](../test/test_lifecycle.ml) "declaration to finalized
  implementation build" and "simulation mode elaborates behavioural models and
  simulates"; the fixture is [`test/fixture.ml`](../test/fixture.ml).
- [x] **P0.2 — Register resources with stable identities.** Define context and
  `Scope.t` cooperation, explicit names, hierarchy, duplicate detection, and
  deterministic ordering. Finalization closes registration; failed or repeated
  elaborations cannot reuse collected state. Evidence: lifecycle tests cover
  duplicates, registration after finalization, failed construction followed by a
  clean retry, and repeatable instance identities and inventory ordering.
  *Done:* the context carries the current `Scope.t` (`Elaboration_context.scope`,
  `in_scope`, which rejects scopes from another elaboration); a
  [`Resource_id`](../lib/resource_id.mli) is the scope path plus an explicit name,
  duplicates raise, and the inventory is sorted by full path. Hardcaml mangles
  repeated instance labels in creation order, so hierarchical instances holding
  resources need explicit distinct `~instance` names for identities to survive
  design edits (documented in `resource_id.mli`). Evidence:
  [`test_lifecycle.ml`](../test/test_lifecycle.ml) duplicate, retained-context,
  failed-then-retry, foreign-scope, and registration-order tests.
- [x] **P0.3 — Define selection policy and resource records.** Separate requested
  contract, technology capability, and project policy. Support explicit flops,
  exact implementation requirements, and explicitly allowed flop fallback, with
  per-instance policy scoping and defined precedence. Record selection/fallback
  reasons and source/collateral roles. Evidence: focused selection tests reject
  missing exact mappings and ambiguous policies, preserve requested shape and
  semantics, and distinguish explicit flops from fallback. Fixture descriptors
  are test inputs, not evidence of a real macro backend.
  *Done:* [`Resource_request`](../lib/resource_request.mli) (requested contract,
  exact-equality matching), [`Technology`](../lib/technology.mli) (capability;
  duplicate mappings rejected; CMOS5L has none),
  [`Resource_policy`](../lib/resource_policy.mli) (`Flops`/`Exact`/
  `Exact_or_flop_fallback`; instance over deeper subtree over default; repeated
  selectors, missing policy, and unmatched rules rejected),
  [`Selection`](../lib/selection.ml), and [`Resource_record`](../lib/resource_record.ml)
  (policy source, selection reason, elaborated form, source/collateral roles).
  Policy applies in both elaboration modes. Evidence:
  [`test_selection.ml`](../test/test_selection.ml).
- [x] **P0.4 — Finalize the portable build boundary.** Capture project metadata,
  resolved target/resource information, constraints, adapter identity/operation,
  and adapter-specific settings without using LibreLane JSON as the core model.
  Evidence: the finalized build can be inspected without tool execution and
  cannot acquire new registrations or change through a retained context.
  *Done:* [`Build`](../lib/build.mli) is abstract and inspectable (`sexp_of_t`),
  holding metadata, mode, target selection, declared clocks, the resource
  inventory, and adapter identity/operation/settings (LibreLane overrides with
  required reasons). The target is the declared selection; P2 resolution returns
  a separate `Resolved_build` with target and validated constraints. Evidence: the lifecycle
  build print and retained-context test in
  [`test_lifecycle.ml`](../test/test_lifecycle.ml).

**Exit gate:** a small executable fixture demonstrates declaration, registration,
validation, and immutable finalization. Lifecycle and policy failures produce
actionable diagnostics. A real memory implementation is the next phase, not a
prerequisite for exercising the lifecycle with a fixture.

## 4. P1 — Contract-correct program memory

**Entry:** P0 context, identity, selection, and resource-record interfaces.
Follow the [memory contract](program-memory-contract.md); this plan does not
introduce new memory semantics.

- [x] **P1.1 — Migrate the RAM constructor.** Add the planned context argument,
  validate signal widths and configuration, select an implementation, and register
  every instance, including flops. Continue returning read data. Evidence: real
  RAM elaboration records the requested shape, stable identity, and selection;
  invalid ports and unsupported requests fail with instance-specific diagnostics.
  Update the `.mli` and example call sites together.
  *Done:* [`Single_port_ram.create`](../lib/single_port_ram.mli) checks every port,
  registers the contract and identity, and follows the context's selection.
  [`test_single_port_ram.ml`](../test/test_single_port_ram.ml) checks the
  inventory, repeatability, invalid ports, and unsupported requests.
- [x] **P1.2 — Implement the behavioral model.** Provide latency-one reads,
  whole-word writes, and disabled-output hold. Initialize the simulation model
  with diagnostic poison and poison post-write output; diagnose enabled
  out-of-range access. Evidence: cycle traces check each operation, unwritten
  reads, disabled writes, and hold after both reads and writes. The testbench
  tracks validity; no validity/reset port is added to the primitive.
  *Done:* `Simulation` elaboration initializes words with alternating-bit poison
  and injects poison after writes and enabled out-of-range accesses. The
  [contract trace](../test/test_single_port_ram.ml) checks unwritten reads,
  disabled writes, hold, and non-power-of-two address bounds.
- [x] **P1.3 — Implement explicit synthesizable flop storage.** Satisfy the same
  defined behavior without simulation poison logic, an initialization guarantee,
  or a bulk reset. Use the selection policy rather than silent inference fallback.
  Evidence: elaboration produces functional RTL and a flop selection record;
  generated-RTL simulation verifies writes, latency, and hold. Keep behavioral
  and synthesis source roles separate from the start.
  *Done:* one register per word with decoded whole-word write enable and a
  registered read output. The [test](../test/test_single_port_ram.ml) verifies
  selection/source records and that generated flop Verilog has no
  initialization. [`memory_example_tb.v`](../test/memory_example_tb.v) checks
  generated RTL using Icarus Verilog 12.0. The reusable
  [runner](../test/run_rtl_sim.sh) works with installed `iverilog`/`vvp` or
  explicit executable paths; ordinary Dune checks do not require Icarus.
- [x] **P1.4 — Run one contract conformance suite.** Use an independent scoreboard
  tracking written locations, contents, latency, and output definedness. Cover
  consecutive operations, write/read sequences, disabled writes, non-power-of-two
  depth, and hold after defined and unspecified outputs. Compare defined values
  across implementations and check each implementation's own held output;
  poison and invalid-access diagnostics are behavioral-model checks only.
  Evidence: the suite passes for both implementations, including generated RTL
  for the flop path, without requiring agreement on unspecified values.
  *Done:* [`test_single_port_ram.ml`](../test/test_single_port_ram.ml) applies
  an independent written-location/output-definedness scoreboard to both
  elaborations, checks each backend's own held output, and tests behavioral
  poison and invalid-address diagnostics separately. The generated RTL
  testbench repeats defined write/read/hold cases against the Verilog output.
- [x] **P1.5 — Demonstrate portable resource usage.** Add a small library-owned
  memory example using one design constructor for behavioral and implementation
  elaborations. Its stimulus writes complete words before checking readback and
  tracks acceptance/validity outside the RAM. Evidence: build and simulation
  commands work without a PDK, inventory is repeatable, and a macro-required
  request fails unless a permitted fallback is selected and recorded.
  *Done:* [`memory_example.ml`](../examples/memory_example.ml) uses one design
  constructor in both modes, tracks written words outside RAM, and demonstrates
  explicit flops, rejected exact macro selection, and recorded fallback. Commands
  are in the [memory example guide](memory-example.md).

**Exit gate / M1:** `create` is functional, both implementations pass conformance,
and the registered example works without an ASIC installation. This establishes
portable resource usage, not SRAM macro support or physical area/timing results.

*Gate met, 2026-09-17:* `dune build`, `dune runtest`, the
[library example](memory-example.md), and the generated-flop-RTL testbench pass.

## 5. P2 — Target, timing, and configuration resolution

**Entry:** P0 declaration/target interfaces. Use the emulator's pinned
[flow plan](../../scaf/tinytapeout/README.md) and
[toolchain lock](../../scaf/tinytapeout/toolchain.lock) as reference inputs;
record the revisions actually adopted rather than assuming upstream defaults.

- [x] **P2.1 — Implement separate TT harness and CMOS5L technology descriptions.**
  Resolve supported combinations, tile geometry, floorplan templates, power
  connections, and permitted routing layers. Record library/view references and
  revisions with their roles and applicable corners. Evidence: the reference
  combination resolves deterministically; unsupported combinations or missing
  required target inputs fail. Resolution does not fetch or bootstrap a PDK.
  *Done:* [`Target.resolve`](../lib/target.mli) accepts the pinned `6x4` TT / CMOS5L
  pair and returns geometry, DEF reference and hash, power pins, routing range,
  corner, and role-labelled PDK views. [`Technology.Cmos5l`](../lib/technology.mli)
  holds standard-cell views separately from resource capability, with no SRAM
  mapping. [`test_target.ml`](../test/test_target.ml) checks repeatability,
  unsupported pairs, and missing/malformed target inputs. The adopted revisions
  and source references are in the [target reference](target-reference.md).
- [x] **P2.2 — Validate the elaborated top-level interface.** Check required
  names, widths, directions, and metadata against the harness. Evidence: the
  reference wrapper passes and malformed interfaces fail with precise diagnostics.
  Wrapper reset/disable behavior and pin arbitration remain consumer logic.
  *Done:* [`Resolved_build.validate_interface`](../lib/resolved_build.ml) checks
  the TT wrapper's exact input/output names, directions, and widths, including
  Hardcaml phantom inputs; TT metadata requires a nonblank author/description and
  all 24 [pin descriptions](../lib/pinout.ml). The TT-shaped Hardcaml wrapper and
  malformed width/direction/metadata cases are in
  [`test_resolved_build.ml`](../test/test_resolved_build.ml).
- [x] **P2.3 — Implement the first typed constraint subset.** Inventory the clocks
  and timing assumptions required by the reference flow, settle endpoint identity
  and unit conversion, then implement that subset and its validation. Evidence:
  declared clocks resolve against the elaborated interface; malformed units or
  endpoints and unsupported intent fail; every required reference constraint has
  an identified owner and rendering path. Do not expand to all SDC commands.
  *Done:* [`Clock`](../lib/clock.ml) uses a floating span to retain the 48 MHz
  fractional-nanosecond period. [`Timing`](../lib/timing.ml) declares optional
  maximum I/O delays; [`Resolved_build`](../lib/resolved_build.ml) requires one
  clock on `clk`, validates endpoint direction and finite nonnegative delays,
  rejects duplicates/additional clocks, and converts to nanoseconds and hertz.
  The [target reference](target-reference.md#validated-ttlibrelane-build) assigns
  `CLOCK_PORT`/`CLOCK_PERIOD`, TT `clock_hz`, and future SDC rendering to their
  owners. Tests cover 48 MHz, invalid endpoints, and malformed delays.
- [x] **P2.4 — Resolve flow defaults and overrides.** Add LibreLane key/JSON/reason
  overrides tied to the adapter. Distinguish defaults from generated source lists,
  clocks, target geometry, power, and resource-owned collateral. Evidence: the
  reference project's required settings are representable, permitted overrides
  retain provenance, and conflicting protected assignments fail. A raw `MACROS`
  setting cannot silently replace registered resources.
  *Done:* [`Flow`](../lib/flow.ml) rejects malformed keys, non-JSON values, and
  missing reasons. [`Resolved_build`](../lib/resolved_build.ml) produces sorted
  settings owned by design, target, clock, default, or reasoned override. Tests
  cover the pinned consumer's configurable keys and conflicts on generated
  sources, target facts, clocks, SDC paths, and `MACROS`.
- [x] **P2.5 — Validate adapter capabilities.** Define the initial supported
  operation and required constraints/source/view roles separately from technology
  resource capability. Evidence: unsupported adapter/target/operation combinations,
  unavailable required views, and settings for the wrong adapter are rejected
  before runnable inputs are emitted. A future operation can have different
  outputs without making GDS a mandatory field of every result.
  *Done:* `Project.elaborate_for_flow` combines implementation elaboration and
  validation. LibreLane synthesis and hardening have separate required view
  roles; hardening requires cell GDS, synthesis does not. Simulation builds,
  missing views, missing synthesis source roles, and macro selections fail at
  this boundary. A LibreLane setting belongs to the LibreLane adapter by type;
  there is no other adapter in this initial API. The capability cases are in
  [`test_resolved_build.ml`](../test/test_resolved_build.ml).

**Exit gate:** the reference target and required configuration resolve from one
declaration, interface/constraint checks pass, and unsupported or conflicting
requests fail before emission. No physical SRAM capability is inferred from
standard-cell technology support or the presence of a PDK.

*Gate met, 2026-09-17:* `dune build` and `dune runtest` pass, including TT-shaped
wrapper validation, target/view failures, clock conversion, configuration
ownership, and adapter capability checks. No bundle or physical-tool result is
claimed; those are P3/P4.

## 6. P3 — Deterministic build bundle

**Entry:** P0/P2 for the observable design; P1 for the registered memory example.
The [build artifact rules](architecture.md#7-build-artifacts-and-provenance) govern
the output; exact staging paths follow the pinned TT tools.

- [x] **P3.1 — Emit RTL and explicit source sets.** Render the named top and
  dependencies from the finalized build. Separate synthesis sources, simulation
  sources/models, and any required wrappers or black boxes. Evidence: each source
  set compiles independently, no duplicate module definitions occur, and the flop
  example's synthesis bundle contains no behavioral poison initialization.
  *Done:* [`Bundle.render`](../lib/bundle.mli) emits the flattened implementation
  top under `src/` and the separately elaborated behavioral model under
  `simulation/`. Each manifest source set names one path. The
  [bundle regression](../test/check_bundle.py) compiles and simulates both sets
  independently with [Icarus testbench](../test/tt_bundle_tb.v), and checks the
  synthesis memory RTL has no behavioral initialization.
- [x] **P3.2 — Render constraints and TT flow inputs.** Generate SDC, resolved
  LibreLane configuration, and TT metadata from the declaration/build. Populate
  source lists, top, tiles, clock information, author/description, and pin meanings
  from their owning fields. Evidence: generated files agree on names, paths, and
  units and satisfy the pinned staging/configuration checks; no second editable
  metadata source or undocumented manual patch is needed.
  *Done:* [`Bundle`](../lib/bundle.ml) writes typed clock and optional maximum
  I/O delays to SDC, sorted resolved settings plus protected source/SDC paths to
  `src/config.json`, and `info.yaml` from the same metadata, pinout, clock, top,
  and source list. The directory and `dir::` paths follow the pinned TT
  `project.py:create_user_config` layout. The regression checks top/source/clock
  agreement, `6x4` die area, and rendered delays. The
  [emission guide](bundle-emission.md) describes the staging boundary.
- [x] **P3.3 — Emit immutable provenance.** Define the initial manifest format
  and its version, including source revision plus dirty/untracked input hashes,
  generated RTL, selected resources, source roles, collateral/target revisions,
  adapter/operation, resolved settings, override reasons, and requested tools.
  Preserve or document how to retrieve referenced input contents. Evidence:
  identical inputs yield identical ordered bundle/manifest content; changed input
  content changes identity, including uncommitted changes. Run timestamps and
  actual execution details belong to separate records.
  *Done:* `manifest.json` schema 1 has a SHA-256 identity, ordered file hashes,
  source revision, Git status and copied bytes for each declared source input,
  source sets, resource requests/selections/roles, target references/revisions,
  resolved setting ownership and override reasons, adapter/operation, and pinned
  requested tool versions. The flop path has no macro collateral; standard-cell
  PDK views remain external revision/path references for P4 preflight, while the
  floorplan has a pinned hash. The regression proves stable manifests and changed
  identity for tracked edits and new untracked inputs.
- [x] **P3.4 — Provide one documented emission command.** Add a small CLI/example
  entry point for the observable design and memory example. It emits the bundle
  without launching EDA tools and diagnoses unavailable inputs. Evidence: the
  documented commands recreate the bundle in a clean output directory using
  declared inputs and do not depend on the workspace's sibling checkout names.
  *Done:* [`tt_bundle_example.ml`](../examples/tt_bundle_example.ml) provides
  `observable` and `memory` commands in the [guide](bundle-emission.md), with an
  optional explicit source root. It uses no sibling checkout path. Missing source
  inputs and nonempty output directories fail; the regression covers the former.
- [x] **P3.5 — Verify the complete emitted example.** Exercise declaration,
  registration, target resolution, emission, and generated-RTL simulation together.
  Check that output files match their recorded hashes and that source/collateral
  references resolve. Evidence: both examples have reproducible generation and
  functional RTL checks, with targeted regression coverage for ownership errors.
  *Done:* [`dune runtest`](../test/dune) emits both declarations in a temporary
  Git repository, checks every bundle/source hash and referenced source path,
  repeats emission byte-for-byte, and runs the synthesis and simulation RTL
  benches when Icarus is installed. It checks the flop selection and the absence
  of a macro collateral requirement. Configuration ownership error cases remain
  in [`test_resolved_build.ml`](../test/test_resolved_build.ml). External PDK file
  availability is the explicit P4.1 preflight, not an ordinary bundle test.

**Exit gate / M2:** an independent script can consume complete, validated inputs
for the registered flop-memory example. Emission and simulation work without
running physical tools. A generated configuration alone does not establish that
the physical flow accepts it; that evidence is P4.

*Gate met, 2026-09-17:* `dune build` and `dune runtest` pass. The independent
bundle checker consumes both emitted examples, verifies hashes and TT file/path
agreement, and simulates both source sets with Icarus on this machine. P4 still
owns installed PDK checks and physical-tool acceptance.

## 7. P4 — Execution, results, and physical integration

**Entry:** a P3 bundle for execution. Environment preparation can start earlier.
Use existing external scripts first; implementing the optional library runner is
not required to close this phase.

- [x] **P4.1 — Document and prepare the external environment.** Record the pinned
  tools, PDK/library inputs, staging requirements, and explicit setup commands.
  Reuse the reference application's provisioning where appropriate. Evidence: a
  reproducible preflight establishes required files and tools; missing prerequisites
  are reported without implicit installation during elaboration or emission.
  *Done:* the [execution guide](phase4-execution.md) gives explicit setup and
  preflight commands. [`phase4.py`](../scripts/phase4.py) checks every emitted
  file hash, target reference and revision, installed LibreLane, Python, Docker,
  and the exact container image without installing anything. The
  [memory preflight](../evidence/p4/memory-synthesis/preflight.json) records all
  external hashes and the intentional Python-version exceptions on this host.
- [x] **P4.2 — Execute the emitted bundle and record runs.** Document the adapter's
  invocation requirements and provide an external consumer command. Record a
  separate run identity, build-manifest identity, actual tools/environment,
  commands, requested/completed stages, status, logs, and output locations.
  Evidence: execution leaves the build's provenance unchanged; repeated attempts
  have distinct run records; failed or interrupted runs retain useful diagnostics.
  *Done:* `phase4.py run` executes the exact emitted `src/config.json` in a
  per-attempt staging directory. Its [run record](../evidence/p4/memory-synthesis/run.json)
  has a distinct UUID, manifest hash/build identity, environment, commands,
  status, and artifact paths; the archived attempt includes the unchanged
  manifest. A [failed native attempt](../evidence/p4/failed-native-run/run.json)
  retained its own ID and [diagnostic log](../evidence/p4/failed-native-run/execution.log).
- [x] **P4.3 — Collect structured results independently of execution.** Parse the
  initial useful timing/area/check results and preserve raw report/artifact links.
  Include units, definitions, stage, tool/version, and applicable mode/corner.
  Evidence: report fixtures cover successful, partial, absent, and malformed
  outputs. Unavailable metrics carry reasons; process success, timing goals, and
  physical checks remain separate. Collection can run on an existing run directory.
  *Done:* `phase4.py collect` reads an existing run directory without executing
  tools. It reports units, stage, corner, tool version, raw paths, unavailable
  reasons, and separate process/timing/check statuses. The
  [fixture tests](../test/test_phase4.py) cover complete, partial, absent, and
  malformed reports; the [memory result](../evidence/p4/memory-synthesis/results.json)
  exercises real Yosys reports.
- [x] **P4.4 — Prove mapped synthesis for registered memory.** Consume the P3
  flop-memory bundle with the pinned technology and record mapped cost and actual
  selected resources. Evidence: synthesis completes without accidental macro
  substitution or unresolved black boxes; results link to the exact build and
  run. Fix rendering problems in the adapter, not by hand-editing emitted files.
  *Done:* the [memory synthesis record](../evidence/p4/memory-synthesis/README.md)
  links the build/run identities and archived inputs, logs, and reports. Yosys
  mapped 179 `sg13cmos5l_*` cells (3,480.0192 µm²); unmapped instances and
  synthesis check errors were zero. The manifest records explicit flops with no
  macro collateral. The Python launcher/container versions differ from the
  bundle's request and are disclosed in the preflight record.
- [x] **P4.5 — Prove the small physical path.** Run the adopted-bundle observable
  design through hardening, required physical checks, TT precheck, and gate-level
  wrapper verification. Record constraints, timing outcomes, and check status.
  Evidence: the small design meets its declared acceptance criteria, with commands,
  inputs, logs, and reports sufficient for reproduction. This can use the emulator's
  adopted observable design and count jointly with P5 evidence; a second identical
  physical run is not required merely because two plans reference it.
  *Done:* the [observable physical record](../evidence/p4/observable-physical/README.md)
  links the build/run identities, the immutable manifest, preflight, run,
  postcheck, and structured results, with logs and signoff reports archived
  beside them. `tt_um_asic_observable` hardened onto the pinned TT 6x4
  `ihp-sg13cmos5l` tile at 48 MHz: timing passes on all three reported corners
  (worst setup 15.882 ns, worst hold 0.148 ns, no violations, no unconstrained
  mode), antenna/DRC/LVS pass, TT precheck passes all nine rows, and gate-level
  simulation of the final netlist against `test/tt_bundle_tb.v` passes.
  Inferred latches, unmapped instances, and synthesis errors are zero.
  This run used the library's own example, so it is P4.5 evidence only; P5.4
  still needs the consumer's adopted design.

**Exit gate:** the memory example has successful mapped synthesis, the small
observable design has the physical/check evidence above, and both retain build/run
identity. Failures remain open with diagnostics. This gate does not require the
full emulator core, a macro implementation, or a declaration of tapeout readiness.

## 8. P5 — Reference-consumer adoption and initial usage

**Entry:** begin dependency packaging and observable-design adoption when P3 is
usable. P1 supplies memory; P4 supplies execution/results. Adoption is part of
closing the library milestone, not a prerequisite that must already be complete.
Consumer code and tests stay in the emulator repository; library fixes stay here.

As of 2026-09-17 the emulator has deferred its adoption
([emulator non-linear sequencing](../../scaf/docs/phase_plan.md#non-linear-sequencing-rtl-decoupled-from-asic-adoption)):
its P0.6 starts once P5.1 here has evidence and its UART TX slice (P2.7) or
store-consumer logic (P3.1a) is complete, and must land before its P3 exits.
P5.1 and P5.5 can proceed independently; P5.2–P5.4, and therefore M3, wait on
that trigger. Do not substitute a library-owned fixture for the consumer evidence.

- [x] **P5.1 — Make the library consumable from a separate project.** Establish
  the Dune/package installation or pinned dependency mechanism needed by the
  consumer, with version/revision and collateral resolution instructions. Keep
  one initial library package. Evidence: a separately built consumer resolves and
  links the library without relying on a checkout named `../hardcaml_asic`.
  Registry publication is not required.
  *Done:* [`dune-project`](../dune-project), [`lib/dune`](../lib/dune), and the
  generated [`hardcaml_asic.opam`](../hardcaml_asic.opam) install one versioned
  package. [`test/package_consumer_smoke.sh`](../test/package_consumer_smoke.sh)
  installs to an isolated prefix, builds an unrelated Dune consumer under `/tmp`,
  and runs it successfully. [`Consumer installation`](consumer-installation.md)
  gives exact-revision pin and collateral instructions, plus the evidence and
  uncommitted-source limitation of this check.
- [ ] **P5.2 — Support emulator P0.6 adoption.** Replace its duplicate configuration
  authority with a declaration for the existing observable design and emulator-owned
  wrapper. Generate target, clock, metadata, source sets, and reasoned overrides.
  Evidence: link its P0.6 integration change, repeatable emitted bundle, wrapper
  regression, and configuration-conflict checks. Earlier RTL-only evidence is not
  proof of library adoption.
- [ ] **P5.3 — Support emulator P0.7 memory integration.** After P5.2, integrate its
  small registered whole-word load/readback design using explicitly selected flops.
  Evidence: link consumer validity/bounds/access-gating checks, latency/hold checks,
  independence from unspecified outputs, and mapped synthesis results. Reuse P4.4
  evidence when it is for this exact adopted design. The emulator's full core,
  firmware loader, and ISA decisions remain its P3 work.
- [ ] **P5.4 — Reproduce the adopted physical path.** Ensure the consumer's physical
  run and required checks use the emitted bundle and pinned dependencies. Evidence:
  link the adopted-design P0 exit evidence and its build/run records, including
  P4.5 where shared. Restore inputs in a clean staging location and verify that
  reproducing emission requires no undocumented sibling paths or manual edits.
  A prior run of the old configuration path does not qualify.
  *Note:* when this lands, the [execution guide](phase4-execution.md) stops being
  about a phase. It is the standing flow guide and the only documentation of
  `flow.sh`, `report.py`, and `archive.py`; rename it to `flow.md` then, updating
  the six files that link it (`README.md`, `docs/README.md`, this plan,
  `bootstrap.md`, `bundle-emission.md`, `consumer-installation.md`). The P4 gate
  narrative stays in section 7 above.
- [ ] **P5.5 — Publish initial usage documentation in the repository.** Document a
  minimal declaration, behavioral versus implementation elaboration, memory policy,
  explicit environment setup, emission/execution/collection commands, output
  interpretation, and common diagnostics. Update implemented/planned status in the
  README and relevant interfaces. Evidence: the examples and commands match the
  delivered API and the consumer evidence; limitations and deferred features are
  explicit. No external publication or hosted service is required.

**Exit gate / M3:** P0–P5 required tasks have evidence. A separate consumer can
declare, build, simulate, emit, execute, and inspect the initial TT/LibreLane path
with registered flop memory. The adopted observable physical run and memory
synthesis have traceable evidence. Consumer hardware semantics and final submission
approval remain consumer responsibilities.

## 9. S — Separate SRAM capability investigation

This track may start early and informs the emulator's P5.1a study. It never blocks
the explicit flop path. The [current investigation](program-memory-contract.md#8-backend-obligations)
has not established a usable CMOS5L SRAM; do not start the library macro backend
until availability, contract compatibility, target permission, and flow integration
are established.

- [ ] **S.1 — Inventory candidate macros and collateral.** Inspect explicitly
  provisioned PDK/library inputs and record versions, permitted use, exact shapes,
  port/power mappings, simulation models, timing corners, and physical views.
  Evidence: a source-backed candidate inventory or a documented absence. A
  `MACROS` configuration hook alone does not establish macro support.
- [ ] **S.2 — Establish behavioral and target compatibility.** Evaluate the
  latency-one, whole-word 1RW, hold-on-disable contract against candidate models
  and documentation, and establish permission for the selected TT target.
  Evidence: model checks and authoritative target/collateral references, with
  unresolved questions called out. A shape mismatch is not silently composed or
  rounded into support.
- [ ] **S.3 — Establish flow feasibility and record a decision.** Use a minimal
  external integration probe to exercise candidate views, power connections,
  constraints, and required physical/precheck handling before building the library
  backend. Evidence: a reproducible supported-candidate result or a documented
  decision to defer, including the missing evidence and next investigation step.
- [ ] **S.4 — Implement a verified exact mapping, conditional on S.1–S.3 establishing
  capability.** Add the technology resource mapping, required wrapper/source
  roles, and registered collateral. Run P1 conformance against the macro model
  and repeat relevant emitted-flow checks. Evidence: exact selection and physical
  integration pass and macro-required unsupported requests still fail. If S.3
  defers support, leave this item deferred; it is not part of M3's exit gate.

The investigation can finish with a supported or deferred capability decision.
Only the additional implementation/conformance evidence permits claiming macro
backend support. Width/depth and instruction-packing choices remain the consumer's
measured design decisions.

## 10. Deferred expansion

After M3, prioritize work from real consumers and measured limitations:

- More resources or shapes, public macro APIs, and automatic composition require
  new contracts and concrete uses.
- Another open harness/technology/flow can test portability of the existing
  boundaries; it is not an initial release gate.
- An optional runner or Workbench driver can consume the same bundles/results;
  neither becomes a second source of ASIC configuration.
- A narrow Cadence/Synopsys adapter can add its own scripts, capabilities, formats,
  and reports without changing portable RAM behavior. Licensed tools and
  proprietary collateral remain optional external dependencies.
- Industrial MMMC, power intent, DFT, signoff frameworks, and scheduler integrations
  remain need-driven work, not empty modules to create during P0.

Expand this plan with concrete tasks and evidence gates when one of those efforts
is selected. Preserve the current task IDs and completed evidence.
