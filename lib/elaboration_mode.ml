(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "elaboration_mode.ml" *)
(* Source implementation of the elaboration mode. A mode is the answer to "why is this
   design being elaborated?"; the same design constructor serves both answers;

   Project.elaborate takes it as [~mode] and hands it to
   Elaboration_context.Private.create, which keeps it for the whole run.
   Elaboration_context.sources_of matches on it to decide what each registered resource
   is elaborated as and which sources it carries, and Build records it so a finished
   build says which mode produced it;

   It does NOT change selection. Selection runs the same way in both modes, so a policy
   that cannot be satisfied fails before any simulation result can be mistaken for an
   implementable design. The mode only decides what is emitted AFTER selection.
*)

open! Core

[@@@ocamlformat "disable"]

(* Why a design is being elaborated;

   Simulation     : build behavioural models for resources, whatever was selected;
   Implementation : build the selected implementation (flops or a technology macro);
*)
type t =
  | Simulation
  | Implementation
[@@deriving compare, equal, sexp_of]

[@@@ocamlformat "enable"]
