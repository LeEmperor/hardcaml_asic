open Hardcaml_asic_execution
let read p=Evidence_json.value (Evidence_json.read p)
let binding ?(executable="/fixture/docker") () = Execution_transport.docker ~executable ~rootless:true
  ~server_version:"fixture" ~declared_ref:"fixture-image"
  ~image_id:Hardcaml_asic_flow_domain.Backends.Librelane.Mapping.tested_image_id ~repo_digests:[]
  ~os:"linux" ~architecture:"amd64" ~flags:Execution_transport.Isolated ()
let print j=print_endline (Yojson.Safe.to_string j)
let run () = match Sys.argv.(1) with
  | "seal" ->
    let j=Yojson.Safe.from_file Sys.argv.(2) in
    let fields=match j with `Assoc xs -> List.remove_assoc "identity" xs | _ -> assert false in
    print (`Assoc (("identity",`String (Identity_json.sha256_bytes (Yojson.Safe.to_string (`Assoc fields))))::fields))
  | "binding" -> print_endline (Identity_json.canonical (Execution_transport.to_json (binding ())))
  | "argv" ->
    let root=Sys.argv.(2) and analysis=Sys.argv.(3)="analysis" and physical=Sys.argv.(4)="full" in
    let d=match binding () with Docker d -> d | _ -> assert false in
    let m=read (root^"/project/manifest.json") in
    let tech=Timing_intent_linked.text (Timing_intent_linked.get (Timing_intent_linked.get m "target") "technology") in
    let pdk=Filename.dirname root^"/pdk" in
    let argv=Execution_transport.docker_command d ~project:(if analysis then root else root^"/project")
      ~pdk_root:pdk ~workdir:(root^"/project") ~name:("hardcaml-asic-execution-"^String.make 32 'a')
      ?pdk:(if analysis then None else Some tech) ~workers:6 ~uid:(Unix.getuid ()) ~gid:(Unix.getgid ()) () in
    let payload=if analysis then [root^"/timing-intent/timing_physical_runtime.py";root^"/timing-intent/request.json"] else
      [root^"/project/timing_physical_runtime.py";"implementation";"--pdk-root";pdk;"--pdk";tech;"--manual-pdk";
       "--run-tag";"asic";"--force-run-dir";"runs/asic"] @ (if physical then [] else ["--to";"Yosys.Synthesis"]) @
      ["--jobs";"6";"-c";"OPENROAD_THREADS=6";"-c";"STA_THREADS=1";"-c";"KLAYOUT_DRC_THREADS=6";"-c";"KLAYOUT_XOR_THREADS=6";"src/config.json"] in
    print (`List (List.map (fun s -> `String s) (argv@["-I";"-B"]@payload)))
  | "publish" -> Timing_intent_flow.publish ~run_dir:Sys.argv.(2) ~context:(read (Sys.argv.(2)^"/run.json")) ~succeeded:(Sys.argv.(3)="true") ()
  | "capture" ->
    let root=Sys.argv.(2) in
    let b=binding ~executable:Sys.argv.(3) () in
    let context=match Result_store.read_json (root^"/run.json") with Ok j -> j | Error e -> failwith (Identity_json.error_message e) in
    let calls=ref 0 in
    let verify_runtime () = incr calls;if Sys.argv.(6)="post_verify" && !calls>1 then Error "changed runtime identity" else Ok () in
    let cancel () = if Sys.argv.(6)="cancel" then Some Sys.sigint else None in
    (try Timing_intent_service.capture ~timeout:(float_of_string Sys.argv.(5)) ~run_dir:root ~context ~binding:b
      ~pdk_root:(Filename.dirname root^"/pdk") ~resources:Sys.argv.(4) ~environment:(Array.to_list (Unix.environment ()))
      ~cancel ~verify_runtime () with Runner.Callback_error e -> List.iter prerr_endline (e.message::e.secondary);exit e.exit_code)
  | "inspect" -> (match Timing_intent_flow.inspect ~run_dir:Sys.argv.(2) () with Ok j -> print j | Error e -> failwith e)
  | "collect" -> print (Collect_service.to_json (Collect_service.collect Sys.argv.(2)))
  | "report" -> print (Report_service.run Sys.argv.(2)).results
  | "metrics" -> let j=read Sys.argv.(2) in
    let get=Timing_intent_linked.get and text=Timing_intent_linked.text and list=Timing_intent_linked.list in
    print (Timing_physical_metrics.interpret ~corner:(text (get j "corner")) ~log:(text (get j "log"))
      ~output_state:(get j "output") ~libraries:(List.map text (list (get j "libraries"))))
  | _ -> invalid_arg "test operation"
let () = try run () with Invalid_argument e | Failure e -> prerr_endline e;exit 2
