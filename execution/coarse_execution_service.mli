(** Fixed Classic aggregate, using the checked coarse plan and [Runner]. No
    journal is fabricated. The allocated run and its results are explicitly
    mutable evidence; report acquisition is read-only. *)
type callbacks = {
  run : unit -> Run_record.outcome;
  postcheck : Run_record.outcome -> Postcheck_service.outcome;
  collect : Run_record.outcome -> Collect_service.t;
  report : Run_record.outcome -> (Report_service.result, int) result;
  archive : Run_record.outcome -> (Archive_service.publication, int) result;
}
type t = (Run_record.outcome, unit) Runner.t

(** Collection callback includes explicit results publication. No optional
    selection is inferred: disabled plan actions never call their callback.
    Preallocation exceptions propagate; retained failures remain collectable.
    SIGINT/TERM across callbacks veto physical work, allowing saved-run collection.
    Services retain their own time/resource bounds. Error results require positive
    exit codes. Synchronous main-thread-only signal scope, restored on return. *)
val execute : ?clock:(unit -> float) -> ?attempt_id:string
  -> ?observe_postcheck:(Postcheck_service.outcome -> unit)
  -> plan:Execution_plan.Coarse.t -> archive:string option -> callbacks -> t
val to_json : t -> Identity_json.t
