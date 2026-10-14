open Hardcaml_asic_execution
module S = Preflight_service
module J = Identity_json
let () =
  let values = Hashtbl.create 12 and native = ref false and json = ref false and verbose = ref false in
  let value name = Hashtbl.find values name in
  let specs = List.map (fun name -> "--" ^ name,Arg.String (fun x -> Hashtbl.replace values name x),name)
    ["bundle";"support-tools";"pdk-root";"python";"resources";"results-root";"output"] @
    ["--native",Arg.Set native,"native runtime";"--json",Arg.Set json,"JSON report";
     "--verbose",Arg.Set verbose,"verbose diagnostics"] in
  try
    Arg.parse specs (fun _ -> raise (Arg.Bad "unexpected argument")) "Standalone preflight";
    let result = S.run ~bundle:(value "bundle") ~support_tools:(value "support-tools")
      ~pdk_root:(value "pdk-root") ~python:(value "python") ~resources:(value "resources")
      ~results_root:(value "results-root") ~environment:(Array.to_list (Unix.environment ()))
      ?output:(Hashtbl.find_opt values "output") ~native:!native () in
    if !json then (print_string (Result_store.record_bytes result.report);
      Printf.eprintf "preflight: %sreport %s\n"
        (if result.report_published then "" else "unpublished ") result.report_path)
    else (Printf.printf "preflight: %s\n" (Result_store.status_name result.status);
      Option.iter (Printf.printf "%soperation: %s\n"
        (if result.receipt_published then "" else "unpublished ")) result.receipt_path;
      Printf.printf "%sreport: %s\n"
        (if result.report_published then "" else "unpublished ") result.report_path);
    (match result.report with J.Object fields ->
      (match List.assoc_opt "issues" fields with Some (J.Array issues) -> List.iter (fun issue ->
        Printf.eprintf "preflight: %s\n" (match issue with J.String x -> x | x -> S.python_repr x)) issues | _ -> ());
      if !verbose then List.iter (fun key -> Option.iter (fun v ->
        Printf.eprintf "preflight %s: %s\n" key (match v with J.String x -> x | x -> S.python_repr x))
        (List.assoc_opt key fields))
        ["waivers";"references";"requested";"actual";"runtime_contract";"support_tools";"pdk_root";"python";"execution_binding";"diagnostic"]
      | _ -> ());
    exit result.exit_code
  with e -> Printf.eprintf "hardcaml-asic-flow: %s\n"
    (match e with Failure x | Invalid_argument x -> x | _ -> Printexc.to_string e); exit 2
