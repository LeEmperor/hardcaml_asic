open Hardcaml_asic_execution
let () =
  let directory=ref "" and json=ref false and kind=ref "standalone" in
  try
    Arg.parse ["--kind",Arg.Set_string kind,"standalone|coarse_run|execution";"--json",Arg.Set json,"Machine-readable evidence";
      "--verbose",Arg.Unit (fun () -> ()),"Diagnostics"]
      (fun p -> if !directory<>"" then invalid_arg "one audit directory required" else directory:=p)
      "Read-only timing intent inspection of standalone retained STA audit";
    if !directory="" then invalid_arg "audit directory required";
    let result=match !kind with
      | "standalone" -> Timing_intent_evidence.inspect ~directory:!directory ()
      | "coarse_run" -> Timing_intent_flow.inspect ~run_dir:!directory ()
      | "execution" -> Timing_intent_execution.inspect ~execution:!directory ()
      | _ -> invalid_arg "unsupported timing intent inspection kind" in
    match result with
    | Error e -> prerr_endline ("timing-intent-inspect: "^e);exit 2
    | Ok j ->
      if !json then print_endline (Yojson.Safe.to_string j)
      else if !kind="coarse_run" || !kind="execution" then (
        let field k=match j with `Assoc xs -> (match List.assoc_opt k xs with Some (`String s) -> s | _ -> "") | _ -> "" in
        Printf.printf "%s synthesized-netlist STA evidence: %s\n" (if !kind="execution" then "Named execution" else "Ordinary coarse") (field "status");
        if field "reason"<>"" then print_endline (field "reason");
        print_endline "Exhaustive native path-effect coverage unavailable (not pass).")
      else print_endline "Standalone synthesized-netlist STA audit retained; native path-effect coverage unavailable (not pass).";
      exit 1
  with Invalid_argument e | Failure e -> prerr_endline e;exit 2
