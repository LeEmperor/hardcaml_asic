(* Fail-closed execution capability for the public exact SRAM synthesis bundle.
   PDK I/O remains in preflight; this module only validates declared JSON. *)
module J = Identity_json
let fail s = invalid_arg ("SRAM bundle: " ^ s)
let get j k = match j with J.Object xs -> Option.value (List.assoc_opt k xs) ~default:J.null | _ -> fail "expected object"
let text = function J.String x -> x | _ -> fail "expected string"
let array = function J.Array xs -> xs | _ -> fail "expected array"
let obj xs = match J.object_ xs with Ok j -> j | Error _ -> fail "invalid object"
let s x = match J.string x with Ok j -> j | Error _ -> fail "invalid string"
let strings xs = J.array (List.map s xs)
let stock = "RM_IHPSG13_1P_256x16_c2_bm_bist"
let stub = "macros/" ^ stock ^ ".blackbox.v"
let prefix = "pdk_dir::libs.ref/sg13cmos5l_sram/"
let corners =
  ["nom_fast_1p32V_m40C", "fast_1p32V_m55C";
   "nom_slow_1p08V_125C", "slow_1p08V_125C";
   "nom_typ_1p20V_25C", "typ_1p20V_25C"]
let path directory suffix = prefix ^ directory ^ "/" ^ stock ^ suffix
let active manifest = match manifest with
  | J.Object xs -> List.mem_assoc "macro_contract" xs
  | _ -> false
let check condition message = if not condition then fail message

