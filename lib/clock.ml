(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "clock.ml" *)
(* Source implementation of declared clocks. A clock is the project's answer to "which
   input is a clock, and how fast does it run?";

   Project.create takes the list through its optional [clocks] argument and checks it with
   [validate_list], alongside the other declaration checks; Build carries the list through
   unchanged so adapters can render it later.

   It does NOT look at the design; Resolved_build resolves [port] against the
   elaborated interface and converts [period] to nanoseconds and hertz.
*)

open! Core

[@@@ocamlformat "disable"]

(* One declared clock;

   port   : name of the top-level input the clock arrives on;
   period : one full clock cycle, as a floating span so fractional nanoseconds
            (including a 48 MHz period) remain representable;

   Careful: nothing checks [port] against the circuit yet. A clock declared on "clk" for a
   design whose input is "clock" validates fine and ends up in the build as is; that is
   caught by Resolved_build, before flow emission.
*)
type t =
  { port   : string
  ; period : Time_float.Span.t
  }
[@@deriving sexp_of]

(* Check a whole clock list at declaration time; returns Or_error rather than raising
   since Project.create folds it into one combined declaration error;

   invalid   : every clock with an empty port or a period that is not positive, reported
               together;
   duplicate : a port declared more than once; only the first repeat found is reported;

   Both checks run even when the other fails, so one call reports both problems.

   Blank ports and nonfinite periods fail here. A port that is not a real input is
   caught by Resolved_build.

   Duplicates compare [port] only; two clocks on the same port with different periods are
   still a duplicate, since one input cannot have two periods.
*)
let validate_list clocks =

  (* Who is invalid out of the clock defs? *)
  let invalid =
    List.filter clocks ~f:(fun { port; period } ->
      String.is_empty (String.strip port)
      || not (Float.is_finite (Time_float.Span.to_sec period))
      || Time_float.Span.( <= ) period Time_float.Span.zero)
  in

  (* Are there any dups? *)
  let duplicate =
    List.find_a_dup clocks ~compare:(fun a b -> String.compare a.port b.port)
  in

  (* Checking with the above in a list format, fold any errors into the result; *)
  Or_error.combine_errors_unit
    [ (match invalid with
       | [] -> Ok ()
       | _ :: _ ->
         Or_error.error_s
           [%message "clocks need a port name and a finite positive period" (invalid : t list)])

    ; (match duplicate with
       | None -> Ok ()
       | Some duplicate ->
         Or_error.error_s
           [%message
             "clock port declared more than once; give each clock a distinct port"
               (duplicate : t)])
    ]
;;

let period_of_frequency_hz frequency_hz =
  if not (Float.is_finite frequency_hz) || Float.(frequency_hz <= 0.)
  then Or_error.error_s [%message "clock frequency must be finite and positive" (frequency_hz : float)]
  else (
    let period_sec = 1. /. frequency_hz in
    if not (Float.is_finite period_sec) || Float.(period_sec <= 0.)
    then Or_error.error_s [%message "clock frequency has an unrepresentable period" (frequency_hz : float)]
    else Ok (Time_float.Span.of_sec period_sec))
;;
[@@@ocamlformat "enable"]
