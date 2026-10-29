(** Immutable post-PNR STA observation; never a checkpoint. Historical schema 1 is
    Signoff-scoped; schema 2 is Timing-scoped and may bind an immutable running execution
    prefix. [load] resolves that prefix only after checking the current execution's
    attempt, plan and exact Timing occurrence/publication. *)
val path : string -> string

val publish : execution:string -> transport_records:(string * string) list -> unit
val load : execution:string -> execution_raw:string -> Identity_json.t option
val validate_sources : Identity_json.t -> unit
val load_file : ?expected_record:Identity_json.t -> string -> Identity_json.t option

(** Shared bounded LibreLane Step completion-duration grammar; no filesystem or
    execution association is inferred by parsing a runtime string. *)
val native_runtime_seconds : string -> float
