(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "resource_request.ml" *)

open! Core

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
