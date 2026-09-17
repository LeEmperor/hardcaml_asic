open! Core

(** Selected harness and technology. Flow validation uses [Target.resolve] through
    {!Project.elaborate_for_flow}. *)
type t =
  { harness : Harness.t
  ; technology : Technology.t
  }
[@@deriving sexp_of]

module Rectangle_um : sig
  type t =
    { x_min : float
    ; y_min : float
    ; x_max : float
    ; y_max : float
    }
  [@@deriving sexp_of]
end

module Reference : sig
  module Source : sig
    type t = Support_tools | Pdk [@@deriving sexp_of]
  end

  module Role : sig
    type t =
      | Floorplan_def
      | Technology_view of Technology.Cmos5l.View.Role.t
    [@@deriving sexp_of]
  end

  (** [path] is relative to the selected support-tools checkout or PDK directory,
      according to [source]. Resolution records references; it does not read files. *)
  type t =
    { source : Source.t
    ; revision : string
    ; role : Role.t
    ; path : string
    ; sha256 : string option
    ; corner : string option
    }
  [@@deriving sexp_of]
end

module Inputs : sig
  type t =
    { support_tools_revision : string
    ; pdk_revision : string
    ; floorplan_path : string
    ; floorplan_sha256 : string
    ; die_area_um : Rectangle_um.t
    ; technology_views : Technology.Cmos5l.View.t list
    }
  [@@deriving sexp_of]

  (** Reference inputs adopted from the emulator's 2026-09-17 toolchain lock. *)
  val reference_cmos5l_6x4 : t
end

module Resolved : sig
  type t =
    { harness : Harness.t
    ; technology_name : string
    ; tiles : string
    ; die_area_um : Rectangle_um.t
    ; floorplan : Reference.t
    ; harness_power_pins : string * string
    ; standard_cell_power_pins : string * string
    ; routing_layers : string list
    ; top_routing_layer : string
    ; corner : string
    ; views : Reference.t list
    }
  [@@deriving sexp_of]
end

(** Resolve the currently supported TT 6x4 / IHP CMOS5L pair. Other selections
    fail explicitly. [inputs] lets a caller supply an independently pinned
    collateral set; required references and revisions are checked. No PDK is
    fetched or opened here. Installed-file checks belong to adapter preflight. *)
val resolve : ?inputs:Inputs.t -> t -> Resolved.t Or_error.t
