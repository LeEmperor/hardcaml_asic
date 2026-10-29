(** Explicit macro-free coarse qualification adapter (companion2/audit3).
    Historical synthesis and named adapters remain separate. Inspection replays
    retained sources without Tcl, rendering, current PDK lookup or native tools.
    Overall exhaustive exception coverage is always unavailable. *)
val enabled : Evidence_json.t -> bool
val inspect : run_dir:string -> unit -> (Evidence_json.t, string) result
val source_files : run_dir:string -> context:Evidence_json.t -> unit ->
  (Evidence_json.t list, string) result
val publish : run_dir:string -> context:Evidence_json.t -> succeeded:bool -> unit -> unit
