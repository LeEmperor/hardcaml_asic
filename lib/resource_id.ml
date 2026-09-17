(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "resource_id.ml" *)
(* Source implementation of resource identities. An identity is the answer to "which
   resource instance is this?";

   Elaboration_context.register_open_exn flattens the Hardcaml scope path and builds one
   through [create_exn]; Resource_policy.Selector.instance_exn parses one out of a policy
   string through [of_string_exn]. Elaboration_context keys its records map by it through
   the comparator, and Build.Private.create sorts the final inventory with [compare];

   [is_valid_component] is shared on purpose: Resource_policy.Selector.subtree_exn,
   Resource_request and Project use it too, so every name in the system follows one
   syntax;

   It does NOT know whether an identity is unique, that is Elaboration_context's job; it
   does NOT depend on Hardcaml either, the caller hands it a plain outermost-first path.
*)

open! Core

[@@@ocamlformat "disable"]

(* Everything that Comparator.Make needs, kept in its own module so the comparator can be
   built before the rest of the file includes it;
*)
module T = struct
  (* The identity itself;

     path : scope labels from the top, outermost first; empty means the top scope;
     name : the resource's own name, as passed to registration;
  *)
  type t =
    { path : string list
    ; name : string
    }
  [@@deriving equal]

  (* The identity flattened to one list, name last;

     Two identities with the same components are the same identity, since [name] is always
     the last element; that is what keeps [compare] consistent with the derived [equal];
  *)
  let components t = t.path @ [ t.name ]

  (* Lexicographic over the whole path, so an inventory reads as a sorted hierarchy;

     A consequence: every subtree is contiguous in sorted order, since identities sharing
     a path prefix share a components prefix. "core/left/buf" sorts next to
     "core/left/mem" and before "core/right/buf";
  *)
  let compare a b = [%compare: string list] (components a) (components b)

  (* "core/left/buf"; the inverse of [of_string_exn], which holds because a valid
     component can never contain '/';
  *)
  let to_string t = String.concat ~sep:"/" (components t)

  (* A single atom rather than a record, so identities in errors and expect tests read the
     same way they are written in policy selectors;
  *)
  let sexp_of_t t = Sexp.Atom (to_string t)
end

include T
include Comparator.Make (T)

(* Identifier syntax; nonempty, only [A-Za-z0-9_], and not starting with a digit;

   Why: a component can then never be empty or contain the '/' separator, which is what
   makes [to_string] and [of_string_exn] exact inverses, and "a//b" or "a/" can never be
   mistaken for a real identity;
*)
let is_valid_component s =
  (not (String.is_empty s))
  && (not (Char.is_digit s.[0]))
  && String.for_all s ~f:(fun c -> Char.is_alphanum c || Char.equal c '_')
;;

(* Build an identity, checking every component of [path] and [name]; raises rather than
   returning Or_error since register_open_exn runs inside a design constructor, and design
   constructors should not have to thread Or_error through every hierarchy level;

   Careful: [path] comes from Hardcaml instance labels, not from the resource constructor.
   A hierarchical instance labelled something that is not an identifier makes every
   resource below it fail here even though each resource's own [name] is fine; the error's
   [component] field points at the offending label, so it is not silent;
*)
let create_exn
    ~path (* outermost first; *)
    ~name
  =
  List.iter (path @ [ name ]) ~f:(fun component ->
    if not (is_valid_component component)
    then
      raise_s
        [%message
          "resource identity components must be identifiers; use only [A-Za-z0-9_], not \
           starting with a digit"
            (component : string)
            (path : string list)
            (name : string)]);
  { path; name }
;;

(* "core/left/buf" -> { path = ["core"; "left"]; name = "buf" };

   1. split on '/';
   2. reverse, so the last piece (the name) is at the head;
   3. validate through [create_exn]; an empty piece from "a//b", "a/", "/a" or "" raises;
*)
let of_string_exn s =
  match List.rev (String.split s ~on:'/') with
  | name :: rev_path -> create_exn ~path:(List.rev rev_path) ~name
  | [] -> assert false (* can never happen; String.split returns at least one piece; *)
;;
[@@@ocamlformat "enable"]
