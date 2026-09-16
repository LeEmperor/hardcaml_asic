(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "resource_id.mli" *)
(* Stable identity of one registered resource instance.

   An identity is the Hardcaml scope path at the point of registration plus the explicit
   resource name. It therefore matches the instance hierarchy of the elaborated design.

   Hardcaml mangles repeated instance labels within a scope in creation order ([foo],
   [foo_0], ...). An identity below such an instance is repeatable across elaborations of
   the same constructor, but it can change if instances are added or reordered. Give
   hierarchical instances that contain resources explicit, distinct [~instance] names. *)

open! Core

type t = private
  { path : string list (** Scope labels from the top, outermost first. *)
  ; name : string
  }
[@@deriving equal]

(** Lexicographic over [path @ [name]]. *)
val compare : t -> t -> int

(** Printed as [path/.../name]. *)
val sexp_of_t : t -> Sexp.t

val to_string : t -> string

(** Identifier syntax: nonempty, [A-Za-z0-9_], not starting with a digit. *)
val is_valid_component : string -> bool

val create_exn : path:string list -> name:string -> t

(** Parses [a/b/name]. *)
val of_string_exn : string -> t

include Comparator.S with type t := t
