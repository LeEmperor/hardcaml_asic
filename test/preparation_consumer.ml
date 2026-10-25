[@@@alert "-unsafe_multidomain"]
module U = Unix
open! Core
open! Hardcaml
open! Hardcaml_asic
module E = Hardcaml_asic_execution
module J = E.Identity_json
module P = Resource_preparation
let mode = Stdlib.Sys.argv.(1)
let store = Stdlib.Sys.argv.(2)
let source_root = Stdlib.Sys.argv.(3)
let () =
  if List.mem ["open-race-fifo";"open-race-symlink"] mode ~equal:String.equal then (
    try
      ignore (E.Preparation_storage.For_testing.read_bytes ~limit:1024 store
        ~after_lstat:(fun () ->
          if String.equal mode "open-race-fifo" then (U.unlink store;U.mkfifo store 0o600)
          else (U.rename store (store^".moved");U.symlink (store^".moved") store)) : string);
      Stdlib.exit 0
    with exn -> eprintf "%s\n%!" (Exn.to_string exn);Stdlib.exit 2)
module Design = struct
  module I = Tt_cmos5l.I
  module O = Tt_cmos5l.O
  let name = "tt_um_preparation_test"
  let create context (i : _ I.t) =
    let data = if String.equal mode "empty" then i.ui_in else
      Single_port_ram.create context ~name:"program"
        (Single_port_ram.Config.create_exn ~width:8 ~depth:4 ~read_latency:1)
        ~clock:i.clk ~enable:i.ena ~write_enable:(Signal.bit i.ui_in ~pos:2)
        ~address:(Signal.select i.ui_in ~high:1 ~low:0) ~write_data:i.uio_in in
    {O.uo_out=data;uio_out=Signal.zero 8;uio_oe=Signal.zero 8}
