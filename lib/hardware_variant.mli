open! Core

(** Bounded hardware declarations, independent of resource policy and flow profiles.
    A checked value and its digest assert declared configuration, not semantic use
    by a circuit, compiled-source consistency or a P6 source stamp. *)
module Value : sig
  type t = Int of int | Bool of bool | Enum of string
end

module Parameter : sig
  type kind =
    | Integer of { minimum : int; maximum : int }
    | Boolean
    | Enumeration of string list
  type t
  (** Inclusive integer bounds within +/-1000000000; enums have 1..64 unique
      members. Keys and enum members match [a-z][a-z0-9_.-]*, at most 128 bytes.
      Enum order is normalized. No defaults or cross-parameter logic. *)
  val create : key:string -> kind:kind -> t Or_error.t
  val key : t -> string
  val kind : t -> kind
end

module Schema : sig
  type t
  (** IDs follow the same rules as parameter keys. Requires 1..64 unique keys;
      descriptors normalize by key. Consumers own supported tuple validation. *)
  val create
    : design_id:string -> schema_id:string -> parameters:Parameter.t list
    -> t Or_error.t
  val design_id : t -> string
  val schema_id : t -> string
  val parameters : t -> Parameter.t list
end

type t
(** Exactly one correctly typed assignment per descriptor; no missing, unknown or
    duplicate keys. Returns an immutable value in canonical key order. *)
val create : schema:Schema.t -> assignments:(string * Value.t) list -> t Or_error.t
val schema : t -> Schema.t
val assignments : t -> (string * Value.t) list
val get_int : t -> key:string -> int Or_error.t
val get_bool : t -> key:string -> bool Or_error.t
val get_enum : t -> key:string -> string Or_error.t
val identity : t -> string
val to_yojson : t -> Yojson.Safe.t
(** Strict version-1 reader, including digest, complete assignments and duplicate
    object keys. Ordering normalizes before checking the declared digest. *)
val of_yojson : Yojson.Safe.t -> t Or_error.t
val to_string : t -> string
(** At most 128 KiB; rejects trailing input and JSON extensions. *)
val of_string : string -> t Or_error.t
val sexp_of_t : t -> Sexp.t
