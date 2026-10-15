(** Host-only stage journal validation. No backend imports, writes, repair,
    completion inference on detach, or live watch loop. Schema 1 has no timing.
    Checkpoint references are recorded facts, not filesystem validation. *)
type schema = Schema_1 | Schema_2
type status = Unreached | Running | Completed | Failed | Interrupted
type phase = Preparing | Executing | Finished
type error_code = Invalid_record | Reset_required
type error = { code : error_code; detail : string }
val error_code_name : error_code -> string
val error_json : error -> Identity_json.t
type timing = private { recorded_at : string; elapsed_seconds : Identity_json.t }
type occurrence = private
  { occurrence_id : string; action_key : string; status : status
  ; exit_code : string option; duration_seconds : Identity_json.t
  ; error : string option; raw : Identity_json.t }
type reference = private
  { boundary : Execution_plan.Stage.t; path : string; identity : string
  ; raw : Identity_json.t }
type outcome = private { status : status; exit_code : string; error : string option }
type allocation = private
  { request : Identity_json.t; workspace : string; checkpoint_store : string
  ; lock_path : string; preflight_record : string }
type event = private
  | Allocated of allocation
  | Planned of Execution_plan.Stage_plan.t
  | Prepared of string option
  | Started of occurrence
  | Published of occurrence * reference
  | Finished_occurrence of occurrence * reference option
  | Outcome of outcome
type state = private
  { attempt_id : string; allocation : allocation; phase : phase
  ; plan : Execution_plan.Stage_plan.t option; occurrences : occurrence list
  ; artifacts : reference list; runtime_record : string option; outcome : outcome option }
type record = private
  { schema : schema; stream_id : string; sequence : int; previous_sha256 : string option
  ; sha256 : string; timing : timing option; event : event; raw : Identity_json.t }

(** Pure event decoding/transition APIs for the next writer. [reduce_event]
    checks the closed lifecycle grammar but does not attest to publication IO.
    Decode before any writer promotion; update writer state only after promotion. *)
val event_of_json : name:string -> Identity_json.t -> (event, error) result
val event_to_json : event -> string * Identity_json.t
val reduce_event : state option -> stream_id:string -> event -> (state, error) result
val state_json : state -> Identity_json.t

(** Immutable validated prefix. [append_record] checks exact schema, identity,
    chain, timing and transitions and returns a new prefix, never alters input. *)
type prefix
val empty : prefix
val append_record : prefix -> Identity_json.t -> (prefix, error) result
val records : prefix -> record list
val state : prefix -> state option
val cursor : prefix -> int
val snapshot : prefix -> writer_active:bool option -> (Identity_json.t, error) result
val updates : prefix -> stream_id:string -> after:int -> (Identity_json.t, error) result

(** Describes the shared persisted service contract, including the foreground
    watch protocol implemented by the installed observation command. *)
val describe : unit -> Identity_json.t
val writer_active : string -> bool option
val load : string -> (prefix, error) result

(** Adds [methodology] (historical-methodology v1) and [execution_request] delivery
    metadata outside the hashed prefix. Named evidence validates the exact retained
    preflight reference/snapshot and published checkpoint resolved values. Only
    named streams receive these fields; legacy output retains its exact shape,
    with absent methodology meaning [not_recorded] to clients. Named streams expose
    [execution_file]: null until a persisted readable record exists, otherwise its
    exact writer-owned path after strict attempt/recipe/reference validation.
    No current catalog/runtime probes. *)
val inspect : string -> (Identity_json.t, error) result
module For_testing : sig
  (** Synchronization point after the first named report read, before rechecking
      writer/commit state. No production environment-variable hook. *)
  val inspect : after_preflight_read:(unit -> unit) -> string -> (Identity_json.t, error) result
end
val read_updates : string -> stream_id:string -> after:int -> (Identity_json.t, error) result

(** Local immutable-prefix metadata cache. Idle refreshes do not reparse records.
    Metadata covers dev/inode/size and nanosecond mtime/ctime, not protection from
    a hostile filesystem owner. A failed reader is poisoned and must be discarded.
    Reconnect binds stream and cursor together. [poll] drains again after observing
    an inactive/unknown writer, then returns updates and the shared status shape.
    No signal handlers or foreground watch/delivery policy are installed. *)
module Reader : sig
  type t
  val create : ?stream_id:string -> ?after:int -> string -> (t, error) result
  val prefix : t -> prefix
  val poll : t -> ((Identity_json.t * Identity_json.t), error) result
end
