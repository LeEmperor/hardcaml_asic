# Reorganize `lib/` into qualified module groups

Status: planned, not started. Written 2026-10-14. Decisions revised and the tree
re-surveyed on 2026-10-15 at commit `936e82d`, after the named-flow feature
(`ecbcd57`) landed in `lib/`. That feature was the in-flight work this change
was waiting for, so the reorganization is no longer blocked on it.

This record is self-contained so a fresh session can pick it up. The
[2026-10-15 survey](#survey-2026-10-15) records what the tree looked like at
that point. Re-run the commands in [Re-survey before starting](#re-survey-before-starting)
if `lib/` has changed since then.

## Motivation

The number of files in `lib/` is not the problem. `hardcaml/src` is one flat
directory of 73 modules, and Jane Street's convention is that a directory marks
a library boundary rather than a browsing aid. What makes `lib/` hard to read is
structure:

1. **Name collisions.** `lib/flow.ml` (in `hardcaml_asic`) sits next to the
   `lib/flow/` directory, which is a different library
   (`hardcaml_asic.flow_domain`). `lib/timing.ml` and
   `lib/flow/analysis/timing.ml` are unrelated `Timing` modules.
   `flow_stage.ml` mostly re-exports `Hardcaml_asic_flow_domain.Stage_id`.
2. **Nesting points the wrong way.** `lib/flow/` and `lib/execution/` look like
   subfolders of `hardcaml_asic`, but each is its own library. The dependency
   order is `flow_domain` → `hardcaml_asic` → `execution`, so the parent
   directory depends on one child and the other child depends on the parent.
3. **Three conventions in one tree.** The top level is flat, `execution/` uses
   `(include_subdirs unqualified)`, and `flow/` uses `(include_subdirs qualified)`.
4. **No table of contents.** There is no hand-written `hardcaml_asic.ml`, so
   nothing tells a reader how the 25 top-level modules group.

## What the package delivers

The package ships three libraries and an executable. The consumer's library and
the CLI are connected through files on disk rather than through linking:

```text
consumer design repo (e.g. hardcaml_asic_example) — its own executable
  -> links Hardcaml_asic (Project, Tt_cmos5l, Pinout, Bundle, Flow, ...)
  -> writes a bundle directory (RTL + configuration + manifest)
  -> hardcaml-asic-flow (bin/flow_cli; links only unix and yojson)
  -> LibreLane -> physical implementation tools
```

- `hardcaml_asic.flow_domain` is a Core-only description of stages, operations,
  the LibreLane mapping and the named-flow catalog (`Catalog`, `Methodology`,
  `Profile`, `Selection`, `Parameter`). It deliberately has no hardware,
  project or execution dependency: `test/catalog_domain/` and
  `test/stage_domain_consumer.ml` link only it to prove that a client such as
  Workbench can read stage definitions and a project's flow catalog without
  `hardcaml`.
- `hardcaml_asic` is the hardware library consumers link.
- `hardcaml_asic.execution` is the native execution engine behind the CLI and
  the `bin/experimental_*` executables.

One opam package carries all of it so a consumer pinning one revision gets a
library and CLI that agree (see the comment in `flow/dune`).

## Decisions

| Question | Decision |
|---|---|
| Qualified or unqualified subdirectories for `hardcaml_asic` (2026-10-14) | **Qualified.** Subdirectories become real namespaces (`Hardcaml_asic.Resource.Id`). |
| How consumers reach modules afterwards (2026-10-14) | **Short aliases plus qualified groups.** A hand-written `lib/hardcaml_asic.ml` exposes the groups and also re-exports the consumer entry points at the top level, so consumer code does not change. |
| `hardcaml_asic.flow_domain` (revised 2026-10-15) | **Keep it a separate library.** It moves out of `lib/` to a repo-root `flow_domain/`. Its library name, `public_name` and internal layout are unchanged. This supersedes the 2026-10-14 decision to merge it into `hardcaml_asic`, whose rationale ("keeping it separate spares no one a dependency") stopped holding once the catalog moved into it and gained Core-only consumers. |
| Where `execution` lives (2026-10-14) | **Repo-root `execution/`**, a sibling of `lib/` and `bin/`. Its `public_name` stays `hardcaml_asic.execution` and its internal layout is unchanged. |
| `flow_domain`'s `stages/<stage>/` (2026-10-14) | **Keep as is**, including the small per-step files. |
| Rename `Flow.Operation` (`Synthesis \| Hardening`) to `Goal` (2026-10-15) | **No.** The rename was only needed to avoid a clash with `flow_domain`'s `Operation` after a merge. Without the merge, the curated `Flow` does not re-export the domain `Operation`, so `Flow.Operation` keeps its name and the example's `asic_test/resolution_test.ml` needs no edit. |
| `lib/flow.ml` becomes `lib/flow/config.ml` | **Yes.** It holds the project's flow selection: `t`, `librelane`, `validate`, `Operation`, `Librelane`, `Adapter`. |

Still open; settle at step 3:

- **Placement of the four modules added by the named-flow feature.** Proposed:
  all four join the `Flow` group. See [module mapping](#module-mapping).

## Constraints verified with dune 3.17

Both were tested in a scratch project, not in this repository.

1. **A library stanza is not allowed under a `(include_subdirs qualified)`
   directory.** dune reports: *"This stanza is not allowed in a sub-directory of
   directory with (include_subdirs qualified). Hint: add (include_subdirs no)"*.
   So `flow_domain` and `execution` cannot stay nested under a qualified `lib/`.
   The opt-out hint works, but it would keep the misleading nesting, and
   `lib/flow/` is also the natural directory for `hardcaml_asic`'s own `Flow`
   group.
2. **A file named after its directory becomes that group's interface module.**
   For example, `resource/resource.ml` becomes `Resource`, and it must re-export
   every member itself. The groups depend on each other (`Tt_cmos5l` uses
   `Flow`; `Bundle` uses `Target`), so such interface modules create dependency
   cycles. **Rule: no group directory contains a file with its own name.** That
   rules out `target/target.ml` and `flow/flow.ml`, which is why one group is
   called `platform/` and `flow.ml` becomes `flow/config.ml`. Without such
   files, dune generates pure alias modules and module-level dependencies
   resolve normally.

## Target layout

```text
flow_domain/                  library hardcaml_asic.flow_domain (moved from lib/flow/)
  stage_id, operation, registry, catalog, methodology, profile, selection,
  parameter, stages/, analysis/, backends/librelane/
lib/                          library hardcaml_asic, (include_subdirs qualified)
  dune
  hardcaml_asic.ml            curated public surface (see below)
  resource/
  platform/
  elaboration/
  flow/                       hardcaml_asic's Flow group, not the domain library
execution/                    library hardcaml_asic.execution (moved from lib/execution/)
bin/                          executables, unchanged
flow/                         Python CLI and runtime data, unchanged
```

The three libraries sit side by side in dependency order. Repo-root `flow/` is
already the Python CLI package, which is why the domain library is called
`flow_domain/` rather than reusing that name.

The groups come from the actual `ocamldep` graph of the top-level modules.

### Module mapping

| Today | New qualified path | Top-level alias in `hardcaml_asic.ml` |
|---|---|---|
| `Resource_id` | `Resource.Id` | — |
| `Resource_request` | `Resource.Request` | — |
| `Resource_policy` | `Resource.Policy` | `Resource_policy` (used by the example) |
| `Resource_record` | `Resource.Record` | — |
| `Selection` | `Resource.Selection` | — |
| `Single_port_ram` | `Resource.Single_port_ram` | `Single_port_ram` |
| `Target` | `Platform.Target` | `Target` |
| `Technology` | `Platform.Technology` | — |
| `Harness` | `Platform.Harness` | — |
| `Tt_cmos5l` | `Platform.Tt_cmos5l` | `Tt_cmos5l` |
| `Pinout` | `Platform.Pinout` | `Pinout` |
| `Clock` | `Platform.Clock` | `Clock` |
| `Timing` (`lib/timing.ml`) | `Platform.Timing` | `Timing` |
| `Project` | `Elaboration.Project` | `Project` |
| `Elaboration_context` | `Elaboration.Context` | — |
| `Elaboration_mode` | `Elaboration.Mode` | — |
| `Elaborated_project` | `Elaboration.Elaborated_project` | `Elaborated_project` |
| `Metadata` | `Elaboration.Metadata` | — |
| `Flow` (`lib/flow.ml`) | `Flow.Config` | merged into curated `Flow`, see below |
| `Flow_stage` | `Flow.Stage` | via curated `Flow` |
| `Flow_recipe` | `Flow.Recipe` | via curated `Flow` |
| `Resolved_flow` | `Flow.Resolved` | `Resolved_flow` (used by the example) |
| `Bundle` | `Flow.Bundle` | `Bundle` |
| `Plan_json` *(proposed)* | `Flow.Plan_json` | — |
| `Flow_spec` *(proposed)* | `Flow.Spec` | — |
| `Methodology_inventory` *(proposed)* | `Flow.Methodology_inventory` | — |
| `Methodology_plan` *(proposed)* | `Flow.Methodology_plan` | `Methodology_plan` (used by the example) |

Since the groups become namespaces, the `Resource_*`, `Elaboration_*` and
`Flow_*` prefixes would stutter, so they are dropped.

`Hardcaml_asic_flow_domain.*` names do not change. The curated `Flow` keeps
re-exporting `Catalog`, `Methodology`, `Profile`, `Selection` and `Parameter`
from it, as `lib/flow.ml` does today. It does not re-export `Stage_id`,
`Operation`, `Registry`, `Stages`, `Analysis` or `Backends`.

**Placement of the four named-flow modules (proposed).** `Plan_json` has no
intra-library dependencies and `Bundle` uses it. `Flow_spec` uses `Flow` and
`Plan_json`. `Methodology_inventory` uses `Plan_json`. `Methodology_plan` uses
`Project`, `Bundle`, `Elaborated_project`, `Resolved_flow`, `Flow`, `Flow_spec`,
`Methodology_inventory` and `Plan_json`. All four describe or serialize flow
plans, so they belong in `Flow`.

**Known cross-group dependencies.** These are acceptable with pure alias
namespaces. Note each in the dependent module's comment.

- `Platform.Tt_cmos5l` depends on `Flow.Config`, because the TT template
  supplies default LibreLane overrides. (`Tt_cmos5l` does not depend on
  `Target`.)
- `Elaboration.Project` depends on `Flow.Bundle`, `Flow.Config` and
  `Flow.Resolved`, while `Flow.Methodology_plan` depends on
  `Elaboration.Project`. So `Flow` and `Elaboration` depend on each other in
  both directions at group level. No module-level cycle exists.

### `lib/hardcaml_asic.ml`

Once this file exists, only what it re-exports is public. It must expose all
four groups, the aliases from the table, and everything `execution/`, `bin/`,
`test/` and `examples/` reference. Use `(** {1 ...} *)` sections, as
`hardcaml/src/hardcaml.ml` does. Sketch:

```ocaml
(** {1 Groups} *)

module Resource = Resource
module Platform = Platform
module Elaboration = Elaboration

(** Flow selection, stages, recipes, resolution, bundle emission and named-flow
    planning. Includes [Flow.Config] so [Flow.librelane], [Flow.validate],
    [Flow.t] and [Flow.Operation] keep working, and re-exports the catalog
    modules from [Hardcaml_asic_flow_domain]. *)
module Flow = struct
  include Flow
  include Flow.Config
  module Catalog = Hardcaml_asic_flow_domain.Catalog
  module Methodology = Hardcaml_asic_flow_domain.Methodology
  module Profile = Hardcaml_asic_flow_domain.Profile
  module Selection = Hardcaml_asic_flow_domain.Selection
  module Parameter = Hardcaml_asic_flow_domain.Parameter
end

(** {1 Consumer entry points} *)

module Project = Elaboration.Project
module Elaborated_project = Elaboration.Elaborated_project
module Target = Platform.Target
module Tt_cmos5l = Platform.Tt_cmos5l
module Pinout = Platform.Pinout
module Clock = Platform.Clock
module Timing = Platform.Timing
module Single_port_ram = Resource.Single_port_ram
module Resource_policy = Resource.Policy
module Resolved_flow = Flow.Resolved
module Bundle = Flow.Bundle
module Methodology_plan = Flow.Methodology_plan
```

Things to check while writing it:

- `include Flow` followed by `include Flow.Config` must not produce duplicate
  names. `Config` carries `t`, `librelane`, `validate`, `Operation`,
  `Librelane` and `Adapter`. The group's members are `Config`, `Stage`,
  `Recipe`, `Resolved`, `Bundle`, `Plan_json`, `Spec`, `Methodology_inventory`
  and `Methodology_plan`, so nothing clashes. The added catalog modules do not
  clash either: `Methodology` and `Methodology_inventory`/`Methodology_plan`
  are distinct names.
- Today `lib/flow.ml` both defines the configuration and re-exports `Stage`,
  `Recipe` and the catalog modules. After the move, `flow/config.ml` keeps only
  the configuration; the re-exports move into the curated `Flow` above.
- Inside the library, modules refer to groups through dune's generated alias
  module (`Flow.Config`, `Platform.Target`), not through the curated `Flow`.
  Internal callers of the old `Flow.t` and `Flow.Operation`
  (`elaborated_project`, `project`, `resolved_flow`, `tt_cmos5l`, `bundle`,
  `flow_spec`, `methodology_plan`) change to `Flow.Config.t` and
  `Flow.Config.Operation`.

## Consumer impact

Usage measured at `936e82d`:

- **`hardcaml_asic_example`** (separate repo, `~/devel/jane/hardcaml_asic_example`)
  uses `Flow.*` (58 references: `Catalog`, `Parameter`, `Selection`, `Stage`,
  `Profile`, `Methodology`, `Recipe`, `Operation`), `Tt_cmos5l`,
  `Methodology_plan` (in `bin/project.ml`), `Bundle`, `Timing`,
  `Resolved_flow` and `Pinout`. With the aliases above, **no edit is
  required**. Still rebuild it and follow the
  [consumer dependency workflow](consumer-dependency-workflow.md) to move its
  pin.
- **References inside this repo to modules that lose their top-level name.**
  These either get a qualified path or, if a name is wanted publicly, an alias:

  | File | Modules |
  |---|---|
  | `bin/experimental_stages.ml` | `Methodology_plan` |
  | `examples/memory_example.ml` | `Elaboration_mode`, `Resource_id`, `Selection`, `Technology` |
  | `examples/tt_bundle_example.ml` | `Technology` |
  | `lib/execution/backends/librelane/stage_preparation.ml(i)` | `Methodology_plan` |
  | `lib/execution/methodology_execution_record.ml(i)` | `Methodology_plan`, `Plan_json` |
  | `lib/execution/methodology_execution_service.ml(i)` | `Methodology_plan`, `Methodology_inventory` |
  | `lib/execution/results/finalization_service.ml` | `Methodology_plan` |
  | `lib/execution/results/historical_methodology.ml` | `Methodology_plan` |
  | `lib/execution/results/stage_execution_record.ml` | `Methodology_plan` |
  | `test/fixture.ml` | `Elaboration_context`, `Resource_id`, `Resource_record`, `Resource_request`, `Selection`, `Technology` |
  | `test/named_observation_race.ml` | `Methodology_plan` |
  | `test/plan_contract/consumer.ml` | `Flow_spec`, `Technology` |
  | `test/project_api_consumer.ml` | `Elaboration_context`, `Elaboration_mode`, `Technology` |
  | `test/stage_preparation_consumer.ml` | `Methodology_plan` |
  | `test/test_lifecycle.ml` | `Elaboration_context`, `Elaboration_mode`, `Resource_id`, `Resource_record` |
  | `test/test_resolved_flow.ml` | `Metadata`, `Technology` |
  | `test/test_selection.ml` | `Elaboration_mode`, `Resource_record`, `Selection`, `Technology` |
  | `test/test_single_port_ram.ml` | `Elaboration_mode`, `Resource_id`, `Resource_record`, `Resource_request`, `Selection`, `Technology` |
  | `test/test_target.ml` | `Technology` |

  The `Methodology_plan` alias covers the execution and `bin/` uses. The rest
  are mostly tests of internal modules and should use qualified paths
  (`Hardcaml_asic.Resource.Record`), not new aliases.
  `test/catalog_domain/catalog_domain_consumer.ml` uses the domain library's
  own `Selection` and is unaffected.
- **`Hardcaml_asic_flow_domain` references are unaffected.** The library name
  and installed library list do not change, so `execution/`, `test/dune`,
  `test/catalog_domain/`, `test/stage_domain_consumer.ml` and
  `test/check_stage_domain.py` need no edits for the move.
- **Source path strings.** No code, dune file or test hard-codes `lib/flow` or
  `lib/execution`. Only `README.md` (lines 153–154, the layout table) names
  them.
- **Docs** that name the old modules or paths include `README.md`,
  `docs/architecture.md`, `docs/phase_plan.md`,
  `docs/guides/ocaml-stage-recipes.md`, the `docs/guides/` flow pages, and §5 of
  [flow-infrastructure-refactor](../flow-infrastructure-refactor.md). §5's
  status note places stage domains under `lib/flow/` and execution under
  `lib/execution/`; update it to match this record. Dated records under
  `docs/development/` stay as historical text.

## Order of work

Work on a branch from a clean `main`, one commit per step. Run
`dune build -j 20` and `dune runtest -j 20 --force` after each step.

1. **Move `lib/execution/` to `execution/`.** Do a pure `git mv`. The dune file
   and `public_name` stay unchanged.
2. **Move `lib/flow/` to `flow_domain/`.** Do a pure `git mv`. The dune file,
   library name and `public_name` stay unchanged. After this step `lib/` holds
   only `hardcaml_asic`.
3. **Create the groups.** Switch `lib/dune` to `(include_subdirs qualified)`.
   Create `resource/`, `platform/`, `elaboration/` and `flow/` with the renames
   from the mapping table: `flow.ml` to `flow/config.ml` (moving its
   `Stage`/`Recipe`/catalog re-exports out, see above), `flow_stage` to
   `flow/stage`, `flow_recipe` to `flow/recipe`, `resolved_flow` to
   `flow/resolved`, `bundle` to `flow/bundle`, `flow_spec` to `flow/spec`, and
   `plan_json`, `methodology_inventory` and `methodology_plan` into `flow/`.
   Update internal references.
4. **Add `lib/hardcaml_asic.ml`** with the groups and aliases. Add a `.mli` if
   the surface should be documented separately.
5. **Update `execution/`, `test/`, `bin/` and `examples/`** using the table in
   [Consumer impact](#consumer-impact). Then rebuild `hardcaml_asic_example`
   against the new revision.
6. **Update the docs** listed above, and add this record to the
   `docs/README.md` index under completed work.

Steps 3 and 4 cannot build separately in practice: once `lib/` is qualified,
consumers see only the generated group aliases until `hardcaml_asic.ml` exists.
Either combine them in one commit, or add `hardcaml_asic.ml` in step 3 and
treat step 4 as its documentation pass.

Prefer `git mv` for every move so `git log --follow` keeps history. Do not
reformat files while moving them; keep content diffs separate from renames.

Missing `.mli` files are a separate follow-up, not part of this change. These
modules have none: `flow.ml`, `selection`, `resource_record`, `pinout`,
`clock`, `timing`, `metadata`, `harness`, `elaboration_mode`, and in
`flow_domain`, `analysis/timing` and `stages/*`.

## Survey (2026-10-15)

Taken at `936e82d` on `main`. `lib/` was unchanged by the docs-only commits
after `ecbcd57`.

**Baseline.** `dune build -j 20` and `dune runtest -j 20 --force` both exited 0
(the test run took about 9 minutes). Uncommitted documentation edits were
present in the working tree; no source or dune file was modified.

**Size.** `lib/` without `execution/` is 8,467 lines; `lib/execution/` is
7,220 lines. There are 85 `.ml` files in all.

**Libraries and `include_subdirs` modes.** Unchanged from 2026-10-14:
`lib/dune` (flat, depends on `hardcaml_asic.flow_domain`), `lib/flow/dune`
(qualified, `core` only), `lib/execution/dune` (unqualified, C stubs).

**`flow_domain` contents.** `stage_id`, `operation`, `registry`, `catalog`,
`methodology`, `profile`, `selection`, `parameter`, `analysis/timing`,
`backends/librelane/mapping`, and `stages/{synthesis,floorplan,placement,cts,routing,signoff}/recipe`
plus placement's `global_placement`, `design_repair` and `detailed_placement`.
The catalog, methodology, profile, selection and parameter modules were added by
`ecbcd57`.

**Top-level dependency graph** (intra-library only; `[fd]` marks a direct
`Hardcaml_asic_flow_domain` reference):

```text
bundle:                Elaborated_project Pinout Plan_json Resolved_flow Resource_id
                       Resource_policy Resource_record Resource_request Selection
                       Target Technology
clock:
elaborated_project:    Clock Elaboration_mode Flow Metadata Pinout Resource_id
                       Resource_record Target Timing
elaboration_context:   Elaboration_mode Resource_id Resource_policy Resource_record
                       Resource_request Selection Technology
elaboration_mode:
flow:                  Flow_recipe Flow_stage  [fd]
flow_recipe:           Flow_stage
flow_spec:             Flow Plan_json
flow_stage:            [fd]
harness:
metadata:
methodology_inventory: Plan_json
methodology_plan:      Bundle Elaborated_project Flow Flow_spec Methodology_inventory
                       Plan_json Project Resolved_flow
pinout:
plan_json:
project:               Bundle Clock Elaboration_context Flow Metadata Pinout
                       Resolved_flow Resource_policy Target Timing
resolved_flow:         Clock Elaborated_project Elaboration_mode Flow Resource_record
                       Selection Target Technology
resource_id:
resource_policy:       Resource_id
resource_record:       Resource_id Resource_policy Resource_request Selection Technology
resource_request:      Resource_id
selection:             Resource_policy Resource_request Technology
single_port_ram:       Elaboration_context Resource_id Resource_request
target:                Harness Technology
technology:            Resource_request
timing:
tt_cmos5l:             Flow
```

**Files referencing the `flow_domain` library.** Source: `lib/dune`,
`lib/flow/dune`, `lib/flow.ml`, `lib/flow_stage.ml(i)`,
`lib/execution/execution_plan.ml` and `classic_contract.ml`,
`segment_service.ml`, `stage_preparation.ml` under
`lib/execution/backends/librelane/`. Tests: `test/dune`,
`test/stage_domain_consumer.ml`, `test/check_stage_domain.py`,
`test/catalog_domain/{dune,catalog_domain_consumer.ml}`. Docs: `README.md`,
`docs/architecture.md`, `docs/phase_plan.md`,
`docs/guides/ocaml-stage-recipes.md` and dated development records. None of
these change under the revised plan except the docs that name source paths.

## Re-survey before starting

If `lib/` has changed since the survey above, regenerate the inventory and
dependency graph and reconcile them with the mapping table. Place any new
top-level module in a group by its dependencies.

```sh
# Modules and line counts
find lib -name '*.ml' -o -name '*.mli' | sort | xargs wc -l

# Intra-library dependencies of the top-level hardcaml_asic modules
cd lib && for f in *.ml; do m=$(basename $f .ml); l=""
  for d in $(ocamldep -modules $f | cut -d: -f2); do
    lc=$(echo $d | sed 's/./\L&/'); [ -f "$lc.ml" ] && l="$l $d"; done
  echo "$m:$l"; done; cd ..

# Library stanzas and include_subdirs modes
find lib -name dune -exec sh -c 'echo "== $1"; cat "$1"' _ {} \;

# Everything referencing the flow_domain library
grep -rlE 'Hardcaml_asic_flow_domain|hardcaml_asic\.flow_domain' --exclude-dir=_build .

# Source path strings that a move would break
grep -rnE 'lib/(flow|execution)\b' --exclude-dir=_build --exclude-dir=docs --exclude-dir=evidence .

# Consumer usage in the example repo
grep -rhoE '\b(Project|Elaborated_project|Tt_cmos5l|Pinout|Bundle|Clock|Timing|Resource_[a-z]+|Resolved_flow|Methodology_[a-z]+|Flow_spec|Plan_json|Flow)\.[A-Za-z_]+' \
  --include=*.ml --include=*.mli ../hardcaml_asic_example | sort | uniq -c
```

Also confirm that the baseline `dune build` and `dune runtest` pass on `main`
before the first move, so later failures are attributable to the refactor.
