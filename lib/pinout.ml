(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "pinout.ml" *)
(* Source implementation of declared pin meanings. A pinout is the project's answer to
   "what does each Tiny Tapeout pin do?";

   Project.create takes it through its optional [pinout] argument, defaulting to the empty
   list, and does NOT check it; Build carries it through unchanged; Resolved_build.resolve
   checks it with [validate_tiny_tapeout] alongside the other TT checks, and
   Bundle.info_yaml renders it into the pinout section of the TT info.yaml.

   Checking at resolution rather than declaration is on purpose: a pinout only means
   something for a TT flow, so a project that only simulates or elaborates can leave it
   empty without failing Project.create.

   It does NOT look at the design; which ports exist, and their widths and directions, is
   Resolved_build's job. A pin entry is only a description for the TT submission.
*)

open! Core

[@@@ocamlformat "disable"]

(* The three Tiny Tapeout pin banks, each 8 bits wide;

   Ui  : dedicated inputs, ui_in on the TT wrapper;
   Uo  : dedicated outputs, uo_out on the TT wrapper;
   Uio : bidirectional pins, uio_in / uio_out / uio_oe on the TT wrapper;

   Careful: the derived [compare] orders banks by constructor ORDER (Ui, Uo, Uio), the
   same order info.yaml lists them in, but Bundle.info_yaml does NOT use it; it keeps
   its own [bank_order] match. A new bank added here fails to compile there until
   someone places it, but reordering the constructors here leaves the yaml order as is.
*)
module Bank = struct
  type t =
    | Ui
    | Uo
    | Uio
  [@@deriving compare, equal, sexp_of]

  (* The bank's name as info.yaml spells it; "ui", "uo", "uio"; *)
  let to_string = function
    | Ui -> "ui"
    | Uo -> "uo"
    | Uio -> "uio"
  ;;
end

(* One described pin;

   bank        : which of the three banks the pin is in;
   bit         : index within the bank, 0 to 7; NOT checked until [validate_tiny_tapeout];
   description : free text shown for the pin in info.yaml; must not be blank;

   The record is left transparent (there is no mli) so a project declaration can build
   the 24 entries as plain record literals -> see examples/tt_bundle_example.ml.
*)
type entry =
  { bank        : Bank.t
  ; bit         : int
  ; description : string
  }
[@@deriving sexp_of]

(* The pinout itself; a plain list of entries, in any order;

   A list rather than a map keyed by (bank, bit) on purpose: declarations stay plain list
   literals, and duplicates are reported by [validate_tiny_tapeout] instead of one entry
   silently replacing another.
*)
type t = entry list [@@deriving sexp_of]

(* Check a pinout is complete for a Tiny Tapeout submission; returns Or_error rather than
   raising since Resolved_build.resolve folds it into one combined TT error;

   invalid   : every entry with a bit outside 0 to 7 or a blank description, reported
               together;
   duplicate : a (bank, bit) described more than once; only the first repeat found is
               reported;
   missing   : every one of the 24 (bank, bit) pairs with no entry, reported together;

   All three checks run even when another fails, so one call reports every problem.

   Duplicates compare [bank] and [bit] only; two entries for the same pin with different
   descriptions are still a duplicate, since info.yaml has one line per pin.

   An out of range entry is reported as invalid only; it does not count toward any
   expected pin, so the pin it was probably meant for shows up as missing as well.

   -> see expect tests (test/test_resolved_build.ml)
*)
let validate_tiny_tapeout entries =

  (* Every (bank, bit) pair a TT submission has to describe; 3 banks x 8 bits; *)
  let expected =
    List.concat_map [ Bank.Ui; Uo; Uio ] ~f:(fun bank ->
      List.init 8 ~f:(fun bit -> bank, bit))
  in

  (* Who is invalid out of the entries? *)
  let invalid =
    List.filter entries ~f:(fun { bit; description; _ } ->
      bit < 0 || bit > 7 || String.is_empty (String.strip description))
  in

  (* Are there any dups on (bank, bit)? *)
  let duplicate =
    List.find_a_dup entries ~compare:(fun a b ->
      let c = Bank.compare a.bank b.bank in
      if c <> 0 then c else Int.compare a.bit b.bit)
  in

  (* Which expected pins have no entry at all? *)
  let missing =
    List.filter expected ~f:(fun (bank, bit) ->
      not (List.exists entries ~f:(fun e -> Bank.equal e.bank bank && e.bit = bit)))
  in

  (* Checking with the above in a list format, fold any errors into the result; *)
  Or_error.combine_errors_unit
    [ (if List.is_empty invalid
       then Ok ()
       else
         Or_error.error_s
           [%message
             "invalid TT pin descriptions; use bits 0 to 7 and a nonblank description"
               (invalid : entry list)])

    ; (match duplicate with
       | None -> Ok ()
       | Some duplicate ->
         Or_error.error_s
           [%message
             "duplicate TT pin description; describe each bank bit once"
               (duplicate : entry)])

    ; (if List.is_empty missing
       then Ok ()
       else
         Or_error.error_s
           [%message
             "missing TT pin descriptions; describe all 8 bits of ui, uo and uio"
               (missing : (Bank.t * int) list)])
    ]
;;

[@@@ocamlformat "enable"]
