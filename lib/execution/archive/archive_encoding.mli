(** Installed tar.gz encoding primitives, independent of selection/publication.
    No shell, Python, extraction, or implicit executable search. *)
type runtime = { gzip : string; scratch : string; timeout : float }
(** Absolute executable and scratch-directory paths. Gzip must support GNU
    [-n -9 -c -- FILE] and [-d -c -- FILE]. Child environment is only LC_ALL=C;
    GZIP and all inherited compression/loader options are absent. Main-thread,
    non-reentrant supervision follows [Process_supervisor.run]. Private 0700
    scratch spools are deleted on success/failure. Disk space scales with tar
    size; memory does not. Timeout covers each gzip invocation, not file copying. *)

exception Gzip_failed of Process_supervisor.result * string
(** Result plus at most 4096 stderr bytes; scratch paths in result are historical. *)

val write
  : runtime:runtime -> normalized:bool -> output:string
  -> Evidence_tar.source list -> Evidence_tar.member list
(** Output is absolute, newly created exclusively; deleted on failure. Returns
    actual written hash inventory. Does not publish or replace an existing file. *)

val write_input_bundle
  : runtime:runtime -> output:string -> manifest:Evidence_tar.source
  -> files:Evidence_tar.source list -> Evidence_tar.member list
(** Manifest name must be manifest.json; other names are bundle-relative.
    Every source must carry an expected SHA-256. Writes bundle/manifest.json
    first, then files sorted by relative name; normalized metadata and gzip -n.
    Identical bytes/names give identical gzip bytes on the same implementation. *)

val verify
  : runtime:runtime -> limits:Evidence_tar.limits -> normalized:bool
  -> expected:(string * string) list -> string -> Evidence_tar.member list
(** Decompresses entire output and waits for successful exit (including CRC)
    before strict nonextracting verification. Expected names are full tar names.
    Output-size limit is polled during supervision and checked again afterward;
    disk usage can overshoot by bytes produced between supervisor polls. *)

val verify_input_bundle
  : runtime:runtime -> limits:Evidence_tar.limits -> manifest_sha256:string
  -> inventory:(string * string) list -> string -> Evidence_tar.member list
(** Inventory names are bundle-relative and must not include manifest.json.
    Also enforces manifest-first/sorted-path order and normalized metadata. *)
