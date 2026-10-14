open Hardcaml_asic_execution
module J = Identity_json
let codec = function Ok x -> x | Error e -> failwith (J.error_message e)
let checked = function Ok x -> x | Error s -> failwith s
let text = function J.String s -> s | _ -> failwith "string required"
let get j k = match j with J.Object xs -> List.assoc k xs | _ -> failwith "object required"
let append p = let oc = open_out_gen [Open_wronly;Open_append] 0o600 p in output_string oc " "; close_out oc
let forge_reply (s:Segment_service.segment) =
  let json = codec (Result_store.read_json s.request.reply_path) in
  let fields = match json with J.Object xs -> xs | _ -> assert false in
  let artifacts = match List.assoc "artifacts" fields with J.Object xs -> xs | _ -> assert false in
  let state = get (List.assoc "state.json" artifacts) "path" |> text in
  let record = checked (Checkpoint.file_record state) in
  let forged = codec (J.object_ ["path",codec (J.string state);"sha256",codec (J.string record.sha256);"bytes",codec (J.integer record.bytes)]) in
  let artifacts = codec (J.object_ (List.map (fun (k,v) -> k,if k="state.json" then forged else v) artifacts)) in
  Result_store.save_json s.request.reply_path (codec (J.object_ (List.map (fun (k,v) -> k,if k="artifacts" then artifacts else v) fields)))
let () =
  let config = codec (Result_store.read_json Sys.argv.(1)) in
  let value k = get config k in
  let mode = Sys.argv.(3) in
  let initial_checkpoint = match value "initial_checkpoint" with J.Null -> None | j -> Some (text j) in
  let timeout = match value "timeout" with J.Float f -> f | J.Integer s -> float_of_string s | _ -> assert false in
  let environment = match value "environment" with J.Array xs -> List.map text xs | _ -> assert false in
  let emit_error e = print_endline (J.canonical (codec (J.object_ ["create_error",codec (J.string e.Runner.message)]))) in
  match Segment_service.Testing.create_native_fixture ~fixture:Sys.argv.(2) ~interpreter:(text (value "interpreter"))
    ~workspace:(text (value "workspace")) ~project:(text (value "project")) ~pdk_root:(text (value "pdk_root"))
    ~checkpoint_store:(text (value "checkpoint_store")) ~compatibility:(value "compatibility") ~environment ~timeout
    ?initial_checkpoint () with
  | Error e -> emit_error e
  | Ok service ->
    if mode = "initial_mutation" then Option.iter (fun p -> Unix.chmod (p ^ "/state.json") 0o644; append (p ^ "/state.json")) initial_checkpoint;
    let events = ref [] in
    let callbacks = Segment_service.callbacks service in
    let invoke action context =
      if mode = "callback_exception" then failwith "injected callback failure";
      if mode = "launch_record_failure" then Unix.chmod (text (value "workspace")) 0o500;
      match callbacks.invoke action context with
      | Ok (Runner.Segment_result (s,_) as result) ->
        if mode = "candidate_mutation" then append (s.request.candidate ^ "/state.json");
        if mode = "candidate_forged_reply" then (append (s.request.candidate ^ "/state.json"); forge_reply s);
        if mode = "bridge_mutation" then append (s.request.project ^ "/bridge/librelane_bridge.py");
        if mode = "closure_mutation" then append (s.request.project ^ "/manifest.json");
        if mode = "publication_permission" then Unix.chmod (text (value "checkpoint_store")) 0o500;
        Ok result
      | result -> result in
    let lifecycle point action _ publication =
      let name = match point with Runner.Started -> "started" | Published -> "published" | Finished -> "finished" in
      events := !events @ [name ^ ":" ^ action.Execution_plan.Action.key];
      Option.iter (fun (p:Segment_service.checkpoint Runner.publication) ->
        ignore (checked (Checkpoint.validate ~compatibility:(value "compatibility") p.checkpoint.path))) publication;
      if mode = "published_hook_failure" && point = Runner.Published then failwith "injected published hook failure" in
    let persist execution =
      if mode = "launch_record_failure" then Unix.chmod (text (value "workspace")) 0o700;
      Result_store.save_json (text (value "summary_path")) (Runner.to_json ~run_json:(fun () -> J.null) execution) in
    let plan = checked (Execution_plan.of_json (value "plan")) in
    let result = Runner.execute ?initial:(Segment_service.initial service) ~persist ~lifecycle
      ~attempt_id:(text (value "attempt_id")) plan {callbacks with invoke} in
    if mode = "publication_permission" then Unix.chmod (text (value "checkpoint_store")) 0o700;
    if mode = "launch_record_failure" then Unix.chmod (text (value "workspace")) 0o700;
    print_endline (J.canonical (codec (J.object_ ["summary",Runner.to_json ~run_json:(fun () -> J.null) result;
      "diagnostics",Segment_service.diagnostics_json service result;
      "events",J.array (List.map (fun s -> codec (J.string s)) !events)])))
