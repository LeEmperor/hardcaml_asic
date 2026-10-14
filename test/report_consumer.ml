open Hardcaml_asic_execution
let () =
  try
    let request=match Evidence_json.parse (read_line ()) with Ok d -> Evidence_json.value d | Error s -> invalid_arg s in
    let get k=match request with `Assoc xs -> Option.value (List.assoc_opt k xs) ~default:`Null | _ -> assert false in
    let context=get "context" and results=get "results" in
    let verdict=Report_service.evaluate ~context results in
    let scope=match verdict.scope with Synthesis -> "synthesis" | Full -> "full" | Invalid -> "invalid" in
    let human=match get "run_dir" with `String run_dir ->
      Report_service.render ~run_dir ~context ~results ~source:"fixture" verdict | _ -> "" in
    print_string (Evidence_json.record_bytes (`Assoc ["scope",`String scope;
      "accepted",`Bool (Report_service.accepted verdict); "exit_code",`Int (Report_service.exit_code verdict);
      "problems",`List (List.map (fun s -> `String s) verdict.problems); "human",`String human]))
  with Invalid_argument s | Sys_error s -> prerr_endline s; exit 2
