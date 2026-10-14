open Hardcaml_asic_execution
let () =
  let values = Hashtbl.create 12 and native = ref false and json = ref false and verbose = ref false and public = ref false and mismatch = ref false in
  let specs = List.map (fun name -> "--" ^ name,Arg.String (fun x -> Hashtbl.replace values name x),name)
    ["bundle";"support-tools";"pdk-root";"python";"resources";"runs";"stage";"plan"] @
    ["--native",Arg.Set native,"native synthesis";"--json",Arg.Set json,"JSON outcome";
     "--verbose",Arg.Set verbose,"diagnostics";"--public-cli4",Arg.Set public,"public presentation";
     "--allow-python-mismatch",Arg.Set mismatch,"legacy API waiver"] in
  try
    Arg.parse specs (fun _ -> raise (Arg.Bad "unexpected argument")) "Coarse run";
    let plan = match Hashtbl.find_opt values "plan" with
      | Some p -> (match Execution_plan.of_json (match Result_store.read_json p with Ok x -> x | Error e -> failwith (Identity_json.error_message e)) with
        | Ok (Execution_plan.Coarse p) -> p | Ok _ -> failwith "coarse plan required" | Error e -> failwith e)
      | None -> Execution_plan.Coarse.resolve (match Hashtbl.find_opt values "stage" with
        | None | Some "synthesis" -> Synthesis | Some "full" -> Full | _ -> invalid_arg "unsupported stage") in
    let value = Hashtbl.find values in
    let o = Coarse_run_service.run ~bundle:(value "bundle") ~support_tools:(value "support-tools")
      ~pdk_root:(value "pdk-root") ~python:(value "python") ~resources:(value "resources")
      ~environment:(Array.to_list (Unix.environment ())) ~runs:(value "runs") ~plan ~native:!native ~allow_python_mismatch:!mismatch () in
    if !json || not !public then print_string (Result_store.record_bytes (Run_record.outcome_json o))
    else (
      Printf.printf "run: %s (exit %d)\nrun id: %s\nrun: %s\nrecord: %s\n"
        (Run_record.status_name o.status) o.exit_code o.run_id o.run_dir o.run_record;
      List.iter (fun name -> let path = o.run_dir ^ "/" ^ name in if Sys.file_exists path then Printf.printf "%s: %s\n" name path)
        ["preflight.json";"results.json";"execution.log"]);
    if !public then (match Result_store.read_json o.run_record with
      | Ok (Identity_json.Object fields) -> List.iter (fun (k,v) ->
        if k="error" then Printf.eprintf "run: %s\n" (match v with Identity_json.String x -> x | _ -> Preflight_service.python_repr v)
        else if !verbose then Printf.eprintf "run %s: %s\n" k (Preflight_service.python_repr v)) fields
      | _ -> ());
    exit o.exit_code
  with
  | Runner.Callback_error {kind=Runner.Cancellation n;message;_} ->
    Printf.eprintf "hardcaml-asic-flow: %s\n" message; exit (128+n)
  | e -> Printf.eprintf "hardcaml-asic-flow: %s\n" (match e with Failure x | Invalid_argument x -> x | _ -> Printexc.to_string e); exit 2
