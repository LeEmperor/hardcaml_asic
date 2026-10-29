module E = Evidence_json
type scope = Synthesis | Full | Invalid
type verdict = { scope : scope; problems : string list }
let object_ = function `Assoc _ -> true | _ -> false
let get x k = match x with `Assoc xs -> Option.value (List.assoc_opt k xs) ~default:`Null
  | _ -> invalid_arg "expected report object"
let field x k = if object_ x then get x k else `Null
let str = function `String s -> s | x -> E.repr x
let truth = function
  | `Null | `Bool false | `String "" | `List [] | `Assoc [] | `Int 0 -> false
  | `Intlit s -> not (Z.equal (Z.of_string s) Z.zero)
  | `Float f -> f <> 0. | _ -> true
let float = function
  | `Int i -> Some (float_of_int i)
  | `Intlit s -> let f = Z.to_float (Z.of_string s) in
    if not (Float.is_finite f) then invalid_arg "int too large to convert to float";
    Some f
  | `Float f -> Some f | _ -> None
let numeric ?(count=false) ?(nonnegative=false) x = match float x with
  | Some f -> Float.is_finite f && (not nonnegative || f >= 0.)
    && (not count || Float.floor f = f)
  | None -> false
let number ?(digits=3) x = match float x with
  | Some f when Float.is_finite f -> Printf.sprintf "%.*f" digits f
  | _ -> "n/a"
(* Python equality does not round large integer identities through binary64. *)
let integer = function `Int i -> Some (Z.of_int i) | `Intlit s -> Some (Z.of_string s)
  | `Bool b -> Some (if b then Z.one else Z.zero) | _ -> None
let rec equal a b = match integer a, integer b with
  | Some a, Some b -> Z.equal a b
  | Some a, None -> (match b with `Float f when Float.is_finite f && Float.floor f=f -> Z.equal a (Z.of_float f) | _ -> false)
  | None, Some _ -> equal b a
  | None, None -> match a,b with
    | `Float a, `Float b -> a=b
    | `List a, `List b -> List.length a=List.length b && List.for_all2 equal a b
    | `Assoc a, `Assoc b -> List.length a=List.length b && List.for_all (fun (k,v) ->
      match List.assoc_opt k b with Some w -> equal v w | None -> false) a
    | _ -> a=b
