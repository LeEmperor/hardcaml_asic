(** Read-only validation of Runner's segmented schema-2/3 records. No runtime
    probes or finalization eligibility requirements. Original JSON is retained.
    Absent methodology is the historical format. A present methodology reference
    is required evidence: its exact sidecar, checksum, main-library identities,
    attempt/recipe and published checkpoint bundle associations are checked.
    Missing/corrupted required evidence is an error, never historical fallback. *)
type t = private
  { raw : Identity_json.t
  ; plan : Execution_plan.Stage_plan.t
  ; occurrences : Identity_json.t list
  ; references : Identity_json.t list
   ; status : string
   ; methodology : Methodology_execution_record.t option
  }
val of_json : Identity_json.t -> (t, string) result
val read : string -> (t, string) result
val validate_snapshot : ?admit_metadata:(string -> unit) -> Identity_json.t ->
  (t * (string * Checkpoint.t) list, string) result
val path : workspace:string -> attempt_id:string -> string

(** Writer-owned deterministic location. [available] returns it only after strict
    persisted record validation, including exact allocated methodology/attempt.
    Absent/empty reservations return [None]; malformed evidence is an error. *)
val available : workspace:string -> attempt_id:string
  -> methodology:Methodology_execution_record.t -> (string option, string) result

(** Shared host-only publication/content and effective resolved-value validation
    for named historical observation inspection. *)
val check_methodology_checkpoints : Methodology_execution_record.t
  -> Identity_json.t list -> (unit, string) result
