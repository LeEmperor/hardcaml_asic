open! Core
open! Hardcaml
open! Hardcaml_asic

(* Genuine ordinary library emission, with synthetic STA events supplied separately
   by check.ml. Nothing here runs synthesis/STA or writes a bundle. *)
let make ?(separate_simulation=false) () =
  let s0=Timing.Stage.create ~id:"rx0" ~chain:"rx" ~index:0 in
  let s1=Timing.Stage.create ~id:"rx1" ~chain:"rx" ~index:1 in
  let timing=Timing.create ~stages:[s0;s1] ~exceptions:[
    Timing.Exception.async_capture ~id:"capture" ~reason:"external asynchronous capture"
      ~source:(Timing.Port.input "ena") ~first_stage:s0] () in
  let module D=struct
    module I=Tt_cmos5l.I
    module O=Tt_cmos5l.O
    let name="tt_um_pt7_evidence_fixture"
    let create context (i:_ I.t) =
      let open Signal in
      let spec=Reg_spec.create ~clock:i.clk ~reset:(~:(i.rst_n)) () in
      let a=reg spec i.ena in
      let b=reg spec a in
      Elaboration.Context.register_timing_stage_exn context ~stage:s0 ~q:a;
      Elaboration.Context.register_timing_stage_exn context ~stage:s1 ~q:b;
      {O.uo_out=uresize (a |: b) ~width:8;uio_out=uresize i.ena ~width:8;uio_oe=zero 8}
  end in
  let project=Project.create ~name:"pt7_evidence_fixture" ~design:(module D)
    ~metadata:{title="evidence";author="fixture";description="genuine bundle, synthetic tool events"}
    ~target:{harness=Tiny_tapeout {tiles=T6x4};technology=Technology.ihp_sg13cmos5l}
    ~flow:(Flow.librelane Synthesis) ~clocks:[{Clock.port="clk";period=Time_float.Span.of_ns 20.}]
    ~pinout:(List.concat_map [Pinout.Bank.Ui;Uo;Uio] ~f:(fun bank ->
      List.init 8 ~f:(fun bit -> {Pinout.bank;bit;description="fixture"})))
    ~timing ~policy:(Resource_policy.create ~default:Flops [] |> Or_error.ok_exn) () |> Or_error.ok_exn in
  let resolved=Project.elaborate_for_flow project |> Or_error.ok_exn in
  let simulation_project=if separate_simulation then Some (Project.elaborate project ~mode:Simulation |> Or_error.ok_exn) else None in
  let bundle=Bundle.render ?simulation_project ~source_root:"../.." ~input_paths:["dune-project"] resolved |> Or_error.ok_exn in
  Bundle.manifest bundle,Option.value_exn (Bundle.file bundle "constraints/top.sdc")
