module E = Evidence_json
module T = Timing_report_model
type links = { resource_id : string; timing_links : E.t; electrical_links : E.t }
type collection = { resources : links list; diagnostics : string list }
let get j k = match j with `Assoc xs -> Option.value (List.assoc_opt k xs) ~default:`Null | _ -> `Null
let text = function `String s when s<>"" -> s | _ -> invalid_arg "expected nonempty timing evidence string"
let list = function `List xs -> xs | _ -> invalid_arg "expected timing evidence array"
let s x = `String x
let obj xs = `Assoc xs
let arr xs = `List xs
let num f = `Float f
let opt f = function None -> `Null | Some x -> f x
let scope = "sampled retained post-PNR macro-boundary observations"
let coverage = "sampled_reported_paths_not_exhaustive"
let unavailable reason = obj ["status",s "unavailable";"reason",s reason]
let protect f = try Ok (f ()) with
  | Invalid_argument e | Failure e | Sys_error e -> Error e
  | Not_found -> Error "incomplete retained timing evidence"
  | Unix.Unix_error (e,f,p) -> Error (f^" "^p^": "^Unix.error_message e)
let relative p = p<>"" && Filename.is_relative p &&
  List.for_all (fun x -> x<>"" && x<>"." && x<>"..") (String.split_on_char '/' p)
let safe_component p = relative p && Filename.basename p=p
let unique label xs = if List.length xs<>List.length (List.sort_uniq String.compare xs) then invalid_arg ("duplicate "^label)
let digest j = let d=text j in
  if String.length d<>64 || not (String.for_all (function '0'..'9'|'a'..'f' -> true | _ -> false) d) then invalid_arg "invalid timing source digest";d
let json raw = match E.parse ~reject_duplicates:true raw with
  | Ok d -> E.value d | Error e -> invalid_arg ("malformed retained timing JSON: "^e)
let role = function T.Data -> "data" | T.Launch_clock -> "launch_clock" | T.Capture_clock -> "capture_clock"
let point (p:T.point) = obj ["line",`Int p.line;"name",s p.name;
  "instance",opt s p.instance;"pin",opt s p.pin;"master",opt s p.master;
  "role",s (role p.role);"edge",s p.edge;"fanout",opt (fun n -> `Int n) p.fanout;
  "reported_load",opt num p.capacitance;"slew",num p.slew;
  "incremental_delay",num p.delay;"arrival",num p.arrival;
  "time_unit",s "ns";"capacitance_unit",s "pF"]
let instances row =
  if get row "status"<>s "matched" || get (get row "selected_implementation") "kind"<>s "macro" then []
  else list (get (get row "realized") "instances") |> List.map (fun i -> text (get i "instance"),text (get i "module"))
let owns identities (p:T.point) = match p.instance,p.master,p.pin with
  | Some instance,Some master,Some _ -> List.mem (instance,master) identities
  | _ -> false
