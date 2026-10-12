(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "resolved_flow.mli" *)
(* Validated TT/LibreLane resolution results for Bundle and design observers.

   Only [resolve], also called by Project.elaborate_for_flow, constructs a result.
   Private records preserve field reads and pattern matching but forbid construction
   and record updates. There is no unchecked constructor or deserializer.

   Resolution checks the target first, then combines wrapper port, submission metadata,
   pinout and implementation capability diagnostics in one stage. Timing is checked
   next, followed by settings and protected overrides. It relies on Elaborated_project's
   declaration/elaboration invariants; it does not freeze Hardcaml circuit internals
   or verify external target files. Bundle owns emission.
*)

open! Core

(** A resolved configuration assignment and its provenance. JSON values use immutable
    lists and strings; inspecting a value cannot mutate the stored setting. *)
module Setting : sig
  module Owner : sig
    type t =
      | Design (** Elaborated design fact. *)
      | Target (** Resolved target fact. *)
      | Clock (** Resolved primary clock fact. *)
      | Default (** Adapter default, replaceable by an override. *)
      | Override of string (** Explicit override, carrying its declared reason. *)
    [@@deriving sexp_of]
  end

  type t = private
    { key : string (** LibreLane variable name. *)
    ; value : Yojson.Safe.t (** Value emitted in the configuration. *)
    ; owner : Owner.t (** Source recorded in the manifest. *)
    }
  [@@deriving sexp_of]
end

(** A checked delay, converted to nanoseconds. *)
module Delay_ns : sig
  type t = private
    { port : string (** Existing nonclock port in the declared direction. *)
    ; minimum : float (** Finite earliest change, no greater than [maximum]. *)
    ; maximum : float (** Finite, nonnegative latest settle. *)
    }
  [@@deriving sexp_of]
end

(** Read-only resolution facts. Subordinate target and clock records can be copied,
    but copies cannot be inserted into this private record. *)
type t = private
  { elaborated_project : Elaborated_project.t
    (** Implementation elaboration supplied to resolution, retained unchanged. *)
  ; target : Target.Resolved.t (** Checked, pinned target references. *)
  ; clock : Clock.t (** The sole primary clock, on [clk]. *)
  ; clock_period_ns : float (** Clock period converted to nanoseconds. *)
  ; clock_hz : float (** [1e9 /. clock_period_ns]. *)
  ; input_delays_ns : Delay_ns.t list (** Input delays sorted by port. *)
  ; output_delays_ns : Delay_ns.t list (** Output delays sorted by port. *)
  ; settings : Setting.t list (** Merged assignments sorted by unique key. *)
  }

(** Resolve an implementation elaboration; defaults to {!Target.Inputs.reference_cmos5l_6x4}.
    Returns an error on unsupported targets, missing capabilities, invalid wrapper,
    metadata, pinout or timing, or overrides of protected facts. No files are read.
    A failure stops subsequent validation stages; no partial result is returned. *)
val resolve : ?inputs:Target.Inputs.t -> Elaborated_project.t -> t Or_error.t

(** Required TT input names and widths, including phantom inputs. *)
val expected_inputs : (string * int) list

(** Required TT output names and widths. *)
val expected_outputs : (string * int) list

(** Whether a LibreLane key is reserved for generated facts, including any SDC key. *)
val protected_key : string -> bool

(** Check implementation mode, required technology views and resource source support.
    Useful for capability diagnostics; success does not construct a resolved flow. *)
val validate_capabilities : Elaborated_project.t -> Target.Resolved.t -> unit Or_error.t
