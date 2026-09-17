(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "resource_request.ml" *)

open! Core

(* What a resource constructor asks for; a kind plus its contract;

   Careful: [contract] is compared structurally, so field order is part of the request.
   [%sexp { width : int; depth : int }] and [%sexp { depth : int; width : int }] describe
   the same memory but never match each other, and nothing raises for it; see
   Technology.exact_mapping;
*)
type t =
  { kind : string
  ; contract : Sexp.t
  }
[@@deriving compare, equal, sexp_of]

let create_exn ~kind ~contract =
  if not (Resource_id.is_valid_component kind)
  then raise_s [%message "resource kind must be an identifier" (kind : string)];
  { kind; contract }
;;
