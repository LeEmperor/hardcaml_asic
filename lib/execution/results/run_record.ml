module J = Identity_json
let codec = function Ok x -> x | Error e -> failwith (J.error_message e)
let s x = codec (J.string x)
let obj x = codec (J.object_ x)
type status = Starting | Running | Completed | Failed | Interrupted
let status_name = function Starting -> "starting" | Running -> "running" | Completed -> "completed" | Failed -> "failed" | Interrupted -> "interrupted"
type t = (string * J.t) list ref
let set t k v = t := (k,v) :: List.remove_assoc k !t
let status t st = set t "status" (s (status_name st))
let stage_name = function Execution_plan.Coarse.Synthesis -> "synthesis" | Full -> "full"
let create (a : Result_store.allocation) ~bundle ~build_identity ~manifest_sha256 ~stage = ref
  ["schema_version",codec (J.integer "1");"run_id",s a.identity;
   "execution_binding_required",J.bool true;"build_identity",build_identity;"bundle",s bundle;
   "manifest_sha256",s manifest_sha256;"started_at",s a.created_at;"ended_at",J.null;
   "requested_stage",s (stage_name stage);"completed_stage",J.null;"status",s "starting";
   "commands",J.array [];"logs",J.array [s "execution.log"];
   "outputs",obj ["project",s "project";"flow",s "project/runs/asic"]]
let command t argv = let old = match List.assoc "commands" !t with J.Array xs -> xs | _ -> [] in
  set t "commands" (J.array (old @ [J.array (List.map s argv)]))
let finish t st ~ended_at ?error ?interrupted_by () =
  status t st; set t "ended_at" (s ended_at);
  Option.iter (fun x -> set t "error" (s x)) error;
  Option.iter (fun x -> set t "interrupted_by" (s x)) interrupted_by
let to_json t = obj !t
type outcome = { run_id : string; run_dir : string; run_record : string; status : status; exit_code : int }
let outcome (a : Result_store.allocation) ~status ~exit_code =
  {run_id=a.identity;run_dir=a.directory;run_record=a.directory ^ "/run.json";status;exit_code}
let outcome_json o = obj ["run_id",s o.run_id;"run_dir",s o.run_dir;"run_record",s o.run_record;
  "status",s (status_name o.status);"exit_code",codec (J.integer (string_of_int o.exit_code))]
