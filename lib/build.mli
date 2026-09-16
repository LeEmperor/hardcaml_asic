(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "build.mli" *)
(* The immutable result of one successful project elaboration.

   A build can be inspected without running any tool. It keeps portable design intent
   (metadata, target selection, clocks, resource inventory) separate from adapter
   settings. It is not a LibreLane configuration; adapters render one from it (P3).

   Nothing can be added to a build after finalization: the elaboration context that
   produced it is closed.

   Not yet present: the resolved target and validated constraints (P2), and emitted
   artifacts and provenance (P3). The circuit is flattened for now; hierarchical RTL
   emission is a P3 decision. *)

open! Core
open! Hardcaml

type t [@@deriving sexp_of]

val project_name : t -> string
val metadata : t -> Metadata.t
val mode : t -> Elaboration_mode.t
val target : t -> Target.t
val flow : t -> Flow.t
val clocks : t -> Clock.t list

(** Ordered by {!Resource_id.compare}, independent of registration order. *)
val resources : t -> Resource_record.t list

val circuit : t -> Circuit.t

module Private : sig
  val create
    :  project_name:string
    -> metadata:Metadata.t
    -> mode:Elaboration_mode.t
    -> target:Target.t
    -> flow:Flow.t
    -> clocks:Clock.t list
    -> resources:Resource_record.t list
    -> circuit:Circuit.t
    -> t
end
