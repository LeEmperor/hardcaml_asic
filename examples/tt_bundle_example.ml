open! Core
open! Hardcaml
open! Hardcaml_asic

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

module Observable = struct
  module I = I
  module O = O

  let name = "tt_um_asic_observable"

  let create _ (i : _ I.t) =
    let observed =
      Signal.reg
        (Signal.Reg_spec.create ~clock:i.clk ~clear:(Signal.(~:) i.rst_n) ())
        i.ui_in
    in
    { O.uo_out = Signal.mux2 i.ena observed (Signal.zero 8)
    ; uio_out = Signal.zero 8
    ; uio_oe = Signal.zero 8
    }
  ;;
end

module Memory = struct
  module I = I
  module O = O

  let name = "tt_um_asic_memory"
  let config = Single_port_ram.Config.create_exn ~width:8 ~depth:4 ~read_latency:1

  let create context (i : _ I.t) =
    let read_data =
      Single_port_ram.create
        context
        ~name:"program"
        config
        ~clock:i.clk
        ~enable:i.ena
        ~write_enable:(Signal.bit i.ui_in ~pos:2)
        ~address:(Signal.select i.ui_in ~high:1 ~low:0)
        ~write_data:i.uio_in
    in
    { O.uo_out = read_data
    ; uio_out = Signal.zero 8
    ; uio_oe = Signal.zero 8
    }
  ;;
end

let pinout : Pinout.t =
  List.concat_map [ Pinout.Bank.Ui; Uo; Uio ] ~f:(fun bank ->
    List.init 8 ~f:(fun bit ->
      let description =
        match bank with
        | Ui ->
          if bit < 2 then "Memory address / observable input"
          else if bit = 2 then "Memory write enable / observable input"
          else "Observable input"
        | Uo -> "Registered observable or memory read data"
        | Uio -> "Memory write data input; output disabled"
      in
      { Pinout.bank; bit; description }))
;;

(* The remaining settings of the pinned TT CMOS5L template's src/config.json
   (ttihp-verilog-template b86a2a7); clock and default keys are derived instead.
   FP_PDN_MULTILAYER=0 keeps the PDN off TopMetal1, which TT precheck forbids. *)
let template_overrides : Flow.Librelane.Override.t list =
  let reason = "TT CMOS5L template src/config.json at b86a2a7" in
  List.map
    ~f:(fun (key, value) -> { Flow.Librelane.Override.key; value; reason })
    [ "PL_TARGET_DENSITY_PCT", `Int 60
    ; "PL_RESIZER_HOLD_SLACK_MARGIN", `Float 0.1
    ; "GRT_RESIZER_HOLD_SLACK_MARGIN", `Float 0.05
    ; "LINTER_INCLUDE_PDK_MODELS", `Int 1
    ; "RUN_KLAYOUT_XOR", `Int 0
    ; "RUN_KLAYOUT_DRC", `Int 0
    ; "DESIGN_REPAIR_BUFFER_OUTPUT_PORTS", `Int 0
    ; "TOP_MARGIN_MULT", `Int 1
    ; "BOTTOM_MARGIN_MULT", `Int 1
    ; "LEFT_MARGIN_MULT", `Int 6
    ; "RIGHT_MARGIN_MULT", `Int 6
    ; "GRT_ALLOW_CONGESTION", `Int 1
    ; "FP_IO_HLENGTH", `Int 2
    ; "FP_IO_VLENGTH", `Int 2
    ; "FP_PDN_VPITCH", `Float 50.0
    ; "FP_PDN_VWIDTH", `Float 2.1
    ; "RUN_CTS", `Int 1
    ; "FP_PDN_MULTILAYER", `Int 0
    ; "MAGIC_DEF_LABELS", `Int 0
    ; "MAGIC_WRITE_LEF_PINONLY", `Int 1
    ]
;;

let project kind =
  let design, title, description =
    match kind with
    | "observable" ->
      ( (module Observable : Project.Design)
      , "ASIC observable example"
      , "Registered TT input observation" )
    | "memory" ->
      ( (module Memory : Project.Design)
      , "ASIC memory example"
      , "Four-word registered memory with whole-word load and readback" )
    | _ -> failwith "kind must be observable or memory"
  in
  Project.create
    ~name:("asic_" ^ kind)
    ~metadata:{ title; author = "hardcaml_asic"; description }
    ~design
    ~target:
      { harness = Tiny_tapeout { tiles = T6x4 }
      ; technology = Technology.ihp_sg13cmos5l
      }
    ~flow:(Flow.librelane ~overrides:template_overrides Hardening)
    ~clocks:[ { Clock.port = "clk"; period = Time_float.Span.of_sec (1. /. 48e6) } ]
    (* Minimums of 0 are the hold-pessimistic choice: TT inputs are driven asynchronously
       to clk through the mux, so a change right at the clock edge is possible, and the
       template's PL/GRT hold slack margins then make the resizer repair hold with that
       assumption rather than find no hold paths at all. *)
    ~timing:
      (if String.equal kind "observable"
       then
         { Timing.input_delays =
             [ { port = "ui_in"
               ; minimum = Time_float.Span.of_ns 0.
               ; maximum = Time_float.Span.of_ns 1.
               }
             ]
         ; output_delays =
             [ { port = "uo_out"
               ; minimum = Time_float.Span.of_ns 0.
               ; maximum = Time_float.Span.of_ns 2.
               }
             ]
         }
       else Timing.empty)
    ~pinout
    ~policy:(Resource_policy.create ~default:Flops [] |> Or_error.ok_exn)
    ()
  |> Or_error.ok_exn
;;

let source_inputs root =
  let lib = Filename.concat root "lib" in
  let library_files =
    Stdlib.Sys.readdir lib
    |> Array.to_list
    |> List.filter ~f:(fun name ->
      String.is_suffix name ~suffix:".ml" || String.is_suffix name ~suffix:".mli")
    |> List.map ~f:(fun name -> "lib/" ^ name)
  in
  [ "dune-project"; "lib/dune"; "examples/dune"; "examples/tt_bundle_example.ml" ]
  @ library_files
;;

let () =
  let argv = Stdlib.Sys.argv in
  if Array.length argv <> 3 && Array.length argv <> 4
  then failwith "usage: tt_bundle_example (observable|memory) OUTPUT_DIR [SOURCE_ROOT]";
  let kind = argv.(1) in
  let output_dir = argv.(2) in
  let source_root = if Array.length argv = 4 then argv.(3) else "." in
  let project = project kind in
  let resolved = Project.elaborate_for_flow project |> Or_error.ok_exn in
  let simulation_build =
    Project.elaborate project ~mode:Simulation |> Or_error.ok_exn
  in
  let bundle =
    Bundle.render
      ~simulation_build
      ~source_root
      ~input_paths:(source_inputs source_root)
      resolved
    |> Or_error.ok_exn
  in
  Bundle.write bundle ~output_dir |> Or_error.ok_exn;
  printf "%s %s\n" output_dir (Bundle.identity bundle)
;;
