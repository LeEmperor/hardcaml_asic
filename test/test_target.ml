open! Core
open! Hardcaml_asic
open! Expect_test_helpers_core

let reference_target =
  { Target.harness = Tiny_tapeout { tiles = T6x4 }
  ; technology = Technology.ihp_sg13cmos5l
  }
;;

let%expect_test "pinned TT CMOS5L target resolves deterministically" =
  let a = Target.resolve reference_target |> ok_exn in
  let b = Target.resolve reference_target |> ok_exn in
  require (Sexp.equal (Target.Resolved.sexp_of_t a) (Target.Resolved.sexp_of_t b));
  print_s
    [%sexp
      { tiles = (a.tiles : string)
      ; die_area_um = (a.die_area_um : Target.Rectangle_um.t)
      ; floorplan = (a.floorplan : Target.Reference.t)
      ; harness_power_pins = (a.harness_power_pins : string * string)
      ; standard_cell_power_pins = (a.standard_cell_power_pins : string * string)
      ; routing_layers = (a.routing_layers : string list)
      ; top_routing_layer = (a.top_routing_layer : string)
      ; corner = (a.corner : string)
      ; views = (a.views : Target.Reference.t list)
      }];
  [%expect
    {|
    ((tiles 6x4)
     (die_area_um (
       (x_min 0)
       (y_min 0)
       (x_max 1289.28)
       (y_max 710.64)))
     (floorplan (
       (source   Support_tools)
       (revision da63c9927411e3aca350977d653d24bbf5bca972)
       (role     Floorplan_def)
       (path tech/ihp-sg13cmos5l/def/tt_block_6x4_pgvdd.def)
       (sha256 (b46d9a0ee8352160e48dbc8312f092f985629061df736c7f46d58686535a76f4))
       (corner ())))
     (harness_power_pins       (VPWR VGND))
     (standard_cell_power_pins (VDD  VSS))
     (routing_layers (Metal2 Metal3 Metal4))
     (top_routing_layer Metal4)
     (corner            nom_typ_1p20V_25C)
     (views (
       ((source   Pdk)
        (revision 2bbec755dc67ca3db0261c3d6163e15735d66710)
        (role (Technology_view Pdk_configuration))
        (path libs.tech/librelane/config.tcl)
        (sha256 ())
        (corner ()))
       ((source   Pdk)
        (revision 2bbec755dc67ca3db0261c3d6163e15735d66710)
        (role (Technology_view Technology_lef))
        (path libs.ref/sg13cmos5l_stdcell/lef/sg13cmos5l_tech.lef)
        (sha256 ())
        (corner ()))
       ((source   Pdk)
        (revision 2bbec755dc67ca3db0261c3d6163e15735d66710)
        (role (Technology_view Standard_cell_lef))
        (path libs.ref/sg13cmos5l_stdcell/lef/sg13cmos5l_stdcell.lef)
        (sha256 ())
        (corner ()))
       ((source   Pdk)
        (revision 2bbec755dc67ca3db0261c3d6163e15735d66710)
        (role (Technology_view Standard_cell_gds))
        (path libs.ref/sg13cmos5l_stdcell/gds/sg13cmos5l_stdcell.gds)
        (sha256 ())
        (corner ()))
       ((source   Pdk)
        (revision 2bbec755dc67ca3db0261c3d6163e15735d66710)
        (role (Technology_view Standard_cell_verilog))
        (path libs.ref/sg13cmos5l_stdcell/verilog/sg13cmos5l_stdcell.v)
        (sha256 ())
        (corner ()))
       ((source   Pdk)
        (revision 2bbec755dc67ca3db0261c3d6163e15735d66710)
        (role (Technology_view Standard_cell_liberty))
        (path
         libs.ref/sg13cmos5l_stdcell/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib)
        (sha256 ())
        (corner (nom_typ_1p20V_25C))))))
    |}]
;;

let%expect_test "unsupported tile and technology are rejected" =
  let unsupported_tile =
    { reference_target with harness = Tiny_tapeout { tiles = T1x1 } }
  in
  let unsupported_technology =
    { reference_target with
      technology = Technology.create_exn ~name:"fixture-tech" ~resource_mappings:[]
    }
  in
  List.iter [ unsupported_tile; unsupported_technology ] ~f:(fun target ->
    match Target.resolve target with
    | Ok _ -> failwith "unsupported target unexpectedly resolved"
    | Error error -> print_endline (Error.to_string_hum error));
  [%expect
    {|
    ("unsupported target combination; the reference resolver supports TT 6x4 with IHP SG13 CMOS5L"
     (tiles (Tiny_tapeout (tiles T1x1))) (technology ihp-sg13cmos5l))
    ("unsupported target combination; the reference resolver supports TT 6x4 with IHP SG13 CMOS5L"
     (tiles (Tiny_tapeout (tiles T6x4))) (technology fixture-tech))
    |}]
