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
  match Stage_preparation.prepare ~bundle:(field "bundle") ~support_tools:(field "support_tools")
    ~pdk_root:(field "pdk_root") ~python:(field "python") ~docker:(field "docker") ~git:(field "git")
    ~resources:(field "resources") ~workspace:(field "workspace") ~checkpoint_store:(field "checkpoint_store")
    ~evidence_root:(field "evidence_root") ~environment ~timeout:2. ~probe_timeout:2. ?initial_checkpoint ~plan () with
  | Error e -> prerr_endline e.cause.message; e.cause.exit_code
  | Ok t -> let result = Stage_preparation.execute t plan in
    print_endline (J.canonical (Runner.to_json ~run_json:(fun () -> J.null) result)); result.exit_code
let () = exit (try main () with exn -> prerr_endline (Printexc.to_string exn); 2)
