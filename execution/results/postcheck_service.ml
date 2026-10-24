[@@@alert "-unsafe_multidomain"]
module J = Identity_json
module E = Evidence_json
module R = Result_store
module T = Execution_transport
let codec = function Ok x -> x | Error e -> failwith (J.error_message e)
let checked = function Ok x -> x | Error e -> failwith e
let s x = codec (J.string x)
let obj x = codec (J.object_ x)
let get j k = match j with J.Object xs -> Option.value (List.assoc_opt k xs) ~default:J.null | _ -> J.null
let text = function J.String x -> x | _ -> failwith "expected string"
let read p = let ch = open_in_bin p in Fun.protect ~finally:(fun () -> close_in_noerr ch)
  (fun () -> let n=in_channel_length ch in if n>1048576 then failwith ("probe/input exceeds 1 MiB: "^p); really_input_string ch n)
let json p = codec (R.read_json p)
let resolve p =
  let rec loop n p =
    if n > 40 then failwith ("symlink loop: " ^ p);
    let p = if Filename.is_relative p then Filename.concat (Sys.getcwd ()) p else p in
    let parent = Filename.dirname p in if parent=p then p else
    let parent = loop n parent in match Filename.basename p with
    | "." -> parent | ".." -> Filename.dirname parent
    | name -> let p = Filename.concat parent name in
      try if (Unix.lstat p).Unix.st_kind=Unix.S_LNK then
        let target = Unix.readlink p in loop (n+1) (if Filename.is_relative target then Filename.concat parent target else target)
      else p with Unix.Unix_error ((Unix.ENOENT|Unix.ENOTDIR),_,_) -> p in loop 0 p
let hash p = (checked (Checkpoint.file_record p)).sha256
let rec mkdir p = if not (Sys.file_exists p) then (mkdir (Filename.dirname p); Unix.mkdir p 0o777)
let copy src dst =
  let ic = open_in_bin src in Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
    let oc = open_out_bin dst in Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
      let b = Bytes.create 65536 in let rec loop () = let n = input ic b 0 (Bytes.length b) in
        if n>0 then (output oc b 0 n; loop ()) in loop ()));
  Unix.chmod dst (Unix.stat src).Unix.st_perm
let rec copy_tree src dst = Unix.mkdir dst 0o777;
  Array.iter (fun name -> let a=src^"/"^name and b=dst^"/"^name in
    match (Unix.stat a).Unix.st_kind with Unix.S_DIR -> copy_tree a b | Unix.S_REG -> copy a b
    | _ -> failwith ("unsupported precheck entry: "^a)) (Sys.readdir src)
let now () = let t = Unix.gettimeofday () in let sec = floor t in let tm = Unix.gmtime sec in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d.%06d+00:00" (tm.tm_year+1900) (tm.tm_mon+1) tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec (int_of_float ((t-.sec)*.1e6))
let message = function Failure x | Invalid_argument x -> x | Runner.Callback_error e -> e.message | e -> Printexc.to_string e
external enter_affinity : unit -> string = "hardcaml_postcheck_affinity_enter"
external leave_affinity : string -> unit = "hardcaml_postcheck_affinity_leave"
type outcome = {check_id:string;check_dir:string;check_record:string;status:string;exit_code:int}
let outcome_json o = obj ["check_id",s o.check_id;"check_dir",s o.check_dir;"check_record",s o.check_record;
  "status",s o.status;"exit_code",codec (J.integer (string_of_int o.exit_code))]
