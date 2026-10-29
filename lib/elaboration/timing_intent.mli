open! Core
open! Hardcaml

(** Checked elaboration intent, never tool-resolution evidence. *)
type t
val resolve : circuit:Circuit.t -> timing:Platform.Timing.t
   -> registrations:(Platform.Timing.Stage.t * Signal.t) list -> t option Or_error.t
(** Explicit qualification metadata; does not change architectural resolution or
    assert that native tools have qualified this policy. *)
val physical_policy : string
val physical_manifest : unit -> Yojson.Safe.t
(** Default v1 rendering is preserved. Physical v2 permits only the fixed bounded
    noninverting table and requires exact complete sequential-stage inventory. *)
val to_json : ?physical:bool -> t -> Yojson.Safe.t
val sdc : ?physical:bool -> t -> string
