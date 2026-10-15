(** Bounded schema-1 result normalization. No EDA, postcheck execution, acceptance,
    run selection, or writes occur in [collect]. Malformed optional reports become
    diagnostics; malformed required context, manifest or postcheck records fail.
    Finite/integral/nonnegative count acceptance belongs to the reporter. *)
type metric = private
  { value : Evidence_json.t
  ; unit_ : string
  ; definition : string
  ; stage : string
  ; corner : Evidence_json.t
  ; source : string
  ; unavailable_reason : Evidence_json.t
  }
val metric : ?corner:Evidence_json.t -> ?reason:Evidence_json.t
  -> value:Evidence_json.t -> unit_:string -> definition:string
  -> stage:string -> source:string -> unit -> metric
val metric_json : metric -> Evidence_json.t
type t
val collect : ?context:Evidence_json.t -> ?synthesis_state:string
  -> string -> t
val to_json : t -> Evidence_json.t

(** Caller explicitly selects the run and destination. Same-directory atomic
    replacement, only the result destination is written. Success is collection,
    never acceptance; retained run/process status is not inferred or edited. *)
val save : string -> t -> unit
