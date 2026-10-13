open! Core

(** Validated schema-3 recipes for the opt-in provider [stages --plan] command.
    Pure declarations: no I/O, process invocation, checkpoint validation or tool
    probing. Independent of [Project.create], bundle identity and run identity. *)
type t [@@deriving sexp_of]

(** Fresh sequences start at synthesis. Resumed sequences start immediately after
    [initial_boundary]. Empty, skipped, repeated and reordered stages fail here.
    The provider must also validate the supplied checkpoint's actual source and
    compatibility before execution. *)
val create : ?initial_boundary:Flow_stage.t -> Flow_stage.t list -> t Or_error.t

(** Expand all stages through the endpoint, optionally from an explicit source.
    A terminal source or an endpoint at/before the source fails. *)
val through : ?initial_boundary:Flow_stage.t -> Flow_stage.t -> t Or_error.t

(** Join validated recipes when the second recipe's source is exactly the first
    recipe's endpoint. This composes declarations, not executions or historical
    checkpoint sets; finalization of resumed attempts is a separate contract. *)
val compose : t -> t -> t Or_error.t

val stages : t -> Flow_stage.t list
val initial_boundary : t -> Flow_stage.t option
val endpoint : t -> Flow_stage.t

module Input : sig
  type t = Bundle | Checkpoint of Flow_stage.t [@@deriving equal, sexp_of]
end

type declaration =
  { stage : Flow_stage.t
  ; input : Input.t
  ; output_checkpoint : Flow_stage.t
  }
[@@deriving sexp_of]

(** First external input and ordered per-stage handoffs. Checkpoint inputs are
    boundary requirements, not proof that any path is a ready checkpoint. All
    stages also require the runtime/closure conditions in [Stage.capability]. *)
val required_input : t -> Input.t
val declarations : t -> declaration list

(** Exactly [schema_version], [stages], [initial_boundary]; no backend settings,
    runtime bindings, paths, or run IDs. [to_string] renders strict JSON suitable
    for writing to the file passed as [--plan]. *)
val to_yojson : t -> Yojson.Safe.t
val to_string : t -> string
