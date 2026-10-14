open Hardcaml_asic_execution
let () =
  try
    let run=ref None and output=ref None and list=ref false and force=ref false in
    let json=ref false and quiet=ref false and verbose=ref false in
    let gzip=ref "/usr/bin/gzip" and timeout=ref 120. in
    let rec parse = function
      | [] -> ()
      | "--run-dir"::s::xs -> run:=Some s;parse xs
      | "--output"::s::xs -> output:=Some s;parse xs
      | "--gzip"::s::xs -> gzip:=s;parse xs
      | "--timeout"::s::xs -> timeout:=float_of_string s;parse xs
      | "--list"::xs -> list:=true;parse xs
      | "--force"::xs -> force:=true;parse xs
      | "--json"::xs -> json:=true;parse xs
      | "--quiet"::xs -> quiet:=true;parse xs
      | "--verbose"::xs -> verbose:=true;parse xs
      | "--help"::_ -> print_endline "archive --run-dir RUN [--list | --output DIR] [--force] [--json] [--quiet] [--verbose]";exit 0
      | s::_ -> invalid_arg ("unknown archive argument: "^s) in
    parse (List.tl (Array.to_list Sys.argv));
    let run_dir=match !run with Some s -> s | None -> invalid_arg "--run-dir is required" in
    if !json && !list then invalid_arg "--json with archive --list is unsupported; use human --list";
    if !force && !output=None then invalid_arg "--force requires an explicit archive destination";
    if !list then (
      let i=Archive_service.inspect ~run_dir in
      List.iter (fun (s:Evidence_tar.source) -> print_endline s.name) i.reports;
      print_endline "input-bundle: bundle/manifest.json";
      List.iter (fun (s:Evidence_tar.source) -> print_endline ("input-bundle: bundle/"^s.name)) i.bundle_files;
      List.iter (fun s -> prerr_endline ("absent: "^s)) i.omitted;
      Printf.eprintf "\n%d report files, %.1f MB uncompressed; %d complete input-bundle files from %s\n"
        (List.length i.reports) (Int64.to_float i.report_bytes/.1e6) (List.length i.bundle_files+1) i.bundle_source)
    else (
      let output=match !output with Some s -> s | None -> invalid_arg "--output is required unless --list is given" in
      let scratch=Filename.get_temp_dir_name () |> Unix.realpath in
      let runtime={Archive_encoding.gzip= !gzip;scratch;timeout= !timeout} in
      let p=Archive_service.publish ~runtime ~run_dir ~output ~force:!force () in
      List.iter (fun s -> prerr_endline ("archive: absent, not included: "^s)) p.omitted;
      if not !quiet then (
        if !json then Printf.printf "{\"archive\": %s, \"reports\": %s}\n"
          (String.trim (Evidence_json.record_bytes (`String p.output))) (String.trim (Evidence_json.record_bytes (`String p.reports)))
        else (print_endline ("archive: created "^p.output);print_endline ("reports: "^p.reports)));
      if !verbose then Printf.eprintf "archive: reports %s; omitted %d files\n" p.reports (List.length p.omitted))
  with
  | Invalid_argument s | Failure s | Sys_error s | Yojson.Json_error s -> prerr_endline ("hardcaml-asic-flow: "^s);exit 2
  | Unix.Unix_error (e,fn,p) -> prerr_endline ("hardcaml-asic-flow: "^fn^" "^p^": "^Unix.error_message e);exit 2
  | Archive_encoding.Gzip_failed (_,s) -> prerr_endline ("hardcaml-asic-flow: archive gzip failed: "^s);exit 2
