(** Selected Classic mapping. Backend [inputs]/[outputs] are native declared
    view IDs, not promises that gated steps ran. Every operation also requires
    the unchanged resolved configuration, technology and preceding native State.
    Gate names are boolean, dimensionless, with upstream defaults. Classic skips
    a step if any configured gate is false. Internal step-specific skip conditions
    remain backend-owned. There are no provider per-step settings/overrides.
    All settings use native validation and immutable resolved-config provenance.
    Inspection is planned structure; observed execution belongs to the journal.
    Only coarse segments are runnable/publishable via protocol v1. *)
val tested_image_id : string
type step =
  { id : string; implementation : string; inputs : string list; outputs : string list
  ; gates : (string * bool) list }
type occurrence = private
  { occurrence_id : string; stage : Stage_id.t; operation : Operation.t; step : step }
type setting = private
  { name : string; kind : string; units : string option; default : string option; pdk : bool }
(** Bounded placement-specific settings, not an exhaustive upstream config schema.
    Decimal defaults are exact text. None means no literal default (optional or
    PDK-supplied). Density None derives FP_CORE_UTIL + 5*GPL_CELL_PADDING + 10.
    Native Variable/Config validation owns type conversion and tool constraints;
    these descriptors do not introduce a provider configuration authoring API. *)
val settings : string -> setting list
val all : occurrence list
val composition : Stage_id.t -> occurrence list
val endpoint : Stage_id.t -> string
val successor : Stage_id.t -> string option
val validate_inventory : step list -> (unit, string) result
val validate_sequence : initial_boundary:Stage_id.t option -> Stage_id.t list -> (unit, string) result
