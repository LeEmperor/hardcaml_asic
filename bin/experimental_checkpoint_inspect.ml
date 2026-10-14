open Hardcaml_asic_execution
module C = Checkpoint
module J = Identity_json
let unwrap = function Ok x -> x | Error s -> failwith s
let js s = match J.string s with Ok x -> x | Error e -> failwith (J.error_message e)
let emit j = print_endline (J.canonical j)
let field k v = Printf.printf "%-22s %s\n" k (if v = "" then "empty" else v)
let human ~path ~source ~restart_to t =
  field "checkpoint" path;
  field "identity" t.C.identity;
  field "boundary" (C.Stage.to_string t.boundary);
  field "bound location" t.location;
  print_endline "\nVALIDATION AND CONTINUATION";
  field "host validation" "passed (host_only)";
  field "compatibility source" source;
  field "runtime validated" "no";
  field "closure scope" (if t.schema = C.Schema_1 then "path-bound (schema 1)" else "path_bound");
  field "restart supported" (if t.restart_targets <> [] then "yes" else "no");
  field "supported targets" (match t.restart_targets with [] -> "none" | xs -> String.concat ", " (List.map C.Stage.to_string xs));
  field "requested restart-to" (match restart_to with None -> "not requested" | Some s -> C.Stage.to_string s);
  if restart_to <> None then field "transition validation" "passed; no execution performed";
  field "tested image" (if t.schema = C.Schema_1 then "not recorded" else (C.Stage.capability t.boundary).tested_image_id);
  print_endline "\nINVENTORIES";
  let image_count = List.length (List.filter (fun (n, _) -> String.starts_with ~prefix:"/nix/store/" n) t.external_files) in
  field "checkpoint files" (string_of_int (List.length t.files));
  field "external dependencies" (string_of_int (List.length t.external_files));
  field "host dependencies" (string_of_int (List.length t.external_files - image_count));
  field "image-only dependencies" (string_of_int image_count);
  print_endline "\nACCUMULATED METRICS (not fresh boundary measurements)";
  let metrics = match t.metrics with J.Object xs -> xs | _ -> assert false in
  let unavailable = List.filter (fun (_, v) -> match v with J.Object xs -> List.assoc_opt "availability" xs = Some (js "unavailable") | _ -> false) metrics in
  field "available values" (string_of_int (List.length metrics - List.length unavailable));
  field "unavailable values" (string_of_int (List.length unavailable));
  List.iteri (fun i (name, v) -> if i < 5 then (
    let xs = match v with J.Object xs -> xs | _ -> [] in
    let reason = match List.assoc_opt "reason" xs, List.assoc_opt "unavailable_reason" xs with
      | Some (J.String s), _ when s <> "" -> s | _, Some (J.String s) when s <> "" -> s | _ -> "reason not recorded" in
    Printf.printf "  %s: unavailable (%s)\n" name reason)) (List.sort (fun (a, _) (b, _) -> String.compare a b) unavailable);
  if List.length unavailable > 5 then Printf.printf "  %d more unavailable values; use --json for complete evidence\n" (List.length unavailable - 5);
  print_endline "\nACCEPTANCE";
  field "acceptance" "not_evaluated";
  print_endline "\nHost inspection passed; runtime/image closure and full-flow acceptance are not established."
let () =
  let json = ref false and compatibility = ref None and restart = ref None and path = ref None in
  let usage = "hardcaml-asic-experimental-checkpoint-inspect [--json] [--compatibility FILE] [--restart-to STAGE] CHECKPOINT\nRead-only host validation; recorded compatibility by default, no runtime readiness." in
  try
    let rec args = function
      | [] -> ()
      | ("--help" | "-h") :: _ -> print_endline usage; exit 0
      | "--json" :: xs -> json := true; args xs
      | "--compatibility" :: v :: xs -> compatibility := Some v; args xs
      | "--restart-to" :: v :: xs ->
        restart := Some (match List.find_opt (fun s -> C.Stage.to_string s = v) C.Stage.all with
          | Some s -> s | None -> failwith "unknown restart boundary"); args xs
      | v :: xs when not (String.starts_with ~prefix:"-" v) && !path = None -> path := Some v; args xs
      | _ -> failwith usage in
    args (List.tl (Array.to_list Sys.argv));
    let path = unwrap (C.absolute_path (match !path with Some p -> p | None -> failwith usage)) in
    let expected, source = match !compatibility with
      | None -> (unwrap (C.read path)).compatibility, `Recorded
      | Some p -> (match Result_store.read_json (unwrap (C.absolute_path p)) with Ok j -> j | Error e -> failwith (J.error_message e)), `Expected in
    let t = unwrap (C.validate ?restart_to:!restart ~compatibility:expected path) in
    if !json then emit (C.inspection ~compatibility_source:source t)
    else human ~path ~source:(match source with `Expected -> "expected" | `Recorded -> "recorded") ~restart_to:!restart t
  with
  | Failure s | Sys_error s ->
    prerr_endline ("checkpoint-inspect: " ^ s);
    if !json then emit (match J.object_ ["validation", js "host_only"; "error", js s] with Ok j -> j | Error _ -> assert false)
    else (
      field "checkpoint" (match !path with Some p -> p | None -> "not recorded");
      field "inspection" "failed"; field "error" s;
      print_endline "\nNo successful inspection or readiness conclusion is available.");
    exit 2
  | Unix.Unix_error (e, op, p) ->
    let s = op ^ ": " ^ p ^ ": " ^ Unix.error_message e in
    prerr_endline ("checkpoint-inspect: " ^ s);
    if !json then emit (match J.object_ ["validation", js "host_only"; "error", js s] with Ok j -> j | Error _ -> assert false);
    exit 2
