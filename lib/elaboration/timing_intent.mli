open! Core
open! Hardcaml

(** Checked elaboration intent, never tool-resolution evidence. *)
type t
val resolve : circuit:Circuit.t -> timing:Platform.Timing.t
  -> registrations:(Platform.Timing.Stage.t * Signal.t) list -> t option Or_error.t
val to_json : t -> Yojson.Safe.t
val sdc : t -> string
