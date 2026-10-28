open! Core
open! Hardcaml
open! Hardcaml_asic
open! Expect_test_helpers_core

module I = struct
  type 'a t =
    { ui_in : 'a [@bits 8]
    ; uio_in : 'a [@bits 8]
    ; ena : 'a
    ; clk : 'a
    ; rst_n : 'a
    }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t =
    { uo_out : 'a [@bits 8]
    ; uio_out : 'a [@bits 8]
    ; uio_oe : 'a [@bits 8]
    }
  [@@deriving hardcaml]
end

module Good = struct
  module I = I
  module O = O

  let name = "tt_um_fixture"

  let create _ (i : _ I.t) =
    { O.uo_out = Signal.reg (Signal.Reg_spec.create ~clock:i.clk ()) i.ui_in
    ; uio_out = Signal.mux2 i.rst_n i.uio_in (Signal.zero 8)
    ; uio_oe = Signal.uresize i.ena ~width:8
    }
  ;;
end

module Unused_inputs = struct
  module I = I
  module O = O

  let name = "tt_um_unused_inputs"

  let create _ (_ : _ I.t) =
    { O.uo_out = Signal.zero 8; uio_out = Signal.zero 8; uio_oe = Signal.zero 8 }
  ;;
end

module Bad_width = struct
  module I = struct
    type 'a t =
      { ui_in : 'a [@bits 7]
      ; uio_in : 'a [@bits 8]
      ; ena : 'a
      ; clk : 'a
      ; rst_n : 'a
      }
    [@@deriving hardcaml]
  end

  module O = O

  let name = "tt_um_bad_width"

  let create _ (i : _ I.t) =
    { O.uo_out =
        Signal.reg
          (Signal.Reg_spec.create ~clock:i.clk ())
          (Signal.uresize i.ui_in ~width:8)
    ; uio_out = Signal.mux2 i.rst_n i.uio_in (Signal.zero 8)
    ; uio_oe = Signal.uresize i.ena ~width:8
    }
  ;;
end

module Wrong_direction = struct
  module I = struct
    type 'a t =
      { ui_in : 'a [@bits 8]
      ; uio_in : 'a [@bits 8]
      ; ena : 'a
      ; clk : 'a
      }
    [@@deriving hardcaml]
  end

  module O = struct
    type 'a t =
      { uo_out : 'a [@bits 8]
      ; uio_out : 'a [@bits 8]
      ; uio_oe : 'a [@bits 8]
      ; rst_n : 'a
      }
    [@@deriving hardcaml]
  end

  let name = "tt_um_wrong_direction"

  let create _ (i : _ I.t) =
    { O.uo_out = Signal.reg (Signal.Reg_spec.create ~clock:i.clk ()) i.ui_in
    ; uio_out = i.uio_in
    ; uio_oe = Signal.zero 8
    ; rst_n = i.ena
    }
  ;;
end

let pinout : Pinout.t =
  List.concat_map [ Pinout.Bank.Ui; Uo; Uio ] ~f:(fun bank ->
    List.init 8 ~f:(fun bit -> { Pinout.bank; bit; description = "fixture pin" }))
;;

let metadata : Elaboration.Metadata.t =
  { title = "TT fixture"; author = "test"; description = "Interface validation" }
;;

let project
  ?(design = (module Good : Project.Design))
  ?(metadata = metadata)
  ?(pinout = pinout)
  ?(timing = Timing.empty)
  ?(clocks = [ { Clock.port = "clk"; period = Time_float.Span.of_ns 20. } ])
  ?(flow = Flow.librelane Hardening)
  ()
  =
  Project.create
    ~name:"tt_fixture"
    ~metadata
    ~pinout
    ~timing
    ~clocks
    ~design
    ~target:
      { Target.harness = Tiny_tapeout { tiles = T6x4 }
      ; technology = Resource.Technology.ihp_sg13cmos5l
      }
    ~flow
    ~policy:(Resource_policy.create ~default:Flops [] |> ok_exn)
    ()
  |> ok_exn
;;

let resolve ?design ?metadata ?pinout ?timing ?clocks ?flow () =
  project ?design ?metadata ?pinout ?timing ?clocks ?flow () |> Project.elaborate_for_flow
;;

