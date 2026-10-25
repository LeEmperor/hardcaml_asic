open! Core

(** PDK-free declaration of the supported fresh CMOS5L hardening strategy.
    Runtime geometry is checked by the generated Tcl against the loaded database. *)
type macro =
  { resource : Resource.Id.t
  ; instance : string
  ; name : string
  ; intent : Flow.Macro_intent.t
  }

type t

val create : macro list -> t Or_error.t
val to_json : t -> Yojson.Safe.t
val settings : t -> (string * Yojson.Safe.t) list
val files : t -> (string * string) list

(** Includes deprecated backend aliases. Owned only when a physical plan is active. *)
val owns_key : string -> bool
