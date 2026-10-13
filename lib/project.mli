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
                              -> immutable Elaborated_project.t
   v}

   Elaboration never invokes an external tool. Each call is independent: a failed
   elaboration leaves nothing behind for the next one. [elaborate_for_flow]
   applies target, interface, constraint, and adapter validation to an
   implementation elaboration before flow emission.
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
  -> ?source_inputs:string list
  -> policy:Resource_policy.t
  -> unit
  -> t Or_error.t

(** Execution recipes are declared separately with [Flow.Recipe]. They do not
    alter [create]'s flow selection, bundle schema, or input-bundle identity.
    Emit a bundle here, then pass the recipe JSON to the provider [stages --plan]
    command; see [docs/guides/ocaml-stage-recipes.md]. *)

(* Of a type t, retrieve a string to be used as a name; *)
val name : t -> string

(** Declared source inventory, unchanged; defaults to []. Paths are relative to the
    source root supplied to [emit_bundle]. Creation does not read or validate files. *)
val source_inputs : t -> string list

(** Local declaration facts, including the packed Design.name, without constructing
    a circuit, resolving a flow, or reading files, Git or a PDK. This is not a
    Workbench driver or observation protocol. *)
val describe : t -> Sexp.t

(** Elaborate the design in the selected mode, retaining its intent and resources.
    Returns an elaborated Hardcaml circuit, not a synthesis result. *)
val elaborate : t -> mode:Elaboration_mode.t -> Elaborated_project.t Or_error.t

(** Elaborate the selected implementation and validate the TT/LibreLane target,
    wrapper, timing, metadata, and configuration before emission. *)
val elaborate_for_flow : ?inputs:Target.Inputs.t -> t -> Resolved_flow.t Or_error.t

(** Emit using [elaborate_for_flow ?inputs], optional Simulation elaboration,
    [Bundle.render], then [Bundle.write], returning the written bundle.
    An empty source inventory fails before invoking the design; it does not prevent
    ordinary elaboration. [include_simulation] defaults to true. When false, no
    Simulation construction occurs and Bundle uses synthesis sources for simulation.

    This explicit I/O boundary reads declared source files and Git during rendering.
    Nothing is written before rendering succeeds. Inherits Bundle.write's new/empty
    output directory requirement and non-atomic writes: a write failure can leave a
    partial directory. No external flow tools or PDK reads are performed. *)
val emit_bundle
  :  ?inputs:Target.Inputs.t
  -> ?include_simulation:bool
  -> t
  -> source_root:string
  -> output_dir:string
  -> Bundle.t Or_error.t

(** The same rendering sequence and optional arguments as [emit_bundle], followed
    by [Bundle.publish]. Returns the rendered bundle and its absolute publication
    location/reuse result. An empty inventory fails before design construction;
    render failure leaves no store output. The caller supplies the store location
    (typically [<results-root>/bundles]); no root is inferred by the library.
    Inherits Bundle.publish's exact reuse, backing layout and atomic visibility. *)
val emit_bundle_to_store
  :  ?inputs:Target.Inputs.t
  -> ?include_simulation:bool
  -> t
  -> source_root:string
  -> store_dir:string
  -> (Bundle.t * Bundle.Publication.t) Or_error.t
[@@@ocamlformat "enable"]
