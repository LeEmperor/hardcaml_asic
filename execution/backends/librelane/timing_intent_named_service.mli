(** Required linked native analysis of a retained named synthesis publication.
    Publication is already retained by Runner. No checkpoint writes or rerender. *)
val expected : Identity_json.t -> bool
val plan_expected : Hardcaml_asic.Methodology_plan.t -> bool
(* Pure selection from an already-decoded frozen plan, not bundle validation. *)
val validate_plan : methodology:Methodology_execution_record.t option ->
  initial_checkpoint:string option -> plan:Execution_plan.t -> Identity_json.t -> unit
val expectation : workspace:string -> attempt_id:string -> Identity_json.t
val source_count_limit : int
val source_size_limit : int
val source_total_limit : int
val precheck_sources : ?external_roots:string list -> string list -> unit
(* Header/stat-only admission:4096 distinct declared sources,128MiB each,
    512MiB total. Explicit canonical collateral roots permit stat-only alias
    resolution; declared keys remain distinct even when their targets coincide.
    Capture metadata stays strict. Capture binds B's external_aliases proof to exact
    checkpoint keys and verifies resolution/hash/size before/after runtime. *)
val capture : ?timeout:float -> workspace:string -> resources:string ->
  methodology:Methodology_execution_record.t -> plan:Execution_plan.t ->
  expectation:Identity_json.t -> occurrence:Runner.occurrence ->
  segment:Segment_service.segment ->
  publication:Segment_service.checkpoint Runner.publication ->
  binding:Execution_transport.binding -> pdk_root:string -> environment:string list ->
  cancel:(unit -> int option) -> verify_runtime:(unit -> (unit, string) result) ->
  verify_inputs:(unit -> (unit, string) result) -> unit -> unit
(** Raises Runner.Callback_error with primary and secondary causes. Missing failed
    companion due to storage failure remains invalid, never historical absence. *)
