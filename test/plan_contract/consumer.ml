open! Core
open! Hardcaml
open! Hardcaml_asic
module P = Flow.Parameter
module C = Flow.Catalog
module MP = Methodology_plan
module E = Resolved_flow.Effective_parameter
module J = Flow.Plan_json

let ok = Or_error.ok_exn
let checks = ref 0

let check label b =
  incr checks;
  if not b then failwith label
;;

let reject label r = check label (Or_error.is_error r)
let get = J.get

let set j key v =
  match j with
  | `Assoc xs ->
    `Assoc (List.map xs ~f:(fun (k, old) -> k, if String.equal key k then v else old))
  | _ -> assert false
;;

let rec alter j path f =
  match path with
  | [] -> f j
  | k :: ks -> set j k (alter (get j k) ks f)
;;

let rec reverse_objects : Yojson.Safe.t -> Yojson.Safe.t = function
  | `Assoc xs -> `Assoc (List.rev_map xs ~f:(fun (k, v) -> k, reverse_objects v))
  | `List xs -> `List (List.map xs ~f:reverse_objects)
  | j -> j
;;

let catalog ?(label = "Classic") ?(reverse = false) () =
  let defaults = [ P.synth_strategy Area_1; P.synth_abc_buffering true ] in
  let m =
    ok
      (Flow.Methodology.create
         ~id:"classic"
         ~label
         ~description:"definition"
         ~backend_recipe:Librelane_classic_v1
         ~endpoints:Flow.Stage.all
         ~configurable:P.Key.all
         ~defaults:(if reverse then List.rev defaults else defaults))
  in
  let profile id strategy =
    ok
      (Flow.Profile.create
         ~id
         ~label:id
         ~description:"profile"
         ~assignments:[ P.synth_strategy strategy; P.synth_abc_buffering false ])
  in
  let profiles =
    [ profile "area" Area_0; profile "delay" Delay_1; profile "alias" Area_0 ]
  in
  let e =
    ok
      (C.Entry.create
         ~methodology:m
         ~profiles:(if reverse then List.rev profiles else profiles)
         ~default_profile:"area")
  in
  ok (C.create ~entries:[ e ] ~default_flow:"classic" ~default_profile:"area")
;;

let selection profile = ok (Flow.Selection.create ~flow:"classic" ~profile ())

let resolve ?(profile = "area") ?(endpoint = Flow.Stage.Synthesis) ?(request = []) c =
  ok (C.resolve ~selection:(selection profile) ~request c ~endpoint ())
;;

