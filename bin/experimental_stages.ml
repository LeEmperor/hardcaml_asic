(* Single-threaded command scopes process-global interruption handlers. *)
[@@@alert "-unsafe_multidomain"]
open Hardcaml_asic_execution
module J = Identity_json
let checked = function Ok x -> x | Error s -> failwith s
let main () =
  let bundle = ref "" and toolchain = ref "" and workspace = ref "" and evidence = ref ""
  and store = ref "" and resources = ref "" and python = ref "" and docker = ref "docker" and git = ref "git"
  and support = ref "" and pdk = ref "" and checkpoint = ref "" and through = ref "synthesis" and stages = ref ""
   and timeout = ref 600. and probe_timeout = ref 20. and no_observation = ref false
     and observation_store = ref "" and json = ref false and public = ref false and plan_file = ref "" and request_json = ref ""
     and methodology_file = ref "" and expected_plan_identity = ref "" and through_explicit = ref false in
  let options = [
    "--public-cli4",Arg.Set public," Internal CLI4 delegation";
    "--request",Arg.Set_string request_json,"JSON Internal public request metadata";
     "--plan",Arg.Set_string plan_file,"PATH Strict schema-4 stage plan (schemas 2/3 retained for reading)";
     "--methodology-plan",Arg.Set_string methodology_file,"PATH Checked frozen methodology plan (fresh only)";
     "--expected-plan-identity",Arg.Set_string expected_plan_identity,"HASH Required named-launch plan identity";
    "--bundle",Arg.Set_string bundle,"PATH Existing emitted bundle (required)";
    "--toolchain",Arg.Set_string toolchain,"PATH Provisioned provider toolchain";
    "--workspace",Arg.Set_string workspace,"PATH Fresh workspace or exact retained resume workspace (required)";
    "--evidence-root",Arg.Set_string evidence,"PATH Separate preflight evidence root (required)";
    "--checkpoint-store",Arg.Set_string store,"PATH Mounted store (default WORKSPACE/checkpoints)";
    "--checkpoint",Arg.Set_string checkpoint,"PATH Resume from this actual checkpoint";
     "--through",Arg.String (fun s -> through_explicit:=true; through:=s),"STAGE Execute contiguous stages through endpoint (default synthesis)";
    "--stages",Arg.Set_string stages,"STAGES Explicit comma-separated contiguous sequence";
    "--timeout",Arg.Set_float timeout,"SECONDS Per segment/publication timeout (default 600; increase for signoff)";
    "--probe-timeout",Arg.Set_float probe_timeout,"SECONDS Per readiness probe (default 20)";
    "--no-observation",Arg.Set no_observation," Disable the default stage journal";
    "--observation-store",Arg.Set_string observation_store,"PATH Journal root (default workspace parent/observations)";
    "--json",Arg.Set json," Emit flushed allocation/terminal JSONL and execution JSON";
    "--resources",Arg.Set_string resources,"PATH Installed runtime package directory (default executable prefix)";
    "--python",Arg.Set_string python,"PATH Literal host venv interpreter (default TOOLCHAIN/.venv/bin/python)";
    "--support-tools",Arg.Set_string support,"PATH TT collateral (default TOOLCHAIN/tt)";
    "--pdk-root",Arg.Set_string pdk,"PATH PDK collateral (default TOOLCHAIN/pdk)";
    "--docker",Arg.Set_string docker,"PATH Docker executable (default PATH lookup)";
    "--git",Arg.Set_string git,"PATH Git executable (default PATH lookup)" ] in
  Arg.parse options (fun _ -> failwith "unexpected positional argument")
    "hardcaml-asic-experimental-stages --bundle PATH --toolchain PATH --workspace PATH --evidence-root PATH [--through floorplan]\nOCaml-owned preparation/execution with schema-2 journals; also the public CLI4 stage backend.";
  if !no_observation && !observation_store<>"" then failwith "--no-observation and --observation-store are mutually exclusive";
  List.iter (fun (name,value) -> if value="" then failwith ("required " ^ name)) ["--bundle",!bundle;"--workspace",!workspace;"--evidence-root",!evidence];
  let abs p = if Filename.is_relative p then Filename.concat (Sys.getcwd ()) p else p in
  let workspace_path = abs !workspace in
  let checkpoint_store = if !store="" then workspace_path ^ "/checkpoints" else abs !store in
   let writer = ref None and execution_file = ref None in
   let methodology = ref None in
   let methodology_reference = ref None in
   let snapshot_path = ref None in
  let emit value = print_endline (J.canonical value); flush stdout in
  let str x = match J.string x with Ok x -> x | Error e -> failwith (J.error_message e) in
  let obj xs = match J.object_ xs with Ok x -> x | Error e -> failwith (J.error_message e) in
  let nullable = function None -> J.null | Some x -> str x in
   let integer x = match J.integer (string_of_int x) with Ok x -> x | Error _ -> assert false in
   let named_fields () = if !methodology_file="" then [] else
     ["methodology",obj ["state",str (if !methodology_reference=None then "pending" else "checked");
       "expected_plan_identity",str !expected_plan_identity;
       "snapshot_path",nullable !snapshot_path;
       "plan_identity",nullable (Option.map (fun (_,p) -> Hardcaml_asic.Methodology_plan.plan_identity p) !methodology);
       "reference",(match !methodology_reference with None -> J.null | Some r -> Methodology_execution_record.to_json r)]] in
   let with_named j = match j with J.Object xs -> obj (xs @ named_fields ()) | _ -> j in
  let signal n = raise (Runner.Callback_error (Runner.cancellation ~signal:n "stage command interrupted")) in
  let old_int = Sys.signal Sys.sigint (Sys.Signal_handle (fun _ -> signal 2)) in
  let old_term = Sys.signal Sys.sigterm (Sys.Signal_handle (fun _ -> signal 15)) in
  Fun.protect ~finally:(fun () -> Option.iter Observation_writer.close !writer;
    Sys.set_signal Sys.sigint old_int; Sys.set_signal Sys.sigterm old_term) (fun () ->
  try
  if not !no_observation then (
    let root = if !observation_store="" then Filename.dirname workspace_path ^ "/observations" else abs !observation_store in
     let request = if !request_json="" then obj ["caller_cwd",str (Sys.getcwd ());"argv",J.array (List.map str (Array.to_list Sys.argv))]
       else match J.parse !request_json with Ok j -> j | Error e -> failwith (J.error_message e) in
     let request_for_allocation = if !methodology_file="" then None else Some (fun ~directory ~attempt_id ->
       snapshot_path:=Some (directory ^ "/methodology-plan.json");
       match request with J.Object xs -> obj (xs @ ["methodology_launch",obj ["state",str "pending";
         "attempt_id",str attempt_id;"expected_plan_identity",str !expected_plan_identity;"snapshot_path",nullable !snapshot_path]])
       | _ -> failwith "request metadata object required") in
     let w = Observation_writer.create ?request_for_allocation ~root ~workspace:workspace_path ~checkpoint_store ~request () in
    writer := Some w;
     if !json then emit (with_named (Observation_writer.allocation_receipt w))
     else if !public then Public_stage_presentation.allocation (Observation_writer.allocation_receipt w)
     else Printf.printf "Observation: %s\n%!" (Observation_writer.directory w));
   if !methodology_file<>"" then (
     if !plan_file<>"" || !through_explicit || !stages<>"" || !checkpoint<>"" then failwith "methodology launch requires fresh input and exclusive plan selection";
     if !expected_plan_identity="" then failwith "--expected-plan-identity required";
     let ic=open_in_bin (abs !methodology_file) in
     let bytes=Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () -> really_input_string ic (in_channel_length ic)) in
     let p=match Hardcaml_asic.Methodology_plan.of_string bytes with Ok p -> p | Error e -> failwith (Core.Error.to_string_hum e) in
     methodology:=Some (!expected_plan_identity,p);
     ignore (checked (Methodology_execution_service.check ~bundle:(abs !bundle) ~expected:!expected_plan_identity p));
     ())
   else if !expected_plan_identity<>"" then failwith "--expected-plan-identity requires --methodology-plan";
   let select value suffix = if !value="" then (if !toolchain="" then failwith "--toolchain or explicit tool paths required"; abs !toolchain ^ suffix) else abs !value in
  let environment = Array.to_list (Unix.environment ()) in
  let python = select python "/.venv/bin/python" and support_tools = select support "/tt" and pdk_root = select pdk "/pdk" in
  let initial_checkpoint = if !checkpoint="" then None else Some (abs !checkpoint) in
  let initial_boundary = Option.map (fun p -> (checked (Checkpoint.read p)).boundary) initial_checkpoint in
  let stage name = match Execution_plan.Stage.of_string name with Ok s -> s | Error _ -> failwith ("unknown stage: " ^ name) in
    let plan = match !methodology with Some (_,p) -> Execution_plan.of_stages (Execution_plan.Stage_plan.of_recipe (Hardcaml_asic.Methodology_plan.recipe p)) | None -> if !plan_file<>"" then (match Result_store.read_json (abs !plan_file) with
     | Error e -> failwith (J.error_message e)
     | Ok j -> (match Execution_plan.of_json j with
       | Ok (Execution_plan.Stages p as plan) ->
         if Option.is_some initial_checkpoint <> Option.is_some (Execution_plan.Stage_plan.source_boundary p)
         then failwith "stage plan resume must match the supplied checkpoint"; plan
       | Ok _ -> failwith "stage plan required"
       | Error e -> failwith e))
     else Execution_plan.of_stages (checked (if !stages="" then Execution_plan.Stage_plan.through ?initial_boundary (stage !through)
     else Execution_plan.Stage_plan.resolve_sequence ?initial_boundary (List.map stage (String.split_on_char ',' !stages)))) in
  Option.iter (fun w -> match plan with Execution_plan.Stages p -> Observation_writer.planned w p | _ -> assert false) !writer;
  let resources = if !resources="" then Stage_preparation.installed_resources ~executable:Sys.executable_name else abs !resources in
  let workspace = abs !workspace in
   let checkpoint_store = if !store="" then workspace ^ "/checkpoints" else abs !store in
   let failure_exit_code = if not !public then None else Some (fun operation (r:Execution_transport.result) ->
     if operation=Backend_protocol.Validate_publication || r.process.outcome=Process_supervisor.Timed_out
     then Some 2 else None) in
  match Stage_preparation.prepare ~bundle:(abs !bundle) ~support_tools ~pdk_root ~python
    ~docker:!docker ~git:!git
    ~resources ~workspace ~checkpoint_store ~evidence_root:(abs !evidence) ~environment
      ~timeout:!timeout ~probe_timeout:!probe_timeout ?initial_checkpoint ?observation:!writer ?failure_exit_code ?methodology:!methodology ~plan () with
    | Error e -> methodology_reference := e.methodology;
      if not !public then Option.iter (fun p -> prerr_endline ("Preflight: " ^ p)) e.preflight_path;
     let cause = if !public then match e.cause.kind with Runner.Cancellation _ -> e.cause
       | Runner.Failure -> Runner.failure ~secondary:e.cause.secondary e.cause.message else e.cause in
     raise (Runner.Callback_error cause)
   | Ok prepared ->
     methodology_reference := prepared.methodology;
    Option.iter (fun w -> Observation_writer.prepared w ~runtime_record:(Some prepared.preflight_path)) !writer;
    let result = Stage_preparation.execute ?observation:!writer prepared plan in
     let value = Runner.to_json ?methodology:prepared.methodology ~run_json:(fun () -> J.null) result in
    (match result.primary with None -> () | Some _ -> Option.iter (fun w ->
      try Result_store.save_json (Observation_writer.directory w ^ "/diagnostics.json") (Segment_service.diagnostics_json prepared.service result)
      with e -> prerr_endline ("Observation/storage diagnostics: " ^ Printexc.to_string e)) !writer);
    (match Result_store.read_json prepared.summary_path with
     | Ok saved when J.canonical saved = J.canonical value -> ()
     | _ -> raise (Runner.Callback_error (match result.primary with Some d -> d.error
       | None -> Runner.failure "terminal execution reference was not published")));
    execution_file := (match prepared.methodology with
      | None -> Some prepared.summary_path
      | Some methodology -> checked (Stage_execution_record.available ~workspace
          ~attempt_id:result.attempt_id ~methodology));
    (try Option.iter (fun w -> Observation_writer.outcome w ~status:result.status ~exit_code:result.exit_code
      ~error:(Option.map (fun (d:Runner.diagnostic) -> d.error.message) result.primary)) !writer
     with exn -> match result.primary with Some d -> prerr_endline ("Observation/storage: " ^ Printexc.to_string exn); raise (Runner.Callback_error d.error) | None -> raise exn);
     if !json then emit (match prepared.methodology,value with
       | Some _,J.Object xs -> obj (xs @ ["execution_file",nullable !execution_file])
       | _ -> value) else if !public then Public_stage_presentation.execution ~workspace value else (
      Printf.printf "Stage execution: %s (exit %d)\nWorkspace: %s\n" (Runner.status_name result.status) result.exit_code workspace;
      Printf.printf "Execution attempt: %s\nExecution record: %s\n" result.attempt_id prepared.summary_path;
      List.iter (fun (o:Runner.occurrence) ->
        Printf.printf "  %s: %s (%.6f s)\n" o.action_key (Runner.status_name o.status) o.duration_seconds;
        Option.iter (fun e -> Printf.printf "    error: %s\n" e) o.error) result.occurrences;
      print_endline "Artifact references (historical publication, not current readiness):";
      List.iter (fun p -> Printf.printf "  %s: %s\n    identity %s\n"
        (Execution_plan.Stage.to_string p.Runner.evidence.boundary) p.evidence.path p.evidence.identity) result.artifacts;
      print_endline "Acceptance: not_evaluated\nExternal postcheck: not_evaluated\nEndpoint completion does not establish acceptance. Interrupted is not an acceptance rejection.");
     if !public then (
       List.iter (fun (o:Runner.occurrence) -> Option.iter (fun e -> prerr_endline ("stages: " ^ o.action_key ^ ": " ^ e)) o.error) result.occurrences;
       if result.exit_code<>0 then Printf.eprintf "stages: %s (exit %d)\n" (Runner.status_name result.status) result.exit_code)
     else (prerr_endline ("Preflight: " ^ prepared.preflight_path); prerr_endline ("Diagnostics: " ^ prepared.diagnostics_path)); result.exit_code
  with exn ->
    let cause = match exn with Runner.Callback_error e -> e | _ -> Runner.failure (Printexc.to_string exn) in
    let status = match cause.kind with Runner.Cancellation _ -> Runner.Interrupted | _ -> Runner.Failed in
    let recording_error = ref None in
    Option.iter (fun w ->
      (try let path = Observation_writer.preflight_path w in
        if not (Sys.file_exists path) then Result_store.save_json path
          (Result_store.diagnostic ~bundle:(abs !bundle)
            ~status:(if status=Runner.Interrupted then Result_store.Interrupted else Result_store.Failed)
            ~issue:cause.message ())
       with e -> recording_error := Some (Printexc.to_string e));
      if (Observation_writer.state w).outcome=None then
        (try Observation_writer.outcome w ~status ~exit_code:cause.exit_code ~error:(Some cause.message)
         with e -> recording_error := Some (Printexc.to_string e));
      Observation_writer.close w) !writer;
    let observation = match !writer with None -> J.null | Some w ->
      (match Observation.inspect (Observation_writer.directory w) with Ok x -> x | Error e -> recording_error := Some e.detail; J.null) in
     if !json && not !no_observation then emit (with_named (obj ["contract",str "hardcaml-asic.stage-observation";
      "schema_version",integer 1;"event",str "observation_terminal";"status",str (Runner.status_name status);
      "exit_code",integer cause.exit_code;"attempt",nullable (Option.map Observation_writer.directory !writer);
      "stream_id",nullable (Option.map Observation_writer.stream_id !writer);"execution_file",nullable !execution_file;
      "observation",observation;"recording_error",nullable !recording_error;
       "error",obj ["code",str (match exn with Observation_writer.Busy -> "BUSY" | _ -> if status=Runner.Interrupted then "INTERRUPTED" else "EXECUTION_FAILED");"detail",str cause.message]]));
     if !public then (
       prerr_endline ((if status=Runner.Interrupted then "stages: interrupted: " else "hardcaml-asic-flow: ") ^ cause.message);
       if not !json then (if status=Runner.Interrupted then
         print_endline "Stage execution interrupted; no terminal result is available here.\nInspect the allocated observation if present; acceptance is not established."
         else Public_stage_presentation.error workspace_path cause.message))
     else prerr_endline cause.message;
     Option.iter (fun s -> prerr_endline ("Observation/storage: " ^ s)) !recording_error;
    cause.exit_code)
let () = exit (try main () with exn -> prerr_endline (Printexc.to_string exn); 2)