let finite label = function
  | `Int n -> float_of_int n
  | `Intlit n -> let f=float_of_string n in if Float.is_finite f then f else invalid_arg label
  | `Float f when Float.is_finite f -> f
  | _ -> invalid_arg label

let collect ~read ~exists ~flow ~context ~manifest ~resources ~final_netlist = protect (fun () ->
  if not (relative flow) then invalid_arg "unsafe flow-relative timing directory";
  let empty reason diagnostics = {resources=List.map (fun row ->
    {resource_id=text (get row "resource_id");timing_links=unavailable reason;electrical_links=unavailable reason}) resources;diagnostics} in
  if get context "requested_stage"<>s "full" || get context "completed_stage"<>s "full" || get context "status"<>s "completed" then
    empty "final physical stage not reached; sampled post-PNR timing unavailable" []
  else (
    if get context "build_identity"<>get manifest "identity" then invalid_arg "timing run/build identity mismatch";
    let candidates=ref [] in
    (* A bounded native numbered-producer grammar, never a newest-run search. *)
    for ordinal=1 to 256 do
      for occurrence=0 to 3 do
        let base=Printf.sprintf "%02d-openroad-stapostpnr%s" ordinal
          (if occurrence=0 then "" else "-"^string_of_int occurrence) in
        let dir=flow^"/"^base in
        if exists (dir^"/config.json") then candidates:=dir::!candidates
      done
    done;
    match !candidates with
    | [] -> empty "no retained post-PNR STA producer" []
    | _::_::_ -> invalid_arg "ambiguous retained post-PNR STA producers"
    | [dir] ->
      let config_raw,config_ref=read (dir^"/config.json") "json" in
      let config=json config_raw in
      if get (get config "meta") "step"<>s "OpenROAD.STAPostPNR" ||
         get (get config "meta") "librelane_version"<>s "3.1.0.dev3" then invalid_arg "unsupported retained STA producer metadata";
      let in_raw,in_ref=read (dir^"/state_in.json") "json" and out_raw,out_ref=read (dir^"/state_out.json") "json" in
      let state_in=json in_raw and state_out=json out_raw in
      let runtime,runtime_ref=read (dir^"/runtime.txt") "text" in
      if not (Str.string_match (Str.regexp "^[0-9][0-9]+:[0-5][0-9]:[0-5][0-9]\\.[0-9][0-9][0-9]$") (String.trim runtime) 0) then invalid_arg "malformed retained STA runtime";
      let recorded_nl=text (get state_in "nl") in
      if Filename.is_relative recorded_nl || String.contains recorded_nl '\000' ||
         List.exists (fun c -> c="." || c="..") (String.split_on_char '/' recorded_nl) then invalid_arg "unsafe recorded STA netlist path";
      if get state_out "nl"<>s recorded_nl then invalid_arg "STA input/output netlist identity mismatch";
      let recorded_flow=text (get (get context "outputs") "flow") in
      if not (relative recorded_flow) then invalid_arg "unsupported coarse timing flow reference";
      let marker="/"^recorded_flow^"/" in
      let offset=try Str.search_forward (Str.regexp_string marker) recorded_nl 0 with Not_found -> invalid_arg "STA netlist outside recorded flow" in
      let prefix=String.sub recorded_nl 0 offset in
      let run_id=text (get context "run_id") in
      if String.length run_id<8 || not (String.ends_with ~suffix:("_"^String.sub run_id 0 8) (Filename.basename prefix)) then
        invalid_arg "STA recorded path belongs to a different coarse run";
      let nl_suffix=String.sub recorded_nl (offset+String.length marker) (String.length recorded_nl-offset-String.length marker) in
      if not (relative nl_suffix) || List.length (String.split_on_char '/' nl_suffix)<>2 then invalid_arg "unsafe/unsupported STA input netlist reference";
      let _,nl_ref=read (flow^"/"^nl_suffix) "verilog_gate_netlist" in
      if digest (get nl_ref "sha256")<>digest (get final_netlist "sha256") then invalid_arg "STA input netlist does not hash-match observed final netlist";
      let recorded_dir=prefix^"/"^recorded_flow^"/"^Filename.basename dir in
      let corners=list (get config "STA_CORNERS") |> List.map text in
      if corners=[] || List.length corners>64 || not (List.for_all safe_component corners) then invalid_arg "invalid/bounded STA corners";
      unique "STA corner" corners;
      let diagnostics=ref [] in
      let diagnostic msg=if List.length !diagnostics<256 then diagnostics:= !diagnostics@[msg] in
      let preflight=if exists "preflight.json" then (let raw,ref_=read "preflight.json" "json" in Some (json raw,ref_)) else None in
      let common_refs=[config_ref;in_ref;out_ref;runtime_ref;nl_ref;final_netlist] in
      let parsed=ref [] and path_count=ref 0 and point_count=ref 0 and points_exhausted=ref false in
      List.iter (fun corner ->
        let corner_dir=dir^"/"^corner in
        let lib_name=text (get manifest "top_module")^"__"^corner^".lib" in
        if not (safe_component lib_name) then invalid_arg "unsafe generated STA library name";
        let required=[corner_dir^"/sta.log";corner_dir^"/"^lib_name] in
        if not (List.for_all exists required) then diagnostic ("missing retained log/unit library for "^corner)
        else (
          if get (get state_out "lib") corner<>s (recorded_dir^"/"^corner^"/"^lib_name) then invalid_arg "STA generated library/corner binding mismatch";
          let lib_raw,unit_ref=read (corner_dir^"/"^lib_name) "liberty" in
          let log_raw,log_ref=read (corner_dir^"/sta.log") "sta_log" in
          if not (String.starts_with ~prefix:("+ define_corners "^corner^"\n") log_raw) then invalid_arg "STA log/directory corner mismatch";
          let log_lines=String.split_on_char '\n' log_raw in
          let netlist_lines=List.filter (String.starts_with ~prefix:"Reading top-level netlist at '") log_lines in
          if netlist_lines<>["Reading top-level netlist at '"^recorded_nl^"'…"] then invalid_arg "STA log/input netlist binding mismatch";
          let corner_lines=List.filter (String.starts_with ~prefix:"+ define_corners ") log_lines in
          if corner_lines<>["+ define_corners "^corner] then invalid_arg "ambiguous STA log corner identity";
          match Timing_report_units.check lib_raw with
          | Error e -> diagnostic (corner^": "^e)
          | Ok () ->
            let external_models=ref [] and model_refs=ref [] and models_valid=ref true in
            List.iter (fun row -> List.iter (fun (_,master) ->
              if not (List.mem_assoc master !external_models) then (
                let models=get (get (get config "MACROS") master) "lib" in
                let model=match get models corner with `List [`String p] -> p | _ -> invalid_arg "ambiguous/missing macro model corner binding" in
                let declared=get (get (get (get manifest "flow_configuration") "MACROS") master) "lib" in
                let declared=match get declared corner with `List [`String p] -> p | _ -> invalid_arg "missing manifest macro model corner binding" in
                let scheme="pdk_dir::" in
                if String.starts_with ~prefix:scheme declared then (
                  let tail=String.sub declared (String.length scheme) (String.length declared-String.length scheme) in
                  if not (relative tail) || not (String.ends_with ~suffix:("/"^tail) model) then invalid_arg "STA model/manifest binding mismatch")
                else if model<>declared then invalid_arg "STA model/manifest binding mismatch";
                let bindings=match preflight with None -> [] | Some (p,_) ->
                  list (get p "references") |> List.filter (fun b -> match get b "reference" with
                    | `String ref_ -> ref_=declared | _ -> false) in
                match bindings,preflight with
                | [binding],Some (_,pref) ->
                  ignore (digest (get binding "sha256"));
                  let line="Reading cell library for the '"^corner^"' corner at '"^model^"'…" in
                  if List.length (List.filter ((=) line) log_lines)<>1 then invalid_arg "STA log/macro model binding mismatch";
                  model_refs:=[pref];
                  external_models:=(master,obj ["master",s master;"analysis_corner",s corner;
                    "reference",s model;"recorded_reference",get binding "reference";"sha256",get binding "sha256";
                    "verification",s "recorded_external_model_not_read"])::!external_models
                | _ -> models_valid:=false;diagnostic ("missing retained preflight macro model binding: "^master^" "^corner))) (instances row)) resources;
            if !models_valid then List.iter (fun file ->
              let report_path=corner_dir^"/"^file in
              if !points_exhausted then ()
              else if not (exists report_path) then diagnostic ("missing retained path report: "^report_path)
              else (
                let raw,report_ref=read report_path "sta_path_report" in
                let result=T.parse_with_usage ~max_paths:(min 4096 (512- !path_count)) ~max_points:(65536- !point_count) raw in
                point_count:= !point_count+result.consumed_points;
                if result.point_limit_reached then (
                  points_exhausted:=true;
                  diagnostic "query-wide timing point budget reached; remaining path reports not read");
                (match result.no_paths with
                 | None -> ()
                 | Some (reported_corner,mode) ->
                   if reported_corner<>corner || mode<>(if file="max.rpt" then "max" else "min") then invalid_arg "native no-path report corner/mode mismatch";
                   diagnostic (report_path^": native No paths found. (sampled report only)"));
                List.iter (fun d -> diagnostic (report_path^": "^d)) result.diagnostics;
                List.iter (fun (path:T.path) ->
                  if List.assoc_opt "corner" path.fields<>Some corner then invalid_arg "timing report/directory corner mismatch";
                  if List.assoc "type" path.fields<>(if file="max.rpt" then "max" else "min") then invalid_arg "timing report mode mismatch";
                  incr path_count;
                  let refs=common_refs @ [unit_ref;log_ref;report_ref] @ !model_refs in
                  let provenance=obj ["origin",s "coarse_run_retained_post_pnr_sta";
                    "run_id",get context "run_id";"build_identity",get context "build_identity";
                    "stage",s "final_physical";"producer",s "OpenROAD.STAPostPNR";"directory",s dir;
                    "report",report_ref;"first_line",`Int path.first_line;"last_line",`Int path.last_line;
                    "unit_library",unit_ref;"external_models",arr (List.map snd !external_models);
                    "evidence_refs",arr refs] in
                  let path_id=Identity_json.sha256_bytes (E.record_bytes (arr [report_ref;`Int path.first_line;`Int path.last_line])) in
                  parsed:=(path,corner,path_id,provenance,refs)::!parsed) result.paths)) ["max.rpt";"min.rpt"])) corners;
      let parsed=List.rev !parsed in
      let resources=List.map (fun row ->
        let identities=instances row in
        let selected=List.filter (fun ((p:T.path),_,_,_,_) -> owns identities p.data_start || owns identities p.data_end) parsed in
        let paths=List.map (fun ((p:T.path),corner,path_id,provenance,_) ->
          let field k=List.assoc k p.fields in
          let quantity k=num (float_of_string (field k)) in
          obj ["path_id",s path_id;"corner",s corner;"group",s (field "group");"path_type",s (field "type");
            "header_startpoint",s (field "startpoint");"header_endpoint",s (field "endpoint");
            "data_start",point p.data_start;"data_end",point p.data_end;
            "arrival",quantity "arrival";"required",quantity "required";"slack",quantity "slack";
            "time_unit",s "ns";"status",s (field "status");"provenance",provenance]) selected in
        let points=List.concat_map (fun ((p:T.path),corner,path_id,provenance,_) ->
          List.filter (owns identities) p.points |> List.map (fun p -> obj ["path_id",s path_id;
            "corner",s corner;"point",point p;"provenance",provenance])) selected in
        let refs=List.concat_map (fun (_,_,_,_,refs) -> refs) selected |> List.sort_uniq compare in
        let link key values extras=if values=[] then unavailable
          (if identities=[] then "exact reconciled macro identity unavailable" else "no supported sampled macro data-endpoint paths retained")
          else obj (["status",s "observed";"scope",s scope;"coverage",s coverage;key,arr values;"evidence_refs",arr refs]@extras) in
        {resource_id=text (get row "resource_id");timing_links=link "paths" paths [];
         electrical_links=link "points" points ["compliance",s "not_assessed"]}) resources in
      {resources;diagnostics= !diagnostics}))

