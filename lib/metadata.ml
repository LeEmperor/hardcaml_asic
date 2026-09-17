(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "metadata.ml" *)
(* Source implementation of declared project metadata. Metadata is the project's answer to
   "what is this design called, and who made it?";

   Project.create takes it as [~metadata] and checks it through [validate]; Build carries
   it unchanged so harness specific outputs (for example the TT info.yaml) are rendered
   from this one declaration rather than maintained separately next to it;

   It does NOT render any harness output, that is the harness integration's job. TT
   pin meanings are declared separately in Project.pinout and validated with it.
*)

open! Core

[@@@ocamlformat "disable"]

(* The descriptive identity of a project;

   title       : human readable project name; the only field [validate] requires;
   author      : who to credit for the design;
   description : short free text summary of what the design does;

   The record is left transparent (there is no mli) so a project declaration can build it
   as a plain record literal -> see test/fixture.ml.
*)
type t =
  { title       : string
  ; author      : string
  ; description : string
  }
[@@deriving sexp_of]

(* Check the metadata is usable before the project is accepted; Project.create combines
   this with its other validators, so it returns Or_error rather than raising;

   A title that is empty or only whitespace -> error;
   author and description are NOT checked, empty strings are accepted for both;
*)
let validate t =
  if String.is_empty (String.strip t.title)
  then
    Or_error.error_s
      [%message "project metadata needs a title; give the project a nonblank title"]
  else Ok ()
;;

[@@@ocamlformat "enable"]
