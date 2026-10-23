module P = Hardcaml_asic_execution.Execution_plan
module J = Hardcaml_asic_execution.Identity_json
module S = Hardcaml_asic.Flow.Stage
module R = Hardcaml_asic.Flow.Recipe

let ok = function Ok x -> x | Error e -> failwith e
let emit j = print_endline (J.canonical j)
let () =
  List.iter (fun endpoint -> List.iter (fun archive ->
    let p = P.Coarse.resolve ~archive endpoint in
    assert (P.to_json (P.of_coarse p) = P.Coarse.to_json p);
    assert (P.actions (P.of_coarse p) = P.Coarse.actions p);
    emit (P.Coarse.to_json p);
    let labels = [""; "same"; "same"; "\000\n"; "λ😀"] in
    emit (P.Coarse.to_json (ok (P.Coarse.with_labels p labels)));)
    [false; true]) [P.Coarse.Synthesis; Full];
  assert (Result.is_error (P.Coarse.with_labels (P.Coarse.resolve Full) ["short"]));
  assert (Result.is_error (P.Coarse.with_labels (P.Coarse.resolve Full)
                            ["a"; "b"; "c"; "d"; "\255"]));
  List.iter (fun endpoint -> List.iter (fun resume ->
    match P.Stage_plan.resolve ~resume endpoint with
    | Ok p ->
      assert (P.to_json (P.of_stages p) = P.Stage_plan.to_json p);
      assert (P.actions (P.of_stages p) = P.Stage_plan.actions p);
      assert (P.Stage_plan.schema_version p = 4);
      assert (S.equal (P.Stage_plan.endpoint p) endpoint);
      emit (P.Stage_plan.to_json p)
    | Error _ -> assert (resume && S.equal endpoint S.Synthesis)) [false; true]) S.all;
  List.iter (fun source -> List.iter (fun endpoint ->
    let resolved = P.Stage_plan.through ?initial_boundary:source endpoint in
    let recipe = R.through ?initial_boundary:source endpoint in
    match resolved, recipe with
    | Ok p, Ok r ->
      assert (P.Stage_plan.schema_version p = 4);
      assert (P.Stage_plan.source_boundary p = source);
      assert (P.Stage_plan.sequence p = R.stages r);
      let q = ok (P.Stage_plan.resolve_sequence ?initial_boundary:source (R.stages r)) in
      assert (J.canonical (P.Stage_plan.to_json q) = J.canonical (P.Stage_plan.to_json p));
      emit (P.Stage_plan.to_json (P.Stage_plan.of_recipe r))
    | Error _, Error _ -> ()
    | _ -> failwith "recipe resolution disagreement") S.all) (None :: List.map Option.some S.all);
  assert (Result.is_error (P.Stage_plan.resolve_sequence ~initial_boundary:S.Synthesis [S.Placement]));
  assert (List.mem S.Placement (S.capability S.Synthesis).restart_targets);
  let prefix = match R.through S.Floorplan with Ok r -> r | Error _ -> assert false in
  let suffix = match R.through ~initial_boundary:S.Floorplan S.Signoff with Ok r -> r | Error _ -> assert false in
  let composed = match R.compose prefix suffix with Ok r -> r | Error _ -> assert false in
  emit (P.Stage_plan.to_json (P.Stage_plan.of_recipe composed))