let pure_checks () =
  let c = catalog () in
  let wire = Flow.Spec.declaration_to_yojson c in
  let decoded = ok (Flow.Spec.declaration_of_yojson (reverse_objects wire)) in
  check "declaration roundtrip" (J.equal wire (Flow.Spec.declaration_to_yojson decoded));
  check
    "canonical declaration ordering"
    (J.equal wire (Flow.Spec.declaration_to_yojson (catalog ~reverse:true ())));
  check
    "list roundtrip"
    (J.equal
       wire
       (Flow.Spec.declaration_to_yojson
          (ok (Flow.Spec.list_of_yojson (Flow.Spec.list_to_yojson c)))));
  let e = List.hd_exn (C.entries c) in
  let desc = Flow.Spec.describe_to_yojson e in
  check
    "describe roundtrip"
    (J.equal desc (Flow.Spec.describe_to_yojson (ok (Flow.Spec.describe_of_yojson desc))));
  reject
    "describe version"
    (Flow.Spec.describe_of_yojson (set desc "schema_version" (`Int 0)));
  reject
    "list descriptors"
    (Flow.Spec.list_of_yojson
       (set (Flow.Spec.list_to_yojson c) "parameter_descriptors" (`List [])));
  reject
    "unsupported backend recipe"
    (Flow.Spec.describe_of_yojson
       (alter desc [ "entry"; "methodology"; "backend_recipe" ] (fun _ ->
          `String "librelane.classic.v2")));
  reject
    "duplicate profile"
    (Flow.Spec.describe_of_yojson
       (alter desc [ "entry"; "profiles" ] (function
         | `List (x :: xs) -> `List (x :: x :: xs)
         | _ -> assert false)));
  reject
    "duplicate endpoint"
    (Flow.Spec.describe_of_yojson
       (alter desc [ "entry"; "methodology"; "endpoints" ] (function
         | `List (x :: xs) -> `List (x :: x :: xs)
         | _ -> assert false)));
  reject
    "wire unknown field"
    (Flow.Spec.declaration_of_yojson
       (match wire with
        | `Assoc xs -> `Assoc (("unknown", `Null) :: xs)
        | _ -> assert false));
  reject
    "wire duplicate field"
    (Flow.Spec.declaration_of_yojson
       (match wire with
        | `Assoc xs -> `Assoc (List.hd_exn xs :: xs)
        | _ -> assert false));
  reject
    "wire version"
    (Flow.Spec.declaration_of_yojson (set wire "schema_version" (`Int 2)));
  reject
    "duplicate entries"
    (Flow.Spec.declaration_of_yojson
       (set
          wire
          "entries"
          (`List
            [ get (Flow.Spec.describe_to_yojson e) "entry"
            ; get (Flow.Spec.describe_to_yojson e) "entry"
            ])));
  reject
    "duplicate assignments"
    (Flow.Spec.describe_of_yojson
       (alter desc [ "entry"; "methodology"; "defaults" ] (function
         | `List (x :: xs) -> `List (x :: x :: xs)
         | _ -> assert false)));
  List.iter
    [ `Int 1; `Null; `Float Float.nan; `Float Float.infinity; `String "true"; `Assoc [] ]
    ~f:(fun value ->
      reject
        "strict bool"
        (Flow.Spec.assignment_of_yojson
           (`Assoc [ "key", `String "SYNTH_ABC_BUFFERING"; "value", value ])));
  reject
    "unknown typed key"
    (Flow.Spec.assignment_of_yojson
       (`Assoc [ "key", `String "PL_TARGET_DENSITY_PCT"; "value", `Bool true ]));
  reject
    "profile alone"
    (Flow.Spec.selection_of_yojson (`Assoc [ "flow", `Null; "profile", `String "area" ]));
  let r = resolve ~request:[ P.synth_strategy Delay_2 ] c in
  let rw = Flow.Spec.resolved_to_yojson r in
  check
    "snapshot roundtrip"
    (J.equal
       rw
       (Flow.Spec.resolved_to_yojson
          (ok (Flow.Spec.resolved_of_yojson (reverse_objects rw)))));
  List.iter
    [ [ "profile"; "label" ]; [ "definition"; "methodology"; "label" ]; [ "endpoint" ] ]
    ~f:(fun path ->
      reject
        "snapshot tampering"
        (Flow.Spec.resolved_of_yojson (alter rw path (fun _ -> `String "wrong"))));
  reject
    "snapshot history tampering"
    (Flow.Spec.resolved_of_yojson (set rw "parameters" (`List [])));
  reject
    "snapshot winner tampering"
    (Flow.Spec.resolved_of_yojson
       (alter rw [ "parameters" ] (function
         | `List (x :: xs) ->
           `List (alter x [ "winning"; "assignment"; "value" ] (fun _ -> `Bool true) :: xs)
         | _ -> assert false)));
  let a = `Assoc [ "z", `Int 1; "a", `List [ `Int 1; `Int 2 ] ] in
  check
    "canonical objects"
    (String.equal (ok (J.canonical a)) (ok (J.canonical (reverse_objects a))));
  check
    "sequence matters"
    (not
       (String.equal
          (ok (J.canonical a))
          (ok (J.canonical (set a "a" (`List [ `Int 2; `Int 1 ]))))));
  reject "finite canonical" (J.canonical (`Float Float.neg_infinity));
  reject "extension canonical" (J.canonical (`Tuple []));
  check
    "contract discriminator"
    (not
       (String.equal (ok (J.identity ~contract:"a" a)) (ok (J.identity ~contract:"b" a))))
;;

let calls = ref 0

module Design = struct
  module I = Tt_cmos5l.I
  module O = Tt_cmos5l.O

  let name = "tt_um_plan_fixture"

  let create _ (i : _ I.t) =
    incr calls;
    { O.uo_out = Signal.reg (Signal.Reg_spec.create ~clock:i.clk ()) i.ui_in
    ; uio_out = Signal.zero 8
    ; uio_oe = Signal.zero 8
    }
  ;;
end

let project ?(reason = "project strategy") ?(name = "plan_fixture") () =
  let pinout =
    List.concat_map [ Pinout.Bank.Ui; Uo; Uio ] ~f:(fun bank ->
      List.init 8 ~f:(fun bit -> { Pinout.bank; bit; description = "test" }))
  in
  ok
    (Project.create
       ~name
       ~metadata:
         { title = "Plan fixture"; author = "Test"; description = "Plan preparation" }
       ~design:(module Design)
       ~target:
         { harness = Tiny_tapeout { tiles = T6x4 }
         ; technology = Resource.Technology.ihp_sg13cmos5l
         }
       ~flow:
         (Flow.librelane
            Hardening
            ~overrides:
              ({ Flow.Librelane.Override.key = "SYNTH_STRATEGY"
               ; value = `String "AREA 3"
               ; reason
               }
               :: Tt_cmos5l.overrides ()))
       ~clocks:[ { Clock.port = "clk"; period = Time_float.Span.of_ns 20. } ]
       ~pinout
       ~source_inputs:[ "design.ml" ]
       ~policy:(ok (Resource_policy.create ~default:Flops []))
       ())
;;

let resign j =
  let md = get j "methodology" in
  let j =
    set
      j
      "methodology_hash"
      (`String (ok (J.identity ~contract:"hardcaml-asic.methodology-hash" md)))
  in
  let unsigned =
    match j with
    | `Assoc xs ->
      `Assoc (List.filter xs ~f:(fun (k, _) -> not (String.equal k "plan_identity")))
    | _ -> assert false
  in
  set
    j
    "plan_identity"
    (`String (ok (J.identity ~contract:"hardcaml-asic.plan-identity" unsigned)))
;;

let resign_manifest wire manifest =
  let unsigned = match manifest with
    | `Assoc xs -> `Assoc (List.filter xs ~f:(fun (k, _) -> not (String.equal k "identity")))
    | _ -> assert false in
  let identity = J.sha256 (Yojson.Safe.to_string unsigned) in
  let manifest = set manifest "identity" (`String identity) in
  set (set wire "bundle_identity" (`String identity)) "bundle_manifest"
    (`String (Yojson.Safe.to_string manifest)) |> resign
;;

let corrupt_inventory wire mode =
  let manifest = Yojson.Safe.from_string (J.string (get wire "bundle_manifest")) in
  let manifest =
    if String.equal mode "bad-source" then
      alter manifest ["source_inputs"] (function
        | `List (first :: rest) -> `List (set first "sha256" (`String (String.make 64 '0')) :: rest)
        | _ -> assert false)
    else if String.is_prefix mode ~prefix:"omit:" then
      let path = String.chop_prefix_exn mode ~prefix:"omit:" in
      alter manifest ["files"] (function
        | `List xs -> `List (List.filter xs ~f:(fun f -> not (String.equal (J.string (get f "path")) path)))
        | _ -> assert false)
    else if String.is_prefix mode ~prefix:"declared:" then
      set manifest (String.chop_prefix_exn mode ~prefix:"declared:") (`List [ `String "src/config.json" ])
    else if String.is_prefix mode ~prefix:"config:" || String.is_prefix mode ~prefix:"extra:"
         || String.is_prefix mode ~prefix:"expression:" then (
      let expression = String.chop_prefix mode ~prefix:"expression:" in
      let extra = String.is_prefix mode ~prefix:"extra:" || Option.is_some expression in
      let key = if Option.is_some expression then "SYNTH_DEFINES" else String.drop_prefix mode (if extra then 6 else 7) in
      let value = if String.equal key "VERILOG_FILES" then `List [ `String "dir::*.v" ]
        else if Option.is_some expression then `List [ `String (Option.value_exn expression) ]
        else `String (if extra then "unchecked.tcl" else "dir::../constraints/unchecked.sdc") in
      let config = set (get manifest "flow_configuration") key value in
      let manifest = set manifest "flow_configuration" config in
      if extra then alter manifest ["resolved_settings"] (function
        | `List xs -> `List (xs @ [ `Assoc ["key", `String key; "value", value; "owner", `String "fixture"] ])
        | _ -> assert false)
      else manifest)
    else (
      let field, change = match mode with
        | "bad-copy" -> "source_inputs", (function
            | `List (f :: xs) -> `List (set f "copy" (`String "inputs/other.ml") :: xs)
            | _ -> assert false)
        | "duplicate-source" -> "source_inputs", (function
            | `List (f :: xs) -> `List (f :: f :: xs) | _ -> assert false)
        | "missing-source" -> "source_inputs", (function
            | `List (_ :: xs) -> `List xs | _ -> assert false)
        | "duplicate-file" -> "files", (function
            | `List (f :: xs) -> `List (f :: f :: xs) | _ -> assert false)
        | "bad-hash" -> "files", (function
            | `List (f :: xs) -> `List (set f "sha256" (`String "not-sha256") :: xs)
            | _ -> assert false)
        | "unsafe-file" -> "files", (function
            | `List (f :: xs) -> `List (set f "path" (`String "../escape") :: xs)
            | _ -> assert false)
        | "file-descendant" -> "files", (function
            | `List (f :: xs) -> `List (set f "path" (`String "src") :: f :: xs)
            | _ -> assert false)
        | _ -> failwith "unknown inventory mutation" in
      alter manifest [field] change)
  in
  let config = get manifest "flow_configuration" in
  let bytes = Yojson.Safe.pretty_to_string config ^ "\n" in
  let manifest = alter manifest ["files"] (function
    | `List xs -> `List (List.map xs ~f:(fun f ->
        if J.equal (get f "path") (`String "src/config.json") then set f "sha256" (`String (J.sha256 bytes)) else f))
    | _ -> assert false) in
  resign_manifest (set wire "configuration_bytes" (`String bytes)) manifest
;;

let inventory_mutations top =
  [ "bad-source"; "bad-copy"; "duplicate-source"; "missing-source"; "duplicate-file";
    "bad-hash"; "unsafe-file"; "file-descendant";
    "declared:synthesis_sources"; "declared:simulation_sources";
    "config:VERILOG_FILES"; "config:PNR_SDC_FILE"; "config:SIGNOFF_SDC_FILE";
    "extra:SYNTH_EXTRA_MAPPING_FILE"; "extra:VERILOG_INCLUDE_DIRS";
    "extra:PDN_CFG"; "extra:FP_PDN_CFG"; "extra:meta"; "extra:SYNTH_STRATEGY";
    "expression:dir::*.v"; "expression:ref::$DESIGN_DIR/unchecked.v";
    "expression:exec::unchecked"; "expression:expr::1+1";
    "omit:src/config.json"; "omit:src/" ^ top ^ ".v";
    "omit:constraints/top.sdc"; "omit:inputs/design.ml" ]
;;

let () =
  pure_checks ();
  check "pure discovery did not elaborate" (!calls = 0);
  let source_root = Stdlib.Sys.argv.(1) in
  let p = project () in
  let c = catalog () in
  let prep
    ?(catalog = c)
    ?(profile = "area")
    ?(endpoint = Flow.Stage.Synthesis)
    ?inputs
    ?expected_plan_identity
    ?(catalog_inputs = [ "catalog.ml" ])
    ?(include_simulation = false)
    ?(project = p)
    ()
    =
    MP.prepare
      ?inputs
      ?expected_plan_identity
      ~catalog
      ~selection:(selection profile)
      ~endpoint
      ~include_simulation
      ~catalog_inputs
      project
      ~source_root
  in
  let expected =
    if Array.length Stdlib.Sys.argv > 3 then Some Stdlib.Sys.argv.(3) else None
  in
  if Array.length Stdlib.Sys.argv > 2 && String.equal Stdlib.Sys.argv.(2) "native-fixture"
  then (
    let base = Target.Inputs.reference_cmos5l_6x4 in
    let inputs = { base with support_tools_revision = String.make 40 'a'; pdk_revision = String.make 40 'a';
      floorplan_sha256 = J.sha256 "floorplan fixture" } in
    let endpoint = if Array.length Stdlib.Sys.argv > 5 then ok (Flow.Stage.of_string Stdlib.Sys.argv.(5)) else Flow.Stage.Floorplan in
    let prepared = ok (prep ~profile:Stdlib.Sys.argv.(3) ~inputs ~endpoint ()) in
    let publication = ok (Bundle.publish (MP.Prepared.bundle prepared) ~store_dir:Stdlib.Sys.argv.(4)) in
    let wire = MP.to_yojson (MP.Prepared.plan prepared) in
    let wire =
      if Array.length Stdlib.Sys.argv > 6
      then (
        let mode = Stdlib.Sys.argv.(6) in
        let wire = corrupt_inventory wire mode in
        reject "rehashed incomplete inventory" (MP.of_yojson wire);
        wire)
      else wire
    in
    print_endline (Yojson.Safe.to_string (`Assoc ["plan",wire;"directory",`String publication.directory]));
    Stdlib.exit 0);
  let prepared = ok (prep ?expected_plan_identity:expected ()) in
  check "one elaboration" (!calls = 1);
  let plan = MP.Prepared.plan prepared
  and bundle = MP.Prepared.bundle prepared in
  let wire = MP.to_yojson plan in
  List.iter (inventory_mutations (J.string (get (Bundle.manifest bundle) "top_module"))) ~f:(fun mode ->
    reject ("rehashed " ^ mode) (MP.of_yojson (corrupt_inventory wire mode)));
  if Array.length Stdlib.Sys.argv > 2 && String.equal Stdlib.Sys.argv.(2) "publish"
  then (
    let before = !calls in
    (* Source can change after preview; publication must retain these exact bytes. *)
    Out_channel.write_all
      (Filename.concat source_root "design.ml")
      ~data:"changed after prepare\n";
    let publication = ok (Bundle.publish bundle ~store_dir:Stdlib.Sys.argv.(4)) in
    check "prepared publication no rerender" (!calls = before);
    print_endline
      (Yojson.Safe.to_string
         (`Assoc
           [ "plan", wire
           ; "directory", `String publication.directory
           ; "elaborations", `Int !calls
           ]));
    Stdlib.exit 0);
  if Array.length Stdlib.Sys.argv > 2
  then (
    print_endline (MP.to_string plan);
    Stdlib.exit 0);
  check
    "plan checked roundtrip"
    (String.equal
       (MP.to_string plan)
        (MP.to_string (ok (MP.of_string (MP.to_string plan)))));
  let simulated = MP.Prepared.plan (ok (prep ~include_simulation:true ())) |> MP.to_yojson in
  ignore (ok (MP.of_yojson simulated) : MP.t);
  check "separate simulation RTL accepted" true;
  let top = J.string (get (Bundle.manifest bundle) "top_module") in
  reject "omitted simulation inventory" (MP.of_yojson (corrupt_inventory simulated ("omit:simulation/" ^ top ^ ".v")));
  check
    "plan object ordering"
    (String.equal
       (MP.plan_identity plan)
       (MP.plan_identity (ok (MP.of_yojson (reverse_objects wire)))));
  let identity_of r = MP.plan_identity (MP.Prepared.plan (ok r)) in
  check
    "assignment map ordering"
    (String.equal
       (MP.plan_identity plan)
       (identity_of (prep ~catalog:(catalog ~reverse:true ()) ())));
  check
    "definition changes identity"
    (not
       (String.equal
          (MP.plan_identity plan)
          (identity_of (prep ~catalog:(catalog ~label:"Renamed" ()) ()))));
  check
    "endpoint changes identity"
    (not
       (String.equal (MP.plan_identity plan) (identity_of (prep ~endpoint:Placement ()))));
  check
    "project provenance changes identity"
    (not
       (String.equal
          (MP.plan_identity plan)
          (identity_of (prep ~project:(project ~reason:"different reason" ()) ()))));
  check
    "project name changes identity"
    (not
       (String.equal
          (MP.plan_identity plan)
          (identity_of (prep ~project:(project ~name:"other" ()) ()))));
  let alias = ok (prep ~profile:"alias" ()) in
  check
    "same configuration different profile plan"
    (not
       (String.equal (MP.plan_identity plan) (MP.plan_identity (MP.Prepared.plan alias))));
  check
    "same configuration same bundle"
    (String.equal (Bundle.identity bundle) (Bundle.identity (MP.Prepared.bundle alias)));
  let delay = ok (prep ~profile:"delay" ()) in
  let other = MP.Prepared.bundle delay in
  check
    "different config bundle"
    (not (String.equal (Bundle.identity bundle) (Bundle.identity other)));
  List.iter (Bundle.paths bundle) ~f:(fun path ->
    if not (List.mem [ "src/config.json"; "manifest.json" ] path ~equal:String.equal)
    then
      check
        ("same bytes " ^ path)
        (Option.equal String.equal (Bundle.file bundle path) (Bundle.file other path)));
  let cfg b =
    Yojson.Safe.from_string (Option.value_exn (Bundle.file b "src/config.json"))
  in
  check
    "actual area bytes"
    (J.equal (get (cfg bundle) "SYNTH_STRATEGY") (`String "AREA 0"));
  check
    "actual delay bytes"
    (J.equal (get (cfg other) "SYNTH_STRATEGY") (`String "DELAY 1"));
  check
    "actual bool bytes"
    (J.equal (get (cfg other) "SYNTH_ABC_BUFFERING") (`Bool false));
  let silent_methodology =
    ok
      (Flow.Methodology.create
         ~id:"silent"
         ~label:"Silent"
         ~description:""
         ~backend_recipe:Librelane_classic_v1
         ~endpoints:[ Synthesis ]
         ~configurable:P.Key.all
         ~defaults:[])
  in
  let silent_profile =
    ok (Flow.Profile.create ~id:"area" ~label:"Area" ~description:"" ~assignments:[])
  in
  let silent_entry =
    ok
      (C.Entry.create
         ~methodology:silent_methodology
         ~profiles:[ silent_profile ]
         ~default_profile:"area")
  in
  let silent_catalog =
    ok (C.create ~entries:[ silent_entry ] ~default_flow:"silent" ~default_profile:"area")
  in
  let silent =
    ok
      (MP.prepare
         ~catalog:silent_catalog
         ~endpoint:Synthesis
         ~include_simulation:false
         p
         ~source_root)
  in
  check
    "unspecified backend default not effective"
    (List.length (MP.effective_parameters (MP.Prepared.plan silent)) = 1);
  check
    "unspecified backend default not emitted"
    (match cfg (MP.Prepared.bundle silent) with
     | `Assoc xs -> not (List.Assoc.mem xs "SYNTH_ABC_BUFFERING" ~equal:String.equal)
     | _ -> false);
  check
    "unspecified plan roundtrip"
    (String.equal
       (MP.to_string (MP.Prepared.plan silent))
       (MP.to_string (ok (MP.of_string (MP.to_string (MP.Prepared.plan silent))))));
  let inherited =
    List.find_exn (MP.effective_parameters plan) ~f:(fun ep ->
      P.Key.equal (P.assignment_key ep.E.winning.assignment) P.Key.Synth_strategy)
  in
  check "complete project history" (List.length inherited.overridden = 2);
  (match (List.hd_exn inherited.overridden).owner with
   | Override reason ->
     check "original project reason" (String.equal reason "project strategy")
   | _ -> failwith "lost project owner");
  List.iter
    [ [ "methodology_hash" ]
    ; [ "plan_identity" ]
    ; [ "bundle_identity" ]
    ; [ "project_name" ]
    ]
    ~f:(fun path ->
      reject
        "tampered asserted identity/metadata"
        (MP.of_yojson (alter wire path (fun _ -> `String "wrong"))));
  List.iter
    [ [ "methodology"; "effective_parameters" ]
    ; [ "methodology"; "project_assignments" ]
    ]
    ~f:(fun path ->
      reject
        "rehashed effective/history tampering"
        (MP.of_yojson (resign (alter wire path (fun _ -> `List [])))));
  reject
    "rehashed recipe tampering"
    (MP.of_yojson
       (resign
          (alter wire [ "methodology"; "recipe"; "stages" ] (fun _ ->
             `List [ `String "routing" ]))));
  reject
    "rehashed translation tampering"
    (MP.of_yojson
       (resign
          (alter wire [ "methodology"; "translation"; "schema_version" ] (fun _ -> `Int 2))));
  reject
    "rehashed snapshot tampering"
    (MP.of_yojson
       (resign
          (alter wire [ "methodology"; "snapshot"; "profile"; "label" ] (fun _ ->
             `String "forged"))));
  reject
    "rehashed config bytes tampering"
    (MP.of_yojson (resign (set wire "configuration_bytes" (`String "{}"))));
  reject
    "rehashed overridden history tampering"
    (MP.of_yojson
       (resign
          (alter wire [ "methodology"; "effective_parameters" ] (function
            | `List xs -> `List (List.map xs ~f:(fun x -> set x "overridden" (`List [])))
            | _ -> assert false))));
  reject
    "rehashed bundle digest association"
    (MP.of_yojson (resign (set wire "bundle_identity" (`String (String.make 64 'a')))));
  (* Even re-signing both hash envelopes cannot hide an emitted typed value that disagrees
     with the selected snapshot/replayed effective configuration. *)
  let configuration = set (cfg bundle) "SYNTH_STRATEGY" (`String "DELAY 4") in
  let bytes = Yojson.Safe.pretty_to_string configuration ^ "\n" in
  let manifest =
    Bundle.manifest bundle
    |> fun m ->
    set m "flow_configuration" configuration
    |> fun m ->
    alter m [ "resolved_settings" ] (function
      | `List xs ->
        `List
          (List.map xs ~f:(fun s ->
             if J.equal (get s "key") (`String "SYNTH_STRATEGY")
             then set s "value" (`String "DELAY 4")
             else s))
      | _ -> assert false)
    |> fun m ->
    alter m [ "files" ] (function
      | `List xs ->
        `List
          (List.map xs ~f:(fun f ->
             if J.equal (get f "path") (`String "src/config.json")
             then set f "sha256" (`String (J.sha256 bytes))
             else f))
      | _ -> assert false)
  in
  let unsigned_manifest =
    match manifest with
    | `Assoc xs ->
      `Assoc (List.filter xs ~f:(fun (k, _) -> not (String.equal k "identity")))
    | _ -> assert false
  in
  let forged_identity = J.sha256 (Yojson.Safe.to_string unsigned_manifest) in
  let manifest = set manifest "identity" (`String forged_identity) in
  let forged =
    wire
    |> fun w ->
    set w "configuration_bytes" (`String bytes)
    |> fun w ->
    set w "bundle_manifest" (`String (Yojson.Safe.to_string manifest))
    |> fun w -> set w "bundle_identity" (`String forged_identity) |> resign
  in
  reject "fully rehashed mismatched bundle/effective" (MP.of_yojson forged);
  reject
    "rehashed bundle metadata tampering"
    (MP.of_yojson
       (resign
          (set
             wire
             "bundle_manifest"
             (`String
               (Yojson.Safe.to_string
                  (set (Bundle.manifest bundle) "project" (`String "forged")))))));
  let before = !calls in
  ignore (ok (prep ~expected_plan_identity:(MP.plan_identity plan) ()) : MP.Prepared.t);
  check "expected match one render" (!calls = before + 1);
  reject "expected mismatch" (prep ~expected_plan_identity:(String.make 64 '0') ());
  reject
    "workspace is not a plan field"
    (MP.of_yojson
       (match wire with
        | `Assoc xs -> `Assoc (("workspace", `String "/absent/workspace") :: xs)
        | _ -> assert false));
  let before = !calls in
  reject "unknown selection before elaboration" (prep ~profile:"missing" ());
  check "invalid selection no elaboration" (!calls = before);
  let reference = Target.Inputs.reference_cmos5l_6x4 in
  check
    "target settings changes identity"
    (not
       (String.equal
          (MP.plan_identity plan)
          (identity_of
             (prep
                ~inputs:
                  { reference with
                    constraints = { reference.constraints with max_fanout = 17 }
                  }
                ()))));
  check
    "catalog inventory affects bundle"
    (not
       (String.equal (MP.plan_identity plan) (identity_of (prep ~catalog_inputs:[] ()))));
  print_endline
    (Yojson.Safe.to_string
       (`Assoc
         [ "checks", `Int !checks
         ; "plan", wire
         ; "list", Flow.Spec.list_to_yojson c
         ; ( "canonical_probe"
           , `String (ok (J.canonical (`Assoc [ "z", `Float 1.25; "a", `String "λ" ]))) )
         ]))
;;
