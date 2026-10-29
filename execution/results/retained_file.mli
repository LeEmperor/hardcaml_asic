(** Descriptor-bound admission for retained metadata/text. Opens read-only with
    O_NONBLOCK and O_NOFOLLOW on every path component; admits regular files only,
    bounds allocation before reading, and checks descriptor/path generation after
    reading. No symlink, FIFO/device, traversal, write or subprocess path. Callers
    may canonicalize an explicitly selected root before constructing member paths. *)
val read : ?max_bytes:int -> string -> string
val exists : string -> bool
