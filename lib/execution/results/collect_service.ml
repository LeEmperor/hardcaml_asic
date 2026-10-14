module E = Evidence_json
type metric = { value : E.t; unit_ : string; definition : string; stage : string;
  corner : E.t; source : string; unavailable_reason : E.t }
let metric ?(corner=`Null) ?(reason=`Null) ~value ~unit_ ~definition ~stage ~source () =
  {value; unit_; definition; stage; corner; source;
   unavailable_reason = if value=`Null then reason else `Null}
let metric_json m = `Assoc ["value",m.value; "unit",`String m.unit_;
  "definition",`String m.definition; "stage",`String m.stage; "corner",m.corner;
  "source",`String m.source; "unavailable_reason",m.unavailable_reason]
type t = E.t
let to_json t = t
let save path t = Result_store.save_bytes path (E.record_bytes t)
let fields = function `Assoc xs -> xs | _ -> invalid_arg "expected object"
let get x k = match List.assoc_opt k (fields x) with Some v -> v | None -> `Null
let required x k = match x with
  | `Assoc xs -> (match List.assoc_opt k xs with Some v -> v | None -> invalid_arg ("'"^k^"'"))
  | `List _ -> invalid_arg "list indices must be integers or slices, not str"
  | `String _ -> invalid_arg "string indices must be integers, not 'str'"
  | x -> let name=match x with `Null -> "NoneType" | `Bool _ -> "bool" | `Float _ -> "float" | _ -> "int" in
    invalid_arg ("'"^name^"' object is not subscriptable")
let text = function `String s -> s | _ -> invalid_arg "expected path string"
let obj_default x k = match List.assoc_opt k (fields x) with None -> `Assoc [] | Some v -> v
let update x xs = `Assoc (fields x @ xs)
let file p = try (Unix.stat p).Unix.st_kind = Unix.S_REG with Unix.Unix_error ((Unix.ENOENT|Unix.ENOTDIR),_,_) -> false
let children p = try Array.to_list (Sys.readdir p) |> List.sort String.compare
  |> List.map (Filename.concat p) with Sys_error _ -> []
