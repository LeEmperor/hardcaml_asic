(* Compiled by check_project_api.py as an unrelated public API consumer. *)
open! Core
open! Hardcaml_asic

let () =
  let source_root = Stdlib.Sys.argv.(1) in
  let output_root = Stdlib.Sys.argv.(2) in
  let output name = Filename.concat output_root name in
  (* Keep declaration order and duplicates; Bundle owns canonicalization. *)
  let inventory = "dune-project" :: List.rev (Oracle.source_inputs source_root) in
  let calls = ref [] in
  let reject_simulation = ref false in
  let reject_implementation = ref false in
  let module Design = struct
    include Oracle.Observable
    let create context i =
      let mode = Elaboration_context.mode context in
      calls := mode :: !calls;
      (match mode with
       | Simulation when !reject_simulation -> failwith "simulation rejected"
       | Implementation when !reject_implementation -> failwith "implementation rejected"
       | _ -> ());
      Oracle.Observable.create context i
  end in
  let project ?(source_inputs = inventory) ?target_override () =
    Oracle.project ~source_inputs ~design_override:(module Design)
      ?target_override "observable"
  in
  let p = project () in
  assert (List.equal String.equal (Project.source_inputs p) inventory);
  ignore (Project.describe p : Sexp.t);
  assert (List.is_empty !calls);
  let expect_failure label fragment p ?inputs () =
    let output_dir = output label in
    let result = Project.emit_bundle ?inputs p ~source_root ~output_dir in
    (match result with
     | Ok _ -> failwith ("unexpected success: " ^ label)
     | Error e ->
       assert (String.is_substring (Error.to_string_hum e) ~substring:fragment));
    assert (not (Stdlib.Sys.file_exists output_dir))
  in
  expect_failure "empty" "source_inputs" (project ~source_inputs:[] ()) ();
  assert (List.is_empty !calls);
  reject_implementation := true;
  expect_failure "design" "implementation rejected" p ();
  reject_implementation := false;
  calls := [];
  expect_failure "target" "flow resolution failed"
    (project ~target_override:
       { harness = Tiny_tapeout { tiles = T1x1 }; technology = Technology.ihp_sg13cmos5l } ()) ();
  assert (List.equal Elaboration_mode.equal !calls [ Implementation ]);
  calls := [];
  reject_simulation := true;
  expect_failure "simulation" "simulation rejected" p ();
  assert (List.equal Elaboration_mode.equal !calls [ Simulation; Implementation ]);
  calls := [];
  let fallback =
    Project.emit_bundle ~include_simulation:false p ~source_root
      ~output_dir:(output "fallback") |> Or_error.ok_exn
  in
  assert (List.equal Elaboration_mode.equal !calls [ Implementation ]);
  let open Yojson.Safe.Util in
  assert (Yojson.Safe.equal (member "simulation_sources" (Bundle.manifest fallback))
          (member "synthesis_sources" (Bundle.manifest fallback)));
  reject_simulation := false;
  calls := [];
  let default_bundle = Project.emit_bundle p ~source_root
      ~output_dir:(output "default") |> Or_error.ok_exn in
  assert (List.equal Elaboration_mode.equal !calls [ Simulation; Implementation ]);
  let explicit_bundle = Project.emit_bundle ~include_simulation:true p ~source_root
      ~output_dir:(output "explicit") |> Or_error.ok_exn in
  assert (String.equal (Bundle.identity default_bundle) (Bundle.identity explicit_bundle));
  List.iter (Bundle.paths default_bundle) ~f:(fun path ->
    assert (Option.equal String.equal
              (Bundle.file default_bundle path) (Bundle.file explicit_bundle path)));
  expect_failure "missing" "source input is missing"
    (project ~source_inputs:[ "absent.ml" ] ()) ();
  let reference = Target.Inputs.reference_cmos5l_6x4 in
  let inputs =
    { reference with
      pdk_revision = String.make 40 'a'
    ; support_tools_revision = String.make 40 'b'
    ; floorplan_sha256 = String.make 64 'c'
    ; constraints = { reference.constraints with max_fanout = 17 }
    }
  in
  expect_failure "inputs" "flow resolution failed" p
    ~inputs:{ inputs with pdk_revision = "invalid" } ();
  List.iter [ "observable"; "memory" ] ~f:(fun kind ->
    List.iter [ true; false ] ~f:(fun include_simulation ->
      let p = Oracle.project ~source_inputs:inventory kind in
      let suffix = kind ^ Bool.to_string include_simulation in
      let actual = Project.emit_bundle ~inputs ~include_simulation p ~source_root
          ~output_dir:(output ("high-" ^ suffix)) |> Or_error.ok_exn in
      let resolved = Project.elaborate_for_flow ~inputs p |> Or_error.ok_exn in
      assert (String.equal resolved.target.floorplan.revision inputs.support_tools_revision);
      assert (resolved.target.constraints.max_fanout = 17);
      let simulation_project =
        if include_simulation
        then Some (Project.elaborate p ~mode:Simulation |> Or_error.ok_exn)
        else None
      in
      let expected = Bundle.render ?simulation_project ~source_root
          ~input_paths:inventory resolved |> Or_error.ok_exn in
      Bundle.write expected ~output_dir:(output ("manual-" ^ suffix)) |> Or_error.ok_exn;
      assert (String.equal (Bundle.identity actual) (Bundle.identity expected));
      assert (List.equal String.equal (Bundle.paths actual) (Bundle.paths expected));
      List.iter (Bundle.paths expected) ~f:(fun path ->
        assert (Option.equal String.equal (Bundle.file actual path) (Bundle.file expected path)));
      assert (Yojson.Safe.equal
                (member "pdk_revision" (member "requested_tools" (Bundle.manifest actual)))
                (`String inputs.pdk_revision))));
  (* Write errors propagate and preserve an existing bundle. *)
  let before = In_channel.read_all (output "fallback/manifest.json") in
  assert (Or_error.is_error
            (Project.emit_bundle p ~source_root ~output_dir:(output "fallback")));
  assert (String.equal before (In_channel.read_all (output "fallback/manifest.json")));
  print_endline "project API: declaration, ordering, failures, overrides and whole-bundle equivalence pass"
;;
