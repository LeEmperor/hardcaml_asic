(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "selection.ml" *)
(* Source implementation of implementation selection. Combines a requested contract,
   technology capability and a project requirement into one implementation choice;

   A "selection" is what was selected, and more importantly WHY.

   Elaboration_context.register_exn calls [select] once per registered resource, after
   Resource_policy.lookup has produced the requirement. The result is stored in
   Resource_record.selection, and Elaboration_context.sources_of reads its
   [implementation] to decide which sources the resource carries;

   It does NOT round, compose or substitute a different contract: a macro is chosen only
   when Technology.exact_mapping finds a mapping for exactly this request. It also does
   NOT decide what gets emitted for simulation; that is Elaboration_mode's job, applied in
   Elaboration_context.sources_of.
*)

open! Core

[@@@ocamlformat "disable"]

(* What was chosen for a resource;

   Flops   : synthesizable flop storage generated from the Hardcaml design;
   Macro s : the technology hard macro named [s];

   TODO (possible optimization): [Macro] keeps only the macro's name, so
   Elaboration_context.sources_of has to call Technology.exact_mapping a second time to
   recover the collateral, with a [None -> []] branch that is only unreachable because the
   caller passes the same technology and request to both. Carrying the whole
   Technology.Macro.t here would remove the second lookup and the dead branch; the cheaper
   alternative is to raise_s in that branch instead of silently returning no collateral;
*)
module Implementation = struct
  type t =
    | Flops
    | Macro of string
  [@@deriving compare, equal, sexp_of]
end

(* Why [implementation] was chosen; this is what keeps a fallback from being silent;

   Explicit_flops  : the requirement was Flops, so flops were used whether or not a
                     macro exists;
   Exact_mapping   : [technology] has an exact mapping for the request, and the
                     requirement allowed a macro;
   Flop_fallback   : [no_exact_mapping_in] has no exact mapping for the request, and the
                     requirement allowed falling back to flops;

   Why: Explicit_flops and Flop_fallback both build flops, so [implementation] alone
   cannot tell a deliberate choice from a degraded one. The technology name is carried in
   the reason so the inventory says which technology was asked, without needing the
   project alongside it;
*)
module Reason = struct
  type t =
    | Explicit_flops
    | Exact_mapping of { technology : string }
    | Flop_fallback of { no_exact_mapping_in : string }
  [@@deriving compare, equal, sexp_of]
end

(* One selection; the choice plus the reason for it;

   Careful: there is no mli, so this record is NOT private. Only [select] guarantees
   [implementation] and [reason] agree; a hand-built { implementation = Macro "x";
   reason = Explicit_flops } compiles and is not caught anywhere;
*)
type t =
  { implementation : Implementation.t
  ; reason         : Reason.t
  }
[@@deriving compare, equal, sexp_of]

(* The main sauce here for selection; given what the technology can map and what the
   project accepts, choose an implementation for [request];

   Requirement              Exact mapping   Result
   Flops                  , any          -> Flops, Explicit_flops;
   Exact                  , Some macro   -> Macro, Exact_mapping;
   Exact_or_flop_fallback , Some macro   -> Macro, Exact_mapping;
   Exact_or_flop_fallback , None         -> Flops, Flop_fallback;
   Exact                  , None         -> error;

   Returns Or_error rather than raising so the caller decides how to fail;
   Elaboration_context.register_exn turns the error into a raise, tagged with the
   instance identity and the request, so design constructors do not have to thread
   Or_error through every hierarchy level;

   The match has no top-level wildcard on purpose: a new Requirement constructor fails to
   compile here until someone decides what it selects -> see expect tests
   (test/test_selection.ml);
*)
let select
    ~(technology : Technology.t) (* what the technology can map; *)
    ~(requirement : Resource_policy.Requirement.t) (* what the project accepts; *)
    (request : Resource_request.t) (* kind plus contract, technology independent; *)
  : t Or_error.t
  =
  match requirement, Technology.exact_mapping technology request with

  (* Flops requested; any mapping is ignored, the project asked for flops explicitly *)
  (* TODO (possible optimization): the mapping is scanned even though this arm ignores it;
     harmless while mapping lists are small, but the lookup could be skipped for Flops; *)
  | Flops, _ -> Ok { implementation = Flops; reason = Explicit_flops }

  (* A macro is allowed and the technology has one for exactly this contract; take it *)
  | (Exact | Exact_or_flop_fallback), Some { macro; _ } ->
    Ok
      { implementation = Macro macro.name
      ; reason         = Exact_mapping { technology = technology.name }
      }

  (* No macro, but fallback is allowed; flops, and the reason says it was a fallback *)
  | Exact_or_flop_fallback, None ->
    Ok
      { implementation = Flops
      ; reason         = Flop_fallback { no_exact_mapping_in = technology.name }
      }

  (* No macro, and the project requires one; nothing acceptable exists *)
  | Exact, None ->
    Or_error.error_s
      [%message
        "technology has no exact implementation for the requested contract, and flop \
         fallback is not permitted"
          ~technology:technology.name]
;;

[@@@ocamlformat "enable"]
