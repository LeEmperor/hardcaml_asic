(** Immutable schema-1 historical snapshot. Reading never probes tools or reads
    referenced artifacts, and does not assert current readiness. *)
type status = Running | Completed | Failed | Interrupted
type acceptance = Not_evaluated | Pass | Fail
type t = private { attempt_id : string; status : status; acceptance : acceptance;
  exit_code : Z.t option; raw : Identity_json.t }
val contract : string
val of_json : Identity_json.t -> (t, string) result
val read : string -> (t, string) result
val to_json : t -> Identity_json.t
val render : directory:string -> t -> string
