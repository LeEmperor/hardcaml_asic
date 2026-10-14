(** Standalone coarse readiness, independent of stage preparation. LibreLane/TT
    remain external tools. No staging, inventory import or EDA execution. *)
type outcome = private
  { report_path : string
  ; receipt_path : string option
  ; report : Identity_json.t
  ; status : Result_store.status
  ; exit_code : int
  ; report_published : bool
  ; receipt_published : bool
  ; publication_errors : string list
  }
val probe : bundle:string -> support_tools:string -> pdk_root:string -> python:string
  -> resources:string -> environment:string list -> directory:string
   -> ?native:bool -> ?allow_python_mismatch:bool -> ?cancel:(unit -> int option)
   -> unit -> Identity_json.t
(* Accumulates ordinary readiness issues; cancellation propagates. Interpreter
     paths are lexical, including virtual-environment symlinks. Optional caller
     cancellation uses OCaml Sys signal numbers and is checked between probes. *)
val run : bundle:string -> support_tools:string -> pdk_root:string -> python:string
  -> resources:string -> environment:string list -> results_root:string
  -> ?output:string -> ?native:bool -> ?allow_python_mismatch:bool -> unit -> outcome
(* Allocates and publishes pending receipt/report before any probes. Explicit
    output is validated first and creates no operation. Allocation/pending write
    errors escape (CLI exit 2). Terminal publication errors are retained in the
    outcome: interruption keeps 130/143, readiness failure keeps 1, otherwise
    storage failure yields Failed/2. The in-memory report includes secondary
    publication issues and is not ready on storage failure. Publication flags
    describe the terminal records, not pending/stale files; receipt_published is
    false for explicit output. A failed destination is never removed or repaired.
    If storage is unavailable, only the returned outcome/CLI output may contain
    the terminal result; no durable terminal receipt is promised.
    Synchronous main-thread-only scope; restores SIGINT/SIGTERM handlers. *)
val python_repr : Identity_json.t -> string
