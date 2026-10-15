(* Deliberately links only the public flow_domain library: no hardware, main
   project library, execution services, Python or installed EDA toolchain. *)
open! Core
open Hardcaml_asic_flow_domain

let checks = ref 0
let check name condition =
  Int.incr checks;
  if not condition then failwith ("Failed: " ^ name)
;;
let ok = Or_error.ok_exn
let rejects name fragment result =
  check name (match result with
    | Ok _ -> false
    | Error e -> String.is_substring (Error.to_string_hum e) ~substring:fragment)
;;
let strategy = Parameter.synth_strategy
let buffering = Parameter.synth_abc_buffering
let profile ?(label = "Display label") id assignments =
  Profile.create ~id ~label ~description:"Profile description" ~assignments
;;
let methodology ?(label = "Display label") ?(endpoints = Stage_id.all)
  ?(configurable = Parameter.Key.all) ?(defaults = []) id =
  Methodology.create ~id ~label ~description:"Flow description"
    ~backend_recipe:Librelane_classic_v1 ~endpoints ~configurable ~defaults
;;
let entry m profiles default_profile =
  Catalog.Entry.create ~methodology:m ~profiles ~default_profile
;;
let catalog entries default_flow default_profile =
  Catalog.create ~entries ~default_flow ~default_profile
;;
let resolve ?selection ?request ?(endpoint = Stage_id.Signoff) c =
  Catalog.resolve ?selection ?request c ~endpoint ()
;;
let selection ?flow ?profile () = ok (Selection.create ?flow ?profile ())
let selected r =
  Selection.Id.to_string (Methodology.id (Catalog.Entry.methodology (Catalog.entry r))),
  Selection.Id.to_string (Profile.id (Catalog.profile r))
;;
let parameter r key =
  List.find_exn (Catalog.parameters r) ~f:(fun p ->
    Parameter.Key.equal key (Parameter.assignment_key (Parameter.assignment (Parameter.winning p))))
;;
let value p = Parameter.assignment_value (Parameter.assignment (Parameter.winning p))
let key_names assignments = List.map assignments ~f:(fun a -> Parameter.Key.to_string (Parameter.assignment_key a))

