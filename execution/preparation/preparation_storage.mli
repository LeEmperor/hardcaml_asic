(** Bounded evidence reads. Leaf entries must be regular files, never symlinks.
    lstat, nonblocking open and fstat prevent a replaced FIFO from blocking the
    reader. File identity/type are rechecked after reading. Caller-owned stable
    parent directories are required; this is not a hostile-filesystem sandbox. *)
val operation_limit : int
val snapshot_limit : int
val read_bytes : limit:int -> string -> string
module For_testing : sig
  (** Deterministic leaf-replacement race immediately after lstat. *)
  val read_bytes : after_lstat:(unit -> unit) -> limit:int -> string -> string
end
