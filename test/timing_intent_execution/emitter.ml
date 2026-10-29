open! Core
open! Hardcaml
open! Hardcaml_asic
let () =
  let legacy=Array.length Stdlib.Sys.argv>2 && String.equal Stdlib.Sys.argv.(2) "legacy" in
  let profile_id=if Array.length Stdlib.Sys.argv>2 && String.equal Stdlib.Sys.argv.(2) "alternative" then "alternative" else "area" in
  let first=Timing.Stage.create ~id:"rx0" ~chain:"rx" ~index:0 in
  let second=Timing.Stage.create ~id:"rx1" ~chain:"rx" ~index:1 in
  let timing=if legacy then Timing.empty else Timing.create ~stages:[first;second] ~exceptions:[
    Timing.Exception.async_capture ~id:"capture" ~reason:"fixture external capture"
      ~source:(Timing.Port.input "ena") ~first_stage:first] () in
  let module Design=struct
    module I=Tt_cmos5l.I
    module O=Tt_cmos5l.O
    let name="tt_um_pt7_flow_fixture"
    let create context (i:_ I.t) =
      let open Signal in
      let spec=Reg_spec.create ~clock:i.clk ~reset:(~:(i.rst_n)) () in
      let a=reg spec i.ena in let b=reg spec a in
      if not legacy then (
        Elaboration.Context.register_timing_stage_exn context ~stage:first ~q:a;
        Elaboration.Context.register_timing_stage_exn context ~stage:second ~q:b);
      {O.uo_out=uresize (a |: b) ~width:8;uio_out=zero 8;uio_oe=zero 8}
  end in
  let project=Project.create ~name:"pt7_named_reader_fixture" ~design:(module Design)
    ~metadata:{title="named reader fixture";author="test";description="No EDA"}
    ~target:{harness=Tiny_tapeout {tiles=T6x4};technology=Technology.ihp_sg13cmos5l}
    ~flow:(Flow.librelane Synthesis) ~clocks:[{Clock.port="clk";period=Time_float.Span.of_ns 20.}]
    ~pinout:(List.concat_map [Pinout.Bank.Ui;Uo;Uio] ~f:(fun bank ->
      List.init 8 ~f:(fun bit -> {Pinout.bank;bit;description="fixture"})))
    ~source_inputs:["dune-project"]
    ~timing ~policy:(Resource_policy.create ~default:Flops [] |> Or_error.ok_exn) () |> Or_error.ok_exn in
  let methodology=Flow.Methodology.create ~id:"classic" ~label:"Classic" ~description:"fixture"
    ~backend_recipe:Librelane_classic_v1 ~endpoints:Flow.Stage.all ~configurable:Flow.Parameter.Key.all
    ~defaults:[] |> Or_error.ok_exn in
  let profile id=Flow.Profile.create ~id ~label:id ~description:"fixture" ~assignments:[] |> Or_error.ok_exn in
  let entry=Flow.Catalog.Entry.create ~methodology ~profiles:[profile "area";profile "alternative"] ~default_profile:"area" |> Or_error.ok_exn in
  let catalog=Flow.Catalog.create ~entries:[entry] ~default_flow:"classic" ~default_profile:"area" |> Or_error.ok_exn in
  let selection=Flow.Selection.create ~flow:"classic" ~profile:profile_id () |> Or_error.ok_exn in
  let base=Target.Inputs.reference_cmos5l_6x4 in
  let inputs={base with support_tools_revision=String.make 40 'a';pdk_revision=String.make 40 'a';
    floorplan_sha256=Flow.Plan_json.sha256 "floorplan fixture"} in
  let prepared=Methodology_plan.prepare ~inputs ~catalog ~selection ~endpoint:Flow.Stage.Synthesis ~catalog_inputs:["dune-project"]
    project ~source_root:"../.." |> Or_error.ok_exn in
  Bundle.write (Methodology_plan.Prepared.bundle prepared) ~output_dir:Stdlib.Sys.argv.(1) |> Or_error.ok_exn;
  print_endline (Methodology_plan.to_string (Methodology_plan.Prepared.plan prepared))
