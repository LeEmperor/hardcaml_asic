module U = Unix
open! Core
open Hardcaml
open Hardcaml_asic
module H = Hardware_variant
module J = Flow.Plan_json
let ok = Or_error.ok_exn
let checks = ref 0
let check label b = incr checks; if not b then failwith label
let reject label r = check label (Or_error.is_error r)
let calls = ref 0
module Design = struct
  module I = Tt_cmos5l.I
  module O = Tt_cmos5l.O
  let name = "tt_um_variant_fixture"
  let create _ (i : _ I.t) =
    incr calls;
    { O.uo_out = Signal.reg (Signal.Reg_spec.create ~clock:i.clk ()) i.ui_in
    ; uio_out=Signal.zero 8;uio_oe=Signal.zero 8 }
end
let project () = Project.create ~name:"variant_fixture"
  ~metadata:{title="Variant";author="Test";description="Binding fixture"}
  ~design:(module Design)
  ~target:{harness=Tiny_tapeout {tiles=T6x4};technology=Technology.ihp_sg13cmos5l}
  ~flow:(Flow.librelane ~overrides:(Tt_cmos5l.overrides ()) Synthesis)
  ~clocks:[{Clock.port="clk";period=Time_float.Span.of_ns 20.}]
  ~pinout:(List.concat_map [Pinout.Bank.Ui;Uo;Uio] ~f:(fun bank ->
    List.init 8 ~f:(fun bit -> {Pinout.bank;bit;description="test"})))
  ~source_inputs:["dune-project"] ~policy:(ok (Resource_policy.create ~default:Flops [])) () |> ok
let variant n =
  let p = H.Parameter.create ~key:"depth" ~kind:(Integer {minimum=128;maximum=256}) |> ok in
  let schema = H.Schema.create ~design_id:"fixture" ~schema_id:"fixture.v1" ~parameters:[p] |> ok in
  H.create ~schema ~assignments:["depth",Int n] |> ok
let same a b = String.equal (H.identity a) (H.identity b)
let fields = function `Assoc xs -> xs | _ -> assert false
let set j key value = `Assoc (List.map (fields j) ~f:(fun (k,v) -> k,if String.equal k key then value else v))
let remove j key = `Assoc (List.filter (fields j) ~f:(fun (k,_) -> not (String.equal k key)))
let resign_manifest j =
  let payload = remove j "identity" in
  match payload with `Assoc xs -> `Assoc (("identity",`String (J.sha256 (Yojson.Safe.to_string payload)))::xs) | _ -> assert false
let catalog () =
  let m = Flow.Methodology.create ~id:"standard" ~label:"Standard" ~description:"Test"
    ~backend_recipe:Librelane_classic_v1 ~endpoints:[Synthesis]
    ~configurable:Flow.Parameter.Key.all ~defaults:[] |> ok in
  let profile id strategy = Flow.Profile.create ~id ~label:id ~description:"Test"
    ~assignments:[Flow.Parameter.synth_strategy strategy;Flow.Parameter.synth_abc_buffering false] |> ok in
  let e = Flow.Catalog.Entry.create ~methodology:m ~profiles:[profile "area" Area_0;profile "delay" Delay_1]
    ~default_profile:"area" |> ok in
  Flow.Catalog.create ~entries:[e] ~default_flow:"standard" ~default_profile:"area" |> ok
