open! Core
open! Hardcaml
open! Hardcaml_asic
let () =
  let first=Timing.Stage.create ~id:"rx0" ~chain:"rx" ~index:0 in
  let second=Timing.Stage.create ~id:"rx1" ~chain:"rx" ~index:1 in
  let timing=Timing.create ~stages:[first;second] ~exceptions:[
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
      Elaboration.Context.register_timing_stage_exn context ~stage:first ~q:a;
      Elaboration.Context.register_timing_stage_exn context ~stage:second ~q:b;
      {O.uo_out=uresize (a |: b) ~width:8;uio_out=zero 8;uio_oe=zero 8}
  end in
  let project=Project.create ~name:"pt7_flow_fixture" ~design:(module Design)
    ~metadata:{title="flow fixture";author="test";description="No native tools"}
    ~target:{harness=Tiny_tapeout {tiles=T6x4};technology=Technology.ihp_sg13cmos5l}
    ~flow:(Flow.librelane Synthesis) ~clocks:[{Clock.port="clk";period=Time_float.Span.of_ns 20.}]
    ~pinout:(List.concat_map [Pinout.Bank.Ui;Uo;Uio] ~f:(fun bank ->
      List.init 8 ~f:(fun bit -> {Pinout.bank;bit;description="fixture"})))
    ~timing ~policy:(Resource_policy.create ~default:Flops [] |> Or_error.ok_exn) () |> Or_error.ok_exn in
  let resolved=Project.elaborate_for_flow project |> Or_error.ok_exn in
  let bundle=Bundle.render ~source_root:"../.." ~input_paths:["dune-project"] resolved |> Or_error.ok_exn in
  Bundle.write bundle ~output_dir:Stdlib.Sys.argv.(1) |> Or_error.ok_exn