let () =
  List.iter [ "standard"; "flow-1"; "a_b2" ] ~f:(fun id ->
    check ("valid ID " ^ id) (String.equal id (Selection.Id.to_string (ok (Selection.Id.create id)))));
  List.iter [ ""; "Upper"; "1first"; "with space"; " a"; "a "; "a.b"; "a/b"; "é" ] ~f:(fun id ->
    rejects ("invalid ID " ^ id) "Invalid flow/profile ID" (Selection.Id.create id));
  rejects "profile requires flow" "requires an explicit flow" (Selection.create ~profile:"balanced" ());
  rejects "selection validates flow" "Invalid flow/profile ID" (Selection.create ~flow:"BAD" ());
  rejects "selection validates profile" "Invalid flow/profile ID" (Selection.create ~flow:"good" ~profile:"BAD" ());
  check "supported recipe roundtrip"
    (Methodology.Backend_recipe.equal Librelane_classic_v1
       (ok (Methodology.Backend_recipe.of_string "librelane.classic.v1")));
  List.iter [ "classic"; "librelane.classic.v2"; " librelane.classic.v1" ] ~f:(fun name ->
    rejects "unsupported recipe" "Unsupported backend recipe" (Methodology.Backend_recipe.of_string name));
  List.iter Parameter.Strategy.all ~f:(fun v ->
    let spelling = Parameter.Strategy.to_string v in
    check ("strategy roundtrip " ^ spelling)
      (Parameter.equal_assignment (strategy v) (ok (Parameter.of_string_value ~key:"SYNTH_STRATEGY" spelling))));
  List.iter [ "AREA0"; "AREA 4"; "DELAY 5"; "AREA  0"; "area 0"; " AREA 0"; "DELAY 0 "; "0"; "true" ] ~f:(fun s ->
    rejects ("strict enum " ^ s) "Invalid SYNTH_STRATEGY" (Parameter.of_string_value ~key:"SYNTH_STRATEGY" s));
  List.iter [ "SYNTH_BUFFERING"; "DIE_AREA"; "PL_TARGET_DENSITY_PCT"; "synth_strategy"; "SYNTH_STRATEGY " ] ~f:(fun key ->
    rejects "unknown string parameter" "Unsupported parameter" (Parameter.of_string_value ~key "AREA 0");
    rejects "unknown bool parameter" "Unsupported parameter" (Parameter.of_bool_value ~key false));
  List.iter [ "true"; "false"; "0"; "1" ] ~f:(fun value ->
    rejects "string/number spelling cannot become bool" "requires a boolean scalar"
      (Parameter.of_string_value ~key:"SYNTH_ABC_BUFFERING" value));
  rejects "bool cannot become strategy" "requires an enum string"
    (Parameter.of_bool_value ~key:"SYNTH_STRATEGY" true);
  List.iter [ false; true ] ~f:(fun b ->
    check "boolean scalar accepted" (Parameter.equal_assignment (buffering b)
      (ok (Parameter.of_bool_value ~key:"SYNTH_ABC_BUFFERING" b))));
  List.iter [ `Int 0; `Int 1; `Float 0.; `Float 1.; `Float Float.nan; `Null ] ~f:(fun scalar ->
    List.iter [ "SYNTH_ABC_BUFFERING"; "SYNTH_STRATEGY" ] ~f:(fun key ->
      rejects "numeric/null scalar rejected" "does not accept numeric or null scalars"
        (Parameter.of_scalar ~key scalar)));
  rejects "numeric scalar still validates key" "Unsupported parameter" (Parameter.of_scalar ~key:"UNKNOWN" (`Int 1));
  check "scalar boolean routes through typed constructor"
    (Parameter.equal_assignment (buffering false) (ok (Parameter.of_scalar ~key:"SYNTH_ABC_BUFFERING" (`Bool false))));
  check "scalar enum routes through typed constructor"
    (Parameter.equal_assignment (strategy Area_0) (ok (Parameter.of_scalar ~key:"SYNTH_STRATEGY" (`String "AREA 0"))));
  check "descriptor canonical key order"
    (List.equal String.equal
      (List.map Parameter.descriptors ~f:(fun d -> Parameter.Key.to_string (Parameter.key d)))
      [ "SYNTH_ABC_BUFFERING"; "SYNTH_STRATEGY" ]);
  let ds = Parameter.descriptor Synth_strategy in
  let db = Parameter.descriptor Synth_abc_buffering in
  check "strategy descriptor exact enum" (List.length (Parameter.allowed_values ds) = 9);
  check "strategy descriptor type" (Parameter.equal_value_type Enum (Parameter.value_type ds));
  check "boolean descriptor type" (Parameter.equal_value_type Boolean (Parameter.value_type db));
  check "backend strategy default" (Parameter.equal_value (Strategy Area_0) (Parameter.backend_default ds));
  check "backend buffering default false" (Parameter.equal_value (Bool false) (Parameter.backend_default db));
  List.iter Parameter.descriptors ~f:(fun d ->
    check "unitless" (Option.is_none (Parameter.units d));
    check "semantic meaning present" (not (String.is_empty (Parameter.meaning d)));
    check "backend consumer versioned" (String.is_substring (Parameter.backend_consumer d) ~substring:"3.1.0.dev3"));
  rejects "profile ID validation" "Invalid flow/profile ID" (profile "Bad" []);
  rejects "profile label validation" "label must be nonblank" (profile ~label:" \n" "good" []);
  rejects "flow ID validation" "Invalid flow/profile ID" (methodology "Bad");
  rejects "flow label validation" "label must be nonblank" (methodology ~label:" " "good");
  rejects "profile duplicate same value" "Duplicate configurable parameter"
    (profile "duplicate" [ buffering false; buffering false ]);
  rejects "profile duplicate different value" "Duplicate configurable parameter"
    (profile "duplicate" [ buffering false; buffering true ]);
  rejects "duplicate configurable key" "Duplicate configurable parameter"
    (methodology ~configurable:[ Synth_strategy; Synth_strategy ] "duplicate");
  rejects "methodology duplicate defaults" "Duplicate configurable parameter"
    (methodology ~defaults:[ strategy Area_0; strategy Delay_0 ] "duplicate");
  rejects "methodology default not configurable" "not configurable"
    (methodology ~configurable:[] ~defaults:[ buffering true ] "fixed");
  rejects "empty endpoints" "at least one endpoint" (methodology ~endpoints:[] "empty");
  rejects "duplicate endpoints" "Duplicate methodology endpoint"
    (methodology ~endpoints:[ Synthesis; Synthesis ] "duplicate");
  let m = ok (methodology ~defaults:[ strategy Area_1; buffering false ] "standard") in
  check "fresh only" (Methodology.equal_input Fresh (Methodology.input m));
  List.iteri Stage_id.all ~f:(fun i endpoint ->
    check "fixed full prefix" (List.equal Stage_id.equal (List.take Stage_id.all (i + 1)) (ok (Methodology.stages m ~endpoint))));
  let restricted = ok (methodology ~endpoints:[ Signoff; Synthesis ] "restricted") in
  check "endpoints canonical physical order" (List.equal Stage_id.equal (Methodology.endpoints restricted) [ Synthesis; Signoff ]);
  rejects "restricted endpoint cannot execute" "not supported" (Methodology.stages restricted ~endpoint:Placement);
  let balanced = ok (profile "balanced" [ strategy Area_2 ]) in
  let fast = ok (profile "fast" [ buffering true; strategy Delay_4 ]) in
  let neutral = ok (profile "neutral" []) in
  rejects "duplicate profiles" "Duplicate profile ID" (entry m [ balanced; balanced ] "balanced");
  rejects "missing per-flow default" "Unknown per-flow default" (entry m [ balanced ] "missing");
  rejects "empty profile list" "Unknown per-flow default" (entry m [] "missing");
  rejects "invalid per-flow default ID" "Invalid flow/profile ID" (entry m [ balanced ] "BAD");
  let fixed = ok (methodology ~configurable:[] "fixed") in
  rejects "profile gated at entry even if not selected" "not configurable"
    (entry fixed [ neutral; balanced ] "neutral");
  let e = ok (entry m [ fast; neutral; balanced ] "balanced") in
  let e_reordered = ok (entry m [ balanced; fast; neutral ] "balanced") in
  let e_restricted = ok (entry restricted [ balanced; neutral ] "neutral") in
  check "profiles canonical ID order" (List.equal String.equal
    (List.map (Catalog.Entry.profiles e) ~f:(fun p -> Selection.Id.to_string (Profile.id p)))
    [ "balanced"; "fast"; "neutral" ]);
  rejects "duplicate flows" "Duplicate flow ID" (catalog [ e; e ] "standard" "balanced");
  rejects "empty catalog" "Unknown flow ID" (catalog [] "standard" "balanced");
  rejects "dangling catalog flow" "Unknown flow ID" (catalog [ e ] "missing" "balanced");
  rejects "dangling catalog profile" "Unknown profile ID" (catalog [ e ] "standard" "missing");
  rejects "catalog profile must belong to flow" "Unknown profile ID"
    (catalog [ e; e_restricted ] "restricted" "fast");
  let c = ok (catalog [ e; e_restricted ] "standard" "fast") in
  let permuted = ok (catalog [ e_restricted; e_reordered ] "standard" "fast") in
  check "entries canonical ID order" (List.equal String.equal
    (List.map (Catalog.entries c) ~f:(fun e -> Selection.Id.to_string (Methodology.id (Catalog.Entry.methodology e))))
    [ "restricted"; "standard" ]);
  let default_result = ok (resolve c) in
  check "resolved endpoint retained" (Stage_id.equal Signoff (Catalog.endpoint default_result));
  check "resolved stages retained" (List.equal Stage_id.equal Stage_id.all (Catalog.stages default_result));
  check "resolved shorter endpoint is complete prefix"
    (List.equal Stage_id.equal [ Synthesis; Floorplan; Placement ]
      (Catalog.stages (ok (resolve ~endpoint:Placement c))));
  check "no selection uses catalog profile not per-flow default" (Poly.equal (selected default_result) ("standard", "fast"));
  check "explicit empty selection uses catalog default" (Poly.equal (selected (ok (resolve ~selection:Selection.default c))) ("standard", "fast"));
  let flow_default = ok (resolve ~selection:(selection ~flow:"standard" ()) c) in
  check "explicit flow uses per-flow default" (Poly.equal (selected flow_default) ("standard", "balanced"));
  let selected_neutral = selection ~flow:"standard" ~profile:"neutral" () in
  check "explicit profile honored" (Poly.equal (selected (ok (resolve ~selection:selected_neutral c))) ("standard", "neutral"));
  rejects "unknown selected flow no fallback" "Unknown flow ID" (resolve ~selection:(selection ~flow:"removed" ()) c);
  rejects "unknown selected profile no fallback" "Unknown profile ID" (resolve ~selection:(selection ~flow:"standard" ~profile:"removed" ()) c);
  rejects "selected profile scoped to flow" "Unknown profile ID" (resolve ~selection:(selection ~flow:"restricted" ~profile:"fast" ()) c);
  rejects "catalog endpoint restriction" "not supported" (resolve ~selection:(selection ~flow:"restricted" ()) ~endpoint:Placement c);
  rejects "request duplicates" "Request assignments" (resolve ~request:[ buffering false; buffering true ] c);
  let fixed_entry = ok (entry fixed [ neutral ] "neutral") in
  let fixed_catalog = ok (catalog [ fixed_entry ] "fixed" "neutral") in
  rejects "request not configurable" "not configurable" (resolve ~request:[ buffering true ] fixed_catalog);
  let r = ok (resolve ~request:[ strategy Delay_2 ] c) in
  let s = parameter r Synth_strategy in
  check "request wins" (Parameter.equal_value (Strategy Delay_2) (value s));
  check "winning request origin" (Parameter.equal_origin Request (Parameter.origin (Parameter.winning s)));
  check "overridden origins chronological" (List.equal Parameter.equal_origin
    (List.map (Parameter.overridden s) ~f:Parameter.origin) [ Methodology; Profile ]);
  check "overridden values retained" (List.equal Parameter.equal_assignment
    (List.map (Parameter.overridden s) ~f:Parameter.assignment) [ strategy Area_1; strategy Delay_4 ]);
  check "profile wins over methodology" (Parameter.equal_origin Profile
    (Parameter.origin (Parameter.winning (parameter r Synth_abc_buffering))));
  check "methodology wins when profile absent" (Parameter.equal_value (Strategy Area_1)
    (value (parameter (ok (resolve ~selection:selected_neutral c)) Synth_strategy)));
  check "all resolved parameters canonical key order" (List.equal String.equal
    (List.map (Catalog.parameters r) ~f:(fun p -> Parameter.Key.to_string (Parameter.assignment_key (Parameter.assignment (Parameter.winning p)))))
    [ "SYNTH_ABC_BUFFERING"; "SYNTH_STRATEGY" ]);
  let same = ok (resolve ~request:[ strategy Delay_4 ] c) in
  check "equal values still retain all origins" (List.length (Parameter.overridden (parameter same Synth_strategy)) = 2);
  check "backend defaults not invented" (List.is_empty (Catalog.parameters (ok (resolve fixed_catalog))));
  let empty_m = ok (methodology "empty") in
  let empty_c = ok (catalog [ ok (entry empty_m [ neutral ] "neutral") ] "empty" "neutral") in
  check "configurable but unspecified stays unspecified" (List.is_empty (Catalog.parameters (ok (resolve empty_c))));
  let request_only = parameter (ok (resolve ~request:[ buffering true ] empty_c)) Synth_abc_buffering in
  check "request-only value has no synthetic backend contribution"
    (List.is_empty (Parameter.overridden request_only)
     && Parameter.equal_origin Request (Parameter.origin (Parameter.winning request_only)));
  rejects "pure resolver checks duplicate methodology layer" "Methodology defaults"
    (Parameter.resolve ~configurable:Parameter.Key.all
      ~methodology:[ buffering false; buffering false ] ~profile:[] ~request:[]);
  rejects "pure resolver checks duplicate profile layer" "Profile assignments"
    (Parameter.resolve ~configurable:Parameter.Key.all
      ~methodology:[] ~profile:[ buffering false; buffering false ] ~request:[]);
  check "full selected declaration retained" (List.length (Catalog.entries (Catalog.declaration r)) = 2
    && List.length (Catalog.Entry.profiles (Catalog.entry r)) = 3
    && String.equal "Flow description" (Methodology.description (Catalog.Entry.methodology (Catalog.entry r)))
    && String.equal "Profile description" (Profile.description (Catalog.profile r)));
  let projection c =
    let r = ok (resolve ~request:[ strategy Delay_2; buffering false ] c) in
    selected r,
    List.map (Catalog.parameters r) ~f:(fun p ->
      Parameter.assignment (Parameter.winning p),
      Parameter.origin (Parameter.winning p),
      List.map (Parameter.overridden p) ~f:(fun x -> Parameter.assignment x, Parameter.origin x))
  in
  check "permuted declarations same canonical resolution" (Poly.equal (projection c) (projection permuted));
  check "methodology defaults canonical" (List.equal String.equal (key_names (Methodology.defaults m))
    [ "SYNTH_ABC_BUFFERING"; "SYNTH_STRATEGY" ]);
  check "profile assignments canonical" (List.equal String.equal (key_names (Profile.assignments fast))
    [ "SYNTH_ABC_BUFFERING"; "SYNTH_STRATEGY" ]);
  let c_changed_default = ok (catalog [ e; e_restricted ] "restricted" "neutral") in
  check "new catalog default applied" (Poly.equal (selected (ok (resolve c_changed_default))) ("restricted", "neutral"));
  check "prior resolved selection immutable" (Poly.equal (selected default_result) ("standard", "fast"));
  check "prior declaration default immutable" (String.equal "standard"
    (Selection.Id.to_string (Option.value_exn (Selection.flow (Catalog.default (Catalog.declaration default_result))))));
  let replacement = ok (profile ~label:"Changed label" "fast" [ strategy Area_3 ]) in
  let independent = ok (catalog [ ok (entry m [ replacement ] "fast") ] "standard" "fast") in
  check "independent catalog same IDs different values" (Parameter.equal_value (Strategy Area_3)
    (value (parameter (ok (resolve independent)) Synth_strategy)));
  check "prior resolved value immutable" (Parameter.equal_value (Strategy Delay_4)
    (value (parameter default_result Synth_strategy)));
  check "prior full profile immutable" (String.equal "Display label" (Profile.label (Catalog.profile default_result)));
  printf "flow_domain catalog consumer: %d checks passed\n" !checks
;;
