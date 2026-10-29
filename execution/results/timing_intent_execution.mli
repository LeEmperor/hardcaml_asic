(** Path-bound named synthesis evidence. No tools, renderer or current PDK lookup.
    Named archive/relocation is not supported. *)
val inspect : execution:string -> unit -> (Evidence_json.t, string) result
val source_files : execution:string -> unit -> (Evidence_json.t list, string) result
(* Admission only, no EDA/hashing. Supply complete conservative closure plus all
   intended bundle/checkpoint/analysis/metadata paths; no source filtering. Explicit
   canonical external_roots permit stat-only alias admission and return each
   declared->target resolution. Declared paths, not targets, are counted/charged.
   Default admission stays strict. Runtime binds those aliases in publication. *)
val precheck_sources : ?external_roots:string list -> paths:string list -> unit -> (Evidence_json.t, string) result

(** Uses the caller's exact captured, validated execution/checkpoint generation.
    None is historical absence; required or malformed present evidence never is. *)
val inspect_snapshot : execution:string -> execution_sha256:string -> raw:Identity_json.t ->
  record:Stage_execution_record.t -> checkpoints:(string * Checkpoint.t) list ->
  unit -> (Evidence_json.t option, string) result

(** Provider-only exclusive companion publication, after runtime completion. *)
val publish : directory:string -> succeeded:bool -> failure:Identity_json.t -> unit -> unit
