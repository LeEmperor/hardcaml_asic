open! Core

(** Main-library finite JSON contract, independent of execution's Python-compatible
    Identity_json. Objects sort by bytewise key; arrays retain sequence; scalar spellings
    are Yojson.Safe compact JSON (including finite IEEE double spelling). Duplicate object
    keys, nonfinite numbers and Yojson extensions are errors. Consumers must use this
    implementation, not a foreign JSON encoder. *)
val canonical : Yojson.Safe.t -> string Or_error.t

val identity : contract:string -> Yojson.Safe.t -> string Or_error.t
val sha256 : string -> string

(** Checked wire-reader primitives. Errors raise internally and are captured by [decode];
    these never perform I/O. *)
val decode : (unit -> 'a) -> 'a Or_error.t

val checked : 'a Or_error.t -> 'a
val fail : string -> 'a
val validate : Yojson.Safe.t -> unit
val object_ : Yojson.Safe.t -> fields:string list -> unit
val get : Yojson.Safe.t -> string -> Yojson.Safe.t
val string : Yojson.Safe.t -> string
val array : Yojson.Safe.t -> Yojson.Safe.t list
val envelope : Yojson.Safe.t -> contract:string -> fields:string list -> unit
val equal : Yojson.Safe.t -> Yojson.Safe.t -> bool

(** Standard JSON grammar admission before Yojson decoding: no comments,
    extensions, trailing input, malformed UTF-8/surrogates or nesting over 256.
    Does not canonicalize or change any existing identity algorithm. *)
val parse : (Yojson.Safe.t -> 'a Or_error.t) -> string -> 'a Or_error.t
