(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "resource_request.mli" *)
(* The contract a resource constructor asks for, independent of any technology.

   [contract] is the resource's own description of shape and behaviour (for example width,
   depth and latency). Selection compares it for exact equality: an implementation is
   never chosen for a nearby or larger contract.

   The comparison is structural on the sexp, so field ORDER counts:
   [((width 8) (depth 4))] and [((depth 4) (width 8))] are different contracts. Build
   every contract for a kind from one [[%sexp { ... }]] expression so the order agrees
   (see {!Technology.exact_mapping}). *)

open! Core

type t = private
  { kind : string
  ; contract : Sexp.t
  }
[@@deriving compare, equal, sexp_of]

val create_exn : kind:string -> contract:Sexp.t -> t
