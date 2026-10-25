open! Core

(** Stable cooperative boundaries, not physical stages. Callback exceptions are
    propagated to the operation owner, never swallowed as design diagnostics. *)
module Phase : sig
  type t = Source_before | Construction | Finalization | Resolution
         | Circuit | Source_after | Snapshot
  [@@deriving compare, equal, sexp_of]
  val to_string : t -> string
  val of_string : string -> t Or_error.t
end

module Failure : sig
  type diagnostic = { code : string; message : string; detail : Sexp.t }
  type t = { phase : Phase.t; diagnostics : diagnostic list }
  val create : phase:Phase.t -> code:string -> message:string -> Error.t -> t
  val to_json : t -> Yojson.Safe.t
  val of_json : Yojson.Safe.t -> t Or_error.t
end

(** A successful, identity-bound preparation. Historical decoding validates its
    schema and content identities, not the truth of a producer's declarations.
    No bundle identity, readiness, P6 source stamp or measured evidence is implied. *)
type t
val identity : t -> string
val source_identity : t -> string
val configuration_identity : t -> string
val circuit_identity : t -> string
val resources : t -> Elaboration.Resource_snapshot.t
val to_json : t -> Yojson.Safe.t
val of_json : Yojson.Safe.t -> t Or_error.t
val to_string : t -> string
(** Strict JSON/schema/identity decoder, including duplicate keys at every depth. *)
val of_string : string -> t Or_error.t

module Success : sig
  type nonrec t = t
  val identity : t -> string
  val source_identity : t -> string
  val configuration_identity : t -> string
  val circuit_identity : t -> string
  val resources : t -> Elaboration.Resource_snapshot.t
  val to_json : t -> Yojson.Safe.t
  val of_json : Yojson.Safe.t -> t Or_error.t
  val to_string : t -> string
  val of_string : string -> t Or_error.t
end

module Private : sig
  (** Project's construction seam; validates the same wire consumed by readers. *)
  val create
    : source:Elaboration.Source_snapshot.t
    -> declaration:Sexp.t
    -> inputs:Platform.Target.Inputs.t
    -> resolution:Elaboration.Resolved.t
    -> rtl:string
    -> t Or_error.t
end
