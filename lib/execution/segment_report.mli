(** Closed production bridge report. Public metrics are finite identity JSON;
    native State remains an opaque artifact, never decoded through this module. *)
type metric = Available of Identity_json.t | Unavailable of { reason : string; raw : string }
type t = private
  { boundary : Execution_plan.Stage.t
  ; metrics : (string * metric) list
  ; raw : Identity_json.t
  }
val of_json : request:Backend_protocol.request -> Identity_json.t -> (t, string) result
