module E = Hardcaml_asic_execution
module D = Hardcaml_asic_flow_domain
module M = D.Backends.Librelane.Mapping
module S = Hardcaml_asic.Flow.Stage
let () =
  (* Public aliases are definitionally equal, not copied stage types. *)
  List.iter (fun (stage : S.t) ->
    assert ((S.capability stage).endpoint = M.endpoint stage);
    assert (D.Registry.restart_targets stage = (S.capability stage).restart_targets)) S.all;
  assert (M.validate_sequence ~initial_boundary:None S.all = Ok ());
  assert (Result.is_error (M.validate_sequence ~initial_boundary:(Some S.Synthesis) [S.Placement]));
  assert (Result.is_error (M.validate_sequence ~initial_boundary:None [S.Placement]));
  let inventory = List.map (fun (o : M.occurrence) -> o.step) M.all in
  assert (M.validate_inventory inventory = Ok ());
  assert (Result.is_error (M.validate_inventory (List.rev inventory)));
  if Array.length Sys.argv > 1 then (
    let text = In_channel.input_all stdin in
    let result = match E.Identity_json.parse text with
      | Error e -> Error (E.Identity_json.error_message e)
      | Ok j -> if Sys.argv.(1) = "settings" then E.Classic_contract.validate_settings j
        else E.Classic_contract.validate_inventory j in
    match result with Ok () -> print_endline "validated" | Error e -> prerr_endline e; exit 2)
  else print_endline (E.Identity_json.canonical (E.Classic_contract.inventory ()))
