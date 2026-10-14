open! Core
type t = Synthesis | Floorplan | Placement | Cts | Routing | Signoff
[@@deriving compare, equal, sexp_of]
val all : t list
val to_string : t -> string
val of_string : string -> t Or_error.t
