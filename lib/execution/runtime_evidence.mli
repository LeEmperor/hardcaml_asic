(** Pure validation of externally obtained observations. A decoded observation is
    evidence of a probe response, not readiness or successful backend execution.
    Importlib/Tcl and Docker probes remain caller-owned and injectable. *)
type tcl = private { ready : bool; version : string option; error : string option }
type metadata = private
  { python_version : string
  ; librelane_version : string option
  ; requires_python : string option
  ; metadata_error : string option
  ; tcl : tcl option
  ; raw : Identity_json.t
  }
val metadata : ?host:bool -> Identity_json.t -> (metadata, string) result
val parse_metadata : ?host:bool -> string -> (metadata, string) result
val metadata_to_json : metadata -> Identity_json.t
(** Matches Python metadata validation: required nullable string fields, mandatory
    Python string and, for host, a typed Tcl response. Additive fields retained.
    Strict Identity_json additionally rejects duplicates/nonfinite/invalid Unicode. *)

type evaluation
val evaluate_observations
  : Runtime_contract.t -> host:Identity_json.t -> ?container:Identity_json.t
  -> ?native:bool -> ?allow_python_mismatch:bool -> unit
  -> (evaluation, string) result
val evaluate_container
  : Runtime_contract.t -> Identity_json.t -> (evaluation, string) result
val evaluation_to_json : evaluation -> Identity_json.t
val comparisons : evaluation -> Identity_json.t list
val issues : evaluation -> Identity_json.t list
val waivers : evaluation -> Identity_json.t list
val policy_satisfied : evaluation -> bool
(** Policy satisfaction includes exact host LibreLane and headless Tcl readiness
    for evaluate_observations; it is not overall preflight/flow readiness. *)

val binding_from_observation
  : native:bool -> Identity_json.t -> (Execution_transport.binding, string) result
(** Uses the existing closed transport validator; no second binding model.
    Does not infer readiness from an observation or evaluate policy. *)

val docker_binding
  : declared_ref:string -> executable:string -> info:Identity_json.t
  -> inspection:Identity_json.t -> observation:Identity_json.t
  -> (Execution_transport.binding, string) result
(** Decode one image inspection and Docker info, then validate through the same
    transport binding API. The caller supplies the successful metadata observation
    and selected interpreter flags. No retry/probe or packaging fallback occurs.
    Missing engine readiness (rootless/server version) fails binding validation. *)

val verify_image : Execution_transport.docker -> actual_id:string -> (unit, string) result
val verify_engine : Execution_transport.docker -> Identity_json.t -> (Identity_json.t, string) result
(** Pure counterparts of Python transport re-verification. Compare fresh probe
    results to the bound local ID/server, not a mutable tag or requested version.
    Absent/null optional engine identity is not asserted. No engine invocation. *)
