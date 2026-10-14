(* CLI4 plain-text stage views. Payloads are the authoritative Runner records. *)
module J = Hardcaml_asic_execution.Identity_json
let get value key = match value with J.Object xs -> Option.value (List.assoc_opt key xs) ~default:J.null | _ -> J.null
let list = function J.Array xs -> xs | _ -> []
let text ?(missing="not recorded") = function
  | J.Null -> missing | J.String "" -> "empty" | J.String s -> s
  | J.Bool true -> "yes" | J.Bool false -> "no" | j -> J.canonical j
let field ?missing label value = Printf.printf "%-22s %s\n" label (text ?missing value)
let string s = match J.string s with Ok j -> j | Error _ -> assert false
let section s = print_endline ("\n" ^ s)
let allocation value =
  field "allocation" (get value "event"); field "attempt" (get value "attempt");
  field "stream" (get value "stream_id");
  print_endline "Requested operation has not completed; this is an allocation receipt."; flush stdout
let error path detail =
  field "stage execution" (string path); field "inspection" (string "failed"); field "error" (string detail);
  print_endline "\nNo successful inspection or readiness conclusion is available."
let execution ~workspace value =
  let plan = get value "plan" in
  let sequence = list (get plan "stages") in
  field "execution attempt" (get value "attempt_id");
  field "execution record" (string (workspace ^ "/execution-" ^ text (get value "attempt_id") ^ ".json"));
  field "requested endpoint" (match List.rev sequence with x::_ -> x | [] -> get plan "endpoint");
  field "recorded plan" (string (match sequence with [] -> "through " ^ text (get plan "endpoint")
    | xs -> String.concat " -> " (List.map text xs)));
  field ~missing:"none recorded" "initial boundary" (match get plan "initial_boundary" with
    | J.Null when get plan "resume" = J.bool true -> string "synthesis" | x -> x);
  field "status" (get value "status"); field "exit" (get value "exit_code");
  section "STAGES (recorded durations)";
  let occurrences = list (get value "occurrences") in
  if occurrences=[] then print_endline "  none recorded";
  List.iter (fun o ->
    let status = text (get o "status") in
    let duration = if List.mem status ["completed";"failed";"interrupted"] then
      (match get o "duration_seconds" with J.Float f -> Printf.sprintf "%.3f s" f
        | J.Integer n -> Printf.sprintf "%.3f s" (float_of_string n) | _ -> "n/a s")
      else "n/a (no finished duration)" in
    Printf.printf "  %-28s %-12s %s   exit %s\n" (text (get o "action_key")) status duration (text (get o "exit_code"));
    if get o "error" <> J.null then Printf.printf "    error: %s\n" (text (get o "error"))) occurrences;
  section "ARTIFACT REFERENCES (historical publication, not current readiness)";
  let artifacts = list (get value "artifacts") in
  if artifacts=[] then print_endline "  none recorded";
  List.iter (fun a -> Printf.printf "  %s: %s\n    identity %s\n" (text (get a "boundary"))
    (text (get a "path")) (text (get a "identity"))) artifacts;
  section "COMPLETION AND ACCEPTANCE";
  field "requested completion" (string (if get value "status" = string "completed" then "completed" else "not established"));
  let physical = List.exists (fun a -> get a "boundary" = string "signoff") artifacts
    && List.exists (fun o -> get o "action_key" = string "implementation.signoff" && get o "status" = string "completed") occurrences in
  field "full physical flow" (string (if physical then "completed" else "not_recorded"));
  field "acceptance" (string "not_evaluated"); field "external postcheck" (string "not_evaluated");
  print_endline "\nEndpoint completion does not establish acceptance. Interrupted is not an acceptance rejection."
