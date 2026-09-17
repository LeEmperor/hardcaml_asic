(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "target.ml" *)
(* Source implementation of the target selection. A target is the project's answer to
   "where is this design going?";

   It is two separately selected axes, a harness and a technology, handed to
   Project.create as one record. Project.elaborate takes [technology] out of it to create
   the Elaboration_context, so resource selection sees the technology; the harness is only
   carried into the Build for now.

   It does NOT check that the pair makes sense, and nothing else does yet either;
   Project.create skips it (see its TODO). Compatibility and the resolved target (die
   geometry, floorplan, power, routing layers) are P2 work, see docs/architecture.md
   section 3.
*)

open! Core

[@@@ocamlformat "disable"]

(* The selected pair;

   harness    : what the design is packaged into, and what its top level must look like;
   technology : what the design is built out of, and which macros exist;

   Careful: this is a declaration, NOT a resolved target. Any harness can be paired with
   any technology here, including combinations that could never be manufactured, and it
   is not caught anywhere until P2 target resolution exists.
*)
type t =
  { harness    : Harness.t
  ; technology : Technology.t
  }
[@@deriving sexp_of]
[@@@ocamlformat "enable"]
