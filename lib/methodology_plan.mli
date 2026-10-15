open! Core

(** Immutable version-1 resolved preparation evidence. Main owns its canonical algorithm
    (Plan_json); these identities are configuration/preview identities, not P6 source
    stamps, tool observations or execution attempt identities. *)
type t

val to_yojson : t -> Yojson.Safe.t
val to_string : t -> string
val of_yojson : Yojson.Safe.t -> t Or_error.t
val of_string : string -> t Or_error.t
val methodology : t -> Flow.Catalog.resolved
val effective_parameters : t -> Resolved_flow.Effective_parameter.t list
val project_name : t -> string
val bundle_identity : t -> string
val recipe : t -> Flow.Recipe.t
val methodology_hash : t -> string
val plan_identity : t -> string

(** Only accepts Project's inseparable checked render result, never an arbitrary
    resolution/bundle pair. Validates emitted configuration and manifest links. *)
val of_rendered : Project.Rendered.t -> t Or_error.t

type t_plan = t

module Prepared : sig
  type t

  val plan : t -> t_plan
  val bundle : t -> Bundle.t
end

(** Resolve catalog before elaboration, render the exact bundle ONCE in memory, derive the
    plan, and compare optional expected identity. On mismatch returns an error before
    publication or any tool probes. No workspace writes/EDA. Catalog files supplied via
    [catalog_inputs] enter Bundle's input inventory. Publish Prepared.bundle later,
    without rerendering. *)
val prepare
  :  ?inputs:Target.Inputs.t
  -> ?selection:Flow.Selection.t
  -> ?request:Flow.Parameter.assignment list
  -> ?include_simulation:bool
  -> ?catalog_inputs:string list
  -> ?expected_plan_identity:string
  -> catalog:Flow.Catalog.t
  -> endpoint:Flow.Stage.t
  -> Project.t
  -> source_root:string
  -> Prepared.t Or_error.t
