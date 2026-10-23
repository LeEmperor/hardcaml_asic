open! Core

type t =
  | Synthesis
  | Floorplan
  | Placement
  | Cts
  | Routing
  | Timing
  | Signoff
[@@deriving compare, equal, sexp_of]

let all = [ Synthesis; Floorplan; Placement; Cts; Routing; Timing; Signoff ]

let to_string = function
  | Synthesis -> "synthesis"
  | Floorplan -> "floorplan"
  | Placement -> "placement"
  | Cts -> "cts"
  | Routing -> "routing"
  | Timing -> "timing"
  | Signoff -> "signoff"
;;

let of_string name =
  match List.find all ~f:(fun s -> String.equal name (to_string s)) with
  | Some s -> Ok s
  | None ->
    Or_error.errorf
      "Unknown flow stage %S; use synthesis, floorplan, placement, cts, routing, timing \
       or signoff"
      name
;;
