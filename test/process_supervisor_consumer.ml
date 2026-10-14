[@@@alert "-unsafe_multidomain"]
open Hardcaml_asic_execution

let () =
  let cwd = Sys.argv.(1) in
  let mode = Sys.argv.(2) in
  let timeout = float_of_string Sys.argv.(3) in
  let prog = Sys.argv.(4) in
  let argv = Array.to_list (Array.sub Sys.argv 4 (Array.length Sys.argv - 4)) in
  let log = Filename.concat cwd "stdout.log" in
  let stderr = if mode = "merged" then log else Filename.concat cwd "stderr.log" in
  let fd = if mode = "descriptor" then
      Some (Unix.openfile log [Unix.O_WRONLY; O_CREAT; O_EXCL; O_CLOEXEC] 0o600)
    else None in
  let stdout = match fd with Some fd -> Process.Descriptor fd | None -> Process.File log in
  let argv = if mode = "argv0" then "custom argv zero" :: List.tl argv else argv in
  let process = Process.make ~prog ~argv
      ~cwd:(if mode = "missing-cwd" then Filename.concat cwd "absent" else cwd)
      ~environment:["PRESERVED=space = value; $(no shell)"; "ONLY_CHILD=yes"]
      ~stdout ~stderr:(Process.File stderr) in
  let reject f = try f (); assert false with Invalid_argument _ -> () in
  let make ~prog ~argv ~cwd ~environment =
    ignore (Process.make ~prog ~argv ~cwd ~environment ~stdout
              ~stderr:(Process.File stderr))
  in
  reject (fun () -> make ~prog:"relative" ~argv ~cwd ~environment:[]);
  reject (fun () -> make ~prog ~argv:[] ~cwd ~environment:[]);
  reject (fun () -> make ~prog ~argv:["nul\000"] ~cwd ~environment:[]);
  reject (fun () -> make ~prog ~argv ~cwd:"relative" ~environment:[]);
  List.iter (fun environment ->
    reject (fun () -> make ~prog ~argv ~cwd ~environment))
    [["INVALID"]; ["=value"]; ["KEY=a"; "KEY=b"]; ["KEY=nul\000"]];
  let invalid_cleanups = ref 0 in
  List.iter (fun timeout ->
    reject (fun () -> ignore (Process_supervisor.run ~timeout
      ~cleanup:(fun () -> incr invalid_cleanups) process))) [0.; -1.; nan; infinity];
  assert (!invalid_cleanups = 0);
  let handled = ref 0 in
  let h = Sys.Signal_handle (fun _ -> incr handled) in
  let old_int = Sys.signal Sys.sigint h in
  let old_term = Sys.signal Sys.sigterm h in
  let cleanups = ref 0 in
  let cleanup () =
    incr cleanups;
    if mode = "hook-failure" then failwith "cleanup fixture";
    if mode = "hook-signal" then Unix.kill (Unix.getpid ()) Sys.sigterm
  in
  let cancel () =
    if mode = "nested" then
      reject (fun () -> ignore (Process_supervisor.run process));
    if mode = "callback-failure" then failwith "cancel fixture"
    else if mode = "cancel" then Some Sys.sigterm
    else None
  in
  let result = Process_supervisor.run ~timeout ~term_grace:0.1 ~cleanup ~cancel process in
  assert (result.stdout_path = (if fd = None then Some log else None));
  assert (result.stderr_path = Some stderr);
  assert ((result.pid = None) = (result.child_status = None));
  Option.iter (fun fd -> ignore (Unix.write_substring fd "borrowed-open" 0 13); Unix.close fd) fd;
  assert (!handled = 0);
  Unix.kill (Unix.getpid ()) Sys.sigint;
  Unix.kill (Unix.getpid ()) Sys.sigterm;
  assert (!handled = 2);
  Sys.set_signal Sys.sigint old_int;
  Sys.set_signal Sys.sigterm old_term;
  let outcome = match result.outcome with
    | Exited n -> "exit:" ^ string_of_int n
    | Signaled s -> "signal:" ^ string_of_int s
    | Timed_out -> "timeout"
    | Cancelled s -> "cancel:" ^ string_of_int s
    | Failed _ -> "failed"
  in
  Printf.printf "%s\n%d\n%b\n%b\n%s\n%f\n" outcome !cleanups
    (Process_supervisor.succeeded result) (result.cleanup_error <> None)
    (match result.pid with None -> "none" | Some p -> string_of_int p)
    result.elapsed_seconds;
  (match result.pid with
   | None -> ()
   | Some pid ->
     (try ignore (Unix.waitpid [Unix.WNOHANG] pid); assert false with
      | Unix.Unix_error (Unix.ECHILD, _, _) -> ()))
;;
