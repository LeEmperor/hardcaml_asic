(* Versioned coarse-only adapter. Historical coarse/named synthesis continues to
   use Timing_intent_linked unchanged. All pointers replay retained sources. *)
module L = Timing_intent_linked
module E = Evidence_json
let get=L.get and text=L.text and list=L.list and require=L.require and exact=L.exact
let s x = `String x
let obj xs = `Assoc xs
let filter_driver = "import sys\nsys.dont_write_bytecode = True\nimport runpy\nfrom pathlib import Path\nsource = Path(__file__).resolve().parents[2] / \"native-sources\" / \"odbpy\" / \"filter_unannotated.py\"\nsys.path.insert(0, str(source.parent))\nrunpy.run_path(str(source), run_name=\"__main__\")\n"
let ordinal directory =
  let token=List.hd (String.split_on_char '-' (Filename.basename directory)) in
  match int_of_string_opt token with Some n when n>0 && String.for_all (function '0'..'9' -> true | _ -> false) token -> n
  | _ -> invalid_arg "invalid native producer ordinal"
let enabled manifest = get manifest "timing_physical_qualification"<>`Null
let prefix = "timing-intent/"
let rel p = prefix^p
let validate_marker manifest =
  Timing_intent_evidence.validate_qualification manifest
let stage context = if get context "requested_stage"=s "full" then "post_pnr" else "synthesized_netlist"
let fresh path value =
  let fd=Unix.openfile path [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL] 0o600 in
  let oc=Unix.out_channel_of_descr fd in
  Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () -> output_string oc (E.record_bytes value))
let read_raw p =
  let st=Unix.stat p in require (st.st_size<=64*1024*1024) "physical source read bound";
  let ic=open_in_bin p in
  Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () -> really_input_string ic st.st_size)
let selected mapping corner =
  let matches pattern =
    require (String.length pattern<=4096 && not (String.contains pattern '[')) "unsupported corner selector grammar";
    let re=String.to_seq pattern |> List.of_seq |> List.map (function
      | '*' -> ".*" | '?' -> "." | c -> Str.quote (String.make 1 c)) |> String.concat "" in
    Str.string_match (Str.regexp ("^"^re^"$")) corner 0 in
  match mapping with
  | `Null -> []
  | `Assoc rows -> List.concat_map (fun (pattern,value) -> if matches pattern then
      match value with `String _ -> [text value] | `List xs -> List.map text xs | _ -> invalid_arg "invalid selected corner views"
      else []) rows
  | _ -> invalid_arg "corner mapping required"

let publish ~run_dir ~context ~succeeded () =
  let root=Unix.realpath run_dir in
  let manifest=L.manifest ~root context in validate_marker manifest;
  require (enabled manifest) "physical timing marker missing at publication";
  let extra=ref ["project/manifest.json";"project/constraints/top.sdc";"project/"^L.producer;
    "project/timing_physical_runtime.py";"project/timing_intent_runtime.py"] in
  let add path = ignore (L.member root path);extra:=path::!extra in
  let reference r = add (L.check_ref root r) in
  let result=root^"/"^rel "input-selection.json" in
  if Sys.file_exists result then (
    let h=L.read result in
    let impl=get h "implementation" in
    List.iter reference (list (get h "retained_producer_files"));
    let synth=get h "originating_synthesis" in
    List.iter (fun k -> reference (get synth k)) ["config";"state";"netlist";"resolved"];
    List.iter (fun k -> reference (get impl k)) ["config";"state";"netlist";"resolved"];
    if stage context="post_pnr" then (
      List.iter (fun k -> reference (get impl k)) ["output_state";"runtime"];
      List.iter (fun row -> List.iter (fun k -> reference (get row k)) ["config";"input_state";"output_state";"runtime"]) (list (get h "physical_chain"));
      let state=L.read (L.member root (text (get (get impl "state") "path"))) in
      let historical=text (get (L.read (root^"/"^rel "request.json")) "execution_root") in
      let local p = let p=text p in let pre=historical^"/" in
        require (String.starts_with ~prefix:pre p) "physical State input outside recorded run";
        String.sub p (String.length pre) (String.length p-String.length pre) in
      List.iter (fun k -> if get state k<>`Null then add (local (get state k))) ["nl";"odb"];
      (match get state "spef" with `Assoc xs -> List.iter (fun (_,p) -> add (local p)) xs | _ -> invalid_arg "missing physical SPEF map")));
  let sources=L.inventory root @ List.map (L.ref_ root) !extra in
  let sources=List.sort_uniq (fun a b -> compare (get a "path") (get b "path")) sources in
  require (List.length sources<=512) "physical source count exceeds 512";
  fresh (root^"/"^rel "analysis.json") (obj ["schema",`Int 2;"kind",s "hardcaml-asic.timing-intent-flow";
    "run_id",get context "run_id";"build_identity",get context "build_identity";
    "manifest_sha256",get context "manifest_sha256";"stage",s (stage context);
    "status",s (if succeeded then "completed" else "failed");
    "request",L.ref_ root (rel "request.json");"sources",`List sources])

let inspect_impl ~run_dir ~context () =
  let context=L.normalize context in
  let root=Unix.realpath run_dir in
  let manifest=L.manifest ~root context in validate_marker manifest;
  require (enabled manifest) "physical timing marker missing";
  require (get (get manifest "target") "technology"=s "ihp-sg13cmos5l") "physical timing requires CMOS5L";
  (match Hardcaml_asic.Elaboration.Bundle.verify_manifest_identity manifest with Ok () -> () | Error _ -> invalid_arg "invalid physical bundle identity");
  let a_path=rel "analysis.json" in
  let a=L.read (L.member root a_path) in
  exact a ["schema";"kind";"run_id";"build_identity";"manifest_sha256";"stage";"status";"request";"sources"];
  require (get a "schema"=`Int 2 && get a "kind"=s "hardcaml-asic.timing-intent-flow") "unsupported physical companion";
  List.iter (fun k -> require (get a k=get context k) ("physical companion/context mismatch: "^k)) ["run_id";"build_identity";"manifest_sha256"];
  let physical=stage context="post_pnr" in
  require (not physical || get manifest "operation"=s "Hardening") "physical timing full requires Hardening operation";
  require (get a "stage"=s (stage context)) "physical companion stage mismatch";
  let sources=list (get a "sources") in
  require (List.length sources<=512) "physical source count bound";
  let total=ref 0 in
  let paths=List.map (fun r ->
    exact r ["path";"sha256"];
    let p=L.member root (text (get r "path")) in let bytes=(Unix.stat p).st_size in
    require (bytes<=64*1024*1024) "physical source byte bound";
    total:= !total+bytes;require (!total<=512*1024*1024) "physical source aggregate bound";
    L.check_ref root r) sources in
  require (List.length paths=List.length (List.sort_uniq String.compare paths)) "duplicate physical source";
  let bound r = let p=L.check_ref root r in require (List.mem r sources) ("unbound physical source: "^p);p in
  let file p = require (List.mem p paths) ("missing physical source: "^p);L.member root p in
  let read p = L.read (file p) in
  let raw p = read_raw (file p) in
  require (bound (get a "request")=rel "request.json") "physical request association mismatch";
  let request=read (rel "request.json") in
  exact request ["schema";"run_id";"build_identity";"manifest_sha256";"analysis_id";"stage";"implementation_process";
    "execution_root";"host_uid";"host_gid";"binding";"pdk_root";"helper_sha256";"base_helper_sha256";"producer_sha256"];
  require (get request "schema"=`Int 2 && get request "stage"=get a "stage") "physical request schema/stage mismatch";
  List.iter (fun k -> require (L.equal (get request k) (get context k)) ("physical request/context mismatch: "^k)) ["run_id";"build_identity";"manifest_sha256";"implementation_process"];
  require (get request "analysis_id"=s (text (get context "run_id")^"/"^(if physical then "post-pnr-sta" else "pre-pnr-sta"))) "physical analysis ID mismatch";
  let historical=L.historical_path (get request "execution_root") in
  let executed p = historical^"/"^p in
  let local p = let p=L.historical_path (s p) and pre=historical^"/" in
    require (String.starts_with ~prefix:pre p) "consumed input outside historical root";
    String.sub p (String.length pre) (String.length p-String.length pre) in
  let process=get request "implementation_process" in
  exact process ["outcome";"code";"succeeded";"argv"];
  require (get process "outcome"=s "exited" && get process "code"=`Int 0 && get process "succeeded"=`Bool true) "implementation process did not complete";
  require (get context "commands"=`List [get process "argv"]) "implementation command association mismatch";
  let binding=match Identity_json.parse (Yojson.Safe.to_string (get request "binding")) with
    | Error _ -> invalid_arg "invalid physical runtime binding" | Ok j ->
      (match Execution_transport.of_json j with Ok b -> b | Error e -> invalid_arg e) in
  require (L.equal (get request "binding") (get context "execution_binding")) "physical runtime binding mismatch";
  let docker=match binding with Execution_transport.Docker d when d.image_id=Hardcaml_asic_flow_domain.Backends.Librelane.Mapping.tested_image_id -> d
    | _ -> invalid_arg "unsupported physical runtime image" in
  let pdk_root=L.historical_path (get request "pdk_root") in
  let uid=L.nonnegative (get request "host_uid") and gid=L.nonnegative (get request "host_gid") in
  let check_argv analysis argv =
    let args=List.map text (list argv) in
    let name=match args with _::"run"::"--rm"::"--pull=never"::"--name"::name::_ -> name | _ -> invalid_arg "unexpected physical transport argv" in
    let technology=text (get (get manifest "target") "technology") in
    let pre=Execution_transport.docker_command docker ~project:(if analysis then historical else executed "project")
      ~pdk_root ~name ~workdir:(executed "project") ?pdk:(if analysis then None else Some technology) ~workers:6 ~uid ~gid () in
    let flags=match docker.flags with Execution_transport.Isolated -> ["-I";"-B"] | Bytecode_disabled -> ["-B"] in
    let payload=if analysis then [executed (rel "timing_physical_runtime.py");executed (rel "request.json")]
      else [executed "project/timing_physical_runtime.py";"implementation";"--pdk-root";pdk_root;"--pdk";technology;"--manual-pdk";
        "--run-tag";"asic";"--force-run-dir";"runs/asic"] @
        (if physical then [] else ["--to";"Yosys.Synthesis"]) @
        ["--jobs";"6";"-c";"OPENROAD_THREADS=6";"-c";"STA_THREADS=1";"-c";"KLAYOUT_DRC_THREADS=6";"-c";"KLAYOUT_XOR_THREADS=6";"src/config.json"] in
    require (args=pre@flags@payload) "physical transport argv differs from exact bounded invocation" in
  check_argv false (get process "argv");
  List.iter (fun (key,path) -> require (get request key=s (L.hash (file path))) ("physical retained helper changed: "^path))
    ["helper_sha256",rel "timing_physical_runtime.py";"base_helper_sha256",rel "timing_intent_runtime.py";"producer_sha256","project/"^L.producer];
  List.iter (fun name -> require (L.hash (file ("project/"^name))=L.hash (file (rel name))) "implementation/analysis helper differs")
    ["timing_physical_runtime.py";"timing_intent_runtime.py"];
  exact (get context "timing_runtime_helpers") ["timing_physical_runtime.py";"timing_intent_runtime.py"];
  List.iter (fun name -> require (get (get context "timing_runtime_helpers") name=s (L.hash (file ("project/"^name)))) "runtime helper differs from pre-implementation identity")
    ["timing_physical_runtime.py";"timing_intent_runtime.py"];
  let launch=read (rel "transport.json") and terminal=read (rel "transport-result.json") in
  require (get launch "request_sha256"=s (L.hash (file (rel "request.json"))) && get terminal "request_sha256"=get launch "request_sha256") "physical transport/request mismatch";
  require (L.equal (get launch "binding") (get request "binding") && get launch "workers"=`Int 6 && get launch "sta_threads"=`Int 1) "physical transport resources/binding mismatch";
  check_argv true (get launch "argv");
  exact terminal ["request_sha256";"succeeded";"outcome";"code";"cleanup_error"];
  let cleanup=match get terminal "cleanup_error" with `Null -> true | `String e when e<>"" -> false | _ -> invalid_arg "invalid cleanup outcome" in
  let exited=match get terminal "outcome",get terminal "code" with
    | `String "exited",`Int n when n>=0 && n<=255 -> n=0
    | `String "signaled",`Int n when n>0 && n<128 -> false
    | `String "cancelled",`Int (2|15) -> false
    | `String ("failed"|"timed_out"),`Null -> false
    | _ -> invalid_arg "invalid physical terminal outcome/code" in
  require (get terminal "succeeded"=`Bool (exited && cleanup)) "physical terminal success contradiction";
  let progress=if not (List.mem (rel "corner-progress.json") paths) then `Null else (
    let p=read (rel "corner-progress.json") in
    exact p ["schema";"stage";"configured_corners";"requested_corners";"executed_corners";"equivalent_corners";"not_observed_corners";"step_completed";"observations"];
    require (get p "schema"=`Int 2 && get p "stage"=get request "stage") "wrong corner progress stage/schema";
    let requested=list (get p "requested_corners") in
    List.iter (fun c -> let c=text c in require (Filename.basename c=c && c<>"." && c<>"..") "unsafe corner progress name") requested;
    require (`List requested=get p "configured_corners" && requested<>[] && List.length requested<=64 &&
      List.length requested=List.length (List.sort_uniq compare requested)) "invalid corner progress request set";
    require (List.mem (get p "step_completed") [`Bool true;`Bool false]) "invalid Step progress completion Boolean";
    let observations=list (get p "observations") in
    require (List.map (fun row -> get row "corner") observations=requested) "corner progress observation set mismatch";
    let executed_corners=List.filter_map (fun row ->
      exact row ["corner";"process";"exit_code";"audit"];
      let corner=text (get row "corner") in
      if get row "process"=`Null then (require (get row "exit_code"=`Null && get row "audit"=`Null) "unobserved corner cannot claim process/audit";None)
      else (
        let path=bound (get row "process") in
        require (path=rel ("corners/"^corner^"/native-process-0.json")) "corner progress native process source mismatch";
        let process=read path in exact process ["argv";"exit_code"];
        require (get process "argv"=`List (List.map s ["sta";"-threads";"1";"-no_splash";"-exit";executed (rel "driver.tcl")]) &&
          get process "exit_code"=get row "exit_code") "corner progress native command/result mismatch";
        if get row "audit"<>`Null then ignore (bound (get row "audit"));
        match get row "exit_code" with
        | `Null -> None | `Int n when n>= -127 && n<=255 -> Some (s corner)
        | _ -> invalid_arg "invalid native corner exit code")) observations in
    require (get p "executed_corners"=`List executed_corners &&
      get p "not_observed_corners"=`List (List.filter (fun c -> not (List.mem c executed_corners)) requested)) "corner progress execution claim mismatch";
    let selections=if List.mem (rel "corner-selections.json") paths then list (read (rel "corner-selections.json")) else [] in
    List.iter (fun alias ->
      exact alias ["corner";"equivalent_to";"inputs"];
      require (not (List.mem (get alias "corner") executed_corners) && List.mem (get alias "equivalent_to") executed_corners) "equivalent input corner was misreported executed";
      let inputs corner=let row=match List.find_opt (fun row -> get row "corner"=corner) selections with Some row -> row | None -> invalid_arg "missing corner equivalence input proof" in
        match row with `Assoc fields -> obj (List.remove_assoc "corner" fields) | _ -> assert false in
      require (L.equal (get alias "inputs") (inputs (get alias "corner")) &&
        L.equal (get alias "inputs") (inputs (get alias "equivalent_to"))) "incomplete corner equivalence proof") (list (get p "equivalent_corners"));p) in
  let common=["provenance",a;"sources",`List (L.ref_ root a_path::sources);"source_digest",s (L.hash (L.member root a_path));
    "corner_execution",progress;
    "verdict",s "unavailable";"exhaustive_coverage",s "unavailable";
    "source_authentication",s "hash_checked_retained_producer_assertions_not_authenticated_execution"] in
  if get a "status"=s "failed" then obj (["status",s "failed";"reason",s "required linked analysis failed";"all_corner_timing_goal",s "unknown"]@common)
  else (
    require (get a "status"=s "completed" && exited && cleanup) "physical analysis did not complete verified transport";
    let h=read (rel "runtime-result.json") in
    require (get h "schema"=`Int 2 && get h "status"=s "completed") "invalid physical runtime result";
    require (progress<>`Null && get progress "step_completed"=`Bool true &&
      get progress "executed_corners"=get h "executed_corners" && get progress "not_observed_corners"=`List [] &&
      get progress "equivalent_corners"=`List []) "required corner not actually executed (progress/process completion mismatch)";
    List.iter (fun k -> require (get h k=get request k) ("physical helper/request mismatch: "^k)) ["run_id";"build_identity";"analysis_id";"stage"];
    let impl=get h "implementation" in
    let selection=read (rel "input-selection.json") in
    require (get selection "schema"=`Int 2 && get selection "stage"=get a "stage") "wrong physical input selection stage";
    List.iter (fun k -> require (L.equal (get selection k) (get h k)) ("physical selected/runtime association mismatch: "^k))
      ["implementation";"physical_chain";"configured_corners";"originating_synthesis";"retained_producer_files"];
    let producer_files=list (get h "retained_producer_files") in
    require (List.length producer_files<=384) "implementation producer source bound";
    List.iter (fun r -> ignore (bound r)) producer_files;
    let synth=get h "originating_synthesis" in
    let synth_config=bound (get synth "config") and synth_state=bound (get synth "state") in
    let synth_dir=Filename.dirname synth_config in
    require (Filename.dirname synth_dir="project/runs/asic" && synth_state=synth_dir^"/state_out.json" &&
      get (get (read synth_config) "meta") "step"=s "Yosys.Synthesis") "wrong originating synthesis producer";
    require (get (read synth_state) "nl"=get synth "state_netlist" && get synth "state_netlist"=s (executed (bound (get synth "netlist")))) "originating synthesis netlist mismatch";
    let config_path=bound (get impl "config") and state_path=bound (get impl "state") in
    let dir=Filename.dirname config_path in
    require (Filename.dirname dir="project/runs/asic" && state_path=dir^"/"^(if physical then "state_in.json" else "state_out.json")) "wrong implementation input producer";
    let config=read config_path and state=read state_path in
    let check_meta cls config = require (get (get config "meta") "step"=s cls && get (get config "meta") "librelane_version"=s "3.1.0.dev3") "wrong native producer metadata/version" in
    let validate_state ~needs_odb ~linked state =
      require (match get state "nl" with `String _ -> true | _ -> false) "required State netlist locator missing";
      if needs_odb then require (match get state "odb" with `String _ -> true | _ -> false) "required State ODB locator missing";
      let rec visit = function
        | `Null -> ()
        | `Assoc fields -> List.iter (fun (_,value) -> visit value) fields
        | `List values -> List.iter visit values
        | `String path ->
          let relative=local path in
          require (String.starts_with ~prefix:"project/" relative || (linked && String.starts_with ~prefix:(rel "corners/") relative)) "State view outside retained execution";
          ignore (file relative)
        | _ -> invalid_arg "unsupported native State view locator" in
      match state with `Assoc fields -> List.iter (fun (key,value) -> if key<>"metrics" then visit value) fields
      | _ -> invalid_arg "native State object required" in
    if physical then (
      validate_state ~needs_odb:false ~linked:false (read synth_state);
      validate_state ~needs_odb:true ~linked:false state);
    check_meta (if physical then "OpenROAD.STAPostPNR" else "Yosys.Synthesis") config;
    let netlist=bound (get impl "netlist") in
    require (get impl "state_netlist"=get state "nl" && get state "nl"=s (executed netlist)) "implementation State/netlist mismatch";
    require (bound (get impl "resolved")="project/runs/asic/resolved.json") "wrong implementation resolved config";
    let resolved=read "project/runs/asic/resolved.json" in
    let required=list (get resolved "STA_CORNERS") |> List.map text in
    require (required<>[] && List.length required<=64 && List.length required=List.length (List.sort_uniq compare required)) "invalid required corner set";
    List.iter (fun k -> require (get h k=`List (List.map s required)) ("configured/requested corner mismatch: "^k)) ["configured_corners";"requested_corners"];
    let actual=list (get h "executed_corners") |> List.map text in
    require (List.sort compare actual=List.sort compare required && get h "equivalent_corners"=`List []) "required corner not actually executed";
    let effective_path=bound (get h "effective_config") in
    require (effective_path=rel "effective-config.json") "wrong effective config source";
    let effective=read effective_path and delta=read (rel "configuration-delta.json") in
    let delta_keys=["STA_CORNERS";"STA_THREADS";"OPENROAD_THREADS";"STA_EXTRA_CORNER_TCL_FILE"] in
    exact delta delta_keys;
    List.iter (fun k -> require (L.equal (get (get delta k) "requested") (get resolved k) && L.equal (get (get delta k) "effective") (get effective k)) "physical config delta mismatch") delta_keys;
    (match effective with `Assoc fields -> List.iter (fun (k,v) -> if not (List.mem k ("meta"::delta_keys)) then require (L.equal v (get resolved k)) ("unexpected physical config delta: "^k)) fields | _ -> invalid_arg "invalid effective config");
    require (get effective "STA_CORNERS"=get resolved "STA_CORNERS" && get effective "STA_THREADS"=`Int 1 && get effective "OPENROAD_THREADS"=`Int 1 && get effective "STA_EXTRA_CORNER_TCL_FILE"=s (executed (rel "hook.tcl"))) "unbounded physical effective config";
    require (L.equal (read (rel "corners/state_in.json")) state) "linked Step did not consume exact implementation INPUT State";
    let output=read (rel "corners/state_out.json") in
    if physical then (
      validate_state ~needs_odb:true ~linked:true (read (rel "corners/state_in.json"));
      validate_state ~needs_odb:true ~linked:true output;
      List.iter (fun key -> require (L.equal (get output key) (get state key)) ("linked STA changed implementation view: "^key)) ["nl";"odb";"spef"]);
    ignore (Timing_analysis.native_runtime_seconds (raw (rel "corners/runtime.txt")));
    let step_config=read (rel "corners/config.json") in
    require (L.equal step_config effective) "linked Step config differs from effective config";
    let chain=list (get h "physical_chain") in
    if physical then (
      require (bound (get impl "output_state")=dir^"/state_out.json" && bound (get impl "runtime")=dir^"/runtime.txt") "incomplete implementation STA";
      let original_output=read (dir^"/state_out.json") in
      validate_state ~needs_odb:true ~linked:false original_output;
      List.iter (fun key -> require (L.equal (get original_output key) (get state key)) ("original STA changed implementation view: "^key)) ["nl";"odb";"spef"];
      ignore (Timing_analysis.native_runtime_seconds (raw (dir^"/runtime.txt")));
      require (List.map (fun row -> get row "class_id") chain=List.map s ["OpenROAD.GlobalPlacement";"OpenROAD.CTS";"OpenROAD.DetailedRouting";"OpenROAD.RCX"]) "physical stage chain mismatch";
      let previous=ref (ordinal synth_dir) in
      List.iter (fun row ->
        let cp=bound (get row "config") in let d=Filename.dirname cp in
        require (Filename.dirname d="project/runs/asic") "physical chain outside exact run";
        let position=ordinal d in
        require (position> !previous) "noncausal synthesis/physical producer stage order";previous:=position;
        check_meta (text (get row "class_id")) (read cp);
        List.iter (fun (k,name) -> require (bound (get row k)=d^"/"^name) "physical chain State source mismatch";
          validate_state ~needs_odb:true ~linked:false (read (d^"/"^name))) ["input_state","state_in.json";"output_state","state_out.json"];
        require (bound (get row "runtime")=d^"/runtime.txt") "physical chain completion source mismatch";ignore (Timing_analysis.native_runtime_seconds (raw (d^"/runtime.txt")))) chain;
      let rcx=read (text (get (get (List.hd (List.rev chain)) "output_state") "path")) in
      require (ordinal dir> !previous) "noncausal original post-PNR STA producer before RCX";
      require (L.equal (get rcx "spef") (get state "spef") && get rcx "nl"=get state "nl" && get rcx "odb"=get state "odb") "RCX/STA extracted nl/SPEF/ODB input mismatch")
    else require (chain=[]) "synthesis cannot claim physical stage chain";
    let audits=list (get h "audits") in
    require (List.map (fun a -> text (get a "corner")) audits=actual) "native audit/executed corner mismatch";
    let metric_views=ref [] in
    let views=List.map (fun row ->
      let corner=text (get row "corner") and audit_path=bound (get row "audit") in
      require (audit_path=rel ("corners/"^corner^"/audit.json")) "native audit directory/corner mismatch";
      let directory=Filename.dirname audit_path in
      let inner=match Timing_intent_evidence.inspect ~directory:(Filename.dirname (file audit_path)) () with Ok v -> v | Error e -> invalid_arg e in
      let p=get inner "provenance" in
      require (get p "schema"=`Int (if physical then 3 else 2) && get p "stage"=get a "stage" && get p "corner"=s corner && get p "audit_id"=get request "analysis_id" && get p "build_identity"=get request "build_identity" && get p "producer"=obj ["tool",s "OpenSTA";"version",s "2.7.0"]) "native audit stage/corner/producer mismatch";
      let inner_sources=list (get inner "sources") in
      List.iter (fun r -> ignore (bound (obj ["path",s (directory^"/"^text (get r "path"));"sha256",get r "sha256"]))) inner_sources;
      let role name = List.filter (fun r -> get r "role"=s name) inner_sources in
      let singleton name = match role name with [r] -> r | _ -> invalid_arg "missing/ambiguous physical role" in
      let inputs=read (directory^"/native-inputs.json") in
      let env=get inputs "environment" in
      List.iter (fun (k,v) -> require (get env k=s v) ("actual native input differs: "^k))
        ["CURRENT_NL",executed (directory^"/mapped.v");"_SDC_IN",executed (directory^"/top.sdc");
         "_CURRENT_CORNER_NAME",corner;"PT7_AUDIT_DIR",executed directory;"PT7_RECEIPT",executed (directory^"/receipt.json");
          "PT7_CORNER_SCRIPT",executed (directory^"/librelane-corner.tcl");
          "STA_EXTRA_CORNER_TCL_FILE",executed (rel "hook.tcl")];
      if physical || get env "_EXTRA_CORNER_TCL_FILE"<>`Null then
        require (get env "_EXTRA_CORNER_TCL_FILE"=get effective "STA_EXTRA_CORNER_TCL_FILE") "actual native extra-corner hook differs from effective config";
      require (bound (get inputs "corner_script")=directory^"/librelane-corner.tcl") "native corner script mismatch";
      let associations=list (get inputs "associations") in
      let input_roles=["manifest";"sdc";"netlist";"liberty";"driver";"native_producer"]@(if physical then ["spef"] else []) in
      let inner_inputs=List.filter (fun r -> List.mem (text (get r "role")) input_roles) inner_sources in
      require (List.length associations=List.length inner_inputs) "actual native input closure mismatch";
      List.iter2 (fun association source ->
        exact association ["role";"original_path";"actual_path";"retained";"bytes"];
        let retained=directory^"/"^text (get source "path") in
        require (get association "role"=get source "role" && bound (get association "retained")=retained && get (get association "retained") "sha256"=get source "sha256" && get association "actual_path"=s (executed retained) && get association "bytes"=`Int (Unix.stat (file retained)).st_size) "actual consumed bytes/role association mismatch";
        let original=text (get association "original_path") in
        let expected=match text (get source "role") with
          | "netlist" -> Some (executed netlist) | "sdc" -> Some (executed "project/constraints/top.sdc")
          | "manifest" -> Some (executed "project/manifest.json") | "native_producer" -> Some (executed ("project/"^L.producer))
          | "driver" -> Some (executed (rel "driver.tcl")) | _ -> None in
        Option.iter (fun expected -> require (original=expected) "wrong original consumed input";
          require (get source "sha256"=s (L.hash (file (local original)))) "native/original input hash mismatch") expected) associations inner_inputs;
      let libraries=List.filter (fun r -> get r "role"=s "liberty") associations in
      let originals=List.map (fun r -> text (get r "original_path")) libraries in
      require (originals=selected (get effective "CELL_LIBS") corner @ selected (get effective "PAD_LIBS") corner) "wrong corner/ordered native library selection";
      require (L.tcl_paths (text (get env "_CURRENT_CORNER_LIBS"))=List.map (fun r -> text (get r "actual_path")) libraries) "actual native Liberty list mismatch";
      if physical then (
        require (get env "_CURRENT_SPEF_BY_CORNER"=s (executed (directory^"/extracted.spef")) && get env "OPENLANE_SDC_IDEAL_CLOCKS"=s "0") "wrong extracted SPEF/clock mode";
        let spefs=selected (get state "spef") corner in
        require (List.length spefs=1) "missing/ambiguous input SPEF corner selection";
        let association=List.find (fun r -> get r "role"=s "spef") associations in
        require (get association "original_path"=s (List.hd spefs) && get (singleton "spef") "sha256"=s (L.hash (file (local (List.hd spefs))))) "selected SPEF differs from exact INPUT State bytes";
        let clocks=read (directory^"/clock-state.json") in
        exact clocks ["schema";"all_propagated";"clocks"];
        require (get clocks "schema"=`Int 1 && get clocks "all_propagated"=`Int 1 && get clocks "clocks"=`List [s "clk"]) "native clocks not propagated under the qualified primary-clock policy";
        ignore (raw (directory^"/parasitic-annotation.rpt")));
      let process=read (directory^"/process-result.json") in
      require (get process "argv"=`List (List.map s ["sta";"-threads";"1";"-no_splash";"-exit";executed (rel "driver.tcl")])) "unbounded/wrong native argv";
      let native=read (directory^"/native-process-0.json") in
      exact native ["argv";"exit_code"];
      require (get native "argv"=get process "argv" && get native "exit_code"=`Int 0) "actual native STA process did not complete";
      let version=read (directory^"/version-process.json") in
      require (get version "argv"=`List [s "sta";s "-version"] && get version "exit_code"=`Int 0 && get version "stderr"=s "" && get version "stdout_sha256"=s (L.hash (file (directory^"/producer-version.txt")))) "native version process mismatch";
      let libs=List.map (fun r -> raw (directory^"/"^text (get r "path"))) (role "liberty") in
      let metrics=Timing_physical_metrics.interpret ~corner ~log:(raw (directory^"/sta.log")) ~output_state:output ~libraries:libs in
      let metrics=match metrics with `Assoc fields -> obj (("metric_sources",obj [
        "log",L.ref_ root (directory^"/sta.log");"output_state",L.ref_ root (rel "corners/state_out.json");
        "libraries",`List (List.map (fun r -> L.ref_ root (directory^"/"^text (get r "path"))) (role "liberty"))])::fields) | _ -> assert false in
      let metrics=if not physical then metrics else (
        let filter=read (directory^"/native-process-1.json") in
        exact filter ["argv";"exit_code"];
        require (get filter "exit_code"=`Int 0) "annotation filter process did not complete";
        let inputs=read (directory^"/filter-inputs.json") in
        exact inputs ["driver_profile";"script_path";"script";"filter_source";"dependencies";"checks_report";"inputs"];
        let script=bound (get inputs "script") in
        require (get inputs "driver_profile"=s "retained_odbpy_v1" && script=directory^"/filter-driver.py" &&
          get inputs "script_path"=s (executed script) && raw script=filter_driver) "annotation filter executed script authority mismatch";
        let filter_source=bound (get inputs "filter_source") in
        require (filter_source=rel "native-sources/odbpy/filter_unannotated.py") "annotation filter source mismatch";
        let dependencies=List.map bound (list (get inputs "dependencies")) in
        let dependency_root=rel "native-sources/odbpy" in
        let expected_dependencies=List.filter (fun path -> Filename.dirname path=dependency_root && Filename.check_suffix path ".py") paths |> List.sort compare in
        require (List.length dependencies<=128 && List.sort compare dependencies=expected_dependencies &&
          List.mem filter_source dependencies && List.mem (dependency_root^"/reader.py") dependencies) "annotation filter dependency closure mismatch";
        let checks_report=bound (get inputs "checks_report") in
        require (checks_report=directory^"/checks.rpt") "annotation filter checks report source mismatch";
        let associations=list (get inputs "inputs") in
        let list_paths value=match value with `Null -> [] | `List xs -> List.map text xs | _ -> invalid_arg "native LEF list required" in
        let lefs=selected (get effective "TECH_LEFS") (text (get effective "DEFAULT_CORNER")) @
          list_paths (get effective "CELL_LEFS") @ list_paths (get effective "EXTRA_LEFS") @ list_paths (get effective "PAD_LEFS") in
        require (List.map (fun row -> text (get row "original_path")) associations=text (get state "odb")::lefs) "annotation filter physical/LEF input selection mismatch";
        let actual=List.map (fun row ->
          exact row ["original_path";"actual_path";"retained";"bytes"];
          let retained=bound (get row "retained") in
          require (Filename.dirname retained=directory && get row "actual_path"=s (executed retained) &&
            get row "bytes"=`Int (Unix.stat (file retained)).st_size) "annotation filter retained input mismatch";
          text (get row "actual_path")) associations in
        (match associations with
         | odb::_ -> require (get (get odb "retained") "sha256"=s (L.hash (file (local (text (get state "odb")))))) "annotation filter did not consume exact physical ODB"
         | [] -> invalid_arg "missing annotation filter ODB");
        let argv=List.map text (list (get filter "argv")) in
        let tool=match argv with tool::_ when tool="openroad" || (String.starts_with ~prefix:"/nix/store/" tool && String.ends_with ~suffix:"/bin/openroad" tool) -> tool | _ -> invalid_arg "unsupported annotation filter executable" in
        let expected=[tool;"-threads";"1";"-exit";"-no_splash";"-metrics";executed (directory^"/filter_unannotated_metrics.json");
          "-python";executed script;"--corner";corner;"--checks-report";executed checks_report] @
          (match actual with odb::lefs -> odb::List.concat_map (fun p -> ["--input-lef";p]) lefs | [] -> assert false) in
        require (argv=expected) "annotation filter actual argv/input mismatch";
        let values=read (directory^"/filter_unannotated_metrics.json") in
        let key="timing__unannotated_net_filtered__count__corner:"^corner in
        let value=Timing_physical_metrics.finite (get values key) in
        let state_value=Timing_physical_metrics.finite (get (get output "metrics") key) in
        let goal=match value,state_value with
          | Some a,Some b when a=b && a>=0. && floor a=a && a<=9007199254740991. -> if a=0. then "pass" else "fail"
          | _ -> "unknown" in
        match metrics with `Assoc fields -> obj (["annotation_goal",s goal;
          "annotation_scope",s "native_odb_connected_net_filter_not_blanket_raw_report_zero";
          "annotation_sources",obj ["metric",L.ref_ root (directory^"/filter_unannotated_metrics.json");
            "output_state",L.ref_ root (rel "corners/state_out.json");"process",L.ref_ root (directory^"/native-process-1.json");
            "report",L.ref_ root checks_report;"hook_report",L.ref_ root (directory^"/parasitic-annotation.rpt")]]@fields) | _ -> assert false) in
      metric_views:=metrics::!metric_views;
      let spef_selection=if not physical then [] else (
        let association=List.find (fun r -> get r "role"=s "spef") associations in
        ["spef_selection",obj ["analysis_stage",s "post_pnr";"timing_corner",s corner;
          "input_state",get impl "state";"rcx_output_state",get (List.hd (List.rev chain)) "output_state";
          "view",s "spef";"state_mapping",get state "spef";
          "selected_original_path",get association "original_path";"retained",get association "retained";
          "native_environment_key",s "_CURRENT_SPEF_BY_CORNER";"native_environment_value",get env "_CURRENT_SPEF_BY_CORNER"]]) in
      obj (["corner",s corner;"evidence",inner;"timing",metrics;"inputs",inputs]@spef_selection)) audits in
    List.iter (fun r -> ignore (L.check_ref root r)) sources;
    obj (["status",s "completed";"stage",get a "stage";"corners",`List views;
      "configured_corners",get h "configured_corners";"requested_corners",get h "requested_corners";
      "qualification_corner_coverage",s (if List.for_all (fun c -> List.mem c actual)
        ["nom_fast_1p32V_m40C";"nom_slow_1p08V_125C";"nom_typ_1p20V_25C"] then "complete" else "incomplete");
      "executed_corners",get h "executed_corners";"equivalent_corners",get h "equivalent_corners";
      "implementation",impl;"physical_chain",`List chain;"configuration_delta",delta;
      "originating_synthesis",synth;"retained_producer_files",`List producer_files;
      "all_corner_timing_goal",s (Timing_physical_metrics.aggregate !metric_views)]@common))

let inspect ~run_dir () = L.protect (fun () ->
  let record=L.member run_dir "run.json" in let before=L.hash record in
  let view=inspect_impl ~run_dir ~context:(L.read record) () in
  require (L.hash record=before) "run record changed during physical inspection";view)
let source_files ~run_dir ~context () = L.protect (fun () -> list (get (inspect_impl ~run_dir ~context ()) "sources"))
