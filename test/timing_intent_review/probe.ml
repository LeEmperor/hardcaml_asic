open! Core
open! Hardcaml
open! Hardcaml_asic

let s0=Timing.Stage.create ~id:"review0" ~chain:"review" ~index:0
let s1=Timing.Stage.create ~id:"review1" ~chain:"review" ~index:1
let timing ?(reason="independent review") ?(reset_targets=[s0;s1]) () =
  Timing.create ~stages:[s0;s1] ~exceptions:[
    Timing.Exception.async_capture ~id:"capture" ~reason
      ~source:(Timing.Port.bit (Timing.Port.input "ui_in") 0) ~first_stage:s0;
    Timing.Exception.async_reset ~id:"reset" ~reason ~source:(Timing.Port.input "rst_n") ~targets:reset_targets] ()

let project ?(case="good") ?(timing=timing ()) () =
  let module D=struct
    module I=Tt_cmos5l.I
    module O=Tt_cmos5l.O
    let name="tt_um_pt7_independent_review"
    let create context (i:_ I.t) =
      let open Signal in
      let alias signal=let w=wire (width signal) in w <-- signal;w in
      let clock=if String.equal case "wrong_clock" then i.ena
        else if String.equal case "alias" then alias i.clk else i.clk in
      let reset=if String.equal case "wrong_reset" then i.ena
        else if List.mem ["direct_low";"direct_high"] case ~equal:String.equal then i.rst_n else ~:(i.rst_n) in
      let reset_level=if List.mem ["direct_low";"inverted_low"] case ~equal:String.equal then Level.Low else Level.High in
      let spec=Reg_spec.create ~clock ~clock_edge:(if String.equal case "falling" then Falling else Rising) ~reset ~reset_level () in
      let data=bit i.ui_in ~pos:(if String.equal case "wrong_source" then 1 else 0) in
      let a=reg spec data in
      let b=reg spec (if String.equal case "wrong_topology" then i.ena else if String.equal case "alias" then alias a else a) in
      let a_uid=uid a and b_uid=uid b in
      let register ctx stage q=Elaboration.Context.register_timing_stage_exn ctx ~stage ~q in
      if String.equal case "existing_keep" then ignore (add_attribute a (Rtl_attribute.create ~value:(Int 0) "keep") : Signal.t);
      if String.equal case "existing_reserved" then ignore (a -- "hc_pt7_other" : Signal.t);
      register context s0 a;
      register context s1 b;
      assert (Signal.Type.Uid.equal a_uid (uid a) && Signal.Type.Uid.equal b_uid (uid b));
      if String.equal case "duplicate_q" then (try
        register context (Timing.Stage.create ~id:"another" ~chain:"other" ~index:0) a
        with _ -> ());
      if String.equal case "duplicate_scope" then (try
        let scope=Scope.sub_scope (Elaboration.Context.scope context) "child" in
        register (Elaboration.Context.in_scope context scope) s0 (reg spec data)
        with _ -> ());
      if String.equal case "colliding_anchor" then ignore (i.ena -- Timing.Stage.anchor s0 : Signal.t);
      {O.uo_out=uresize (if String.equal case "detached" then i.ena else a |: b) ~width:8;
       uio_out=uresize i.ena ~width:8;uio_oe=zero 8}
  end in
  Project.create ~name:"pt7_review" ~design:(module D)
    ~metadata:{title="review";author="review";description="independent no-EDA probes"}
    ~target:{harness=Tiny_tapeout {tiles=T6x4};technology=Technology.ihp_sg13cmos5l}
    ~flow:(Flow.librelane Synthesis) ~clocks:[{Clock.port="clk";period=Time_float.Span.of_ns 20.}]
    ~pinout:(List.concat_map [Pinout.Bank.Ui;Uo;Uio] ~f:(fun bank ->
      List.init 8 ~f:(fun bit -> {Pinout.bank;bit;description="review"})))
    ~timing ~policy:(Resource_policy.create ~default:Flops [] |> Or_error.ok_exn) () |> Or_error.ok_exn

let resolve ?case ?timing ()=Project.elaborate_for_flow (project ?case ?timing ())
let checked ?case ?timing ()=resolve ?case ?timing () |> Or_error.ok_exn
let intent r=Option.value_exn r.Resolved_flow.timing_intent
let tests root =
  List.iter ["good";"alias";"direct_low"] ~f:(fun case ->
    let r=checked ~case () in
    let circuit=Elaborated_project.circuit r.elaborated_project in
    let regs=Signal_graph.filter (Circuit.signal_graph circuit) ~f:Signal.Type.is_reg in
    assert (List.length regs=2);
    Printf.printf "OCAML accepted %s: exactly two original registers\n" case);
  List.iter ["wrong_clock";"falling";"wrong_reset";"wrong_source";"wrong_topology";
    "detached";"duplicate_q";"duplicate_scope";"existing_keep";"existing_reserved";"colliding_anchor";
    "direct_high";"inverted_low"]
    ~f:(fun case -> match resolve ~case () with
      | Ok _ -> failwith ("unexpected accepted OCaml negative "^case)
      | Error e ->
        if List.mem ["direct_high";"inverted_low"] case ~equal:String.equal then
          assert (String.is_substring (Error.to_string_hum e) ~substring:"unsupported reset polarity");
        Printf.printf "OCAML rejected %s: %s\n" case (Error.to_string_hum e |> String.split_lines |> List.hd_exn));
  let bundle timing=Bundle.render ~source_root:root ~input_paths:["dune-project"] (checked ~timing ()) |> Or_error.ok_exn in
  let a=bundle (timing ()) and b=bundle (timing ~reason:"different review reason" ()) in
  assert (not (String.equal (Bundle.identity a) (Bundle.identity b)));
  assert (Poly.equal (Bundle.file a "constraints/top.sdc") (Bundle.file b "constraints/top.sdc"));
  let c=bundle (timing ~reset_targets:[s0] ()) in
  assert (not (String.equal (Bundle.identity a) (Bundle.identity c)));
  assert (not (Poly.equal (Bundle.file a "constraints/top.sdc") (Bundle.file c "constraints/top.sdc")));
  let json=Bundle.manifest a in
  let tampered=match json with `Assoc xs -> `Assoc (List.map xs ~f:(fun (k,v) -> k,(if String.equal k "timing_intent" then `Null else v))) | _ -> assert false in
  assert (Result.is_error (Bundle.verify_manifest_identity tampered));
  Printf.printf "IDENTITY reason-only change covered; reset-scope change covers SDC; tampering rejected\n"

let ()=match Array.to_list (Sys.get_argv ()) with
  | [_;"sdc"] -> print_string (Elaboration.Timing_intent.sdc (intent (checked ())))
  | [_;"tests";root] -> tests root
  | _ -> failwith "sdc | tests SOURCE_ROOT"
