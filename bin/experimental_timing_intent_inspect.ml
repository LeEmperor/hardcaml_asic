open Hardcaml_asic_execution
let () =
  let directory=ref "" and json=ref false in
  try
    Arg.parse ["--json",Arg.Set json,"Machine-readable evidence";
      "--verbose",Arg.Unit (fun () -> ()),"Diagnostics"]
      (fun p -> if !directory<>"" then invalid_arg "one audit directory required" else directory:=p)
      "Read-only timing intent inspection of standalone retained STA audit";
    if !directory="" then invalid_arg "audit directory required";
    match Timing_intent_evidence.inspect ~directory:!directory () with
    | Error e -> prerr_endline ("timing-intent-inspect: "^e);exit 2
    | Ok j ->
      if !json then print_endline (Yojson.Safe.to_string j)
      else print_endline "Standalone synthesized-netlist STA audit retained; native path-effect coverage unavailable (not pass).";
      exit 1
  with Invalid_argument e | Failure e -> prerr_endline e;exit 2
