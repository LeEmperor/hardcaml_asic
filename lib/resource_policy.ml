(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "resource_policy.ml" *)

open! Core

module Requirement = struct
  type t =
    | Flops
    | Exact
    | Exact_or_flop_fallback
  [@@deriving compare, equal, sexp_of]
end

module Selector = struct
  type t =
    | Instance of Resource_id.t
    | Subtree of string list
  [@@deriving compare, equal, sexp_of]

  let instance_exn s = Instance (Resource_id.of_string_exn s)

  let subtree_exn s =
    let path = String.split s ~on:'/' in
    if not (List.for_all path ~f:Resource_id.is_valid_component)
    then
      raise_s
        [%message
          "subtree selector must be a nonempty '/'-separated scope path" ~selector:s];
    Subtree path
  ;;

  let matches t (id : Resource_id.t) =
    match t with
    | Instance selected -> Resource_id.equal selected id
    | Subtree prefix -> List.is_prefix id.path ~prefix ~equal:String.equal
  ;;

  let precedence = function
    | Instance _ -> 2, 0
    | Subtree prefix -> 1, List.length prefix
  ;;
end

module Rule = struct
  type t =
    { selector : Selector.t
    ; requirement : Requirement.t
    }
  [@@deriving sexp_of]
end

module Applied = struct
  type t =
    | Default
    | Rule of Selector.t
  [@@deriving compare, equal, sexp_of]
end

type t =
  { default : Requirement.t option
  ; rules : Rule.t list
  }
[@@deriving sexp_of]

let create ?default rules =
  match
    List.find_a_dup rules ~compare:(fun (a : Rule.t) b ->
      Selector.compare a.selector b.selector)
  with
  | Some { selector; _ } ->
    Or_error.error_s
      [%message
        "ambiguous implementation policy: selector appears in more than one rule"
          (selector : Selector.t)]
  | None -> Ok { default; rules }
;;

let rules t = t.rules

let lookup t id =
  (* Equal precedence implies an identical selector, which [create] rejects, so the
     maximum is unique. *)
  let matching = List.filter t.rules ~f:(fun rule -> Selector.matches rule.selector id) in
  match
    List.max_elt matching ~compare:(fun (a : Rule.t) b ->
      [%compare: int * int]
        (Selector.precedence a.selector)
        (Selector.precedence b.selector))
  with
  | Some { selector; requirement } -> Ok (requirement, Applied.Rule selector)
  | None ->
    (match t.default with
     | Some requirement -> Ok (requirement, Applied.Default)
     | None ->
       Or_error.error_s
         [%message
           "no implementation policy applies; add a default or a rule selecting this \
            instance"
             ~instance:(id : Resource_id.t)])
;;
