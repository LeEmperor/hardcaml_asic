open Hardcaml_asic_execution
let () =
  try
    let run = ref None and output = ref None and context = ref None and state = ref None in
    let stdout = ref false and json = ref false and quiet = ref false and verbose = ref false in
    let args=Array.to_list Sys.argv |> List.tl in
    let rec parse = function
      | [] -> ()
      | "--run-dir"::s::xs -> run:=Some s; parse xs
      | "--output"::s::xs -> output:=Some s; parse xs
      | "--context"::s::xs -> context:=Some (Evidence_json.value (Evidence_json.read s)); parse xs
      | "--synthesis-state"::s::xs -> state:=Some s; parse xs
      | "--stdout"::xs -> stdout:=true; parse xs
      | "--json"::xs -> json:=true; parse xs
      | "--quiet"::xs -> quiet:=true; parse xs
      | "--verbose"::xs -> verbose:=true; parse xs
      | "--help"::_ -> print_endline "collect --run-dir RUN [--output FILE | --stdout] [--json] [--quiet] [--verbose] [--context FILE --synthesis-state FILE]"; exit 0
      | s::_ -> invalid_arg ("unknown collect argument: "^s) in
    parse args;
    let directory=match !run with Some s -> Unix.realpath s | None -> invalid_arg "--run-dir is required" in
    if !stdout && !output<>None then invalid_arg "--stdout and --output are mutually exclusive";
    let destination=Option.value !output ~default:(Filename.concat directory "results.json") in
    let result=Collect_service.collect ?context:!context ?synthesis_state:!state directory in
    if not !stdout then Collect_service.save destination result;
    if !stdout || !json then print_string (Evidence_json.record_bytes (Collect_service.to_json result))
    else if not !quiet then print_endline ("collect: results "^destination);
    if !verbose then List.iter (fun (k,v) -> prerr_endline ("collect "^k^": "^Evidence_json.repr v))
      (match Collect_service.to_json result with `Assoc xs -> xs | _ -> assert false)
  with
  | Invalid_argument s | Sys_error s | Yojson.Json_error s -> prerr_endline ("collect: "^s); exit 2
  | Unix.Unix_error (e,fn,p) -> prerr_endline ("collect: "^fn^" "^p^": "^Unix.error_message e); exit 2
