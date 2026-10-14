(** Bounded Python-compatible service plans. Pure validation/resolution only;
    capabilities are static declarations, not runtime readiness. *)
module Stage = Hardcaml_asic.Flow.Stage
module Recipe = Hardcaml_asic.Flow.Recipe

module Action : sig
  type operation = Run | Postcheck | Collect | Report | Archive | Segment
  type gate = Success | Run_available | Accepted
  type phase = Implementation | Verification | Results | Acceptance | Retention
             | Physical of Stage.t
  type t = private
    { key : string
    ; operation : operation
    ; stage : phase
    ; label : string
    ; enabled : bool
    ; requires : string list
    ; gate : gate
    ; inputs : string list
    ; outputs : string list
    }
  val to_json : t -> Identity_json.t
end

module Coarse : sig
  type endpoint = Synthesis | Full
  type t

  (** Exactly five fixed service contracts; archive alone is optional.
      Labels are presentation data and may be changed after Unicode validation. *)
  val resolve : ?archive:bool -> endpoint -> t
  val with_labels : t -> string list -> (t, string) result
  val endpoint : t -> endpoint
  val actions : t -> Action.t list
  val of_json : Identity_json.t -> (t, string) result
  val to_json : t -> Identity_json.t
end

module Stage_plan : sig
  type t

  (** Schema 2. Resumption is from synthesis, including all intervening stages. *)
  val resolve : ?resume:bool -> Stage.t -> (t, string) result

  (** Schema 3, using the hardware library's checked contiguous recipe. *)
  val of_recipe : Recipe.t -> t
  val resolve_sequence : ?initial_boundary:Stage.t -> Stage.t list -> (t, string) result
  val through : ?initial_boundary:Stage.t -> Stage.t -> (t, string) result
  val schema_version : t -> int
  val endpoint : t -> Stage.t
  val source_boundary : t -> Stage.t option
  val sequence : t -> Stage.t list
  val recipe : t -> Recipe.t
  val actions : t -> Action.t list
  val of_json : Identity_json.t -> (t, string) result
  val to_json : t -> Identity_json.t
end

type t = private Coarse of Coarse.t | Stages of Stage_plan.t
val of_coarse : Coarse.t -> t
val of_stages : Stage_plan.t -> t
val of_json : Identity_json.t -> (t, string) result
val parse : string -> (t, string) result
val to_json : t -> Identity_json.t
val actions : t -> Action.t list

(** Same shape as Python [boundary_capabilities], sourced from [Flow.Stage]. *)
val capabilities : unit -> Identity_json.t

(** Normalized plan, resolved actions, source boundary/sequence (null for coarse),
    static capabilities, all six [operation_groups], and requested
    [operation_sequence] (null for coarse). Occurrences describe the trusted
    selected-Classic composition; gates/defaults are configuration contracts,
    [execution_evidence] is null, and individual steps advertise no durable
    checkpoint. No tool probes, paths, allocation or execution. *)
val inspection : t -> Identity_json.t
