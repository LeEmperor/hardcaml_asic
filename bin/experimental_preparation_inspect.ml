open Hardcaml_asic_execution
let () =
  let directory=ref "" and current=ref None and json=ref false in
  try
    Arg.parse ["--current-identity",Arg.String (fun s->current:=Some s),"current preparation identity";
      "--json",Arg.Set json,"machine-readable historical inspection";
      "--verbose",Arg.Unit (fun ()->()),"diagnostics"]
      (fun s->if !directory<>"" then raise (Arg.Bad "one attempt directory required");directory:=s)
      "preparation-inspect ATTEMPT [--current-identity ID] [--json]";
    if !directory="" then invalid_arg "attempt directory required";
    let result=match Preparation_inspection.inspect ?current_identity:!current !directory with
      | Ok x->x | Error e->invalid_arg e in
    if !json then print_endline (Identity_json.canonical (Preparation_inspection.to_json result))
    else print_string (Preparation_inspection.render result);
    flush stdout
  with exn -> Printf.eprintf "preparation-inspect: %s\n" (Printexc.to_string exn);exit 2
