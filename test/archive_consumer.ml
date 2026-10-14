open Hardcaml_asic_execution
let () = try
  let run_dir=Sys.argv.(2) in
  if Sys.argv.(1)="inspect" then (
    let i=Archive_service.inspect ~run_dir in
    let strings xs=`List (List.map (fun s -> `String s) xs) in
    print_string (Evidence_json.record_bytes (`Assoc [
      "members",strings (List.map (fun (s:Evidence_tar.source) -> s.name) i.reports);
      "omitted",strings i.omitted;"source",`String i.bundle_source;
      "input_members",strings ("bundle/manifest.json"::List.map (fun (s:Evidence_tar.source) -> "bundle/"^s.name) i.bundle_files)])))
  else (
    let count=ref 0 in
    let rename a b = incr count;
      if Sys.argv.(1)="rollback" && !count=2 then raise (Sys_error "injected second rename failure");
      Unix.rename a b in
    let runtime={Archive_encoding.gzip=Sys.argv.(5);scratch=Sys.argv.(6);timeout=30.} in
    let p=Archive_service.publish ~rename ~runtime ~run_dir ~output:Sys.argv.(3) ~force:(bool_of_string Sys.argv.(4)) () in
    print_string (Evidence_json.record_bytes p.record))
  with e -> prerr_endline (Printexc.to_string e);exit 2
