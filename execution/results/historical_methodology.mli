(** Normalized historical delivery metadata; never reads an active catalog.
    [recorded] consumes evidence validated by the strict execution reader. *)
val not_recorded : Identity_json.t
val pending : Identity_json.t -> Identity_json.t
val recorded : Methodology_execution_record.t -> Identity_json.t
val human : ?verbose:bool -> Identity_json.t -> string
