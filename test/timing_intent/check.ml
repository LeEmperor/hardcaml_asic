open! Core
open! Hardcaml
open! Hardcaml_asic

let rx0 = Timing.Stage.create ~id:"rx0" ~chain:"rx" ~index:0
let rx1 = Timing.Stage.create ~id:"rx1" ~chain:"rx" ~index:1
let rr0 = Timing.Stage.create ~id:"rr0" ~chain:"rr" ~index:0
let rr1 = Timing.Stage.create ~id:"rr1" ~chain:"rr" ~index:1
let capture ?(reason = "external asynchronous request, two scalar stages") () =
  Timing.Exception.async_capture ~id:"capture" ~reason
    ~source:(Timing.Port.bit (Timing.Port.input "ui_in") 0) ~first_stage:rx0
let reset () = Timing.Exception.async_reset ~id:"reset"
  ~reason:"raw reset release is asynchronous at enumerated reset synchronizer controls"
  ~source:(Timing.Port.input "rst_n") ~targets:[rr1; rr0]
let timing = Timing.create ~stages:[rx1; rr0; rx0; rr1] ~exceptions:[reset (); capture ()] ()
let held = ref None

let project ?(case = "good") ?(timing = timing) () =
  let module Design = struct
    module I = Tt_cmos5l.I
    module O = Tt_cmos5l.O
    let name = "tt_um_pt7_fixture"
    let create context (i : _ I.t) =
      held := Some context;
      let open Signal in
      let spec = Reg_spec.create ~clock:(if String.equal case "clock" then i.ena else i.clk) () in
      let a = reg ?enable:(if String.equal case "enable" then Some i.ena else None)
        ?clear:(if String.equal case "clear" then Some i.ena else None)
        spec (bit i.ui_in ~pos:0) in
      let b = reg spec (if String.equal case "topology" then bit i.ui_in ~pos:1 else a) in
      let direct = List.mem ["active_low_direct";"active_high_direct"] case ~equal:String.equal in
      let low = List.mem ["active_low_direct";"active_low_inverted"] case ~equal:String.equal in
      let rspec = Reg_spec.create ~clock:i.clk
        ~reset:(if direct then i.rst_n else ~:(i.rst_n))
        ~reset_level:(if low then Low else High) () in
      let c = reg ~reset_to:(Bits.of_int_trunc ~width:1 (if String.equal case "preset" then 1 else 0)) rspec (ones 1) in
      let d = reg rspec c in
      let register stage q = Elaboration.Context.register_timing_stage_exn context ~stage ~q in
      register rx0 (if String.equal case "not_reg" then bit i.ui_in ~pos:0 else a);
      if not (String.equal case "missing") then register rx1 b;
      register rr0 c; register rr1 d;
      if String.equal case "caught_duplicate" then (try register rx0 a with _ -> ());
      if String.equal case "duplicate_name" then ignore (i.ena -- "hc_pt7_rx0" : Signal.t);
      if String.equal case "lost_keep" then (
        Option.iter (Signal.Type.info a) ~f:(fun info ->
          Option.iter info.metadata ~f:(fun m -> m.attributes <- [])));
      { O.uo_out = uresize (b |: d |: a) ~width:8
      ; uio_out = uresize i.ena ~width:8
      ; uio_oe = zero 8 }
  end in
  Project.create ~name:"pt7_fixture" ~design:(module Design)
    ~metadata:{title="PT7";author="fixture";description="scalar timing intent"}
    ~target:{harness=Tiny_tapeout {tiles=T6x4};technology=Technology.ihp_sg13cmos5l}
    ~flow:(Flow.librelane Synthesis)
    ~clocks:[{Clock.port="clk";period=Time_float.Span.of_ns 20.}]
    ~pinout:(List.concat_map [Pinout.Bank.Ui; Uo; Uio] ~f:(fun bank ->
      List.init 8 ~f:(fun bit -> {Pinout.bank;bit;description="fixture"})))
    ~timing ~policy:(Resource_policy.create ~default:Flops [] |> Or_error.ok_exn) ()
  |> Or_error.ok_exn
