(** Native State codec, deliberately separate from identity/public JSON. View
    leaves are null, paths, lists or objects. The metrics object is validated for
    syntax but retained as original bytes, including Infinity, -Infinity, NaN,
    exponent overflow, signed zero and integer/float distinctions. No metric
    token is passed to Identity_json as a nonfinite number. Duplicate keys,
    invalid Unicode and excessive nesting are rejected as in the host reader. *)
type t
val parse : string -> (t, string) result
val views : t -> (string * Identity_json.t) list
val map_paths : t -> f:(string -> string) -> t
val serialize : t -> string
