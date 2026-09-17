(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "timing.ml" *)
(* Source implementation of declared I/O timing. Timing is the project's answer to "how
   late may a signal arrive at an input, or leave an output, relative to the clock?";

   Project.create takes it through its optional [timing] argument, defaulting to [empty],
   and does NOT check it; Build carries it through unchanged;
   Resolved_build.validate_timing checks every delay against the elaborated ports and
   converts it to nanoseconds, sorted by port; Bundle.sdc renders those into one
   "set_input_delay" or "set_output_delay" line each in constraints/top.sdc.

   Every delay carries both a minimum and a maximum on purpose. An SDC delay given only
   "-max" leaves the earliest arrival undefined, so OpenSTA reports no hold paths at all
   (hold slack 1e39) and the resizer never repairs hold; requiring [minimum] makes that
   silent gap impossible to declare;

   It does NOT own the clock; the one primary clock the delays are measured against is a
   Clock.t, declared separately. Only minimum and maximum I/O delays exist; false paths,
   clock uncertainty and any other SDC intent are not accepted by this declaration API
   (see docs/target-reference.md).
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
   and ends up in the build as is; all are caught by Resolved_build.validate_timing,
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

   The record is left transparent (there is no mli) so a project declaration can build it
   as a plain record literal -> see examples/tt_bundle_example.ml.

   Two lists rather than one list tagged with a direction on purpose: the direction is
   stated once by which field a delay sits in, and Resolved_build.validate_timing checks
   each list against the ports of that direction only, so a delay in the wrong list is
   reported as naming no such port.

   Duplicates are only checked within a list; the same port in both lists is still
   rejected, since it cannot be both an input and an output.
*)
type t =
  { input_delays  : Delay.t list
  ; output_delays : Delay.t list
  }
[@@deriving sexp_of]

(* No I/O delays at all; the default for Project.create, and what a project that only
   simulates or elaborates wants;

   Empty on purpose rather than some typical value: there are no reviewed board specific
   delays for the TT harness, so the SDC gets only the clock instead of fabricated delays;
*)
let empty = { input_delays = []; output_delays = [] }

[@@@ocamlformat "enable"]
