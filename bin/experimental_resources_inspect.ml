open Hardcaml_asic_execution
let () =
  let run=ref "" and json=ref false in
  Arg.parse ["--run-dir",Arg.Set_string run,"Run directory";"--json",Arg.Set json,"JSON output";
    "--verbose",Arg.Unit (fun () -> ()),"Diagnostics"] (fun p -> run:=p) "resources-inspect RUN_DIR [--json]";
  match Resource_evidence.inspect ~run_dir:!run with
  | Error e -> prerr_endline ("resources-inspect: "^e);exit 2
  | Ok evidence ->
    let problems=Resource_evidence.problems evidence in
    if !json then print_endline (Yojson.Safe.pretty_to_string evidence)
    else (print_endline "Resource realization (read-only retained evidence)";
      let get j k=match j with `Assoc xs -> Option.value (List.assoc_opt k xs) ~default:`Null | _ -> `Null in
      let text=function `String s -> s | `Null -> "unavailable" | v -> Yojson.Safe.to_string v in
      (match get evidence "observations" with `List observations -> List.iter (fun o ->
        Printf.printf "%s: %s\n" (text (get o "stage")) (text (get o "status"));
        (match get o "resources" with `List rows -> List.iter (fun row -> Printf.printf "  %s: %s (%s)\n"
          (text (get row "resource_id")) (text (get row "status")) (text (get row "reason"))) rows | _ -> ());
        match get o "measurements" with `Assoc xs -> List.iter (fun (name,m) -> Printf.printf "  %s: %s %s%s\n"
          name (text (get m "value")) (text (get m "unit"))
          (if get m "value"=`Null then " — "^text (get m "unavailable_reason") else "")) xs | _ -> ()) observations | _ -> ());
      if problems=[] then (
        let required=match get evidence "check_outcomes" with `List xs -> List.exists (fun c -> get c "required"=`Bool true) xs | _ -> false in
        print_endline (if required then "Required resource checks passed (see JSON for attribution/coverage limitations)"
          else "No required macro retention checks; resource attribution and observation availability remain explicit"))
      else List.iter print_endline problems);
    exit (if problems=[] then 0 else 1)