let is x s = x = `String s
let evaluate ~context:r t =
  let problems = ref [] in
  let add s = problems := s :: !problems in
  List.iter (fun k -> let a=get r k and b=get t k in
    if a=`Null || b=`Null then add ("missing "^k^" in run or results record")
    else if not (equal a b) then add ("contradictory "^k^": run="^E.repr a^", results="^E.repr b)) ["run_id";"build_identity"];
  List.iter (fun (a,b) -> if not (equal (get r a) (get t b)) then
    add ("contradictory "^b^": run="^E.repr (get r a)^", results="^E.repr (get t b)))
    ["status","process_status";"requested_stage","requested_stage";"completed_stage","completed_stage"];
  let requested=get r "requested_stage" and completed=get r "completed_stage" in
  let rq=get t "requested_stage" and cp=get t "completed_stage" in
  let valid x = (match x with `List _ -> invalid_arg "unhashable type: 'list'"
    | `Assoc _ -> invalid_arg "unhashable type: 'dict'" | _ -> ());
    is x "synthesis" || is x "full" in
  let scope = if not (valid requested && valid rq) then (
    add ("unknown requested stage: run="^E.repr requested^", results="^E.repr rq); Invalid)
    else if requested<>rq then Invalid else if is requested "full" then Full else Synthesis in
  if not ((valid completed || completed=`Null) && (valid cp || cp=`Null)) then
    add ("unknown completed stage: run="^E.repr completed^", results="^E.repr cp);
  if not (is (get r "status") "completed" && is (get t "process_status") "completed") then
    add ("process did not complete: run="^E.repr (get r "status")^", results="^E.repr (get t "process_status"));
  if scope<>Invalid && (completed<>requested || cp<>requested) then
    add ("requested "^str requested^" but completed stage is run="^E.repr completed^", results="^E.repr cp);
  (match get t "errors" with `List xs -> List.iter (fun e -> add ("collection error: "^str e)) xs
    | _ -> add "collection errors field missing or malformed");
   (match get t "resource_evidence" with
   | `Null -> () (* Historical direct evaluation has no manifest; run adds a fresh inspection. *)
   | evidence ->
     if field (field evidence "provenance") "run_id"<>get r "run_id" ||
        field (field evidence "provenance") "build_identity"<>get r "build_identity" then add "resource evidence run/build provenance mismatch";
     if field (field evidence "provenance") "requested_stage"<>get r "requested_stage" then add "resource evidence requested-stage provenance mismatch";
      List.iter add (Resource_evidence.problems evidence));
    (match get t "timing_intent" with
     | `Null -> if get r "timing_physical_expected"=`Bool true then add "required physical timing evidence missing"
     | evidence when List.mem (field evidence "status") [`String "invalid";`String "failed"] ->
       add ("timing intent evidence "^str (field evidence "status")^": "^str (field evidence "reason"))
     | evidence when equal (field (field evidence "provenance") "schema") (`Int 2) ->
       if scope=Full then (
         if field evidence "qualification_corner_coverage"<>`String "complete" then add "required fast/slow/typical qualification corners not all executed";
         if field evidence "all_corner_timing_goal"<>`String "pass" then add ("all-corner extracted timing "^str (field evidence "all_corner_timing_goal"));
         match field evidence "corners" with
         | `List corners -> List.iter (fun corner ->
           if field (field corner "timing") "electrical_goal"<>`String "pass" then add "all-corner electrical limits failed or unavailable";
           if field (field corner "timing") "annotation_goal"<>`String "pass" then add "extracted parasitic annotation failed or unavailable") corners
         | _ -> add "all-corner evidence missing")
     | _ -> ());
  let metrics=get t "metrics" in
  if not (object_ metrics) then add "metrics missing or malformed";
  let check container name count zero =
    let item=field container name in let v=field item "value" and reason=field item "unavailable_reason" in
    if reason<>`Null then add (name^" unavailable: "^str reason)
    else if not (numeric ~count ~nonnegative:true v) then add (name^" missing or malformed")
    else if zero && not (equal v (`Int 0)) then add (name^" = "^number ~digits:0 v) in
  check metrics "mapped_area" false false; check metrics "mapped_cells" true false;
  let synthesis=get t "synthesis_checks" in
  if not (object_ synthesis) then add "synthesis_checks missing or malformed";
  List.iter (fun n -> check synthesis n true true) ["unmapped_instances";"synthesis_errors";"inferred_latches"];
   if scope=Full then (
     if get t "physical_profile"=`String "cmos5l_real_gds_v1" || get r "physical_checks_sha256"<>`Null then (
       if get t "physical_profile"<>`String "cmos5l_real_gds_v1" then add "physical checking profile missing";
       let evidence=get t "physical_evidence" in
       if field evidence "status"<>`String "pass" || field evidence "lvs_scope"<>`String "abstract_macro_boundary_with_schematic_cdl"
       then add "required physical profile evidence missing or failed";
       List.iter (fun name -> if field (field (get t "checks") name) "status"<>`String "pass" then add (name ^ " electrical check failed or missing")) ["max_slew";"max_cap"]);
    let goal=get t "timing_goal" in if not (is goal "pass") then add ("timing goal "^str goal);
    (match get t "timing_unconstrained_modes" with
      | `List xs when List.for_all (function `String _ -> true | _ -> false) xs ->
        if xs<>[] then add ("unconstrained timing modes: "^String.concat ", " (List.map str xs))
      | _ -> add "timing_unconstrained_modes missing or malformed");
    List.iter (fun name -> let item=field metrics name in
      let v=field item "value" and reason=field item "unavailable_reason" and corner=field item "corner" in
      if reason<>`Null then add (name^" unavailable: "^str reason)
      else if not (numeric ~nonnegative:true v) ||
        (match float v with Some f -> abs_float f>=1e30 | _ -> true) ||
        (match corner with `String s -> s="" | _ -> true) then add (name^" missing or malformed")) ["setup_slack";"hold_slack"];
    let checks=get t "checks" in if not (object_ checks) then add "physical checks missing or malformed";
    List.iter (fun name -> let status=field (field checks name) "status" in
      if not (is status "pass") then add (name^" "^(if truth status then str status else "missing"))) ["drc";"lvs";"antenna"];
    match get t "postchecks" with
    | `List (_::_ as xs) -> List.iteri (fun i entry -> let label="postcheck "^string_of_int (i+1) in
      if not (object_ entry) then add (label^" malformed") else (
        if not (is (get entry "status") "completed") then add (label^" status "^str (get entry "status"));
        let checks=get entry "checks" in if not (object_ checks) then add (label^" checks missing or malformed");
        List.iter (fun name -> let status=field checks name in
          if not (is status "pass") then add (name^" "^(if truth status then str status else "missing"))) ["precheck";"gate_level"])) xs
    | _ -> add "required postchecks missing or malformed");
  {scope; problems=List.rev !problems}
let accepted v = v.problems=[]
let exit_code v = if accepted v then 0 else 1

let file p = try (Unix.stat p).Unix.st_kind=Unix.S_REG with Unix.Unix_error ((Unix.ENOENT|Unix.ENOTDIR),_,_) -> false
let read p = Retained_file.read p
let strip s =
  (* Python str.strip's Unicode whitespace, also used around Markdown cells. *)
  let spaces=[" ";"\t";"\n";"\r";"\011";"\012";"\028";"\029";"\030";"\031";
    "\194\133";"\194\160";"\225\154\128";"\226\128\128";"\226\128\129";
    "\226\128\130";"\226\128\131";"\226\128\132";"\226\128\133";
    "\226\128\134";"\226\128\135";"\226\128\136";"\226\128\137";
    "\226\128\138";"\226\128\168";"\226\128\169";"\226\128\175";
    "\226\129\159";"\227\128\128"] in
  let rec left i = match List.find_opt (fun w -> i+String.length w<=String.length s &&
    String.sub s i (String.length w)=w) spaces with Some w -> left (i+String.length w) | None -> i in
  let start=left 0 in
  let rec right i = match List.find_opt (fun w -> i-String.length w>=start &&
    String.sub s (i-String.length w) (String.length w)=w) spaces with Some w -> right (i-String.length w) | None -> i in
  String.sub s start (right (String.length s)-start)
let children p =
  let directory = try (Unix.stat p).Unix.st_kind=Unix.S_DIR
    with Unix.Unix_error ((Unix.ENOENT|Unix.ENOTDIR),_,_) -> false in
  if directory then Sys.readdir p |> Array.to_list |> List.sort String.compare
    |> List.map (Filename.concat p) else []
let join root name = if Filename.is_relative name then Filename.concat root name else name
let lines s =
  let s=Str.global_replace (Str.regexp "\r\n\\|\r\\|\011\\|\012\\|\028\\|\029\\|\030\\|\194\133\\|\226\128\168\\|\226\128\169") "\n" s in
  let xs=String.split_on_char '\n' s in
  if String.ends_with ~suffix:"\n" s then List.rev (List.tl (List.rev xs)) else if s="" then [] else xs
(* Width is Unicode code points, like Python's format mini-language, not bytes. *)
let width s = String.fold_left (fun n c -> if Char.code c land 0xc0=0x80 then n else n+1) 0 s
let pad ?(right=false) n s = let p=String.make (max 0 (n-width s)) ' ' in if right then p^s else s^p
let flow_dir root context =
  let outputs=match context with `Assoc xs -> Option.value (List.assoc_opt "outputs" xs) ~default:(`Assoc []) | _ -> invalid_arg "expected report context object" in
  let name=match outputs with `Assoc xs -> Option.value (List.assoc_opt "flow" xs) ~default:(`String "project/runs/asic") | _ -> invalid_arg "expected outputs object" in
  match name with `String s -> join root s | _ -> invalid_arg "expected flow path string"
let csv_rows s =
  let n=String.length s and b=Buffer.create 64 in
  let finish () = let s=Buffer.contents b in Buffer.clear b; s in
  let rec rows i quoted start active row acc =
    if i=n then List.rev (if active || row<>[] then List.rev (finish ()::row)::acc else acc)
    else let c=s.[i] in
      if quoted then if c='"' then
        if i+1<n && s.[i+1]='"' then (Buffer.add_char b '"'; rows (i+2) true false true row acc)
        else rows (i+1) false false true row acc
      else (Buffer.add_char b c; rows (i+1) true false true row acc)
      else if c='"' && start then rows (i+1) true false true row acc
      else if c=',' then rows (i+1) false true true (finish ()::row) acc
      else if c='\r' || c='\n' then
        let row=if not active && row=[] then [] else List.rev (finish ()::row) in
        rows (if c='\r' && i+1<n && s.[i+1]='\n' then i+2 else i+1) false true false [] (row::acc)
      else (Buffer.add_char b c; rows (i+1) false false true row acc) in
  rows 0 false true false [] []
let corner_timing path =
  if not (file path) then [] else
  let corners=ref [] in
  let pattern=Str.regexp "^timing__\\(setup\\|hold\\)__\\(ws\\|tns\\)__corner:\\(.+\\)$" in
  let counts=Str.regexp "^timing__\\(setup\\|hold\\)_vio__count__corner:\\(.+\\)$" in
  let matches pattern key = Str.string_match pattern key 0 &&
    (Str.match_end ()=String.length key ||
      (Str.match_end ()=String.length key-1 && String.ends_with ~suffix:"\n" key)) in
  List.iter (function [key;raw] ->
    let matched=if matches pattern key then Some (Str.matched_group 1 key,Str.matched_group 2 key,Str.matched_group 3 key)
      else if matches counts key then Some (Str.matched_group 1 key,"vio",Str.matched_group 2 key) else None in
    (match matched with None -> () | Some (mode,field,corner) ->
      let raw=strip raw in
      let digit c = c>='0' && c<='9' in
      let valid=ref (not (String.contains raw 'x' || String.contains raw 'X')) in
      String.iteri (fun i c -> if c='_' && (i=0 || i+1=String.length raw || not (digit raw.[i-1] && digit raw.[i+1])) then valid:=false) raw;
      if !valid then match float_of_string_opt raw with None -> () | Some f ->
      let value=if field="ws" && abs_float f>=1e30 then `Null else `Float f in
      let old=Option.value (List.assoc_opt corner !corners) ~default:[] in
      corners:=(corner,(mode^"_"^field,value)::List.remove_assoc (mode^"_"^field) old)::List.remove_assoc corner !corners)
    | _ -> ()) (csv_rows (read path));
  List.sort (fun (a,_) (b,_) -> String.compare a b) !corners
let render ~run_dir ~context:r ~results:t ~source verdict =
  let b=Buffer.create 2048 in let out s=Buffer.add_string b (s^"\n") in
  out ("run        "^str (get t "run_id")^"  ("^run_dir^")");
  out ("bundle     "^str (get r "bundle"));
  out ("status     "^str (get t "process_status")^"   stage "^str (get t "completed_stage")^" of "^str (get t "requested_stage")^"   source "^source);
  out ("scope      "^(match verdict.scope with Synthesis -> "synthesis-only acceptance" | Full -> "full-flow acceptance" | Invalid -> "invalid/unknown"));
  out "\nSYNTHESIS EVIDENCE";
  let metrics=get t "metrics" in
  let display container name digits = let item=field container name in let reason=field item "unavailable_reason" in
    out ("  "^pad 22 name^" "^number ~digits (field item "value")^(if reason<>`Null then "   "^str reason else "")) in
  display metrics "mapped_area" 3; display metrics "mapped_cells" 0;
  (match get t "resource_evidence" with `Null -> out "  resource realization unavailable (historical results have no resource evidence)"
   | evidence -> out ("  resource coverage "^str (get evidence "coverage"));
     (match get evidence "observations" with `List observations -> List.iter (fun o ->
       out ("  resource "^str (get o "stage")^": "^str (get o "status"));
       match get o "resources" with `List rows -> List.iter (fun row -> out ("    "^str (get row "resource_id")^": "^str (get row "status")^" — "^str (get row "reason"))) rows | _ -> ()) observations | _ -> ());
     List.iter (fun p -> out ("  resource: "^p)) (Resource_evidence.problems evidence));
   List.iter (fun n -> display (get t "synthesis_checks") n 0) ["unmapped_instances";"synthesis_errors";"inferred_latches"];
   (match get t "timing_intent" with
    | `Null -> ()
    | evidence ->
      out (if field evidence "stage"=`String "post_pnr" then "\nLINKED POST-PNR TIMING INTENT" else "\nLINKED PRE-PNR TIMING INTENT");
      out ("  status "^str (field evidence "status")^"; exhaustive exception-effect coverage unavailable (not pass)");
      if equal (field (field evidence "provenance") "schema") (`Int 2) then (
        out ("  all-corner timing "^str (field evidence "all_corner_timing_goal"));
        (match field evidence "executed_corners" with `List xs -> out ("  actually executed "^String.concat ", " (List.map str xs)) | _ -> ());
        match field evidence "corners" with `List xs -> List.iter (fun corner ->
          let timing=field corner "timing" in
          out ("  "^str (field corner "corner")^": setup "^str (field timing "setup_goal")^", hold "^str (field timing "hold_goal")^
            ", electrical "^str (field timing "electrical_goal")^(if field timing "annotation_goal"=`Null then "" else ", native connected-net annotation "^str (field timing "annotation_goal")))) xs | _ -> ());
      if field evidence "reason"<>`Null then out ("  "^str (field evidence "reason"));
      if field evidence "source_digest"<>`Null then out ("  exact source digest "^str (field evidence "source_digest")));
  (if verdict.scope=Full then (
    out "\nTIMING"; out ("  goal "^str (get t "timing_goal"));
    (match get t "timing_unconstrained_modes" with `List (_::_ as xs) when List.for_all (function `String _ -> true | _ -> false) xs ->
      out ("  UNCONSTRAINED: "^String.concat ", " (List.map str xs)^"  (no constrained paths reported; the SDC does not check this mode)") | _ -> ());
    List.iter (fun name -> let item=field metrics name in let corner=field item "corner" and reason=field item "unavailable_reason" in
      out ("  "^pad 12 name^" "^pad ~right:true 10 (number (field item "value"))^" ns   corner "^(if truth corner then str corner else "-")^(if truth reason then "   "^str reason else ""))) ["setup_slack";"hold_slack"];
    let corners=corner_timing (Filename.concat (flow_dir run_dir r) "final/metrics.csv") in
    if corners<>[] then (
      out ("  "^pad 22 "corner"^pad ~right:true 10 "setup ws"^pad ~right:true 11 "setup vio"^pad ~right:true 10 "hold ws"^pad ~right:true 10 "hold vio");
      List.iter (fun (corner,values) -> let n k digits w = pad ~right:true w (number ~digits (Option.value (List.assoc_opt k values) ~default:`Null)) in
        out ("  "^pad 22 corner^n "setup_ws" 3 10^n "setup_vio" 0 11^n "hold_ws" 3 10^n "hold_vio" 0 10)) corners);
    out "\nSIGNOFF CHECKS";
    List.iter (fun name -> let item=field (get t "checks") name in let status=field item "status" and note=field item "reason" in
      out ("  "^pad 10 name^" "^(if truth status then str status else "missing")^(if truth note then "  "^str note else ""))) ["drc";"lvs";"antenna"];
    out "\nPOSTCHECKS";
    (match get t "postchecks" with `List xs -> List.iter (fun entry -> if object_ entry then
      List.iter (fun name -> let status=field (get entry "checks") name in
        out ("  "^pad 12 name^" "^(if truth status then str status else "missing"))) ["precheck";"gate_level"];
        if field (field entry "tools") "replay_profile"=`String "cmos5l_physical_timing_used_cells_v1" then
          out "  replay scope: zero-delay digital functional only; vendor timing/SDF conformance not established") xs | _ -> ());
    List.iter (fun check -> let path=Filename.concat check "tt/precheck/reports/results.md" in
      if file path then List.iter (fun line -> let cells=String.split_on_char '|' line in
        let cells=match cells with [] -> [] | _::xs -> List.rev (match List.rev xs with [] -> [] | _::ys -> ys) |> List.map strip in
        match cells with [check;result] when check<>"Check" && check<>"" && not (try ignore (Str.search_forward (Str.regexp_string "---") result 0); true with Not_found -> false) -> out ("    "^pad 44 check^" "^result) | _ -> ()) (lines (read path))) (children (Filename.concat run_dir "checks"));
    let repair=children (flow_dir run_dir r) |> List.filter (fun p -> try ignore (Str.search_forward (Str.regexp_string "resizer") (Filename.basename p) 0); true with Not_found -> false)
      |> List.concat_map (fun step -> children step |> List.filter (fun p -> Filename.check_suffix p ".log") |> List.concat_map (fun p ->
        lines (read p) |> List.filter_map (fun line -> if (try ignore (Str.search_forward (Str.regexp "RSZ-00\\(33\\|98\\)\\|repair_timing .*-hold\\|Hold violation") line 0); true with Not_found -> false)
        then Some (Filename.basename step,strip line) else None))) in
    out (if repair=[] then "\nHOLD REPAIR  no resizer log found" else "\nHOLD REPAIR (post-CTS resizer)");
    List.iter (fun (step,line) -> out ("  ["^step^"] "^line)) repair
  ) else (
    let reason=if verdict.scope=Synthesis then "not evaluated / not required for requested synthesis operation" else "not evaluated: acceptance scope is invalid" in
    List.iter (fun s -> out ("\n"^s^"  "^reason)) ["TIMING";"SIGNOFF CHECKS";"POSTCHECKS";"HOLD REPAIR"]));
  let sdc=Filename.concat run_dir "project/constraints/top.sdc" in
  if file sdc then (out "\nCONSTRAINTS (project/constraints/top.sdc)"; List.iter (fun l -> out ("  "^l)) (lines (read sdc)));
  out "";
  if verdict.problems<>[] then (out "PROBLEMS"; List.iter (fun p -> out ("  - "^p)) verdict.problems)
  else out (if verdict.scope=Synthesis then "synthesis acceptance passed; physical timing and signoff were not evaluated" else "full-flow acceptance passed");
  Buffer.contents b
type result = { results : E.t; source : string; verdict : verdict; human : string; metadata_sources:E.t list }
let run ?context ?synthesis_state ?(render_human=true) ?(strict_sources=false) run_dir =
  let run_dir=Unix.realpath run_dir in
  let metadata_sources=ref [] and used=ref 0 in
  let metadata path =
    let raw=Retained_file.read ~max_bytes:(min (32*1024*1024) (64*1024*1024 - !used)) path in
    used:= !used+String.length raw;
    let document=match E.parse raw with Ok d -> d | Error e -> invalid_arg e in
    metadata_sources:= !metadata_sources@[`Assoc ["path",`String path;
      "sha256",`String (Identity_json.sha256_bytes raw);"bytes",`Int (String.length raw)]];
    E.value document in
  let context=match context with Some x -> x | None -> metadata (Filename.concat run_dir "run.json") in
  let stored=Filename.concat run_dir "results.json" in
  let results,source=if Retained_file.exists stored then metadata stored,"results.json"
    else Collect_service.to_json (Collect_service.collect ~context ?synthesis_state run_dir),"collected in memory" in
  let results=match get results "resource_evidence" with
    | `Null -> results
    | evidence ->
      (match Resource_evidence.validate evidence with Ok _ -> () | Error e -> invalid_arg ("malformed stored resource evidence: "^e));
      match Resource_evidence.verify_sources ~context ~run_dir evidence with
      | Ok () -> results
       | Error e -> if strict_sources then invalid_arg e;
         let errors=match get results "errors" with `List xs -> xs | _ -> [] in
        `Assoc (("errors",`List (errors@[`String e]))::List.remove_assoc "errors" (match results with `Assoc xs -> xs | _ -> invalid_arg "results object required")) in
  let has_resource_inventory=match Resource_evidence.inventory_available ~run_dir with Ok b -> b | Error e -> invalid_arg e in
  let results=if has_resource_inventory then (
    let fresh=Resource_evidence.collect ~context ~run_dir () in
    `Assoc (["resource_evidence",fresh;"resource_evidence_unavailable_reason",`Null] @
      List.remove_assoc "resource_evidence_unavailable_reason" (List.remove_assoc "resource_evidence" (match results with `Assoc xs -> xs | _ -> invalid_arg "results object required")))) else results in
    let manifest_path=Filename.concat run_dir "project/manifest.json" in
    let manifest=if Retained_file.exists manifest_path then metadata manifest_path else `Null in
     let has_pt7=get context "timing_intent_expected"=`Bool true || get context "timing_physical_expected"=`Bool true ||
      (manifest<>`Null && Timing_intent_flow.expected manifest) in
   let results=if has_pt7 then (
     let evidence=match Timing_intent_flow.inspect ~run_dir () with Ok e -> e | Error message ->
       `Assoc ["status",`String "invalid";"reason",`String message] in
      `Assoc (("timing_intent",evidence)::List.remove_assoc "timing_intent" (match results with `Assoc xs -> xs | _ -> invalid_arg "results object required"))) else results in
   let has_timing_models=get context "timing_physical_expected"=`Bool true ||
      (manifest<>`Null && Timing_physical_flow.enabled manifest) in
   let results=if has_timing_models then (
     (* Stored acceptance must not outlive its functional-view sources or hide a
        later failed postcheck. Reuse collection's read-only source validation. *)
     let fresh=Collect_service.to_json (Collect_service.collect ~context ?synthesis_state run_dir) in
     let errors value=match get value "errors" with `List xs -> xs | _ -> [] in
     let fields=match results with `Assoc fields -> fields | _ -> invalid_arg "results object required" in
     `Assoc (["postchecks",get fresh "postchecks";"errors",`List (List.sort_uniq compare (errors results @ errors fresh))] @
       List.remove_assoc "postchecks" (List.remove_assoc "errors" fields))) else results in
   let source=if has_resource_inventory then source^" + read-only resource reconciliation" else source in
   let source=if has_timing_models then source^" + read-only functional-model source validation" else source in
  let verdict=evaluate ~context results in
   let human=if render_human then render ~run_dir ~context ~results ~source verdict else "" in
   {results; source; verdict; human; metadata_sources= !metadata_sources}
