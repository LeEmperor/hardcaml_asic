[@@@alert "-unsafe_multidomain"]
module J = Identity_json
module R = Result_store
module P = Hardcaml_asic.Resource_preparation
let codec = function Ok x -> x | Error e -> invalid_arg (J.error_message e)
let s x = codec (J.string x)
let obj x = codec (J.object_ x)
let num n = codec (J.integer (string_of_int n))
let checked = function Ok x -> x | Error e -> invalid_arg e
let library = function Ok x -> x | Error e -> invalid_arg (Core.Error.to_string_hum e)
let now () = let t=Unix.gettimeofday () in
  let tm=Unix.gmtime t in Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
    (tm.tm_year+1900) (tm.tm_mon+1) tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec
type prepare = on_phase:(P.Phase.t -> unit) -> (P.t,P.Failure.t) result
type outcome = { directory : string; record : Preparation_record.t }
exception Cancelled of int
exception Source_failure of P.Failure.t
let active = ref false
let run_with ~save_bytes ~store ~request ~prepare ?allocated () =
  if !active then invalid_arg "preparation runner is non-reentrant";
  (match request with J.Object _ -> () | _ -> invalid_arg "preparation request must be an object");
  active:=true;
  Fun.protect ~finally:(fun () -> active:=false) (fun () ->
    let signal=ref None in
    let committing=ref false and deferred=ref [] and commit_mask=ref None in
    let handler n =
      if !committing then (if not (List.mem n !deferred) then deferred:=n::!deferred)
      else if !signal=None then signal:=Some (if n=Sys.sigint then 2 else 15) in
    let old_int=Sys.signal Sys.sigint (Sys.Signal_handle handler) in
    let old_term=try Sys.signal Sys.sigterm (Sys.Signal_handle handler) with exn -> Sys.set_signal Sys.sigint old_int; raise exn in
    Fun.protect ~finally:(fun () ->
      (* Kernel-pending commit signals remain blocked until the old handlers are
         restored. Requeue any already dispatched runtime callbacks too. *)
      Sys.set_signal Sys.sigint old_int;Sys.set_signal Sys.sigterm old_term;
      List.iter (fun n->Unix.kill (Unix.getpid ()) n) !deferred;
      Option.iter (fun mask->ignore (Unix.sigprocmask Unix.SIG_SETMASK mask)) !commit_mask) (fun () ->
      let a=R.allocate store in
      let fields=ref ["contract",s Preparation_record.contract;"schema_version",num 1;
        "operation",Preparation_record.descriptor ();"attempt_id",s a.identity;
        "status",s "running";"phase",s "constructing_project";
        "started_at",s (now ());"ended_at",J.null;"exit_code",J.null;
        "request",request;"snapshot",J.null;"diagnostic",J.null] in
      let set k v = fields:=(k,v)::List.remove_assoc k !fields in
      let save () = let raw=obj !fields in ignore (checked (Preparation_record.of_json raw));
        save_bytes (a.directory^"/operation.json") (R.record_bytes raw) in
      save ();
      let check_cancel () = Option.iter (fun n -> raise (Cancelled n)) !signal in
      let phase name = check_cancel ();set "phase" (s name);save ();check_cancel () in
      let failure exn =
        let interrupted = match !signal,exn with Some n,_->Some n | None,Cancelled n->Some n | _->None in
        let code,message,detail = match exn with
          | Source_failure f ->
            set "phase" (s (P.Phase.to_string f.phase));
            "preparation_rejected","Project resource preparation failed",
            codec (J.parse (Yojson.Safe.to_string (P.Failure.to_json f)))
          | _ -> "preparation_exception",Printexc.to_string exn,J.null in
        let phase=List.assoc "phase" !fields in
        set "status" (s (if interrupted=None then "failed" else "interrupted"));
        set "exit_code" (num (match interrupted with None->1 | Some n->128+n));
        set "snapshot" J.null;
        set "diagnostic" (obj ["phase",phase;"code",s (if interrupted=None then code else "interrupted");
          "message",s (if interrupted=None then message else "Preparation interrupted");
          "detail",detail;"signal",(match interrupted with None->J.null | Some n->num n)]) in
      (try
        Option.iter (fun f -> f ~directory:a.directory ~attempt_id:a.identity) allocated;
        check_cancel ();
        let result=match prepare ~on_phase:(fun p -> phase (P.Phase.to_string p)) with
          | Ok p -> p
          | Error f ->
            (* Failure records are publicly constructible. Validate inside this
               protected path so malformed callback data becomes a durable
               preparation_exception, never an unrecordable terminal failure. *)
            let validated=library (P.Failure.of_json (P.Failure.to_json f)) in
            raise (Source_failure validated) in
        check_cancel ();
        let bytes=P.to_string result in
        (* The library is the identity authority. Execution only hashes file bytes. *)
        let verified=library (P.of_string bytes) in
        if P.identity verified<>P.identity result then invalid_arg "preparation identity changed during encoding";
        phase "publishing";
        save_bytes (a.directory^"/resources.json") bytes;
        let retained=Preparation_storage.read_bytes ~limit:Preparation_storage.snapshot_limit (a.directory^"/resources.json") in
        if retained<>bytes then invalid_arg "published preparation snapshot bytes changed";
        check_cancel ();
        set "snapshot" (obj ["path",s "resources.json";"identity",s (P.identity verified);
          "sha256",s (J.sha256_bytes bytes);"bytes",num (String.length bytes)]);
        set "status" (s "completed"); set "phase" (s "finished");set "exit_code" (num 0)
       with exn -> failure exn);
      (* Cancellation cutoff: block INT/TERM, then account for the signals already
         observed by our handler. After this final check the terminal commit is
         noncancellable. Later signals belong to the restored caller, not to an
         operation record which may already be terminal. *)
      commit_mask:=Some (Unix.sigprocmask Unix.SIG_BLOCK [Sys.sigint;Sys.sigterm]);
      (match !signal with None->() | Some n->failure (Cancelled n));
      committing:=true;
      set "ended_at" (s (now ()));
      (* Outside the exception handler: terminal publication failure must propagate,
         never be converted into a successful in-memory outcome or retried write. *)
      save ();
      let expected=obj !fields in
      let retained=Preparation_storage.read_bytes ~limit:Preparation_storage.operation_limit (a.directory^"/operation.json") in
      if retained<>R.record_bytes expected then invalid_arg "terminal preparation record bytes changed";
      let record=checked (Preparation_record.of_json (codec (J.parse retained))) in
      {directory=a.directory;record}))
let run = run_with ~save_bytes:R.save_bytes
let run_cli ~store ~request ~prepare ~json () =
  let o=run ~store ~request ~prepare ~allocated:(fun ~directory ~attempt_id ->
    if json then print_endline (J.canonical (obj ["contract",s Preparation_record.contract;
      "schema_version",num 1;"event",s "allocated";"attempt",s directory;"attempt_id",s attempt_id]))
    else Printf.printf "Preparation allocated\nAttempt: %s\nAttempt ID: %s\n%!" directory attempt_id;
    flush stdout) () in
  if json then print_endline (J.canonical (obj ["contract",s Preparation_record.contract;
    "schema_version",num 1;"event",s "terminal";"attempt",s o.directory;
    "record",Preparation_record.to_json o.record]))
  else (
    let inspection=checked (Preparation_inspection.inspect o.directory) in
    print_string (Preparation_inspection.render inspection));
  flush stdout;o
module For_testing = struct let run = run_with end
