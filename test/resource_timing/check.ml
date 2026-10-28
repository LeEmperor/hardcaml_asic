open Hardcaml_asic_execution
module T = Timing_report_model
module R = Resource_timing_evidence
let s x = `String x
let obj xs = `Assoc xs
let arr xs = `List xs
let get j k = match j with `Assoc xs -> Option.value (List.assoc_opt k xs) ~default:`Null | _ -> `Null
let xs = function `List xs -> xs | _ -> failwith "expected array"
let set j k v = match j with `Assoc xs -> obj ((k,v)::List.remove_assoc k xs) | _ -> assert false
let ok = function Ok x -> x | Error e -> failwith e
let require b = if not b then failwith "assertion failed"
let equal a b = require (a=b)
let close a b = require (abs_float (a-.b)<1e-10)
let number = function `Float f -> f | `Int n -> float_of_int n | _ -> failwith "expected number"
let read_file path = let ic=open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () -> really_input_string ic (in_channel_length ic))
let replace a b raw = Str.global_replace (Str.regexp_string a) b raw
let contains raw part = try ignore (Str.search_forward (Str.regexp_string part) raw 0);true with Not_found -> false
let remove_first_line predicate raw =
  let removed=ref false in
  String.split_on_char '\n' raw |> List.filter (fun line ->
    if not !removed && predicate line then (removed:=true;false) else true) |> String.concat "\n"
let repeat_data_row count raw =
  let row=String.split_on_char '\n' raw |> List.find (fun l -> contains l "hc_resource_7_program/A_DOUT[11]") in
  replace (row^"\n") (String.concat "" (List.init count (fun _ -> row^"\n"))) raw
let slow="nom_slow_1p08V_125C" and fast="nom_fast_1p32V_m40C"
let master="RM_IHPSG13_1P_256x16_c2_bm_bist"
let instance="hc_resource_7_program"
let flow="project/runs/asic"
let producer=flow^"/56-openroad-stapostpnr"
let root="/retained/20261025T034710180883Z_be961b2c/"
let nl_suffix="53-openroad-fillinsertion/tt_um_program_memory.nl.v"
let nl="module tt_um_program_memory(); endmodule\n"
let reference path raw format = obj ["path",s path;"sha256",s (Identity_json.sha256_bytes raw);
  "format",s format;"scope",s "retained observed bytes"]
let final_ref=reference (flow^"/final/nl/tt_um_program_memory.nl.v") nl "verilog_gate_netlist"
let resource=obj ["resource_id",s "program";"status",s "matched";
  "selected_implementation",obj ["kind",s "macro";"name",s master];
  "realized",obj ["instances",arr [obj ["instance",s instance;"module",s master]]]]
let context=obj ["run_id",s "be961b2c95f74c81ad6af81ca4d2b269";"build_identity",s "build";
  "requested_stage",s "full";"completed_stage",s "full";"status",s "completed";
  "outputs",obj ["flow",s flow]]
let model_base corner=master^(if corner=fast then "_fast_1p32V_m55C.lib" else "_slow_1p08V_125C.lib")
let declared corner="pdk_dir::libs.ref/sram/"^model_base corner
let model corner="/external/pdk/libs.ref/sram/"^model_base corner
let libs f=obj (List.map (fun c -> c,arr [s (f c)]) [slow;fast])
let macros f=obj [master,obj ["lib",libs f]]
let manifest=obj ["identity",s "build";"top_module",s "tt_um_program_memory";
  "flow_configuration",obj ["MACROS",macros declared]]
