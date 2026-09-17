(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "technology.mli" *)
(* Technology capability: which resource contracts have an exact implementation, and the
   collateral each implementation carries.

   A technology is a name plus a list of mappings, each saying "a request for exactly this
   contract can be built as this hard macro". Matching is exact equality on the request:
   there is no rounding to a nearby or larger contract. At most one mapping may claim a
   request, so a lookup never has to choose.

   Capability describes what is possible. Project policy ({!Resource_policy}) decides what
   is acceptable, and {!Selection} is where the two meet. Tile geometry, layers, corners
   and library views are described separately by {!Cmos5l} for target resolution. *)

open! Core

module Collateral : sig
  module Role : sig
    type t =
      | Simulation_model (** Model used to simulate the macro itself. *)
      | Black_box (** Empty module stub standing in for the macro during synthesis. *)
      | Timing_model of { corner : string } (** Timing library for one named corner. *)
      | Physical_abstract (** Abstract view for place and route. *)
      | Physical_layout (** Full layout of the macro. *)
    [@@deriving compare, equal, sexp_of]
  end

  (** One file shipped with a macro; [reference] locates it and is not resolved or checked
      here. *)
  type t =
    { role : Role.t
    ; reference : string
    }
  [@@deriving compare, equal, sexp_of]
end

(** A technology hard macro and all of its collateral. *)
module Macro : sig
  type t =
    { name : string
    ; collateral : Collateral.t list
    }
  [@@deriving compare, equal, sexp_of]
end

(** "A request for exactly [request] can be built as [macro]". *)
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

(** [create_exn ~name:"fixture-tech" ~resource_mappings]

    Raises, with the technology name and the request, if two mappings claim the same
    request: selection would be ambiguous. Requests are compared exactly, so two contracts
    that mean the same thing but are written differently are NOT caught (see
    {!exact_mapping}). The name [ihp-sg13cmos5l] is reserved for the built-in
    reference technology. *)
val create_exn : name:string -> resource_mappings:Resource_mapping.t list -> t

(** IHP SG13 CMOS5L standard cells. No resource mappings: no SRAM macro has been
    established for this technology (see docs/program-memory-contract.md section 8). *)
val ihp_sg13cmos5l : t

(** Standard-cell views and routing limits for the pinned CMOS5L reference. Paths
    are relative to the [ihp-sg13cmos5l] PDK directory. Presence and suitability
    for a requested flow operation are checked separately; this description does
    not claim an SRAM capability. *)
module Cmos5l : sig
  module View : sig
    module Role : sig
      type t =
        | Pdk_configuration
        | Technology_lef
        | Standard_cell_lef
        | Standard_cell_gds
        | Standard_cell_verilog
        | Standard_cell_liberty
      [@@deriving compare, equal, sexp_of]
    end

    type t =
      { role : Role.t
      ; path : string
      ; corner : string option
      }
    [@@deriving compare, equal, sexp_of]
  end

  val pdk : string
  val corner : string
  val routing_layers : string list
  val top_routing_layer : string
  val standard_cell_power_pins : string * string
  val views : View.t list
end

(** The mapping whose request equals [request], or [None].

    Equality is structural on the contract sexp, including field order: a mapping for
    [((width 8) (depth 4))] does not match a request for [((depth 4) (width 8))]. Build
    every contract for a resource kind the same way (one [[%sexp { ... }]] expression) so
    the order agrees. *)
val exact_mapping : t -> Resource_request.t -> Resource_mapping.t option
