(** Validate optional identity-covered hardware metadata. Absence is historical;
    present null or malformed declarations are errors. No current schema lookup. *)
val validate : Evidence_json.t -> unit
