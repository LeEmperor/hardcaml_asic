open Hardcaml_asic_execution
let () =
  let root=Sys.argv.(1) and mode=Sys.argv.(2) in
  let clock=ref 0. in
  let clock ()=let x= !clock in clock:=x+.0.125; x in
  let touch name=Result_store.save_bytes (root^"/"^name) "called" in
  let boundary name =
    touch ("called-"^name);
    if mode="fail-"^name then failwith (name^" fixture failure");
    if mode="int-"^name || mode="term-"^name then
      Unix.kill (Unix.getpid ()) (if mode="int-"^name then Sys.sigint else Sys.sigterm) in
  let archive=if mode="none" then None else Some (root^"/archive") in
  let services={Coarse_execution_service.
    run=(fun () -> boundary "run";
      let a=Result_store.allocate ~clock:(fun () -> 0.) ~id_factory:(fun () -> String.make 32 'a') (root^"/runs") in
      let record=Evidence_json.value (Evidence_json.read (root^"/record.json")) in
      Result_store.save_bytes (a.directory^"/run.json") (Evidence_json.record_bytes record);
      (* Explicit fixture evidence context; report/collection themselves remain real. *)
      let status,exit_code=match mode with
        | "run-failed" | "run-failed-collect" -> Run_record.Failed,1
        | "run-interrupted" | "run-interrupted-collect" -> Interrupted,130
        | _ -> Completed,0 in
      let o=Run_record.outcome a ~status ~exit_code in
      if mode="retained-error" then raise (Coarse_run_service.Retained_error (
        Run_record.outcome a ~status:Failed ~exit_code:2,Runner.failure "publication fixture failure"));
      if mode="retained-interrupted" then raise (Coarse_run_service.Retained_error (
        Run_record.outcome a ~status:Interrupted ~exit_code:143,
        Runner.cancellation ~signal:15 ~secondary:["publication fixture failure"] "interrupted by SIGTERM"));
      o);
    postcheck=(fun _ -> boundary "postcheck"; failwith "postcheck fixture failure");
    collect=(fun o -> boundary "collect";
      if mode="run-failed-collect" || mode="run-interrupted-collect" then failwith "collect fixture failure";
      let r=Collect_service.collect ~context:(Evidence_json.value (Evidence_json.read (root^"/record.json"))) (root^"/source") in
      Collect_service.save (o.run_dir^"/results.json") r; r);
    report=(fun o -> boundary "report";
      if mode="malformed-report" then Error 2 else Ok (Report_service.run o.run_dir));
    archive=(fun _ -> boundary "archive"; Error 2)
  } in
  try
    let full=mode="fail-postcheck" || mode="int-postcheck" || mode="term-postcheck" in
    let plan=Execution_plan.Coarse.resolve ~archive:(Option.is_some archive) (if full then Full else Synthesis) in
    let t=Coarse_execution_service.execute ~clock ~plan ~archive services in
    print_string (Result_store.record_bytes (Coarse_execution_service.to_json t)); exit t.exit_code
  with e -> prerr_endline (match e with Failure s -> s | _ -> Printexc.to_string e); exit 2
