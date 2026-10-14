(** Read-only validation of Runner's segmented schema-2/3 records. No runtime
    probes or finalization eligibility requirements. Original JSON is retained. *)
type t = private
  { raw : Identity_json.t
  ; plan : Execution_plan.Stage_plan.t
  ; occurrences : Identity_json.t list
  ; references : Identity_json.t list
  ; status : string
  }
val of_json : Identity_json.t -> (t, string) result
val read : string -> (t, string) result
