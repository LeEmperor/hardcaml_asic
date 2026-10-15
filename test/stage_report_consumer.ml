open Hardcaml_asic_execution
let checked = function Ok x -> x | Error e -> invalid_arg e
let runner_snapshot path event interrupted =
  let raw = match Result_store.read_json path with Ok j -> j | Error e -> invalid_arg (Identity_json.error_message e) in
  let get k = match raw with Identity_json.Object xs -> List.assoc k xs | _ -> assert false in
  let plan = checked (Execution_plan.Stage_plan.of_json (get "plan")) |> Execution_plan.of_stages in
  let refs = match get "artifacts" with Identity_json.Array xs -> xs | _ -> assert false in
  let publications = List.map (fun r ->
    let field k = match r with Identity_json.Object xs -> List.assoc k xs | _ -> assert false in
    let text k = match field k with Identity_json.String s -> s | _ -> assert false in
    let boundary = match Execution_plan.Stage.of_string (text "boundary") with
      | Ok b -> b | Error _ -> invalid_arg "invalid fixture boundary" in
    {Runner.evidence=checked (Runner.reference ~boundary ~path:(text "path") ~identity:(text "identity")); checkpoint=()}) refs in
  let captured = ref None and ticks = ref 0 in
  let error = if interrupted then Runner.cancellation ~signal:2 "injected lifecycle cancellation"
    else Runner.failure "injected lifecycle failure" in
  let callbacks = {Runner.validate=(fun _ -> Ok ());
    invoke=(fun _ _ -> Ok (Runner.Segment_result ((),{status=Runner.Completed;exit_code=0;error=None})));
    publish=(fun a _ () -> Ok (List.find (fun p ->
      a.Execution_plan.Action.stage=Physical p.Runner.evidence.boundary) publications))} in
  ignore (Runner.execute ~attempt_id:"attempt" plan callbacks
    ~clock:(fun () -> incr ticks;
      if event="clock" && !ticks=3 then raise (Runner.Callback_error error);
      float_of_int !ticks)
    ~lifecycle:(fun point action _ _ ->
      if action.Execution_plan.Action.key="implementation.floorplan" &&
         ((event="started" && point=Runner.Started) || (event="published" && point=Runner.Published)) then
        raise (Runner.Callback_error error))
    ~persist:(fun state ->
      if !captured=None && state.Runner.exit_code=error.exit_code &&
         List.exists (fun (o:Runner.occurrence) -> o.action_key="implementation.floorplan" && o.status=Runner.Running) state.occurrences
      then captured:=Some (Runner.to_json ~run_json:(fun () -> Identity_json.null) state)));
  Identity_json.canonical (Option.get !captured)
let () =
  try
    if Array.length Sys.argv=5 && Sys.argv.(1)="--runner-snapshot" then begin
      print_endline (runner_snapshot Sys.argv.(2) Sys.argv.(3)
        (Sys.argv.(4)="interrupted")); exit 0
    end;
    if Array.length Sys.argv=3 && Sys.argv.(1)="--supplement" then begin
      let supplements,diagnostics=Yosys_stat_evidence.read ~run_dir:Sys.argv.(2) ~mapped_count:None in
      print_endline (Identity_json.canonical (Identity_json.array [Identity_json.array supplements;Identity_json.array diagnostics])); exit 0
    end;
    let target = match Stage_report_service.select Sys.argv.(1) with Ok t -> t | Error e -> invalid_arg e in
    let report = match Stage_report_service.run target with Ok r -> r | Error e -> invalid_arg e in
    (match report.envelope with Identity_json.Object xs when not (List.mem_assoc "methodology" xs) ->
      assert (Stage_report_service.methodology report = Historical_methodology.not_recorded)
    | _ -> ());
    print_endline (Identity_json.canonical report.envelope)
  with Invalid_argument s -> prerr_endline s; exit 2
