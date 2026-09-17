open! Core

type t =
  { harness : Harness.t
  ; technology : Technology.t
  }
[@@deriving sexp_of]

module Rectangle_um = struct
  type t =
    { x_min : float
    ; y_min : float
    ; x_max : float
    ; y_max : float
    }
  [@@deriving sexp_of]
end

module Reference = struct
  module Source = struct
    type t = Support_tools | Pdk [@@deriving sexp_of]
  end

  module Role = struct
    type t =
      | Floorplan_def
      | Technology_view of Technology.Cmos5l.View.Role.t
    [@@deriving sexp_of]
  end

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

module Inputs = struct
  type t =
    { support_tools_revision : string
    ; pdk_revision : string
    ; floorplan_path : string
    ; floorplan_sha256 : string
    ; die_area_um : Rectangle_um.t
    ; technology_views : Technology.Cmos5l.View.t list
    }
  [@@deriving sexp_of]

  (* From the consumer's tinytapeout/toolchain.lock, inspected against the
     support-tools tile_sizes.yaml and the CMOS5L PDK config at these revisions.
     No checkout path or installed PDK is embedded in this declaration. *)
  let reference_cmos5l_6x4 =
    { support_tools_revision = "da63c9927411e3aca350977d653d24bbf5bca972"
    ; pdk_revision = "2bbec755dc67ca3db0261c3d6163e15735d66710"
    ; floorplan_path = "tech/ihp-sg13cmos5l/def/tt_block_6x4_pgvdd.def"
    ; floorplan_sha256 =
        "b46d9a0ee8352160e48dbc8312f092f985629061df736c7f46d58686535a76f4"
    ; die_area_um = { x_min = 0.; y_min = 0.; x_max = 1289.28; y_max = 710.64 }
    ; technology_views = Technology.Cmos5l.views
    }
  ;;
end

module Resolved = struct
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

let is_hex_string ~length value =
  String.length value = length
  && String.for_all value ~f:(function
    | '0' .. '9' | 'a' .. 'f' -> true
    | _ -> false)
;;

let valid_relative_path path =
  not (String.is_empty (String.strip path))
  && not (String.is_prefix path ~prefix:"/")
  && List.for_all (String.split path ~on:'/') ~f:(fun part ->
    not (String.is_empty part) && not (String.equal part "..") && not (String.equal part "."))
;;

let validate_inputs (inputs : Inputs.t) =
  let open Technology.Cmos5l.View in
  let required =
    [ Role.Pdk_configuration
    ; Role.Technology_lef
    ; Role.Standard_cell_lef
    ; Role.Standard_cell_gds
    ; Role.Standard_cell_verilog
    ; Role.Standard_cell_liberty
    ]
  in
  let roles = List.map inputs.technology_views ~f:(fun view -> view.role) in
  let missing =
    List.filter required ~f:(fun role ->
      not (List.mem roles role ~equal:Role.equal))
  in
  let duplicates = List.find_a_dup roles ~compare:Role.compare in
  let malformed_views =
    List.filter inputs.technology_views ~f:(fun view ->
      not (valid_relative_path view.path)
      || (Role.equal view.role Standard_cell_liberty
          && not (Option.equal String.equal view.corner (Some Technology.Cmos5l.corner)))
      || (not (Role.equal view.role Standard_cell_liberty)
          && Option.is_some view.corner))
  in
  let { Rectangle_um.x_min; y_min; x_max; y_max } = inputs.die_area_um in
  Or_error.combine_errors_unit
    [ (if is_hex_string ~length:40 inputs.support_tools_revision
       && is_hex_string ~length:40 inputs.pdk_revision
       then Ok ()
       else Or_error.error_string "target inputs need full lowercase Git revisions")
    ; (if valid_relative_path inputs.floorplan_path
          && String.equal
               inputs.floorplan_path
               "tech/ihp-sg13cmos5l/def/tt_block_6x4_pgvdd.def"
       then Ok ()
       else
         Or_error.error_string
           "TT CMOS5L 6x4 target needs its pinned relative floorplan DEF path")
    ; (if is_hex_string ~length:64 inputs.floorplan_sha256
       then Ok ()
       else Or_error.error_string "target inputs need a floorplan SHA-256")
    ; (if Float.is_finite x_min
       && Float.is_finite y_min
       && Float.is_finite x_max
       && Float.is_finite y_max
       && Float.(x_max > x_min)
       && Float.(y_max > y_min)
       then Ok ()
       else Or_error.error_string "target inputs need a finite positive die area in micrometres")
    ; (if List.is_empty missing
       then Ok ()
       else Or_error.error_s [%message "missing required CMOS5L views" (missing : Role.t list)])
    ; (match duplicates with
       | None -> Ok ()
       | Some duplicate ->
         Or_error.error_s [%message "duplicate CMOS5L view role" (duplicate : Role.t)])
    ; (if List.is_empty malformed_views
       then Ok ()
       else
         Or_error.error_s
           [%message "malformed CMOS5L view references" (malformed_views : t list)])
    ]
;;

let resolve ?(inputs = Inputs.reference_cmos5l_6x4) ({ harness; technology } : t) =
  match harness with
  | Tiny_tapeout { tiles = T6x4 }
    when String.equal technology.name Technology.Cmos5l.pdk
         && List.is_empty technology.resource_mappings ->
    let%map.Or_error () = validate_inputs inputs in
    let floorplan =
      { Reference.source = Support_tools
      ; revision = inputs.support_tools_revision
      ; role = Floorplan_def
      ; path = inputs.floorplan_path
      ; sha256 = Some inputs.floorplan_sha256
      ; corner = None
      }
    in
    let views =
      List.map inputs.technology_views ~f:(fun view ->
        { Reference.source = Pdk
        ; revision = inputs.pdk_revision
        ; role = Technology_view view.role
        ; path = view.path
        ; sha256 = None
        ; corner = view.corner
        })
    in
    { Resolved.harness
    ; technology_name = Technology.Cmos5l.pdk
    ; tiles = Harness.Tiny_tapeout.Tiles.to_string T6x4
    ; die_area_um = inputs.die_area_um
    ; floorplan
    ; harness_power_pins = "VPWR", "VGND"
    ; standard_cell_power_pins = Technology.Cmos5l.standard_cell_power_pins
    ; routing_layers = Technology.Cmos5l.routing_layers
    ; top_routing_layer = Technology.Cmos5l.top_routing_layer
    ; corner = Technology.Cmos5l.corner
    ; views
    }
  | _ ->
    Or_error.error_s
      [%message
        "unsupported target combination; the reference resolver supports TT 6x4 with IHP SG13 CMOS5L"
          ~tiles:(harness : Harness.t)
          ~technology:(technology.name : string)]
;;
