open! Core

module Id = struct
  type t = string [@@deriving compare, equal, sexp_of]

  let create value =
    let letter c = Char.(c >= 'a' && c <= 'z') in
    match String.to_list value with
    | first :: rest
      when letter first
           && List.for_all rest ~f:(fun c ->
             letter c || Char.is_digit c || Char.equal c '_' || Char.equal c '-') ->
      Ok value
    | _ -> Or_error.errorf "Invalid flow/profile ID %S; use [a-z][a-z0-9_-]*" value
  ;;

  let to_string t = t
end

type t = { flow : Id.t option; profile : Id.t option }

let default = { flow = None; profile = None }
let flow t = t.flow
let profile t = t.profile

let create ?flow ?profile () =
  let open Or_error.Let_syntax in
  let%bind flow = Option.value_map flow ~default:(Ok None) ~f:(fun s -> Id.create s >>| Option.some) in
  let%bind profile = Option.value_map profile ~default:(Ok None) ~f:(fun s -> Id.create s >>| Option.some) in
  match flow, profile with
  | None, Some _ -> Or_error.error_string "Profile selection requires an explicit flow ID"
  | _ -> Ok { flow; profile }
;;
