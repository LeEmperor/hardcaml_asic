(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "resource_record.ml" *)
(* What one resource registered during elaboration. The finalized build's inventory is a
   list of these, ordered by identity. *)

open! Core

module Source = struct
  type t =
    | Generated_behavioral_model
    | Generated_synthesis_rtl
    | Collateral of Technology.Collateral.t
  [@@deriving compare, equal, sexp_of]
end

module Elaborated_as = struct
  type t =
    | Behavioral_model
    | Selected_implementation
  [@@deriving compare, equal, sexp_of]
end

type t =
  { id : Resource_id.t
  ; request : Resource_request.t
  ; requirement : Resource_policy.Requirement.t
  ; policy : Resource_policy.Applied.t
  ; selection : Selection.t
  ; elaborated_as : Elaborated_as.t
  ; sources : Source.t list
  }
[@@deriving compare, equal, sexp_of]
