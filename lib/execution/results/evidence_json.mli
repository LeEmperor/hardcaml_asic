(** Python evidence JSON, deliberately separate from strict identity JSON.
    Accepts NaN, +/-Infinity and overflow exponents; integers remain arbitrary
    precision, booleans remain booleans, duplicate object keys use the last value.
    Original bytes are retained; nesting is bounded at 256. Never use this decoder/writer for identities,
    manifests to be hashed, or protocol validation. *)
type t = Yojson.Safe.t
type document
(* [reject_duplicates] defaults to false, preserving legacy evidence semantics;
    supplementary evidence can opt into rejection after decoding escaped keys. *)
val parse : ?reject_duplicates:bool -> string -> (document, string) result
val read : string -> document
val value : document -> t
val raw_bytes : document -> string
val record_bytes : t -> string
val repr : t -> string
