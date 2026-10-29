(** Pure interpretation of one actual native corner process. A State value alone
    or sampled timing witness cannot supply a metric. Units must be independently
    established from every retained loaded Liberty. *)
val finite : Evidence_json.t -> float option
val interpret : corner:string -> log:string -> output_state:Evidence_json.t ->
  libraries:string list -> Evidence_json.t
val aggregate : Evidence_json.t list -> string
