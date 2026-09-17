(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "build.ml" *)
(* Source implementation of the finalized build. A build is the answer to "what did this
   elaboration produce?";

   Project.elaborate is the only caller of [Private.create]; it runs once the design
   constructor returned a circuit AND Elaboration_context.Private.finalize accepted the
   collected resources. Everything else only reads a build through the accessors, or
   prints it through [sexp_of_t] (the lifecycle expect tests do this).

   It does NOT validate anything; every field arrives already checked, by Project.create
   (metadata, clocks, flow) or by the elaboration context (resources). It does NOT resolve
   the target or emit files either, that is P2 and P3 work.
*)

open! Core
open! Hardcaml

[@@@ocamlformat "disable"]

(* The build itself; a straight copy of the declaration plus what elaboration produced;

   project_name : the Project.t name, already a valid identifier;
   metadata     : declared metadata, unchanged;
   mode         : which elaboration produced this build;
   target       : the declared harness and technology selection, NOT a resolved target;
   flow         : adapter identity, operation and adapter settings;
   clocks       : declared clocks, not yet resolved against the circuit's ports;
   resources    : the resource inventory, sorted by identity in [Private.create];
   circuit      : the flattened Hardcaml circuit returned by the design constructor;
*)
type t =
  { project_name : string
  ; metadata     : Metadata.t
  ; mode         : Elaboration_mode.t
  ; target       : Target.t
  ; flow         : Flow.t
  ; clocks       : Clock.t list
  ; resources    : Resource_record.t list
  ; circuit      : Circuit.t
  }

(* Hand written instead of derived, because Circuit.t has no useful sexp; the circuit is
   summarised by its top module name as [top], and everything else prints as is;

   Careful: the field order here is the order the lifecycle expect test prints, [top] sits
   right after [project_name]. Reordering is harmless but shows up as an expect diff.
*)
let sexp_of_t { project_name; metadata; mode; target; flow; clocks; resources; circuit } =
  let top = Circuit.name circuit in
  [%sexp
    { project_name : string
    ; top          : string
    ; metadata     : Metadata.t
    ; mode         : Elaboration_mode.t
    ; target       : Target.t
    ; flow         : Flow.t
    ; clocks       : Clock.t list
    ; resources    : Resource_record.t list
    }]
;;

(* grab the project name out of a build *)
let project_name t = t.project_name

(* grab the declared metadata out of a build *)
let metadata t = t.metadata

(* grab the elaboration mode that produced this build *)
let mode t = t.mode

(* grab the declared target selection; not resolved, see Target *)
let target t = t.target

(* grab the flow adapter and its settings *)
let flow t = t.flow

(* grab the declared clocks *)
let clocks t = t.clocks

(* grab the resource inventory; already sorted by identity, see [Private.create] *)
let resources t = t.resources

(* grab the elaborated circuit; tests hand this to Cyclesim *)
let circuit t = t.circuit

(* The only way to make a build; Private by Jane convention, meaning only
   Project.elaborate is supposed to call it;
*)
module Private = struct
  (* Assemble a build out of already validated parts;

     The one thing it does is sort [resources] by Resource_id.compare, so the inventory
     order is independent of registration order and is a guarantee this module owns;

     Why: Elaboration_context.Private.finalize happens to return its records in identity
     order already, since they come out of a map keyed by Resource_id. Sorting again here
     means the mli promise does not silently depend on how the context stores records;
  *)
  let create
      ~project_name
      ~metadata
      ~mode
      ~target
      ~flow
      ~clocks
      ~resources (* in whatever order the context hands them over *)
      ~circuit
    =
    let resources =
      List.sort resources ~compare:(fun (a : Resource_record.t) b ->
        Resource_id.compare a.id b.id)
    in
    { project_name; metadata; mode; target; flow; clocks; resources; circuit }
  ;;
end
[@@@ocamlformat "enable"]
