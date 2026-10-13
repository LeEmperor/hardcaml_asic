open! Core

type t = Synthesis | Floorplan | Placement | Cts | Routing | Signoff
[@@deriving compare, equal, sexp_of]

let all = [ Synthesis; Floorplan; Placement; Cts; Routing; Signoff ]

let to_string = function
  | Synthesis -> "synthesis"
  | Floorplan -> "floorplan"
  | Placement -> "placement"
  | Cts -> "cts"
  | Routing -> "routing"
  | Signoff -> "signoff"
;;

let of_string name =
  match List.find all ~f:(fun stage -> String.equal (to_string stage) name) with
  | Some stage -> Ok stage
  | None -> Or_error.errorf "Unknown flow stage %S; use synthesis, floorplan, placement, cts, routing or signoff" name
;;

module Closure_scope = struct
  type t = Path_bound [@@deriving equal, sexp_of]
end

module Acceptance = struct
  type t = Not_evaluated [@@deriving equal, sexp_of]
end

type capability =
  { endpoint : string
  ; successor : string option
  ; restart_targets : t list
  ; tested_image_id : string
  ; closure_scope : Closure_scope.t
  ; acceptance : Acceptance.t
  }
[@@deriving sexp_of]

let capability stage =
  let endpoint, successor, restart_targets =
    match stage with
    | Synthesis -> "Yosys.Synthesis", Some "Checker.YosysUnmappedCells", [ Floorplan; Placement ]
    | Floorplan -> "OpenROAD.Floorplan", Some "OpenROAD.DumpRCValues", [ Placement ]
    | Placement -> "OpenROAD.DetailedPlacement", Some "OpenROAD.CTS", [ Cts ]
    | Cts -> "OpenROAD.CTS", Some "OpenROAD.STAMidPNR-1", [ Routing ]
    | Routing -> "OpenROAD.DetailedRouting", Some "Odb.RemoveRoutingObstructions", [ Signoff ]
    | Signoff -> "Misc.ReportManufacturability", None, []
  in
  { endpoint
  ; successor
  ; restart_targets
  ; tested_image_id = "sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a"
  ; closure_scope = Path_bound
  ; acceptance = Not_evaluated
  }
;;
