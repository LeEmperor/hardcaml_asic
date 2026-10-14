open Hardcaml_asic_execution
let () =
  let directory=ref None and json=ref false in
  try
    Arg.parse ["--json",Arg.Set json,"JSON snapshot"] (fun p->match !directory with None->directory:=Some p | _->raise (Arg.Bad "one directory required")) "Historical finalization inspection";
    let dir=match !directory with Some x->x | None->invalid_arg "directory required" in
    let record=match Finalization_record.read dir with Ok x->x | Error x->invalid_arg x in
    if !json then print_endline (Identity_json.canonical (Finalization_record.to_json record))
    else print_string (Finalization_record.render ~directory:dir record)
  with e->Printf.eprintf "finalization-inspect: %s\n" (match e with Invalid_argument x | Failure x->x | _->Printexc.to_string e);exit 2
