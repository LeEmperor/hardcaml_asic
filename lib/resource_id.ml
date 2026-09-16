(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "resource_id.ml" *)

open! Core

module T = struct
  type t =
    { path : string list
    ; name : string
    }
  [@@deriving equal]

  let components t = t.path @ [ t.name ]

  (* Lexicographic over the whole path, so an inventory reads as a sorted hierarchy. *)
  let compare a b = [%compare: string list] (components a) (components b)
  let to_string t = String.concat ~sep:"/" (components t)
  let sexp_of_t t = Sexp.Atom (to_string t)
end

include T
include Comparator.Make (T)

let is_valid_component s =
  (not (String.is_empty s))
  && (not (Char.is_digit s.[0]))
  && String.for_all s ~f:(fun c -> Char.is_alphanum c || Char.equal c '_')
;;

let create_exn ~path ~name =
  List.iter (path @ [ name ]) ~f:(fun component ->
    if not (is_valid_component component)
    then
      raise_s
        [%message
          "resource identity components must be identifiers"
            (component : string)
            (path : string list)
            (name : string)]);
  { path; name }
;;

let of_string_exn s =
  match List.rev (String.split s ~on:'/') with
  | name :: rev_path -> create_exn ~path:(List.rev rev_path) ~name
  | [] -> assert false
;;
