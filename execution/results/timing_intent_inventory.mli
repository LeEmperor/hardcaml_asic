(** Named outer source admission. Inner native audit/coarse limits are separate.
    Files are stat-admitted before hashing; hashing streams exactly the admitted
    byte count and rejects replacement/growth/shrinkage. Canonical metadata and
    native files stay strict. Only explicit, closure-bound external collateral
    aliases may use a different declared path and canonical target. *)
val max_sources : int
val max_source_bytes : int
val max_total_bytes : int
type usage = { source_count : int; total_bytes : int; largest_bytes : int }
type alias = private { path:string; target:string; root:string; sha256:string; bytes:int }
val regular : ?aliases:alias list -> string -> Unix.stats
val admit_paths : ?aliases:alias list -> ?external_roots:string list -> string list -> usage
val hash : ?aliases:alias list -> string -> string
val capture_aliases : roots:string list -> paths:string list -> alias list
val aliases_to_json : alias list -> Evidence_json.t
val aliases_of_json : Evidence_json.t -> alias list
val validate_aliases : roots:string list -> external_files:(string * Checkpoint.file_record) list -> alias list -> unit
val admit_checkpoint : string -> unit
