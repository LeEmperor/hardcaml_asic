(** Direct structural selection only. No recursive discovery or latest-attempt
    selection; conflicting markers and malformed selected evidence are errors. *)
type target = Coarse_run of string | Checkpoint of string
            | Stage_execution of { path : string; selected_record : string }
val select : string -> (target, string) result
type t = { envelope : Identity_json.t; human : string }

(** Host-only read-only reporting. Coarse targets belong to [Report_service].
    Recorded failures are evidence, not report-query failures. *)
val run : ?verbose:bool -> target -> (t, string) result
