open! Core

module Key : sig
  type t = Synth_strategy | Synth_abc_buffering [@@deriving compare, equal, sexp_of]
  val all : t list
  val to_string : t -> string
  val of_string : string -> t Or_error.t
end

module Strategy : sig
  type t = Area_0 | Area_1 | Area_2 | Area_3 | Delay_0 | Delay_1 | Delay_2 | Delay_3 | Delay_4
  [@@deriving compare, equal, sexp_of]
  val all : t list
  val to_string : t -> string
  val of_string : string -> t Or_error.t
end

type value = Strategy of Strategy.t | Bool of bool [@@deriving equal, sexp_of]
type value_type = Enum | Boolean [@@deriving equal, sexp_of]
type descriptor
val descriptors : descriptor list
val descriptor : Key.t -> descriptor
val key : descriptor -> Key.t
val value_type : descriptor -> value_type
val allowed_values : descriptor -> value list
(** Backend documentation defaults, NOT provider assignments or runtime evidence. *)
val backend_default : descriptor -> value
val units : descriptor -> string option
val meaning : descriptor -> string
val backend_consumer : descriptor -> string

type assignment [@@deriving equal, sexp_of]
val synth_strategy : Strategy.t -> assignment
val synth_abc_buffering : bool -> assignment
val assignment_key : assignment -> Key.t
val assignment_value : assignment -> value
(** Strict scalar boundary for future wire readers. No coercion, normalization,
    aliases, numeric booleans or arbitrary backend keys. *)
val of_string_value : key:string -> string -> assignment Or_error.t
val of_bool_value : key:string -> bool -> assignment Or_error.t
(** Numeric scalars (including 0/1) and null are rejected for both keys. This
    Core-only scalar input is not a wire schema; object/array handling belongs
    to the eventual decoder. *)
val of_scalar
  :  key:string
  -> [ `String of string | `Bool of bool | `Int of int | `Float of float | `Null ]
  -> assignment Or_error.t

(** Reject duplicates, then return canonical backend-key order. *)
val check_keys : Key.t list -> Key.t list Or_error.t
val check_assignments
  :  configurable:Key.t list
  -> assignment list
  -> assignment list Or_error.t

type origin = Methodology | Profile | Request [@@deriving equal, sexp_of]
type contribution
val assignment : contribution -> assignment
val origin : contribution -> origin
type resolved
val winning : resolved -> contribution
(** Oldest to newest; excludes the winner, even when values are equal. *)
val overridden : resolved -> contribution list
(** Only declared values are returned. An absent key remains runtime-unspecified;
    descriptor defaults are never materialized into this list. *)
val resolve
  :  configurable:Key.t list
  -> methodology:assignment list
  -> profile:assignment list
  -> request:assignment list
  -> resolved list Or_error.t
