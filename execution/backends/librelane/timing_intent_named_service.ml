module J = Identity_json
module T = Execution_transport
module Inventory = Timing_intent_inventory
let checked = function Ok x -> x | Error e -> failwith e
let codec = function Ok x -> x | Error e -> failwith (J.error_message e)
let str x = codec (J.string x)
let int x = codec (J.integer (string_of_int x))
let obj xs = codec (J.object_ xs)
let get j k = match j with J.Object xs -> Option.value (List.assoc_opt k xs) ~default:J.null | _ -> J.null
let text = function J.String s -> s | _ -> failwith "named timing: string required"
let hash p = (checked (Checkpoint.file_record p)).sha256
let reference p = obj ["path",str p;"sha256",str (hash p)]
let read p = codec (Result_store.read_json p)
let require b s = if not b then failwith ("named timing: " ^ s)
let source_count_limit = Inventory.max_sources
let source_size_limit = Inventory.max_source_bytes
let source_total_limit = Inventory.max_total_bytes
let source_admission ?(aliases=[]) () =
  let seen=Hashtbl.create 2048 and total=ref 0 in
  fun path ->
    if Hashtbl.mem seen path then false else (
      let stat=Inventory.regular ~aliases path in
      require (Hashtbl.length seen<source_count_limit) "named outer source count exceeds 4096";
      require (stat.st_size<=source_size_limit) "named outer source exceeds 128MiB";
      require (stat.st_size<=source_total_limit - !total) "named outer source bytes exceed 512MiB";
      total:= !total+stat.st_size;Hashtbl.add seen path ();true)
let precheck_sources ?(external_roots=[]) paths =
  ignore (Inventory.admit_paths ~external_roots (List.sort_uniq String.compare paths))
let state_netlist p =
  let ic=open_in_bin p in
  let bytes=Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
    let n=in_channel_length ic in require (n<=64*1024*1024) "native State exceeds bound";
    really_input_string ic n) in
  let state=checked (Backend_state.parse bytes) in
  text (List.assoc "nl" (Backend_state.views state))
let expected manifest = Timing_intent_flow.expected (Yojson.Safe.from_string (J.canonical manifest))
let plan_expected plan =
  let wire=Hardcaml_asic.Methodology_plan.to_yojson plan in
  match wire with `Assoc fields ->
    (match List.assoc "bundle_manifest" fields with
     | `String raw -> Timing_intent_flow.expected (Yojson.Safe.from_string raw)
     | _ -> assert false)
  | _ -> assert false
let profile = "opensta-2.7-native-state-v2"
let validate_plan ~methodology ~initial_checkpoint ~plan manifest =
  if expected manifest then (
    require (Option.is_some methodology) "producer-bearing segmented execution requires a named methodology";
    require (initial_checkpoint=None) "fresh named synthesis only";
    require (get manifest "macro_contract"=J.null) "macro-free named synthesis only";
    (match plan with Execution_plan.Stages p ->
       require (Execution_plan.Stage_plan.schema_version p=4 &&
         Execution_plan.Stage_plan.sequence p=[Execution_plan.Stage.Synthesis] &&
         Execution_plan.Stage_plan.source_boundary p=None) "only schema4 named synthesis endpoint is supported"
     | _ -> failwith "named timing: stage plan required");
    let native = get manifest "timing_native_coverage" in
    require (get native "schema"=int 2 && get native "profile"=str profile &&
      get native "contract"=str "hardcaml-asic.timing-native-coverage" &&
      get native "producer"=str "constraints/pt7-native-coverage.tcl") "unsupported native producer profile")
let expectation ~workspace ~attempt_id =
  require (attempt_id<>"" && Filename.basename attempt_id=attempt_id && attempt_id<>"." && attempt_id<>"..") "invalid attempt";
  let directory=workspace ^ "/timing-intent/" ^ attempt_id in
  obj ["schema_version",int 1;"kind",str "hardcaml-asic.named-timing-expectation";
    "attempt_id",str attempt_id;"occurrence_id",str (attempt_id ^ "/implementation.synthesis");
    "profile",str profile;"directory",str directory;"request",str (directory ^ "/request.json");
    "publication",str (directory ^ "/publication.json");"companion",str (directory ^ "/analysis.json")]
let fresh p value =
  let fd=Unix.openfile p [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL] 0o600 in
  let oc=Unix.out_channel_of_descr fd in
  Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () -> output_string oc (J.canonical value ^ "\n");close_out oc)
