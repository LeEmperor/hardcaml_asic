(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "flow.ml" *)
(* Flow adapter selection, requested operation and adapter-specific settings.

   LibreLane overrides are a LibreLane representation, not the core project model.
   Resolved_build checks protected-key conflicts and resolves defaults. Declaration
   validation here rejects malformed keys, non-JSON values, and missing reasons. *)

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
    let valid_key key =
      let letter c = Char.(c >= 'A' && c <= 'Z') in
      let digit c = Char.(c >= '0' && c <= '9') in
      match String.to_list key with
      | [] -> false
      | first :: rest ->
        (letter first || Char.equal first '_')
        && List.for_all rest ~f:(fun c -> letter c || digit c || Char.equal c '_')
    in
    let rec strict_json : Yojson.Safe.t -> bool = function
      | `Null | `Bool _ | `Int _ | `String _ -> true
      | `Float value -> Float.is_finite value
      | `List values -> List.for_all values ~f:strict_json
      | `Assoc fields ->
        Option.is_none
          (List.find_a_dup fields ~compare:(fun (a, _) (b, _) -> String.compare a b))
        && List.for_all fields ~f:(fun (_, value) -> strict_json value)
      | `Intlit _ | `Tuple _ | `Variant _ -> false
    in
    let invalid =
      List.filter overrides ~f:(fun (o : Override.t) ->
        not (valid_key o.key) || blank o.reason || not (strict_json o.value))
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
               "LibreLane overrides need an uppercase key, strict JSON value, and nonempty reason"
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
