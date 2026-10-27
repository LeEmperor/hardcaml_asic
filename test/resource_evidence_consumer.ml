open Hardcaml_asic_execution
let () =
  let operation=Sys.argv.(1) and root=Sys.argv.(2) in
  let result=match operation with
    | "collect" -> Collect_service.to_json (Collect_service.collect root)
    | "collect-context" -> let context=Evidence_json.value (Evidence_json.read (Filename.concat root "context.json")) in
      Collect_service.to_json (Collect_service.collect ~context root)
    | "report" -> let r=Report_service.run root in
      `Assoc ["accepted",`Bool (Report_service.accepted r.verdict);"results",r.results;
        "problems",`List (List.map (fun s -> `String s) r.verdict.problems)]
    | "archive" -> let i=Archive_service.inspect ~run_dir:root in
      `List (List.map (fun (s:Evidence_tar.source) -> `String s.name) i.reports)
    | "validate" -> let j=Evidence_json.value (Evidence_json.read root) in
      (match Resource_evidence.validate j with Ok _ -> `String "valid" | Error s -> `String s)
    | ("verify"|"verify-context") -> let results=Evidence_json.value (Evidence_json.read (Filename.concat root "results.json")) in
      let evidence=match results with `Assoc xs -> List.assoc "resource_evidence" xs | _ -> invalid_arg "results object" in
      let context=if operation="verify-context" then Some (Evidence_json.value (Evidence_json.read (Filename.concat root "context.json"))) else None in
      (match Resource_evidence.verify_sources ?context ~run_dir:root evidence with Ok () -> `String "valid" | Error s -> `String s)
    | "reconcile" -> let expected=List.map (fun name -> `Assoc ["resource_id",`String name;"module",`String "M";
        "instances",`List [`Assoc ["instance",`String name;"module",`String "M"]]]) ["a";"b"] in
      Resource_evidence.reconcile ~expected ~instances:(Some ["a","M";"b","M"])
        ~known_standard_cells:[] ~reason:None
    | _ -> invalid_arg "operation" in
  print_endline (Yojson.Safe.to_string result)
