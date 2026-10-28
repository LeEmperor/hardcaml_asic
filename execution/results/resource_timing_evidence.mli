(** Read-only sampled STA evidence. [read path format] returns bytes and the
    shared reader's reference; [exists] and [read] must enforce run containment.
    [flow] is a safe run-relative flow directory. [resources] are reconciled final
    physical resource rows, not declaration-only expectations. [final_netlist] is
    the shared reader's reference to the observed final implementation netlist. *)
type links = {
  resource_id : string;
  timing_links : Evidence_json.t;
  electrical_links : Evidence_json.t;
}

type collection = { resources : links list; diagnostics : string list }

val collect :
  read:(string -> string -> string * Evidence_json.t) ->
  exists:(string -> bool) ->
  flow:string ->
  context:Evidence_json.t ->
  manifest:Evidence_json.t ->
  resources:Evidence_json.t list ->
  final_netlist:Evidence_json.t ->
  (collection, string) result

(** Structural/ownership/reference validation. Source-aware correctness additionally
    requires the caller's full collection replay over the recorded source bytes. *)
val validate_links :
  references:Evidence_json.t list ->
  resource:Evidence_json.t ->
  timing_links:Evidence_json.t ->
  electrical_links:Evidence_json.t ->
  (unit, string) result
