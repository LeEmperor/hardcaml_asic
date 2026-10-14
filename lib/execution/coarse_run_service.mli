(** Bounded coarse service: external [-m librelane], exact emitted configuration,
     synthesis or Docker full Classic. Failed attempts remain collectable. *)
exception Retained_error of Run_record.outcome * Runner.error

(** Terminal publication failure after the initial run record was saved. The
    retained outcome/error preserve an earlier implementation failure or signal;
    otherwise publication is failure/2. The record may still be nonterminal. *)
val run : bundle:string -> support_tools:string -> pdk_root:string -> python:string
  -> resources:string -> environment:string list -> runs:string
  -> plan:Execution_plan.Coarse.t -> ?native:bool -> ?allow_python_mismatch:bool
  -> unit -> Run_record.outcome
(** Manifest/plan/native-full errors before allocation propagate to the caller.
    After allocation, ordinary failures and SIGINT/SIGTERM produce retained terminal
     records and outcome codes 1/130/143. Initial publication errors propagate;
     terminal publication errors raise [Retained_error].
    Synchronous main-thread signal scope, restored on return. No Classic journal. *)
