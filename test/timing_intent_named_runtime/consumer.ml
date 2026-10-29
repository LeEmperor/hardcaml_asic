open Hardcaml_asic_execution
module J=Identity_json
let checked = function Ok x -> x | Error s -> failwith s
let codec = function Ok x -> x | Error e -> failwith (J.error_message e)
let text = function J.String s -> s | _ -> failwith "string"
let get j k = match j with J.Object xs -> List.assoc k xs | _ -> failwith "object"
let () =
  try
    if Sys.argv.(1)="precheck" then (
      let paths=match codec (Result_store.read_json Sys.argv.(2)) with J.Array xs -> List.map text xs | _ -> failwith "source paths" in
      let external_roots=if Array.length Sys.argv>3 then match codec (Result_store.read_json Sys.argv.(3)) with J.Array xs -> List.map text xs | _ -> failwith "roots"
        else [] in
      Timing_intent_named_service.precheck_sources ~external_roots paths;print_endline "null";exit 0);
    if Sys.argv.(1)="audit" then (
      let j=checked (Timing_intent_evidence.inspect ~directory:Sys.argv.(2) ()) in
      print_endline (Yojson.Safe.to_string j);exit 0);
    if Sys.argv.(1)="inspect" then (
      let j=checked (Timing_intent_execution.inspect ~execution:Sys.argv.(2) ()) in
      print_endline (Yojson.Safe.to_string j);exit 0);
    let cfg=codec (Result_store.read_json Sys.argv.(1)) in
    let field k=text (get cfg k) in
    let methodology=match Hardcaml_asic.Methodology_plan.of_string (field "methodology") with
      | Ok p -> p | Error e -> failwith (Core.Error.to_string_hum e) in
    let plan=Execution_plan.of_stages (Execution_plan.Stage_plan.of_recipe (Hardcaml_asic.Methodology_plan.recipe methodology)) in
    let environment=Array.to_list (Unix.environment ()) in
    let started=Unix.gettimeofday () in
    let mode=field "mode" in
    let cancel () =
      if String.starts_with ~prefix:"root_" mode then (
        let oc=open_out_bin (Filename.dirname (field "workspace") ^ "/cancel-polled") in
        close_out oc);
      if (mode="cancel" || mode="cancel_cleanup" || mode="cancel_obstruction") && Sys.file_exists (field "workspace" ^ "/analysis-started") then Some Sys.sigint
      else if mode="cancel_initial" then Some Sys.sigterm
      else if mode="cancel_preflight" && Unix.gettimeofday ()-.started>0.05 then Some Sys.sigterm else None in
    match Stage_preparation.prepare ~bundle:(field "bundle") ~support_tools:(field "support_tools")
      ~pdk_root:(field "pdk_root") ~python:(field "python") ~docker:(field "docker") ~git:(field "git")
      ~resources:(field "resources") ~workspace:(field "workspace") ~checkpoint_store:(field "workspace" ^ "/checkpoints")
      ~evidence_root:(field "evidence_root") ~environment
      ~timeout:(if String.starts_with ~prefix:"alias_" mode || mode="pdk_aliases" then 30. else 0.7) ~probe_timeout:2. ~cancel
      ~methodology:((if mode="validation_failure" then String.make 64 '0' else Hardcaml_asic.Methodology_plan.plan_identity methodology),methodology) ~plan () with
    | Error e -> prerr_endline e.cause.message; exit e.cause.exit_code
    | Ok t ->
      let result=Stage_preparation.execute t plan in
      print_endline (J.canonical (Runner.to_json ?methodology:t.methodology ~run_json:(fun () -> J.null) result));
      exit result.exit_code
  with Runner.Callback_error e -> prerr_endline e.message;exit e.exit_code
     | exn -> prerr_endline (Printexc.to_string exn);exit 2
