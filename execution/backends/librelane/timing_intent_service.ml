module J = Identity_json
module T = Execution_transport
let checked = function Ok x -> x | Error s -> failwith s
let codec = function Ok x -> x | Error e -> failwith (J.error_message e)
let s x = codec (J.string x)
let obj xs = codec (J.object_ xs)
let int n = codec (J.integer (string_of_int n))
let get j k = match j with J.Object xs -> List.assoc k xs | _ -> invalid_arg "run object required"
let hash p = (checked (Checkpoint.file_record p)).sha256
let posix_signal n =
  match List.assoc_opt n [Sys.sighup,1;Sys.sigint,2;Sys.sigquit,3;Sys.sigill,4;Sys.sigtrap,5;
    Sys.sigabrt,6;Sys.sigbus,7;Sys.sigfpe,8;Sys.sigkill,9;Sys.sigusr1,10;
    Sys.sigsegv,11;Sys.sigusr2,12;Sys.sigpipe,13;Sys.sigalrm,14;Sys.sigterm,15;
    Sys.sigchld,17;Sys.sigcont,18;Sys.sigstop,19;Sys.sigtstp,20;
    Sys.sigttin,21;Sys.sigttou,22;Sys.sigurg,23;Sys.sigxcpu,24;Sys.sigxfsz,25;
    Sys.sigvtalrm,26;Sys.sigprof,27;Sys.sigpoll,29;Sys.sigsys,31] with
  | Some p -> p | None when n>0 && n<128 -> n | None -> failwith "unknown process signal"
let capture ?(timeout=600.) ~run_dir ~context ~binding ~pdk_root ~resources ~environment ~cancel ~verify_runtime () =
  let docker=match binding with T.Docker d -> d | T.Native _ -> failwith "PT7 linked synthesis requires qualified immutable Docker runtime" in
  if docker.image_id<>Hardcaml_asic_flow_domain.Backends.Librelane.Mapping.tested_image_id then
    failwith "PT7 linked synthesis requires the qualified immutable image";
  checked (verify_runtime ());
  let dir=run_dir^"/timing-intent" in
  Unix.mkdir dir 0o700;
  let helper=resources^"/timing_intent_runtime.py" in
  let helper_hash=hash helper in
  let staged=dir^"/timing_intent_runtime.py" in
  let ic=open_in_bin helper in
  Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
    let oc=open_out_bin staged in
    Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
      let b=Bytes.create 65536 in
      let rec copy ()=let n=input ic b 0 (Bytes.length b) in if n>0 then (output oc b 0 n;copy ()) in copy ()));
  if hash staged<>helper_hash || hash helper<>helper_hash then failwith "PT7 runtime helper changed while staging";
  let request=obj ["schema",int 1;"run_id",get context "run_id";"build_identity",get context "build_identity";
    "manifest_sha256",get context "manifest_sha256";"analysis_id",get context "run_id";
     "synthesis_process",get context "synthesis_process";
    "execution_root",s run_dir;"host_uid",int (Unix.getuid ());"host_gid",int (Unix.getgid ());
    "binding",T.to_json binding;"pdk_root",s pdk_root;"helper_sha256",s helper_hash;
    "producer_sha256",s (hash (run_dir^"/project/constraints/pt7-native-coverage.tcl"))] in
  let request_path=dir^"/request.json" in
  Result_store.save_json request_path request;
  let request_hash=hash request_path in
  let invocation=T.docker_invocation docker ~project:run_dir ~pdk_root ~workers:6 ~workdir:(run_dir^"/project")
    ~interpreter:true ~arguments:[staged;request_path] ~cwd:(run_dir^"/project") ~environment
    ~stdout:(Process.File (dir^"/runtime.log")) ~stderr:(Process.File (dir^"/runtime.log")) () in
  let spec=T.process_specification invocation in
  Result_store.save_json (dir^"/transport.json") (obj ["request_sha256",s request_hash;
    "binding",T.to_json binding;"argv",J.array (List.map s spec.argv);
    "workers",int 6;"sta_threads",int 1;"timeout_seconds",codec (J.float timeout)]);
  let result=T.run ~timeout ~cancel invocation in
  let outcome,code=match result.process.outcome with
    | Exited n -> "exited",int n | Cancelled n -> "cancelled",int (if n=Sys.sigint || n=2 then 2 else 15)
    | Signaled n -> "signaled",int (posix_signal n) | Timed_out -> "timed_out",J.null | Failed _ -> "failed",J.null in
  let cleanup_errors=List.filter_map Fun.id [result.process.cleanup_error;
    (match result.cleanup with Some c -> c.error | None -> None)] in
  Result_store.save_json (dir^"/transport-result.json") (obj ["request_sha256",s request_hash;
    "succeeded",J.bool (T.succeeded result);"outcome",s outcome;"code",code;
    "cleanup_error",(match cleanup_errors with [] -> J.null | xs -> s (String.concat "; " xs))]);
  let intact=hash helper=helper_hash && hash staged=helper_hash && hash request_path=request_hash in
  let verified=if T.succeeded result && intact then verify_runtime () else Error "linked STA transport/input failure" in
  let success=T.succeeded result && intact && verified=Ok () in
  let context=Yojson.Safe.from_string (J.canonical context) in
  Timing_intent_flow.publish ~run_dir ~context ~succeeded:success ();
  if not success then (
    match result.process.outcome with
    | Cancelled n -> raise (Runner.Callback_error (Runner.cancellation ~signal:(if n=Sys.sigint || n=2 then 2 else 15) "PT7 linked STA interrupted"))
    | Timed_out -> raise (Runner.Callback_error (Runner.failure ~exit_code:124 "PT7 linked STA timed out"))
    | _ -> failwith ("PT7 linked STA failed; retained timing-intent companion: " ^
        (match verified with Error e -> e | Ok () -> "process did not complete")));
  match Timing_intent_flow.inspect ~run_dir () with
  | Ok _ -> ()
  | Error e -> failwith ("PT7 linked STA evidence invalid: "^e)
