(* This boundary deliberately scopes process-global handlers on the main thread. *)
[@@@alert "-unsafe_multidomain"]
type outcome =
  | Exited of int
  | Signaled of int
  | Timed_out
  | Cancelled of int
  | Failed of string

type result =
  { outcome : outcome
  ; pid : int option
  ; child_status : Unix.process_status option
  ; elapsed_seconds : float
  ; stdout_path : string option
  ; stderr_path : string option
  ; cleanup_error : string option
  }

external now : unit -> float = "hardcaml_asic_monotonic"
external child_exited : int -> bool = "hardcaml_asic_child_exited"

let active = ref false
let succeeded r = r.outcome = Exited 0 && r.cleanup_error = None
let path = function Process.File p -> Some p | Descriptor _ -> None
let pause seconds =
  let until = now () +. seconds in
  let rec loop () =
    let remaining = until -. now () in
    if remaining > 0. then
      (try ignore (Unix.select [] [] [] remaining) with
       | Unix.Unix_error (Unix.EINTR, _, _) -> loop ())
  in
  loop ()
;;

let signal_group pid signal =
  if pid <= 0 || pid = Unix.getpid () then failwith "unsafe process group";
  try Unix.kill (-pid) signal with
  | Unix.Unix_error (Unix.ESRCH, _, _) -> ()
;;

let rec reap pid =
  try snd (Unix.waitpid [] pid) with
  | Unix.Unix_error (Unix.EINTR, _, _) -> reap pid
;;

let run ?timeout ?(term_grace = 0.5) ?(cancel = fun () -> None)
    ?(cleanup = fun () -> ()) (process : Process.t) =
  let duration x =
    if not (Float.is_finite x) || x <= 0. then
      invalid_arg "Process_supervisor: duration must be finite and positive"
  in
  duration term_grace;
  Option.iter duration timeout;
  if !active then invalid_arg "Process_supervisor: already active";
  let started = now () in
  active := true;
  let interrupted = ref None in
  let handler s = if !interrupted = None then interrupted := Some s in
  let previous = ref [] in
  let descriptors = ref [] in
  let pid = ref None in
  let status = ref None in
  let outcome = ref (Failed "launch not attempted") in
  let cleanup_error = ref None in
  let own fd = descriptors := fd :: !descriptors; fd in
  let opened = Hashtbl.create 2 in
  let output = function
    | Process.Descriptor fd -> fd
    | File p ->
      (match Hashtbl.find_opt opened p with
       | Some fd -> fd
       | None ->
         let fd = own (Unix.openfile p [Unix.O_WRONLY; O_CREAT; O_EXCL; O_CLOEXEC] 0o600) in
         Hashtbl.add opened p fd;
         fd)
  in
  let stop child first =
    signal_group child first;
    pause term_grace;
    if first <> Sys.sigterm then (signal_group child Sys.sigterm; pause term_grace);
    signal_group child Sys.sigkill;
    status := Some (reap child)
  in
  Fun.protect
    ~finally:(fun () ->
      List.iter (fun fd -> try Unix.close fd with _ -> ()) !descriptors;
      List.iter (fun (s, h) -> Sys.set_signal s h) !previous;
      active := false)
    (fun () ->
       (try
          List.iter
            (fun s ->
               let h = Sys.signal s (Sys.Signal_handle handler) in
               previous := (s, h) :: !previous)
            [Sys.sigint; Sys.sigterm];
          let stdout = output process.stdout in
          let stderr = output process.stderr in
          let stdin = own (Unix.openfile "/dev/null" [Unix.O_RDONLY; O_CLOEXEC] 0) in
          let child = Spawn.spawn ~prog:process.prog ~argv:process.argv
              ~cwd:(Spawn.Working_dir.Path process.cwd)
              ~env:(Spawn.Env.of_list process.environment) ~stdin ~stdout ~stderr
              ~setpgid:Spawn.Pgid.new_process_group () in
          pid := Some child;
          let rec wait () =
            (match !interrupted with
             | Some _ -> ()
             | None ->
               match cancel () with
               | None -> ()
               | Some s when s = Sys.sigint || s = Sys.sigterm -> handler s
               | Some _ -> invalid_arg "Process_supervisor: invalid cancellation signal");
            match !interrupted with
            | Some s -> outcome := Cancelled s; stop child s
            | None when Option.fold ~none:false
                          ~some:(fun t -> now () -. started >= t) timeout ->
              outcome := Timed_out; stop child Sys.sigterm
            | None when child_exited child ->
              stop child Sys.sigterm;
              outcome := (match !status with
                | Some (Unix.WEXITED n) -> Exited n
                | Some (Unix.WSIGNALED s) -> Signaled s
                | _ -> Failed "unexpected child status")
            | None -> pause 0.01; wait ()
          in
          wait ()
        with exn ->
          outcome := Failed (Printexc.to_string exn);
          (match !pid, !status with
           | Some child, None ->
             (try stop child Sys.sigterm with termination ->
                outcome := Failed (Printexc.to_string exn ^ "; termination: "
                                   ^ Printexc.to_string termination))
           | _ -> ()));
       (try cleanup () with exn -> cleanup_error := Some (Printexc.to_string exn)));
  (* Snapshot only after restoring handlers, so signals caught during descriptor
     closing/handler restoration cannot be lost behind an earlier success copy. *)
  Option.iter (fun s -> outcome := Cancelled s) !interrupted;
  { outcome = !outcome; pid = !pid; child_status = !status
  ; elapsed_seconds = now () -. started
  ; stdout_path = path process.stdout; stderr_path = path process.stderr
  ; cleanup_error = !cleanup_error }
;;
