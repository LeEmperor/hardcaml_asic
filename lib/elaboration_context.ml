(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "elaboration_context.ml" *)
(* Source implementation of the elaboration context system. These are essentially
   databases that are spawned for an individual Build run;
*)

open! Core
open! Hardcaml

[@@@ocamlformat "disable"]
(* A context starts, and ends up either Finalized or Failed;
   If one wants to be more mathematically pedantic we could technically make a set on the final state between SUCCESS and ERROR but this is fine for a tool like this.
*)
module State = struct
  type t =
    | Open
    | Finalized
    | Failed
  [@@deriving sexp_of]
end

(* Biggest ownership items for the context.

  The mode in which we're operating,
  The technology we're using and it's features,
  The resource mapping policy,
  The Circuit_database.t that Hardcaml uses that we may draw from inside of,
  The *mutable* State of the context,
  The *mutable* result of the Resource Mapping the tool ultimately did.
      Very important!
*)
type shared =
  { mode            : Elaboration_mode.t
  ; technology      : Technology.t
  ; policy          : Resource_policy.t
  ; database        : Circuit_database.t
  ; mutable state   : State.t
  ; mutable records : Resource_record.t Map.M(Resource_id).t
  }

(* Elaboration_context.t : maintains a shared grouping record, as well as the main scope it's attached to in the hierarchy; *)
type t =
  { shared  : shared
  ; scope   : Scope.t
  }

let check_open
  t
  ~operation
  =

  match t.shared.state with
  | Open -> ()
  | (Finalized | Failed) as state ->
    raise_s
      [%message
        "elaboration context is closed; each elaboration uses a fresh context"
          (operation : string)
          (state : State.t)]
;;

let mode t = t.shared.mode

let scope t =
  check_open t ~operation:"scope";
  t.scope
;;

let in_scope t scope =
  check_open t ~operation:"in_scope";
  if not (phys_equal (Scope.circuit_database scope) t.shared.database)
  then raise_s [%message "scope does not belong to this elaboration"];
  { t with scope }
;;

let sources_of ~(mode : Elaboration_mode.t) ~(technology : Technology.t) request selection
  : Resource_record.Elaborated_as.t * Resource_record.Source.t list
  =
  match mode, (selection : Selection.t).implementation with
  | Simulation, _ -> Behavioral_model, [ Generated_behavioral_model ]
  | Implementation, Flops -> Selected_implementation, [ Generated_synthesis_rtl ]
  | Implementation, Macro _ ->
    let collateral =
      match Technology.exact_mapping technology request with
      | Some { macro; _ } -> macro.collateral
      | None -> []
    in
    ( Selected_implementation
    , List.map collateral ~f:(fun c -> Resource_record.Source.Collateral c) )
;;

let register_exn t ~name request =
  check_open t ~operation:"register";
  let path = Scope.path t.scope |> Scope.Path.to_list |> List.rev in
  let id = Resource_id.create_exn ~path ~name in
  if Map.mem t.shared.records id
  then
    raise_s
      [%message
        "duplicate resource instance; give each instance in a scope a distinct name"
          ~instance:(id : Resource_id.t)
          (request : Resource_request.t)];
  let { mode; technology; policy; _ } = t.shared in
  let record =
    let%bind.Or_error requirement, applied = Resource_policy.lookup policy id in
    let%map.Or_error selection = Selection.select ~technology ~requirement request in
    let elaborated_as, sources = sources_of ~mode ~technology request selection in
    { Resource_record.id
    ; request
    ; requirement
    ; policy = applied
    ; selection
    ; elaborated_as
    ; sources
    }
  in
  match record with
  | Error error ->
    Error.raise
      (Error.tag_s
         error
         ~tag:
           [%message
             "resource selection failed"
               ~instance:(id : Resource_id.t)
               (request : Resource_request.t)])
  | Ok record ->
    t.shared.records <- Map.set t.shared.records ~key:id ~data:record;
    record
;;

module Private = struct
  let create ~mode ~technology ~policy ~scope =
    { shared =
        { mode
        ; technology
        ; policy
        ; database = Scope.circuit_database scope
        ; state = Open
        ; records = Map.empty (module Resource_id)
        }
    ; scope
    }
  ;;

  let finalize t =
    check_open t ~operation:"finalize";
    let records = Map.data t.shared.records in
    let unmatched_rules =
      List.filter (Resource_policy.rules t.shared.policy) ~f:(fun rule ->
        not
          (List.exists records ~f:(fun record ->
             Resource_policy.Selector.matches rule.selector record.id)))
    in
    match unmatched_rules with
    | [] ->
      t.shared.state <- Finalized;
      Ok records
    | _ :: _ ->
      t.shared.state <- Failed;
      Or_error.error_s
        [%message
          "implementation policy rules match no registered resource"
            (unmatched_rules : Resource_policy.Rule.t list)
            ~registered:(List.map records ~f:(fun r -> r.id) : Resource_id.t list)]
  ;;

  let fail t = t.shared.state <- Failed
end
[@@@ocamlformat "enable"]
