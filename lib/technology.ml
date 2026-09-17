(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "technology.ml" *)
(* Source implementation of technology capability. A technology is the answer to "what can
   this process build exactly, and which files come with it?";

   It is a name plus a list of mappings from a Resource_request to a hard macro.
   Selection.select asks it for a mapping through [exact_mapping] to decide between a
   macro and flops, and Elaboration_context.sources_of asks again to turn the chosen
   macro's collateral into Resource_record sources;

   It does NOT know what the project will accept, that is Resource_policy's job; Selection
   is where the two meet. The pinned CMOS5L standard-cell view/routing description below
   is separate from resource mappings and has no SRAM capability.
*)

open! Core

[@@@ocamlformat "disable"]

(* One file shipped with a macro, and what it is for;

   role      : which downstream step consumes the file;
   reference : where the file lives; kept as a plain string, nothing resolves or checks it
               here;
*)
module Collateral = struct

  (* What a collateral file is for;

     Simulation_model  : model used to simulate the macro itself;
     Black_box         : empty module stub standing in for the macro during synthesis;
     Timing_model c    : timing library for the named corner [c];
     Physical_abstract : abstract view for place and route;
     Physical_layout   : full layout of the macro;
  *)
  module Role = struct
    type t =
      | Simulation_model
      | Black_box
      | Timing_model of { corner : string }
      | Physical_abstract
      | Physical_layout
    [@@deriving compare, equal, sexp_of]
  end

  type t =
    { role      : Role.t
    ; reference : string
    }
  [@@deriving compare, equal, sexp_of]
end

(* A technology hard macro;

   name       : the macro's name; this is what Selection.Implementation.Macro records;
   collateral : every file that comes with it -> see expect tests;
*)
module Macro = struct
  type t =
    { name       : string
    ; collateral : Collateral.t list
    }
  [@@deriving compare, equal, sexp_of]
end

(* One entry in the technology; "a request for exactly [request] is built as [macro]"; *)
module Resource_mapping = struct
  type t =
    { request : Resource_request.t
    ; macro   : Macro.t
    }
  [@@deriving compare, equal, sexp_of]
end

(* The technology itself;

   The type is private in the mli, so the only way to build one is through [create_exn],
   which means every technology has already been checked for duplicate requests.
*)
type t =
  { name              : string
  ; resource_mappings : Resource_mapping.t list
  }
[@@deriving sexp_of]

(* Build a technology; raises rather than returning Or_error since technologies are
   fixed values declared at module level (see [ihp_sg13cmos5l]), where there is nothing
   to thread an error through;

   The one check: the same request cannot appear in two mappings. Without it
   [exact_mapping] would silently return whichever mapping came first, so the macro chosen
   would depend on list order;

   Careful: the check uses Resource_request.compare, so it inherits the field order
   pitfall described on [exact_mapping]; two requests whose contracts differ only in
   field order are both accepted here;
*)
let create_exn ~name ~resource_mappings =
  if String.equal name "ihp-sg13cmos5l"
  then
    raise_s
      [%message
        "ihp-sg13cmos5l is a reserved reference technology; use Technology.ihp_sg13cmos5l"];
  (match
     List.find_a_dup resource_mappings ~compare:(fun (a : Resource_mapping.t) b ->
       Resource_request.compare a.request b.request)
   with
   | None -> ()
   | Some { request; _ } ->
     raise_s
       [%message
         "ambiguous technology capability: more than one mapping for a request; keep one \
          mapping per request"
           ~technology:(name : string)
           (request : Resource_request.t)]);
  { name; resource_mappings }
;;

(* IHP SG13 CMOS5L standard cells; no mappings, so every resource under it is flops or a
   selection error, depending on policy; *)
let ihp_sg13cmos5l = { name = "ihp-sg13cmos5l"; resource_mappings = [] }

(* Pinned CMOS5L standard-cell description. These are references within the PDK,
   not files loaded during elaboration. The PDK configuration is the authority for
   the full set of flow variables; this inventory records the views the first
   adapter must be able to locate. None of these views is an SRAM macro. *)
module Cmos5l = struct
  module View = struct
    module Role = struct
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

  open View.Role

  let corner = "nom_typ_1p20V_25C"
  let routing_layers = [ "Metal2"; "Metal3"; "Metal4" ]
  let top_routing_layer = "Metal4"
  let pdk = "ihp-sg13cmos5l"
  let stdcell = "libs.ref/sg13cmos5l_stdcell"
  let standard_cell_power_pins = "VDD", "VSS"

  let views =
    let view ?corner role path = { View.role; path; corner } in
    [ view Pdk_configuration "libs.tech/librelane/config.tcl"
    ; view Technology_lef (stdcell ^ "/lef/sg13cmos5l_tech.lef")
    ; view Standard_cell_lef (stdcell ^ "/lef/sg13cmos5l_stdcell.lef")
    ; view Standard_cell_gds (stdcell ^ "/gds/sg13cmos5l_stdcell.gds")
    ; view Standard_cell_verilog (stdcell ^ "/verilog/sg13cmos5l_stdcell.v")
    ; view
        ~corner
        Standard_cell_liberty
        (stdcell ^ "/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib")
    ]
  ;;
end

(* The main sauce here for technologies; given a request, return the mapping for exactly
   that request, if the technology has one;

   A linear scan; mapping lists are a handful of entries, and [create_exn] guarantees at
   most one can match, so the first hit is the only hit;

   Careful: the contract is a Sexp.t compared structurally, so field ORDER is part of the
   match. A mapping built from [%sexp { width : int; depth : int }] gives
   ((width 8) (depth 4)), and a request built from [%sexp { depth : int; width : int }]
   gives ((depth 4) (width 8)); they describe the same memory but do not match. Nothing
   raises for this: under Exact_or_flop_fallback the resource becomes a Flop_fallback
   that only the inventory shows, and only Exact turns it into an error. Build every
   contract for a resource kind from one [%sexp { ... }] expression so the order agrees;
*)
let exact_mapping t request =
  List.find t.resource_mappings ~f:(fun mapping ->
    Resource_request.equal mapping.request request)
;;

[@@@ocamlformat "enable"]