end
let prepare ~on_phase =
  if String.equal mode "construct-fail" then failwith "intentional project constructor failure";
  if String.equal mode "malformed-failure" then
    (* Public Failure records can be constructed without the strict decoder. *)
    Error {P.Failure.phase=P.Phase.Construction;diagnostics=[]}
  else (
  if String.equal mode "wait" then (
    (* Signal tests synchronize on allocation, which is flushed before this. *)
    U.sleepf 0.2;
    on_phase P.Phase.Source_before;
    U.sleepf 30.);
  let policy=Resource_policy.create ~default:(if String.equal mode "reject" then Exact else Flops) [] |> Or_error.ok_exn in
  let project=Project.create ~name:"preparation_test" ~metadata:{title="Preparation fixture";author="ASIC";description="Durable operation fixture"}
    ~design:(module Design)
    ~target:{harness=Tiny_tapeout {tiles=T6x4};technology=Technology.ihp_sg13cmos5l}
    ~flow:(Flow.librelane Synthesis)
    ~clocks:[{Clock.port="clk";period=Time_float.Span.of_ns 20.}]
    ~pinout:(List.concat_map [Pinout.Bank.Ui;Uo;Uio] ~f:(fun bank ->
      List.init 8 ~f:(fun bit -> {Pinout.bank;bit;description="Fixture pin"})))
    ~source_inputs:[if String.equal mode "invalid-source" then "missing.ml" else "design.ml"] ~policy () |> Or_error.ok_exn in
  let result=Project.prepare_resources ~on_phase project ~source_root in
  if String.equal mode "invalid-result" then (
    match result with Error _ -> result | Ok p ->
      let json=match P.to_json p with `Assoc xs -> `Assoc (("identity",`String (String.make 64 '0'))::List.Assoc.remove xs "identity" ~equal:String.equal) | _->assert false in
      Ok (P.of_string (Yojson.Safe.to_string json) |> Or_error.ok_exn))
  else result)
let () =
  let handler_calls=ref 0 in
  let previous_handler=if String.equal mode "commit-default-window" then Stdlib.Sys.Signal_default
    else Stdlib.Sys.Signal_handle (fun _ -> incr handler_calls) in
  let previous_int=Stdlib.Sys.signal Stdlib.Sys.sigint previous_handler in
  let previous=Stdlib.Sys.signal Stdlib.Sys.sigterm previous_handler in
  Stdlib.Fun.protect ~finally:(fun ()->Stdlib.Sys.set_signal Stdlib.Sys.sigint previous_int;Stdlib.Sys.set_signal Stdlib.Sys.sigterm previous) (fun () ->
    try
      let request=J.object_ ["fixture",Result.ok_or_failwith (Result.map_error (J.string mode) ~f:J.error_message)] |> Result.map_error ~f:J.error_message |> Result.ok_or_failwith in
      let outcome = if List.mem ["terminal-fail";"terminal-corrupt";"snapshot-fail";"snapshot-mutate";"publication-cancel";"commit-window";"commit-default-window";"precutoff-window";"phase-order"] mode ~equal:String.equal then (
        let phases=ref [] in
        let outcome=E.Preparation_service.For_testing.run ~store ~request ~prepare
          ~allocated:(fun ~directory ~attempt_id:_ -> print_endline directory;Out_channel.flush stdout)
          ~save_bytes:(fun path bytes ->
            if String.equal mode "phase-order" && String.is_suffix path ~suffix:"operation.json" then (
              let raw=Yojson.Safe.from_string bytes in
              match raw with `Assoc xs -> phases:=List.Assoc.find_exn xs "phase" ~equal:String.equal :: !phases | _->assert false);
            let terminal=String.is_substring bytes ~substring:"\"ended_at\": \"" in
            if terminal && List.mem ["commit-window";"commit-default-window"] mode ~equal:String.equal then (
              print_endline "commit";Out_channel.flush stdout;U.sleepf 0.5);
            if (String.equal mode "terminal-fail" && terminal) ||
               (String.equal mode "snapshot-fail" && String.is_suffix path ~suffix:"resources.json")
            then failwith "injected publication failure";
            E.Result_store.save_bytes path
              (if String.equal mode "terminal-corrupt" && terminal then "{}\n"
               else if String.equal mode "snapshot-mutate" && String.is_suffix path ~suffix:"resources.json" then bytes^" " else bytes);
            if String.equal mode "precutoff-window" && String.is_suffix path ~suffix:"resources.json" then (
              print_endline "before-cutoff";Out_channel.flush stdout;U.sleepf 0.5);
            if String.equal mode "publication-cancel" && String.is_suffix path ~suffix:"resources.json"
             then U.kill (U.getpid ()) Stdlib.Sys.sigterm) () in
        if String.equal mode "phase-order" then (
          let expected=match E.Preparation_record.descriptor () with
            | J.Object xs -> List.Assoc.find_exn xs "phases" ~equal:String.equal |> J.canonical |> Yojson.Safe.from_string
            | _ -> assert false in
          if not (Yojson.Safe.equal (`List (List.rev !phases)) expected) then failwith "descriptor differs from actual phase callbacks");
        outcome)
        else E.Preparation_service.run_cli ~store ~request ~prepare
          ~json:(Array.length Stdlib.Sys.argv<5 || not (String.equal Stdlib.Sys.argv.(4) "--human")) () in
      (* Verify runner restored the consumer's pre-existing signal handler. *)
      if String.equal mode "commit-window" && !handler_calls<>1 then failwith "commit signal was not delivered to previous handler";
      if String.equal mode "precutoff-window" && !handler_calls<>0 then failwith "precutoff cancellation was forwarded to previous handler";
      let before= !handler_calls in
      U.kill (U.getpid ()) Stdlib.Sys.sigterm;
      U.kill (U.getpid ()) Stdlib.Sys.sigint;
      if !handler_calls<>before+2 then failwith "signal handlers/mask not restored";
      Stdlib.exit (Option.value outcome.record.exit_code ~default:1)
    with exn ->
      let before= !handler_calls in
      U.kill (U.getpid ()) Stdlib.Sys.sigterm;
      if !handler_calls<>before+1 then failwith "signal handler not restored after exception";
      eprintf "%s\n%!" (Exn.to_string exn);Stdlib.exit 2)