let () =
  (* Read only the actual checkout. No fixture Git mutations, writes, publication,
     EDA or toolchain/PDK probes are needed by this suite. *)
  let ch = U.open_process_args_in "git" [|"git";"rev-parse";"--show-toplevel"|] in
  let root = Stdlib.input_line ch in
  check "locate source root" (Poly.equal (U.close_process_in ch) (U.WEXITED 0));
  let v = variant 128 and w = variant 256 in
  let plain = project () in
  let factory_calls = ref 0 in
  let bound = Project.of_variant ~variant:v ~create:(fun supplied ->
    incr factory_calls;check "same assignment object" (phys_equal supplied v);Ok plain) |> ok in
  check "factory once/no elaboration" (!factory_calls=1 && !calls=0);
  check "plain unchanged" (Option.is_none (Project.hardware_variant plain));
  check "attached" (same v (Option.value_exn (Project.hardware_variant bound)));
  reject "factory result failure" (Project.of_variant ~variant:v ~create:(fun _ -> Or_error.error_string "factory failure"));
  reject "factory exception" (Project.of_variant ~variant:v ~create:(fun _ -> failwith "factory exception"));
  reject "repeated attachment" (Project.of_variant ~variant:v ~create:(fun _ -> Ok bound));
  reject "conflicting attachment" (Project.of_variant ~variant:w ~create:(fun _ -> Ok bound));
  ignore (Project.of_variant ~variant:v ~create:(fun _ -> Ok plain) |> ok : Project.t);
  let plain_description = Project.describe plain in
  let bound_description = Project.describe bound in
  let stripped = match bound_description with Sexp.List xs -> Sexp.List (List.filter xs ~f:(function
    | Sexp.List (Sexp.Atom "hardware_variant"::_) -> false | _ -> true)) | _ -> assert false in
  check "absent describe unchanged" (Sexp.equal plain_description stripped);
  check "describe association" (String.is_substring (Sexp.to_string bound_description) ~substring:(H.identity v));
  List.iter [Elaboration.Mode.Implementation;Simulation] ~f:(fun mode ->
    let e = Project.elaborate bound ~mode |> ok in
    check "same immutable elaborated assignment" (phys_equal v (Option.value_exn (Elaborated_project.hardware_variant e))));
  calls := 0;
  let cat = catalog () in
  let methodology = Flow.Catalog.resolve cat ~endpoint:Synthesis () |> ok in
  let rendered = Project.render_result ~methodology ~include_simulation:false bound ~source_root:root |> ok in
  check "one implementation render" (!calls=1);
  let bundle = Project.Rendered.bundle rendered in
  let manifest = Bundle.manifest bundle in
  check "manifest association" (J.equal (J.get manifest "hardware_variant") (H.to_yojson v));
  ignore (Bundle.verify_manifest_identity manifest |> ok : unit);
  let plan = Methodology_plan.of_rendered rendered |> ok in
  check "plan no rerender" (!calls=1);
  check "plan association" (same v (Option.value_exn (Methodology_plan.hardware_variant plan)));
  let decoded = Methodology_plan.of_string (Methodology_plan.to_string plan) |> ok in
  check "frozen plan roundtrip" (String.equal (Methodology_plan.plan_identity plan) (Methodology_plan.plan_identity decoded));
  check "decoded declaration" (same v (Option.value_exn (Methodology_plan.hardware_variant decoded)));
  let again = Project.render_result ~methodology ~include_simulation:false bound ~source_root:root |> ok in
  check "deterministic bundle" (String.equal (Bundle.identity bundle) (Bundle.identity (Project.Rendered.bundle again)));
  let legacy_rendered = Project.render_result ~methodology ~include_simulation:false plain ~source_root:root |> ok in
  let legacy = Project.Rendered.bundle legacy_rendered in
  let legacy_plan = Methodology_plan.of_rendered legacy_rendered |> ok in
  check "historical None" (Option.is_none (Methodology_plan.hardware_variant legacy_plan));
  ignore (Methodology_plan.of_string (Methodology_plan.to_string legacy_plan) |> ok : Methodology_plan.t);
  let stripped_manifest = resign_manifest (remove manifest "hardware_variant") in
  check "absent manifest exact legacy bytes/identity" (Poly.equal stripped_manifest (Bundle.manifest legacy));
  List.iter (Bundle.paths bundle) ~f:(fun path -> if not (String.equal path "manifest.json") then
    check "metadata does not replace actual files" (Option.equal String.equal (Bundle.file bundle path) (Bundle.file legacy path)));
  let bad = set manifest "hardware_variant" (set (H.to_yojson v) "identity" (`String (String.make 64 '0'))) |> resign_manifest in
  reject "rehashed inner corruption" (Bundle.verify_manifest_identity bad);
  reject "present null" (Bundle.verify_manifest_identity (set manifest "hardware_variant" `Null |> resign_manifest));
  let substitute_manifest m =
    let wire = Methodology_plan.to_yojson plan in
    let wire = set wire "bundle_manifest" (`String (Yojson.Safe.to_string m))
      |> fun j -> set j "bundle_identity" (J.get m "identity") in
    let payload = remove wire "plan_identity" in
    set wire "plan_identity" (`String (J.identity ~contract:"hardcaml-asic.plan-identity" payload |> ok)) in
  reject "plan coherently rehashed invalid declaration" (Methodology_plan.of_yojson (substitute_manifest bad));
  reject "plan coherently rehashed null declaration" (Methodology_plan.of_yojson
    (substitute_manifest (set manifest "hardware_variant" `Null |> resign_manifest)));
  let substituted = set manifest "hardware_variant" (H.to_yojson w) |> resign_manifest in
  let substituted_plan = Methodology_plan.of_yojson (substitute_manifest substituted) |> ok in
  check "valid different declaration is not hardware attestation" (same w
    (Option.value_exn (Methodology_plan.hardware_variant substituted_plan)));
  (* Simulation/implementation may not silently carry different declarations. *)
  let other = Project.of_variant ~variant:w ~create:(fun _ -> Ok plain) |> ok in
  let sim = Project.elaborate other ~mode:Simulation |> ok in
  reject "simulation variant mismatch" (Bundle.render ~simulation_project:sim ~source_root:root
    ~input_paths:["dune-project"] (Project.Rendered.resolution rendered));
  let legacy_sim = Project.elaborate plain ~mode:Simulation |> ok in
  reject "simulation absence mismatch" (Bundle.render ~simulation_project:legacy_sim ~source_root:root
    ~input_paths:["dune-project"] (Project.Rendered.resolution rendered));
  let with_sim = Project.render_result ~methodology bound ~source_root:root |> ok in
  ignore (Methodology_plan.of_rendered with_sim |> ok : Methodology_plan.t);
  let prepared = match Project.prepare_resources ~methodology bound ~source_root:root with
    | Ok p -> p | Error f -> failwith (Yojson.Safe.to_string (Resource_preparation.Failure.to_json f)) in
  check "preparation includes assignment" (String.is_substring (Resource_preparation.to_string prepared) ~substring:(H.identity v));
  let prepare p = match Project.prepare_resources ~methodology p ~source_root:root with
    | Ok p -> p | Error _ -> failwith "preparation failed" in
  let legacy_prepared = prepare plain and other_prepared = prepare other in
  check "preparation config identity covers declaration" (not (String.equal
    (Resource_preparation.configuration_identity prepared) (Resource_preparation.configuration_identity other_prepared)));
  check "ignored parameter may have equal circuit" (String.equal
    (Resource_preparation.circuit_identity prepared) (Resource_preparation.circuit_identity other_prepared));
  check "legacy preparation differs only declaration/config" (String.equal
    (Resource_preparation.circuit_identity prepared) (Resource_preparation.circuit_identity legacy_prepared));
  let expected = Methodology_plan.plan_identity plan in
  reject "changed declaration stale plan" (Methodology_plan.prepare ~catalog:cat ~endpoint:Synthesis
    ~expected_plan_identity:expected ~include_simulation:false other ~source_root:root);
  let selected = Flow.Selection.create ~flow:"standard" ~profile:"delay" () |> ok in
  let delay = Methodology_plan.prepare ~catalog:cat ~selection:selected ~endpoint:Synthesis
    ~include_simulation:false bound ~source_root:root |> ok |> Methodology_plan.Prepared.plan in
  check "profile change separate from hardware" (same v (Option.value_exn (Methodology_plan.hardware_variant delay)));
  check "profile changes plan" (not (String.equal expected (Methodology_plan.plan_identity delay)));
  printf "hardware variant integration: %d checks passed (no writes/EDA)\n" !checks
