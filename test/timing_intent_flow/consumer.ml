open Hardcaml_asic_execution
let read p=Evidence_json.value (Evidence_json.read p)
let run () =
  match Sys.argv.(1) with
  | "seal" ->
      let j=Yojson.Safe.from_file Sys.argv.(2) in
      let fields=match j with `Assoc xs -> List.remove_assoc "identity" xs | _ -> assert false in
      let identity=Identity_json.sha256_bytes (Yojson.Safe.to_string (`Assoc fields)) in
      print_endline (Yojson.Safe.to_string (`Assoc (("identity",`String identity)::fields)))
  | "binding" -> let b=Execution_transport.docker ~executable:"/fixture/docker" ~rootless:true
      ~server_version:"fixture" ~declared_ref:"fixture-image"
      ~image_id:Hardcaml_asic_flow_domain.Backends.Librelane.Mapping.tested_image_id ~repo_digests:[]
      ~os:"linux" ~architecture:"amd64" ~flags:Execution_transport.Isolated () in
      print_endline (Identity_json.canonical (Execution_transport.to_json b))
  | "argv" ->
      let root=Sys.argv.(2) and analysis=Sys.argv.(3)="analysis" in
      let binding=Execution_transport.docker ~executable:"/fixture/docker" ~rootless:true
        ~server_version:"fixture" ~declared_ref:"fixture-image"
        ~image_id:Hardcaml_asic_flow_domain.Backends.Librelane.Mapping.tested_image_id ~repo_digests:[]
        ~os:"linux" ~architecture:"amd64" ~flags:Execution_transport.Isolated () in
      let d=match binding with Execution_transport.Docker d -> d | _ -> assert false in
      let m=Yojson.Safe.from_file (root^"/project/manifest.json") in
      let get j k=match j with `Assoc xs -> List.assoc k xs | _ -> assert false in
      let tech=match get (get m "target") "technology" with `String s -> s | _ -> assert false in
      let pdk=Filename.dirname root^"/pdk" in
      let argv=Execution_transport.docker_command d ~project:(if analysis then root else root^"/project")
        ~pdk_root:pdk ~workdir:(root^"/project") ~name:("hardcaml-asic-execution-"^String.make 32 'a')
        ?pdk:(if analysis then None else Some tech) ~workers:6 ~uid:(Unix.getuid ()) ~gid:(Unix.getgid ()) () in
      let payload=if analysis then [root^"/timing-intent/timing_intent_runtime.py";root^"/timing-intent/request.json"]
        else ["-m";"librelane";"--pdk-root";pdk;"--pdk";tech;"--manual-pdk";"--run-tag";"asic";
          "--force-run-dir";"runs/asic";"--to";"Yosys.Synthesis";"--jobs";"6";"-c";"OPENROAD_THREADS=6";
          "-c";"STA_THREADS=1";"-c";"KLAYOUT_DRC_THREADS=6";"-c";"KLAYOUT_XOR_THREADS=6";"src/config.json"] in
      print_endline (Yojson.Safe.to_string (`List (List.map (fun s -> `String s) (argv@["-I";"-B"]@payload))))
  | "capture" ->
      let root=Sys.argv.(2) in
      let context=match Result_store.read_json (root^"/run.json") with Ok j -> j | Error e -> failwith (Identity_json.error_message e) in
      let binding=Execution_transport.docker ~executable:Sys.argv.(3) ~rootless:true
        ~server_version:"fixture" ~declared_ref:"fixture-image"
        ~image_id:Hardcaml_asic_flow_domain.Backends.Librelane.Mapping.tested_image_id ~repo_digests:[]
        ~os:"linux" ~architecture:"amd64" ~flags:Execution_transport.Isolated () in
      let context=match context with Identity_json.Object xs ->
        (match Identity_json.object_ (("execution_binding",Execution_transport.to_json binding)::List.remove_assoc "execution_binding" xs) with Ok j -> j | Error _ -> assert false)
        | _ -> assert false in
      Result_store.save_json (root^"/run.json") context;
      let cancel () = if Sys.argv.(6)="cancel" then Some Sys.sigint else None in
      let verifications=ref 0 in
      let verify_runtime () = incr verifications;
        if Sys.argv.(6)="post_verify" && !verifications>1 then Error "fixture post-runtime identity mismatch" else Ok () in
      (try Timing_intent_service.capture ~timeout:(float_of_string Sys.argv.(5)) ~run_dir:root ~context ~binding
        ~pdk_root:(Filename.dirname root^"/pdk") ~resources:Sys.argv.(4)
        ~environment:(Array.to_list (Unix.environment ())) ~cancel ~verify_runtime ()
       with Runner.Callback_error e -> prerr_endline e.message;exit e.exit_code)
  | "publish" -> Timing_intent_flow.publish ~run_dir:Sys.argv.(2)
      ~context:(read (Sys.argv.(2)^"/run.json")) ~succeeded:(Sys.argv.(3)="true") ()
  | "inspect" -> (match Timing_intent_flow.inspect ~run_dir:Sys.argv.(2) () with
      | Ok j -> print_endline (Yojson.Safe.to_string j)
      | Error e -> prerr_endline e;exit 2)
  | "collect" -> print_endline (Yojson.Safe.to_string (Collect_service.to_json (Collect_service.collect Sys.argv.(2))))
  | "report" -> let r=Report_service.run Sys.argv.(2) in print_endline (Yojson.Safe.to_string r.results)
  | "archive" -> let i=Archive_service.inspect ~run_dir:Sys.argv.(2) in
      print_endline (Yojson.Safe.to_string (`List (List.map (fun (s:Evidence_tar.source) -> `String s.name) i.reports)))
  | _ -> invalid_arg "test operation"
let () = try run () with Invalid_argument e | Failure e -> prerr_endline e;exit 2
