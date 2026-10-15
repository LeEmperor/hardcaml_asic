open! Core
type t =
  { id : Selection.Id.t
  ; label : string
  ; description : string
  ; assignments : Parameter.assignment list
  }
let create ~id ~label ~description ~assignments =
  let open Or_error.Let_syntax in
  let%bind id = Selection.Id.create id in
  let%bind () =
    if String.is_empty (String.strip label)
    then Or_error.error_string "Profile label must be nonblank"
    else Ok ()
  in
  let%map assignments = Parameter.check_assignments ~configurable:Parameter.Key.all assignments in
  { id; label; description; assignments }
;;
let id t = t.id
let label t = t.label
let description t = t.description
let assignments t = t.assignments
