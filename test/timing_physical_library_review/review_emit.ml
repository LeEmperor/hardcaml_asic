(* Independent review consumer. Does not modify or duplicate the resolver. *)
open! Core
open! Hardcaml
open! Hardcaml_asic

let all_stages = List.concat_map ["rr"; "rx"] ~f:(fun chain ->
  List.init 2 ~f:(fun index -> Timing.Stage.create ~id:(chain^Int.to_string index) ~chain ~index))
let stage id = List.find_exn all_stages ~f:(fun s -> String.equal s.id id)

let resolve variant =
  let declared=if String.equal variant "empty" then [] else if String.equal variant "partial" then List.take all_stages 2 else all_stages in
  let timing=Timing.create ~stages:declared ~exceptions:(if List.length declared<>4 then [] else [
    Timing.Exception.async_capture ~id:"capture" ~reason:"independent literal capture scope"
      ~source:(Timing.Port.bit (Timing.Port.input "ui_in") 0) ~first_stage:(stage "rx0");
    Timing.Exception.async_reset ~id:"reset" ~reason:"independent explicit reset scope"
      ~source:(Timing.Port.input "rst_n") ~targets:all_stages]) () in
  let module Design = struct
    module I=Tt_cmos5l.I
    module O=Tt_cmos5l.O
    let name="tt_um_library_review"
    let create context (i:_ I.t) =
      let open Signal in
      let spec=Reg_spec.create ~clock:i.clk ~reset:i.rst_n ~reset_level:Low () in
      let register id d =
        let q=reg spec d in
        if List.exists declared ~f:(fun s -> String.equal s.id id) then (
          if String.equal variant "reserved_anchor" && String.equal id "rr0" then ignore (q -- "hc_pt7_unowned" : Signal.t);
          Elaboration.Context.register_timing_stage_exn context ~stage:(stage id) ~q;
          if String.equal variant "same_q" && String.equal id "rr0" then
            Elaboration.Context.register_timing_stage_exn context ~stage:(stage "rr1") ~q);
        q in
      let rr0=register "rr0" i.ena in
      let rr1=register "rr1" rr0 in
      let rx0=register "rx0" (bit i.ui_in ~pos:0) in
      let rx1=register "rx1" (if String.equal variant "wrong_architectural_predecessor" then rr0 else rx0) in
      {O.uo_out=uresize (rr1 &: rx1 &: i.ena) ~width:8;uio_out=zero 8;uio_oe=zero 8}
  end in
  let open Or_error.Let_syntax in
  let%bind policy=Resource_policy.create ~default:Flops [] in
  let%bind project=Project.create ~name:"physical_library_review" ~design:(module Design)
    ~metadata:{title="Independent library review";author="reviewer";description="No EDA"}
    ~target:{harness=Tiny_tapeout {tiles=T6x4};technology=Technology.ihp_sg13cmos5l}
    ~flow:(Flow.librelane Hardening) ~clocks:[{Clock.port="clk";period=Time_float.Span.of_ns 20.}]
    ~pinout:(List.concat_map [Pinout.Bank.Ui;Uo;Uio] ~f:(fun bank -> List.init 8 ~f:(fun bit -> {Pinout.bank;bit;description="review fixture"})))
    ~timing ~policy () in
  Project.elaborate_for_flow project

let print j=print_endline (Yojson.Safe.to_string j)
let () =
  match Array.to_list (Sys.get_argv ()) with
  | [_;"verify"] ->
    let manifest=Yojson.Safe.from_channel Stdlib.stdin in
    print (`Assoc ["valid",`Bool (Result.is_ok (Bundle.verify_manifest_identity manifest))])
  | [_;"emit";variant;root] ->
    (match resolve variant with
     | Error error -> print (`Assoc ["status",`String "rejected";"error",`String (Error.to_string_hum error)])
     | Ok resolved ->
       let render ?timing_physical_qualification () =
         Bundle.render ?timing_physical_qualification ~source_root:root ~input_paths:["dune-project"] resolved in
       let encode = function
         | Error error -> `Assoc ["status",`String "rejected";"error",`String (Error.to_string_hum error)]
         | Ok bundle ->
           let top=Yojson.Safe.Util.(Bundle.manifest bundle |> member "top_module" |> to_string) in
           `Assoc ["status",`String "emitted";"manifest",Bundle.manifest bundle;
             "sdc",`String (Option.value_exn (Bundle.file bundle "constraints/top.sdc"));
             "rtl",`String (Option.value_exn (Bundle.file bundle ("src/"^top^".v")));
             "native",`String (Option.value (Bundle.file bundle "constraints/pt7-native-coverage.tcl") ~default:"")] in
       print (`Assoc ["default",encode (render ());"false",encode (render ~timing_physical_qualification:false ());
         "physical",encode (render ~timing_physical_qualification:true ())]))
  | _ -> failwith "review_emit emit VARIANT SOURCE_ROOT | verify"
