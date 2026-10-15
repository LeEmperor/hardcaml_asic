open Hardcaml_asic_execution
module J = Identity_json
let codec = function Ok x -> x | Error e -> failwith (J.error_message e)
let checked = function Ok x -> x | Error e -> failwith e
let str s = codec (J.string s)
let obj xs = codec (J.object_ xs)
let get j k = match j with J.Object xs -> List.assoc k xs | _ -> failwith "object"
let text = function J.String s -> s | _ -> failwith "string"
let inspect d = match Observation.inspect d with Ok j -> j | Error e -> failwith e.detail
let expect_state state j = assert (get (get j "methodology") "state" = str state)
let () =
  let plan = match Hardcaml_asic.Methodology_plan.of_string (let ic = open_in Sys.argv.(1) in
    Fun.protect ~finally:(fun () -> close_in ic) (fun () -> really_input_string ic (in_channel_length ic))) with
    | Ok p -> p | Error e -> failwith (Core.Error.to_string_hum e) in
  let expected = Hardcaml_asic.Methodology_plan.plan_identity plan in
  let root = Sys.argv.(3) in
  List.iter (fun mode ->
    let base = root ^ "/" ^ mode in Unix.mkdir base 0o700;
    let from_child,to_parent = Unix.pipe () and from_parent,to_child = Unix.pipe () in
    let pid = Unix.fork () in
    if pid=0 then (
      Unix.close from_child; Unix.close to_child;
      let input = Unix.in_channel_of_descr from_parent and output = Unix.out_channel_of_descr to_parent in
      let w = Observation_writer.create ~root:(base ^ "/observations") ~workspace:(base ^ "/workspace")
        ~checkpoint_store:(base ^ "/workspace/checkpoints") ~request:(obj [])
        ~request_for_allocation:(fun ~directory ~attempt_id -> obj ["methodology_launch",obj [
          "state",str "pending";"attempt_id",str attempt_id;"expected_plan_identity",str expected;
          "snapshot_path",str (directory ^ "/methodology-plan.json")]]) () in
      output_string output (Observation_writer.directory w ^ "\n"); flush output;
      let result = Stage_preparation.prepare ~bundle:Sys.argv.(2) ~support_tools:base ~pdk_root:base
        ~python:"/nonexistent/python" ~docker:"/nonexistent/docker" ~git:"/nonexistent/git"
        ~resources:base ~workspace:(base ^ "/workspace") ~checkpoint_store:(base ^ "/workspace/checkpoints")
        ~evidence_root:(base ^ "/evidence") ~environment:[] ~observation:w
        ~methodology:(expected,plan) ~after_methodology_snapshot:(fun () ->
          output_char output 'S'; flush output;
          match input_char input with
          | 'L' -> Unix._exit 0
          | 'I' -> Observation_writer.outcome w ~status:Runner.Interrupted ~exit_code:143 ~error:(Some "fixture interruption"); Unix._exit 0
          | 'F' -> raise (Runner.Callback_error (Runner.cancellation ~signal:15 "fixture cancellation"))
          | 'R' -> () | _ -> assert false)
        ~plan:(checked (Methodology_execution_service.check ~bundle:Sys.argv.(2) ~expected plan)) () in
      let error = match result with Error e -> e | Ok _ -> failwith "unexpected preparation" in
      Observation_writer.outcome w ~status:(match error.cause.kind with Runner.Cancellation _ -> Runner.Interrupted | _ -> Runner.Failed)
        ~exit_code:error.cause.exit_code ~error:(Some error.cause.message);
      output_char output 'C'; flush output;
      ignore (input_char input); Observation_writer.close w; Unix._exit 0);
    Unix.close to_parent; Unix.close from_parent;
    let input = Unix.in_channel_of_descr from_child and output = Unix.out_channel_of_descr to_child in
    let send c = output_char output c; flush output in
    Fun.protect ~finally:(fun () ->
      (* Only the forked fixture child is owned here. *)
      (try Unix.kill pid Sys.sigkill with Unix.Unix_error (Unix.ESRCH,_,_) -> ());
      ignore (Unix.waitpid [] pid); close_in_noerr input; close_out_noerr output) (fun () ->
      let directory = input_line input in assert (input_char input='S');
      let snapshot = directory ^ "/methodology-plan.json" in assert (Sys.file_exists snapshot);
      for _=1 to 5 do
        let j = inspect directory in expect_state "pending" j;
        assert (get j "writer_active"=J.bool true && get j "execution_file"=J.null);
        assert (get j "execution_request"=get (get j "state") "request")
      done;
      if mode="lost" || mode="incomplete-terminal" then (
        send (if mode="lost" then 'L' else 'I');
        (try ignore (input_char input); assert false with End_of_file -> ());
        let j = inspect directory in expect_state "pending" j;
        assert (get j "writer_active"=J.bool false);
        assert (get j "observation_status"=str (if mode="lost" then "writer_lost_or_unknown" else "final"));
        if mode="incomplete-terminal" then assert (get (get (get j "state") "outcome") "status"=str "interrupted"))
      else (
        let commit () = send (if mode="cancel" then 'F' else 'R'); assert (input_char input='C') in
        let j = if mode="interleaved" || mode="corrupt-interleaved" then
          Observation.For_testing.inspect ~after_preflight_read:(fun () -> commit ();
            if mode="corrupt-interleaved" then Unix.unlink snapshot) directory
          else (commit (); Observation.inspect directory) in
        if mode="corrupt-interleaved" then (match j with Error _ -> () | Ok _ -> failwith "masked missing committed snapshot")
        else (
          let j = match j with Ok j -> j | Error e -> failwith e.detail in
          expect_state "recorded" j;
          assert (get (get (get j "state") "outcome") "status" = str (if mode="cancel" then "interrupted" else "failed"));
          let report_path = text (get (get j "state") "preflight_record") in
          let report = codec (Result_store.read_json report_path) in
          let stripped = match report with J.Object xs -> obj (List.remove_assoc "methodology" xs) | _ -> assert false in
          Result_store.save_json report_path stripped;
          (match Observation.inspect directory with Error _ -> () | Ok _ -> failwith "masked missing committed reference");
          Result_store.save_json report_path report;
          Unix.unlink report_path;
          (match Observation.inspect directory with Error _ -> () | Ok _ -> failwith "masked missing committed report");
          Result_store.save_json report_path report;
          Unix.chmod snapshot 0o600;
          let oc = open_out snapshot in output_string oc "corrupt"; close_out oc;
          (match Observation.inspect directory with Error _ -> () | Ok _ -> failwith "masked corrupt committed snapshot"));
        send 'T')))
    ["normal";"interleaved";"corrupt-interleaved";"cancel";"lost";"incomplete-terminal"];
  print_endline "named observation publication races: 6 synchronized processes passed"
