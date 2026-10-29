open! Core
open! Hardcaml
open! Hardcaml_asic

let stages = List.concat_map ["rr"; "rx"] ~f:(fun chain ->
  List.init 2 ~f:(fun index -> Timing.Stage.create ~id:(chain ^ Int.to_string index) ~chain ~index))
let stage id = List.find_exn stages ~f:(fun s -> String.equal s.id id)
let timing = Timing.create ~stages ~exceptions:[
  Timing.Exception.async_capture ~id:"capture" ~reason:"fixture input"
    ~source:(Timing.Port.bit (Timing.Port.input "ui_in") 0) ~first_stage:(stage "rx0");
  Timing.Exception.async_reset ~id:"reset" ~reason:"fixture reset"
    ~source:(Timing.Port.input "rst_n") ~targets:[stage "rr0"; stage "rr1"]] ()
let resolved ?(declare = true) () =
  let module Design = struct
    module I = Tt_cmos5l.I
    module O = Tt_cmos5l.O
    let name = "tt_um_physical_fixture"
    let create context (i : _ I.t) =
      let open Signal in
      let spec = Reg_spec.create ~clock:i.clk ~reset:i.rst_n ~reset_level:Low () in
      let register id d =
        let q = reg spec d in
        if declare then Elaboration.Context.register_timing_stage_exn context ~stage:(stage id) ~q;
        q in
      let a = register "rx0" (bit i.ui_in ~pos:0) in
      let b = register "rx1" a in
      let c = register "rr0" i.ena in
      let d = register "rr1" c in
      {O.uo_out=uresize (b &: d &: i.ena) ~width:8; uio_out=zero 8; uio_oe=zero 8}
  end in
  Project.create ~name:"physical_fixture" ~design:(module Design)
    ~metadata:{title="Physical fixture";author="test";description="Explicit qualification"}
    ~target:{harness=Tiny_tapeout {tiles=T6x4};technology=Technology.ihp_sg13cmos5l}
    ~flow:(Flow.librelane Hardening)
    ~clocks:[{Clock.port="clk";period=Time_float.Span.of_ns 20.}]
    ~pinout:(List.concat_map [Pinout.Bank.Ui; Uo; Uio] ~f:(fun bank ->
      List.init 8 ~f:(fun bit -> {Pinout.bank;bit;description="fixture"})))
    ~timing:(if declare then timing else Timing.empty) ~policy:(Resource_policy.create ~default:Flops [] |> Or_error.ok_exn) ()
  |> Or_error.ok_exn |> Project.elaborate_for_flow |> Or_error.ok_exn

let () =
  let r = resolved () in
  let intent = Option.value_exn r.timing_intent in
  match Array.to_list (Sys.get_argv ()) with
  | [_; "v1"] -> print_string (Elaboration.Timing_intent.sdc intent)
  | [_; "v2"] -> print_string (Elaboration.Timing_intent.sdc ~physical:true intent)
  | [_; "bundle"; root] ->
    let render ?timing_physical_qualification r =
      Bundle.render ?timing_physical_qualification ~source_root:root ~input_paths:["dune-project"] r |> Or_error.ok_exn in
    let old = render r and explicit_old = render ~timing_physical_qualification:false r in
    let physical = render ~timing_physical_qualification:true r in
    assert (String.equal (Bundle.identity old) (Bundle.identity explicit_old));
    assert (not (String.equal (Bundle.identity old) (Bundle.identity physical)));
    assert (Poly.equal (Yojson.Safe.Util.member "timing_physical_qualification" (Bundle.manifest old)) `Null);
    assert (String.equal (Option.value_exn (Bundle.file old "constraints/top.sdc"))
      (Elaboration.Bundle.file explicit_old "constraints/top.sdc" |> Option.value_exn));
    (match Bundle.render ~timing_physical_qualification:true ~source_root:root ~input_paths:["dune-project"] (resolved ~declare:false ()) with
     | Error _ -> () | Ok _ -> failwith "missing intent accepted");
    print_endline (Yojson.Safe.to_string (`List [Bundle.manifest old; Bundle.manifest physical]))
  | _ -> failwith "expected v1, v2 or bundle ROOT"
