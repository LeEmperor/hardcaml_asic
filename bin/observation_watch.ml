(* The foreground command scopes process-global handlers on the main thread. *)
[@@@alert "-unsafe_multidomain"]
open Hardcaml_asic_execution
module O = Observation
module J = Identity_json
let json_value = function Ok v -> v | Error e -> invalid_arg (J.error_message e)
let str s = json_value (J.string s)
let integer n = json_value (J.integer (string_of_int n))

let get value key = match value with
  | J.Object fields -> Option.value (List.assoc_opt key fields) ~default:J.null
  | _ -> J.null
let items = function J.Array xs -> xs | _ -> []
let text = function
  | J.Null -> "not recorded" | J.Bool true -> "yes" | J.Bool false -> "no"
  | J.String "" -> "empty" | J.String s -> s | value -> J.canonical value
let present = function J.Null | J.String "" -> false | _ -> true
let output s = output_string stdout (s ^ "\n"); flush stdout
let field label value = output (Printf.sprintf "%-22s %s" label (text value))
let fields value pairs = List.iter (fun (label,key) -> field label (get value key)) pairs
let updates ?(elide=false) directory value =
  field "observation" (str directory);
  fields value ["stream","stream_id"; "requested after","after"; "cursor","cursor"];
  let events = items (get value "events") in
  let count=List.length events in
  field "updates returned" (integer count);
  output "\nUPDATES (recorded events; not a current readiness check)";
  if events=[] then output "  none after the requested cursor; no new outcome is implied";
  List.iteri (fun index event ->
    if elide && count>20 && index=10 then
      output (Printf.sprintf "  ... %d events omitted; use --json for all events" (count-20));
    if not elide || count<=20 || index<10 || index>=count-10 then (
    let data = get event "data" in
    let occurrence = get data "occurrence" and artifact = get data "artifact" in
    let name = text (get event "event") in
    let detail = if occurrence <> J.null then
        Printf.sprintf " %s: %s" (text (get occurrence "action_key")) (text (get occurrence "status"))
      else if name = "outcome" then
        Printf.sprintf " %s; exit %s" (text (get data "status")) (text (get data "exit_code"))
      else if name = "planned" then
        let plan = get data "plan" in
        let stages = items (get plan "stages") in
        " " ^ (if stages = [] then text (get plan "endpoint") else String.concat " -> " (List.map text stages))
      else "" in
    let timing = match get event "recorded_at" with
      | J.Null -> ""
      | recorded -> Printf.sprintf " [recorded %s; +%.3fs]" (text recorded)
          (float_of_string (J.canonical (get event "elapsed_seconds"))) in
    output (Printf.sprintf "  %4s %s%s%s" (text (get event "sequence")) name detail timing);
    if artifact <> J.null then output (Printf.sprintf "       published %s: %s"
      (text (get artifact "boundary")) (text (get artifact "path")));
    let error = get data "error" in
    let error = if present error then error else get occurrence "error" in
    if present error then output ("       error: " ^ text error))) events;
  output "\nCursor covers all returned events. Use this stream and cursor for the next read;\na recorded interruption is not an acceptance rejection."
let status value =
  fields value ["stream","stream_id"; "cursor","cursor"; "reader status","observation_status"; "writer active","writer_active"];
  let outcome = get value "outcome" in
  if outcome <> J.null then (
    fields outcome ["recorded outcome","status"; "execution exit code","exit_code"];
    if present (get outcome "error") then field "execution error" (get outcome "error"));
  let results = get value "final_results" in
  fields results ["physical_completion","physical_completion"; "acceptance","acceptance"; "external_postcheck","external_postcheck"];
  let refs = items (get results "checkpoint_refs") in
  field "recorded checkpoints" (integer (List.length refs));
  List.iter (fun ref -> output (Printf.sprintf "  %s: %s" (text (get ref "boundary")) (text (get ref "path")))) refs

exception Interrupted
exception Query_error of O.error
let checked = function Ok x -> x | Error e -> raise (Query_error e)
let invalid detail = raise (Query_error {O.code=O.Reset_required; detail})
let run directory flags =
  let json = ref false in
  let interrupted = ref false in
  let check_interrupt () = if !interrupted then raise Interrupted in
  let old_int = Sys.signal Sys.sigint (Sys.Signal_handle (fun _ -> interrupted := true)) in
  let old_pipe = Sys.signal Sys.sigpipe Sys.Signal_ignore in
  Fun.protect ~finally:(fun () -> ignore (Sys.signal Sys.sigint old_int); ignore (Sys.signal Sys.sigpipe old_pipe)) (fun () ->
    try
      let rec parse stream after interval = function
        | [] -> stream, after, interval
        | "--json"::rest when not !json -> json := true; parse stream after interval rest
        | "--stream-id"::id::rest when stream=None -> parse (Some id) after interval rest
        | "--after"::n::rest when after=None ->
          let n = match J.parse n with
            | Ok (J.Integer n) -> (try int_of_string n with Failure _ -> invalid "cursor outside retained prefix")
            | _ -> invalid "after must be an integer" in
          parse stream (Some n) interval rest
        | "--interval"::n::rest ->
          let n = try float_of_string n with Failure _ -> invalid "interval must be positive and finite" in
          if not (Float.is_finite n) || n <= 0. then invalid "interval must be positive and finite";
          parse stream after n rest
        | _ -> invalid "invalid watch arguments" in
      let stream_id, after, interval = parse None None 0.5 flags in
      let reader = checked (O.Reader.create ?stream_id ?after directory) in
      let emit kind value = if !json then
          match value with J.Object xs -> output (J.canonical (json_value (J.object_ (("event",str kind)::xs)))) | _ -> assert false
        else if kind="updates" then updates directory value else status value in
      let rec loop previous =
        check_interrupt ();
        let u,s = checked (O.Reader.poll reader) in
        check_interrupt ();
        if items (get u "events") <> [] then emit "updates" u;
        if Some s <> previous then emit "status" s;
        check_interrupt ();
        if get s "outcome" <> J.null then 0
        else if get s "writer_active" <> J.bool true then 3
        else (
          let rec wait remaining =
            check_interrupt ();
            if remaining > 0. then (
              let step = min remaining 0.05 in
              Unix.sleepf step; wait (remaining -. step)) in
          wait interval; loop (Some s)) in
      loop None
    with
    | Interrupted -> 130
    | Sys_error _ | Unix.Unix_error _ -> if !interrupted then 130 else 2
    | Query_error e ->
      prerr_endline ("observation watch: " ^ e.detail);
      (try if !json then output (J.canonical (O.error_json e)) else (
        field "observation" (str directory); field "inspection" (str "failed");
        field "error code" (str (O.error_code_name e.code)); field "error" (str e.detail);
        output "\nNo successful inspection or readiness conclusion is available.")
       with Sys_error _ | Unix.Unix_error _ -> ());
      2)
