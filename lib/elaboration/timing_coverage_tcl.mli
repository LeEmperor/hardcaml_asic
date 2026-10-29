(** Retained native-state producer, not exhaustive path-effect coverage.
    The generated member is sourced only by an allocated native STA producer. *)
val contract : string
val profile : string
val path : string
val manifest : unit -> Yojson.Safe.t
val render : unit -> string
