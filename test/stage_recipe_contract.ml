open! Core
open Hardcaml_asic

module S = Flow.Stage
module R = Flow.Recipe

let name stage = `String (S.to_string stage)
let source_json = function None -> `Null | Some stage -> name stage
let input_json = function
  | R.Input.Bundle -> `String "bundle"
  | Checkpoint stage -> `String (S.to_string stage ^ "_checkpoint")
;;

let describe recipe =
  `Assoc
    [ "recipe", R.to_yojson recipe
    ; "rendered", `String (R.to_string recipe)
    ; "endpoint", name (R.endpoint recipe)
    ; "source", source_json (R.initial_boundary recipe)
    ; "required_input", input_json (R.required_input recipe)
    ; "declarations", `List (List.map (R.declarations recipe) ~f:(fun d ->
        `Assoc [ "stage", name d.stage; "input", input_json d.input
               ; "output", `String (S.to_string d.output_checkpoint ^ "_checkpoint") ]))
    ]
;;

let result_json = function Ok recipe -> describe recipe | Error _ -> `Null

let rec sequences n =
  if n = 0 then [ [] ] else
    List.concat_map S.all ~f:(fun stage -> List.map (sequences (n - 1)) ~f:(fun rest -> stage :: rest))
;;

let () =
  List.iter S.all ~f:(fun stage -> assert (S.equal (Or_error.ok_exn (S.of_string (S.to_string stage))) stage));
  assert (Or_error.is_error (S.of_string "CTS"));
  let sources = None :: List.map S.all ~f:Option.some in
  let candidates = List.concat_map [ 0; 1; 2; 3 ] ~f:sequences in
  let cases = List.concat_map sources ~f:(fun source ->
    List.map candidates ~f:(fun requested ->
      `Assoc [ "source", source_json source; "requested", `List (List.map requested ~f:name)
             ; "result", result_json (R.create ?initial_boundary:source requested) ])) in
  let through = List.concat_map sources ~f:(fun source ->
    List.map S.all ~f:(fun endpoint ->
      `Assoc [ "source", source_json source; "endpoint", name endpoint
             ; "result", result_json (R.through ?initial_boundary:source endpoint) ])) in
  let compose = List.concat_map S.all ~f:(fun middle ->
    let first = R.through middle |> Or_error.ok_exn in
    List.filter_map S.all ~f:(fun endpoint ->
      match R.through ~initial_boundary:middle endpoint with
      | Error _ -> None
      | Ok second ->
        let combined = R.compose first second |> Or_error.ok_exn in
        assert (String.equal (R.to_string combined) (R.to_string (R.through endpoint |> Or_error.ok_exn)));
        assert (Or_error.is_error (R.compose second first));
        Some (describe combined))) in
  let resumed = R.through ~initial_boundary:S.Floorplan S.Placement |> Or_error.ok_exn in
  let tail = R.through ~initial_boundary:S.Placement S.Signoff |> Or_error.ok_exn in
  let joined = R.compose resumed tail |> Or_error.ok_exn in
  assert (Option.equal S.equal (R.initial_boundary joined) (Some S.Floorplan));
  let capabilities = `Assoc (List.map S.all ~f:(fun stage ->
    let c = S.capability stage in
    assert (S.Closure_scope.equal c.closure_scope Path_bound);
    assert (S.Acceptance.equal c.acceptance Not_evaluated);
    S.to_string stage, `Assoc
      [ "endpoint", `String c.endpoint; "successor", Option.value_map c.successor ~default:`Null ~f:(fun s -> `String s)
      ; "restart_targets", `List (List.map c.restart_targets ~f:name)
      ; "restart_supported", `Bool (not (List.is_empty c.restart_targets))
      ; "tested_image_id", `String c.tested_image_id
      ; "closure_scope", `String "path_bound"; "acceptance", `String "not_evaluated" ])) in
  printf "%s\n" (Yojson.Safe.to_string (`Assoc
    [ "cases", `List cases; "through", `List through; "composed", `List (describe joined :: compose)
    ; "stage_order", `List (List.map S.all ~f:name)
    ; "capabilities", capabilities ]))
;;
