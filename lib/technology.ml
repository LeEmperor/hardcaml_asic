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

  (* The environment the standard cells are analysed in: what drives the design's inputs,
     what its outputs drive, and how much margin timing analysis keeps;

     driving_cell          : the cell that stands in for whatever drives a top-level
                             input, the clock included; without one an input has no slew
                             and the first gate on the path looks faster than it is;
     driving_cell_pin      : the output pin of [driving_cell] that does the driving;
                             LibreLane spells the pair "<cell>/<pin>" in
                             SYNTH_DRIVING_CELL, this record keeps the halves apart so
                             neither can contain the separator;
     output_cap_load_ff    : the capacitance every top-level output is assumed to drive,
                             in femtofarads, the unit LibreLane's OUTPUT_CAP_LOAD uses;
     max_fanout            : how many cells one net may drive before synthesis and CTS
                             have to buffer it;
     clock_uncertainty_ns  : jitter and skew margin taken off every capturing edge;
     clock_transition_ns   : the slew assumed on the clock, which matters before CTS has
                             built a tree to derive one from;
     time_derating_percent : how far cell and net delays are stretched for late paths and
                             shrunk for early ones, to cover on-chip variation;

     Every value is read off the pinned PDK's own LibreLane standard-cell configuration,
     libs.tech/librelane/sg13cmos5l_stdcell/config.tcl, at the PDK revision a Target pins
     (see docs/target-reference.md). They are recorded here rather than left to LibreLane
     because this project supplies its own SDC: setting PNR_SDC_FILE stops LibreLane's
     FALLBACK_SDC from running, and that script is the only place these variables reach
     timing analysis.

     Careful: upstream's own comment on the last four is "FIXME: A bit random ... from
     sky130". They are the pinned values, NOT values characterised for this process; a
     project with a reason to differ passes its own through Target.Inputs.
  *)
  module Constraints = struct
    type t =
      { driving_cell          : string
      ; driving_cell_pin      : string
      ; output_cap_load_ff    : float
      ; max_fanout            : int
      ; clock_uncertainty_ns  : float
      ; clock_transition_ns   : float
      ; time_derating_percent : float
      }
    [@@deriving compare, equal, sexp_of]

    (* grab the output load in the unit set_load takes;

       Why the conversion: set_load is read in the Liberty's capacitive_load_unit, which
       is (1, pf) for every sg13cmos5l standard-cell view, while [output_cap_load_ff] is
       in femtofarads. LibreLane's base.sdc divides by the same 1000 for the same reason.
       A technology whose Liberty declared another unit would need its own factor here.
    *)
    let output_cap_load_pf t = t.output_cap_load_ff /. 1000.

    (* grab the driving cell as LibreLane's "<cell>/<pin>" spelling; what synthesis reads
       out of SYNTH_DRIVING_CELL, and what Resolved_build derives that setting from *)
    let driving_cell_setting t = t.driving_cell ^ "/" ^ t.driving_cell_pin
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

  (* The pinned constraint environment, and the default Target.Inputs carries; the values
     the PDK's standard-cell LibreLane configuration sets at the pinned revision *)
  let constraints =
    { Constraints.driving_cell = "sg13cmos5l_buf_4"
    ; driving_cell_pin         = "X"
    ; output_cap_load_ff       = 6.0
    ; max_fanout               = 10
    ; clock_uncertainty_ns     = 0.25
    ; clock_transition_ns      = 0.15
    ; time_derating_percent    = 5.0
    }
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
