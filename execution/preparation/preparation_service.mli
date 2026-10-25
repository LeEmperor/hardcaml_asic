(** In-process project-owned invocation. Allocate before calling [prepare], which
    must construct the project and pass [on_phase] to Project.prepare_resources.
    Request is JSON metadata only; it conveys no executable authority.

    Main-thread-only, non-reentrant scoped SIGINT/SIGTERM ownership. Handlers are
    restored. Cancellation is cooperative at phase/publication boundaries;
    arbitrary constructors are not forcibly preempted. At terminal commit INT/TERM
    are blocked and one final check consumes signals already observed by the
    runner. The subsequent save and exact readback are noncancellable. Pending
    commit signals are delivered under the previous handlers/mask after restoring
    them, even if commit verification raises; terminal records are never rewritten
    in response. A previous default handler may therefore terminate the process
    after a valid terminal record, before terminal JSONL delivery. Standard POSIX
    signal coalescing applies. A crash may leave Running.
    Terminal publication errors propagate; no completed outcome is returned.
    Terminal attempts are never resumed or rewritten; retries allocate afresh. *)
type prepare =
  on_phase:(Hardcaml_asic.Resource_preparation.Phase.t -> unit) ->
  (Hardcaml_asic.Resource_preparation.t,
   Hardcaml_asic.Resource_preparation.Failure.t) result
type outcome = private { directory : string; record : Preparation_record.t }
val run : store:string -> request:Identity_json.t -> prepare:prepare
  -> ?allocated:(directory:string -> attempt_id:string -> unit) -> unit -> outcome

(** Standard foreground delivery: flushed allocation then terminal JSONL with
    [json=true]; useful human summaries otherwise. Caller exits with record code.
    Delivery errors propagate; callers must report these as command failures. *)
val run_cli : store:string -> request:Identity_json.t -> prepare:prepare
  -> json:bool -> unit -> outcome

module For_testing : sig
  val run : save_bytes:(string -> string -> unit) -> store:string
    -> request:Identity_json.t -> prepare:prepare
    -> ?allocated:(directory:string -> attempt_id:string -> unit) -> unit -> outcome
end
