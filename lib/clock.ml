(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "clock.ml" *)
(* A declared clock. Endpoint resolution against the elaborated interface and unit
   conversion for each output are P2 work.
*)

open! Core

type t =
  { port : string
  ; period : Time_ns.Span.t
  }
[@@deriving sexp_of]

let validate_list clocks =
  let invalid =
    List.filter clocks ~f:(fun { port; period } ->
      String.is_empty port || Time_ns.Span.( <= ) period Time_ns.Span.zero)
  in
  let duplicate =
    List.find_a_dup clocks ~compare:(fun a b -> String.compare a.port b.port)
  in
  Or_error.combine_errors_unit
    [ (match invalid with
       | [] -> Ok ()
       | _ :: _ ->
         Or_error.error_s
           [%message "clocks need a port name and a positive period" (invalid : t list)])
    ; (match duplicate with
       | None -> Ok ()
       | Some duplicate ->
         Or_error.error_s [%message "clock port declared more than once" (duplicate : t)])
    ]
;;
