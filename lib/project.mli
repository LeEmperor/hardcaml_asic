(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "project.mli" *)
(* An immutable ASIC project declaration and its elaboration lifecycle.

   {v
   Project.create             validate the declaration (names, metadata, clocks,
                              policy, adapter settings)
   Project.elaborate ~mode    fresh Elaboration_context
                              -> run the design constructor; resources register and
                                 select implementations (selection failures raise here)
                              -> finalize: validate collected state, close the context
                              -> immutable Build.t
   v}

   Elaboration never invokes an external tool. Each call is independent: a failed
   elaboration leaves nothing behind for the next one. [elaborate_for_flow]
   applies target, interface, constraint, and adapter validation to an
   implementation build before flow emission.
*)

open! Core
open! Hardcaml

(* we're saying that a Design module implements the following items;

   It has a module I and O that implement the capabilities of Hardcaml.Interface;

   It has a "name" member and a function "create" that follows a certain signature.
   Therefore anything that implements these functions, and has the members can be counted
   on as a "Design".
*)
module type Design = sig
  module I : Interface.S
  module O : Interface.S

  (** Top-level module name. *)
  val name : string

  (* A design must have a create function; different from standard is the elaboration
     context that is required for ASIC items. This may be for simulation though, or even
     emultaion, meaning an elaboration context varies by target we're shooting.
  *)
  val create : Elaboration_context.t -> Signal.t I.t -> Signal.t O.t
end

(* A project has a type t -> treats as Project.t *)
type t

[@@@ocamlformat "disable"]
(* Project.create is a function that has members:
  name      : string
  metadata  : Metadata.t
  design    : Design (a module that implements the properties of the Design signature)
  target    : asic? fpga? sim? emulate?
  flow      : tt? cadence? synopsys?
  clocks    : clock data; what speeds, who exists, where they are
  policy    : per-instance or per-subtree requirement (Flops, Exact, Exact_or_flop_fallback); exact contracts only, never rounded or composed; flops are the only fallback
  unit      : positional for optional boundaries

  -> Or_error.t
      we return an error type
*)
val create
  :  name:string
  -> metadata:Metadata.t
  -> design:(module Design)
  -> target:Target.t
  -> flow:Flow.t
  -> ?clocks:Clock.t list
  -> ?pinout:Pinout.t
  -> ?timing:Timing.t
  -> policy:Resource_policy.t
  -> unit
  -> t Or_error.t

(* Of a type t, retrieve a string to be used as a name; *)
val name : t -> string

(* Of a type t, retrieve an elaboration mode item and return a build error shape; *)
val elaborate : t -> mode:Elaboration_mode.t -> Build.t Or_error.t

(** Elaborate the selected implementation and validate the TT/LibreLane target,
    wrapper, timing, metadata, and configuration before emission. *)
val elaborate_for_flow : ?inputs:Target.Inputs.t -> t -> Resolved_build.t Or_error.t
[@@@ocamlformat "enable"]
