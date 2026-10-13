open! Core

(** Tested LibreLane Classic segment boundaries, not individual backend steps.
    Successor checks remain part of the next segment. No stage settings are
    implied by these declarations; project adapter settings remain on [Flow]. *)
type t = Synthesis | Floorplan | Placement | Cts | Routing | Signoff
[@@deriving compare, equal, sexp_of]

val all : t list
val to_string : t -> string
val of_string : string -> t Or_error.t

module Closure_scope : sig
  type t = Path_bound [@@deriving equal, sexp_of]
end

module Acceptance : sig
  type t = Not_evaluated [@@deriving equal, sexp_of]
end

type capability =
  { endpoint : string
  ; successor : string option
  ; restart_targets : t list
  ; tested_image_id : string
  ; closure_scope : Closure_scope.t
  ; acceptance : Acceptance.t
  }
[@@deriving sexp_of]

(** Static demonstrated capabilities, not a probe of the caller's installation.
    Docker, the exact tested image, retained workspace/input/support/PDK roots,
    and runtime bridge/configuration closure validation are required. Native,
    relocated and macro handoffs are outside the implemented stage service.
    Signoff is terminal and does not imply external postcheck or acceptance.
    Synthesis -> placement is supported by the standalone Python segment API;
    recipes always include the intermediate floorplan stage. *)
val capability : t -> capability
