open! Core

let find_id values ~id ~get = List.find values ~f:(fun v -> Selection.Id.equal (get v) id)

module Entry = struct
  type t =
    { methodology : Methodology.t
    ; profiles : Profile.t list
    ; default_profile : Selection.Id.t
    }
  let create ~methodology ~profiles ~default_profile =
    let open Or_error.Let_syntax in
    let%bind default_profile = Selection.Id.create default_profile in
    let%bind () =
      match List.find_a_dup profiles ~compare:(fun a b -> Selection.Id.compare (Profile.id a) (Profile.id b)) with
      | Some p -> Or_error.errorf "Duplicate profile ID %s" (Selection.Id.to_string (Profile.id p))
      | None -> Ok ()
    in
    let%bind () =
      if Option.is_none (find_id profiles ~id:default_profile ~get:Profile.id)
      then Or_error.errorf "Unknown per-flow default profile %s" (Selection.Id.to_string default_profile)
      else Ok ()
    in
    let%map () = Or_error.combine_errors_unit (List.map profiles ~f:(fun p ->
      Parameter.check_assignments ~configurable:(Methodology.configurable methodology) (Profile.assignments p)
      |> Or_error.map ~f:(fun _ -> ())
      |> Or_error.tag ~tag:("Profile " ^ Selection.Id.to_string (Profile.id p)))) in
    { methodology
    ; profiles = List.sort profiles ~compare:(fun a b -> Selection.Id.compare (Profile.id a) (Profile.id b))
    ; default_profile }
  ;;
  let methodology t = t.methodology
  let profiles t = t.profiles
  let default_profile t = t.default_profile
end

type t = { entries : Entry.t list; default : Selection.t }
let entries t = t.entries
let default t = t.default
let entry_id e = Methodology.id (Entry.methodology e)
let lookup_entry entries id =
  match find_id entries ~id ~get:entry_id with
  | Some e -> Ok e
  | None -> Or_error.errorf "Unknown flow ID %s; select a declared flow" (Selection.Id.to_string id)
;;
let lookup_profile entry id =
  match find_id (Entry.profiles entry) ~id ~get:Profile.id with
  | Some p -> Ok p
  | None -> Or_error.errorf "Unknown profile ID %s for flow %s" (Selection.Id.to_string id) (Selection.Id.to_string (entry_id entry))
;;
let create ~entries ~default_flow ~default_profile =
  let open Or_error.Let_syntax in
  let%bind default = Selection.create ~flow:default_flow ~profile:default_profile () in
  let%bind () =
    match List.find_a_dup entries ~compare:(fun a b -> Selection.Id.compare (entry_id a) (entry_id b)) with
    | Some e -> Or_error.errorf "Duplicate flow ID %s" (Selection.Id.to_string (entry_id e))
    | None -> Ok ()
  in
  let%bind flow_id = Selection.Id.create default_flow in
  let%bind profile_id = Selection.Id.create default_profile in
  let%bind entry = lookup_entry entries flow_id in
  let%map _ = lookup_profile entry profile_id in
  { entries = List.sort entries ~compare:(fun a b -> Selection.Id.compare (entry_id a) (entry_id b)); default }
;;

type resolved =
  { declaration : t
  ; entry : Entry.t
  ; profile : Profile.t
  ; endpoint : Stage_id.t
  ; stages : Stage_id.t list
  ; parameters : Parameter.resolved list
  }
let resolve ?(selection = Selection.default) ?(request = []) t ~endpoint () =
  let open Or_error.Let_syntax in
  let selection = if Option.is_none (Selection.flow selection) then t.default else selection in
  (* Catalog construction guarantees the default has a flow. *)
  let%bind entry = lookup_entry t.entries (Option.value_exn (Selection.flow selection)) in
  let profile_id = Option.value (Selection.profile selection) ~default:(Entry.default_profile entry) in
  let%bind profile = lookup_profile entry profile_id in
  let methodology = Entry.methodology entry in
  let%bind stages = Methodology.stages methodology ~endpoint in
  let%map parameters = Parameter.resolve ~configurable:(Methodology.configurable methodology)
    ~methodology:(Methodology.defaults methodology) ~profile:(Profile.assignments profile) ~request in
  { declaration = t; entry; profile; endpoint; stages; parameters }
;;
let entry t = t.entry
let profile t = t.profile
let endpoint t = t.endpoint
let stages t = t.stages
let parameters t = t.parameters
let declaration t = t.declaration
