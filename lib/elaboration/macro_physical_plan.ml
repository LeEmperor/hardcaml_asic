open! Core

type macro =
  { resource : Resource.Id.t
  ; instance : string
  ; name : string
  ; intent : Flow.Macro_intent.t
  }

type t = macro list

let stock = "RM_IHPSG13_1P_256x16_c2_bm_bist"
let plan_file = "physical/macro-plan.json"
let pdn_tcl = "physical/pdn.tcl"
let cdl = "pdk_dir::libs.ref/sg13cmos5l_sram/cdl/" ^ stock ^ ".cdl"
let supplies = `Assoc [ "VDD!", `String "VPWR"; "VDDARRAY!", `String "VPWR"; "VSS!", `String "VGND" ]

let aligned x =
  Float.is_finite x
  && Float.(abs (x *. 200. -. round_nearest (x *. 200.)) < 1e-7)
;;

let create macros =
  let open Or_error.Let_syntax in
  let%bind () =
    Or_error.combine_errors_unit
      (List.map macros ~f:(fun m ->
         let i = m.intent in
         if not (String.equal m.name stock
                 && Resource.Id.equal m.resource i.resource
                 && String.equal m.instance (Resource.Id.rtl_instance_name m.resource))
         then Or_error.error_string "physical plan requires the checked exact SRAM resource/instance"
         else if not (aligned i.x_um && aligned i.y_um && aligned i.halo_um)
         then Or_error.error_string "physical placement and halo must align to the 0.005 um manufacturing grid"
         else if Float.(i.halo_um < 2.)
         then Or_error.error_string "physical edge access requires a placement halo of at least 2 um"
         else Ok ()))
  in
  match macros with
  | [] -> Or_error.error_string "physical macro plan cannot be empty"
  | first :: rest ->
    if List.exists rest ~f:(fun m -> not (Float.equal m.intent.halo_um first.intent.halo_um))
    then Or_error.error_string "physical macros require one common global placement halo"
    else if Option.is_some (List.find_a_dup macros ~compare:(fun a b -> String.compare a.instance b.instance))
    then Or_error.error_string "physical macro instances must be unique"
    else Ok (List.sort macros ~compare:(fun a b -> String.compare a.instance b.instance))
;;

