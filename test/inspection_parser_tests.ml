open Hardcaml_asic_execution
let () =
  let raw="header\nStartpoint: a (input)\nEndpoint: b (output)\nPath Group: clk\nPath Type: max\n 1.25 data arrival time\n 2.0 data required time\n -1.25 data arrival time\n 0.75 slack (MET)\n" in
  let paths,ds=Inspection_service.timing_records raw in
  assert (ds=[]);
  (match paths with [(2,9,fields)] ->
    assert (List.assoc "arrival" fields="1.25");
    assert (List.assoc "slack" fields="0.75");
    assert (List.assoc "status" fields="met") | _ -> assert false);
  let paths,ds=Inspection_service.timing_records "Startpoint: truncated\nEndpoint: missing slack\n" in
  assert (paths=[] && ds<>[]);
  let paths,ds=Inspection_service.timing_records (raw^"Startpoint: malformed\n NaN slack (VIOLATED)\n") in
  assert (List.length paths=1 && ds<>[]);
  let entries,ds=Inspection_service.native_entries "{\n\"design__instance__area\": 1,\n\"design__instance__area\": 2,\n\"route__wirelength\": Infinity\n}\n" in
  assert (List.length entries=3 && ds<>[]);
  assert (List.length ds=1 && List.exists (String.starts_with ~prefix:"native repeated key preserved") ds);
  (* Evidence_json deliberately represents every integer as Intlit. Do not
     narrow the parser's arbitrary-precision tokens to machine integers. *)
  (match entries with
   | [(2,"design__instance__area",`Intlit "1");
      (3,"design__instance__area",`Intlit "2");
      (4,"route__wirelength",`Float f)] -> assert (f=infinity)
   | _ -> assert false);
  let large="1234567890123456789012345678901234567890" in
  let entries,ds=Inspection_service.native_entries ("{\n\"design__instance__count\": "^large^"\n}\n") in
  assert (ds=[]);
  (match entries with [(2,"design__instance__count",`Intlit s)] -> assert (s=large) | _ -> assert false);
  let entries,ds=Inspection_service.native_entries "{\n\"nested\": {\"not\": \"flat\"}\n}\n" in
  assert (entries=[] && ds<>[]);
  let entries,ds=Inspection_service.native_entries "{\n\"bad\":\n}" in
  assert (entries=[] && ds<>[]);
  let entries,ds=Inspection_service.native_entries "{\n\"missing_comma\": 1\n\"other\": 2\n}" in
  assert (entries=[] && ds<>[]);
  let declarations,ds=Inspection_service.liberty_time_units
    "library (fixture) {\n  // time_unit : \"1ps\";\n  /* time_unit : \"1us\";\n     still a comment */\n  time_unit                      : \"1ns\"; // actual retained form\n}\000" in
  assert (ds=[]);
  (match declarations with [(5,"1ns",line)] ->
    assert (String.contains line '"');
    assert (String.ends_with ~suffix:"actual retained form" line)
   | _ -> assert false);
  let declarations,ds=Inspection_service.liberty_time_units
    "comment : \"time_unit : \\\"1ps\\\";\";\ntime_unit : \"1ns\";\n" in
  assert (ds=[]);
  (match declarations with [(2,"1ns",_)] -> () | _ -> assert false);
  let declarations,ds=Inspection_service.liberty_time_units "time_unit : 1ns;\n" in
  assert (declarations=[] && ds<>[]);
  let declarations,ds=Inspection_service.liberty_time_units "time_unit : \"1ns\"\n" in
  assert (declarations=[] && ds<>[]);
  let declarations,ds=Inspection_service.liberty_time_units "time_unit : \"1ns\";\ntime_unit : \"1ps\";\n" in
  assert (ds=[] && List.map (fun (_,unit,_) -> unit) declarations=["1ns";"1ps"]);
  (* Persistent B after validation of A must fail even though B is stable and
     its own final hash would be internally consistent. This is the production
     segment decoder, with the captured manifest's expected hash injected. *)
  let a="{\"run_dir\":\"/validated/A\",\"returned_steps\":[\"OpenROAD.STAPostPNR\"]}" in
  let b="{\"run_dir\":\"/mutated/B\",\"returned_steps\":[\"OpenROAD.STAPostPNR-2\"]}" in
  let expected_sha256=Identity_json.sha256_bytes a in
  assert (Result.is_ok (Stage_report_service.decode_segment_bytes ~expected_sha256 a));
  assert (Result.is_error (Stage_report_service.decode_segment_bytes ~expected_sha256 b));
  assert (Result.is_error (Stage_report_service.decode_segment_bytes ~expected_sha256 (a^"\n")));
  List.iter (fun (id,expected) -> assert (Inspection_service.registered_class id=expected))
    ["OpenROAD.STAPostPNR-1","OpenROAD.STAPostPNR";
     "OpenROAD.Floorplan-2","OpenROAD.Floorplan";
     "OpenROAD.DetailedPlacement-3","OpenROAD.DetailedPlacement";
     "OpenROAD.CheckAntennas-1","OpenROAD.CheckAntennas";
     "OpenROAD.STAPostPNR-","OpenROAD.STAPostPNR-"];
  let rows,ds=Inspection_service.clock_records
    "0.9 skew\nClock: a\nSources: root_a\nGenerated: no\nClock: b\nSources: root_b\nGenerated: yes\nMaster Clock: a\nDivide By: 2\nClock a\nrise -> rise\n0.1 0.2 latency\nClock b\n9 9 latency\nfall -> fall\n0.3 0.4 latency\nClock a\n9 skew\n" in
  assert (List.length ds=4);
  let quantities=List.filter_map (fun (_,fields) -> match List.assoc_opt "raw_value" fields with
    | None -> None | Some value -> Some (value,fields)) rows in
  assert (List.length quantities=4);
  List.iter (fun (value,fields) ->
    assert (value<>"9");
    if value="0.1" || value="0.2" then (
      assert (List.assoc "clock" fields="a");
      assert (List.assoc "transition" fields="rise -> rise");
      assert (List.assoc "sources" fields="root_a");
      assert (List.assoc "generated" fields="no");
      assert (not (List.mem_assoc "master_clock" fields)))
    else (
      assert (List.assoc "clock" fields="b");
      assert (List.assoc "transition" fields="fall -> fall");
      assert (List.assoc "sources" fields="root_b");
      assert (List.assoc "generated" fields="yes");
      assert (List.assoc "master_clock" fields="a");
      assert (List.assoc "divide_by" fields="2"))) quantities;
  let rows,ds=Inspection_service.clock_records
    "Clock a\nrise -> rise\n        min     max\n    0.1         network latency a/CLK\n            0.2 network latency b/CLK\nClock b\nfall -> fall\n0.9 network latency unknown/CLK\n" in
  assert (List.length ds=1);
  assert (List.map (fun (_,fields) -> List.assoc "quantity" fields) rows=["network_latency_min";"network_latency_max"]);
  assert (List.map (fun (_,fields) -> List.assoc "endpoint" fields) rows=["a/CLK";"b/CLK"]);
  let rows,ds=Inspection_service.clock_records "Clock: derived\nGenerated: yes\nSource Pin: root/Q\nClock derived\nrise -> rise\n0.1 skew\n" in
  assert (ds=[]);
  let quantity=List.find (fun (_,fields) -> List.mem_assoc "raw_value" fields) rows |> snd in
  assert (List.assoc "header:Source Pin" quantity="root/Q");
  assert (not (List.mem_assoc "master_clock" quantity));
  let rows,ds=Inspection_service.timing_records ~max_records:1 (raw^raw^"Startpoint: bad tail\n") in
  assert (List.length rows=1 && List.exists (String.starts_with ~prefix:"timing record bound exceeded") ds);
  assert (not (List.exists (String.starts_with ~prefix:"malformed") ds));
  let rows,ds=Inspection_service.native_entries ~max_entries:1 "{\n\"a\": 1,\n\"a\": 2\n}\n" in
  assert (List.length rows=1 && List.exists (String.starts_with ~prefix:"native entry bound exceeded") ds);
  let rows,ds=Inspection_service.clock_records ~max_records:1 "Clock a\nrise -> rise\n0.1 0.2 latency\nClock b\n" in
  assert (List.length rows=1 && List.exists (String.starts_with ~prefix:"clock record bound exceeded") ds);
  let rows,ds=Inspection_service.timing_records (String.make 262145 '\n') in
  assert (rows=[] && List.exists (String.starts_with ~prefix:"timing source line bound exceeded") ds);
  let mib=1024*1024 in
  assert (Inspection_service.admit_input ~used_bytes:0 ~source_count:0 ~bytes:(32*mib)=Ok (32*mib,1));
  assert (Inspection_service.admit_input ~used_bytes:(32*mib) ~source_count:1 ~bytes:(32*mib)=Ok (64*mib,2));
  assert (Result.is_error (Inspection_service.admit_input ~used_bytes:(64*mib) ~source_count:2 ~bytes:1));
  assert (Result.is_error (Inspection_service.admit_input ~used_bytes:0 ~source_count:0 ~bytes:(32*mib+1)));
  assert (Inspection_service.admit_input ~used_bytes:0 ~source_count:511 ~bytes:0=Ok (0,512));
  assert (Result.is_error (Inspection_service.admit_input ~used_bytes:0 ~source_count:512 ~bytes:0))
