# Reorganize `lib/` into qualified module groups

Status: planned, not started. Written 2026-10-14. Deferred until the feature
being implemented concurrently in `lib/` is committed, because this change
touches nearly every file under `lib/` and would conflict with in-flight work.

This record is self-contained so a fresh session can pick it up. Facts about the
tree were true at commit `0d04bae`; re-verify them with the commands in
[Re-survey before starting](#re-survey-before-starting) because the concurrent
feature will have moved things.

## Motivation

The number of files in `lib/` is not the problem. The whole tree is about 57
modules and 11k lines. For comparison, `hardcaml/src` is one flat directory of
73 modules, and Jane Street's convention is that a directory marks a library
boundary rather than a browsing aid. What makes `lib/` hard to read is
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
   nothing tells a reader how the 21 top-level modules group.

## What the package delivers

The package ships both a library and an executable, connected through files on
disk rather than through linking:

```text
consumer design repo (e.g. hardcaml_asic_example) — its own executable
  -> links Hardcaml_asic (Project, Tt_cmos5l, Pinout, Bundle, ...)
  -> writes a bundle directory (RTL + configuration + manifest)
  -> hardcaml-asic-flow (bin/flow_cli; links only unix and yojson)
  -> LibreLane -> physical implementation tools
```

`hardcaml_asic.execution` is a second library, used today only by the
`bin/experimental_*` executables; it is the engine the CLI is moving onto. One
opam package carries all of it so a consumer pinning one revision gets a library
and CLI that agree (see the comment in `flow/dune`).

## Decisions (made 2026-10-14)

| Question | Decision |
|---|---|
| Qualified or unqualified subdirectories for `hardcaml_asic` | **Qualified.** Subdirectories become real namespaces (`Hardcaml_asic.Resource.Id`). |
| How consumers reach modules afterwards | **Short aliases plus qualified groups.** A hand-written `lib/hardcaml_asic.ml` exposes the four groups and also re-exports the consumer entry points at the top level, so consumer code barely changes. |
| `hardcaml_asic.flow_domain` | **Merge into `hardcaml_asic`** as the `Flow` group. It depends only on `core`, and `hardcaml_asic` already depends on it, so keeping it separate spares no one a dependency. |
| Where `execution` lives | **Repo-root `execution/`**, a sibling of `lib/` and `bin/`. Its `public_name` stays `hardcaml_asic.execution` and its internal layout is unchanged. |
| `lib/flow/stages/<stage>/` | **Keep as is**, including the small per-step files. |

Still open; settle these when the work starts:

- **The new name for `Flow.Operation` (`Synthesis | Hardening`).** It clashes
  with `flow_domain`'s `Operation` (stage-step descriptions) after the merge.
  Proposed: `Flow.Config.Goal`, since it means "how far to take the design".
- **`Flow.Config` as the new name for `lib/flow.ml`.** It holds the project's
  flow selection: `t`, `librelane`, `validate`, `Librelane`, `Adapter`.

## Constraints verified with dune 3.17

Both were tested in a scratch project, not in this repository.

1. **A library stanza is not allowed under a `(include_subdirs qualified)`
   directory.** dune reports: *"This stanza is not allowed in a sub-directory of
   directory with (include_subdirs qualified). Hint: add (include_subdirs no)"*.
   So `flow_domain` and `execution` cannot stay nested under a qualified `lib/`.
   The opt-out hint works, but it would keep the misleading nesting.
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
lib/                          library hardcaml_asic, (include_subdirs qualified)
  dune
  hardcaml_asic.ml            curated public surface (see below)
  resource/
  platform/
  elaboration/
  flow/
    stages/ analysis/ backends/librelane/   (moved from today's lib/flow/)
execution/                    library hardcaml_asic.execution (moved from lib/execution/)
bin/                          executables, unchanged
```

The groups come from the actual `ocamldep` graph of the 21 top-level modules.

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
| `Flow.Operation` (inside `flow.ml`) | `Flow.Config.Goal` (name open) | — |
| `Flow_stage` | `Flow.Stage` | via curated `Flow` |
| `Flow_recipe` | `Flow.Recipe` | via curated `Flow` |
| `Resolved_flow` | `Flow.Resolved` | `Resolved_flow` (used by the example) |
| `Bundle` | `Flow.Bundle` | `Bundle` |
| `Hardcaml_asic_flow_domain.Stage_id` | `Flow.Stage_id` | — |
| `Hardcaml_asic_flow_domain.Operation` | `Flow.Operation` | — |
| `Hardcaml_asic_flow_domain.Registry` | `Flow.Registry` | — |
| `Hardcaml_asic_flow_domain.Stages.*` | `Flow.Stages.*` | — |
| `Hardcaml_asic_flow_domain.Analysis.Timing` | `Flow.Analysis.Timing` | — |
| `Hardcaml_asic_flow_domain.Backends.Librelane.Mapping` | `Flow.Backends.Librelane.Mapping` | — |

Since the groups become namespaces, the `Resource_*` and `Elaboration_*`
prefixes would stutter, so they are dropped.

**Keep `Flow.Stage_id` and `Flow.Stage` as two modules.** Do not fold them
together. `Flow_stage.capability` calls `Registry.restart_targets` and
`Backends.Librelane.Mapping`, and both of those depend on `Stage_id`. A merged
module would form a cycle. `Flow.Stage` keeps its current role: it re-exports
the `Stage_id.t` constructors and adds `capability`.

**Known cross-group dependency:** `Platform.Tt_cmos5l` depends on
`Flow.Config`, because the TT template supplies default LibreLane overrides.
This is acceptable with pure alias namespaces. Note it in the module's comment.

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

(** Flow selection, stages, recipes, resolution and bundle emission. Includes
    [Flow.Config] so [Flow.librelane], [Flow.validate] and [Flow.t] keep working. *)
module Flow = struct
  include Flow
  include Flow.Config
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
```

Two things to check while writing it:

- `include Flow` followed by `include Flow.Config` must not produce
  duplicate names. Today `Config` would carry `Librelane`, `Adapter`, `Goal`,
  `t`, `librelane` and `validate`; the group's `Librelane` sits under
  `Backends`, so the names should not clash. The renamed `Goal` is what removes
  the `Operation` clash.
- Inside the library, modules refer to groups through dune's generated alias
  module (`Flow.Config`, `Platform.Target`), not through the curated `Flow`.
  Internal callers of the old `Flow.t` and `Flow.Operation`
  (`elaborated_project`, `project`, `resolved_flow`, `tt_cmos5l`, `bundle`)
  change to `Flow.Config.t` and `Flow.Config.Goal`.

## Consumer impact

Usage measured at `0d04bae`:

- **`hardcaml_asic_example`** (separate repo, `~/devel/jane/hardcaml_asic_example`)
  uses `Project`, `Elaborated_project`, `Tt_cmos5l`, `Pinout`, `Bundle`,
  `Clock`, `Timing`, `Resource_policy`, `Resolved_flow`, `Flow.librelane`,
  `Flow.Stage`, `Flow.Recipe` and `Flow.Operation`. With the aliases above, the
  only required edit is `asic_test/resolution_test.ml:31`, which uses
  `Flow.Operation.equal … Hardening`; that becomes the `Goal` name. Follow
  [consumer dependency workflow](consumer-dependency-workflow.md) to move the
  example's pin.
- **`Hardcaml_asic_flow_domain` references** that must change to
  `Hardcaml_asic.Flow.*`: `lib/flow_stage.ml(i)`, `lib/dune`,
  `lib/execution/execution_plan.ml`, and `classic_contract.ml`,
  `segment_service.ml` and `stage_preparation.ml` under
  `lib/execution/backends/librelane/`. Tests: `test/stage_domain_consumer.ml`,
  `test/check_stage_domain.py` and `test/dune`.
- **The installed library list changes.** `hardcaml_asic.flow_domain`
  disappears from the install. Check any installed-prefix or consumer-linkage
  test that asserts the library list or META (grep `test/` for `flow_domain`
  and `test_installed_prefix`).
- **Docs** that name the old modules or paths include `docs/architecture.md`,
  `docs/phase_plan.md`, `docs/guides/ocaml-stage-recipes.md`, the
  `docs/guides/` flow pages, and §5 of
  [flow-infrastructure-refactor](../flow-infrastructure-refactor.md). §5's
  layout sketch places `execution/` inside `lib/`; update it to match this
  record. Dated records under `docs/development/` stay as historical text.

## Order of work

Work on a branch from a clean `main`, one commit per step. Run `dune build` and
`dune runtest` after each step.

1. **Move `lib/execution/` to `execution/`.** Do a pure `git mv`. The dune file
   and `public_name` stay unchanged. Fix any relative paths in `test/dune` or
   `flow/dune` that point into it.
2. **Merge `flow_domain` into `hardcaml_asic`.** `git mv lib/flow/*` into the
   new `lib/flow/` group (`stage_id`, `operation`, `registry`, `stages/`,
   `analysis/`, `backends/`). Delete `lib/flow/dune`. Switch `lib/dune` to
   `(include_subdirs qualified)` and drop the `hardcaml_asic.flow_domain`
   dependency. Move `flow.ml` to `flow/config.ml` (renaming `Operation` to
   `Goal`), `flow_stage` to `flow/stage`, `flow_recipe` to `flow/recipe`,
   `resolved_flow` to `flow/resolved`, and `bundle` to `flow/bundle`. Update
   `execution/` and the tests to `Hardcaml_asic.Flow.*`.
3. **Create `resource/`, `platform/` and `elaboration/`** with the renames from
   the mapping table, and update internal references.
4. **Add `lib/hardcaml_asic.ml`** with the groups and aliases. Add a `.mli` if
   the surface should be documented separately.
5. **Update `test/`, `bin/` and `examples/`.** Then update and build
   `hardcaml_asic_example`.
6. **Update the docs** listed above, and add this record to the `docs/README.md`
   index under completed work.

Prefer `git mv` for every move so `git log --follow` keeps history. Do not
reformat files while moving them; keep content diffs separate from renames.

Missing `.mli` files are a separate follow-up, not part of this change. These
modules have none: `flow.ml`, `selection`, `resource_record`, `pinout`,
`clock`, `timing`, `metadata`, `harness`, `elaboration_mode`, and
`flow/stages/*`.

## Re-survey before starting

The concurrent feature will have changed `lib/`. Before step 1, regenerate the
inventory and dependency graph and reconcile them with the mapping table. Place
any new top-level module in a group by its dependencies.

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

# Everything still referencing the flow_domain library
grep -rlE 'Hardcaml_asic_flow_domain|hardcaml_asic\.flow_domain' --exclude-dir=_build .

# Consumer usage in the example repo
grep -rhoE '\b(Project|Elaborated_project|Tt_cmos5l|Pinout|Bundle|Clock|Timing|Resource_[a-z]+|Resolved_flow|Flow)\.[A-Za-z_]+' \
  --include=*.ml --include=*.mli ../hardcaml_asic_example | sort | uniq -c
```

Also confirm that the baseline `dune build` and `dune runtest` pass on `main`
before the first move, so later failures are attributable to the refactor.
