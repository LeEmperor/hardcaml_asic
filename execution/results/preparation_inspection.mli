(** Read-only historical inspection. Verifies exact retained bytes with the
    library's strict decoder. Explicit current identity is a preparation identity,
    not a bundle/input/attempt identity. No probes or source reads. *)
type t
val inspect : ?current_identity:string -> string -> (t, string) result
val to_json : t -> Identity_json.t
val render : t -> string
