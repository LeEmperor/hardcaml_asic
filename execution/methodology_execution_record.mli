(** Named-flow v1 immutable evidence. Main-library plan codecs own all identities.
    Context (attempt and absolute snapshot path) is outside the plan hash. *)
type t
val to_json : t -> Identity_json.t
val publish : directory:string -> attempt_id:string -> expected:string
  -> Hardcaml_asic.Methodology_plan.t -> t
val of_json : attempt_id:string -> plan:Execution_plan.Stage_plan.t
  -> Identity_json.t -> (t, string) result
val plan : t -> Hardcaml_asic.Methodology_plan.t

(** Same strict reference/snapshot/identity decoder for preflight attempts that
    have not recorded an execution plan yet. No catalog or runtime access. *)
val of_reference_json : attempt_id:string -> Identity_json.t -> (t, string) result
