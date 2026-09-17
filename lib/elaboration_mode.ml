(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "elaboration_mode.ml" *)
(* Why a design is being elaborated. The same constructor serves both.

   [Simulation] builds behavioural models for resources. [Implementation] builds the
   selected implementation.

   Selection runs in both modes, so a policy that cannot be satisfied fails before any
   simulation result can be mistaken for an implementable design.
*)

open! Core

type t =
  | Simulation
  | Implementation
[@@deriving compare, equal, sexp_of]
