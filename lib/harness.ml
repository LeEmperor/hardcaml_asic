(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "harness.ml" *)
(* Source implementation of harness selection. A harness is the answer to "what does this
   design get dropped into?"; for now that is only Tiny Tapeout;

   Target pairs it with a technology, and Build carries it through so adapters can render
   harness specific outputs later (for example the TT info.yaml tiles field). Nothing
   reads inside it yet.

   It does NOT know the top-level interface a harness requires, its geometry or its
   submission metadata; resolving those is P2 work. It does NOT describe the process
   either, that is Technology's job.
*)

open! Core

[@@@ocamlformat "disable"]

(* Everything specific to the Tiny Tapeout harness; *)
module Tiny_tapeout = struct
  (* How many Tiny Tapeout tiles the design occupies; the constructors mirror the tile
     sizes TT accepts in info.yaml, T1x1 -> "1x1" through T8x2 -> "8x2";

     Only sizes TT actually offers are constructors, so an unsupported size cannot be
     declared at all. The physical size of a tile depends on the technology as well, so
     no geometry is attached here; that is resolved per harness and technology pair in P2.

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
    [@@deriving compare, equal, enumerate, sexp_of]
  end
end

(* The selected harness;

   Tiny_tapeout : a Tiny Tapeout project occupying [tiles];

   A variant with one constructor on purpose: future harnesses (a bare die, for example)
   become new constructors instead of fields bolted onto the Tiny Tapeout case.
*)
type t = Tiny_tapeout of { tiles : Tiny_tapeout.Tiles.t } [@@deriving sexp_of]
[@@@ocamlformat "enable"]
