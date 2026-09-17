(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "clock.ml" *)
(* Source implementation of declared clocks. A clock is the project's answer to "which
   input is a clock, and how fast does it run?";

   Project.create takes the list through its optional [clocks] argument and checks it with
   [validate_list], alongside the other declaration checks; Build carries the list through
   unchanged so adapters can render it later.

   It does NOT look at the design; [port] is only a name, and resolving it against the
   elaborated interface is P2 work, as is converting [period] into the units each output
   (SDC, LibreLane, TT metadata) wants.
*)

open! Core

[@@@ocamlformat "disable"]

(* One declared clock;

   port   : name of the top-level input the clock arrives on;
   period : one full clock cycle, as a span so the unit is never ambiguous;

   Careful: nothing checks [port] against the circuit yet. A clock declared on "clk" for a
   design whose input is "clock" validates fine and ends up in the build as is; that is
   not caught until endpoint resolution lands in P2.
*)
type t =
  { port   : string
  ; period : Time_ns.Span.t
  }
[@@deriving sexp_of]

(* Check a whole clock list at declaration time; returns Or_error rather than raising
   since Project.create folds it into one combined declaration error;

   invalid   : every clock with an empty port or a period that is not positive, reported
               together;
   duplicate : a port declared more than once; only the first repeat found is reported;

   Both checks run even when the other fails, so one call reports both problems.

   Careful: an empty port is checked with String.is_empty, NOT after stripping, so a port
   of " " passes here (Metadata.validate strips its title). A port that is not a real
   input is only caught once ports resolve in P2.

   Duplicates compare [port] only; two clocks on the same port with different periods are
   still a duplicate, since one input cannot have two periods.
*)
let validate_list clocks =

  (* Who is invalid out of the clock defs? *)
  let invalid =
    List.filter clocks ~f:(fun { port; period } ->
      String.is_empty port || Time_ns.Span.( <= ) period Time_ns.Span.zero)
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
           [%message "clocks need a port name and a positive period" (invalid : t list)])

    ; (match duplicate with
       | None -> Ok ()
       | Some duplicate ->
         Or_error.error_s
           [%message
             "clock port declared more than once; give each clock a distinct port"
               (duplicate : t)])
    ]
;;
[@@@ocamlformat "enable"]