let units="library (tt_um_program_memory) {\n  capacitive_load_unit (1,pF);\n  time_unit : \"1ns\";\n}\n"
let lib_name c="tt_um_program_memory__"^c^".lib"
let report c f=producer^"/"^c^"/"^f
let fixture slow_raw fast_raw =
  let table=Hashtbl.create 32 in
  let add p raw=Hashtbl.add table p raw in
  let add_json p j=add p (Yojson.Safe.to_string j) in
  add_json (producer^"/config.json") (obj ["meta",obj ["step",s "OpenROAD.STAPostPNR";"librelane_version",s "3.1.0.dev3"];
    "STA_CORNERS",arr [s slow;s fast];"MACROS",macros model]);
  add_json (producer^"/state_in.json") (obj ["nl",s (root^flow^"/"^nl_suffix)]);
  add_json (producer^"/state_out.json") (obj ["nl",s (root^flow^"/"^nl_suffix);
    "lib",obj (List.map (fun c -> c,s (root^producer^"/"^c^"/"^lib_name c)) [slow;fast])]);
  add (producer^"/runtime.txt") "00:00:03.405";
  add (flow^"/"^nl_suffix) nl;
  List.iter (fun c ->
    add (report c (lib_name c)) units;
    add (report c "sta.log") ("+ define_corners "^c^"\n"^
      "Reading cell library for the '"^c^"' corner at '"^model c^"'…\n"^
      "Reading top-level netlist at '"^root^flow^"/"^nl_suffix^"'…\n")) [slow;fast];
  add (report slow "max.rpt") slow_raw;
  add (report fast "min.rpt") fast_raw;
  add_json "preflight.json" (obj ["references",arr (List.map (fun c -> obj [
    "reference",s (declared c);"sha256",s (String.make 64 'a')]) [slow;fast])]);
  table
let collect ?(context=context) ?(manifest=manifest) ?(resource=resource) ?(final_ref=final_ref) ?(flow=flow) table =
  let refs=ref [final_ref] and reads=ref [] in
  let read path format =
    require (Filename.is_relative path && not (List.mem ".." (String.split_on_char '/' path)));
    reads:=path::!reads;
    let raw=Hashtbl.find table path in
    let ref_=reference path raw format in refs:=ref_::!refs;raw,ref_ in
  R.collect ~read ~exists:(Hashtbl.mem table) ~flow ~context ~manifest ~resources:[resource] ~final_netlist:final_ref,
  refs,reads
let links collection = List.hd collection.R.resources
let paths collection = xs (get (links collection).R.timing_links "paths")
let unavailable collection = equal (get (links collection).R.timing_links "status") (s "unavailable")
let tests=ref 0 and failures=ref []
let test name f = incr tests;try f ();print_endline ("PASS "^name) with exn ->
  failures:=name::!failures;prerr_endline ("FAIL "^name^": "^Printexc.to_string exn)
