open! Core

(** Pure versioned inspection. Selection is distinct from the actual elaboration
    role. Resolved linkage observes RTL, not synthesis or physical retention. *)
type t
val of_elaborated : Elaborated_project.t -> t
val of_resolved : Resolved.t -> t
val to_json : t -> Yojson.Safe.t
(** Strict schema reader; does not reconstruct or certify a Resolved.t. *)
val of_json : Yojson.Safe.t -> t Or_error.t
