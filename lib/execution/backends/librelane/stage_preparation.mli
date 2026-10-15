(** OCaml-owned bundle readiness, fresh staging and exact path-bound resumption.
    This service does not provision tools. Optional observation ownership is
    allocated by the caller before plan resolution/preflight; it writes the
    referenced preflight report and uses the writer's stream ID for execution.
     Failed preparation retains its separate early preflight/probe evidence and
     any newly owned partial workspace. Existing work is never adopted as fresh.
     Named preparation retains the checked plan's input inventory/config bytes and
     measured collateral digests. Execution rechecks actual staged paths before
     and after successful calls and before publication, and checks effective typed
     parameters against backend resolved.json. Generated supplementary files are
     outside that frozen input inventory. Requires trusted stable parents and
     exclusive workspace use; this is bounded pre/post validation, not protection
     against arbitrary adversarial filesystem races. *)
type t = private
  { service : Segment_service.t
  ; compatibility : Identity_json.t
  ; binding : Execution_transport.binding
  ; preflight_path : string
  ; evidence_directory : string
  ; summary_path : string
  ; diagnostics_path : string
   ; attempt_id : string
   ; methodology : Methodology_execution_record.t option
  }
type error = private { cause : Runner.error; preflight_path : string option;
  methodology : Methodology_execution_record.t option }
val installed_resources : executable:string -> string
(** Prefix-relative lib/hardcaml_asic/flow/hardcaml_asic_flow. No checkout search. *)

(** [after_methodology_snapshot] is a test synchronization callback between sidecar
    publication and reference-report commit. Exceptions follow preparation failure
    handling; production callers leave it absent. *)
val prepare : bundle:string -> support_tools:string -> pdk_root:string -> python:string
  -> docker:string -> git:string -> resources:string -> workspace:string
  -> checkpoint_store:string -> evidence_root:string -> environment:string list
  -> ?timeout:float -> ?probe_timeout:float -> ?initial_checkpoint:string
    -> ?observation:Observation_writer.t
     -> ?failure_exit_code:(Backend_protocol.operation -> Execution_transport.result -> int option)
     -> ?methodology:(string * Hardcaml_asic.Methodology_plan.t)
     -> ?after_methodology_snapshot:(unit -> unit)
   -> plan:Execution_plan.t -> unit -> (t, error) result
val execute : ?observation:Observation_writer.t -> t -> Execution_plan.t -> (unit, Segment_service.checkpoint) Runner.t
(** Composes Segment_service/Runner, persisting their existing summary and separate
    diagnostics at fresh reserved paths. Timeout defaults to 600 seconds per call;
     probe timeout defaults to 20 seconds. Neither is a whole-plan deadline.
     Caller records planned/prepared/outcome. Execute connects only Runner hooks;
     terminal persistence precedes return and therefore the caller's outcome. *)
