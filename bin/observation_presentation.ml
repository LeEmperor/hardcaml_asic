open Observation_watch
let section s = output ("\n"^s)
let description value =
  fields value ["contract","contract";"schema","schema_version";"scope","scope";"cursor","cursor"];
  field "events" (str (String.concat " -> " (List.map text (items (get value "events")))));
  section "CAPABILITIES";
  (match get value "capabilities" with J.Object xs -> List.iter (fun (k,v) -> field k v) xs | _ -> ());
  fields value ["writer_policy","writer_policy";"retention","retention";"lost_writer","lost_writer"];
  output "\nUse --json for the complete event and response schemas."
let inspection directory value =
  let state=get value "state" in
  let plan=get state "plan" and request=get state "request" and outcome=get state "outcome" in
  let sequence=items (get plan "stages") in
  let endpoint=match List.rev sequence with x::_ -> x | [] -> get plan "endpoint" in
  field "observation" (str directory);
  fields value ["stream","stream_id";"cursor","cursor"];
  field "requested endpoint" (if present endpoint then endpoint else get request "endpoint");
  field "requested plan file" (get request "plan");
  field "recorded plan" (if sequence<>[] then str (String.concat " -> " (List.map text sequence))
    else if present endpoint then str ("through "^text endpoint) else J.null);
  field "initial boundary" (match get plan "initial_boundary" with
    | J.Null -> str (if get plan "resume"=J.bool true then "synthesis" else "none recorded") | x -> x);
  field "outcome" (match get outcome "status" with J.Null -> str "not recorded (nonterminal prefix)" | x -> x);
  field "execution exit" (get outcome "exit_code");
  field "observation status" (get value "observation_status");
  field "writer active" (match get value "writer_active" with J.Null -> str "unknown" | x -> x);
  field "phase" (get state "phase");
  if get outcome "error"<>J.null then field "execution error" (get outcome "error");
  section "STAGES (recorded durations)";
  let occurrences=items (get state "occurrences") in
  if occurrences=[] then output "  none recorded";
  List.iter (fun item ->
    let status=text (get item "status") in
    let duration=if List.mem status ["completed";"failed";"interrupted"] then
      Hardcaml_asic_execution.Report_service.number (match get item "duration_seconds" with
        | J.Float f -> `Float f | J.Integer s -> `Intlit s | _ -> `Null)^" s"
      else "n/a (no finished duration)" in
    output (Printf.sprintf "  %-28s %-12s %s   exit %s" (text (get item "action_key")) status duration (text (get item "exit_code")));
    if get item "error"<>J.null then output ("    error: "^text (get item "error"))) occurrences;
  section "ARTIFACT REFERENCES (historical publication, not current readiness)";
  let artifacts=items (get state "artifacts") in
  if artifacts=[] then output "  none recorded";
  List.iter (fun a -> output (Printf.sprintf "  %s: %s\n    identity %s" (text (get a "boundary")) (text (get a "path")) (text (get a "identity")))) artifacts;
  fields state ["workspace","workspace";"checkpoint store","checkpoint_store";"preflight reference","preflight_record";"runtime reference","runtime_record"];
  section "COMPLETION AND ACCEPTANCE";
  field "requested completion" (str (if get outcome "status"=str "completed" then "completed (recorded outcome)" else "not established by recorded outcome"));
  fields (get value "final_results") ["full physical flow","physical_completion";"acceptance","acceptance";"external postcheck","external_postcheck"];
  output "\nRecorded endpoint completion does not establish full-flow acceptance or current runtime readiness."
let error directory value =
  field "observation" (str directory);field "inspection" (str "failed");
  fields (get value "error") ["error code","code";"error","detail"];
  output "\nNo successful inspection or readiness conclusion is available."
