(* Compiled by check_project_api.py as an unrelated public API consumer. *)
module U = Unix
open! Core
open! Hardcaml_asic

(* Separate executable invocations exercise the actual public publisher. A gate
   releases two independently rendered bundles into a real filesystem race. *)
let publish_command () =
  let source_root = Stdlib.Sys.argv.(2) in
  let store_dir = Stdlib.Sys.argv.(3) in
  let inventory = "dune-project" :: List.rev (Oracle.source_inputs source_root) in
  let p = Oracle.project ~source_inputs:inventory "observable" in
  let result =
    if Array.length Stdlib.Sys.argv = 6 then (
      let resolved = Project.elaborate_for_flow p |> Or_error.ok_exn in
      let simulation_project = Project.elaborate p ~mode:Simulation |> Or_error.ok_exn in
      let bundle = Bundle.render ~simulation_project ~source_root ~input_paths:inventory
          resolved |> Or_error.ok_exn in
      Out_channel.write_all Stdlib.Sys.argv.(5) ~data:"ready";
      while not (Stdlib.Sys.file_exists Stdlib.Sys.argv.(4)) do U.sleepf 0.01 done;
      Or_error.map (Bundle.publish bundle ~store_dir) ~f:(fun publication -> bundle, publication))
    else Project.emit_bundle_to_store p ~source_root ~store_dir
  in
  match result with
  | Error e -> prerr_endline (Error.to_string_hum e); Stdlib.exit 1
  | Ok (bundle, publication) ->
    print_endline (Yojson.Safe.to_string
      (`Assoc [ "identity", `String (Bundle.identity bundle)
              ; "directory", `String publication.directory
              ; "reused", `Bool publication.reused ]));
    Stdlib.exit 0
;;

