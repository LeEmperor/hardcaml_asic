open Hardcaml_asic_execution
let () = try
  match Array.to_list Sys.argv with
  | [_;"run";execution;store] ->
    let o=Finalization_service.run ~execution ~store ~environment:(Array.to_list (Unix.environment ())) () in
    let raw=Finalization_record.to_json o.record in
    let fields=match raw with Identity_json.Object xs->xs | _->assert false in
    let path=match Identity_json.string o.directory with Ok j->j | Error _->assert false in
    let j=match Identity_json.object_ (("attempt",path)::fields) with Ok j->j | Error _->assert false in
    print_endline (Identity_json.canonical j)
  | [_;"select";p] -> ignore (Finalization_service.selected p); print_endline "selected"
  | [_;"inspect";p] -> let t=match Finalization_record.read p with Ok t->t | Error s->invalid_arg s in
    print_endline (Identity_json.canonical (Finalization_record.to_json t))
  | [_;"normalize";p] -> let r=match Finalization_record.read p with Ok t->Finalization_record.to_json t | Error s->invalid_arg s in
    let context=match r with Identity_json.Object xs->List.assoc "evidence_context" xs | _->assert false in
    let context=Evidence_json.value (match Evidence_json.parse (Identity_json.canonical context) with Ok d->d | Error s->invalid_arg s) in
    let results=Collect_service.to_json (Collect_service.collect ~context ~synthesis_state:(p^"/evidence/synthesis-state.json") p) in
    let verdict=Report_service.evaluate ~context results in
    print_string (Evidence_json.record_bytes (`Assoc ["results",results;"exit_code",`Int (Report_service.exit_code verdict)]))
  | _->invalid_arg "select/inspect/normalize PATH"
  with e->Printf.eprintf "%s\n" (Printexc.to_string e);exit 2
