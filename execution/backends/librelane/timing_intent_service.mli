(** Provider-owned supplementary analysis after successful coarse synthesis.
    The exact observed immutable image is reused; STA corners are serialized. *)
val capture : ?timeout:float -> run_dir:string -> context:Identity_json.t
  -> binding:Execution_transport.binding -> pdk_root:string -> resources:string
  -> environment:string list -> cancel:(unit -> int option)
  -> verify_runtime:(unit -> (unit, string) result) -> unit -> unit