let () =
  if String.equal Stdlib.Sys.argv.(1) "publish" then publish_command ();
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
      let mode = Elaboration.Context.mode context in
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
  let failed_store = output "failed store" in
  assert (Or_error.is_error
            (Project.emit_bundle_to_store (project ~source_inputs:[] ())
               ~source_root ~store_dir:failed_store));
  assert (not (Stdlib.Sys.file_exists failed_store));
  assert (List.is_empty !calls);
  reject_implementation := true;
  expect_failure "design" "implementation rejected" p ();
  reject_implementation := false;
  calls := [];
  expect_failure "target" "flow resolution failed"
    (project ~target_override:
       { harness = Tiny_tapeout { tiles = T1x1 }; technology = Resource.Technology.ihp_sg13cmos5l } ()) ();
  assert (List.equal Elaboration.Mode.equal !calls [ Implementation ]);
  calls := [];
  reject_simulation := true;
  expect_failure "simulation" "simulation rejected" p ();
  assert (List.equal Elaboration.Mode.equal !calls [ Simulation; Implementation ]);
  calls := [];
  let fallback =
    Project.emit_bundle ~include_simulation:false p ~source_root
      ~output_dir:(output "fallback") |> Or_error.ok_exn
  in
  assert (List.equal Elaboration.Mode.equal !calls [ Implementation ]);
  let open Yojson.Safe.Util in
  assert (Yojson.Safe.equal (member "simulation_sources" (Bundle.manifest fallback))
           (member "synthesis_sources" (Bundle.manifest fallback)));
  calls := [];
  let stored_fallback, _ = Project.emit_bundle_to_store ~include_simulation:false p
      ~source_root ~store_dir:(output "fallback store") |> Or_error.ok_exn in
  assert (List.equal Elaboration.Mode.equal !calls [ Implementation ]);
  assert (String.equal (Bundle.identity stored_fallback) (Bundle.identity fallback));
  reject_simulation := false;
  calls := [];
  let default_bundle = Project.emit_bundle p ~source_root
      ~output_dir:(output "default") |> Or_error.ok_exn in
  assert (List.equal Elaboration.Mode.equal !calls [ Simulation; Implementation ]);
  calls := [];
  let stored_default, _ = Project.emit_bundle_to_store p ~source_root
      ~store_dir:(output "default store") |> Or_error.ok_exn in
  assert (List.equal Elaboration.Mode.equal !calls [ Simulation; Implementation ]);
  assert (String.equal (Bundle.identity stored_default) (Bundle.identity default_bundle));
  let explicit_bundle = Project.emit_bundle ~include_simulation:true p ~source_root
      ~output_dir:(output "explicit") |> Or_error.ok_exn in
  assert (String.equal (Bundle.identity default_bundle) (Bundle.identity explicit_bundle));
  List.iter (Bundle.paths default_bundle) ~f:(fun path ->
    assert (Option.equal String.equal
              (Bundle.file default_bundle path) (Bundle.file explicit_bundle path)));
  expect_failure "missing" "source input is missing"
    (project ~source_inputs:[ "absent.ml" ] ()) ();
  assert (Or_error.is_error
            (Project.emit_bundle_to_store (project ~source_inputs:[ "absent.ml" ] ())
               ~source_root ~store_dir:failed_store));
  assert (not (Stdlib.Sys.file_exists failed_store));
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
      let stored, publication = Project.emit_bundle_to_store ~inputs ~include_simulation p
          ~source_root ~store_dir:(output ("store-" ^ suffix)) |> Or_error.ok_exn in
      assert (not publication.reused);
      assert (String.equal (Filename.basename publication.directory) (Bundle.identity stored));
      assert (String.equal (Bundle.identity stored) (Bundle.identity expected));
      let again = Bundle.publish stored ~store_dir:(output ("store-" ^ suffix))
          |> Or_error.ok_exn in
      assert (again.reused && String.equal again.directory publication.directory);
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
  (* Checked catalog profiles render concrete bundles before any publication. *)
  let module P = Flow.Parameter in
  let m = Flow.Methodology.create ~id:"classic" ~label:"Classic" ~description:""
      ~backend_recipe:Librelane_classic_v1 ~endpoints:[ Synthesis ]
      ~configurable:P.Key.all ~defaults:[] |> Or_error.ok_exn in
  let profile id strategy = Flow.Profile.create ~id ~label:id ~description:""
      ~assignments:[ P.synth_strategy strategy; P.synth_abc_buffering false ]
      |> Or_error.ok_exn in
  let entry = Flow.Catalog.Entry.create ~methodology:m
      ~profiles:[ profile "area" Area_0; profile "delay" Delay_1 ]
      ~default_profile:"area" |> Or_error.ok_exn in
  let catalog = Flow.Catalog.create ~entries:[ entry ] ~default_flow:"classic"
      ~default_profile:"area" |> Or_error.ok_exn in
  let snapshot profile =
    let selection = Flow.Selection.create ~flow:"classic" ~profile () |> Or_error.ok_exn in
    Flow.Catalog.resolve ~selection catalog ~endpoint:Synthesis () |> Or_error.ok_exn in
  let area = snapshot "area" and delay = snapshot "delay" in
  let declaration_before = Project.describe p in
  calls := [];
  let area_bundle = Project.render_bundle ~methodology:area p ~source_root |> Or_error.ok_exn in
  assert (List.equal Elaboration.Mode.equal !calls [ Simulation; Implementation ]);
  let delay_bundle = Project.render_bundle ~methodology:delay p ~source_root |> Or_error.ok_exn in
  assert (not (String.equal (Bundle.identity area_bundle) (Bundle.identity delay_bundle)));
  List.iter (Bundle.paths area_bundle) ~f:(fun path ->
    if not (List.mem [ "src/config.json"; "manifest.json" ] path ~equal:String.equal)
    then assert (Option.equal String.equal (Bundle.file area_bundle path) (Bundle.file delay_bundle path)));
  let config bundle = Bundle.file bundle "src/config.json" |> Option.value_exn
      |> Yojson.Safe.from_string in
  assert (Yojson.Safe.equal (member "SYNTH_STRATEGY" (config area_bundle)) (`String "AREA 0"));
  assert (Yojson.Safe.equal (member "SYNTH_STRATEGY" (config delay_bundle)) (`String "DELAY 1"));
  assert (Yojson.Safe.equal (member "SYNTH_ABC_BUFFERING" (config delay_bundle)) (`Bool false));
  assert (String.is_substring (Yojson.Safe.to_string (Bundle.manifest delay_bundle))
            ~substring:"Methodology Profile");
  let hash = Bundle.identity area_bundle in
  calls := [];
  let published = Bundle.publish area_bundle ~store_dir:(output "preview store") |> Or_error.ok_exn in
  assert (List.is_empty !calls);
  assert (String.equal hash (Filename.basename published.directory));
  assert (String.equal (In_channel.read_all (Filename.concat published.directory "manifest.json"))
            (Bundle.file area_bundle "manifest.json" |> Option.value_exn));
  let emitted = Project.emit_bundle ~methodology:area p ~source_root
      ~output_dir:(output "area emitted") |> Or_error.ok_exn in
  assert (String.equal hash (Bundle.identity emitted));
  let stored, _ = Project.emit_bundle_to_store ~methodology:delay p ~source_root
      ~store_dir:(output "delay store") |> Or_error.ok_exn in
  assert (String.equal (Bundle.identity stored) (Bundle.identity delay_bundle));
  assert (Sexp.equal declaration_before (Project.describe p));
  let legacy = Project.render_bundle p ~source_root |> Or_error.ok_exn in
  assert (String.equal (Bundle.identity legacy) (Bundle.identity default_bundle));
  print_endline "project API: declaration, ordering, failures, overrides and whole-bundle equivalence pass"
;;
