module J = Identity_json
let checked = function Ok x -> x | Error e -> failwith (J.error_message e)
let s x = checked (J.string x)
let i x = checked (J.integer (string_of_int x))
let obj x = checked (J.object_ x)
external lock : Unix.file_descr -> unit = "hardcaml_asic_observation_lock"
external monotonic : unit -> float = "hardcaml_asic_monotonic"
exception Busy
type t = { allocation : Result_store.allocation; workspace_lock : Unix.file_descr;
  activity_lock : Unix.file_descr; clock : unit -> float; wall_clock : unit -> float;
  created : float; mutable elapsed : float; mutable sequence : int;
  mutable previous : string option; mutable current : Observation.state option;
  mutable closed : bool; mutable poisoned : bool }
let directory t = t.allocation.directory
let stream_id t = t.allocation.identity
let preflight_path t = directory t ^ "/preflight.json"
let state t = Option.get t.current
let close t = if not t.closed then (t.closed <- true;
  Fun.protect ~finally:(fun () -> Unix.close t.workspace_lock) (fun () -> Unix.close t.activity_lock))
let stamp time =
  if not (Float.is_finite time) then failwith "invalid wall clock";
  let seconds = floor time in
  let tm = Unix.gmtime seconds in
  let year = tm.Unix.tm_year + 1900 in
  if year < 1 || year > 9999 then failwith "invalid UTC year";
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d.%06dZ" year (tm.tm_mon+1)
    tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec (int_of_float (floor ((time -. seconds) *. 1e6)))
let append t ~name data =
  if t.closed || t.poisoned then failwith "observation writer closed or poisoned";
  try
    let event = match Observation.event_of_json ~name data with Ok e -> e | Error e -> failwith e.detail in
    let current = match Observation.reduce_event t.current ~stream_id:(stream_id t) event with
      Ok x -> x | Error e -> failwith e.detail in
    let elapsed = t.clock () -. t.created in
    if not (Float.is_finite elapsed) || elapsed < t.elapsed then failwith "invalid/regressing observation clock";
    let sequence = t.sequence + 1 in
    let unsigned = obj ["contract",s "hardcaml-asic.stage-observation";"schema_version",i 2;
      "stream_id",s (stream_id t);"sequence",i sequence;
      "previous_sha256",(match t.previous with None -> J.null | Some x -> s x);
      "event",s name;"data",data;"recorded_at",s (stamp (t.wall_clock ()));
      "elapsed_seconds",checked (J.float elapsed)] in
    let hash = J.identity unsigned in
    let value = match unsigned with J.Object xs -> obj (("sha256",s hash)::xs) | _ -> assert false in
    let target = Printf.sprintf "%s/%012d.json" (directory t) sequence in
    let temporary = directory t ^ "/.event-pending.json" in
    let fd = Unix.openfile temporary [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC] 0o600 in
    Unix.close fd;
    Fun.protect ~finally:(fun () -> try Unix.unlink temporary with Unix.Unix_error (Unix.ENOENT,_,_) -> ()) (fun () ->
      Result_store.save_json temporary value;
      Unix.link temporary target);
    t.current <- Some current; t.previous <- Some hash; t.sequence <- sequence; t.elapsed <- elapsed
  with exn -> t.poisoned <- true; raise exn
let canonical_path p = match Checkpoint.absolute_path p with Ok x -> x | Error e -> failwith e
let rec resolve p =
  try Unix.realpath p with Unix.Unix_error (Unix.ENOENT,_,_) ->
    Filename.concat (resolve (Filename.dirname p)) (Filename.basename p)
let create ?(wall_clock=Unix.gettimeofday) ?(clock=monotonic) ?request_for_allocation ~root ~workspace ~checkpoint_store ~request () =
  let workspace = resolve (canonical_path workspace) and checkpoint_store = resolve (canonical_path checkpoint_store) in
  let parent = Unix.realpath (Filename.dirname workspace) in
  let workspace = parent ^ "/" ^ Filename.basename workspace in
  let root = resolve (canonical_path root) in
  if root=workspace || String.starts_with ~prefix:(workspace ^ "/") root then failwith "observation store must be outside workspace";
  let path = parent ^ "/.stage-writer-" ^ J.identity (s workspace) ^ ".lock" in
  let workspace_lock = Unix.openfile path [Unix.O_RDWR;Unix.O_CREAT;Unix.O_CLOEXEC] 0o600 in
  try
    (try lock workspace_lock with Unix.Unix_error ((Unix.EAGAIN | Unix.EACCES),_,_) -> raise Busy);
    let created = clock () in
    if not (Float.is_finite created) then failwith "invalid observation clock";
    let allocation = Result_store.allocate ~clock:wall_clock root in
    if allocation.directory=workspace || String.starts_with ~prefix:(workspace ^ "/") allocation.directory then failwith "resolved observation store inside workspace";
    let activity_lock = Unix.openfile (allocation.directory ^ "/writer.lock") [Unix.O_RDWR;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC] 0o600 in
    try
      lock activity_lock;
      let t = {allocation;workspace_lock;activity_lock;clock;wall_clock;created;elapsed=0.;sequence=0;
        previous=None;current=None;closed=false;poisoned=false} in
      let request = match request_for_allocation with None -> request | Some f -> f ~directory:allocation.directory ~attempt_id:allocation.identity in
      append t ~name:"allocated" (obj ["request",request;"workspace",s workspace;
        "checkpoint_store",s checkpoint_store;"lock_path",s (allocation.directory ^ "/writer.lock");
        "preflight_record",s (preflight_path t)]); t
    with exn -> Unix.close activity_lock; raise exn
  with exn -> Unix.close workspace_lock; raise exn
let planned t plan = append t ~name:"planned" (obj ["plan",Execution_plan.Stage_plan.to_json plan])
let prepared t ~runtime_record = append t ~name:"prepared" (obj ["runtime_record",match runtime_record with None -> J.null | Some p -> s p])
let lifecycle t event _action (o:Runner.occurrence) artifact =
  let artifact = match event,o.status with Runner.Finished,(Runner.Failed | Runner.Interrupted) -> None | _ -> artifact in
  let occurrence = obj ["occurrence_id",s o.occurrence_id;"action_key",s o.action_key;
    "status",s (Runner.status_name o.status);"exit_code",(match o.exit_code with None -> J.null | Some n -> i n);
    "duration_seconds",checked (J.float o.duration_seconds);"best_effort",J.bool o.best_effort;
    "error",(match o.error with None -> J.null | Some x -> s x);"verdict",J.null] in
  append t ~name:(match event with Runner.Started -> "started" | Published -> "published" | Finished -> "finished")
    (obj ["occurrence",occurrence;"artifact",match artifact with None -> J.null | Some p -> Runner.reference_json p.Runner.evidence])
let outcome t ~status ~exit_code ~error = append t ~name:"outcome"
  (obj ["status",s (Runner.status_name status);"exit_code",i exit_code;"error",match error with None -> J.null | Some x -> s x])
let allocation_receipt t = obj ["contract",s "hardcaml-asic.stage-observation";"schema_version",i 1;
  "event",s "observation_allocated";"stream_id",s (stream_id t);"attempt",s (directory t)]
