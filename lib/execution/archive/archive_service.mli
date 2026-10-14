(** OUR completed-run evidence policy. Acceptance is deliberately not a prerequisite.
    Inspection is read-only; large file IO is streaming. Internal source symlinks
    are rejected, while caller root aliases and the original bundle alias resolve.
    No extraction, shell, Python, fsync or crash-transaction guarantee. *)
type inspection = private
  { run_dir : string
  ; reports : Evidence_tar.source list
  ; omitted : string list
  ; report_bytes : int64
  ; bundle_source : string
  ; bundle_root : string
  ; bundle_files : Evidence_tar.source list
  }
val inspect : run_dir:string -> inspection
(* Omissions here cover report selection only; publication additionally records
    missing results/preflight records, as the historical --list contract does. *)
type publication = private
  { output : string; reports : string; selected : string list; omitted : string list
  ; record : Evidence_json.t }
val publish : ?rename:(string -> string -> unit) -> runtime:Archive_encoding.runtime
  -> run_dir:string -> output:string -> force:bool -> unit -> publication
(** Sibling private staging, preservation of unrelated entries (including links),
    backup then replacement rename, rollback on replacement failure. [rename] is
    an explicit IO-injection seam, default Unix.rename. Cooperative publishers
    serialize through an exclusive sibling directory; a concurrent publisher
    fails without clobbering. Parents must not be concurrently renamed by others.
    A populated output, even README-only, requires force. Archive-owned entries,
    including directories and stale postchecks, are replaced. *)