let read p = E.value (E.read p)
let csv path =
  let ic = open_in_bin path in
  let s = Fun.protect ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic)) in
  let n=String.length s and b=Buffer.create 64 in
  let rec rows i quoted start active row acc =
    let finish () = let x=Buffer.contents b in Buffer.clear b; `String x in
    if i=n then
      if active || row<>[] then List.rev (List.rev (finish ()::row)::acc) else List.rev acc
    else let c=s.[i] in
      if quoted then
        if c='"' then
          if i+1<n && s.[i+1]='"' then (Buffer.add_char b '"'; rows (i+2) true false true row acc)
          else rows (i+1) false false true row acc
        else (Buffer.add_char b c; rows (i+1) true false true row acc)
      else if c='"' && start then rows (i+1) true false true row acc
      else if c=',' then rows (i+1) false true true (finish ()::row) acc
      else if c='\r' || c='\n' then
        let row = if not active && row=[] then [] else List.rev (finish ()::row) in
        let j = if c='\r' && i+1<n && s.[i+1]='\n' then i+2 else i+1 in
        rows j false true false [] (row::acc)
      else (Buffer.add_char b c; rows (i+1) false false true row acc) in
  let rows = rows 0 false true false [] [] in
  List.fold_left (fun acc -> function
    | [`String k; v] -> if List.mem_assoc k acc then List.map (fun (key,x) -> key,if key=k then v else x) acc else acc@[k,v]
    | row -> invalid_arg ("expected two columns, got "^E.repr (`List row))) [] rows
let collect ?context ?synthesis_state run_dir =
  let record = match context with Some x -> x | None -> read (Filename.concat run_dir "run.json") in
  let relative p =
    let prefix = if Filename.check_suffix run_dir "/" then run_dir else run_dir^"/" in
    if String.starts_with ~prefix p then String.sub p (String.length prefix) (String.length p-String.length prefix)
    else invalid_arg (p^" is not in the selected run directory") in
  let flow_name = text (required (required record "outputs") "flow") in
  let flow = if Filename.is_relative flow_name then Filename.concat run_dir flow_name else flow_name in
  let synth = ref (Filename.concat flow "06-yosys-synthesis/reports/stat.json") in
  let synth_state = ref (Filename.concat flow "06-yosys-synthesis/state_out.json") in
  let metrics = Filename.concat flow "final/metrics.csv" in
  let errors = ref [] in
  let error s = errors := !errors @ [`String s] in
  let optional p f default = if file p then
    try f () with Invalid_argument s -> error (relative p^": "^s); default
    else default in
  let values = try optional metrics (fun () -> csv metrics) [] with
    Sys_error s -> error (relative metrics^": "^s); [] in
  let creator = ref `Null in
  let stats = optional !synth (fun () ->
    let report=read !synth in
    let stats=required report "design" in creator := get report "creator";
    (match stats with `Assoc _ -> () | _ -> invalid_arg "design must be an object"); stats) `Null in
  let state_metrics = optional !synth_state (fun () -> required (read !synth_state) "metrics") (`Assoc []) in
  let stats,state_metrics = match synthesis_state with
    | None -> stats,state_metrics
    | Some path -> synth:=path; synth_state:=path;
      let sm=required (read path) "metrics" in
      `Assoc ["area",get sm "design__instance__area"; "num_cells",get sm "design__instance__count"],sm in
  let number raw label =
    if raw=`Null then `Null,`String "report absent or metric missing" else
    let parsed = match raw with
      | `Float f -> Some f | `Int n -> Some (float_of_int n)
      | `Intlit s -> let f=Z.to_float (Z.of_string s) in
        if not (Float.is_finite f) then invalid_arg "int too large to convert to float"; Some f
      | `Bool b -> Some (if b then 1. else 0.)
      | `String s ->
        (* Python float accepts decimal text/underscores, not OCaml hex floats. *)
        let s=String.trim s in
        let digit c = c >= '0' && c <= '9' in
        let underscore_ok = ref true in
        String.iteri (fun i c -> if c='_' &&
          (i=0 || i+1=String.length s || not (digit s.[i-1]) || not (digit s.[i+1]))
          then underscore_ok:=false) s;
        if not !underscore_ok || String.contains s 'x' || String.contains s 'X' then None
        else (try Some (float_of_string s) with Failure _ -> None)
      | _ -> None in
    match parsed with
    | Some f when Float.is_finite f -> `Float f,`Null
    | _ -> error ("malformed "^label^": "^E.repr raw); `Null,`String "malformed metric" in
  let stat field = if stats=`Null then `Null else get stats field in
  let mk name field unit_ definition =
    let value,reason=number (stat field) name in
    name,metric_json (metric ~value ~reason ~unit_ ~definition ~stage:"Yosys.Synthesis" ~source:(relative !synth) ()) in
  let mapped=List.map (fun (a,b,c,d) -> mk a b c d)
    ["mapped_area","area","um^2","sum of mapped standard-cell areas";
     "sequential_area","sequential_area","um^2","mapped sequential-cell area";
     "mapped_cells","num_cells","cells","mapped standard-cell instance count"] in
  let timing = List.map (fun (name,prefix,mode) ->
    let valid = List.filter_map (fun (k,raw) ->
      if String.starts_with ~prefix k then match number raw k with `Float f,_ -> Some (k,f) | _ -> None else None) values in
    let has_corner k = let token="corner:" in
      let rec find i = if i+7>String.length k then None else if String.sub k i 7=token then Some (i+7) else find (i+1) in find 0 in
    let best = List.fold_left (fun best ((k,f) as item) -> match best with
      | None -> Some item | Some (bk,bf) ->
        if f<bf || (f=bf && synthesis_state<>None && has_corner bk=None && has_corner k<>None) then Some item else best) None valid in
    let value,corner,reason = match best with
      | Some (_,f) when abs_float f>=1e30 -> `Null,`Null,`String "no constrained timing paths reported"
      | Some (k,f) -> `Float f,(match has_corner k with None -> `Null | Some i -> `String (String.sub k i (String.length k-i))),`Null
      | None -> `Null,`Null,`String "report absent or metric missing" in
    name,update (metric_json (metric ~value ~corner ~reason ~unit_:"ns" ~definition:"worst slack across reported corners"
      ~stage:"final" ~source:(relative metrics) ())) ["mode",`String mode])
    ["setup_slack","timing__setup__ws","setup"; "hold_slack","timing__hold__ws","hold"] in
  let physical=List.map (fun (name,field,unit_,definition) ->
    let value,reason=number (Option.value (List.assoc_opt field values) ~default:`Null) name in
    name,metric_json (metric ~value ~reason ~unit_ ~definition ~stage:"final" ~source:(relative metrics) ()))
    ["final_standard_cell_area","design__instance__area__stdcell","um^2","standard-cell area after the completed physical flow";
     "final_utilization","design__instance__utilization__stdcell","fraction","standard-cell area divided by placement area"] in
  let checks=List.map (fun (name,keys) ->
    let matches=List.filter_map (fun k -> Option.map (fun v -> k,v) (List.assoc_opt k values)) keys in
    let numeric=List.map (fun (k,v) -> fst (number v k)) matches in
    let status,reason=if List.length matches<>List.length keys then "unknown",`String "metric missing"
      else if List.mem `Null numeric then "unknown",`String "malformed metric"
      else (if List.for_all (function `Float f -> f=0. | _ -> false) numeric then "pass" else "fail"),`Null in
    name,`Assoc ["status",`String status; "source",`String (relative metrics); "raw",`Assoc matches; "reason",reason])
    ["drc",["route__drc_errors";"magic__drc_error__count"]; "lvs",["design__lvs_error__count"];
     "antenna",["antenna__violating__nets";"antenna__violating__pins"]] in
  let unconstrained=List.filter_map (fun (_,m) -> if get m "unavailable_reason"=`String "no constrained timing paths reported"
      then Some (get m "mode") else None) timing in
  let constrained=List.filter_map (fun (_,m) -> if List.mem (get m "mode") unconstrained then None else Some (get m "value")) timing in
  let timing_goal = if constrained=[] || List.mem `Null constrained then "unknown"
    else if List.for_all (function `Float f -> f>=0. | _ -> false) constrained then "pass" else "fail" in
  let synthesis_checks=List.map (fun (label,field) ->
    let value,reason=number (get state_metrics field) label in
    label,metric_json (metric ~value ~reason ~unit_:"count" ~definition:field ~stage:"Yosys.Synthesis" ~source:(relative !synth_state) ()))
    ["unmapped_instances","design__instance_unmapped__count"; "synthesis_errors","synthesis__check_error__count";
     "inferred_latches","design__inferred_latch__count"] in
  let manifest_path=Filename.concat run_dir "project/manifest.json" in
  let manifest=if file manifest_path then read manifest_path else `Assoc [] in
  let env=obj_default record "environment" in
  let runtime=obj_default env "runtime_contract" in
  let container=obj_default (obj_default runtime "observations") "container" in
  let mode=match List.assoc_opt "execution_mode" (fields record) with Some v -> v | None -> get runtime "execution_mode" in
  let version=get (obj_default env "actual") "librelane" in
  let container_version=get container "librelane_version" in
  let truth = function `Null | `Bool false | `String "" | `Assoc [] | `List [] | `Int 0 -> false | _ -> true in
  let librelane=`Assoc ["name",`String "LibreLane"; "version",if mode=`String "dockerized" && truth container_version then container_version else version] in
  let yosys=`Assoc ["name",`String "Yosys"; "version",!creator] in
  let corner=get (obj_default manifest "target") "corner" in
  let add_metric (name,m) = let synthesis=get m "stage"=`String "Yosys.Synthesis" in
    let mode=if synthesis then "synthesis" else if name="setup_slack" then "setup" else if name="hold_slack" then "hold" else "physical" in
    let xs=List.remove_assoc "mode" (fields m) in
    let xs=if synthesis then List.remove_assoc "corner" xs @ ["corner",corner] else xs in
    name,`Assoc (xs@["tool",(if synthesis then yosys else librelane);"mode",`String mode]) in
  let checks=List.map (fun (name,c) -> name,update c ["definition",`String ("reported "^name^" violation counts are zero");
    "unit",`String "count"; "stage",`String "final"; "corner",`Null; "tool",librelane]) checks in
  let reports=List.concat_map (fun step -> children (Filename.concat step "reports")
    |> List.filter (fun p -> Filename.check_suffix p ".rpt" || Filename.check_suffix p ".json")) (children flow) in
  let artifacts = [!synth;metrics;!synth_state;Filename.concat flow "final/metrics.json"] @ reports
    @ List.filter (fun p -> Filename.check_suffix p ".gds") (children (Filename.concat flow "final/gds"))
    @ List.filter (fun p -> Filename.check_suffix p ".v") (children (Filename.concat flow "final/nl")) in
  let artifacts=List.filter file artifacts |> List.map relative |> List.sort_uniq String.compare |> List.map (fun s -> `String s) in
  let postchecks=children (Filename.concat run_dir "checks") |> List.map (fun p -> Filename.concat p "postcheck.json")
    |> List.filter Sys.file_exists |> List.map read in
  `Assoc (["schema_version",`Int 1; "tool",librelane; "mode",`String "nominal and reported corners";
    "metrics",`Assoc (List.map add_metric (mapped@timing@physical)); "checks",`Assoc checks;
    "timing_goal",`String timing_goal; "timing_unconstrained_modes",`List unconstrained;
    "mapped_cell_types",stat "num_cells_by_type"; "synthesis_checks",`Assoc (List.map add_metric synthesis_checks);
    "raw_artifacts",`List artifacts; "errors",`List !errors; "postchecks",`List postchecks]
    @ List.map (fun (out,k) -> out,required record k)
      ["run_id","run_id";"build_identity","build_identity";"process_status","status";
       "requested_stage","requested_stage";"completed_stage","completed_stage"])
