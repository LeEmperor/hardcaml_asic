(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "build.ml" *)

open! Core
open! Hardcaml

type t =
  { project_name : string
  ; metadata : Metadata.t
  ; mode : Elaboration_mode.t
  ; target : Target.t
  ; flow : Flow.t
  ; clocks : Clock.t list
  ; resources : Resource_record.t list
  ; circuit : Circuit.t
  }

let sexp_of_t { project_name; metadata; mode; target; flow; clocks; resources; circuit } =
  let top = Circuit.name circuit in
  [%sexp
    { project_name : string
    ; top : string
    ; metadata : Metadata.t
    ; mode : Elaboration_mode.t
    ; target : Target.t
    ; flow : Flow.t
    ; clocks : Clock.t list
    ; resources : Resource_record.t list
    }]
;;

let project_name t = t.project_name
let metadata t = t.metadata
let mode t = t.mode
let target t = t.target
let flow t = t.flow
let clocks t = t.clocks
let resources t = t.resources
let circuit t = t.circuit

module Private = struct
  let create ~project_name ~metadata ~mode ~target ~flow ~clocks ~resources ~circuit =
    let resources =
      List.sort resources ~compare:(fun (a : Resource_record.t) b ->
        Resource_id.compare a.id b.id)
    in
    { project_name; metadata; mode; target; flow; clocks; resources; circuit }
  ;;
end
