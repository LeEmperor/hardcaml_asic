(** Bounded lexical Liberty time-unit evidence, excluding comments and quoted text.
    Entries are one-based line, unit, original line. *)
val parse : string -> (int * string * string) list * string list
