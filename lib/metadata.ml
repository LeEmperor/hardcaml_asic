(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "metadata.ml" *)
(* Declared project metadata. Harness-specific outputs (for example TT info.yaml) are
   rendered from this rather than maintained separately. Pin meanings arrive with P2. *)

open! Core

type t =
  { title : string
  ; author : string
  ; description : string
  }
[@@deriving sexp_of]

let validate t =
  if String.is_empty (String.strip t.title)
  then Or_error.error_s [%message "project metadata needs a title"]
  else Ok ()
;;
