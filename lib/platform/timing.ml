(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "platform/timing.ml" *)
(* Source implementation of declared I/O timing. Timing is the project's answer to "how
   late may a signal arrive at an input, or leave an output, relative to the clock?";

   Project.create takes it through its optional [timing] argument, defaulting to [empty],
   and does NOT check it; Elaborated_project carries it through unchanged;
   Elaboration.Resolved.validate_timing checks every delay against the elaborated ports
   and converts it to nanoseconds, sorted by port; Bundle.sdc renders those into one
   "set_input_delay" or "set_output_delay" line each in constraints/top.sdc.

   Every delay carries both a minimum and a maximum on purpose. An SDC delay given only
   "-max" leaves the earliest arrival undefined, so OpenSTA reports no hold paths at all
   (hold slack 1e39) and the resizer never repairs hold; requiring [minimum] makes that
   silent gap impossible to declare;

   It does NOT own the clock; the one primary clock the delays are measured against is a
   Clock.t, declared separately. PT.7 adds exact scalar synchronizer-stage declarations
   and reasoned data/reset exceptions, checked by Elaboration.Timing_intent. General
   false paths and arbitrary SDC remain unsupported.
*)

open! Core

[@@@ocamlformat "disable"]

(* One minimum and maximum delay on one top-level port;

   port    : name of the top-level port the delay applies to; an input for
             [input_delays], an output for [output_delays];
   minimum : the earliest the signal may change, measured from the "clk" edge; checked
             for hold. May be negative (an output feeding a receiver with a hold time is
             modelled as minus that hold time); floating span like [maximum];
   maximum : the latest the signal may settle, measured from the "clk" edge; checked for
             setup. A floating span so fractional nanoseconds remain representable;

   Careful: nothing here checks [port], [minimum] or [maximum]. A delay on "ui_in" placed
   in [output_delays], a negative [maximum], or a [minimum] above [maximum], builds fine
   and enters the elaborated project as is; all are caught by Elaboration.Resolved.validate_timing,
   before flow emission.
*)
module Delay = struct
  type t =
    { port    : string
    ; minimum : Time_float.Span.t
    ; maximum : Time_float.Span.t
    }
  [@@deriving sexp_of]
end

(* The timing declaration itself;

   input_delays  : input delays, in any order; each [port] must be a nonclock top-level
                   input;
   output_delays : output delays, in any order; each [port] must be a top-level output;

   The record remains transparent in the mli. Prefer [create] so future optional
   declaration fields do not require changes to project record literals.

   Two lists rather than one list tagged with a direction on purpose: the direction is
   stated once by which field a delay sits in, and Elaboration.Resolved.validate_timing
   checks each list against the ports of that direction only, so a delay in the wrong list
   is reported as naming no such port.

   Delay duplicates are only checked within a list; the same port in both lists is still
   rejected, since it cannot be both an input and an output.
*)
module Port = struct
  type direction = Input | Output [@@deriving sexp_of, equal]
  type t = { direction : direction; port : string; bit : int option }
  [@@deriving sexp_of, equal]
  let input port = { direction = Input; port; bit = None }
  let output port = { direction = Output; port; bit = None }
  let bit t bit =
    if Option.is_some t.bit then invalid_arg "timing port already has a bit selection";
    { t with bit = Some bit }
end

module Stage = struct
  type t = { id : string; chain : string; index : int } [@@deriving sexp_of, equal]
  let create ~id ~chain ~index = { id; chain; index }
  let anchor t = "hc_pt7_" ^ t.id
end

module Exception = struct
  type kind = Async_capture | Async_reset [@@deriving sexp_of, equal]
  type t =
    { id : string; reason : string; kind : kind; source : Port.t; targets : Stage.t list }
  [@@deriving sexp_of]
  let async_capture ~id ~reason ~source ~first_stage =
    { id; reason; kind = Async_capture; source; targets = [first_stage] }
  let async_reset ~id ~reason ~source ~targets =
    { id; reason; kind = Async_reset; source; targets }
  let kind_string = function Async_capture -> "async_capture" | Async_reset -> "async_reset"
end

type t =
  { input_delays  : Delay.t list
  ; output_delays : Delay.t list
  ; stages : Stage.t list [@sexp.omit_nil]
  ; exceptions : Exception.t list [@sexp.omit_nil]
  }
[@@deriving sexp_of]

(* No I/O delays at all; the default for Project.create, and what a project that only
   simulates or elaborates wants;

   Empty on purpose rather than some typical value: there are no reviewed board specific
   delays for the TT harness, so the SDC gets only the clock instead of fabricated delays;
*)
let create ?(input_delays = []) ?(output_delays = []) ?(stages = [])
    ?(exceptions = []) () = { input_delays; output_delays; stages; exceptions }
let empty = create ()

[@@@ocamlformat "enable"]
