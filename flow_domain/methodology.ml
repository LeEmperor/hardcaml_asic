open! Core
module Backend_recipe = struct
  type t = Librelane_classic_v1 [@@deriving equal, sexp_of]
  let to_string Librelane_classic_v1 = "librelane.classic.v1"
  let of_string = function
    | "librelane.classic.v1" -> Ok Librelane_classic_v1
    | s -> Or_error.errorf "Unsupported backend recipe %S; use librelane.classic.v1" s
end
type input = Fresh [@@deriving equal, sexp_of]
type t =
  { id : Selection.Id.t
  ; label : string
  ; description : string
  ; backend_recipe : Backend_recipe.t
  ; endpoints : Stage_id.t list
  ; configurable : Parameter.Key.t list
  ; defaults : Parameter.assignment list
  }
let create ~id ~label ~description ~backend_recipe ~endpoints ~configurable ~defaults =
  let open Or_error.Let_syntax in
  let%bind id = Selection.Id.create id in
  let%bind () =
    if String.is_empty (String.strip label)
    then Or_error.error_string "Methodology label must be nonblank"
    else Ok ()
  in
  let%bind () =
    if List.is_empty endpoints then Or_error.error_string "Methodology requires at least one endpoint"
    else if Option.is_some (List.find_a_dup endpoints ~compare:Stage_id.compare)
    then Or_error.error_string "Duplicate methodology endpoint; declare each endpoint once"
    else Ok ()
  in
  let endpoints = List.filter Stage_id.all ~f:(fun s -> List.mem endpoints s ~equal:Stage_id.equal) in
  let%bind configurable = Parameter.check_keys configurable in
  let%map defaults = Parameter.check_assignments ~configurable defaults in
  { id; label; description; backend_recipe; endpoints; configurable; defaults }
;;
let id t = t.id
let label t = t.label
let description t = t.description
let backend_recipe t = t.backend_recipe
let endpoints t = t.endpoints
let configurable t = t.configurable
let defaults t = t.defaults
let input _ = Fresh
let stages t ~endpoint =
  if not (List.mem t.endpoints endpoint ~equal:Stage_id.equal)
  then Or_error.errorf "Endpoint %s is not supported by flow %s" (Stage_id.to_string endpoint) (Selection.Id.to_string t.id)
  else Ok (List.take_while Stage_id.all ~f:(fun s -> Stage_id.compare s endpoint <= 0))
;;
