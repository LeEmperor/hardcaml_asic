open Hardcaml_asic_execution
let () =
  let values=Hashtbl.create 12 and json=ref false and public=ref false and verbose=ref false in
  let specs=List.map (fun name -> "--"^name,Arg.String (fun x -> Hashtbl.replace values name x),name)
     ["run-dir";"support-tools";"pdk-root";"precheck-python";"testbench";"testbench-top";"context";"replay-trace";"timeout";"resources"] @
    ["--json",Arg.Set json,"JSON outcome";"--public-cli4",Arg.Set public,"public presentation";"--verbose",Arg.Set verbose,"diagnostics"] in
  try
    Arg.parse specs (fun _ -> raise (Arg.Bad "unexpected argument")) "External postcheck";
    let v=Hashtbl.find values in
    let o=Postcheck_service.run ~run_dir:(v "run-dir") ~support_tools:(v "support-tools") ~pdk_root:(v "pdk-root")
      ~precheck_python:(v "precheck-python") ~testbench:(v "testbench") ~testbench_top:(v "testbench-top")
       ~environment:(Array.to_list (Unix.environment ()))
       ?resources:(Hashtbl.find_opt values "resources")
      ?context:(Option.map (fun p -> Evidence_json.value (Evidence_json.read p)) (Hashtbl.find_opt values "context"))
      ?replay_trace:(Hashtbl.find_opt values "replay-trace") ?timeout:(Option.map float_of_string (Hashtbl.find_opt values "timeout")) () in
    if !json || not !public then print_string (Result_store.record_bytes (Postcheck_service.outcome_json o))
    else (
      Printf.printf "postcheck: %s (exit %d)\ncheck id: %s\ncheck: %s\nrecord: %s\n"
        o.status o.exit_code o.check_id o.check_dir o.check_record;
      if Sys.file_exists (o.check_dir^"/postcheck.log") then Printf.printf "log: %s/postcheck.log\n" o.check_dir);
    if !public then (match Result_store.read_json o.check_record with
      | Ok (Identity_json.Object fields) -> List.iter (fun (k,v) ->
        if k="error" then Printf.eprintf "postcheck: %s\n" (match v with Identity_json.String x -> x | _ -> Preflight_service.python_repr v)
        else if !verbose then Printf.eprintf "postcheck %s: %s\n" k (Preflight_service.python_repr v)) fields
      | _ -> ());
    exit o.exit_code
  with e -> Printf.eprintf "hardcaml-asic-flow: %s\n" (match e with Failure x | Invalid_argument x -> x | _ -> Printexc.to_string e); exit 2