let () =
  let slow_raw=read_file "fixtures/slow-max.rpt" and fast_raw=read_file "fixtures/fast-min.rpt" in
  let fresh ()=fixture slow_raw fast_raw in
  test "actual slow path summary, pin values and launch-clock role" (fun () ->
    let ps,ds=T.parse slow_raw in equal ds [];let p=List.hd ps in
    equal (p.first_line,p.last_line) (7,62);
    equal p.data_start.name (instance^"/A_DOUT[11]");equal p.data_end.name "uo_out[3]";
    close p.data_start.slew 0.067838;equal p.data_start.capacitance (Some 0.004815);
    close (float_of_string (List.assoc "slack" p.fields)) 11.246561;
    let clock=List.find (fun (p:T.point) -> p.name=instance^"/A_CLK") p.points in
    equal clock.role T.Launch_clock);
  test "actual fast hold capture point, blank Cap and capture-clock role" (fun () ->
    let ps,ds=T.parse fast_raw in equal ds [];let p=List.hd ps in
    equal (p.first_line,p.last_line) (7,61);
    equal p.data_end.name (instance^"/A_ADDR[6]");equal p.data_end.capacitance None;
    close p.data_end.slew 0.167545;
    let clock=List.find (fun (p:T.point) -> p.name=instance^"/A_CLK") p.points in
    equal clock.role T.Capture_clock);
  test "legacy parser unchanged and identical summaries" (fun () ->
    let old,ds=Inspection_service.timing_records slow_raw in equal ds [];
    let ps,_=T.parse slow_raw in equal old (List.map (fun (p:T.path) -> p.first_line,p.last_line,p.fields) ps));
  test "edge-tagged native external-delay arithmetic is not a pin" (fun () ->
    let raw=replace "   clock source latency\n" "   clock source latency\n                                  1.000000    1.000000 ^ input external delay\n" slow_raw in
    let ps,ds=T.parse raw in equal ds [];
    let original,_=T.parse slow_raw in equal (List.length (List.hd ps).points) (List.length (List.hd original).points));
  test "negative slack is a valid failing observation" (fun () ->
    let raw=slow_raw |> replace "11.246561   slack (MET)" "-0.125000   slack (VIOLATED)" in
    let ps,ds=T.parse raw in equal ds [];equal (List.assoc "status" (List.hd ps).fields) "violated";
    close (float_of_string (List.assoc "slack" (List.hd ps).fields)) (-0.125));
  List.iter (fun (name,raw) -> test name (fun () -> let ps,ds=T.parse raw in equal ps [];require (ds<>[]))) [
    "nonfinite point",replace "0.067838" "     NaN" slow_raw;
    "unsupported columns",replace "Fanout         Cap" "Fanout        Load" slow_raw;
    "truncated report",String.sub slow_raw 0 (String.length slow_raw-40);
    "slack/status conflict",replace "11.246561   slack (MET)" "-0.125000   slack (MET)" slow_raw;
    "header/data endpoint mismatch",replace "Endpoint: uo_out[3]" "Endpoint: unrelated" slow_raw];
  test "clock pin substituted as data endpoint is rejected" (fun () ->
    let ps,ds=T.parse (replace "A_ADDR[6]" "A_CLK" fast_raw) in equal ps [];require (ds<>[]));
  let missing_arrival=remove_first_line (fun l -> String.ends_with ~suffix:"data arrival time" (String.trim l)) fast_raw in
  test "subtraction arrival cannot replace missing primary arrival" (fun () ->
    let legacy,_=Inspection_service.timing_records missing_arrival in
    require (float_of_string (List.assoc "arrival" (let _,_,f=List.hd legacy in f))<0.);
    let ps,ds=T.parse missing_arrival in equal ps [];require (ds<>[]));
  test "dropping primary arrival and real data pin cannot promote capture clock" (fun () ->
    let raw=remove_first_line (fun l -> contains l (instance^"/A_ADDR[6]")) missing_arrival in
    let ps,ds=T.parse raw in equal ps [];require (ds<>[]));
  test "primary required time cannot be replaced by repeated summary" (fun () ->
    let raw=remove_first_line (fun l -> String.ends_with ~suffix:"data required time" (String.trim l)) fast_raw in
    let ps,ds=T.parse raw in equal ps [];require (ds<>[]));
  test "subtraction sign and complete summary ordering are checked" (fun () ->
    List.iter (fun raw -> let ps,ds=T.parse raw in equal ps [];require (ds<>[])) [
      replace "-0.949038   data arrival time" " 0.949038   data arrival time" fast_raw;
      remove_first_line (fun l -> contains l "-0.949038   data arrival time") fast_raw;
      replace "0.725504   data required time" "0.725504   missing required time" fast_raw]);
  test "attempted points in rejected paths remain charged" (fun () ->
    let raw=repeat_data_row 128 slow_raw |> replace "Endpoint: uo_out[3]" "Endpoint: wrong" in
    let result=T.parse_with_usage ~max_points:256 raw in
    equal result.paths [];require (result.diagnostics<>[]);
    require (result.consumed_points>=128 && result.consumed_points<256);
    require (not result.point_limit_reached);
    let remaining=T.parse_with_usage ~max_points:(256-result.consumed_points) (repeat_data_row 200 slow_raw) in
    require remaining.point_limit_reached;
    equal (result.consumed_points+remaining.consumed_points) 256);
  test "point bound is explicit" (fun () -> let ps,ds=T.parse ~max_points:1 slow_raw in equal ps [];require (ds<>[]));
  test "path bound is explicit" (fun () -> let ps,ds=T.parse ~max_paths:0 slow_raw in equal ps [];require (ds<>[]));
  test "native units valid; comments cannot supply missing units" (fun () ->
    ignore (ok (Timing_report_units.check units));
    require (Result.is_error (Timing_report_units.check "/* time_unit : \"1ns\"; */\ncapacitive_load_unit (1,pF);\n")));
  List.iter (fun (name,raw) -> test name (fun () -> require (Result.is_error (Timing_report_units.check raw)))) [
    "duplicate time units",units^"time_unit : \"1ns\";\n";
    "conflicting time units",units^"time_unit : \"1ps\";\n";
    "missing capacitance unit",replace "capacitive_load_unit (1,pF);" "" units;
    "conflicting capacitance units",units^"capacitive_load_unit (1,fF);\n";
    "unterminated Liberty comment",units^"/*";
    "quoted capacitance declaration",replace "  capacitive_load_unit (1,pF);" "  note : \"capacitive_load_unit (1,pF);\";" units];
  List.iter (fun (name,raw) -> test name (fun () -> require (Result.is_error (Timing_report_units.check raw)))) [
    "nested pin units cannot spoof missing library units", "library(x) { cell(fake) { pin(fake) { time_unit : \"1ns\"; capacitive_load_unit (1,pF); } } }";
    "nested time unit rejected even with valid direct units",replace "\n}" "\n cell(fake) { pin(fake) { time_unit : \"1ns\"; } }\n}" units;
    "nested capacitance unit rejected even with valid direct units",replace "\n}" "\n cell(fake) { capacitive_load_unit (1,pF); }\n}" units;
    "unbalanced library braces",units^"}";
    "truncated balanced-scope library",String.sub units 0 (String.length units-2);
    "unbalanced nested parentheses",replace "\n}" "\n cell(fake { }\n}" units;
    "multiple library scopes",units^units;
    "bare unit declarations cannot imply a library","time_unit : \"1ns\";\ncapacitive_load_unit (1,pF);\n"];
  test "direct library units after balanced nested groups and quoted delimiters" (fun () ->
    let raw="library(x) { /* { fake */ note : \"} fake {\"; cell(fake) { pin(fake) { capacitance : 1; } } time_unit : \"1ns\"; capacitive_load_unit (1,pF); }" in
    ignore (ok (Timing_report_units.check raw)));
  List.iter (fun (label,raw) -> test label (fun () ->
    let result=T.parse_with_usage raw in equal result.paths [];require (result.diagnostics<>[]);equal result.no_paths None)) [
    "empty report explicitly diagnosed","";
    "arbitrary text report explicitly diagnosed","this is not an STA report\n";
    "gzip report explicitly diagnosed","\031\139compressed fixture bytes";
    "binary report explicitly diagnosed","\000not STA"];
  let no_paths="\n===========================================================================\nreport_checks -path_delay min (Hold)\n===========================================================================\n======================= "^fast^" Corner ===================================\n\nNo paths found.\n" in
  test "native no-path report has explicit corner/mode semantics" (fun () ->
    let result=T.parse_with_usage no_paths in equal result.paths [];equal result.diagnostics [];
    equal result.no_paths (Some (fast,"min"));
    let bad=T.parse_with_usage (no_paths^"unrecognized trailing bytes\n") in require (bad.diagnostics<>[]));
  test "collector real paths, model-corner distinction, closure and validator" (fun () ->
    let result,refs,reads=collect (fresh ()) in let result=ok result in
    equal (List.length (paths result)) 2;
    close (number (get (List.hd (paths result)) "slack")) 11.246561;
    let fast_path=List.find (fun p -> get p "corner"=s fast) (paths result) in
    let models=xs (get (get fast_path "provenance") "external_models") in
    let model=List.hd models in
    equal (get model "analysis_corner") (s fast);
    equal (get model "recorded_reference") (s (declared fast));
    require (List.mem (flow^"/"^nl_suffix) !reads);
    let l=links result in ignore (ok (R.validate_links ~references:!refs ~resource
      ~timing_links:l.timing_links ~electrical_links:l.electrical_links));
    equal (get l.electrical_links "compliance") (s "not_assessed"));
  List.iter (fun (label,raw) -> test label (fun () ->
    let t=fresh () in Hashtbl.replace t (report fast "min.rpt") raw;
    let result,_,_=collect t in let result=ok result in
    equal (List.length (paths result)) 1;
    require (List.exists (fun d -> contains d (report fast "min.rpt")) result.diagnostics);
    let ps=xs (get (links result).electrical_links "points") in
    require (List.for_all (fun e -> not (get (get e "point") "pin"=s "A_CLK" && get (get e "point") "role"=s "data")) ps))) [
      "collector missing-arrival attack quarantined",missing_arrival;
      "collector clock-only attack quarantined",remove_first_line (fun l -> contains l (instance^"/A_ADDR[6]")) missing_arrival;
      "collector empty min retains partial diagnostics","";
      "collector gzip min retains partial diagnostics","\031\139compressed fixture bytes";
      "collector arbitrary min retains partial diagnostics","not native STA\n";
      "collector native no-path report is explicit",no_paths];
  test "native no-path corner and mode mismatches rejected" (fun () ->
    List.iter (fun raw -> let t=fresh () in Hashtbl.replace t (report fast "min.rpt") raw;
      let result,_,_=collect t in require (Result.is_error result)) [replace fast slow no_paths;
      replace "report_checks -path_delay min (Hold)" "report_checks -path_delay max (Setup)" no_paths]);
  test "collector budget exhaustion in rejected path stops later reports" (fun () ->
    let t=fresh () in Hashtbl.replace t (report slow "max.rpt") (repeat_data_row 65536 slow_raw);
    let result,_,reads=collect t in let result=ok result in unavailable result;
    require (List.exists (fun d -> contains d "query-wide timing point budget") result.diagnostics);
    require (not (List.mem (report fast "min.rpt") !reads)));
  test "collector charges rejected attempts across reports, not accepted paths only" (fun () ->
    let t=fresh () in
    Hashtbl.replace t (report slow "max.rpt") (repeat_data_row 40000 slow_raw |> replace "Endpoint: uo_out[3]" "Endpoint: wrong");
    let row=String.split_on_char '\n' fast_raw |> List.find (fun l -> contains l "_203_/Q") in
    Hashtbl.replace t (report fast "min.rpt") (replace (row^"\n") (String.concat "" (List.init 30000 (fun _ -> row^"\n"))) fast_raw);
    let result,_,_=collect t in let result=ok result in unavailable result;
    require (List.exists (fun d -> contains d "query-wide timing point budget") result.diagnostics));
  test "collector rejects nested-only units with explicit diagnostics" (fun () ->
    let t=fresh () in Hashtbl.replace t (report fast (lib_name fast))
      "library(x) { cell(fake) { pin(fake) { time_unit : \"1ns\"; capacitive_load_unit (1,pF); } } }";
    let result,_,_=collect t in let result=ok result in equal (List.length (paths result)) 1;
    require (List.exists (fun d -> contains d "direct library") result.diagnostics));
  test "wrong netlist bytes fail binding" (fun () ->
    let t=fresh () in Hashtbl.replace t (flow^"/"^nl_suffix) "different";
    let result,_,_=collect t in require (Result.is_error result));
  test "wrong run fails binding even with same netlist bytes" (fun () ->
    let result,_,_=collect ~context:(set context "run_id" (s "deadbeefother")) (fresh ()) in
    require (Result.is_error result));
  test "state/log netlist reference cannot escape selected flow" (fun () ->
    let t=fresh () in let path=producer^"/state_in.json" in
    let state=Yojson.Safe.from_string (Hashtbl.find t path) in
    Hashtbl.replace t path (Yojson.Safe.to_string (set state "nl" (s (root^flow^"/../../secret"))));
    let result,_,reads=collect t in require (Result.is_error result);
    require (not (List.exists (fun p -> String.contains p '\000' || List.mem ".." (String.split_on_char '/' p)) !reads)));
  test "wrong stage unavailable without source reads" (fun () ->
    let result,_,reads=collect ~context:(set context "completed_stage" (s "synthesis")) (fresh ()) in
    unavailable (ok result);equal !reads []);
  test "unsafe flow rejected before reader" (fun () ->
    let result,_,reads=collect ~flow:"../escape" (fresh ()) in require (Result.is_error result);equal !reads []);
  test "unsafe corner rejected before corner reader" (fun () ->
    let t=fresh () in let config=Yojson.Safe.from_string (Hashtbl.find t (producer^"/config.json")) in
    Hashtbl.replace t (producer^"/config.json") (Yojson.Safe.to_string (set config "STA_CORNERS" (arr [s "../escape"])));
    let result,_,_=collect t in require (Result.is_error result));
  test "missing producer remains unavailable" (fun () -> let result,_,_=collect (Hashtbl.create 0) in unavailable (ok result));
  test "duplicate producer is ambiguous" (fun () ->
    let t=fresh () in Hashtbl.add t (flow^"/57-openroad-stapostpnr/config.json") "{}";
    let result,_,_=collect t in require (Result.is_error result));
  test "wrong producer class rejected" (fun () ->
    let t=fresh () in let p=producer^"/config.json" in
    Hashtbl.replace t p (replace "OpenROAD.STAPostPNR" "OpenROAD.STAPrePNR" (Hashtbl.find t p));
    let result,_,_=collect t in require (Result.is_error result));
  test "report/header corner conflict rejected" (fun () ->
    let t=fresh () in Hashtbl.replace t (report slow "max.rpt") (replace slow fast slow_raw);
    let result,_,_=collect t in require (Result.is_error result));
  test "log corner conflict rejected" (fun () ->
    let t=fresh () in Hashtbl.replace t (report slow "sta.log") (replace slow fast (Hashtbl.find t (report slow "sta.log")));
    let result,_,_=collect t in require (Result.is_error result));
  test "duplicate/conflicting netlist log records rejected" (fun () ->
    let t=fresh () in let p=report slow "sta.log" in
    Hashtbl.replace t p (Hashtbl.find t p^"Reading top-level netlist at '/other/netlist.v'…\n");
    let result,_,_=collect t in require (Result.is_error result));
  test "near-prefix exact instance does not link" (fun () ->
    let row=set resource "realized" (obj ["instances",arr [obj ["instance",s (instance^"_extra");"module",s master]]]) in
    let result,_,_=collect ~resource:row (fresh ()) in unavailable (ok result));
  test "wrong endpoint master does not link" (fun () ->
    let t=fresh () in Hashtbl.replace t (report slow "max.rpt") (replace master "wrong_master" slow_raw);
    Hashtbl.replace t (report fast "min.rpt") (replace master "wrong_master" fast_raw);
    let result,_,_=collect t in unavailable (ok result));
  test "clock-only macro point cannot establish a data endpoint" (fun () ->
    let t=fresh () in
    Hashtbl.replace t (report slow "max.rpt") (slow_raw |>
      replace ("Startpoint: "^instance) "Startpoint: _other_" |>
      replace (instance^"/A_DOUT[11]") "_other_/Q");
    Hashtbl.remove t (report fast "min.rpt");
    let result,_,_=collect t in unavailable (ok result));
  test "missing units cannot become measurements" (fun () ->
    let t=fresh () in List.iter (fun c -> Hashtbl.replace t (report c (lib_name c)) "library (x) {}") [slow;fast];
    let result,_,_=collect t in let result=ok result in unavailable result;require (result.diagnostics<>[]));
  test "external preflight missing remains unavailable" (fun () ->
    let t=fresh () in Hashtbl.remove t "preflight.json";
    let result,_,_=collect t in unavailable (ok result));
  test "manifest model must match config/log model" (fun () ->
    let manifest=set manifest "flow_configuration" (obj ["MACROS",macros (fun _ -> "pdk_dir::wrong.lib")]) in
    let result,_,_=collect ~manifest (fresh ()) in require (Result.is_error result));
  test "generated library must be state-bound to exact corner" (fun () ->
    let t=fresh () in let path=producer^"/state_out.json" in
    let state=Yojson.Safe.from_string (Hashtbl.find t path) in
    Hashtbl.replace t path (Yojson.Safe.to_string (set state "lib" (obj [slow,s "/outside.lib"])));
    let result,_,_=collect t in require (Result.is_error result));
  test "unreconciled resource cannot earn links" (fun () ->
    let result,_,_=collect ~resource:(set resource "status" (s "missing")) (fresh ()) in unavailable (ok result));
  test "link validator rejects unclosed refs and compliance claims" (fun () ->
    let result,refs,_=collect (fresh ()) in let l=links (ok result) in
    require (Result.is_error (R.validate_links ~references:[] ~resource ~timing_links:l.timing_links ~electrical_links:l.electrical_links));
    require (Result.is_error (R.validate_links ~references:!refs ~resource ~timing_links:l.timing_links
      ~electrical_links:(set l.electrical_links "compliance" (s "pass")))));
  test "wire validator rejects wrong pin identity and stage" (fun () ->
    let result,refs,_=collect (fresh ()) in let l=links (ok result) in
    let paths=xs (get l.timing_links "paths") in let p=List.hd paths in
    let bad=set p "data_start" (set (get p "data_start") "pin" (s "WRONG")) in
    let timing=set l.timing_links "paths" (arr (bad::List.tl paths)) in
    require (Result.is_error (R.validate_links ~references:!refs ~resource ~timing_links:timing ~electrical_links:l.electrical_links));
    let bad=set p "provenance" (set (get p "provenance") "stage" (s "synthesis")) in
    let timing=set l.timing_links "paths" (arr (bad::List.tl paths)) in
    require (Result.is_error (R.validate_links ~references:!refs ~resource ~timing_links:timing ~electrical_links:l.electrical_links)));
  test "coherent value forgery differs from source replay despite unchanged hashes" (fun () ->
    let t=fresh () in let result,refs,_=collect t in let l=links (ok result) in
    let paths=xs (get l.timing_links "paths") in
    let changed=set (List.hd paths) "slack" (`Float 12.0) in
    let forged=set l.timing_links "paths" (arr (changed::List.tl paths)) in
    ignore (ok (R.validate_links ~references:!refs ~resource ~timing_links:forged ~electrical_links:l.electrical_links));
    let replay,_,_=collect t in
    require (Evidence_json.record_bytes forged<>Evidence_json.record_bytes (links (ok replay)).timing_links));
  (match Sys.getenv_opt "PT5B_RETAINED_STA" with
   | None -> ()
   | Some dir -> test "optional read-only full original native reports/unit libraries" (fun () ->
     let count=ref 0 in
     List.iter (fun corner ->
       ignore (ok (Timing_report_units.check (read_file (dir^"/"^corner^"/"^lib_name corner))));
       List.iter (fun report ->
         let ps,ds=T.parse (read_file (dir^"/"^corner^"/"^report)) in
         if ds<>[] then failwith (String.concat "; " ds);
         require (ps<>[]);count:= !count+List.length ps) ["max.rpt";"min.rpt"])
       [slow;fast;"nom_typ_1p20V_25C"];
     Printf.printf "Full original native paths: %d\n" !count);
     test "optional original coarse collector and wire validation" (fun () ->
       let root=Filename.dirname (Filename.dirname (Filename.dirname (Filename.dirname dir))) |> Unix.realpath in
       let refs=ref [] in
       let read path format =
         require (Filename.is_relative path && not (List.mem ".." (String.split_on_char '/' path)));
         let canonical=Unix.realpath (Filename.concat root path) in
         require (String.starts_with ~prefix:(root^"/") canonical);
         let raw=read_file canonical in
         let ref_=reference path raw format in refs:=ref_::!refs;raw,ref_ in
       let exists p=Sys.file_exists (Filename.concat root p) in
       let context=Yojson.Safe.from_string (read_file (root^"/run.json")) in
       let manifest=Yojson.Safe.from_string (read_file (root^"/project/manifest.json")) in
       let _,final_netlist=read (flow^"/final/nl/tt_um_program_memory.nl.v") "verilog_gate_netlist" in
       let result=ok (R.collect ~read ~exists ~flow ~context ~manifest ~resources:[resource] ~final_netlist) in
       equal result.diagnostics [];
       let l=links result in
       ignore (ok (R.validate_links ~references:!refs ~resource ~timing_links:l.timing_links ~electrical_links:l.electrical_links));
       require (paths result<>[]);
       Printf.printf "Original resource-linked paths: %d; electrical points: %d\n"
         (List.length (paths result)) (List.length (xs (get l.electrical_links "points")))));
  Printf.printf "%d tests, %d failures\n" !tests (List.length !failures);
  if !failures<>[] then exit 1
