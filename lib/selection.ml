(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "selection.ml" *)
(* Combines a requested contract, technology capability and a project requirement into one
   implementation choice. Never rounds, composes or substitutes a different contract. *)

open! Core

module Implementation = struct
  type t =
    | Flops
    | Macro of string
  [@@deriving compare, equal, sexp_of]
end

module Reason = struct
  type t =
    | Explicit_flops
    | Exact_mapping of { technology : string }
    | Flop_fallback of { no_exact_mapping_in : string }
  [@@deriving compare, equal, sexp_of]
end

type t =
  { implementation : Implementation.t
  ; reason : Reason.t
  }
[@@deriving compare, equal, sexp_of]

let select
  ~(technology : Technology.t)
  ~(requirement : Resource_policy.Requirement.t)
  request
  =
  match requirement, Technology.exact_mapping technology request with
  | Flops, _ -> Ok { implementation = Flops; reason = Explicit_flops }
  | (Exact | Exact_or_flop_fallback), Some { macro; _ } ->
    Ok
      { implementation = Macro macro.name
      ; reason = Exact_mapping { technology = technology.name }
      }
  | Exact_or_flop_fallback, None ->
    Ok
      { implementation = Flops
      ; reason = Flop_fallback { no_exact_mapping_in = technology.name }
      }
  | Exact, None ->
    Or_error.error_s
      [%message
        "technology has no exact implementation for the requested contract, and flop \
         fallback is not permitted"
          ~technology:technology.name]
;;
