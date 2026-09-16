(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "target.ml" *)
(* A selected harness and technology. Compatibility checks and the resolved target (die
   geometry, floorplan, power, routing layers) are P2 work; nothing here claims the pair
   is valid. *)

open! Core

type t =
  { harness : Harness.t
  ; technology : Technology.t
  }
[@@deriving sexp_of]
