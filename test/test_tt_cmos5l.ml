open! Core
open! Hardcaml
open! Hardcaml_asic
open! Expect_test_helpers_core

(* The ports a TT design gets by using the library's interface have to be the ports
   Resolved_build.validate_interface insists on; if these ever disagree, every design
   built on Tt_cmos5l.I fails to resolve. *)
let%expect_test "the wrapper interface is the TT wrapper interface" =
  let inputs = Tt_cmos5l.I.(to_list port_names_and_widths) in
  let outputs = Tt_cmos5l.O.(to_list port_names_and_widths) in
  require (List.equal Poly.equal inputs Resolved_build.expected_inputs);
  require (List.equal Poly.equal outputs Resolved_build.expected_outputs);
  print_s [%sexp { inputs : (string * int) list; outputs : (string * int) list }];
  [%expect
    {|
    ((inputs (
       (ui_in  8)
       (uio_in 8)
       (ena    1)
       (clk    1)
       (rst_n  1)))
     (outputs (
       (uo_out  8)
       (uio_out 8)
       (uio_oe  8))))
    |}]
;;

(* The values, without the reasons; this is the list a consumer's config.json is built
   from, so a change here is a change to every TT CMOS5L chip. *)
let%expect_test "template defaults" =
  print_s
    [%sexp
      (List.map Tt_cmos5l.template_overrides ~f:(fun o ->
         o.key, Yojson.Safe.to_string o.value)
       : (string * string) list)];
  [%expect
    {|
    ((PL_TARGET_DENSITY_PCT             60)
     (PL_RESIZER_HOLD_SLACK_MARGIN      0.1)
     (GRT_RESIZER_HOLD_SLACK_MARGIN     0.05)
     (LINTER_INCLUDE_PDK_MODELS         1)
     (RUN_KLAYOUT_XOR                   0)
     (RUN_KLAYOUT_DRC                   0)
     (DESIGN_REPAIR_BUFFER_OUTPUT_PORTS 0)
     (TOP_MARGIN_MULT                   1)
     (BOTTOM_MARGIN_MULT                1)
     (LEFT_MARGIN_MULT                  6)
     (RIGHT_MARGIN_MULT                 6)
     (GRT_ALLOW_CONGESTION              1)
     (FP_IO_HLENGTH                     2)
     (FP_IO_VLENGTH                     2)
     (FP_PDN_VPITCH                     50.0)
     (FP_PDN_VWIDTH                     2.1)
     (RUN_CTS                           1)
     (FP_PDN_MULTILAYER                 0)
     (MAGIC_DEF_LABELS                  0)
     (MAGIC_WRITE_LEF_PINONLY           1))
    |}]
;;

(* Two things that would make a default useless: a reason that does not carry the
   provenance, and a key Resolved_build would refuse as an override anyway. *)
let%expect_test "every default carries its provenance and is overridable" =
  let missing_revision =
    List.filter_map Tt_cmos5l.template_overrides ~f:(fun o ->
      if String.is_substring o.reason ~substring:Tt_cmos5l.template_revision
      then None
      else Some o.key)
  in
  let protected =
    List.filter_map Tt_cmos5l.template_overrides ~f:(fun o ->
      if Resolved_build.protected_key o.key then Some o.key else None)
  in
  print_s
    [%sexp
      { missing_revision : string list; protected : string list }];
  [%expect
    {|
    ((missing_revision ())
     (protected        ()))
    |}]
;;

(* The point of the module: change one entry, keep the other nineteen. *)
let%expect_test "a consumer replaces one default and adds one key" =
  let mine : Flow.Librelane.Override.t list =
    [ { key = "RUN_KLAYOUT_DRC"
      ; value = `Int 1
      ; reason = "in-flow signoff for the tapeout run"
      }
    ; { key = "SYNTH_STRATEGY"
      ; value = `String "AREA 0"
      ; reason = "the tile is area bound"
      }
    ]
  in
  let merged = Tt_cmos5l.overrides ~extra:mine () in
  let show key =
    List.find merged ~f:(fun o -> String.equal o.key key)
    |> Option.map ~f:(fun o -> Yojson.Safe.to_string o.value, o.reason)
  in
  print_s
    [%sexp
      { count = (List.length merged : int)
      ; run_klayout_drc = (show "RUN_KLAYOUT_DRC" : (string * string) option)
      ; synth_strategy = (show "SYNTH_STRATEGY" : (string * string) option)
      ; run_klayout_xor_untouched =
          (Option.map (show "RUN_KLAYOUT_XOR") ~f:fst : string option)
      }];
  [%expect
    {|
    ((count 21)
     (run_klayout_drc ((1 "in-flow signoff for the tapeout run")))
     (synth_strategy (("\"AREA 0\"" "the tile is area bound")))
     (run_klayout_xor_untouched (0)))
    |}]
;;

(* [without] is the other half: hand a key back to LibreLane's own default. *)
let%expect_test "a consumer drops a default" =
  let merged = Tt_cmos5l.overrides ~without:[ "GRT_ALLOW_CONGESTION" ] () in
  print_s
    [%sexp
      { count = (List.length merged : int)
      ; present =
          (List.exists merged ~f:(fun o -> String.equal o.key "GRT_ALLOW_CONGESTION")
           : bool)
      }];
  [%expect
    {|
    ((count   19)
     (present false))
    |}]
;;

(* A [without] that names nothing would silently leave the default in the bundle, which
   is exactly the failure the raise exists to prevent. *)
let%expect_test "dropping a key that is not a default" =
  require_does_raise (fun () -> Tt_cmos5l.overrides ~without:[ "RUN_KLAYOUT_DRC " ] ());
  [%expect
    {|
    ("no TT CMOS5L template default has this key; drop it from [without], or pass it in [extra] to set a key the template does not"
     (unknown ("RUN_KLAYOUT_DRC ")))
    |}]
;;

let%expect_test "dropping and setting the same key" =
  require_does_raise (fun () ->
    Tt_cmos5l.overrides
      ~without:[ "RUN_CTS" ]
      ~extra:[ { key = "RUN_CTS"; value = `Int 0; reason = "combinational only" } ]
      ());
  [%expect
    {|
    ("a key cannot be both dropped and set; keep it in [extra] alone, which already replaces the template default"
     (contradicted (RUN_CTS)))
    |}]
;;

(* One stage would build the flop the synchroniser exists to avoid. *)
let%expect_test "a one stage reset synchroniser" =
  let clock = Signal.input "clk" 1 in
  let rst_n = Signal.input "rst_n" 1 in
  require_does_raise (fun () ->
    Tt_cmos5l.synchronised_reset ~stages:1 ~clock ~rst_n ());
  [%expect
    {|
    ("a reset synchroniser needs at least two stages; one stage resynchronises nothing"
     (stages 1))
    |}]
;;
