module L = Timing_intent_linked
module J = Identity_json
module Inventory = Timing_intent_inventory
let get = L.get
let text = L.text
let list = L.list
let require = L.require
let exact = L.exact
let equal = L.equal
let read = L.read
let hash = Inventory.hash
let checked = function Ok x -> x | Error e -> invalid_arg e
let wire j = L.normalize (Yojson.Safe.from_string (J.canonical j))
let identity j = match J.parse (Yojson.Safe.to_string j) with Ok j -> j | Error e -> invalid_arg (J.error_message e)
let regular p =
  ignore (L.historical_path (`String p));
  ignore (Inventory.regular p)
let ref_ ?(aliases=[]) p = ignore (Inventory.regular ~aliases p); `Assoc ["path",`String p;"sha256",`String (Inventory.hash ~aliases p)]
let verify_ref ?(aliases=[]) r =
  exact r ["path";"sha256"];
  let p=text (get r "path") in ignore (Inventory.regular ~aliases p);
  require (get r "sha256"=`String (Inventory.hash ~aliases p)) ("changed named source: "^p);p
let absent p = try ignore (Unix.lstat p);false with Unix.Unix_error (Unix.ENOENT,_,_) -> true
let names directory =
  let handle=Unix.opendir directory in
  Fun.protect ~finally:(fun () -> Unix.closedir handle) (fun () ->
    let rec loop n acc=match Unix.readdir handle with
      | "."|".." -> loop n acc
      | name -> require (n<Inventory.max_sources) "named directory entry bound exceeded";loop (n+1) (name::acc)
      | exception End_of_file -> List.sort String.compare acc in loop 0 [])
let unavailable reason = `Assoc ["status",`String "unavailable";"reason",`String reason;
  "verdict",`String "unavailable";"sources",`List []]
let verify_sources ?(aliases=[]) sources =
  let paths=List.map (fun source -> exact source ["path";"sha256"];text (get source "path")) sources in
  ignore (Inventory.admit_paths ~aliases paths);
  List.iter (fun source -> ignore (verify_ref ~aliases source)) sources;
  paths
let bound_source ?(aliases=[]) sources p =
  let r=ref_ ~aliases p in require (List.exists (equal r) sources) ("missing named source: "^p)
let require_source sources p = bound_source sources p;read p
let bundle_paths ~root m =
  let project=root^"/project" in
  let members=list (get m "files") in
  require (List.length members<=Inventory.max_sources) "too many frozen bundle members";
  let paths=List.map (fun entry ->
    exact entry ["path";"sha256"];
    let relative=text (get entry "path") in
    require (L.safe relative) "unsafe frozen bundle member";
    project^"/"^relative) members in
  ignore (Inventory.admit_paths paths);paths
let verify_external_pins ~aliases ~root ~sources ~(checkpoint:Checkpoint.t) m =
  let target=get m "target" in
  let technology=text (get target "technology") in
  require (L.safe technology && Filename.basename technology=technology) "invalid frozen external technology locator";
  let compatibility=wire checkpoint.compatibility in
  require (get compatibility "project"=`String (root^"/project")) "frozen external project root differs from checkpoint";
  let pdk_root=L.historical_path (get compatibility "pdk_root") in
  let refs=list (get target "external_references") in
  require (List.length refs<=Inventory.max_sources) "too many frozen external references";
  let locators=Hashtbl.create 32 and pins=Hashtbl.create 32 in
  let technology_roles=List.map (fun role -> "(Technology_view "^role^")")
    ["Pdk_configuration";"Technology_lef";"Standard_cell_lef";"Standard_cell_gds";"Standard_cell_verilog";"Standard_cell_liberty"] in
  let located=List.map (fun reference ->
    exact reference ["source";"revision";"role";"path";"sha256";"corner"];
    let source=text (get reference "source") and role=text (get reference "role") and path=text (get reference "path") in
    require (L.safe path) ("unsafe frozen external reference path: "^path);
    ignore (text (get reference "revision"));
    let corner=match get reference "corner" with `Null -> None | `String s when s<>"" -> Some s | _ -> invalid_arg "invalid frozen external reference corner" in
    let source,declared=match source,role with
      | "Support_tools","Floorplan_def" ->
        require (corner=None) "unsupported frozen external Floorplan_def corner";
        "Support_tools",root^"/project/tt/"^path
      | ("Pdk"|"PDK"),role when List.mem role technology_roles -> "Pdk",pdk_root^"/"^technology^"/"^path
      | _ -> invalid_arg ("unsupported frozen external source/role locator: "^source^"/"^role) in
    let pin=match get reference "sha256" with
      | `Null -> None
      | `String sha when String.length sha=64 && String.for_all (function '0'..'9'|'a'..'f'->true | _->false) sha -> Some sha
      | _ -> invalid_arg "invalid frozen external pin SHA256" in
    (match Hashtbl.find_opt pins declared,pin with
     | Some old,Some sha when old<>sha -> invalid_arg ("conflicting frozen external pins for exact locator: "^declared)
     | _,Some sha -> Hashtbl.replace pins declared sha
     | _,None -> ());
    let locator=source,role,path,corner in
    require (not (Hashtbl.mem locators locator)) ("duplicate frozen external reference locator: "^source^"/"^role^"/"^path);
    Hashtbl.add locators locator ();
    declared,pin) refs in
  List.iter (fun (declared,pin) -> match pin with None -> () | Some expected ->
    let retained=match List.assoc_opt declared checkpoint.external_files with
      | Some record -> record
      | None -> invalid_arg ("pinned frozen external locator missing from published closure: "^declared) in
    require (retained.sha256=expected) ("frozen external pin differs from published closure: "^declared);
    bound_source ~aliases sources declared;
    require (Inventory.hash ~aliases declared=expected) ("frozen external pin differs from retained bytes: "^declared)) located

let verify_bundle ?(aliases=[]) ~root ~sources ~checkpoint m =
  let members=list (get m "files") in
  let paths=bundle_paths ~root m in
  List.iter2 (fun entry path ->
    bound_source sources path;
    require (get entry "sha256"=`String (hash path)) ("frozen bundle member hash differs: "^text (get entry "path"));
    match List.assoc_opt path checkpoint.Checkpoint.external_files with
    | Some inventory when `String inventory.sha256=get entry "sha256" -> ()
    | _ -> invalid_arg ("frozen bundle member missing/different in published input closure: "^path)) members paths;
  List.iter (fun source ->
    let copy=text (get source "copy") in
    let matches=List.filter (fun entry -> get entry "path"=`String copy) members in
    require (L.safe (text (get source "path")) && copy="inputs/"^text (get source "path") &&
      match matches with [entry] -> get entry "sha256"=get source "sha256" | _ -> false)
      "frozen source-input copy/inventory hash differs") (list (get m "source_inputs"));
  let manifest_path=root^"/project/manifest.json" in
  bound_source sources manifest_path;
  require (equal (read manifest_path) m) "named staged/frozen manifest differs";
  (match List.assoc_opt manifest_path checkpoint.external_files with
   | Some inventory -> require (inventory.sha256=hash manifest_path) "frozen manifest differs from published input closure"
   | None -> invalid_arg "frozen manifest missing from published input closure");
  verify_external_pins ~aliases ~root ~sources ~checkpoint m
let relative root p =
  require (String.starts_with ~prefix:(root^"/") p) "named linked source outside workspace";
  String.sub p (String.length root+1) (String.length p-String.length root-1)
let rec methodology_manifest r = let p=Methodology_execution_record.plan r in
    let j=Hardcaml_asic.Methodology_plan.to_yojson p in
    read_manifest (get j "bundle_manifest")
and read_manifest = function
  | `String raw -> (match Evidence_json.parse ~reject_duplicates:true raw with Ok j -> L.normalize (Evidence_json.value j) | Error e -> invalid_arg e)
  | _ -> invalid_arg "named frozen bundle manifest missing"
let manifest record = match record.Stage_execution_record.methodology with None -> `Null | Some r -> methodology_manifest r

let failure_check a occurrence =
  let failure=get a "failure" in
  if get a "status"=`String "completed" then require (failure=`Null) "completed named analysis has failure"
  else (
    require (get a "status"=`String "failed") "invalid named companion status";
    exact failure ["kind";"exit_code";"signal";"error";"secondary"];
    let kind=get failure "kind" and code=get failure "exit_code" in
    ignore (text (get failure "error"));List.iter (fun x -> ignore (text x)) (list (get failure "secondary"));
    (match kind,code,get failure "signal" with
     | `String "failed",`Int n,`Null when n>0 && n<=255 -> ()
     | `String "interrupted",`Int n,`Int signal when signal>0 && signal<128 && n=128+signal -> ()
     | _ -> invalid_arg "invalid named failure kind/code/signal");
    require (get occurrence "status"=kind && get occurrence "exit_code"=code) "named failure/final occurrence mismatch")

let failure_transport a result =
  if get a "status"=`String "failed" && get result "succeeded"=`Bool false then (
    let kind,code,signal=match get result "outcome",get result "code" with
      | `String "timed_out",`Null -> "failed",124,`Null
      | `String "cancelled",`Int signal -> "interrupted",128+signal,`Int signal
      | `String "signaled",`Int signal -> "failed",128+signal,`Null
      | `String "exited",`Int n when n>0 -> "failed",n,`Null
      | `String "exited",`Int 0 | `String "failed",`Null -> "failed",2,`Null
      | _ -> invalid_arg "invalid named failure transport" in
    let failure=get a "failure" in
    require (get failure "kind"=`String kind && get failure "exit_code"=`Int code && get failure "signal"=signal)
      "named primary failure contradicts analysis transport outcome/code/signal";
    (match get result "cleanup_error" with `Null -> () | `String cleanup ->
      let secondary=String.concat "; " (List.map text (list (get failure "secondary"))) in
      let represented=try ignore (Str.search_forward (Str.regexp_string cleanup) secondary 0);true with Not_found -> false in
      require represented "named transport cleanup error missing from companion secondary causes"
    | _ -> invalid_arg "invalid named transport cleanup error"))

let process_succeeded ~label p =
  (try exact p ["outcome";"code";"error";"pid";"child_status";"elapsed_seconds";"stdout_path";"stderr_path";"cleanup_error"]
   with Invalid_argument _ -> invalid_arg (label^": unexpected process fields"));
  (match get p "outcome",get p "code",get p "error" with
   | `String "exited",`Int n,`Null when n>=0 && n<=255 -> ()
   | `String ("signaled"|"cancelled"),`Int n,`Null when n>0 && n<128 -> ()
   | `String "timed_out",`Null,`Null -> ()
   | `String "failed",`Null,`String error when error<>"" -> ()
   | _ -> invalid_arg (label^": invalid process outcome/code/error"));
  List.iter (fun k -> match get p k with `Null -> () | `String s when s<>"" -> () | _ -> invalid_arg (label^": invalid "^k))
    ["stdout_path";"stderr_path";"cleanup_error"];
  (match get p "pid" with `Null -> () | `Int n when n>0 -> () | _ -> invalid_arg (label^": invalid pid"));
  let duration=match get p "elapsed_seconds" with `Int n -> float_of_int n | `Float f -> f | _ -> nan in
  require (Float.is_finite duration && duration>=0.) (label^": invalid elapsed duration");
  (match get p "child_status" with `Null -> () | child ->
    exact child ["outcome";"code"];
    match get child "outcome",get child "code" with
    | `String "exited",`Int n when n>=0 && n<=255 -> ()
    | `String ("signaled"|"stopped"),`Int n when n>0 && n<128 -> ()
    | _ -> invalid_arg (label^": invalid child status"));
  (match get p "outcome" with
   | `String ("exited"|"signaled") ->
     let child=get p "child_status" in
     require (get child "outcome"=get p "outcome" && get child "code"=get p "code" && get p "pid"<>`Null)
       (label^": process/child status differs")
   | _ -> ());
  get p "outcome"=`String "exited" && get p "code"=`Int 0 && get p "cleanup_error"=`Null
let execute_cleanup terminal =
  require (process_succeeded ~label:"named execute process" (get terminal "process") && get terminal "transport_succeeded"=`Bool true)
    "named execute process did not succeed";
  let cleanup=get terminal "cleanup" in
  (try exact cleanup ["error";"attempts"] with Invalid_argument _ -> invalid_arg "named execute requires owned cleanup evidence");
  require (get cleanup "error"=`Null) "named execute container cleanup failed";
  let attempts=list (get cleanup "attempts") in
  require (attempts<>[] && List.length attempts<=256) "named execute cleanup attempts missing/excessive";
  let supported=List.map (fun attempt ->
    exact attempt ["process";"diagnostic"];
    let p=get attempt "process" in
    let succeeded=process_succeeded ~label:"named cleanup process" p in
    let diagnostic=match get attempt "diagnostic" with `String s when String.length s<=8192 -> s | _ -> invalid_arg "invalid named cleanup diagnostic" in
    let contains fragment=try ignore (Str.search_forward (Str.regexp_string fragment) diagnostic 0);true with Not_found -> false in
    let absent=match get p "outcome",get p "code" with
      | `String "exited",`Int n when n<>0 -> contains "No such container" || contains "no container"
      | _ -> false in
    succeeded || absent) attempts in
  require (List.hd (List.rev supported)) "named execute cleanup attempts contradict successful removal/absence"

let early_snapshot ~sources ~expectation publication =
  match publication with
  | `Assoc fields when List.mem_assoc "timing_intent_snapshot" fields ->
    let reference=get publication "timing_intent_snapshot" in
    let path=verify_ref reference in
    require (List.exists (equal reference) sources) "early timing expectation snapshot outside publication sources";
    require (equal (require_source sources path) expectation) "early timing expectation snapshot/final expectation differs"
  | _ -> ()

let aliases_of_publication publication = match publication with
  | `Assoc fields when List.mem_assoc "external_aliases" fields -> Inventory.aliases_of_json (get publication "external_aliases")
  | _ -> []
let collateral_roots (checkpoint:Checkpoint.t) =
  let compatibility=wire checkpoint.compatibility in
  [text (get compatibility "pdk_root");text (get compatibility "project")^"/tt"]
let checkpoint_for record checkpoints =
  let references=List.filter (fun r -> get (wire r) "boundary"=`String "synthesis") record.Stage_execution_record.references in
  match references with
  | [reference] -> (match List.assoc_opt (text (get (wire reference) "path")) checkpoints with
    | Some checkpoint -> checkpoint | None -> invalid_arg "named checkpoint outside captured snapshot")
  | _ -> invalid_arg "missing/ambiguous synthesis publication"

let association ~aliases ~analysis_sources ~root ~record ~checkpoints ~expectation ~directory m =
  let publication_path=directory^"/publication.json" in
  let publication=read publication_path in
  let optional=match publication with `Assoc fields -> List.filter (fun key -> List.mem_assoc key fields) ["timing_intent_snapshot";"external_aliases"] | _ -> [] in
  exact publication (["schema_version";"kind";"expectation";"methodology";"plan";"occurrence";"checkpoint";"request";"reply";"segment";"sources"]@optional);
  require (get publication "schema_version"=`Int 1 && get publication "kind"=`String "hardcaml-asic.named-timing-publication") "unsupported named publication";
  let raw=wire record.Stage_execution_record.raw in
  List.iter (fun k -> require (equal (get publication k) (get raw k)) ("publication/final execution mismatch: "^k)) ["methodology";"plan"];
  require (equal (get publication "expectation") expectation) "publication/expectation mismatch";
  let occurrence=match List.filter (fun o -> get (wire o) "action_key"=`String "implementation.synthesis") record.occurrences with
    | [o] -> wire o | _ -> invalid_arg "missing/ambiguous named synthesis occurrence" in
  let published=get publication "occurrence" in
  exact published ["occurrence_id";"action_key";"status";"exit_code";"duration_seconds";"best_effort";"error";"verdict"];
  require (get published "status"=`String "running" && get published "exit_code"=`Null &&
    (get published "duration_seconds"=`Int 0 || get published "duration_seconds"=`Float 0.) && get published "error"=`Null) "publication must bind Running occurrence";
  List.iter (fun k -> require (get published k=get occurrence k) ("publication occurrence mismatch: "^k)) ["occurrence_id";"action_key";"best_effort";"verdict"];
  require (List.mem (get occurrence "status") [`String "completed";`String "failed";`String "interrupted"]) "publication requires finalized reached synthesis";
  let reference=match List.filter (fun r -> get (wire r) "boundary"=`String "synthesis") record.references with
    | [r] -> wire r | _ -> invalid_arg "missing/ambiguous synthesis publication" in
  require (equal reference (get publication "checkpoint")) "publication/final checkpoint mismatch";
  let checkpoint=text (get reference "path") in
  let cm=match List.assoc_opt checkpoint checkpoints with Some m -> m | None -> invalid_arg "publication checkpoint outside captured snapshot" in
  require (aliases=aliases_of_publication publication) "publication alias association changed during inspection";
  Inventory.validate_aliases ~roots:(collateral_roots cm) ~external_files:cm.external_files aliases;
  let publication_sources=list (get publication "sources") in
  ignore (verify_sources ~aliases publication_sources);
  early_snapshot ~sources:publication_sources ~expectation publication;
  List.iter (fun r -> require (List.exists (equal r) analysis_sources) "publication source outside named companion") publication_sources;
  let sources=analysis_sources in
  let retained p=require_source sources p in
  List.iter (fun (p,expected) -> let path=checkpoint^"/"^p in
    bound_source sources path;require (hash path=expected.Checkpoint.sha256) "checkpoint source changed from captured snapshot") cm.Checkpoint.files;
  List.iter (fun (p,expected) -> if not (String.starts_with ~prefix:"/nix/store/" p) then (
    bound_source ~aliases sources p;require (Inventory.hash ~aliases p=expected.Checkpoint.sha256) "checkpoint external source changed from captured snapshot")) cm.external_files;
  require (equal (retained (checkpoint^"/manifest.json")) (wire cm.raw)) "checkpoint manifest changed from captured snapshot";
  verify_bundle ~aliases ~root ~sources ~checkpoint:cm m;
  let segment=retained (checkpoint^"/segment.json") in
  require (equal segment (get publication "segment")) "publication/ checkpoint segment differs";
  let request=get publication "request" in
  let req=checked (Backend_protocol.request_of_json (identity request)) in
  require (req.operation=Backend_protocol.Execute_segment && req.boundary=Execution_plan.Stage.Synthesis && req.source_boundary=None && req.checkpoint=None)
    "named publication must originate from fresh execute_segment, not validation";
  require (req.project=root^"/project") "named execute project differs";
  require (get (wire cm.compatibility) "project"=`String req.project && get (wire cm.compatibility) "pdk_root"=`String req.pdk_root)
    "named execute/checkpoint collateral roots differ";
  let request_path=req.project^"/"^req.tag^"-request.json" in
  require (equal (retained request_path) request) "publication/original execute request differs";
  let reply=retained req.reply_path in
  require (equal reply (get publication "reply")) "publication/original execute reply differs";
  let decoded=checked (Backend_protocol.reply_of_json ~request:req (identity reply)) in
  (match decoded.outcome with Backend_protocol.Completed -> () | _ -> invalid_arg "execute reply did not complete");
  List.iter (fun (_,artifact) ->
    ignore (retained artifact.Backend_protocol.path);
    let actual=checked (Checkpoint.file_record artifact.path) in
    require (actual.sha256=artifact.sha256 && actual.bytes=artifact.bytes) "execute reply artifact bytes differ") decoded.artifacts;
  ignore (checked (Segment_report.of_json ~request:req (identity segment)));
  let launch_path=root^"/"^req.tag^"-transport.json" and terminal_path=root^"/"^req.tag^"-transport-result.json" in
  let launch=retained launch_path and terminal=retained terminal_path in
  let request_hash=Backend_protocol.request_identity req in
  List.iter (fun j -> require (get j "request_sha256"=`String request_hash && get j "request_id"=`String req.request_id && get j "request_path"=`String request_path)
    "named execute transport/request correlation differs") [launch;terminal];
  require (get launch "kind"=`String "backend_transport_launch" && get terminal "kind"=`String "backend_transport_result") "wrong named transport kind";
  require (get launch "cwd"=`String req.project) "named execute cwd differs";
  List.iter (fun k -> require (get (get launch "resources") k=`Int 6) ("named execute resource policy differs: "^k))
    ["cpus";"openlane_max_cores";"openroad_threads";"omp_num_threads"];
  execute_cleanup terminal;
  let binding=get launch "binding" in
  require (equal binding (wire cm.compatibility |> fun c -> get c "binding")) "execute/checkpoint binding differs";
  let d=match checked (Execution_transport.of_json (identity binding)) with Execution_transport.Docker d -> d | _ -> invalid_arg "named Docker binding required" in
  require (d.image_id=Hardcaml_asic_flow_domain.Backends.Librelane.Mapping.tested_image_id) "unsupported named image";
  let argv=List.map text (list (get launch "argv")) in
  let name=match argv with _::"run"::"--rm"::"--pull=never"::"--name"::name::_ -> name | _ -> invalid_arg "unexpected named Docker argv" in
  let prefix=Execution_transport.docker_command d ~project:root ~pdk_root:req.pdk_root ~name ~workdir:req.project
    ~pdk:(text (get (get m "target") "technology")) ~workers:6 ~uid:(L.nonnegative (get launch "host_uid")) ~gid:(L.nonnegative (get launch "host_gid")) () in
  let flags=match d.flags with Execution_transport.Isolated -> ["-I";"-B"] | Bytecode_disabled -> ["-B"] in
  require (argv=prefix@flags@[req.project^"/bridge/librelane_bridge.py";request_path]) "named execute transport argv/resources differ";
  let run_dir=req.project^"/src/runs/"^req.tag in
  require (get launch "fresh_run_dir"=`String run_dir && get segment "run_dir"=`String run_dir) "named synthesis run association differs";
  let returned=List.map text (list (get segment "returned_steps")) in
  require (List.length returned<=256 && List.length returned=List.length (List.sort_uniq String.compare returned)) "duplicate/too many named producer occurrences";
  let positions=List.mapi (fun i id -> i+1,id) returned |> List.filter (fun (_,id) ->
    id="Yosys.Synthesis" || String.starts_with ~prefix:"Yosys.Synthesis-" id) in
  let ordinal,step=match positions with [x] -> x | _ -> invalid_arg "missing/ambiguous exact named synthesis producer" in
  let dirs=names run_dir |> List.filter (fun name ->
    match String.index_opt name '-' with Some k -> int_of_string_opt (String.sub name 0 k)=Some ordinal | None -> false) in
  let producer_dir=match dirs with [name] -> run_dir^"/"^name | _ -> invalid_arg "missing/ambiguous named producer position" in
  let config=retained (producer_dir^"/config.json") in
  let meta=get config "meta" in
  let actual=match get meta "step" with `Null -> get meta "id" | x -> x in
  require (actual=`String step || actual=`String "Yosys.Synthesis") "named producer metadata/position mismatch";
  let native_state=retained (producer_dir^"/state_out.json") in
  let state=retained (checkpoint^"/state.json") in
  let candidate_state=retained (req.candidate^"/state.json") in
  require (equal native_state candidate_state) "candidate/native synthesis State differs";
  require (equal (retained (req.candidate^"/resolved.json")) (retained (checkpoint^"/resolved.json")) &&
    equal (retained (req.candidate^"/closure.json")) (retained (checkpoint^"/closure.json")) &&
    equal (retained (req.candidate^"/segment.json")) segment) "candidate/publication config/closure/segment differs";
  let nl=text (get state "nl") in
  let native_nl=text (get native_state "nl") in
  bound_source sources nl;bound_source sources native_nl;
  require (hash nl=hash native_nl) "published/native netlist differs";
  let synref p = let r=ref_ p in `Assoc ["path",`String (relative root p);"sha256",get r "sha256"] in
  let synthesis=`Assoc ["config",synref (producer_dir^"/config.json");"state",synref (checkpoint^"/state.json");
    "netlist",synref nl;"resolved",synref (checkpoint^"/resolved.json");"state_netlist",get state "nl";
    "native_state",synref (producer_dir^"/state_out.json");"candidate_state",synref (req.candidate^"/state.json")] in
  occurrence,publication_sources,binding,synthesis,ref_ publication_path

let inspect_snapshot ~execution ~execution_sha256 ~raw ~record ~checkpoints () = L.protect (fun () ->
  require (J.canonical raw=J.canonical record.Stage_execution_record.raw) "captured execution/decoded record mismatch";
  ignore (L.historical_path (`String execution));
  let root=Filename.dirname execution in
  let m=manifest record in
  let expectation=get (wire raw) "timing_intent" in
  let staged_path=root^"/project/manifest.json" in
  let advertised=L.expected m || (not (absent staged_path) && L.expected (read staged_path)) in
  let attempt=text (get (wire raw) "attempt_id") in
  let directory=root^"/timing-intent/"^attempt in
  let present=not (absent (directory^"/analysis.json")) || not (absent (directory^"/publication.json")) in
  if expectation=`Null && not advertised && not present then None else (
    require (Stage_execution_record.path ~workspace:root ~attempt_id:attempt=execution) "exact execution JSON path required";
    require (expectation<>`Null) "advertised/present named timing evidence missing persisted expectation";
    require advertised "named timing expectation's advertised producer is missing";
    require (get expectation "directory"=`String directory) "named timing directory outside exact execution workspace";
    let occurrence=match record.occurrences with [o] -> wire o | _ -> invalid_arg "named timing supports synthesis-only occurrence" in
    if absent (directory^"/publication.json") then (
      require (record.references=[] && List.mem (get occurrence "status") [`String "unreached";`String "failed";`String "interrupted"] && not present)
        "required named timing publication/companion missing";
      require (hash execution=execution_sha256) "named execution changed from captured snapshot";
      let methodology=wire (Methodology_execution_record.to_json (Option.get record.methodology)) in
      let snapshot=text (get methodology "snapshot_path") in
      require (get methodology "snapshot_sha256"=`String (hash snapshot)) "methodology snapshot changed from captured reference";
      let sources=[`Assoc ["path",`String execution;"sha256",`String execution_sha256];ref_ snapshot] in
      ignore (verify_sources sources);
      Some (`Assoc ["status",`String "not_produced";"reason",`String "synthesis did not publish; no native coverage asserted";
        "occurrence",occurrence;"expectation",expectation;"verdict",`String "unavailable";"sources",`List sources]))
    else (
      let a=read (directory^"/analysis.json") in
      exact a ["schema_version";"kind";"expectation";"publication";"request";"status";"failure";"sources"];
      require (get a "schema_version"=`Int 1 && get a "kind"=`String "hardcaml-asic.named-timing-analysis") "unsupported named companion";
      let alias_publication=read (directory^"/publication.json") in
      let aliases=aliases_of_publication alias_publication in
      let cm=checkpoint_for record checkpoints in
      Inventory.validate_aliases ~roots:(collateral_roots cm) ~external_files:cm.external_files aliases;
      let sources=list (get a "sources") in ignore (verify_sources ~aliases sources);
      let occurrence,publication_sources,binding,synthesis,publication=association ~aliases ~analysis_sources:sources ~root ~record ~checkpoints ~expectation ~directory m in
      require (equal (get a "expectation") expectation && equal (get a "publication") publication) "named companion/publication/expectation mismatch";
      List.iter (fun r -> require (List.exists (equal r) sources) "publication source outside named companion") publication_sources;
      ignore (require_source sources (text (get publication "path")));
      let request_path=verify_ref (get a "request") in
      require (request_path=directory^"/request.json") "named companion request path differs";
      let request=require_source sources request_path in
      let pub=read (directory^"/publication.json") in
      let backend=get pub "request" in
      let execute_launch=require_source sources (root^"/"^text (get backend "tag")^"-transport.json") in
      let methodology=wire (Methodology_execution_record.to_json (Option.get record.methodology)) in
      let snapshot_path=text (get methodology "snapshot_path") in
      ignore (require_source sources snapshot_path);
      require (get methodology "snapshot_sha256"=`String (hash snapshot_path)) "methodology snapshot changed from captured reference";
      require (get request "kind"=`String "hardcaml-asic.named-timing-request" && get request "schema"=`Int 1) "unsupported named runtime request";
      exact request ["schema";"kind";"expectation";"publication";"execution_root";"project";"analysis_directory";
        "host_uid";"host_gid";"binding";"pdk_root";"helper_sha256";"producer_sha256";"manifest_sha256";
        "build_identity";"analysis_id";"attempt_id";"occurrence_id";"checkpoint";"synthesis_run_dir";"state_path";"resolved_path"];
      require (equal (get request "expectation") expectation && equal (get request "publication") publication) "named request expectation/publication mismatch";
      List.iter (fun (k,v) -> require (get request k=v) ("named request association differs: "^k))
        ["execution_root",`String root;"project",`String (root^"/project");"analysis_directory",`String directory;
         "attempt_id",`String attempt;"occurrence_id",get occurrence "occurrence_id";"checkpoint",get (read (directory^"/publication.json")) "checkpoint";
         "analysis_id",`String (attempt^"/pre-pnr-sta");"state_path",`String (root^"/"^text (get (get synthesis "state") "path"));
         "resolved_path",`String (root^"/"^text (get (get synthesis "resolved") "path"));
         "synthesis_run_dir",get (get pub "segment") "run_dir";"pdk_root",get backend "pdk_root";
         "host_uid",get execute_launch "host_uid";"host_gid",get execute_launch "host_gid"];
      require (get request "build_identity"=get m "identity" && get request "manifest_sha256"=`String (hash (root^"/project/manifest.json"))) "named request/frozen bundle differs";
      require (equal (read (root^"/project/manifest.json")) m) "named staged/frozen manifest differs";
      failure_check a occurrence;
      let linked_sources=List.filter_map (fun r -> let p=text (get r "path") in
        if String.starts_with ~prefix:(root^"/") p && not (List.exists (fun (a:Inventory.alias)->a.path=p) aliases)
        then Some (`Assoc ["path",`String (relative root p);"sha256",get r "sha256"]) else None) sources in
      let companion=`Assoc ["schema",`Int 1;"kind",`String "hardcaml-asic.timing-intent-execution";
        "build_identity",get request "build_identity";"manifest_sha256",get request "manifest_sha256";
        "publication",publication;"stage",`String "synthesized_netlist";"status",get a "status";"sources",`List linked_sources] in
      let named:L.named={directory=relative root directory;publication;synthesis;binding;companion} in
      let view=L.inspect_impl ~named ~run_dir:root ~context:request () in
      failure_transport a (require_source sources (directory^"/transport-result.json"));
      List.iter (fun r -> ignore (verify_ref ~aliases r)) sources;
      Inventory.validate_aliases ~roots:(collateral_roots cm) ~external_files:cm.external_files aliases;
      require (hash execution=execution_sha256) "named execution changed from captured snapshot";
      let all=`Assoc ["path",`String execution;"sha256",`String execution_sha256]::ref_ (directory^"/analysis.json")::sources in
      ignore (verify_sources ~aliases all);
      let source_digest=J.identity (identity (`Assoc ["expectation",expectation;"sources",`List all])) in
      Some (`Assoc (["association",read (directory^"/publication.json");"provenance",a;"sources",`List all;
        "source_digest",`String source_digest;
        "path_binding",`String "original_absolute_paths_required_named_relocation_unsupported"] @
        (match view with `Assoc fields -> List.filter (fun (k,_) -> not (List.mem k ["provenance";"sources";"source_digest"])) fields | _ -> assert false))))))

let inspect ~execution () = L.protect (fun () ->
  regular execution;let before=hash execution in
  let raw=identity (read execution) in
  let record,checkpoints=checked (Stage_execution_record.validate_snapshot raw) in
  let view=checked (inspect_snapshot ~execution ~execution_sha256:before ~raw ~record ~checkpoints ()) in
  require (hash execution=before) "named execution changed while inspecting";
  Option.value view ~default:(unavailable "historical execution has no native timing producer"))
let source_files ~execution () = match inspect ~execution () with Error e -> Error e | Ok j -> Ok (list (get j "sources"))
let precheck_sources ?(external_roots=[]) ~paths () = L.protect (fun () ->
  let paths=List.sort_uniq String.compare paths in
  require (List.length paths<=Inventory.max_sources) "source count exceeds 4096";
  let before=List.map (fun path -> path,Unix.realpath path,Unix.stat path) paths in
  let usage=Inventory.admit_paths ~external_roots paths in
  let resolutions=List.filter_map (fun (path,target,stat) ->
    if target=path then None else
    let root=match List.filter (fun root -> String.starts_with ~prefix:(root^"/") path) external_roots with
      | [root] -> root | _ -> invalid_arg "ambiguous/unregistered precheck alias root" in
    Some (`Assoc ["path",`String path;"target",`String target;"root",`String root;"bytes",`Int stat.Unix.st_size])) before in
  ignore (Inventory.admit_paths ~external_roots paths);
  List.iter (fun (path,target,stat) ->
    let after=Unix.stat path in
    require (Unix.realpath path=target && after.Unix.st_dev=stat.Unix.st_dev && after.st_ino=stat.st_ino &&
      after.st_size=stat.st_size && after.st_mtime=stat.st_mtime && after.st_ctime=stat.st_ctime)
      "precheck declared resolution/source changed during admission") before;
  `Assoc ["source_count",`Int usage.source_count;"total_bytes",`Int usage.total_bytes;"largest_bytes",`Int usage.largest_bytes;
    "declared_alias_count",`Int (List.length resolutions);"external_resolutions",`List resolutions;
    "limits",`Assoc ["sources",`Int Inventory.max_sources;"source_bytes",`Int Inventory.max_source_bytes;"total_bytes",`Int Inventory.max_total_bytes];
    "scope",`String "named_outer_full_required_paths_metadata_overhead_must_be_included";
    "hashes_verified",`Bool false])

let publish ~directory ~succeeded ~failure () =
  let publication_path=directory^"/publication.json" and request_path=directory^"/request.json" in
  let publication=read publication_path and request=read request_path in
  let checkpoint=text (get (get publication "checkpoint") "path") in
  let cm=checked (Checkpoint.read checkpoint) in
  let aliases=aliases_of_publication publication in
  require (get (wire cm.compatibility) "pdk_root"=get request "pdk_root" &&
    get (wire cm.compatibility) "project"=get request "project") "publisher/checkpoint collateral roots differ";
  Inventory.validate_aliases ~roots:(collateral_roots cm) ~external_files:cm.external_files aliases;
  ignore (verify_sources ~aliases (list (get publication "sources")));
  early_snapshot ~sources:(list (get publication "sources")) ~expectation:(get publication "expectation") publication;
  let root=text (get request "execution_root") in
  let visited=ref 0 in
  let walked_files=ref 0 and walked_bytes=ref 0 in
  let rec walk dir =
    incr visited;require (!visited<=Inventory.max_sources) "named inventory directory bound exceeded";
    require (Unix.realpath dir=dir && (Unix.lstat dir).Unix.st_kind=Unix.S_DIR) "linked named directory";
    names dir |> List.concat_map (fun name ->
      let p=dir^"/"^name in
      if p=directory^"/analysis.json" || p=directory^"/toolbox" then [] else
      if (Unix.lstat p).Unix.st_kind=Unix.S_DIR then walk p else (
        incr walked_files;require (!walked_files<=Inventory.max_sources) "named inventory file count exceeds 4096";
        let stat=Inventory.regular p in
        require (!walked_bytes<=Inventory.max_total_bytes-stat.st_size) "named inventory bytes exceed 512MiB";
        walked_bytes:= !walked_bytes+stat.st_size;[p])) in
  let methodology=checked (Methodology_execution_record.of_reference_json
    ~attempt_id:(text (get (get request "expectation") "attempt_id")) (identity (get publication "methodology"))) in
  let m=methodology_manifest methodology in
  require (get request "build_identity"=get m "identity") "publisher request/frozen bundle identity differs";
  let extras=(root^"/project/manifest.json")::bundle_paths ~root m in
  let extras=text (get (get publication "methodology") "snapshot_path")::extras in
  let extras=List.filter_map (fun (p,_) -> if String.starts_with ~prefix:"/nix/store/" p then None else Some p) cm.external_files @ extras in
  let segment=get publication "segment" in
  let run_dir=text (get segment "run_dir") in
  let returned=List.map text (list (get segment "returned_steps")) in
  let extras=List.mapi (fun i id -> i+1,id) returned |> List.fold_left (fun extras (ordinal,id) ->
    if id<>"Yosys.Synthesis" && not (String.starts_with ~prefix:"Yosys.Synthesis-" id) then extras else
    let names=names run_dir |> List.filter (fun name -> match String.index_opt name '-' with
      Some k -> int_of_string_opt (String.sub name 0 k)=Some ordinal | None -> false) in
    match names with [name] ->
      let dir=run_dir^"/"^name in
      let state=read (dir^"/state_out.json") in
      [dir^"/config.json";dir^"/state_out.json";text (get state "nl")] @ extras
    | _ -> invalid_arg "missing/ambiguous publication synthesis producer") extras in
  let extras=if absent (directory^"/runtime-result.json") then extras else
    let synth=get (read (directory^"/runtime-result.json")) "synthesis" in
    extras @ List.map (fun k -> let r=get synth k in L.member root (text (get r "path")))
      ["config";"state";"netlist";"resolved";"native_state";"candidate_state"] in
  let paths=walk directory @ List.map (fun r -> text (get r "path")) (list (get publication "sources")) @ extras
    |> List.sort_uniq String.compare in
  ignore (Inventory.admit_paths ~aliases paths);
  let sources=List.map (ref_ ~aliases) paths in
  ignore (verify_sources ~aliases sources);
  List.iter (fun r -> require (List.exists (equal r) sources) "publication source changed before companion publication") (list (get publication "sources"));
  verify_bundle ~aliases ~root ~sources ~checkpoint:cm m;
  let a=`Assoc ["schema_version",`Int 1;"kind",`String "hardcaml-asic.named-timing-analysis";
    "expectation",get publication "expectation";"publication",ref_ publication_path;"request",ref_ request_path;
    "status",`String (if succeeded then "completed" else "failed");"failure",wire failure;"sources",`List sources] in
  let bytes=Evidence_json.record_bytes a in
  let usage=Inventory.admit_paths ~aliases paths in
  Inventory.validate_aliases ~roots:(collateral_roots cm) ~external_files:cm.external_files aliases;
  let execution=root^"/execution-"^text (get (get request "expectation") "attempt_id")^".json" in
  let execution_bytes=if absent execution then 0 else (Inventory.regular execution).Unix.st_size in
  require (usage.source_count+2<=Inventory.max_sources) "named companion closure exceeds 4096 sources including execution/companion";
  require (String.length bytes<=8*1024*1024) "named companion metadata exceeds 8MiB";
  require (usage.total_bytes<=Inventory.max_total_bytes-String.length bytes-execution_bytes)
    "named companion closure exceeds 512MiB including execution/companion";
  let path=directory^"/analysis.json" in
  let temporary=Filename.temp_file ~temp_dir:directory ".named-analysis-" ".pending" in
  Fun.protect ~finally:(fun () -> Unix.unlink temporary) (fun () ->
    let oc=open_out_bin temporary in
    Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () -> output_string oc bytes);
    Unix.chmod temporary 0o400;Unix.link temporary path)
