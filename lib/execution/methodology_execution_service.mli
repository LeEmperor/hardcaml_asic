(** No tools, probes, allocation or writes. Checks the frozen plan against the
    actual bundle, including every inventory digest and source identity. *)
val check : bundle:string -> expected:string -> Hardcaml_asic.Methodology_plan.t
  -> (Execution_plan.t, string) result

(** Exact typed effective assignments, not documented defaults, against backend output.
    Also used by historical readers; no backend imports or current catalog reads. *)
val check_resolved : Hardcaml_asic.Methodology_plan.t -> string -> (unit, string) result
