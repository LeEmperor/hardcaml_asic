(** Synchronous schema-2 writer. Interoperable nonblocking flock ownership;
    immutable atomic no-replace records, no fsync/recovery or inferred completion.
    Retains reduced state and one chain head, not the event history. Caller owns
    stable local parent directories. Close is idempotent and never writes events. *)
type t
exception Busy

(** [request_for_allocation], when supplied, constructs request metadata using
    the actual reserved directory/stream ID before the immutable allocated event.
    It supplies metadata only, never execution authority. *)
val create : ?wall_clock:(unit -> float) -> ?clock:(unit -> float)
   -> ?request_for_allocation:(directory:string -> attempt_id:string -> Identity_json.t)
  -> root:string -> workspace:string -> checkpoint_store:string
  -> request:Identity_json.t -> unit -> t
val directory : t -> string
val stream_id : t -> string
val preflight_path : t -> string
val state : t -> Observation.state
val close : t -> unit

(** Validate lifecycle before publication; update state only after successful
    promotion. Any append failure poisons the writer: no retry/fake outcome. *)
val append : t -> name:string -> Identity_json.t -> unit

val planned : t -> Execution_plan.Stage_plan.t -> unit
val prepared : t -> runtime_record:string option -> unit
val lifecycle : t -> Runner.lifecycle -> Execution_plan.Action.t
  -> Runner.occurrence -> 'a Runner.publication option -> unit
val outcome : t -> status:Runner.status -> exit_code:int -> error:string option -> unit
val allocation_receipt : t -> Identity_json.t
