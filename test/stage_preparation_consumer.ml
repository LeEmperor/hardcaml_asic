open Hardcaml_asic_execution
module J = Identity_json
let codec = function Ok x -> x | Error e -> failwith (J.error_message e)
let checked = function Ok x -> x | Error s -> failwith s
let get j k = match j with J.Object xs -> List.assoc k xs | _ -> failwith "object"
let text = function J.String x -> x | _ -> failwith "string"
let main () =
  let j = codec (Result_store.read_json Sys.argv.(1)) in
  let field k = text (get j k) in
  let plan = checked (Execution_plan.of_json (get j "plan")) in
  let environment = match get j "environment" with J.Array xs -> List.map text xs | _ -> failwith "environment" in
  let initial_checkpoint = match get j "checkpoint" with J.Null -> None | v -> Some (text v) in
  let optional k = match j with J.Object xs -> List.assoc_opt k xs | _ -> None in
  let methodology = Option.map (fun v ->
    let p = match Hardcaml_asic.Methodology_plan.of_string (text v) with Ok p -> p | Error e -> failwith (Core.Error.to_string_hum e) in
    Hardcaml_asic.Methodology_plan.plan_identity p,p) (optional "methodology") in
  match Stage_preparation.prepare ~bundle:(field "bundle") ~support_tools:(field "support_tools")
    ~pdk_root:(field "pdk_root") ~python:(field "python") ~docker:(field "docker") ~git:(field "git")
    ~resources:(field "resources") ~workspace:(field "workspace") ~checkpoint_store:(field "checkpoint_store")
    ~evidence_root:(field "evidence_root") ~environment ~timeout:2. ~probe_timeout:2. ?initial_checkpoint ?methodology ~plan () with
  | Error e -> prerr_endline e.cause.message; e.cause.exit_code
  | Ok t ->
    let mutate mutation =
      let path = field "workspace" ^ "/project/" ^ text (get mutation "path") in
      let oc = open_out_bin path in output_string oc (text (get mutation "bytes")); close_out oc in
    Option.iter mutate (optional "after_prepare");
    let result = match optional "after_invoke" with
      | None -> Stage_preparation.execute t plan
      | Some mutation ->
        let callbacks = Segment_service.callbacks t.service in
        let invoke action context =
          let outcome = callbacks.invoke action context in
          (match outcome with Ok _ -> mutate mutation | Error _ -> ()); outcome in
        let persist execution =
          Result_store.save_json t.summary_path (Runner.to_json ?methodology:t.methodology ~run_json:(fun () -> J.null) execution);
          Result_store.save_json t.diagnostics_path (Segment_service.diagnostics_json t.service execution) in
        Runner.execute ~persist ~attempt_id:t.attempt_id plan {callbacks with invoke} in
    print_endline (J.canonical (Runner.to_json ~run_json:(fun () -> J.null) result)); result.exit_code
let () = exit (try main () with exn -> prerr_endline (Printexc.to_string exn); 2)
