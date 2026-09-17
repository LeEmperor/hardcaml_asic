(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "test_single_port_ram.ml" *)
(* P1: contract checks for Single_port_ram, run against both the behavioral model and the
   flop implementation.

   The scoreboard follows docs/program-memory-contract.md section 9: it compares defined
   read data across implementations, checks hold within each one, and checks poison for
   the behavioral model only. The technology in the macro test is a test input, not
   evidence of a real macro backend. *)

open! Core
open! Hardcaml
open! Hardcaml_asic
open! Expect_test_helpers_core

module I = struct
  type 'a t =
    { clock : 'a
    ; enable : 'a
    ; write_enable : 'a
    ; address : 'a [@bits 2]
    ; write_data : 'a [@bits 8]
    }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t = { read_data : 'a [@bits 8] } [@@deriving hardcaml]
end

let config = Single_port_ram.Config.create_exn ~width:8 ~depth:3 ~read_latency:1

(* A top level wrapping one RAM named "program"; [bad_address] widens the address by one
   bit to trip the port width check. *)
let design ?(bad_address = false) () : (module Project.Design) =
  (module struct
    module I = I
    module O = O

    let name = "ram_top"

    let create context (i : _ I.t) =
      let address =
        if bad_address then Signal.concat_msb [ Signal.vdd; i.address ] else i.address
      in
      { O.read_data =
          Single_port_ram.create
            context
            ~name:"program"
            config
            ~clock:i.clock
            ~enable:i.enable
            ~write_enable:i.write_enable
            ~address
            ~write_data:i.write_data
      }
    ;;
  end)
;;

let elaborate ~mode ~policy ?(design = design ()) () =
  let project = Fixture.project ~design ~policy () |> ok_exn in
  Project.elaborate project ~mode
;;

let policy requirement = Resource_policy.create ~default:requirement [] |> ok_exn

(* One cycle of stimulus; [data] only matters on an enabled write. *)
type operation =
  { enable : bool
  ; write : bool
  ; address : int
  ; data : int
  }

let op ?(enable = true) ?(write = false) ?(address = 0) ?(data = 0) () =
  { enable; write; address; data }
;;

(* Seeded from the contract section 4 trace, extended with a disabled write, holds after
   defined and unspecified outputs, an unwritten read and an overwrite. *)
let trace =
  [ op ~write:true ~address:0 ~data:0x31 ()
  ; op ~enable:false ~write:true ~address:1 ~data:0x55 ()
  ; op ~address:0 ()
  ; op ~enable:false ()
  ; op ~address:1 ()
  ; op ~write:true ~address:2 ~data:0x7e ()
  ; op ~enable:false ()
  ; op ~address:2 ()
  ; op ~address:0 ()
  ; op ~write:true ~address:0 ~data:0xa4 ()
  ; op ~address:0 ()
  ; op ~enable:false ()
  ]
;;

(* Elaborate in [mode], check the registered record, then replay [trace] against a model
   of the contract. [expected] is [None] whenever the contract leaves the output
   unspecified. *)
let run_scoreboard mode =
  let build = elaborate ~mode ~policy:(policy Flops) () |> ok_exn in
  let record = List.hd_exn (Build.resources build) in
  assert (String.equal (Resource_id.to_string record.id) "program");
  assert (
    Resource_request.equal
      record.request
      (Resource_request.create_exn
         ~kind:"single_port_ram"
         ~contract:
           [%sexp
             { width = (8 : int)
             ; depth = (3 : int)
             ; read_latency = (1 : int)
             ; port = ("1rw" : string)
             ; disabled_output = ("hold" : string)
             ; write_output = ("unspecified" : string)
             }]));
  let expected_source =
    match mode with
    | Simulation -> Resource_record.Source.Generated_behavioral_model
    | Implementation -> Generated_synthesis_rtl
  in
  assert (List.equal Resource_record.Source.equal record.sources [ expected_source ]);
  let sim = Cyclesim.create (Build.circuit build) in
  let set port value =
    Cyclesim.in_port sim port
    := Bits.of_int_trunc ~width:(Bits.width !(Cyclesim.in_port sim port)) value
  in
  let stored = Array.create ~len:3 None in
  let expected = ref None in
  let prior = ref None in
  List.iteri trace ~f:(fun cycle operation ->
    set "enable" (Bool.to_int operation.enable);
    set "write_enable" (Bool.to_int operation.write);
    set "address" operation.address;
    set "write_data" operation.data;
    Cyclesim.cycle sim;
    let actual = !(Cyclesim.out_port sim "read_data") in
    if not operation.enable
    then
      Option.iter !prior ~f:(fun previous ->
        if not (Bits.equal actual previous)
        then
          failwithf
            "%s cycle %d: disabled output changed"
            (Elaboration_mode.sexp_of_t mode |> Sexp.to_string)
            cycle
            ());
    expected
    := if not operation.enable
       then !expected
       else if operation.write
       then None
       else stored.(operation.address);
    Option.iter !expected ~f:(fun value ->
      let wanted = Bits.of_int_trunc ~width:8 value in
      if not (Bits.equal actual wanted)
      then
        failwithf "cycle %d: expected %02x, got %s" cycle value (Bits.to_bstr actual) ());
    if Elaboration_mode.equal mode Simulation
    then (
      let poison =
        if operation.write
        then Some 0x55
        else if operation.enable && Option.is_none stored.(operation.address)
        then Some (if operation.address mod 2 = 0 then 0x55 else 0xaa)
        else None
      in
      Option.iter poison ~f:(fun value ->
        let wanted = Bits.of_int_trunc ~width:8 value in
        if not (Bits.equal actual wanted)
        then
          failwithf
            "cycle %d: expected poison %02x, got %s"
            cycle
            value
            (Bits.to_bstr actual)
            ()));
    if operation.enable && operation.write
    then stored.(operation.address) <- Some operation.data;
    prior := Some actual);
  build
;;

let%test_unit "one scoreboard checks behavioral and flop elaborations" =
  ignore (run_scoreboard Simulation : Build.t);
  ignore (run_scoreboard Implementation : Build.t)
;;

let%test_unit "behavioral out-of-range access is diagnostic and does not wrap" =
  let build = elaborate ~mode:Simulation ~policy:(policy Flops) () |> ok_exn in
  let sim = Cyclesim.create (Build.circuit build) in
  let set port width value =
    Cyclesim.in_port sim port := Bits.of_int_trunc ~width value
  in
  let cycle ~enable ~write ~address ~data =
    set "enable" 1 enable;
    set "write_enable" 1 write;
    set "address" 2 address;
    set "write_data" 8 data;
    Cyclesim.cycle sim;
    !(Cyclesim.out_port sim "read_data")
  in
  ignore (cycle ~enable:1 ~write:1 ~address:0 ~data:0x19 : Bits.t);
  let out_of_range = cycle ~enable:1 ~write:1 ~address:3 ~data:0xee in
  assert (Bits.equal out_of_range (Bits.of_int_trunc ~width:8 0xaa));
  let original = cycle ~enable:1 ~write:0 ~address:0 ~data:0 in
  assert (Bits.equal original (Bits.of_int_trunc ~width:8 0x19));
  let out_of_range = cycle ~enable:1 ~write:0 ~address:3 ~data:0 in
  assert (Bits.equal out_of_range (Bits.of_int_trunc ~width:8 0xaa))
;;

let%test_unit "flop RTL renders without behavioral initialization" =
  let flop = elaborate ~mode:Implementation ~policy:(policy Flops) () |> ok_exn in
  let behavioral = elaborate ~mode:Simulation ~policy:(policy Flops) () |> ok_exn in
  let render build =
    Rtl.create Verilog [ Build.circuit build ] |> Rtl.full_hierarchy |> Rope.to_string
  in
  let flop_rtl = render flop in
  let behavioral_rtl = render behavioral in
  if String.is_substring flop_rtl ~substring:"initial"
  then failwith "flop RTL unexpectedly contains initialization";
  if not (String.is_substring behavioral_rtl ~substring:"initial")
  then failwith "behavioral model lost its diagnostic initialization"
;;

let%test_unit "RAM inventory is repeatable and fallback is recorded" =
  let explicit = elaborate ~mode:Implementation ~policy:(policy Flops) () |> ok_exn in
  let repeated = elaborate ~mode:Implementation ~policy:(policy Flops) () |> ok_exn in
  assert (
    List.equal Resource_record.equal (Build.resources explicit) (Build.resources repeated));
  let fallback =
    elaborate ~mode:Implementation ~policy:(policy Exact_or_flop_fallback) () |> ok_exn
  in
  let selected = (List.hd_exn (Build.resources fallback)).selection in
  assert (Selection.Implementation.equal selected.implementation Flops);
  assert (
    Selection.Reason.equal
      selected.reason
      (Selection.Reason.Flop_fallback { no_exact_mapping_in = "ihp-sg13cmos5l" }))
;;

let%test_unit "an unimplemented macro mapping cannot masquerade as RAM hardware" =
  let build = elaborate ~mode:Implementation ~policy:(policy Flops) () |> ok_exn in
  let request = (List.hd_exn (Build.resources build)).request in
  let technology =
    Technology.create_exn
      ~name:"test-macro-technology"
      ~resource_mappings:[ { request; macro = { name = "test_macro"; collateral = [] } } ]
  in
  let project =
    Fixture.project ~technology ~design:(design ()) ~policy:(policy Exact) () |> ok_exn
  in
  let simulation = Project.elaborate project ~mode:Simulation |> ok_exn in
  let record = List.hd_exn (Build.resources simulation) in
  assert (Resource_record.Elaborated_as.equal record.elaborated_as Behavioral_model);
  match Project.elaborate project ~mode:Implementation with
  | Ok _ -> failwith "unimplemented macro backend was accepted"
  | Error error ->
    if not
         (String.is_substring
            (Error.to_string_hum error)
            ~substring:"single-port RAM macro backend is unavailable")
    then Error.raise error
;;

let%expect_test "invalid RAM port and unsupported selection identify the instance" =
  let bad =
    elaborate
      ~mode:Implementation
      ~policy:(policy Flops)
      ~design:(design ~bad_address:true ())
      ()
  in
  print_s [%sexp (bad : Build.t Or_error.t)];
  let unsupported = elaborate ~mode:Implementation ~policy:(policy Exact) () in
  print_s [%sexp (unsupported : Build.t Or_error.t)];
  [%expect
    {|
    (Error (
      ("design construction failed"
        (project fixture)
        (mode    Implementation))
      ("single-port RAM port width mismatch"
        (instance program)
        (port     address)
        (expected 2)
        (actual   3))))
    (Error (
      ("design construction failed"
        (project fixture)
        (mode    Implementation))
      (("resource selection failed"
         (instance program)
         (request (
           (kind single_port_ram)
           (contract (
             (width           8)
             (depth           3)
             (read_latency    1)
             (port            1rw)
             (disabled_output hold)
             (write_output    unspecified))))))
       ("technology has no exact implementation for the requested contract, and flop fallback is not permitted"
        (technology ihp-sg13cmos5l)))))
    |}]
;;
