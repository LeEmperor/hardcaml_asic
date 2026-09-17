open! Core

module Bank = struct
  type t =
    | Ui
    | Uo
    | Uio
  [@@deriving compare, equal, sexp_of]

  let to_string = function
    | Ui -> "ui"
    | Uo -> "uo"
    | Uio -> "uio"
  ;;
end

type entry =
  { bank : Bank.t
  ; bit : int
  ; description : string
  }
[@@deriving sexp_of]

type t = entry list [@@deriving sexp_of]

let validate_tiny_tapeout entries =
  let expected =
    List.concat_map [ Bank.Ui; Uo; Uio ] ~f:(fun bank ->
      List.init 8 ~f:(fun bit -> bank, bit))
  in
  let invalid =
    List.filter entries ~f:(fun { bit; description; _ } ->
      bit < 0 || bit > 7 || String.is_empty (String.strip description))
  in
  let duplicate =
    List.find_a_dup entries ~compare:(fun a b ->
      let c = Bank.compare a.bank b.bank in
      if c <> 0 then c else Int.compare a.bit b.bit)
  in
  let missing =
    List.filter expected ~f:(fun (bank, bit) ->
      not (List.exists entries ~f:(fun e -> Bank.equal e.bank bank && e.bit = bit)))
  in
  Or_error.combine_errors_unit
    [ (if List.is_empty invalid
       then Ok ()
       else
         Or_error.error_s [%message "invalid TT pin descriptions" (invalid : entry list)])
    ; (match duplicate with
       | None -> Ok ()
       | Some duplicate ->
         Or_error.error_s [%message "duplicate TT pin description" (duplicate : entry)])
    ; (if List.is_empty missing
       then Ok ()
       else
         Or_error.error_s
           [%message "missing TT pin descriptions" (missing : (Bank.t * int) list)])
    ]
;;
