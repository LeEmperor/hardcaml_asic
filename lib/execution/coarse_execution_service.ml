[@@@alert "-unsafe_multidomain"]
module R = Runner
module A = Execution_plan.Action
module J = Identity_json
type callbacks = {
  run : unit -> Run_record.outcome;
  postcheck : Run_record.outcome -> Postcheck_service.outcome;
  collect : Run_record.outcome -> Collect_service.t;
  report : Run_record.outcome -> (Report_service.result, int) result;
  archive : Run_record.outcome -> (Archive_service.publication, int) result;
}
type t = (Run_record.outcome, unit) R.t
let completion status exit_code = {R.status; exit_code; error=None}
let status = function
  | "completed" -> R.Completed | "failed" -> R.Failed | "interrupted" -> R.Interrupted
  | s -> invalid_arg ("nonterminal service status: " ^ s)
let execute ?clock ?(attempt_id="execute")
    ?(observe_postcheck=fun _ -> ()) ~plan ~archive services =
  let selected = List.exists (fun (a:A.t) -> a.operation=A.Archive && a.enabled)
      (Execution_plan.Coarse.actions plan) in
  if selected <> Option.is_some archive then invalid_arg "plan does not match the bound service inputs";
  let signal = ref None and preallocation = ref None in
  let handler n = if !signal=None then signal:=Some (if n=Sys.sigint then 2 else 15) in
  let int_handler=Sys.signal Sys.sigint (Sys.Signal_handle handler) in
  let term_handler=Sys.signal Sys.sigterm (Sys.Signal_handle handler) in
  Fun.protect ~finally:(fun () -> Sys.set_signal Sys.sigint int_handler; Sys.set_signal Sys.sigterm term_handler)
    (fun () ->
      let remember code = if code=130 || code=143 then signal:=Some (code-128) in
      let check () = match !signal with None -> () | Some n ->
        raise (R.Callback_error (R.cancellation ~signal:n
          ("interrupted by " ^ if n=2 then "SIGINT" else "SIGTERM"))) in
      let callbacks = {
        R.validate=(fun _ -> Ok ());
        publish=(fun _ _ () -> Error (R.failure "coarse plan cannot publish checkpoints"));
        invoke=(fun action context ->
          let before= !signal in
          try
          if action.A.operation<>A.Collect then check ();
          match action.operation with
          | A.Run ->
            let o,retained_error = try services.run (),None with
              | Coarse_run_service.Retained_error (o,e) -> o,Some e
              | e -> preallocation:=Some e; raise e in
            remember o.exit_code;
            let c=match !signal with Some n when o.exit_code=0 -> completion R.Interrupted (128+n)
              | _ -> {R.status=status (Run_record.status_name o.status);exit_code=o.exit_code;error=retained_error} in
            Ok (R.Run_result (o,c))
          | _ ->
            let o=Option.get context.R.run in
            match action.operation with
            | A.Postcheck ->
              let c=services.postcheck o in remember c.exit_code;
              observe_postcheck c;
              Ok (R.Service_result (completion (status c.status) c.exit_code))
            | A.Collect -> ignore (services.collect o); if before=None then check ();
              Ok (R.Service_result (completion R.Completed 0))
            | A.Report -> let report=services.report o in check ();
              let code=match report with Ok r -> Report_service.exit_code r.verdict
                | Error n when n>0 -> n | Error _ -> invalid_arg "report failure requires positive exit code" in
              Ok (R.Service_result (completion (if code=0 then R.Accepted else R.Rejected) code))
            | A.Archive -> let publication=services.archive o in check ();
              let code=match publication with Ok _ -> 0 | Error n when n>0 -> n
                | Error _ -> invalid_arg "archive failure requires positive exit code" in
              Ok (R.Archive_result (Option.get archive,completion (if code=0 then R.Completed else R.Failed) code))
            | A.Run | A.Segment -> assert false
          with
          | R.Callback_error _ as e -> raise e
          | (Failure s | Invalid_argument s | Sys_error s) ->
            if before=None then check (); Error (R.failure s))
      } in
      let result=R.execute ?clock ~attempt_id (Execution_plan.of_coarse plan) callbacks in
      match result.run,!preallocation with
      | None,Some e -> raise e
      | None,None -> (match result.primary with Some d -> raise (R.Callback_error d.error) | None -> assert false)
      | Some _,_ -> result)
let to_json (t:t) =
  let get = function Ok x -> x | Error e -> invalid_arg (J.error_message e) in
  let str s=get (J.string s) and int n=get (J.integer (string_of_int n)) in
  let o=Option.get t.run in
  let steps=match R.steps_json t with
    | J.Array xs -> J.array (List.map (function
        | J.Object fields ->
          let best=List.assoc_opt "best_effort" fields=Some (J.bool true) in
          let interrupted=List.assoc_opt "operation" fields=Some (str "postcheck") &&
            List.assoc_opt "status" fields=Some (str "interrupted") in
          let fields=if interrupted then List.remove_assoc "error" fields else fields in
          let fields=if best then
            let failed=List.mem_assoc "error" fields in
            ("status",str (if failed then "failed" else "completed")) ::
            (if failed then ("exit_code",int 2)::List.remove_assoc "exit_code" (List.remove_assoc "status" fields)
             else List.remove_assoc "status" fields) else fields in
          get (J.object_ fields)
        | _ -> assert false) xs)
    | _ -> assert false in
  get (J.object_ (["run_id",str o.run_id;"run_dir",str o.run_dir;"run_record",str o.run_record;
    "steps",steps;"status",str (R.status_name t.status);"exit_code",int t.exit_code] @
    match t.archive with None -> [] | Some p -> ["archive",str p]))