let to_json macros =
  `Assoc
    [ "schema_version", `Int 1
    ; "strategy", `String "cmos5l_m4_edge_access_v1"
    ; "plan_file", `String plan_file
    ; "pdn_tcl", `String pdn_tcl
    ; "checking_profile", `String "cmos5l_real_gds_v1"
    ; "lvs_scope", `String "abstract_macro_boundary_with_schematic_cdl"
    ; "macros", `List (List.map macros ~f:(fun m ->
        `Assoc
          [ "resource", `String (Resource.Id.to_string m.resource)
          ; "instance", `String m.instance
          ; "module", `String m.name
          ; "location_um", `List [`Float m.intent.x_um; `Float m.intent.y_um]
          ; "orientation", `String "R0"
          ; "halo_um", `Float m.intent.halo_um
          ; "supplies", supplies
          ]))
    ]
;;

let settings_with_halo ~halo macros =
  [ "PDN_CFG", `String ("dir::../" ^ pdn_tcl)
  ; "PDN_MACRO_CONNECTIONS", `List (List.concat_map macros ~f:(fun m ->
      (* Canonical resource instance names contain only ASCII letters, digits and
         underscores. Anchors prevent prefix matches in the backend regex engine. *)
      List.map ["VDD!"; "VDDARRAY!"] ~f:(fun pin ->
        `String (Printf.sprintf "^%s$ VPWR VGND %s VSS!" m.instance pin))))
  ; "PDN_CONNECT_MACROS_TO_GRID", `Bool true
  ; "PDN_MULTILAYER", `Bool false
  ; "PDN_VERTICAL_LAYER", `String "Metal4"
  ; "PDN_VWIDTH", `Float 2.1
  ; "PDN_VPITCH", `Float 50.
  ; "PDN_VOFFSET", `Float 10.
  ; "PDN_VSPACING", `Float 2.
  ; "PDN_ENABLE_RAILS", `Bool true
  ; "PDN_ENABLE_PINS", `Bool true
  ; "PDN_ENABLE_GLOBAL_CONNECTIONS", `Bool true
  ; "PDN_RAIL_LAYER", `String "Metal1"
  ; "PDN_RAIL_WIDTH", `Float 0.44
  ; "PDN_SKIPTRIM", `Bool false
  ; "PDN_CORE_RING", `Bool false
  ; "PDN_HORIZONTAL_HALO", `Float 0.
  ; "PDN_VERTICAL_HALO", `Float 0.
  ; "FP_MACRO_HORIZONTAL_HALO", `Float halo
  ; "FP_MACRO_VERTICAL_HALO", `Float halo
  ; "ROUTING_OBSTRUCTIONS", `List (List.map macros ~f:(fun m ->
      (* The stock macro has no Metal4 signal pins. Keep lower-layer pin access
         governed by LEF OBS/PORT semantics, not a global rectangle over ports. *)
      `String (Printf.sprintf "Metal4 %.17g %.17g %.17g %.17g"
        m.intent.x_um m.intent.y_um (m.intent.x_um +. 236.8) (m.intent.y_um +. 118.78))))
  ; "RUN_KLAYOUT_STREAMOUT", `Bool true
  ; "PRIMARY_GDSII_STREAMOUT_TOOL", `String "klayout"
  ; "RUN_KLAYOUT_DRC", `Bool true
  ; "KLAYOUT_DRC_RUNSET", `String "pdk_dir::libs.tech/klayout/tech/drc/ihp-sg13cmos5l.drc"
  ; "KLAYOUT_DRC_THREADS", `Int 6
  ; "KLAYOUT_XOR_THREADS", `Int 6
  ; "KLAYOUT_DRC_OPTIONS", `Assoc
      (List.map ["no_feol"; "no_beol"; "no_offgrid"; "no_angle"; "no_pin";
                 "no_forbidden"; "no_recommended"; "precheck_drc"]
         ~f:(fun key -> key, `String "false")
       @ ["log", `String "drc-klayout.log"; "threads", `Int 6])
  ; "EXTRA_SPICE_MODELS", `List [`String cdl]
  ; "RUN_MAGIC_DRC", `Bool true
  ; "ERROR_ON_ILLEGAL_OVERLAPS", `Bool true
  ; "MAGIC_MACRO_STD_CELL_SOURCE", `String "PDK"
  ; "MAGIC_EXT_ABSTRACT_CELLS", `List [`String stock]
  ; "MAGIC_DRC_USE_GDS", `Bool false
  (* CTS hold repair may place weak delay cells on long macro-boundary nets.
     Rebuffer using routed estimates after CTS, with a positive wire limit:
     pinned repair_design's zero setting does not insert long-wire buffers. *)
  ; "RUN_POST_GRT_DESIGN_REPAIR", `Bool true
  ; "GRT_DESIGN_REPAIR_RUN_GRT", `Bool true
  ; "GRT_DESIGN_REPAIR_MAX_WIRE_LENGTH", `Float 200.
  ; "GRT_DESIGN_REPAIR_MAX_SLEW_PCT", `Int 20
  ; "GRT_DESIGN_REPAIR_MAX_CAP_PCT", `Int 20
  ; "RSZ_CORNERS", `List (List.map
      ["nom_fast_1p32V_m40C"; "nom_slow_1p08V_125C"; "nom_typ_1p20V_25C"]
      ~f:(fun corner -> `String corner))
  ]
;;

let settings macros =
  settings_with_halo ~halo:(List.hd_exn macros).intent.halo_um macros
;;

let owns_key key =
  (* This list is generated from the actual settings, including aliases accepted by
     pinned LibreLane. Physical settings cannot be bypassed through old spelling. *)
  let canonical =
    if String.is_prefix key ~prefix:"FP_PDN_"
    then String.drop_prefix key 3
    else match key with
      | "KLAYOUT_DRC_TECH_SCRIPT" -> "KLAYOUT_DRC_RUNSET"
      | "GLB_RESIZER_MAX_WIRE_LENGTH" -> "GRT_DESIGN_REPAIR_MAX_WIRE_LENGTH"
      | "GLB_RESIZER_MAX_SLEW_MARGIN" -> "GRT_DESIGN_REPAIR_MAX_SLEW_PCT"
      | "GLB_RESIZER_MAX_CAP_MARGIN" -> "GRT_DESIGN_REPAIR_MAX_CAP_PCT"
      | _ -> key
  in
  List.mem (List.map (settings_with_halo ~halo:0. []) ~f:fst) canonical ~equal:String.equal
  || String.is_prefix key ~prefix:"PDN_"
  || String.is_prefix key ~prefix:"FP_PDN_"
  || List.mem ["PDN_OBSTRUCTIONS"; "ROUTING_OBSTRUCTIONS"; "PDN_SKIPTRIM";
               "PDN_RAIL_LAYER"; "PDN_RAIL_WIDTH"; "PDN_CORE_RING";
               "PDN_HORIZONTAL_LAYER"; "PDN_EXTEND_TO";
               "FP_PDN_LOWER_LAYER"; "FP_PDN_UPPER_LAYER"; "FP_PDN_RAILS_LAYER";
               "VDD_NETS"; "GND_NETS"; "SCL_POWER_PINS"; "SCL_GROUND_PINS"]
       key ~equal:String.equal
;;

let files macros =
  let table =
    List.map macros ~f:(fun m ->
      (* Encode logical identity as bytes rather than relying on OCaml/JSON
         escaping also being Tcl escaping. Hierarchy remains part of the identity. *)
      let hex = Resource.Id.to_string m.resource |> String.to_list
        |> List.map ~f:(fun c -> Printf.sprintf "%02x" (Char.to_int c))
        |> String.concat in
      Printf.sprintf "lappend ::hc_pdn::instances [list [encoding convertfrom utf-8 [binary decode hex %s]] {%s} {%s} %.17g %.17g %.17g]\n"
        hex m.instance m.name m.intent.x_um m.intent.y_um m.intent.halo_um)
    |> String.concat
  in
  [ plan_file, Yojson.Safe.pretty_to_string (to_json macros) ^ "\n"
  ; pdn_tcl, Macro_physical_tcl.geometry ^ "\n" ^ table ^ Macro_physical_tcl.runtime
  ]
;;
