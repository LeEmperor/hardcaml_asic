(** Read exactly the retained producer's synthesis stat report, without discovery
    or writes. Missing sources are optional; invalid evidence yields diagnostics.
    Provenance never extends checkpoint inventory validation. *)
val read : run_dir:string -> mapped_count:Z.t option -> Identity_json.t list * Identity_json.t list

(** Shared strict count/area checks for retained stat evidence. Raises
    [Invalid_argument] on inconsistent or malformed producer measurements. *)
val validate_counts : mapped_count:Z.t option -> Evidence_json.t -> (string * Z.t) list * Z.t