let validate_links ~references ~resource ~timing_links ~electrical_links = protect (fun () ->
  let exact j keys=match j with `Assoc xs ->
    unique "timing evidence field" (List.map fst xs);
    if List.sort String.compare keys<>List.sort String.compare (List.map fst xs) then invalid_arg "malformed timing link fields"
    | _ -> invalid_arg "expected timing link object" in
  let refs j=let xs=list (get j "evidence_refs") in
    if xs=[] then invalid_arg "missing timing evidence references";
    List.iter (fun r -> if not (List.mem r references) then invalid_arg "unclosed timing evidence reference") xs;xs in
  let identities=instances resource in
  let point_keys=["line";"name";"instance";"pin";"master";"role";"edge";"fanout";"reported_load";"slew";"incremental_delay";"arrival";"time_unit";"capacitance_unit"] in
  let integer label j = let f=finite label j in if f<0. || floor f<>f || f>9007199254740991. then invalid_arg label;f in
  let check_point p =
    exact p point_keys;
    if integer "point line" (get p "line")<1. then invalid_arg "invalid point line";
    let name=text (get p "name") in
    (match get p "instance",get p "pin",get p "master" with
     | `String i,`String pin,`String master when i<>"" && pin<>"" && master<>"" && name=i^"/"^pin -> ()
     | `Null,`Null,`Null -> ()
     | _ -> invalid_arg "inconsistent timing pin identity");
    if not (List.mem (get p "role") [s "data";s "launch_clock";s "capture_clock"]) ||
       not (List.mem (get p "edge") [s "rise";s "fall"]) then invalid_arg "invalid timing point role/edge";
    if get p "time_unit"<>s "ns" || get p "capacitance_unit"<>s "pF" then invalid_arg "unsupported timing point unit";
    List.iter (fun k -> ignore (finite k (get p k))) ["incremental_delay";"arrival"];
    if finite "slew" (get p "slew")<0. then invalid_arg "negative slew";
    if get p "reported_load"<>`Null && finite "reported load" (get p "reported_load")<0. then invalid_arg "negative reported load";
    if get p "fanout"<>`Null then ignore (integer "fanout" (get p "fanout")) in
  let owned p = match get p "instance",get p "master" with `String i,`String m -> List.mem (i,m) identities | _ -> false in
  let provenance p =
    exact p ["origin";"run_id";"build_identity";"stage";"producer";"directory";"report";"first_line";"last_line";"unit_library";"external_models";"evidence_refs"];
    if get p "origin"<>s "coarse_run_retained_post_pnr_sta" || get p "stage"<>s "final_physical" || get p "producer"<>s "OpenROAD.STAPostPNR" then invalid_arg "invalid timing producer origin/stage";
    List.iter (fun k -> ignore (text (get p k))) ["run_id";"build_identity"];
    if not (relative (text (get p "directory"))) then invalid_arg "unsafe timing producer directory";
    let first=integer "first line" (get p "first_line") and last=integer "last line" (get p "last_line") in
    if first<1. || last<first then invalid_arg "invalid timing path span";
    let refs=refs p in
    List.iter (fun k -> if not (List.mem (get p k) refs) then invalid_arg "timing provenance source not closed") ["report";"unit_library"];
    let models=list (get p "external_models") in
    if models=[] then invalid_arg "missing recorded timing model identity";
    List.iter (fun m -> exact m ["master";"analysis_corner";"reference";"recorded_reference";"sha256";"verification"];
      List.iter (fun k -> ignore (text (get m k))) ["master";"analysis_corner";"reference";"recorded_reference"];
      ignore (digest (get m "sha256"));
      if get m "verification"<>s "recorded_external_model_not_read" then invalid_arg "unsupported external model verification claim") models in
  let check_link key extra j =
    match get j "status" with
    | `String "unavailable" -> exact j ["status";"reason"];ignore (text (get j "reason"));[]
    | `String "observed" ->
      exact j (["status";"scope";"coverage";key;"evidence_refs"]@extra);
      if get j "scope"<>s scope || get j "coverage"<>s coverage then invalid_arg "unsupported timing coverage claim";
      ignore (refs j);
      let xs=list (get j key) in if xs=[] || List.length xs>4096 then invalid_arg "empty/bounded observed timing links";xs
    | _ -> invalid_arg "unsupported timing link status" in
  let paths=check_link "paths" [] timing_links in
  let timing_refs=if paths=[] then [] else refs timing_links in
  List.iter (fun p ->
    exact p ["path_id";"corner";"group";"path_type";"header_startpoint";"header_endpoint";"data_start";"data_end";"arrival";"required";"slack";"time_unit";"status";"provenance"];
    List.iter (fun k -> ignore (text (get p k))) ["path_id";"corner";"group";"header_startpoint";"header_endpoint"];
    if not (List.mem (get p "path_type") [s "min";s "max"]) || not (List.mem (get p "status") [s "met";s "violated"]) || get p "time_unit"<>s "ns" then invalid_arg "invalid path type/status/unit";
    List.iter (fun k -> ignore (finite k (get p k))) ["arrival";"required";"slack"];
    let start=get p "data_start" and stop=get p "data_end" in check_point start;check_point stop;
    if get start "role"<>s "data" || get stop "role"<>s "data" || not (owned start || owned stop) then invalid_arg "timing path has no exact owned data endpoint";
    let prov=get p "provenance" in
    provenance prov;
    List.iter (fun r -> if not (List.mem r timing_refs) then invalid_arg "timing path reference absent from link closure") (refs prov);
    let expected_id=Identity_json.sha256_bytes (E.record_bytes (arr [get prov "report";get prov "first_line";get prov "last_line"])) in
    if get p "path_id"<>s expected_id then invalid_arg "timing path id/span/source mismatch";
    List.iter (fun point ->
      let line=finite "endpoint line" (get point "line") in
      if line<finite "first line" (get prov "first_line") || line>finite "last line" (get prov "last_line") then invalid_arg "endpoint outside timing path span") [start;stop];
    List.iter (fun m -> if get m "analysis_corner"<>get p "corner" then invalid_arg "timing path/model corner mismatch") (list (get prov "external_models"));
    if (finite "slack" (get p "slack")<0.)<>(get p "status"=s "violated") then invalid_arg "timing path slack/status conflict") paths;
  unique "timing path id" (List.map (fun p -> text (get p "path_id")) paths);
  let points=check_link "points" ["compliance"] electrical_links in
  let electrical_refs=if points=[] then [] else refs electrical_links in
  if points<>[] && get electrical_links "compliance"<>s "not_assessed" then invalid_arg "resource electrical compliance not assessed";
  List.iter (fun e ->
    exact e ["path_id";"corner";"point";"provenance"];
    let p=get e "point" in check_point p;
    if not (owned p) then invalid_arg "electrical point not owned by exact reconciled macro";
    let path=List.find_opt (fun p -> get p "path_id"=get e "path_id") paths in
    (match path with Some path when get path "corner"=get e "corner" && get path "provenance"=get e "provenance" -> ()
     | _ -> invalid_arg "electrical point lacks linked timing path provenance");
    let prov=get e "provenance" in
    provenance prov;
    List.iter (fun r -> if not (List.mem r electrical_refs) then invalid_arg "electrical point reference absent from link closure") (refs prov);
    let line=finite "point line" (get p "line") in
    if line<finite "first line" (get prov "first_line") || line>finite "last line" (get prov "last_line") then invalid_arg "electrical point outside timing path span") points)
