(** Ordinary coarse synthesis companion. No tool discovery, Tcl execution or
    rerendering occurs during inspection. Historical absence is unavailable;
    advertised but missing/corrupt evidence is an error. Named flows are deferred. *)
val expected : Evidence_json.t -> bool
val inspect : run_dir:string -> unit -> (Evidence_json.t, string) result
val source_files : run_dir:string -> context:Evidence_json.t -> unit
  -> (Evidence_json.t list, string) result

(** Provider-only publication after supervised runtime completion. *)
val publish : run_dir:string -> context:Evidence_json.t -> succeeded:bool
  -> unit -> unit
