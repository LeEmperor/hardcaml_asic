open Hardcaml_asic_execution
let () =
  let o = Coarse_run_service.run ~bundle:Sys.argv.(1) ~support_tools:Sys.argv.(2)
    ~pdk_root:Sys.argv.(3) ~python:Sys.argv.(4) ~resources:Sys.argv.(5)
    ~runs:Sys.argv.(6) ~environment:(Array.to_list (Unix.environment ()))
    ~plan:(Execution_plan.Coarse.resolve Synthesis) ~native:true () in
  print_string (Result_store.record_bytes (Run_record.outcome_json o)); exit o.exit_code
