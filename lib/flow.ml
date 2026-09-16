(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "flow.ml" *)
(* Flow adapter selection, requested operation and adapter-specific settings.

   LibreLane overrides are a LibreLane representation, not the core project model.
   Protected-key conflicts and default resolution are P2 work; declaration validation here
   only rejects overrides that cannot be meaningful. *)

open! Core

module Operation = struct
  type t =
    | Synthesis
    | Hardening
  [@@deriving compare, equal, sexp_of]
end

module Librelane = struct
  module Override = struct
    type t =
      { key : string
      ; value : Yojson.Safe.t
      ; reason : string
      }

    let sexp_of_t { key; value; reason } =
      [%sexp
        { key : string; value = (Yojson.Safe.to_string value : string); reason : string }]
    ;;
  end

  type t = { overrides : Override.t list } [@@deriving sexp_of]

  let validate { overrides } =
    let blank s = String.is_empty (String.strip s) in
    let invalid =
      List.filter overrides ~f:(fun (o : Override.t) -> blank o.key || blank o.reason)
    in
    let duplicate =
      List.find_a_dup overrides ~compare:(fun (a : Override.t) b ->
        String.compare a.key b.key)
    in
    Or_error.combine_errors_unit
      [ (match invalid with
         | [] -> Ok ()
         | _ :: _ ->
           Or_error.error_s
             [%message
               "LibreLane overrides need a key and a nonempty reason"
                 (invalid : Override.t list)])
      ; (match duplicate with
         | None -> Ok ()
         | Some duplicate ->
           Or_error.error_s
             [%message
               "LibreLane override key set more than once" (duplicate : Override.t)])
      ]
  ;;
end

module Adapter = struct
  type t = Librelane of Librelane.t [@@deriving sexp_of]
end

type t =
  { adapter : Adapter.t
  ; operation : Operation.t
  }
[@@deriving sexp_of]

let librelane ?(overrides = []) operation =
  { adapter = Librelane { overrides }; operation }
;;

let validate t =
  match t.adapter with
  | Librelane settings -> Librelane.validate settings
;;
