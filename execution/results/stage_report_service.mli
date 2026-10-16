(** Direct structural selection only. No recursive discovery or latest-attempt
    selection; conflicting markers and malformed selected evidence are errors. *)
type target = Coarse_run of string | Checkpoint of string
            | Stage_execution of { path : string; selected_record : string }
val select : string -> (target, string) result
type t = { envelope : Identity_json.t; human : string }

(** Host-only read-only reporting. Coarse targets belong to [Report_service].
    Recorded failures are evidence, not report-query failures. *)
val run : ?verbose:bool -> target -> (t, string) result

(** The report's execution/checkpoint/compatibility/shared-file validation,
    without reading optional supplementary producer reports. *)
val validate_execution : string -> (Stage_execution_record.t, string) result

(** Validate the supplied captured execution value and retain the exact
    validated manifests. Subsequent segment reads must match their inventories. *)
val validate_execution_snapshot : ?admit_metadata:(string -> unit) -> Identity_json.t ->
  (Stage_execution_record.t * (string * Checkpoint.t) list, string) result

(** Bind exact segment bytes to a previously validated inventory hash before
    decoding. Also used by race regression fixtures; a final rehash alone is
    insufficient to establish this association. *)
val decode_segment_bytes : expected_sha256:string -> string -> (Identity_json.t, string) result

(** Normalized metadata, explicitly [state=not_recorded] for historical records.
    Legacy report bytes omit the additive named-only envelope field. *)
val methodology : t -> Identity_json.t
