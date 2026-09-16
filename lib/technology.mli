(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "technology.mli" *)
(* Technology capability: which resource contracts have an exact implementation, and the
   collateral each implementation carries.

   Capability describes what is possible. Project policy ({!Resource_policy}) decides what
   is acceptable. Tile geometry, layers, corners and library views are resolved in phase
   P2 and are not represented yet. *)

open! Core

module Collateral : sig
  module Role : sig
    type t =
      | Simulation_model
      | Black_box
      | Timing_model of { corner : string }
      | Physical_abstract
      | Physical_layout
    [@@deriving compare, equal, sexp_of]
  end

  type t =
    { role : Role.t
    ; reference : string
    }
  [@@deriving compare, equal, sexp_of]
end

module Macro : sig
  type t =
    { name : string
    ; collateral : Collateral.t list
    }
  [@@deriving compare, equal, sexp_of]
end

module Resource_mapping : sig
  type t =
    { request : Resource_request.t
    ; macro : Macro.t
    }
  [@@deriving compare, equal, sexp_of]
end

type t = private
  { name : string
  ; resource_mappings : Resource_mapping.t list
  }
[@@deriving sexp_of]

(** Raises if two mappings claim the same request: selection would be ambiguous. *)
val create_exn : name:string -> resource_mappings:Resource_mapping.t list -> t

(** IHP SG13 CMOS5L standard cells. No resource mappings: no SRAM macro has been
    established for this technology (see docs/program-memory-contract.md section 8). *)
val ihp_sg13cmos5l : t

val exact_mapping : t -> Resource_request.t -> Resource_mapping.t option