let copy source dest =
  let before=hash source in
  let ic=open_in_bin source in
  Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
    let fd=Unix.openfile dest [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL] 0o600 in
    let oc=Unix.out_channel_of_descr fd in
    Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
      let buf=Bytes.create 65536 in
      let rec loop ()=let n=input ic buf 0 (Bytes.length buf) in if n>0 then (output oc buf 0 n;loop ()) in
      loop ();close_out oc));
  require (hash source=before && hash dest=before) "helper changed during copy"
let error_of_exception = function Runner.Callback_error e -> e | exn -> Runner.failure (Printexc.to_string exn)
let failure_json (e:Runner.error) = obj [
  "kind",str (match e.kind with Failure -> "failed" | Cancellation _ -> "interrupted");
  "exit_code",int e.exit_code;"signal",(match e.kind with Failure -> J.null | Cancellation n -> int n);
  "error",str e.message;"secondary",J.array (List.map str e.secondary)]
let add_secondary (e:Runner.error) s = match e.kind with
  | Failure -> Runner.failure ~exit_code:e.exit_code ~secondary:(e.secondary@[s]) e.message
  | Cancellation signal -> Runner.cancellation ~signal ~secondary:(e.secondary@[s]) e.message
let capture ?(timeout=600.) ~workspace ~resources ~methodology ~plan ~expectation:expect ~(occurrence:Runner.occurrence)
    ~(segment:Segment_service.segment) ~(publication:Segment_service.checkpoint Runner.publication)
    ~binding ~pdk_root ~environment ~cancel ~verify_runtime ~verify_inputs () =
  let dir=text (get expect "directory") in
  let publication_path=dir ^ "/publication.json" and request_path=dir ^ "/request.json" in
  let sources=ref [] in
  let aliases=ref [] in
  let roots=[pdk_root;workspace ^ "/project/tt"] in
  let admit=ref (source_admission ()) in
  let source_hash p=Inventory.hash ~aliases:!aliases p in
  let add p = if !admit p then sources:= obj ["path",str p;"sha256",str (source_hash p)] :: !sources in
  let published_companion=ref false in
  let companion_attempted=ref false in
  let recheck () =
    Inventory.validate_aliases ~roots ~external_files:publication.checkpoint.manifest.external_files !aliases;
    List.iter (fun r -> require (source_hash (text (get r "path"))=text (get r "sha256")) "source changed") !sources in
  let companion error =
    recheck ();
    companion_attempted:=true;
    Timing_intent_execution.publish ~directory:dir ~succeeded:(error=None)
      ~failure:(match error with None -> J.null | Some e -> failure_json e) ();
    published_companion:=true in
  let run () =
    require (Float.is_finite timeout && timeout>0.) "finite positive timeout required";
    require (occurrence.Runner.occurrence_id=text (get expect "occurrence_id") &&
      occurrence.action_key="implementation.synthesis" && occurrence.status=Runner.Running && occurrence.exit_code=None)
      "Published running synthesis occurrence required";
    let checkpoint=publication.checkpoint in
    require (publication.evidence.identity=checkpoint.manifest.identity && publication.evidence.path=checkpoint.path &&
      publication.evidence.boundary=Execution_plan.Stage.Synthesis) "synthesis publication mismatch";
    require (get checkpoint.manifest.compatibility "pdk_root"=str pdk_root &&
      get checkpoint.manifest.compatibility "project"=str (workspace ^ "/project")) "checkpoint collateral roots differ";
    require (segment.request.boundary=Execution_plan.Stage.Synthesis && segment.request.operation=Backend_protocol.Execute_segment &&
      segment.request.checkpoint=None && T.succeeded segment.process) "completed fresh synthesis call required";
    checked (verify_runtime ()); checked (verify_inputs ());
    ignore (checked (Checkpoint.validate ~compatibility:checkpoint.manifest.compatibility checkpoint.path));
    require (Backend_protocol.reply_to_json (Segment_service.verify_reply segment.request)=Backend_protocol.reply_to_json segment.reply)
      "originating reply changed";
    require (read (segment.request.candidate ^ "/segment.json")=segment.report.raw) "originating segment report changed";
    require (read (checkpoint.path ^ "/segment.json")=segment.report.raw) "published segment report differs";
    let external_paths=List.filter_map (fun (p,_) -> if String.starts_with ~prefix:"/nix/store/" p then None else Some p)
      checkpoint.manifest.external_files in
    aliases:=Inventory.capture_aliases ~roots ~paths:external_paths;
    Inventory.validate_aliases ~roots ~external_files:checkpoint.manifest.external_files !aliases;
    admit:=source_admission ~aliases:!aliases ();
    let runtime=match binding with T.Docker d when d.image_id=Hardcaml_asic_flow_domain.Backends.Librelane.Mapping.tested_image_id -> d
      | _ -> failwith "named timing: qualified immutable Docker image required" in
    let parent=workspace ^ "/timing-intent" in
    if not (Sys.file_exists parent) then Unix.mkdir parent 0o700;
    require (Unix.realpath parent=parent && (Unix.lstat parent).Unix.st_kind=Unix.S_DIR) "canonical timing parent required";
    Unix.mkdir dir 0o700;
    let candidate=segment.request.candidate in
    List.iter add [segment.request.project ^ "/" ^ segment.request.tag ^ "-request.json";
      segment.request.reply_path;segment.transport_record;segment.transport_result];
    List.iter (fun n -> add (candidate ^ "/" ^ n)) ["state.json";"resolved.json";"closure.json";"segment.json"];
    add (checkpoint.path ^ "/manifest.json");
    List.iter (fun (n,_) -> add (checkpoint.path ^ "/" ^ n)) checkpoint.manifest.files;
    List.iter (fun (p,_) -> if not (String.starts_with ~prefix:"/nix/store/" p) then add p) checkpoint.manifest.external_files;
    (* Retain producer provenance before launch, including failed attempts that
       never produce runtime-result.json. Select by returned position + metadata. *)
    let run_dir=segment.request.project ^ "/src/runs/" ^ segment.request.tag in
    require (get segment.report.raw "run_dir"=str run_dir) "backend run directory differs";
    let steps=match get segment.report.raw "returned_steps" with J.Array xs -> List.map text xs | _ -> failwith "named timing: returned steps required" in
    let positions=List.mapi (fun i step -> i+1,step) steps |> List.filter (fun (_,step) ->
      step="Yosys.Synthesis" || String.starts_with ~prefix:"Yosys.Synthesis-" step) in
    let ordinal=match positions with [ordinal,"Yosys.Synthesis"] when ordinal=List.length steps -> ordinal
      | _ -> failwith "named timing: exact terminal synthesis producer required" in
    let dirs=Array.to_list (Sys.readdir run_dir) |> List.filter (fun name ->
      match String.index_opt name '-' with None -> false | Some k -> int_of_string_opt (String.sub name 0 k)=Some ordinal) in
    let producer=match dirs with [name] -> run_dir ^ "/" ^ name | _ -> failwith "named timing: ambiguous producer position" in
    let config=producer ^ "/config.json" in
    require (get (get (read config) "meta") "step"=str "Yosys.Synthesis") "wrong native producer metadata";
    let native=producer ^ "/state_out.json" in
    List.iter add [config;native;state_netlist native;state_netlist (candidate ^ "/state.json")];
    require (hash (state_netlist native)=hash (state_netlist (checkpoint.path ^ "/state.json"))) "native/publication netlist differs";
    let alias_fields=if !aliases=[] then [] else
      ["external_aliases",codec (J.parse (Yojson.Safe.to_string (Inventory.aliases_to_json !aliases)))] in
    let pub=obj (["schema_version",int 1;"kind",str "hardcaml-asic.named-timing-publication";
      "expectation",expect;"methodology",Methodology_execution_record.to_json methodology;
      "plan",Execution_plan.to_json plan;"occurrence",Runner.occurrence_json occurrence;
      "checkpoint",Runner.reference_json publication.evidence;"request",Backend_protocol.request_to_json segment.request;
      "reply",Backend_protocol.reply_to_json segment.reply;"segment",segment.report.raw;"sources",J.array (List.rev !sources)] @ alias_fields) in
    fresh publication_path pub;add publication_path;
    let helper=dir ^ "/timing_intent_runtime.py" in
    copy (resources ^ "/timing_intent_runtime.py") helper;add helper;
    let project=workspace ^ "/project" in
    let manifest=read (project ^ "/manifest.json") in
    List.iter (fun p -> add (project ^ "/" ^ p)) ["manifest.json";"constraints/top.sdc";"constraints/pt7-native-coverage.tcl"];
    let request=obj ["schema",int 1;"kind",str "hardcaml-asic.named-timing-request";
      "expectation",expect;"publication",reference publication_path;"execution_root",str workspace;"project",str project;
      "analysis_directory",str dir;"host_uid",int (Unix.getuid ());"host_gid",int (Unix.getgid ());
      "binding",T.to_json binding;"pdk_root",str pdk_root;"helper_sha256",str (hash helper);
      "producer_sha256",str (hash (project ^ "/constraints/pt7-native-coverage.tcl"));
      "manifest_sha256",str (hash (project ^ "/manifest.json"));"build_identity",get manifest "identity";
      "analysis_id",str (text (get expect "attempt_id") ^ "/pre-pnr-sta");
      "attempt_id",get expect "attempt_id";"occurrence_id",get expect "occurrence_id";
      "checkpoint",Runner.reference_json publication.evidence;
      "synthesis_run_dir",get segment.report.raw "run_dir";
      "state_path",str (checkpoint.path ^ "/state.json");"resolved_path",str (checkpoint.path ^ "/resolved.json")] in
    fresh request_path request;add request_path;
    let invocation=T.docker_invocation runtime ~workers:6 ~project:workspace ~pdk_root ~workdir:project
      ~interpreter:true ~arguments:[helper;request_path] ~cwd:project ~environment
      ~stdout:(Process.File (dir ^ "/runtime.log")) ~stderr:(Process.File (dir ^ "/runtime.log")) () in
    let spec=T.process_specification invocation in
    fresh (dir ^ "/transport.json") (obj ["request_sha256",str (hash request_path);"binding",T.to_json binding;
      "argv",J.array (List.map str spec.argv);"workers",int 6;"sta_threads",int 1;"timeout_seconds",codec (J.float timeout)]);
    let result=T.run ~timeout ~cancel invocation in
    let outcome,code=match result.process.outcome with
      | Exited n -> "exited",int n | Cancelled n -> "cancelled",int (Segment_service.signal n)
      | Signaled n -> "signaled",int (Segment_service.signal n) | Timed_out -> "timed_out",J.null | Failed _ -> "failed",J.null in
    let errors=List.filter_map Fun.id [result.process.cleanup_error;Option.bind result.cleanup (fun c -> c.T.error)] in
    let process_error=if T.succeeded result then None else Some (Segment_service.process_error result) in
    (try fresh (dir ^ "/transport-result.json") (obj ["request_sha256",str (hash request_path);
      "succeeded",J.bool (T.succeeded result);"outcome",str outcome;"code",code;
      "cleanup_error",(if errors=[] then J.null else str (String.concat "; " errors))])
     with exn -> let e=error_of_exception exn in raise (Runner.Callback_error
       (match process_error with None -> e | Some primary -> add_secondary primary e.message)));
    Option.iter (fun e -> raise (Runner.Callback_error e)) process_error;
    checked (verify_runtime ());checked (verify_inputs ()); recheck ();
    let result=read (dir ^ "/runtime-result.json") in
    require (get result "status"=str "completed" && get result "kind"=str "hardcaml-asic.named-timing-result") "native helper did not complete";
    let audits=match get result "audits" with J.Array [a] -> [a] | _ -> failwith "named timing: exactly one native audit required" in
    List.iter (fun a -> let relative=text (get (get a "audit") "path") in
      let path=workspace ^ "/" ^ relative in
      require (String.starts_with ~prefix:(dir ^ "/") (Unix.realpath path)) "audit escapes analysis";
      ignore (checked (Timing_intent_evidence.inspect ~directory:(Filename.dirname path) ()))) audits;
    companion None in
  try run () with exn ->
    let error=error_of_exception exn in
    let error=try
      if Sys.file_exists publication_path && Sys.file_exists request_path && not !published_companion && not !companion_attempted then (
        let destination=dir ^ "/analysis.json" in
        (match Unix.lstat destination with
         | stat ->
           let kind=match stat.Unix.st_kind with Unix.S_DIR -> "directory" | Unix.S_REG -> "unowned regular file"
             | Unix.S_LNK -> "symlink" | _ -> "special file" in
           failwith ("named timing companion destination obstructed by " ^ kind ^ ": " ^ destination)
         | exception Unix.Unix_error (Unix.ENOENT,_,_) -> companion (Some error)));
      error
    with exn -> add_secondary error ("named timing companion publication failed: " ^ Printexc.to_string exn) in
    raise (Runner.Callback_error error)
