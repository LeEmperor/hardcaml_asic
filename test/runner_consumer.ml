open Hardcaml_asic_execution
module R = Runner
module J = Identity_json
let get = function Ok x -> x | Error _ -> failwith "invalid test input"
let obj x = get (J.object_ x)
let str x = get (J.string x)
let int x = get (J.integer (string_of_int x))
let field j k = match j with J.Object xs -> List.assoc_opt k xs | _ -> None
let text = function J.String s -> s | _ -> failwith "expected text"
let number = function J.Integer s -> int_of_string s | _ -> failwith "expected integer"
let default j k f d = match field j k with None -> d | Some v -> f v
let () =
  let request = get (J.parse (read_line ())) in
  let plan = get (Execution_plan.of_json (Option.get (field request "plan"))) in
  let directory = default request "directory" text "/tmp/opencode" in
  let trace = ref [] and snapshots = ref [] in
  let add point key = trace := !trace @ [obj ["point",str point;"key",str key]] in
  let failing point key =
    match field request "failures" with
    | Some (J.Array xs) -> List.find_opt (fun x -> default x "point" text ""=point && default x "key" text ""=key) xs
    | _ -> None in
  let check point key = match failing point key with
    | None -> ()
    | Some f ->
      let message = default f "message" text (point ^ " fault") in
      if default f "mode" text "error" = "exception" then failwith message;
      let e = if default f "mode" text "error" = "cancel" then R.cancellation ~signal:15 message
        else R.failure ~secondary:["cleanup retained"] message in
      raise (R.Callback_error e) in
  let result_code a = match field request "codes" with Some j -> default j a.Execution_plan.Action.key number 0 | _ -> 0 in
  let complete a =
    let code=result_code a in
    {R.status=(if default request "bad_completion" text ""=a.Execution_plan.Action.key then Running
       else if a.Execution_plan.Action.operation=Report then (if code=0 then R.Accepted else Rejected)
       else if code=143 && (a.operation=Run || a.operation=Postcheck || a.operation=Segment) then Interrupted
       else if code=0 then Completed else Failed);exit_code=code;
     error=(if default request "completion_error" text ""=a.key then
       Some (R.failure ~exit_code:(max 1 code) ~secondary:["owned cleanup failed"] "process failed") else None)} in
  let returned f = try f () with R.Callback_error e -> Error e in
  let callbacks = {
    R.validate=(fun _ -> returned (fun () -> add "validate" "";check "validate" "";Ok ()));
    invoke=(fun a ctx -> returned (fun () ->
      add "invoke" a.key; check "invoke" a.key;
      (if default request "wrong_outcome" text ""=a.key then Ok (R.Service_result (complete a)) else match a.operation with Segment ->
        let expected = match a.stage with Physical s -> s | _ -> assert false in
        (match ctx.R.source with None -> assert (expected=Execution_plan.Stage.Synthesis)
          | Some s -> assert (s.boundary<>expected);
            if s.checkpoint<>directory^"/initial" then begin
              assert (s.checkpoint=directory^"/"^Execution_plan.Stage.to_string s.boundary);
              assert (Sys.file_exists (s.checkpoint^".publication.json"))
            end);
        Ok (R.Segment_result (expected,complete a))
       | Run -> Ok (R.Run_result (obj ["run_dir",str (directory^"/run");"status",str (R.status_name (complete a).status);
                                      "exit_code",int (result_code a)],complete a))
       | Archive -> Ok (R.Archive_result (directory^"/archive",complete a))
       | _ -> assert (ctx.run<>None);Ok (R.Service_result (complete a)))));
    publish=(fun a _ boundary -> returned (fun () ->
      add "publish" a.key;check "publish" a.key;
      let path=directory^"/"^Execution_plan.Stage.to_string boundary in
      let evidence_boundary = if default request "wrong_publication" text ""=a.key then Execution_plan.Stage.Signoff else boundary in
      let evidence=get (R.reference ~boundary:evidence_boundary ~path ~identity:(String.make 64 'a')) in
      Result_store.save_json (path^".publication.json") (R.reference_json evidence);
      Ok {R.evidence;checkpoint=path})) } in
  let clocks=ref 0 and polls=ref 0 and saves=ref 0 in
  let clock () = incr clocks; check "clock" (string_of_int !clocks);
    if field request "elapsed" <> None then
      let elapsed = match Option.get (field request "elapsed") with J.Float f -> f | J.Integer s -> float_of_string s | _ -> assert false in
      if !clocks=1 then 0. else elapsed
    else if default request "nonfinite_clock" number 0= !clocks then nan
    else if default request "backward_clock" number 0= !clocks then -1.
    else float_of_int !clocks in
  let cancel () = incr polls;check "cancel" (string_of_int !polls);None in
  let lifecycle event a (o : R.occurrence) publication =
    let point=match event with R.Started -> "started" | Published -> "published" | Finished -> "finished" in
    add point a.Execution_plan.Action.key;
    if event=R.Published then begin
      assert (o.status=R.Running);
      let p=Option.get publication in assert (Sys.file_exists (p.R.evidence.path^".publication.json"))
    end;
    check point a.key in
  let persist t = incr saves;add "persist" (string_of_int !saves);
    check "persist" (string_of_int !saves);
    let json=R.to_json ~run_json:Fun.id t in
    snapshots := !snapshots@[json];
    Result_store.save_json (directory^"/execution.json") json in
  let initial = match field request "initial" with
    | None | Some J.Null -> None
    | Some j -> Some {R.boundary=get (Execution_plan.Stage.of_string (text j));checkpoint=directory^"/initial"} in
  let execution = R.execute ?initial ~clock ~cancel ~lifecycle ~persist
    ~observe:(fun a _ -> add "observe" a.Execution_plan.Action.key; check "observe" a.key)
    ~attempt_id:(default request "attempt_id" text "attempt") plan callbacks in
  print_endline (J.canonical (obj ["execution",R.to_json ~run_json:Fun.id execution;
    "steps",R.steps_json execution;"diagnostics",R.diagnostics_json execution;
    "trace",J.array !trace;"snapshots",J.array !snapshots]))