let methodology ?(defaults = []) ?(assignments = []) ?(request = [])
  ?(configurable = Flow.Parameter.Key.all) () =
  let m = Flow.Methodology.create ~id:"classic" ~label:"Classic" ~description:""
      ~backend_recipe:Librelane_classic_v1 ~endpoints:[ Synthesis ]
      ~configurable ~defaults |> ok_exn in
  let p = Flow.Profile.create ~id:"area" ~label:"Area" ~description:""
      ~assignments |> ok_exn in
  let entry = Flow.Catalog.Entry.create ~methodology:m ~profiles:[ p ]
      ~default_profile:"area" |> ok_exn in
  let catalog = Flow.Catalog.create ~entries:[ entry ] ~default_flow:"classic"
      ~default_profile:"area" |> ok_exn in
  Flow.Catalog.resolve ~request catalog ~endpoint:Synthesis () |> ok_exn
;;

let%test_unit "methodology merge checks inherited domains and preserves complete precedence" =
  let module P = Flow.Parameter in
  let override key value = { Flow.Librelane.Override.key; value; reason = "project template origin" } in
  let p = project ~flow:(Flow.librelane Hardening ~overrides:
      [ override "SYNTH_STRATEGY" (`String "AREA 2")
      ; override "SYNTH_ABC_BUFFERING" (`Bool true)
      ; override "PL_TARGET_DENSITY_PCT" (`Int 47) ]) () in
  let before = Project.describe p in
  let inherited = Project.elaborate_for_flow ~methodology:(methodology ()) p |> ok_exn in
  assert (List.length inherited.effective_parameters = 2);
  List.iter inherited.effective_parameters ~f:(fun e ->
    assert (List.is_empty e.overridden);
    match e.winning.owner with
    | Override "project template origin" -> ()
    | _ -> assert false);
  let m = methodology ~defaults:[ P.synth_strategy Area_0 ]
      ~assignments:[ P.synth_strategy Delay_0; P.synth_abc_buffering false ]
      ~request:[ P.synth_strategy Delay_1 ] () in
  let r = Project.elaborate_for_flow ~methodology:m p |> ok_exn in
  let strategy = List.find_exn r.effective_parameters ~f:(fun e ->
    P.Key.equal (P.assignment_key e.winning.assignment) Synth_strategy) in
  assert (P.equal_value (P.assignment_value strategy.winning.assignment) (Strategy Delay_1));
  assert (List.length strategy.overridden = 3);
  (match List.map strategy.overridden ~f:(fun c -> c.owner), strategy.winning.owner with
   | [ Override "project template origin"; Methodology Methodology; Methodology Profile ],
     Methodology Request -> ()
   | _ -> assert false);
  let value key = (List.find_exn r.settings ~f:(fun s -> String.equal s.key key)).value in
  assert (Yojson.Safe.equal (value "SYNTH_ABC_BUFFERING") (`Bool false));
  assert (Yojson.Safe.equal (value "PL_TARGET_DENSITY_PCT") (`Int 47));
  assert (Sexp.equal before (Project.describe p));
  let again = Project.elaborate_for_flow ~methodology:(methodology ()) p |> ok_exn in
  assert (List.equal (fun a b -> Sexp.equal (Resolved_flow.Setting.sexp_of_t a)
              (Resolved_flow.Setting.sexp_of_t b)) inherited.settings again.settings);
  List.iter [ `String "area 0"; `String "AREA0"; `Bool false; `Int 1 ] ~f:(fun invalid ->
    let p = project ~flow:(Flow.librelane Hardening ~overrides:
      [ override "SYNTH_STRATEGY" invalid ]) () in
    assert (Or_error.is_error (Project.elaborate_for_flow ~methodology:m p)));
  List.iter [ `Int 0; `Int 1; `String "false"; `Null ] ~f:(fun invalid ->
    let p = project ~flow:(Flow.librelane Hardening ~overrides:
      [ override "SYNTH_ABC_BUFFERING" invalid ]) () in
    assert (Or_error.is_error (Project.elaborate_for_flow ~methodology:m p)));
  let default = Project.elaborate_for_flow
      ~methodology:(methodology ~defaults:[ P.synth_strategy Area_0 ] ()) p |> ok_exn in
  let s = List.find_exn default.settings ~f:(fun s -> String.equal s.key "SYNTH_STRATEGY") in
  assert (Yojson.Safe.equal s.value (`String "AREA 0"));
  let unspecified = Project.elaborate_for_flow ~methodology:(methodology ()) (project ()) |> ok_exn in
  assert (List.is_empty unspecified.effective_parameters);
  let unconfigurable = Project.elaborate_for_flow
      ~methodology:(methodology ~configurable:[] ()) p |> ok_exn in
  assert (List.is_empty unconfigurable.effective_parameters);
  List.iter [ "CLOCK_PERIOD"; "DESIGN_NAME"; "PNR_SDC_FILE"; "DIE_AREA" ] ~f:(fun key ->
    let p = project ~flow:(Flow.librelane Hardening ~overrides:[ override key (`Int 1) ]) () in
    assert (Or_error.is_error (Project.elaborate_for_flow ~methodology:m p)));
  assert (Or_error.is_error (P.of_string_value ~key:"CLOCK_PERIOD" "20"));
  assert (Or_error.is_error (P.check_assignments ~configurable:[] [ P.synth_strategy Area_0 ]));
  assert (Or_error.is_error (Project.create ~name:"duplicate" ~metadata ~pinout
    ~design:(module Good) ~target:{ harness = Tiny_tapeout { tiles = T6x4 };
      technology = Resource.Technology.ihp_sg13cmos5l } ~policy:(Resource_policy.create ~default:Flops [] |> ok_exn)
    ~flow:(Flow.librelane Hardening ~overrides:
      [ override "SYNTH_STRATEGY" (`String "AREA 0"); override "SYNTH_STRATEGY" (`String "DELAY 1") ]) ()))
;;

let error_contains result fragment =
  match result with
  | Ok _ -> failwith ("expected error containing: " ^ fragment)
  | Error error ->
    require (String.is_substring (Error.to_string_hum error) ~substring:fragment)
;;

let%expect_test "reference wrapper and resolved flow facts" =
  let resolved = resolve () |> ok_exn in
  require (Float.equal resolved.clock_period_ns 20.);
  let keys = List.map resolved.settings ~f:(fun setting -> setting.key) in
  print_s [%sexp (keys : string list)];
  [%expect
    {|
    (CLOCK_PERIOD
     CLOCK_PORT
     CLOCK_TRANSITION_CONSTRAINT
     CLOCK_UNCERTAINTY_CONSTRAINT
     DESIGN_NAME
     DIE_AREA
     FP_DEF_TEMPLATE
     FP_SIZING
     GND_PIN
     MAX_FANOUT_CONSTRAINT
     OUTPUT_CAP_LOAD
     PDK
     RT_MAX_LAYER
     RUN_LINTER
     STD_CELL_LIBRARY
     SYNTH_DRIVING_CELL
     TIME_DERATING_CONSTRAINT
     VDD_PIN)
    |}]
;;

let%expect_test "the constraint environment reaches the settings as target facts" =
  let resolved = resolve () |> ok_exn in
  List.iter
    [ "SYNTH_DRIVING_CELL"
    ; "OUTPUT_CAP_LOAD"
    ; "MAX_FANOUT_CONSTRAINT"
    ; "CLOCK_UNCERTAINTY_CONSTRAINT"
    ; "CLOCK_TRANSITION_CONSTRAINT"
    ; "TIME_DERATING_CONSTRAINT"
    ]
    ~f:(fun key ->
      print_s
        [%sexp
          (List.find_exn resolved.settings ~f:(fun setting ->
             String.equal setting.key key)
           : Resolved_flow.Setting.t)]);
  [%expect
    {|
    ((key   SYNTH_DRIVING_CELL)
     (value "\"sg13cmos5l_buf_4/X\"")
     (owner Target))
    ((key   OUTPUT_CAP_LOAD)
     (value 6.0)
     (owner Target))
    ((key   MAX_FANOUT_CONSTRAINT)
     (value 10)
     (owner Target))
    ((key   CLOCK_UNCERTAINTY_CONSTRAINT)
     (value 0.25)
     (owner Target))
    ((key   CLOCK_TRANSITION_CONSTRAINT)
     (value 0.15)
     (owner Target))
    ((key   TIME_DERATING_CONSTRAINT)
     (value 5.0)
     (owner Target))
    |}]
;;

let%expect_test "unused declared wrapper inputs remain part of the interface" =
  ignore
    (resolve ~design:(module Unused_inputs : Project.Design) () |> ok_exn
     : Resolved_flow.t);
  [%expect {| |}]
;;

let%expect_test "48 MHz clock retains its fractional nanosecond period" =
  let period = Clock.period_of_frequency_hz 48e6 |> ok_exn in
  let resolved = resolve ~clocks:[ { port = "clk"; period } ] () |> ok_exn in
  require Float.(abs (resolved.clock_period_ns -. (1e9 /. 48e6)) < 1e-9);
  require Float.(abs (resolved.clock_hz -. 48e6) < 1e-6);
  print_s [%sexp (Float.round_decimal resolved.clock_period_ns ~decimal_digits:6 : float)];
  [%expect {| 20.833333 |}]
;;

let%expect_test "malformed wrapper ports fail with their name and direction" =
  error_contains
    (resolve ~design:(module Bad_width : Project.Design) ())
    "TT top-level port has the wrong width";
  error_contains
    (resolve ~design:(module Wrong_direction : Project.Design) ())
    "TT top-level port has the wrong direction";
  [%expect {| |}]
;;

let%expect_test "metadata and all 24 pin meanings are required" =
  error_contains (resolve ~pinout:(List.tl_exn pinout) ()) "missing TT pin descriptions";
  error_contains
    (resolve ~pinout:(List.hd_exn pinout :: pinout) ())
    "duplicate TT pin description";
  error_contains
    (resolve ~metadata:{ metadata with author = "  " } ())
    "TT metadata needs a nonblank author";
  [%expect {| |}]
;;

let%expect_test "clock and I/O delay endpoints resolve with nanosecond units" =
  let timing =
    { Timing.empty with input_delays =
        [ { port = "ui_in"
          ; minimum = Time_float.Span.of_ns 0.5
          ; maximum = Time_float.Span.of_ns 3.
          }
        ]
    ; output_delays =
        [ { port = "uo_out"
          ; minimum = Time_float.Span.of_ns (-1.)
          ; maximum = Time_float.Span.of_ns 4.
          }
        ]
    }
  in
  let delay port ~minimum ~maximum : Timing.Delay.t =
    { port
    ; minimum = Time_float.Span.of_ns minimum
    ; maximum = Time_float.Span.of_ns maximum
    }
  in
  let resolved = resolve ~timing () |> ok_exn in
  print_s
    [%sexp
      (resolved.input_delays_ns : Resolved_flow.Delay_ns.t list)
      , (resolved.output_delays_ns : Resolved_flow.Delay_ns.t list)];
  [%expect {|
    ((((port ui_in)  (minimum 0.5) (maximum 3)))
     (((port uo_out) (minimum -1)  (maximum 4))))
    |}];
  error_contains
    (resolve
       ~timing:
         { timing with
           input_delays = [ delay "uo_out" ~minimum:0. ~maximum:3. ]
         }
       ())
    "nonclock top-level port";
  error_contains
    (resolve ~clocks:[ { port = "rst_n"; period = Time_float.Span.of_ns 20. } ] ())
    "exactly one primary clock on clk";
  error_contains
    (resolve
       ~timing:
         { timing with
           input_delays = [ delay "ui_in" ~minimum:(-2.) ~maximum:(-1.) ]
         }
       ())
    "nonnegative";
  error_contains
    (resolve
       ~timing:
         { timing with input_delays = [ delay "ui_in" ~minimum:2. ~maximum:1. ] }
       ())
    "no greater than its maximum";
  error_contains
    (resolve
       ~timing:
         { timing with
           output_delays = [ delay "uo_out" ~minimum:Float.nan ~maximum:1. ]
         }
       ())
    "no greater than its maximum";
  error_contains
    (resolve
       ~timing:{ timing with input_delays = timing.input_delays @ timing.input_delays }
       ())
    "declared more than once";
  [%expect {| |}]
;;

let%expect_test "LibreLane override provenance and protected assignments" =
  let override key value reason : Flow.Librelane.Override.t = { key; value; reason } in
  let flow =
    Flow.librelane
      Hardening
      ~overrides:[ override "PL_TARGET_DENSITY_PCT" (`Int 60) "consumer floorplan" ]
  in
  let resolved = resolve ~flow () |> ok_exn in
  let density =
    List.find_exn resolved.settings ~f:(fun setting ->
      String.equal setting.key "PL_TARGET_DENSITY_PCT")
  in
  print_s [%sexp (density : Resolved_flow.Setting.t)];
  [%expect
    {|
    ((key   PL_TARGET_DENSITY_PCT)
     (value 60)
     (owner (Override "consumer floorplan")))
    |}];
  List.iter
    [ "MACROS"
    ; "CLOCK_PERIOD"
    ; "VERILOG_FILES"
    ; "DIE_AREA"
    ; "PNR_SDC_FILE"
    ; "EXTRA_LEFS"
      (* The constraint environment: the SDC is its only authority, so none of these may
         be set by hand, whether LibreLane still reads it (the first four) or no longer
         reads it at all now that PNR_SDC_FILE replaces base.sdc *)
    ; "SYNTH_DRIVING_CELL"
    ; "OUTPUT_CAP_LOAD"
    ; "MAX_FANOUT_CONSTRAINT"
    ; "MAX_TRANSITION_CONSTRAINT"
    ; "CLOCK_UNCERTAINTY_CONSTRAINT"
    ; "CLOCK_TRANSITION_CONSTRAINT"
    ; "TIME_DERATING_CONSTRAINT"
    ; "IO_DELAY_CONSTRAINT"
    ]
    ~f:(fun key ->
      error_contains
        (resolve
           ~flow:
             (Flow.librelane
                Hardening
                ~overrides:[ override key (`Int 1) "test conflict" ])
           ())
        "override conflicts");
  [%expect {| |}]
;;

(* The library's own TT CMOS5L defaults, resolved: every one has to survive as the value
   it declares, owned by Override with its reason. A default that collided with a
   protected key would fail [resolve] outright, and one Resolved_flow also derives would
   be dropped silently, so both are checked here rather than in test_tt_cmos5l.ml, which
   never resolves an elaborated project. *)
let%expect_test "the TT CMOS5L template defaults fit the override boundary" =
  let overrides = Tt_cmos5l.overrides () in
  let resolved = resolve ~flow:(Flow.librelane Hardening ~overrides) () |> ok_exn in
  List.iter overrides ~f:(fun (override : Flow.Librelane.Override.t) ->
    let setting =
      List.find_exn resolved.settings ~f:(fun setting ->
        String.equal setting.key override.key)
    in
    require (Yojson.Safe.equal setting.value override.value);
    require
      (Sexp.equal
         (Resolved_flow.Setting.Owner.sexp_of_t setting.owner)
         (Resolved_flow.Setting.Owner.sexp_of_t (Override override.reason))));
  [%expect {| |}]
;;

let%expect_test "simulation elaboration is not a runnable flow input" =
  let elaborated_project = Project.elaborate (project ()) ~mode:Simulation |> ok_exn in
  error_contains
    (Resolved_flow.resolve elaborated_project) "requires implementation elaboration";
  [%expect {| |}]
;;

let%expect_test "unsupported target fails at the flow boundary" =
  error_contains
    (Project.elaborate_for_flow (Fixture.project () |> ok_exn))
    "unsupported target combination";
  [%expect {| |}]
;;

let%expect_test "adapter view requirements differ by operation" =
  let target =
    Target.resolve
      (Elaborated_project.target (Project.elaborate (project ()) ~mode:Implementation |> ok_exn))
    |> ok_exn
  in
  let without_gds =
    { target with
      views =
        List.filter target.views ~f:(fun view ->
          match view.role with
          | Technology_view Standard_cell_gds -> false
          | _ -> true)
    }
  in
  let synthesis =
    Project.elaborate (project ~flow:(Flow.librelane Synthesis) ()) ~mode:Implementation
    |> ok_exn
  in
  let hardening = Project.elaborate (project ()) ~mode:Implementation |> ok_exn in
  ignore (Resolved_flow.validate_capabilities synthesis without_gds |> ok_exn : unit);
  error_contains
    (Resolved_flow.validate_capabilities hardening without_gds)
    "lacks required technology views";
  [%expect {| |}]
;;

let%expect_test "invalid JSON and malformed keys are rejected at declaration" =
  let override key value : Flow.Librelane.Override.t = { key; value; reason = "test" } in
  List.iter
    [ override "CLOCK_PERIOD " (`Int 1)
    ; override "VALID_KEY" (`Float Float.nan)
    ; override "VALID_KEY" (`Tuple [ `Int 1 ])
    ]
    ~f:(fun setting ->
      error_contains
        (Flow.validate (Flow.librelane Hardening ~overrides:[ setting ]))
        "strict JSON value");
  [%expect {| |}]
;;
