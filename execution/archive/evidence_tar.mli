(** Bounded-memory regular-file USTAR/PAX codec; never extracts files.
    Paths are relative UTF-8 bytes, with no empty/dot/dot-dot components,
    backslashes or NULs. Local PAX only; unsupported extensions are rejected. *)
type metadata =
  { mode : int; uid : int64; gid : int64; uname : string; gname : string
  ; mtime : string }
type member = { name : string; bytes : int64; sha256 : string; metadata : metadata }
type source = { path : string; name : string; sha256 : string option }
type limits = { max_members : int; max_member_bytes : int64; max_tar_bytes : int64
              ; max_pax_bytes : int; max_name_bytes : int }
val normalized : metadata
val validate_name : string -> unit
val validate_inventory : (string * string) list -> unit

val write : normalized:bool -> out_channel -> source list -> member list
(** Sources must be regular files with no symlink components. Hashes are computed
    from the bytes actually written and checked against optional expected hashes.
    Changes in descriptor metadata/size during copying also fail. Caller owns IO. *)

val verify
  : limits:limits -> normalized:bool -> expected:(string * string) list
  -> in_channel -> member list
(** Exact caller inventory, no duplicates, regular files only, checked header
    checksums, sizes, zero padding and two-block terminator. Reads through EOF,
    permitting only zero record padding. Returns actual hashes in archive order.
    Normalized mode also requires 0644/0/0/empty owner names/mtime 0. *)
