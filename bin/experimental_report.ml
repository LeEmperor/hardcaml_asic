open Hardcaml_asic_execution
let () =
  try
    let run=ref None and target=ref None and context=ref None and state=ref None in
    let json=ref false and diagnostics_only=ref false and verbose=ref false in
    let rec parse = function
      | [] -> ()
      | "--run-dir"::s::xs -> run:=Some s; parse xs
      | "--target"::s::xs -> target:=Some s; parse xs
      | "--context"::s::xs -> context:=Some (Evidence_json.value (Evidence_json.read s)); parse xs
      | "--synthesis-state"::s::xs -> state:=Some s; parse xs
      | "--json"::xs -> json:=true; parse xs
      | "--diagnostics-only"::xs -> diagnostics_only:=true; parse xs
      | "--verbose"::xs -> verbose:=true; parse xs
      | "--help"::_ -> print_endline "report --target TARGET [--json] [--verbose]\nPrivate diagnostic interface: --run-dir RUN [--diagnostics-only] [--context FILE --synthesis-state FILE]"; exit 0
      | s::_ -> invalid_arg ("unknown report argument: "^s) in
    parse (Array.to_list Sys.argv |> List.tl);
    (match !target with None -> () | Some path ->
      if !run<>None || !context<>None || !state<>None || !diagnostics_only then invalid_arg "--target conflicts with private run diagnostic options";
      let selected=match Stage_report_service.select path with Ok t -> t | Error e -> invalid_arg e in
      match selected with
      | Stage_report_service.Coarse_run directory -> run:=Some directory
      | _ ->
        let report=match Stage_report_service.run ~verbose:!verbose selected with Ok r -> r | Error e -> invalid_arg e in
        if !json then (prerr_string report.human;print_endline (Identity_json.canonical report.envelope))
        else print_string report.human;
        exit 0);
    let directory=match !run with Some s -> Unix.realpath s | None -> invalid_arg "--run-dir is required" in
    let result=Report_service.run ?context:!context ?synthesis_state:!state directory in
    let status=Report_service.exit_code result.verdict in
    if !diagnostics_only then (
      if status<>0 || !verbose then prerr_string result.human)
    else if !json then prerr_string result.human else print_string result.human;
    if !verbose then prerr_endline ("report: run "^directory^"; result source "^result.source^"; acceptance exit "^string_of_int status);
    if !json && not !diagnostics_only then print_string (Evidence_json.record_bytes result.results);
    exit status
  with
  | Invalid_argument s | Sys_error s | Yojson.Json_error s -> prerr_endline ("report: "^s); exit 2
  | Unix.Unix_error (e,fn,p) -> prerr_endline ("report: "^fn^" "^p^": "^Unix.error_message e); exit 2