;;

let%expect_test "reference technology identity cannot be forged" =
  require_does_raise (fun () ->
    Technology.create_exn
      ~name:"ihp-sg13cmos5l"
      ~resource_mappings:[]
    |> ignore);
  [%expect
    {| "ihp-sg13cmos5l is a reserved reference technology; use Technology.ihp_sg13cmos5l" |}]
;;

let%expect_test "the pinned constraint environment resolves onto the target" =
  let resolved = Target.resolve reference_target |> ok_exn in
  print_s [%sexp (resolved.constraints : Technology.Cmos5l.Constraints.t)];
  [%expect
    {|
    ((driving_cell          sg13cmos5l_buf_4)
     (driving_cell_pin      X)
     (output_cap_load_ff    6)
     (max_fanout            10)
     (clock_uncertainty_ns  0.25)
     (clock_transition_ns   0.15)
     (time_derating_percent 5))
    |}];
  (* The load converts into the Liberty's picofarad capacitive_load_unit for set_load *)
  require
    (Float.equal
       (Technology.Cmos5l.Constraints.output_cap_load_pf resolved.constraints)
       0.006);
  print_endline
    (Technology.Cmos5l.Constraints.driving_cell_setting resolved.constraints);
  [%expect {| sg13cmos5l_buf_4/X |}]
;;

let%expect_test "an unusable constraint environment is rejected with every reason" =
  let base = Target.Inputs.reference_cmos5l_6x4 in
  let inputs constraints = { base with constraints } in
  List.iter
    [ inputs { base.constraints with driving_cell = "sg13cmos5l_buf_4/X" }
    ; inputs
        { base.constraints with
          output_cap_load_ff    = -1.
        ; max_fanout            = 0
        ; clock_uncertainty_ns  = Float.nan
        ; clock_transition_ns   = -0.1
        ; time_derating_percent = 100.
        }
    ]
    ~f:(fun inputs ->
      match Target.resolve ~inputs reference_target with
      | Ok _ -> failwith "an unusable constraint environment unexpectedly resolved"
      | Error error -> print_endline (Error.to_string_hum error));
  [%expect
    {|
    ("unusable timing constraint environment; correct the values named below"
     (problems ("driving cell and pin must be nonblank and contain no \"/\""))
     (constraints
      ((driving_cell sg13cmos5l_buf_4/X) (driving_cell_pin X)
       (output_cap_load_ff 6) (max_fanout 10) (clock_uncertainty_ns 0.25)
       (clock_transition_ns 0.15) (time_derating_percent 5))))
    ("unusable timing constraint environment; correct the values named below"
     (problems
      ("output capacitive load must be finite and nonnegative"
       "maximum fanout must be positive"
       "clock uncertainty must be finite and nonnegative"
       "clock transition must be finite and nonnegative"
       "timing derate must be finite and at least 0% but below 100%"))
     (constraints
      ((driving_cell sg13cmos5l_buf_4) (driving_cell_pin X)
       (output_cap_load_ff -1) (max_fanout 0) (clock_uncertainty_ns NAN)
       (clock_transition_ns -0.1) (time_derating_percent 100))))
    |}]
;;

let%expect_test "missing or malformed target inputs fail before use" =
  let base = Target.Inputs.reference_cmos5l_6x4 in
  let missing_view =
    { base with
      technology_views =
        List.filter base.technology_views ~f:(fun view ->
          not
            (Technology.Cmos5l.View.Role.equal
               view.role
               Standard_cell_liberty))
    }
  in
  let malformed =
    { base with
      pdk_revision = ""
    ; floorplan_path = "../wrong.def"
    ; floorplan_sha256 = ""
    }
  in
  List.iter [ missing_view; malformed ] ~f:(fun inputs ->
    match Target.resolve ~inputs reference_target with
    | Ok _ -> failwith "invalid target inputs unexpectedly resolved"
    | Error error -> print_endline (Error.to_string_hum error));
  [%expect
    {|
    ("missing required CMOS5L views" (missing (Standard_cell_liberty)))
    ("target inputs need full lowercase Git revisions"
     "TT CMOS5L 6x4 target needs its pinned relative floorplan DEF path"
     "target inputs need a floorplan SHA-256")
    |}]
;;
