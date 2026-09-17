(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "build.mli" *)
(* The immutable result of one successful project elaboration.

   A build can be inspected without running any tool. It keeps portable design intent
   (metadata, target selection, clocks, resource inventory) separate from adapter
   settings. It is NOT a LibreLane configuration; adapters render one from it (P3).

   Nothing can be added to a build after finalization: the elaboration context that
   produced it is closed. A failed elaboration produces no build at all.

   Not yet present: the resolved target and validated constraints (P2), and emitted
   artifacts and provenance (P3). The circuit is flattened for now; hierarchical RTL
   emission is a P3 decision.
*)

open! Core
open! Hardcaml

(** Prints every field except the circuit, which is summarised by its top module name. *)
type t [@@deriving sexp_of]

(** The name given to {!Project.create}. *)
val project_name : t -> string

val metadata : t -> Metadata.t

(** The mode passed to {!Project.elaborate}. *)
val mode : t -> Elaboration_mode.t

(** The declared harness and technology selection. Nothing has checked that the pair is
    compatible yet (P2). *)
val target : t -> Target.t

val flow : t -> Flow.t

(** The declared clocks. Their ports are not yet checked against the circuit (P2). *)
val clocks : t -> Clock.t list

(** Ordered by {!Resource_id.compare}, independent of registration order. *)
val resources : t -> Resource_record.t list

(** The flattened circuit returned by the design constructor. *)
val circuit : t -> Circuit.t

module Private : sig
  (** Only {!Project.elaborate} should call this, after
      {!Elaboration_context.Private.finalize} succeeded. It performs no validation. *)
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
