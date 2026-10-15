(** Coarse Classic attempt record. No journal or acceptance is implied. *)
type status = Starting | Running | Completed | Failed | Interrupted
type t
val create : Result_store.allocation -> bundle:string -> build_identity:Identity_json.t
  -> manifest_sha256:string -> stage:Execution_plan.Coarse.endpoint -> t
val set : t -> string -> Identity_json.t -> unit
val status : t -> status -> unit
val command : t -> string list -> unit
val finish : t -> status -> ended_at:string -> ?error:string -> ?interrupted_by:string -> unit -> unit
val to_json : t -> Identity_json.t
val status_name : status -> string
type outcome = private
  { run_id : string; run_dir : string; run_record : string; status : status; exit_code : int }
val outcome : Result_store.allocation -> status:status -> exit_code:int -> outcome
val outcome_json : outcome -> Identity_json.t
