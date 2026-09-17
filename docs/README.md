# Documentation

- [Implementation phase plan](phase_plan.md): actionable P0–P5 tasks,
  dependencies, intermediate usage milestones, and evidence-based exit gates
  for the first TT/LibreLane path, plus a separate SRAM investigation track.
  Start here to choose implementation work.
- [Architecture and implementation plan](architecture.md): accepted system
  boundaries, project lifecycle, target and resource policies, build outputs,
  implementation sequencing, and boundaries for future third-party flow adapters.
  Use this for architecture and scope decisions.
- [Program-memory contract](program-memory-contract.md): authoritative behavior,
  verification obligations, and project integration for `Single_port_ram`.
- [Registered memory example](memory-example.md): PDK-free simulation,
  implementation elaboration, selection outcomes, and optional generated RTL test.
- [Comment and formatting guidelines](comment_guidelines.md): header, doc comment,
  alignment and error message conventions, with a table of reference files in `lib/`
  for each kind of example.
- [Architecture direction](hardcaml_asic_architecture_direction.md): Tiny Tapeout
  first, with optional future open/commercial-flow adapters. Examples align with
  the accepted plan; broader API/module sketches remain exploratory.
- [Original architecture-direction PDF](hardcaml_asic_architecture_direction.pdf):
  historical snapshot, not updated with the reconciled Markdown decisions.
- [Original concept note](hardcaml_asic_concept_note.md): project motivation and
  exploratory scope. Its status section points out decisions superseded by the
  architecture plan.
- [Original concept-note PDF](hardcaml_asic_concept_note.pdf): historical snapshot;
  it is not updated with the current architecture decisions.

Architecture decisions were accepted on 2026-09-16. API examples in the plan are
sketches, not a claim that the corresponding modules are implemented. Resource
behavior is governed by its contract; current architecture and milestone order
are governed by the architecture plan. The library phase plan breaks that first
milestone into implementation tasks and tracks completion evidence.

The shared direction is one initial package, separate harness/technology/flow
selection, context-registered resources with explicit implementation policy, and
an immutable build followed by separate execution/results. The first path uses
behavioral and explicitly selected flop memory with TT/LibreLane. Physical SRAM
and commercial adapters have separate later gates. Adapter-specific extensions
and report context preserve future flexibility without requiring industrial EDA
features in the first milestone.

Related consumer plans in this workspace:

- [Protocol emulator](../../scaf/docs/construction-plan.md) and
  [phase plan](../../scaf/docs/phase_plan.md): P0.6/P0.7 adopt the library;
  P3 owns memory consumer logic; P5.1a tracks the SRAM capability investigation.
- [Workbench architecture](../../workbench/docs/hardcaml_workbench_architecture.md):
  optional project-driver, supervised-job, and artifact integration. Neither a
  Workbench UI nor commercial EDA support is required for the first ASIC path.
