open! Core

(** Stable IDs use [[a-z][a-z0-9_-]*]; labels are separate display text. *)
module Id : sig
  type t [@@deriving compare, equal, sexp_of]
  val create : string -> t Or_error.t
  val to_string : t -> string
end

type t

(** An absent flow and profile requests the catalog default. A profile alone is
    invalid. An explicit flow without a profile requests that flow's default. *)
val create : ?flow:string -> ?profile:string -> unit -> t Or_error.t
val default : t
val flow : t -> Id.t option
val profile : t -> Id.t option
