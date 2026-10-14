open Hardcaml_asic_execution
module J=Identity_json
let checked=function Ok x->x | Error s->invalid_arg s
let codec=function Ok x->x | Error e->invalid_arg (J.error_message e)
let s x=codec (J.string x)
let obj x=codec (J.object_ x)
let () =
  let values=Hashtbl.create 12 and json=ref false and accept=ref false and public=ref false and verbose=ref false and inspect=ref false in
  let specs=List.map (fun name->"--"^name,Arg.String (fun x->Hashtbl.replace values name x),name)
    ["execution";"store";"directory";"support-tools";"precheck-python";"testbench";"testbench-top";"replay-trace"] @
    ["--json",Arg.Set json,"JSON";"--accept",Arg.Set accept,"external postcheck and acceptance";
     "--inspect",Arg.Set inspect,"read historical receipt";"--public-cli4",Arg.Set public,"public presentation";"--verbose",Arg.Set verbose,"diagnostics"] in
  let error exn=match exn with Failure x | Invalid_argument x->x | _->Printexc.to_string exn in
  try
    Arg.parse specs (fun _->raise (Arg.Bad "unexpected argument")) "Bounded finalization / historical inspection";
    let v=Hashtbl.find values in
    let directory,record=if !inspect then let dir=v "directory" in dir,checked (Finalization_record.read dir)
      else let o=Finalization_service.run ~execution:(v "execution") ~store:(v "store") ~accept:!accept
        ~environment:(Array.to_list (Unix.environment ()))
        ?support_tools:(Hashtbl.find_opt values "support-tools") ?precheck_python:(Hashtbl.find_opt values "precheck-python")
        ?testbench:(Hashtbl.find_opt values "testbench") ?testbench_top:(Hashtbl.find_opt values "testbench-top")
        ?replay_trace:(Hashtbl.find_opt values "replay-trace")
        ~allocated:(fun directory attempt-> if !public then (
          if !json then print_endline (J.canonical (obj ["contract",s Finalization_record.contract;"schema_version",codec (J.integer "1");
            "event",s "allocated";"attempt",s directory;"attempt_id",s attempt]))
          else Printf.printf "%-22s allocated\n%-22s %s\n%-22s %s\nRequested operation has not completed; this is an allocation receipt.\n"
            "allocation" "attempt" directory "attempt id" attempt;
          flush stdout)) () in o.directory,o.record in
    let raw=Finalization_record.to_json record in
    if !json || not !public then (
      let raw=if !inspect then raw else match raw with J.Object xs->obj (("attempt",s directory)::xs) | _->assert false in
      print_endline (J.canonical raw))
    else print_string (Finalization_record.render ~directory record);
    if not !inspect then (
      let get k=match raw with J.Object xs->Option.value (List.assoc_opt k xs) ~default:J.null | _->J.null in
      if get "error"<>J.null then Printf.eprintf "finalize: %s\n" (match get "error" with J.String x->x | j->J.canonical j)
      else if record.exit_code<>Some Z.zero then Printf.eprintf "finalize: %s (exit %s); acceptance %s\n"
        (match get "status" with J.String x->x | _->"failed") (Z.to_string (Option.value record.exit_code ~default:Z.one))
        (match get "acceptance" with J.String x->x | _->"not_evaluated"));
    ignore !verbose;
    exit (if !inspect then 0 else Z.to_int (Option.value record.exit_code ~default:Z.one))
  with exn->
    let message=error exn in Printf.eprintf "%s: %s\n" (if !inspect then "finalization-inspect" else "finalize") message;
    if !json then print_endline (J.canonical (obj ["contract",s Finalization_record.contract;"schema_version",codec (J.integer "1");"error",s message]));
    if !public && not !json then (
      let path=Option.value (Hashtbl.find_opt values (if !inspect then "directory" else "execution")) ~default:"not recorded" in
      Printf.printf "%-22s %s\n%-22s failed\n%-22s %s\n\nNo successful inspection or readiness conclusion is available.\n"
        "finalization" path "inspection" "error" message);
    exit 2
