open Hardcaml_asic_execution
module J = Identity_json
let checked = function Ok x -> x | Error s -> failwith s
let codec = function Ok x -> x | Error e -> failwith (J.error_message e)
let text = function J.String s -> s | _ -> failwith "expected string"
let number = function J.Float f -> f | J.Integer s -> float_of_string s | _ -> failwith "expected timeout number"
let reserve p =
  let p = Result_store.validate_output p in
  let fd = Unix.openfile p [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL] 0o600 in Unix.close fd; p
let main () =
  if Array.length Sys.argv = 2 && Sys.argv.(1) = "--help" then (
    print_endline "Usage: hardcaml-asic-experimental-segment-execute PREPARED.json\nExecute a checked stage plan over caller-prepared Docker workspace paths.\nFields: workspace, project, pdk_root, checkpoint_store, compatibility, binding,\nenvironment (complete KEY=VALUE list), timeout, initial_checkpoint (path or null),\nattempt_id, plan, summary_path, diagnostics_path. Output paths must be fresh.\nNo preparation or runtime probes are performed."; 0)
  else (
    if Array.length Sys.argv <> 2 then failwith "expected one prepared service configuration";
    let config = codec (Result_store.read_json Sys.argv.(1)) in
    let xs = codec (J.exact_object config ~fields:["workspace";"project";"pdk_root";"checkpoint_store";
      "compatibility";"binding";"environment";"timeout";"initial_checkpoint";"attempt_id";"plan";
      "summary_path";"diagnostics_path"]) in
    let get k = List.assoc k xs in
    let environment = match get "environment" with J.Array xs -> List.map text xs | _ -> failwith "expected environment array" in
    let initial_checkpoint = match get "initial_checkpoint" with J.Null -> None | j -> Some (text j) in
    let plan = checked (Execution_plan.of_json (get "plan")) in
    let service = match Segment_service.create ~binding:(checked (Execution_transport.of_json (get "binding")))
      ~workspace:(text (get "workspace")) ~project:(text (get "project")) ~pdk_root:(text (get "pdk_root"))
      ~checkpoint_store:(text (get "checkpoint_store")) ~compatibility:(get "compatibility") ~environment
      ~timeout:(number (get "timeout")) ?initial_checkpoint () with
      | Ok t -> t | Error e -> failwith e.message in
    let summary = reserve (text (get "summary_path")) in
    let diagnostics = reserve (text (get "diagnostics_path")) in
    let run_json () = J.null in
    let persist execution = Result_store.save_json summary (Runner.to_json ~run_json execution);
      Result_store.save_json diagnostics (Segment_service.diagnostics_json service execution) in
    let result = Segment_service.execute ~persist ~attempt_id:(text (get "attempt_id")) plan service in
    print_endline (J.canonical (Runner.to_json ~run_json result)); result.exit_code)
let () = let code = try main () with exn -> prerr_endline (Printexc.to_string exn); 2 in exit code
