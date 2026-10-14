open Hardcaml_asic_execution
module O = Observation
module J = Identity_json
let emit value = print_endline (J.canonical value)
let usage = "Usage: hardcaml-asic-experimental-observation-read describe\n       hardcaml-asic-experimental-observation-read inspect DIRECTORY\n       hardcaml-asic-experimental-observation-read read-updates DIRECTORY --stream-id ID [--after INTEGER]\n       hardcaml-asic-experimental-observation-read watch DIRECTORY [--json] [--interval SECONDS] [--stream-id ID --after INTEGER]\nHost-only read-only queries and foreground watch; no producer mutation."
let invalid detail = Error {O.code=O.Reset_required;detail}
let query arguments = match arguments with
  | [_;"describe"] -> Ok (O.describe ())
  | [_;"inspect";directory] -> O.inspect directory
  | _::"read-updates"::directory::flags ->
    let rec parse stream after = function
      | [] -> (match stream with None -> invalid "stream-id is required" | Some stream_id ->
        let after=Option.value after ~default:"0" in
        (match J.parse after with
         | Ok (J.Integer s) -> (try O.read_updates directory ~stream_id ~after:(int_of_string s) with Failure _ -> invalid "cursor outside retained prefix")
         | _ -> invalid "after must be an integer"))
      | "--stream-id"::id::rest when stream=None -> parse (Some id) after rest
      | "--after"::n::rest when after=None -> parse stream (Some n) rest
      | _ -> invalid "invalid query arguments" in
    parse None None flags
  | _ -> invalid usage
let () =
  match Array.to_list Sys.argv with
  | _::"watch"::directory::flags ->
    let code = Observation_watch.run directory flags in
    (* Do not flush a failed buffered stdout again during runtime shutdown. *)
    if code = 2 then (try
      let sink = Unix.openfile "/dev/null" [Unix.O_WRONLY] 0 in
      Fun.protect ~finally:(fun () -> Unix.close sink) (fun () -> Unix.dup2 sink Unix.stdout)
      with _ -> ());
    exit code
  | [_;"--help"] -> print_endline usage
  | arguments ->
    let public=List.mem "--public-cli4" arguments and json=List.mem "--json" arguments in
    let arguments=List.filter (fun s -> s<>"--public-cli4" && s<>"--json") arguments in
    let query_name=match arguments with _::q::_ -> q | _ -> "query" in
    let path=match arguments with _::_::p::_ -> p | _ -> "describe" in
    match query arguments with
    | Ok j -> if not public || json then emit j else (
      match query_name with
      | "describe" -> Observation_presentation.description j
      | "read-updates" -> Observation_watch.updates ~elide:true path j
      | _ -> Observation_presentation.inspection path j)
    | Error e ->
      let j=O.error_json e in
      if not public || json then emit j else Observation_presentation.error path j;
      if public then prerr_endline ("observation "^query_name^": "^e.detail);
      exit 2