let run ~run_dir ~support_tools ~pdk_root ~precheck_python ~testbench ~testbench_top ~environment
    ?context ?replay_trace ?timeout () =
  Option.iter (fun t -> if not (Float.is_finite t) || t<=0. then invalid_arg "finite positive timeout required") timeout;
  let run_dir=resolve run_dir and support_tools=resolve support_tools and pdk_root=resolve pdk_root in
  let testbench=resolve testbench and precheck_python=checked (Checkpoint.absolute_path precheck_python) in
  let replay_trace=Option.map resolve replay_trace in
  let evidence=match context with None -> E.value (E.read (run_dir^"/run.json")) | Some j -> j in
  let run=match evidence with `Assoc xs ->
    let selected=List.filter (fun (k,_) -> List.mem k ["run_id";"build_identity";"status";"completed_stage";"outputs";
      "environment";"execution_binding";"execution_binding_required";"evidence_origin"]) xs in
    codec (J.parse (E.record_bytes (`Assoc selected))) | _ -> invalid_arg "postcheck context must be an object" in
  if get run "status"<>s "completed" || get run "completed_stage"<>s "full" then
    invalid_arg "postcheck requires a completed full flow";
  let flow=text (get (get run "outputs") "flow") in
  let flow=if Filename.is_relative flow then Filename.concat run_dir flow else flow in
  let manifest=json (run_dir^"/project/manifest.json") in
  Macro_contract.require_synthesis manifest;
  let top=text (get manifest "top_module") in
  let gds=flow^"/final/gds/"^top^".gds" and netlist=flow^"/final/nl/"^top^".nl.v" in
  List.iter (fun p -> if not (try (Unix.stat p).Unix.st_kind=Unix.S_REG with _ -> false) then
    invalid_arg ("missing postcheck input: "^p))
    ([gds;netlist;testbench;precheck_python;support_tools^"/precheck/default.nix"] @ Option.to_list replay_trace);
  let signal=ref None in let handler n = if !signal=None then signal:=Some n in
  let old_int=Sys.signal Sys.sigint (Sys.Signal_handle handler) and old_term=Sys.signal Sys.sigterm (Sys.Signal_handle handler) in
  let cancel () = !signal in
  let check_cancel () = match !signal with None -> () | Some _ -> failwith "postcheck interrupted" in
  Fun.protect ~finally:(fun () -> Sys.set_signal Sys.sigint old_int; Sys.set_signal Sys.sigterm old_term) (fun () ->
  let a=R.allocate ~uuid_directory:true (run_dir^"/checks") in
  let check_id=Filename.basename a.directory and check_dir=a.directory in
  let check_record=check_dir^"/postcheck.json" in
  let fields=ref ["schema_version",codec (J.integer "1");"run_id",get run "run_id";"build_identity",get run "build_identity";
    "started_at",s (now ());"ended_at",J.null;"status",s "running";"commands",J.array [];
    "checks",obj ["precheck",s "pending";"gate_level",s "pending"];
    "inputs",obj ["gds_sha256",s (hash gds);"netlist_sha256",s (hash netlist);"testbench_sha256",s (hash testbench);"testbench_top",s testbench_top];
    "logs",J.array [s "postcheck.log"];"tools",obj [];
    "resource_limits",obj ["host_cpu_affinity_max",codec (J.integer "20");"tool_threads",codec (J.integer "20");
      "container_cpus",codec (J.integer "20");"tool_timeout_seconds",(match timeout with None -> J.null | Some t -> codec (J.float t));
      "cleanup_timeout_seconds",codec (J.integer "5")]] in
  let set k v = fields := (k,v)::List.remove_assoc k !fields in
  let put k name v = let xs=match List.assoc k !fields with J.Object xs -> xs | _ -> [] in set k (obj ((name,v)::List.remove_assoc name xs)) in
  let append k v = let xs=match List.assoc_opt k !fields with Some (J.Array xs) -> xs | _ -> [] in set k (J.array (xs@[v])) in
  let save () = R.save_json check_record (obj !fields) in
  Option.iter (fun _ -> set "evidence_origin" (get run "evidence_origin")) context;
  save ();
  let env=ref (T.clean_environment environment) in
  let env_set key value = env:=List.filter (fun x -> not (String.starts_with ~prefix:(key^"=") x)) !env @ [key^"="^value] in
  env_set "PDK_ROOT" pdk_root; env_set "PDK" "ihp-sg13cmos5l";
  List.iter (fun k -> env_set k "20") ["OMP_NUM_THREADS";"OPENROAD_THREADS";"_OPENLANE_MAX_CORES";"NIX_BUILD_CORES"];
  let serial=ref 0 in
  let work=check_dir^"/tt" in
  let status,exit_code = try
    let affinity=enter_affinity () in
    Fun.protect ~finally:(fun () -> leave_affinity affinity) (fun () ->
    let launch ?(logged=false) ?docker ~cwd argv =
      check_cancel (); incr serial;
      let base=check_dir^"/command-"^string_of_int !serial in
      let prog=match docker with None -> Runtime_probe.find_executable ~environment:!env (List.hd argv) | Some _ -> List.hd argv in
      let argv=prog::List.tl argv in
      let log=if logged then Some (open_out_gen [Open_wronly;Open_creat;Open_append;Open_binary] 0o600 (check_dir^"/postcheck.log")) else None in
      Fun.protect ~finally:(fun () -> Option.iter close_out_noerr log) (fun () ->
      let out=if logged then check_dir^"/postcheck.log" else base^".stdout" in
      let err=if logged then out else base^".stderr" in
      let stdout,stderr=match log with
        | Some oc -> let output=Process.Descriptor (Unix.descr_of_out_channel oc) in output,output
        | None -> Process.File out,Process.File err in
      let invocation=Option.map (fun d -> T.docker_invocation d ~project:run_dir ~pdk_root ~workdir:check_dir ~entrypoint:"env" ~interpreter:false
          ~arguments:argv ~cwd ~environment:!env ~stdout ~stderr ()) docker in
      let spec=match invocation with Some i -> T.process_specification i | None ->
        Process.make ~prog ~argv ~cwd ~environment:!env ~stdout ~stderr in
      Option.iter (fun i -> Option.iter (fun (_,name) -> set "simulator_container_name" (s name)) (T.container i)) invocation;
      if logged then append "commands" (J.array (List.map s spec.argv));
      append "processes" (obj ["argv",J.array (List.map s spec.argv);"stdout",s (Filename.basename out);"stderr",s (Filename.basename err)]); save ();
      Option.iter (fun oc -> output_string oc ("\n$ "^String.concat " " (List.map Filename.quote spec.argv)^"\n"); flush oc) log;
      let result=match invocation with Some i -> T.run ?timeout ~cancel i | None ->
        {T.process=Process_supervisor.run ?timeout ~cancel spec;cleanup=None} in
      let outcome,code=match result.process.outcome with
        | Process_supervisor.Exited n -> "exited",codec (J.integer (string_of_int n))
        | Cancelled n -> "cancelled",codec (J.integer (string_of_int n))
        | Signaled n -> "signaled",codec (J.integer (string_of_int n))
        | Timed_out -> "timed_out",J.null | Failed _ -> "failed",J.null in
      append "process_results" (obj ["outcome",s outcome;"code_or_ocaml_signal",code;
        "elapsed_seconds",codec (J.float result.process.elapsed_seconds);"succeeded",J.bool (T.succeeded result);
        "error",(match result.process.outcome with Failed e -> s e | _ -> J.null)]);
      Option.iter (fun (c:T.cleanup) -> List.iter (fun (a:T.removal) ->
        let outcome,code=match a.result.outcome with
          | Process_supervisor.Exited n -> "exited",codec (J.integer (string_of_int n))
          | Cancelled n -> "cancelled",codec (J.integer (string_of_int n))
          | Signaled n -> "signaled",codec (J.integer (string_of_int n))
          | Timed_out -> "timed_out",J.null | Failed _ -> "failed",J.null in
        append "container_cleanup" (obj (["status",s (if Process_supervisor.succeeded a.result then "removed-or-absent" else "failed");
          "outcome",s outcome;"code_or_ocaml_signal",code] @
          if Process_supervisor.succeeded a.result then [] else ["error",s a.diagnostic]));
        match a.result.outcome with Process_supervisor.Cancelled n -> if !signal=None then signal:=Some n | _ -> ()) c.attempts) result.cleanup;
      (match result.process.outcome with Process_supervisor.Cancelled n -> if !signal=None then signal:=Some n | _ -> ());
      save (); check_cancel ();
      (match result.process.outcome with Process_supervisor.Timed_out -> failwith "postcheck tool timed out" | Failed e -> failwith e | _ -> ());
      Option.iter (fun (c:T.cleanup) -> Option.iter (fun e -> failwith ("owned container cleanup failed: "^e)) c.error) result.cleanup;
      T.succeeded result,(if not logged && Sys.file_exists out then String.trim (read out) else "")) in
    let probe ?docker ~cwd argv = let ok,out=launch ?docker ~cwd argv in
      if not ok then failwith ("command failed: "^String.concat " " argv^": "^
        String.trim (read (check_dir^"/command-"^string_of_int !serial^".stderr"))) else out in
    mkdir work; copy_tree (support_tools^"/precheck") (work^"/precheck");
    Unix.symlink (resolve (support_tools^"/tech")) (work^"/tech");
    let cwd=work^"/precheck" in
    let pin=text (get (json (cwd^"/tool-versions.json")) "klayout") in
    let nix=read (cwd^"/default.nix") in
    let re=Str.regexp "fetchTarball[ \n\r\t]*\"\\([^\"]+\\)\"" in
    (try ignore (Str.search_forward re nix 0); env_set "NIX_PATH" ("nixpkgs="^Str.matched_group 1 nix) with Not_found -> ());
    let nix_shell=Runtime_probe.find_executable ~environment:!env "nix-shell" in
    let actual=probe ~cwd [nix_shell;"default.nix";"--run";"klayout -v"] in
    put "tools" "klayout" (s actual); put "tools" "klayout_requested" (s pin); save ();
    if actual<>"KLayout "^pin then failwith ("precheck KLayout "^actual^"; requested "^pin);
    let version=probe ~cwd [precheck_python;"-c";"from importlib.metadata import version; print(version('klayout'))"] in
    put "tools" "precheck_python_klayout" (s version); save ();
    if not (String.starts_with ~prefix:"0.28." version) then failwith "precheck Python KLayout package must be 0.28.x";
    let binding=get run "execution_binding" in
    let has_binding=match run with J.Object xs -> List.mem_assoc "execution_binding" xs | _ -> false in
    let saved=get (get run "environment") "execution_binding" in
    let environment_has_binding=match get run "environment" with J.Object xs -> List.mem_assoc "execution_binding" xs | _ -> false in
    if not has_binding && (get run "execution_binding_required"=J.bool true || environment_has_binding) then failwith "new run is missing execution binding";
    let docker = if has_binding then (
      let b=checked (T.of_json binding) in
      let d=match b with T.Docker d -> d | _ -> failwith "new native run has no recorded container simulator binding" in
      if saved<>J.null && saved<>binding then failwith "run binding differs from saved preflight binding";
      put "tools" "execution_binding" binding; save ();
      let info=codec (J.parse (probe ~cwd [d.executable;"info";"--format";"{{json .}}"])) in
      put "tools" "execution_engine" (checked (Runtime_evidence.verify_engine d info)); save ();
      let actual_id=probe ~cwd [d.executable;"image";"inspect";"--format";"{{.Id}}";d.image_id] in
      checked (Runtime_evidence.verify_image d ~actual_id);
      put "tools" "simulator_image" (s actual_id); d
    ) else (
      let executable=Runtime_probe.find_executable ~environment:!env "docker" in
      let declared_ref="ghcr.io/librelane/librelane:"^text (get (get (get run "environment") "requested") "librelane") in
      let image_id=probe ~cwd [executable;"image";"inspect";"--format";"{{.Id}}";declared_ref] in
      put "tools" "simulator_image" (s image_id);
      match T.docker ~executable ~rootless:false ~server_version:"historical-unrecorded" ~declared_ref ~image_id
        ~repo_digests:[] ~os:"linux" ~architecture:"historical-unrecorded" ~flags:T.Bytecode_disabled () with T.Docker d -> d | _ -> assert false) in
    let iverilog=probe ~docker ~cwd:check_dir ["iverilog";"-V"] in
    put "tools" "iverilog" (s (List.hd (String.split_on_char '\n' iverilog))); save ();
    let env_tool=Runtime_probe.find_executable ~environment:!env "env" in
    let shell="exec "^Filename.quote env_tool^" -u PYTHONPATH -u PYTHONHOME "^
      String.concat " " (List.map Filename.quote [precheck_python;"precheck.py";"--gds";gds;"--tech";"ihp-sg13cmos5l"]) in
    let ok,_=launch ~logged:true ~cwd [nix_shell;"default.nix";"--run";shell] in
    put "checks" "precheck" (s (if ok then "pass" else "fail")); save ();
    let cells=pdk_root^"/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog/" in
    let models=[pdk_root^"/ihp-sg13cmos5l/libs.ref/sg13cmos5l_io/verilog/sg13cmos5l_io.v";cells^"sg13cmos5l_udp.v";cells^"sg13cmos5l_stdcell.v"] in
    if not (List.for_all Sys.file_exists models) then failwith "missing gate-level PDK Verilog models";
    let tb=check_dir^"/testbench.v" in copy testbench tb;
    let simulation_args=match replay_trace with None -> [] | Some p -> let trace=check_dir^"/replay-trace.txt" in
      copy p trace; put "inputs" "replay_trace_sha256" (s (hash trace)); save (); ["+trace="^trace] in
    let executable=check_dir^"/gate.out" in
    let compiled,_=launch ~logged:true ~docker ~cwd:check_dir (["iverilog";"-g2012";"-DFUNCTIONAL";"-DSIM";"-s";testbench_top;"-o";executable]@models@[netlist;tb]) in
    let replayed=if not compiled then false else fst (launch ~logged:true ~docker ~cwd:check_dir (["vvp";executable]@simulation_args)) in
    put "checks" "gate_level" (s (if replayed then "pass" else "fail"));
    if ok && replayed then "completed",0 else "failed",1)
  with e ->
    (match e with Runner.Callback_error {kind=Runner.Cancellation n;_} -> signal:=Some (if n=2 then Sys.sigint else Sys.sigterm) | _ -> ());
    match !signal with
    | Some n -> let name,code=if n=Sys.sigint then "SIGINT",130 else "SIGTERM",143 in
      set "interrupted_by" (s name); set "error" (s ("interrupted by "^name)); "interrupted",code
    | None -> set "error" (s (message e)); "failed",1 in
  let reports=work^"/precheck/reports" in
  let names=if Sys.file_exists reports && Sys.is_directory reports then Array.to_list (Sys.readdir reports) |> List.sort String.compare else [] in
  set "reports" (J.array (List.filter_map (fun n -> let p=reports^"/"^n in
    if (try (Unix.stat p).Unix.st_kind=Unix.S_REG with _ -> false) then Some (s ("tt/precheck/reports/"^n)) else None) names));
  set "status" (s status); set "ended_at" (s (now ())); save ();
  {check_id;check_dir;check_record;status;exit_code})
