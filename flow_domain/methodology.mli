open! Core
module Backend_recipe : sig
  type t = Librelane_classic_v1 [@@deriving equal, sexp_of]
  val to_string : t -> string
  val of_string : string -> t Or_error.t
end
type input = Fresh [@@deriving equal, sexp_of]
type t
(** Endpoints are a nonempty subset of the fixed physical sequence. Each
    endpoint means the complete prefix starting at synthesis, never a DAG or
    continuation. Defaults must belong to the configurable set. *)
val create
  :  id:string
  -> label:string
  -> description:string
  -> backend_recipe:Backend_recipe.t
  -> endpoints:Stage_id.t list
  -> configurable:Parameter.Key.t list
  -> defaults:Parameter.assignment list
  -> t Or_error.t
val id : t -> Selection.Id.t
val label : t -> string
val description : t -> string
val backend_recipe : t -> Backend_recipe.t
val endpoints : t -> Stage_id.t list
val configurable : t -> Parameter.Key.t list
val defaults : t -> Parameter.assignment list
val input : t -> input
val stages : t -> endpoint:Stage_id.t -> Stage_id.t list Or_error.t