(* The resource inventory is the independent elaboration record, not the macro
   contract's own assertion. Parse its sexps structurally; whitespace is irrelevant. *)
let sexp j = try Core.Sexp.of_string (text j) with _ -> fail "invalid resource inventory sexp"
let sexp_field key = function
  | Core.Sexp.List fields ->
    (match List.filter_map (function
       | Core.Sexp.List [Core.Sexp.Atom k;value] when k=key -> Some value
       | _ -> None) fields with
     | [value] -> value | _ -> fail ("missing or duplicate resource field: " ^ key))
  | _ -> fail "invalid resource inventory record"

let registered_macros manifest =
  let module R = Hardcaml_asic.Resource in
  let resources = array (get manifest "resources") in
  let ids = List.map (fun r -> text (get r "id")) resources in
  check (List.length ids=List.length (List.sort_uniq String.compare ids)) "duplicate registered resource";
  List.filter_map (fun r ->
    match sexp_field "implementation" (sexp (get r "selection")) with
    | Core.Sexp.Atom "Flops" -> None
    | Core.Sexp.List [Core.Sexp.Atom "Macro"; Core.Sexp.Atom name] ->
      check (name=stock) "unsupported registered macro";
      check (Core.Sexp.equal (sexp (get r "request"))
        (R.Request.sexp_of_t (R.Request.single_port_ram ~width:16 ~depth:256 ~read_latency:1)))
        "registered macro requires exact256x16 request";
      check (sexp (get r "elaborated_as") = Core.Sexp.Atom "Selected_implementation")
        "registered macro is not the elaborated implementation";
      let id = text (get r "id") in
      let canonical = try R.Id.of_string_exn id |> R.Id.rtl_instance_name
        with _ -> fail "invalid registered macro resource ID" in
      Some (id, canonical)
    | _ -> fail "invalid registered resource implementation") resources

let validate manifest config =
  let macros = get config "MACROS" in
  if not (active manifest) then (
    check (macros=J.null || macros=obj []) "MACROS require a public macro contract";
    []) else (
    let contract = get manifest "macro_contract" in
    check (get contract "schema_version" = (match J.integer "1" with Ok j -> j | Error _ -> assert false)) "unsupported contract schema";
    check (get contract "execution" = s "synthesis_only" && get manifest "operation" = s "Synthesis")
      "only synthesis is supported; physical power/KLayout/CDL gates are unverified";
    check (get manifest "flow_configuration" = config) "configuration differs from manifest";
    check (get config "PDK" = s "ihp-sg13cmos5l") "unsupported PDK";
    check (get config "STA_CORNERS" = strings (List.map fst corners)) "exact STA corner set required";
    check (get config "DEFAULT_CORNER" = s "nom_typ_1p20V_25C") "unexpected default corner";
    check (get config "EXTRA_VERILOG_MODELS" = strings ["dir::../" ^ stub]) "generated synthesis stub required";
    check (get contract "blackbox_sources" = strings [stub]) "unexpected blackbox inventory";
    let macro = get macros stock in
    check (match macros with J.Object [name,_] -> name=stock | _ -> false) "only stock exact256x16 is supported";
    check (match macro with J.Object xs -> List.map fst xs = ["gds";"instances";"lef";"lib";"spice"] | _ -> false)
      "unexpected macro configuration fields";
    List.iter (fun (key,value) -> check (get macro key=value) ("incorrect macro " ^ key))
      ["lef",strings [path "lef" ".lef"];"gds",strings [path "gds" ".gds"];
       "spice",strings [path "cdl" ".cdl"];
       "lib",obj (List.map (fun (corner,suffix) -> corner,strings [path "lib" ("_"^suffix^".lib")]) corners)];
    let entries = array (get contract "macros") in
    check (entries<>[]) "empty macro inventory";
    let registered = registered_macros manifest in
    let resources = List.map (fun m -> text (get m "resource")) entries in
    check (List.sort String.compare resources = List.sort String.compare (List.map fst registered))
      "macro resources differ from registered exact-SRAM inventory";
    let instances = List.map (fun m -> text (get m "instance")) entries in
    check (List.length (List.sort_uniq String.compare instances)=List.length entries) "duplicate instance";
    List.iter (fun m ->
      let resource = text (get m "resource") in
      check (get m "instance"=s (List.assoc resource registered)) "macro instance differs from canonical resource encoding") entries;
    let placements = List.filter_map (fun m ->
      let intent = get m "physical_intent" in
      if intent=J.null then None else (
        check (get intent "orientation"=s "R0") "unsupported macro intent orientation";
        let location = get intent "location_um" in
        check (match location with J.Array [J.Float x;J.Float y] -> Float.is_finite x && Float.is_finite y
          | _ -> false) "invalid macro intent location";
        Some (text (get m "instance"),obj ["location",location;"orientation",s "R0"]))) entries in
    check (get macro "instances"=obj placements) "configuration placements differ from declared macro intent inventory";
    let references = List.concat_map (fun m ->
      check (get m "module"=s stock) "unknown module";
      let refs = List.map (fun c -> text (get c "role"),text (get c "reference")) (array (get m "collateral")) in
      check (List.length refs=11) "unexpected collateral roles";
      let require role reference = check (List.filter (fun (r,_) -> r=role) refs = [role,reference]) ("incorrect collateral " ^ role) in
      require "Black_box" ("generated:" ^ stock ^ ".blackbox.v");
      require "Physical_abstract" (path "lef" ".lef");
      require "Physical_layout" (path "gds" ".gds");
      require "Spice_netlist" (path "cdl" ".cdl");
      List.iter (fun (corner,suffix) ->
        let tag = if String.starts_with ~prefix:"nom_fast" corner then "fast"
          else if String.starts_with ~prefix:"nom_slow" corner then "slow" else "typ" in
        require ("(Timing_model (corner " ^ tag ^ "))") (path "lib" ("_"^suffix^".lib"))) corners;
      List.iter (fun role ->
        let actual = List.filter_map (fun (r,p) -> if r=role then Some p else None) refs |> List.sort String.compare in
        let expected = [path "verilog" ".v";prefix ^ "verilog/RM_IHPSG13_1P_core_behavioral_bm_bist.v"] |> List.sort String.compare in
        check (actual=expected) ("incomplete vendor model set: " ^ role)) ["Simulation_model";"Timed_simulation_model"];
      List.filter_map (fun (role,reference) ->
        if String.starts_with ~prefix:"generated:" reference then None else (
          check (String.starts_with ~prefix reference) "unsupported collateral reference";
          Some (role,reference))) refs) entries in
    let models = [path "verilog" ".v"; prefix ^ "verilog/RM_IHPSG13_1P_core_behavioral_bm_bist.v"] |> List.sort String.compare in
    let sim = get contract "implementation_simulation" in
    check (get sim "defines"=strings ["FUNCTIONAL"] && get sim "models"=strings models)
      "functional implementation model set required";
    List.sort_uniq compare references)

let require_synthesis manifest =
  if active manifest then fail "physical execution and checkpoint continuation are unsupported; only fresh synthesis is supported"
