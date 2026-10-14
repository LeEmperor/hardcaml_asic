# Project flow catalog and named methodology execution

**Status:** agreed design direction, not implemented. Recorded 2026-10-14.

**Next feature priority:** project-owned named methodologies and parameter profiles,
with a public interface suitable for Hardcaml Workbench's active-flow selection.
Arbitrary LibreLane operation rearrangement is not a prerequisite.

The [phase plan](../phase_plan.md#ocaml-first-flow-infrastructure) remains the
implementation queue. This document records the feature boundary, ownership,
proposed interfaces and acceptance criteria. The
[infrastructure refactor](../flow-infrastructure-refactor.md) and its
[implementation record](flow-infrastructure-progress.md) describe the foundation.

## 1. Motivation and priority

The provider now supports native execution, named physical stage boundaries,
checkpoints, observation, human reporting and separate finalization. The example
has exercised individual continuations and a fresh full flow with acceptance.

The next useful abstraction is a reusable answer to:

> When I run this project, which implementation methodology and configuration
> should execute?

Workbench needs to discover that answer, let the user select it, launch it and
present the resulting facts. It should not implement its own ASIC stage sequence,
parameter-merging rules, checkpoint policy or acceptance policy.

Named methodologies and parameter experiments are the immediate user priority.
Further modularization should establish the catalog, configuration-resolution and
execution contracts before expanding arbitrary step-level composition. The first
Workbench integration can target those contracts while stage internals evolve.

## 2. Concepts and identities

| Concept | Meaning |
| --- | --- |
| Project | Hardware declaration, target, clocks, constraints and resources |
| Flow definition | Named methodology: supported composition and implementation choices |
| Configuration profile | Named implementation settings associated with a flow |
| Active selection | Project-scoped reference to a flow ID and profile ID |
| Resolved execution plan | Validated concrete stages, effective settings and input requirements |
| Execution request | Selected inputs, endpoint, workspace options and explicit checkpoint if applicable |
| Execution | One attempt with its own identity, outcomes, artifacts and observation stream |

For example:

```text
Project: controlled_fifo
Active flow: standard
Active profile: balanced

Executions:
  A: standard / balanced, completed through synthesis
  B: standard / balanced, completed through signoff
  C: standard / cts_experiment, running
```

Changing the active selection affects future requests. It must not mutate a
running execution or reinterpret historical results. Stable machine IDs are
separate from display labels and descriptions. Renamed or removed selections
should produce explicit resolution errors rather than silently choosing a default.

Workspace paths, attempt IDs and the particular checkpoint selected for a launch
belong to the execution request, not to a reusable flow definition.

## 3. Ownership

| Owner | Responsibility |
| --- | --- |
| Consumer project | Declare available flows/profiles, their default selection, and project-specific methodology choices |
| `hardcaml_asic` | Provide typed definitions, resolve configuration, validate compatibility, execute and preserve authoritative evidence |
| Workbench | Display choices, remember the user's project-scoped active selection, launch/supervise requests and present progress/results |
| LibreLane and external tools | Retain their existing backend engine, operation implementations, native state/configuration semantics and physical checks |

Workbench stores references such as `{flow_id: standard, profile_id: balanced}`.
It must resolve them against the project's current catalog when preparing a new
request. The project supplies a default for callers without an explicit selection;
Workbench's current selection is not a second copy of the methodology.

The first integration should not need a Workbench daemon to define or execute a
flow. Terminal clients and Workbench use the same public project/provider boundary.
Workbench consumes machine payloads rather than parsing human reports or backend
logs to infer completion. Existing provider process/cleanup ownership and the
distinction between observation-reader lifetime and execution lifetime remain.

## 4. Authoring direction

Use ordinary consumer-owned OCaml modules, compiled with Dune, to declare flows
and profiles. Emit a versioned declarative specification for the installed
provider to resolve and execute. Do not dynamically load arbitrary `flow.ml`
files in the Python adapter.

A possible consumer layout is:

```text
asic/
  project.ml
  flows/
    standard.ml
    profiles.ml
```

Illustrative API only; these names are not delivered interfaces:

```ocaml
let flows =
  Flow.Catalog.create
    ~default:{ flow = "standard"; profile = "balanced" }
    [ standard_flow; quick_synthesis_flow ]
```

The intended path is:

```text
Project-owned OCaml declarations
  -> versioned flow specification
  -> provider resolution and validation
  -> concrete execution plan
  -> OCaml execution services
  -> focused Python adapter / external CLI
  -> unmodified LibreLane and physical tools
```

A bespoke `.flow` language, a generic plugin loader and arbitrary operation
substitution are not required for this first feature.

## 5. Public client contract

Establish four capabilities before starting substantial Workbench integration.
Exact command spelling, schema fields and OCaml module signatures remain to be
specified during implementation design.

### Discover

List available flow/profile IDs, display names, descriptions, the project default,
supported endpoints and execution capabilities. Discovery should not launch EDA
or require an installed physical toolchain merely to enumerate declarations.

### Describe

Explain the selected methodology, its stage sequence, backend implementations,
supported parameter types/units/meanings and profile assignments. Distinguish
project-owned constraints from configurable methodology choices.

This metadata should support a useful Workbench flow panel. It does not require
a universal automatic GUI form generator or exposure of every LibreLane variable.

### Resolve / preview

Combine project facts, the flow, a profile and any supported explicit overrides
into a validated plan. Show effective settings and their origins. Reject unknown
or incompatible choices before EDA execution.

Preview may need project elaboration or input inspection; it must not imply that
tools ran or that a retained checkpoint is runtime-ready. Static compatibility,
host inspection and execution-time readiness remain distinct facts.

### Run and inspect

Execute an explicitly selected methodology, preserving the resolved selection.
Return structured references for the execution, observation attempt/stream,
workspace and artifacts, so clients do not reconstruct paths or choose the newest
record. Allocate and announce the attempt early, as existing stages do.

Reuse existing inspection, watch and reporting mechanisms, extending their records
with flow/profile identity where needed. A frozen resolved plan or a checked
expected identity must prevent previewed settings from silently changing at launch.

Illustrative command shapes, **not currently runnable commands**:

```sh
project flow list --json
project flow describe standard --profile balanced --json
project flow plan standard --profile balanced --endpoint signoff --json
project flow run standard --profile balanced --endpoint signoff --json
```

The consumer owns the catalog entry point; the provider owns reusable semantics.
Workbench should call the configured project interface, not assume a particular
repository layout, Dune executable name or sibling provider checkout.

## 6. Parameter resolution and reproducibility

Keep separate:

- **Design/target facts:** generated RTL, ports, geometry, clocks, constraints and
  resource intent. Profiles cannot silently overwrite protected facts.
- **Methodology settings:** supported synthesis, placement, CTS and routing choices.
- **Execution options:** selected endpoint, tool roots, output locations, resource
  limits and explicit continuation input.

Define and validate precedence rather than using an opaque configuration merge.
A candidate order is backend defaults, flow defaults, profile assignments, then
supported explicit request overrides. Preserve the origin of each effective value.

For the first version, apply methodology settings before bundle publication.
Existing bundles already contain implementation settings; a profile must not mutate
a published bundle or merely change a label beside unchanged tool inputs.
Changes that affect those inputs must participate in their identity.

Retain, per execution:

- Selected flow/profile IDs and resolved definition data.
- Fully effective settings and their provenance.
- A content identity for the resolved methodology/plan.
- Input bundle identity and relevant execution options.

A profile name is not a reproducibility identity. Updating a preset must not change
the meaning of a past execution. This feature's plan/configuration identity also
does not, by itself, close the separate provider source-artifact stamping gates.

## 7. First milestone and acceptance criteria

**Milestone: project flow catalog and named methodology execution.**

Use `hardcaml_asic_example` as the independent consumer specimen:

1. Declare a default flow with at least two meaningful supported profiles.
2. Discover and describe both through versioned machine-readable interfaces,
   without launching EDA.
3. Preview concrete plans/settings and demonstrate that the profiles change the
   intended effective backend parameters, not just display labels.
4. Launch fresh executions through the existing provider runner. Save exact
   methodology/configuration identities and input references.
5. Use public observation and reporting interfaces to inspect those executions.
   Results remain identifiable after editing a profile or changing the active
   selection; no particular improvement in area/timing is assumed.
6. Reject unknown flow/profile IDs, invalid settings and protected-fact conflicts
   with actionable diagnostics.
7. Demonstrate a small headless client that performs
   **discover -> select -> preview -> launch -> observe -> report** using only
   the installed project/provider interfaces.

The headless client is the readiness test for Workbench's active-flow integration.
Workbench implementation itself is a subsequent consumer of that tested contract.
Preserve existing explicit endpoint commands and historical readers unless an
intentional interface migration is specified and documented.

## 8. Later capabilities

### Parameter-changing checkpoint branches

Initially run each profile as a fresh execution. Reusing a placement checkpoint
with changed CTS settings needs a separate compatibility contract:

```text
placement checkpoint
  -> CTS profile A -> routing -> signoff
  -> CTS profile B -> routing -> signoff
```

The provider must know which settings could affect checkpoint production, preserve
upstream lineage/evidence, and validate acceptance across inherited history.
Current exact-configuration continuation and fresh-six-stage finalization rules do
not establish that capability. Unknown backend overrides require conservative
reuse behavior until their consumers are classified.

### Finer operation composition

The existing stage/operation definitions and LibreLane mapping are a foundation.
Individually callable backend operations, substitutions, inserted analyses, and new
restart boundaries still need supported contracts and physical verification.

They can extend the flow-definition model later. Their implementation is not a gate
on named methodologies or Workbench's first active-flow integration. General DAG
scheduling, automatic caching and parameter sweeps are likewise separate scope.

## 9. Decisions still to specify

- Concrete OCaml catalog/profile APIs and versioned wire schemas.
- The project-facing discovery/preview/run command contract.
- The initial supported, typed parameter subset and default/profile precedence.
- How project resolution receives methodology settings before bundle emission.
- Canonical plan identity and preview-to-launch consistency handling.
- Workbench selection persistence, missing-selection UX and comparison presentation.

These are implementation-design questions within the agreed direction. The
priority remains **named, inspectable methodologies and fresh parameter experiments
as the bridge to Workbench**, followed by finer backend composition and validated
checkpoint reuse when needed.
