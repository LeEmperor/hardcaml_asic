(** Pure bundle-authoritative runtime policy. No installed defaults, IO, probes,
    packaging-specifier interpretation or fallback from malformed explicit policy. *)
type source = Legacy | Runtime_policy
type t = private { source : source; python_minor : string; librelane : string }
val supported_minors : string list
val requires_python : string
val image_ref : t -> string
val policy_from_requested : Identity_json.t -> (t, string) result
val policy_from_lock : Identity_json.t -> (t, string) result
(** Lock values must be explicit strings. This API must never replace bundle authority. *)

val of_json : Identity_json.t -> (t, string) result
val parse : string -> (t, string) result
val to_json : t -> Identity_json.t

type role = Host | Container
type status = Pass | Fail | Waived
type comparison = private
  { role : role; field : string; expected : Identity_json.t
  ; actual : Identity_json.t; status : status }
type evaluation = private
  { contract : t; native : bool; comparisons : comparison list
  ; issues : comparison list; waivers : comparison list }
val evaluate
  : t -> host:Identity_json.t -> ?container:Identity_json.t -> ?native:bool
  -> ?allow_python_mismatch:bool -> unit -> (evaluation, string) result
(** Missing fields become failed comparisons. Required observation objects must
    exist. Only syntactically valid legacy exact-minor mismatches are waivable.
    Native skips container checks; it does not establish native stage support. *)

val evaluation_to_json : evaluation -> Identity_json.t
