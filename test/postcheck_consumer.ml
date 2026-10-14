open Hardcaml_asic_execution
let () =
  try
    let o=Postcheck_service.run ~run_dir:Sys.argv.(1) ~support_tools:Sys.argv.(2) ~pdk_root:Sys.argv.(3)
      ~precheck_python:Sys.argv.(4) ~testbench:Sys.argv.(5) ~testbench_top:"memory_tb"
      ~context:(Evidence_json.value (Evidence_json.read Sys.argv.(6))) ~replay_trace:Sys.argv.(7)
      ~environment:(Array.to_list (Unix.environment ())) () in
    print_string (Result_store.record_bytes (Postcheck_service.outcome_json o)); exit o.exit_code
  with e -> prerr_endline (Printexc.to_string e); exit 2
