type outcome =
  | Exited of int
  | Signaled of int
  | Timed_out
  | Cancelled of int
  | Failed of string
(** Signal numbers are OCaml [Sys.sigint]/[Sys.sigterm] representations, as in
    [Unix.WSIGNALED], not POSIX numeric exit codes. *)

type result =
  { outcome : outcome
  ; pid : int option
  ; child_status : Unix.process_status option
  ; elapsed_seconds : float
  ; stdout_path : string option
  ; stderr_path : string option
  ; cleanup_error : string option
  }

val succeeded : result -> bool

val run
  :  ?timeout:float
  -> ?term_grace:float
  -> ?cancel:(unit -> int option)
  -> ?cleanup:(unit -> unit)
  -> Process.t
  -> result
(** Synchronous POSIX main-thread-only, non-reentrant supervision. The caller must
    have exclusive ownership of SIGINT/SIGTERM handlers and child waiting during
    this scope. Previous handlers are restored, not invoked or re-raised.
    Cancellation callback returns [Sys.sigint] or [Sys.sigterm]; first signal wins.
    The owned group receives that signal, then TERM after one grace period, then
    KILL after another. Timeout sends TERM then KILL. Even normal leader exit
    triggers TERM/grace/KILL for remaining group members before leader reaping.
    Defaults: no timeout, 0.5-second grace. Durations must be finite and positive.
    Children must not escape the group (setsid/setpgid); transport cleanup handles
    external resources. The leader is reaped; orphan descendants are reaped by
    their OS reaper, not by this library. SIGKILL reaping can wait on kernel IO.

    Cleanup runs exactly once after local termination/reaping, including launch
    or callback failures, with scoped handlers still installed. Hook exceptions
    are recorded in [cleanup_error]; they never mask the primary outcome and make
    [succeeded] false. Hooks must themselves be bounded; no OCaml callback can be
    forcibly timed out here. Callback/IO/spawn exceptions become [Failed]. Invalid
    durations or concurrent/nested use raise [Invalid_argument] before launch or
    cleanup. Output file evidence is retained on every outcome; no output is read
    or buffered by the supervisor. Signals/timeouts cannot become [Exited 0]. *)
