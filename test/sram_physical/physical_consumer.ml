open! Core
open! Hardcaml
open! Hardcaml_asic

module Design = struct
  module I = Tt_cmos5l.I
  module O = Tt_cmos5l.O
  let name = "tt_um_physical_sram"
  let create context (i : _ I.t) =
    let ram name = Single_port_ram.create context ~name
      (Single_port_ram.Config.create_exn ~width:16 ~depth:256 ~read_latency:1)
      ~clock:i.clk ~enable:i.ena ~write_enable:i.rst_n ~address:i.ui_in
      ~write_data:(Signal.concat_msb [i.ui_in; i.uio_in]) in
    let a = ram "left" and b = ram "right" in
    { O.uo_out = Signal.sel_bottom a ~width:8
    ; uio_out = Signal.sel_bottom b ~width:8
    ; uio_oe = Signal.zero 8 }
end

let intent ?(halo = 2.) ?(y = 81.) name x =
  Macro_intent.tt_cmos5l_r0 ~resource:(Resource.Id.of_string_exn name)
    ~x_um:x ~y_um:y ~halo_um:halo ()
;;

let project ?(operation = Flow.Operation.Hardening)
    ?(macros = [intent "left" 40.; intent "right" 400.]) ?(overrides = []) () =
  Project.create ~name:"physical_sram_fixture"
    ~metadata:{title="Physical SRAM";author="test";description="Checked physical plan"}
    ~design:(module Design)
    ~target:{harness=Tiny_tapeout {tiles=T6x4};technology=Technology.ihp_sg13cmos5l}
    ~flow:(Flow.librelane ~macros ~overrides operation)
    ~clocks:[{port="clk";period=Time_float.Span.of_ns 20.}]
    ~pinout:(List.concat_map [Pinout.Bank.Ui; Uo; Uio] ~f:(fun bank ->
      List.init 8 ~f:(fun bit -> {Pinout.bank;bit;description="fixture"})))
    ~source_inputs:["lib/elaboration/bundle.ml"]
    ~policy:(Resource_policy.create ~default:Exact [] |> ok_exn) () |> ok_exn
;;

let resolve ?operation ?macros ?overrides () =
  Project.elaborate_for_flow (project ?operation ?macros ?overrides ())
;;

let error_contains result substring =
  match result with
  | Ok _ -> failwith ("expected rejection: " ^ substring)
  | Error e ->
    if not (String.is_substring (Error.to_string_hum e) ~substring)
    then failwith (Error.to_string_hum e)
;;

let check () =
  let resolved = resolve () |> ok_exn in
  assert (Option.is_some resolved.physical_plan);
  error_contains (resolve ~macros:[] ()) "complete macro placement intent";
  error_contains (resolve ~macros:[intent "left" 40.] ()) "complete macro placement intent";
  error_contains (resolve ~macros:[intent "left" 40.001; intent "right" 400.] ()) "manufacturing grid";
  error_contains (resolve ~macros:[intent ~halo:1. "left" 40.; intent ~halo:1. "right" 400.] ()) "at least 2";
  error_contains (resolve ~macros:[intent "left" 40.; intent ~halo:3. "right" 400.] ()) "common global";
  error_contains (resolve ~macros:[intent "left" 40.; intent "right" 200.] ()) "overlap";
  error_contains (resolve ~macros:[intent "left" 40.; intent "right" 1200.] ()) "target bounds";
  List.iter ["PDN_VWIDTH";"FP_PDN_VWIDTH";"RUN_KLAYOUT_DRC";"KLAYOUT_DRC_TECH_SCRIPT";
             "ERROR_ON_ILLEGAL_OVERLAPS";"ROUTING_OBSTRUCTIONS";
             "RUN_POST_GRT_DESIGN_REPAIR";"GRT_DESIGN_REPAIR_MAX_WIRE_LENGTH";
             "GLB_RESIZER_MAX_WIRE_LENGTH";"RSZ_CORNERS"] ~f:(fun key ->
    error_contains (resolve ~overrides:[{key;value=`Int 0;reason="negative physical bypass"}] ()) "conflict");
  let template = Tt_cmos5l.overrides ~without:["RUN_KLAYOUT_DRC";"FP_PDN_VPITCH";
      "FP_PDN_VWIDTH";"FP_PDN_MULTILAYER"] () in
  ignore (resolve ~overrides:template () |> ok_exn);
  let synthesis = resolve ~operation:Synthesis ~macros:[] ~overrides:(Tt_cmos5l.overrides ()) () |> ok_exn in
  assert (Option.is_none synthesis.physical_plan);
  let unaligned_synthesis = resolve ~operation:Synthesis
    ~macros:[intent ~halo:1. "left" 40.001] () |> ok_exn in
  assert (Option.is_none unaligned_synthesis.physical_plan)
;;

let () =
  check ();
  match Sys.get_argv () with
  | [|_; ("generate-pdn" | "generate-settings" as action); plan_path; output|] ->
    let module P = Elaboration.Macro_physical_plan in
    let open Yojson.Safe.Util in
    let original = Yojson.Safe.from_file plan_path in
    let number = function `Int x -> Float.of_int x | `Float x -> x | _ -> failwith "expected coordinate" in
    let entries = original |> member "macros" |> to_list |> List.map ~f:(fun m ->
      let resource = m |> member "resource" |> to_string |> Resource.Id.of_string_exn in
      let location = m |> member "location_um" |> to_list |> List.map ~f:number in
      let x_um, y_um = match location with [x;y] -> x,y | _ -> failwith "expected location pair" in
      { P.resource; instance = m |> member "instance" |> to_string
      ; name = m |> member "module" |> to_string
      ; intent = Macro_intent.tt_cmos5l_r0 ~resource ~x_um ~y_um
          ~halo_um:(m |> member "halo_um" |> number) () }) in
    let plan = P.create entries |> ok_exn in
    if not (Yojson.Safe.equal original (P.to_json plan)) then failwith "unsupported physical plan";
    let data = if String.equal action "generate-settings"
      then Yojson.Safe.pretty_to_string (`Assoc (P.settings plan)) ^ "\n"
      else List.Assoc.find_exn (P.files plan) ~equal:String.equal "physical/pdn.tcl" in
    Out_channel.write_all output ~data
  | [|_; root; output; mode|] ->
    let operation = if String.equal mode "physical" then Flow.Operation.Hardening else Synthesis in
    let p = project ~operation () in
    let a = Project.render_bundle p ~source_root:root |> ok_exn in
    let b = Project.render_bundle p ~source_root:root |> ok_exn in
    assert (String.equal (Bundle.identity a) (Bundle.identity b));
    Bundle.write a ~output_dir:output |> ok_exn
  | _ -> failwith "ROOT OUTPUT physical|synthesis"