;;
let resolution ?case ?timing () = Project.elaborate_for_flow (project ?case ?timing ())
let intent r = Option.value_exn r.Resolved_flow.timing_intent

let tests () =
  let count = ref 0 in
  let reject label ?case ?timing fragment =
    incr count;
    match resolution ?case ?timing () with
    | Ok _ -> failwith ("accepted negative: " ^ label)
    | Error e -> if not (String.is_substring (Error.to_string_hum e) ~substring:fragment)
      then failwith (label ^ ": unexpected error " ^ Error.to_string_hum e) in
  ignore (resolution () |> Or_error.ok_exn : Resolved_flow.t);
  ignore (resolution ~case:"active_low_direct" () |> Or_error.ok_exn : Resolved_flow.t);
  reject "externally active-high direct reset" ~case:"active_high_direct" "unsupported reset polarity";
  reject "externally active-high inverted reset" ~case:"active_low_inverted" "unsupported reset polarity";
  reject "wrong clock" ~case:"clock" "primary clk";
  reject "wrong topology" ~case:"topology" "previous stage Q";
  reject "not register" ~case:"not_reg" "scalar register Q";
  reject "missing registration" ~case:"missing" "inventory differs";
  reject "caught registration error" ~case:"caught_duplicate" "registration failed";
  reject "anchor collision" ~case:"duplicate_name" "ambiguous";
  reject "removed preservation" ~case:"lost_keep" "keep=1";
  reject "unsupported preset" ~case:"preset" "resets to zero";
  reject "stage enable" ~case:"enable" "enable/clear";
  reject "stage clear" ~case:"clear" "enable/clear";
  let capture source first_stage = Timing.Exception.async_capture ~id:"capture" ~reason:"reviewed" ~source ~first_stage in
  let with_exception e = {timing with exceptions=[e]} in
  reject "bus source" ~timing:(with_exception (capture (Timing.Port.input "ui_in") rx0)) "explicit bit";
  reject "negative bit" ~timing:(with_exception (capture (Timing.Port.bit (Timing.Port.input "ui_in") (-1)) rx0)) "out of range";
  reject "large bit" ~timing:(with_exception (capture (Timing.Port.bit (Timing.Port.input "ui_in") 8) rx0)) "out of range";
  reject "scalar bit" ~timing:(with_exception (capture (Timing.Port.bit (Timing.Port.input "ena") 0) rx0)) "selects a scalar";
  reject "output source" ~timing:(with_exception (capture (Timing.Port.output "uo_out") rx0)) "nonclock input";
  reject "clock source" ~timing:(with_exception (capture (Timing.Port.input "clk") rx0)) "nonclock input";
  reject "literal wildcard" ~timing:(with_exception (capture (Timing.Port.input "ui_*") rx0)) "input missing";
  reject "downstream capture" ~timing:(with_exception (capture (Timing.Port.bit (Timing.Port.input "ui_in") 0) rx1)) "first stage";
  reject "mismatched data" ~timing:(with_exception (capture (Timing.Port.bit (Timing.Port.input "ui_in") 1) rx0)) "data does not match";
  reject "blank reason" ~timing:(with_exception (Timing.Exception.async_capture ~id:"blank" ~reason:" \n"
    ~source:(Timing.Port.input "ena") ~first_stage:rx0)) "nonblank reason";
  reject "duplicate stage" ~timing:{timing with stages=rx0::timing.stages} "stage ID";
  reject "duplicate exception" ~timing:{timing with exceptions=[reset ();reset ()]} "exception ID";
  reject "unknown stage" ~timing:(with_exception (capture (Timing.Port.input "ena")
    (Timing.Stage.create ~id:"unknown" ~chain:"other" ~index:0))) "not declared";
  let reset targets source = Timing.Exception.async_reset ~id:"reset" ~reason:"reviewed" ~source ~targets in
  reject "empty reset" ~timing:(with_exception (reset [] (Timing.Port.input "rst_n"))) "explicit targets";
  reject "duplicate reset" ~timing:(with_exception (reset [rr0;rr0] (Timing.Port.input "rst_n"))) "target declared";
  reject "data pin as reset" ~timing:(with_exception (reset [rx0] (Timing.Port.input "rst_n"))) "no asynchronous control";
  reject "wrong reset source" ~timing:(with_exception (reset [rr0] (Timing.Port.input "ena"))) "does not match";
  reject "overlapping scope" ~timing:{timing with exceptions=[reset [rr0] (Timing.Port.input "rst_n");
    Timing.Exception.async_reset ~id:"other" ~reason:"reviewed" ~source:(Timing.Port.input "rst_n") ~targets:[rr0]]}
    "overlapping exception";
  let r = resolution () |> Or_error.ok_exn in
  let ep = r.elaborated_project in
  let remap label change fragment =
    incr count;
    let declarations = List.map timing.stages ~f:change in
    let registrations = Elaborated_project.timing_stages ep
      |> List.map ~f:(fun (s, q) -> change s, q) in
    match Elaboration.Timing_intent.resolve ~circuit:(Elaborated_project.circuit ep)
      ~timing:{timing with stages=declarations;exceptions=[]} ~registrations with
    | Ok _ -> failwith ("accepted remapped negative: " ^ label)
    | Error e -> assert (String.is_substring (Error.to_string_hum e) ~substring:fragment) in
  remap "bad ID" (fun s -> if String.equal s.Timing.Stage.id "rx0" then
    Timing.Stage.create ~id:"bad-*" ~chain:s.chain ~index:s.index else s) "ASCII identifiers";
  remap "gap" (fun s -> if String.equal s.Timing.Stage.id "rx1" then
    Timing.Stage.create ~id:s.id ~chain:s.chain ~index:2 else s) "contiguous";
  remap "duplicate index" (fun s -> if String.equal s.Timing.Stage.id "rx1" then
    Timing.Stage.create ~id:s.id ~chain:s.chain ~index:0 else s) "contiguous";
  remap "single stage" (fun s -> if String.equal s.Timing.Stage.id "rx1" then
    Timing.Stage.create ~id:s.id ~chain:"other" ~index:0 else s) "at least two";
  let json = Elaboration.Timing_intent.to_json (intent r) |> Yojson.Safe.to_string in
  let r2 = resolution ~timing:{timing with exceptions=[capture (Timing.Port.bit (Timing.Port.input "ui_in") 0) rx0]} () |> Or_error.ok_exn in
  assert (not (String.equal json (Elaboration.Timing_intent.to_json (intent r2) |> Yojson.Safe.to_string)));
  (* A finalized context rejects subsequent registrations; a new elaboration is independent. *)
  (try Elaboration.Context.register_timing_stage_exn (Option.value_exn !held) ~stage:rx0 ~q:(Signal.zero 1);
       failwith "closed context accepted registration"
   with exn -> assert (String.is_substring (Exn.to_string exn) ~substring:"closed"));
  ignore (resolution () |> Or_error.ok_exn : Resolved_flow.t);
  Printf.printf "library timing intent: positive lifecycle/intent checks and %d negatives passed\n" !count
;;

let () = match Array.to_list (Sys.get_argv ()) with
  | [_; "sdc"] -> print_string (Elaboration.Timing_intent.sdc (resolution () |> Or_error.ok_exn |> intent))
  | [_; "json"] -> print_endline (Elaboration.Timing_intent.to_json (resolution () |> Or_error.ok_exn |> intent) |> Yojson.Safe.to_string)
  | [_; "rtl"] -> print_string (Rtl.create Verilog [Elaborated_project.circuit (resolution () |> Or_error.ok_exn).elaborated_project] |> Rtl.full_hierarchy |> Rope.to_string)
  | [_; "bundle"; root] ->
    let bundle timing =
      let r = resolution ~timing () |> Or_error.ok_exn in
      Bundle.render ~source_root:root ~input_paths:["dune-project"] r |> Or_error.ok_exn in
    let a = bundle timing in
    let b = bundle {timing with exceptions=[reset ();capture ~reason:"changed reviewed assumption" ()]} in
    assert (not (String.equal (Bundle.identity a) (Bundle.identity b)));
    assert (not (Poly.equal (Yojson.Safe.Util.member "timing_intent" (Bundle.manifest a)) `Null));
    print_endline "bundle timing intent and reason changes are identity-covered"
  | _ -> tests ()
