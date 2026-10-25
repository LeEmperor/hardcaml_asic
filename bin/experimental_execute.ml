open Hardcaml_asic_execution
let message = function
  | Failure s | Invalid_argument s | Sys_error s -> s
  | Unix.Unix_error (e,fn,p) -> fn^" "^p^": "^Unix.error_message e
  | e -> Printexc.to_string e
let diagnostics ~verbose operation record =
  if Sys.file_exists record then
    match Evidence_json.value (Evidence_json.read record) with
    | `Assoc fields -> List.iter (fun (k,v) ->
        if k="error" then (if v<>`Null && v<>`String "" then Printf.eprintf "%s: %s\n" operation
          (match v with `String s -> s | _ -> Evidence_json.repr v))
        else if verbose then Printf.eprintf "%s %s: %s\n" operation k
          (match v with `String s -> s | _ -> Evidence_json.repr v)) fields
    | _ -> ()
let () =
  try
    let values=Hashtbl.create 16 and native=ref false and json=ref false and verbose=ref false and force=ref false in
    let specs=List.map (fun n -> "--"^n,Arg.String (Hashtbl.replace values n),n)
      ["bundle";"support-tools";"pdk-root";"python";"resources";"runs";"stage";
       "precheck-python";"testbench";"testbench-top";"archive"] @
      ["--native",Arg.Set native,"native";"--json",Arg.Set json,"JSON";
       "--verbose",Arg.Set verbose,"verbose";"--force",Arg.Set force,"force"] in
    Arg.parse specs (fun _ -> invalid_arg "unexpected argument") "Coarse execute";
    let value=Hashtbl.find values in
    let endpoint=match value "stage" with "synthesis" -> Execution_plan.Coarse.Synthesis | "full" -> Full
      | _ -> invalid_arg "unsupported stage" in
    let archive=Hashtbl.find_opt values "archive" in
    let plan=Execution_plan.Coarse.resolve ~archive:(Option.is_some archive) endpoint in
    let environment=Array.to_list (Unix.environment ()) in
    let callbacks={Coarse_execution_service.
      run=(fun () -> Coarse_run_service.run ~bundle:(value "bundle") ~support_tools:(value "support-tools")
        ~pdk_root:(value "pdk-root") ~python:(value "python") ~resources:(value "resources")
        ~environment ~runs:(value "runs") ~plan ~native:!native ());
      postcheck=(fun o -> Postcheck_service.run ~run_dir:o.run_dir ~support_tools:(value "support-tools")
        ~pdk_root:(value "pdk-root") ~precheck_python:(value "precheck-python")
         ~testbench:(value "testbench") ~testbench_top:(value "testbench-top") ~resources:(value "resources") ~environment ());
      collect=(fun o -> try let r=Collect_service.collect o.run_dir in
        Collect_service.save (o.run_dir^"/results.json") r;
        if !verbose then (match Collect_service.to_json r with `Assoc xs -> List.iter (fun (k,v) ->
          Printf.eprintf "collect %s: %s\n" k (Evidence_json.repr v)) xs | _ -> ()); r
        with e -> Printf.eprintf "collect: %s\n" (message e); failwith "OCaml collect exited 2");
      report=(fun o -> try let r=Report_service.run o.run_dir in
        let code=Report_service.exit_code r.verdict in
        if code<>0 || !verbose then prerr_string r.human;
        if !verbose then Printf.eprintf "report: run %s; result source %s; acceptance exit %d\n" o.run_dir r.source code;
        Ok r with e -> Printf.eprintf "report: %s\n" (message e); Error 2);
      archive=(fun o -> try let runtime={Archive_encoding.gzip="/usr/bin/gzip";
          scratch=Unix.realpath (Filename.get_temp_dir_name ());timeout=120.} in
        let p=Archive_service.publish ~runtime ~run_dir:o.run_dir ~output:(Option.get archive) ~force:!force () in
        List.iter (fun s -> prerr_endline ("archive: absent, not included: "^s)) p.omitted; Ok p
        with
        | Archive_encoding.Gzip_failed ({outcome=Process_supervisor.Cancelled n;_},_) ->
          raise (Runner.Callback_error (Runner.cancellation ~signal:(if n=Sys.sigint then 2 else 15) "archive interrupted"))
        | e -> Printf.eprintf "hardcaml-asic-flow: %s\n" (message e); Error 2)
    } in
    let observe_postcheck (o:Postcheck_service.outcome) =
      if not !json then (
        Printf.printf "postcheck: %s (exit %d)\ncheck id: %s\ncheck: %s\nrecord: %s\n"
          o.status o.exit_code o.check_id o.check_dir o.check_record;
        let log=o.check_dir^"/postcheck.log" in if Sys.file_exists log then Printf.printf "log: %s\n" log);
      diagnostics ~verbose:!verbose "postcheck" o.check_record in
    let t=Coarse_execution_service.execute ~observe_postcheck ~plan ~archive callbacks in
    let result=Coarse_execution_service.to_json t in
    let out=if !json then stderr else stdout in
    (match result with Identity_json.Object fields ->
      (match List.assoc "steps" fields with Identity_json.Array steps -> List.iter (function
        | Identity_json.Object xs ->
          let text n=match List.assoc n xs with Identity_json.String s -> s | _ -> assert false in
          let duration=match List.assoc "duration_seconds" xs with Identity_json.Float x -> x | _ -> 0. in
          Printf.fprintf out "execute: %s %s (%.3fs)\n" (text "operation") (text "status") duration;
          (match List.assoc_opt "error" xs with Some (Identity_json.String s) when s<>"" ->
            Printf.eprintf "execute: %s: %s\n" (text "operation") s | _ -> ())
        | _ -> assert false) steps | _ -> assert false)
      | _ -> assert false);
    Printf.fprintf out "execute: %s\n" (Runner.status_name t.status);
    let o=Option.get t.run in
    if !json then Printf.fprintf out "execute: run %s\n" o.run_dir else (
      Printf.printf "run: %s (exit %d)\nrun id: %s\nrun: %s\nrecord: %s\n"
        (Run_record.status_name o.status) o.exit_code o.run_id o.run_dir o.run_record;
      List.iter (fun n -> let p=o.run_dir^"/"^n in if Sys.file_exists p then Printf.printf "%s: %s\n" n p)
        ["preflight.json";"results.json";"execution.log"]);
    Option.iter (Printf.fprintf out "execute: archive %s\n") t.archive;
    diagnostics ~verbose:!verbose "run" o.run_record;
    if !json then print_string (Result_store.record_bytes result);
    exit t.exit_code
  with
  | Runner.Callback_error e -> Printf.eprintf "hardcaml-asic-flow: %s\n" e.message; exit e.exit_code
  | e -> Printf.eprintf "hardcaml-asic-flow: %s\n" (match e with
      Failure s | Invalid_argument s | Sys_error s -> s | _ -> Printexc.to_string e); exit 2
