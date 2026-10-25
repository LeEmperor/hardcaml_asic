(** Retained preparation lifecycle. No tools, source reconstruction or liveness
    inference. Atomic local publication does not promise fsync durability. *)
type status = Running | Completed | Failed | Interrupted
type t = private
  { attempt_id : string
  ; status : status
  ; phase : string
  ; exit_code : int option
  ; raw : Identity_json.t
  }
val contract : string

(** Current workflow descriptor schema 2 has the actual phase order
    circuit -> snapshot -> source_after. Readers additionally accept only the
    exact historical descriptor schema 1 (which advertised the latter two in
    reverse order); the retained object is preserved, never normalized. Outer
    operation record schema remains 1. *)
val descriptor : unit -> Identity_json.t
val of_json : Identity_json.t -> (t, string) result
val read : string -> (t, string) result
val to_json : t -> Identity_json.t
val valid_identity : string -> bool
