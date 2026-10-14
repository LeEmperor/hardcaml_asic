(** Read exactly the retained producer's synthesis stat report, without discovery
    or writes. Missing sources are optional; invalid evidence yields diagnostics.
    Provenance never extends checkpoint inventory validation. *)
val read : run_dir:string -> mapped_count:Z.t option -> Identity_json.t list * Identity_json.t list
