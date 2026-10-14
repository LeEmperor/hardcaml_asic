[@@@alert "-unsafe_multidomain"]
open Hardcaml_asic_execution
let () =
  let a = Sys.argv in
  if a.(1)="--runtime-observe" then (
    let signal=ref None in
    List.iter (fun n -> Sys.set_signal n (Sys.Signal_handle (fun n -> signal:=Some n))) [Sys.sigint;Sys.sigterm];
    let probe=Runtime_probe.create_cancellable ~cancel:(fun () -> !signal) ~directory:a.(2)
      ~environment:(Array.to_list (Unix.environment ())) ~timeout:5. in
    let policy=match Runtime_contract.policy_from_requested
      (match Result_store.read_json a.(6) with Ok (Identity_json.Object xs) -> List.assoc "requested_tools" xs | _ -> failwith "manifest") with
      | Ok p -> p | Error e -> failwith e in
    try ignore (Runtime_probe.observe probe ~python:a.(3) ~docker:a.(4) ~payload:a.(5) ~pdk_root:a.(7) policy);
      failwith "unexpected successful observation"
    with Runner.Callback_error e ->
      print_endline (String.concat "; " (e.message::e.secondary)); exit e.exit_code)
  else if a.(1)="--run" then (
    let r = Preflight_service.run ~bundle:a.(2) ~support_tools:a.(3) ~pdk_root:a.(4)
      ~python:a.(5) ~resources:a.(6) ~results_root:a.(7)
      ~environment:(Array.to_list (Unix.environment ())) ~native:(a.(8)="native")
      ?output:(if Array.length a>9 then Some a.(9) else None) () in
    Printf.eprintf "published: report=%b receipt=%b errors=%d status=%s\n"
      r.report_published r.receipt_published (List.length r.publication_errors)
      (Result_store.status_name r.status);
    print_endline (Identity_json.canonical r.report); exit r.exit_code)
  else
  let r = Preflight_service.run ~bundle:a.(1) ~support_tools:a.(2) ~pdk_root:a.(3)
    ~python:a.(4) ~resources:a.(5) ~results_root:a.(6)
    ~environment:(Array.to_list (Unix.environment ())) ~native:true ~allow_python_mismatch:true () in
  print_endline (Identity_json.canonical r.report)
