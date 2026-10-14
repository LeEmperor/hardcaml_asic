(** Caller-selected storage primitives matching the finite record domain of the
    Python result store. No probes, signal handlers, journal, checkpoint promotion,
    or process outcome inference. Use [Process_supervisor] for process ownership.

    JSON records use sorted two-space-indented ASCII JSON plus newline, not identity
    bytes. Identity hashing remains [Identity_json.identity]. Nonfinite backend
    state must remain opaque files; it cannot be decoded/re-encoded here. Unknown
    finite record fields are retained. IO errors propagate. Atomic rename provides
    old-or-new visibility on a local filesystem, NOT fsync/crash durability.
    Roots/explicit outputs are caller-owned; these APIs do not adopt existing runs.
    Parents must not be concurrently renamed or modified by untrusted writers. *)
type allocation = private
  { identity : string
  ; directory : string
  ; created_at : string
  }

(** UTC Unix-seconds clock; finite years 1..9999, rounded to microseconds.
    Identity factories return UUID hex or standard hyphenated UUID strings.
    Defaults use Unix time and /dev/urandom UUIDv4. Each collision consumes a fresh
    clock/identity pair. Only EEXIST retries, at most eight times by default.
    Failed allocations never delete or overwrite collision paths. Root parents
    are created and resolved through symlinks as Python Path.resolve does. *)
val allocate : ?clock:(unit -> float) -> ?id_factory:(unit -> string)
  -> ?max_attempts:int -> ?uuid_directory:bool -> string -> allocation
(* [uuid_directory=true] retains the historical checks/<uuid-hex> layout. *)

val record_bytes : Identity_json.t -> string

(** Same-directory exclusive 0600 temporary, closed before rename; cleanup on
    errors. Parent must exist. Deliberately replaces the caller-selected entry,
    including a symlink itself (never its referent). *)
val save_json : string -> Identity_json.t -> unit
(* Same atomic publication primitive for explicitly scoped evidence codecs.
   Bytes are not validated, canonicalized, or hashed. *)
val save_bytes : string -> string -> unit
val read_json : string -> (Identity_json.t, Identity_json.error) result

(** Explicit output validation only: absolute lexical path, existing writable
    parent, no directory destination; no directory creation or probes. *)
val validate_output : string -> string

type status = Pending | Ready | Failed | Interrupted
val status_name : status -> string
val diagnostic : ?provenance:Identity_json.t -> ?interrupted_by:string
  -> bundle:string -> status:status -> issue:string -> unit -> Identity_json.t
val pending_report : ?provenance:Identity_json.t -> bundle:string -> unit -> Identity_json.t

(** Checks only ready:boolean and issues:array, just like the Python provider;
    returns status/exit code without editing or dropping the original report. *)
val classify_report : Identity_json.t -> (status * int, string) result
val operation_receipt : allocation -> bundle:string -> Identity_json.t

(** Retains additive receipt fields. Caller supplies terminal status, actual exit
    code, end time and optional publication/probe error. No signal conversion. *)
val finish_receipt : Identity_json.t -> status:status -> exit_code:int
  -> ended_at:string -> ?error:string -> unit -> Identity_json.t

(** Allocate then publish pending receipt before returning paths to a probe
    owner. If publication fails, the newly reserved directory is retained.
    No automatic retry after that failure, rollback, or fake completed receipt. *)
val begin_preflight : ?clock:(unit -> float) -> ?id_factory:(unit -> string)
  -> ?max_attempts:int -> ?save:(string -> Identity_json.t -> unit)
  -> results_root:string -> bundle:string -> unit
  -> allocation * string * string * Identity_json.t
