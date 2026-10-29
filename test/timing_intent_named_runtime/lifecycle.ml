open Hardcaml_asic_execution
module J=Identity_json
let checked = function Ok x -> x | Error s -> failwith s
let assert_true name b = if not b then failwith name
let get j k = match j with J.Object xs -> List.assoc_opt k xs | _ -> None
let () =
  let stages=checked (Execution_plan.Stage_plan.through Execution_plan.Stage.Floorplan) in
  let plan=Execution_plan.of_stages stages in
  let expectation=Timing_intent_named_service.expectation ~workspace:"/fixture/workspace" ~attempt_id:"attempt" in
  let publication boundary =
    {Runner.evidence=checked (Runner.reference ~boundary ~path:("/fixture/" ^ Execution_plan.Stage.to_string boundary)
      ~identity:(String.make 64 'a'));checkpoint=boundary} in
  List.iter (fun mode ->
    let invokes=ref 0 and published=ref false and saves=ref [] in
    let callbacks={Runner.validate=(fun _ -> Ok ());
      invoke=(fun _ _ -> incr invokes; Ok (Runner.Segment_result ((),{Runner.status=Completed;exit_code=0;error=None})));
      publish=(fun action _ () -> match action.Execution_plan.Action.stage with
        | Physical b -> Ok (publication b) | _ -> assert false)} in
    let lifecycle event _ (occurrence:Runner.occurrence) artifact = match event,artifact with
      | Runner.Published,Some _ ->
        published:=true;
        assert_true "artifact persisted before required hook" (List.length (List.hd (List.rev !saves)).Runner.artifacts=1);
        assert_true "Published is Running" (occurrence.status=Runner.Running && occurrence.exit_code=None);
        (match mode with
         | "failure" -> raise (Runner.Callback_error (Runner.failure ~exit_code:9 ~secondary:["native cleanup failed"] "native failed"))
         | "cancel" -> raise (Runner.Callback_error (Runner.cancellation ~signal:2 ~secondary:["cleanup failed"] "cancelled"))
         | "timeout" -> raise (Runner.Callback_error (Runner.failure ~exit_code:124 "timed out"))
         | "publication" -> failwith "companion storage failed"
         | _ -> ())
      | _ -> () in
    let persist t = saves:= !saves@[t] in
    let result=Runner.execute ~timing_intent:expectation ~lifecycle ~persist ~attempt_id:"attempt" plan callbacks in
    assert_true "expectation persisted before invoke" (get (Runner.to_json ~run_json:(fun () -> J.null) (List.hd !saves)) "timing_intent"=Some expectation);
    assert_true "published reached" !published;
    assert_true "failure retains checkpoint" (List.length result.artifacts=1);
    assert_true "downstream blocked" (!invokes=1 && (List.nth result.occurrences 1).status=Runner.Unreached);
    let code=match mode with "failure"->9 | "cancel"->130 | "timeout"->124 | _ ->2 in
    assert_true "primary status preserved" (result.exit_code=code);
    assert_true "secondary preserved" (match mode,result.primary with
      | ("failure"|"cancel"),Some d -> d.error.secondary<>[] | _ -> true))
    ["failure";"cancel";"timeout";"publication"];
  let callbacks={Runner.validate=(fun _ -> Ok ());invoke=(fun _ _ -> assert false);publish=(fun _ _ _ -> assert false)} in
  let result=Runner.execute ~timing_intent:expectation ~cancel:(fun () -> Some (Runner.cancellation ~signal:15 "cancel before work"))
    ~attempt_id:"attempt" plan callbacks in
  assert_true "prework cancellation" (result.exit_code=143 && result.artifacts=[]);
  let called=ref false in
  let callbacks={Runner.validate=(fun _ -> Ok ());
    invoke=(fun _ _ -> Ok (Runner.Segment_result ((),{Runner.status=Completed;exit_code=0;error=None})));
    publish=(fun _ _ () -> Ok (publication Execution_plan.Stage.Synthesis))} in
  let persist t = if t.Runner.artifacts<>[] then failwith "durable publication save failed" in
  let lifecycle event _ _ _ = if event=Runner.Published then called:=true in
  let result=Runner.execute ~timing_intent:expectation ~persist ~lifecycle ~attempt_id:"attempt" plan callbacks in
  assert_true "failed durable save vetoes analysis" (not !called && result.exit_code=2 && List.length result.artifacts=1);
  List.iter (fun mode ->
    let events=ref [] and snapshots=ref [] in
    let note s=events:= !events@[s] in
    let callbacks={Runner.validate=(fun _ -> note "validate";
      match mode with
      | "cancel_validation" -> Error (Runner.cancellation ~signal:15 "validation cancelled")
      | "fail_validation" -> Error (Runner.failure ~exit_code:17 "validation failed")
      | _ -> Ok ());
      invoke=(fun _ _ -> failwith "initial persistence/validation must veto invocation");
      publish=(fun _ _ _ -> assert false)} in
    let persist t = note "persist";snapshots:= !snapshots@[t];
      if mode="fail_initial_save" then raise (Runner.Callback_error (Runner.failure ~exit_code:28 "initial store full")) in
    let result=Runner.execute ~timing_intent:expectation ~persist ~attempt_id:"attempt" plan callbacks in
    assert_true "initial save precedes any validation" (List.hd !events="persist");
    assert_true "initial snapshot contains expectation" ((List.hd !snapshots).Runner.timing_intent=Some expectation);
    assert_true "initial snapshot is unreached" (List.for_all (fun (o:Runner.occurrence) -> o.status=Runner.Unreached) (List.hd !snapshots).occurrences);
    if mode="fail_initial_save" then assert_true "initial storage error vetoes validation" (not (List.mem "validate" !events) && result.exit_code=28)
    else assert_true "validation terminal cause preserved" (result.exit_code=(if mode="cancel_validation" then 143 else 17)))
    ["fail_initial_save";"cancel_validation";"fail_validation"];
  print_endline "Runner expectation/Published retention: failure, cancellation, timeout, publication failure, prework cancellation pass"
