(** Host-only bounded projection over ASIC-owned inventory/reconciliation. All
    page requests re-read and verify the exact source and require its index digest.
    Kinds: bundle, coarse_run, execution, finalization. Queries: index (default),
    detail, artifacts, bytes. No EDA, current PDK/source discovery or publication. *)
type target = Bundle of string | Coarse_run of string | Execution of string | Finalization of string

val inspect : target -> ?query:string -> ?resource_id:string
  -> ?section:string -> ?expected_digest:string -> ?artifact_id:string
  -> ?offset:int -> ?limit:int -> unit -> (Evidence_json.t, string) result

(** CLI compatibility shim; rejects unknown kind strings. *)
val run : kind:string -> target:string -> ?query:string -> ?resource_id:string
  -> ?section:string -> ?expected_digest:string -> ?artifact_id:string
  -> ?offset:int -> ?limit:int -> unit -> (Evidence_json.t, string) result
