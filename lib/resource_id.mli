(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "resource_id.mli" *)
(* Stable identity of one registered resource instance.

   An identity is the Hardcaml scope path at the point of registration plus the explicit
   resource name. It therefore matches the instance hierarchy of the elaborated design.
   The type is private and every constructor validates, so any [t] in hand has only
   identifier components (see {!is_valid_component}).

   Hardcaml mangles repeated instance labels within a scope in creation order ([foo],
   [foo_0], ...). An identity below such an instance is repeatable across elaborations of
   the same constructor, but it can change if instances are added or reordered. Give
   hierarchical instances that contain resources explicit, distinct [~instance] names.

   An identity does NOT know whether it is unique; {!Elaboration_context.register_exn}
   rejects duplicates, and {!Resource_policy} decides what requirement an identity gets.
*)

open! Core

type t = private
  { path : string list
  (** Scope labels from the top, outermost first; empty at the top. *)
  ; name : string (** The resource's own name, as passed to registration. *)
  }
[@@deriving equal]

(** Lexicographic over [path @ [name]]. Every scope subtree is contiguous in this order,
    so a sorted inventory reads as the hierarchy. *)
val compare : t -> t -> int

(** Printed as a single atom [path/.../name], the same form policy selectors are written
    in. *)
val sexp_of_t : t -> Sexp.t

(** [core/left/buf]; the inverse of {!of_string_exn}. *)
val to_string : t -> string

(** Identifier syntax: nonempty, [A-Za-z0-9_], not starting with a digit. Selector paths,
    resource kinds and project names are checked with this too. *)
val is_valid_component : string -> bool

(** [create_exn ~path:["core"; "left"] ~name:"buf"]

    Raises, naming the offending component, if any label in [path] or the [name] is not a
    valid identifier. *)
val create_exn : path:string list -> name:string -> t

(** [of_string_exn "core/left/buf"]; the last component is the name.

    Raises as {!create_exn} does if any component is invalid, including the empty
    components in ["a//b"], ["a/"], ["/a"] and [""]. *)
val of_string_exn : string -> t

(** Lets identities key [Map.M(Resource_id)] and [Set.M(Resource_id)], ordered by
    {!compare}. *)
include Comparator.S with type t := t
