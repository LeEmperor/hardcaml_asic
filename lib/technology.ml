(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "technology.ml" *)

open! Core

module Collateral = struct
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
    { role : Role.t
    ; reference : string
    }
  [@@deriving compare, equal, sexp_of]
end

module Macro = struct
  type t =
    { name : string
    ; collateral : Collateral.t list
    }
  [@@deriving compare, equal, sexp_of]
end

module Resource_mapping = struct
  type t =
    { request : Resource_request.t
    ; macro : Macro.t
    }
  [@@deriving compare, equal, sexp_of]
end

type t =
  { name : string
  ; resource_mappings : Resource_mapping.t list
  }
[@@deriving sexp_of]

let create_exn ~name ~resource_mappings =
  (match
     List.find_a_dup resource_mappings ~compare:(fun (a : Resource_mapping.t) b ->
       Resource_request.compare a.request b.request)
   with
   | None -> ()
   | Some { request; _ } ->
     raise_s
       [%message
         "ambiguous technology capability: more than one mapping for a request"
           ~technology:(name : string)
           (request : Resource_request.t)]);
  { name; resource_mappings }
;;

let ihp_sg13cmos5l = create_exn ~name:"ihp-sg13cmos5l" ~resource_mappings:[]

let exact_mapping t request =
  List.find t.resource_mappings ~f:(fun mapping ->
    Resource_request.equal mapping.request request)
;;
