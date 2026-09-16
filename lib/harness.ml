(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "harness.ml" *)
(* Harness selection. Interface requirements, geometry and metadata are resolved in P2. *)

open! Core

module Tiny_tapeout = struct
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

type t = Tiny_tapeout of { tiles : Tiny_tapeout.Tiles.t } [@@deriving sexp_of]
