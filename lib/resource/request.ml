(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "resource/request.ml" *)

open! Core

(* What a resource constructor asks for; a kind plus its contract;

   Careful: [contract] is compared structurally, so field order is part of the request.
   [%sexp { width : int; depth : int }] and [%sexp { depth : int; width : int }] describe
   the same memory but never match each other, and nothing raises for it; see
   Technology.exact_mapping;
*)
type t =
  { kind : string
  ; contract : Sexp.t
  }
[@@deriving compare, equal, sexp_of]

let create_exn ~kind ~contract =
  if not (Id.is_valid_component kind)
  then raise_s [%message "resource kind must be an identifier" (kind : string)];
  { kind; contract }
;;

(* Canonical portable 1RW request. Keep this below the resource constructors so
   both technology capabilities and hardware construction share field order
   without introducing a Technology/Context/Single_port_ram dependency cycle.
   Shape support is checked by Single_port_ram.Config, not rounded here. *)
let single_port_ram ~width ~depth ~read_latency =
  create_exn
    ~kind:"single_port_ram"
    ~contract:
      [%sexp
        { width = (width : int)
        ; depth = (depth : int)
        ; read_latency = (read_latency : int)
        ; port = ("1rw" : string)
        ; disabled_output = ("hold" : string)
        ; write_output = ("unspecified" : string)
        }]
;;
