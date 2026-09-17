(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "resource_record.ml" *)
(* Source implementation of the resource record. A record is what one registered resource
   ended up as during elaboration, and WHY;

   Elaboration_context.register_exn builds one per registered resource, after
   Resource_policy.lookup, Selection.select and Elaboration_context.sources_of have each
   made their decision, and keeps it in the context keyed by identity.
   Elaboration_context.Private.finalize hands the records over, and Build.Private.create
   sorts them by Resource_id.compare into the build's inventory (Build.resources);

   It does NOT make any of those decisions or check that they agree with each other; the
   policy, the selection and the mode own them, and this module only writes them down.
*)

open! Core

[@@@ocamlformat "disable"]

(* An artifact a downstream step (simulation, synthesis, hardening) needs for a resource;

   Generated_behavioral_model : the behavioral model generated from the Hardcaml design;
                                what every resource gets in Simulation mode;
   Generated_synthesis_rtl    : synthesizable RTL generated from the Hardcaml design;
                                what a Flops selection gets in Implementation mode;
   Collateral c               : one file shipped with the selected hard macro; a Macro
                                selection in Implementation mode gets one per collateral
                                entry of its Technology.Macro.t;
*)
module Source = struct
  type t =
    | Generated_behavioral_model
    | Generated_synthesis_rtl
    | Collateral of Technology.Collateral.t
  [@@deriving compare, equal, sexp_of]
end

(* What this elaboration actually built for a resource;

   Behavioral_model        : the behavioral model, regardless of what was selected;
   Selected_implementation : the implementation the selection chose;

   Careful: in Simulation mode a resource can have selection Macro "fixture_macro_8" and
   still be elaborated as Behavioral_model, since simulation ignores the selection.
   Anything reading the inventory to find out what hardware was built should look at
   [elaborated_as], NOT [selection]; -> see expect tests in test_selection.ml
*)
module Elaborated_as = struct
  type t =
    | Behavioral_model
    | Selected_implementation
  [@@deriving compare, equal, sexp_of]
end

(* One entry in the build's inventory;

   id            : the resource's identity, its scope path plus name;
   request       : what the design asked for, kind plus contract;
   requirement   : what the project policy accepts for it;
   policy        : which part of the policy produced [requirement];
   selection     : the implementation chosen, and why;
   elaborated_as : what this elaboration actually built;
   sources       : artifacts downstream steps need for what was built;

   The whole decision chain is kept rather than only the outcome, so the inventory can
   answer why a resource was built the way it was without rerunning elaboration.
*)
type t =
  { id            : Resource_id.t
  ; request       : Resource_request.t
  ; requirement   : Resource_policy.Requirement.t
  ; policy        : Resource_policy.Applied.t
  ; selection     : Selection.t
  ; elaborated_as : Elaborated_as.t
  ; sources       : Source.t list
  }
[@@deriving compare, equal, sexp_of]

[@@@ocamlformat "enable"]
