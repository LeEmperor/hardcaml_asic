(** Strict supported report units, lexically extracted outside Liberty comments
    and quoted text. Exactly one 1ns and one (1,pF) direct library attribute are
    required, with balanced braces/parentheses and one complete library scope. *)
val check : string -> (unit, string) result
