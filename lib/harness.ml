(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "harness.ml" *)
(* Source implementation of harness selection. A harness is the answer to "what does this
   design get dropped into?"; for now that is only Tiny Tapeout;

   Target pairs it with a technology, and Build carries it through so adapters can render
   harness specific outputs later (for example the TT info.yaml tiles field).

   Top-level port and submission-metadata validation live in Resolved_build. Concrete
   geometry is resolved with the technology and pinned support-tools inputs by Target.
   The harness does not describe the process; that is Technology's job.
*)

open! Core

[@@@ocamlformat "disable"]

(* Everything specific to the Tiny Tapeout harness; *)
module Tiny_tapeout = struct
  (* How many Tiny Tapeout tiles the design occupies. Target resolution checks whether
     a selected technology and pinned support-tools revision have this floorplan;

     These constructors represent sizes known to this declaration API, not a promise that
     every pinned target supports each size. Geometry is resolved per target pair.

     enumerate is derived, but nothing walks the sizes yet.
  *)
  module Tiles = struct
    type t =
      | T1x1
      | T1x2
      | T2x2
      | T3x2
      | T4x2
      | T6x2
      | T8x2
      | T6x4
    [@@deriving compare, equal, enumerate, sexp_of]

    let to_string = function
      | T1x1 -> "1x1"
      | T1x2 -> "1x2"
      | T2x2 -> "2x2"
      | T3x2 -> "3x2"
      | T4x2 -> "4x2"
      | T6x2 -> "6x2"
      | T8x2 -> "8x2"
      | T6x4 -> "6x4"
    ;;
  end
end

(* The selected harness;

   Tiny_tapeout : a Tiny Tapeout project occupying [tiles];

   A variant with one constructor on purpose: future harnesses (a bare die, for example)
   become new constructors instead of fields bolted onto the Tiny Tapeout case.
*)
type t = Tiny_tapeout of { tiles : Tiny_tapeout.Tiles.t } [@@deriving sexp_of]
[@@@ocamlformat "enable"]
