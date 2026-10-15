open! Core

type t =
  { stages : Stage.t list
  ; initial_boundary : Stage.t option
  }
[@@deriving sexp_of]

let stages t = t.stages
let initial_boundary t = t.initial_boundary
let endpoint t = List.last_exn t.stages

let remaining = function
  | None -> Stage.all
  | Some source ->
    List.drop_while Stage.all ~f:(fun stage ->
      Stage.compare stage source <= 0)
;;

let create ?initial_boundary stages =
  let expected = List.take (remaining initial_boundary) (List.length stages) in
  if List.is_empty stages || not (List.equal Stage.equal stages expected)
  then Or_error.error_s
    [%message "Flow recipe must be nonempty and contiguous after its source; include every required stage"
      (initial_boundary : Stage.t option) (stages : Stage.t list)
      (expected : Stage.t list)]
  else Ok { stages; initial_boundary }
;;

let through ?initial_boundary endpoint =
  let stages = List.take_while (remaining initial_boundary) ~f:(fun stage ->
    Stage.compare stage endpoint <= 0) in
  create ?initial_boundary stages
;;

let compose first second =
  if Option.equal Stage.equal second.initial_boundary (Some (endpoint first))
  then create ?initial_boundary:first.initial_boundary (first.stages @ second.stages)
  else Or_error.error_string
    "Flow recipe composition source mismatch; the second source must be the first endpoint"
;;

module Input = struct
  type t = Bundle | Checkpoint of Stage.t [@@deriving equal, sexp_of]
end

type declaration =
  { stage : Stage.t
  ; input : Input.t
  ; output_checkpoint : Stage.t
  }
[@@deriving sexp_of]

let required_input t =
  match t.initial_boundary with None -> Input.Bundle | Some source -> Checkpoint source
;;

let declarations t =
  let _, declarations = List.fold_map t.stages ~init:(required_input t)
    ~f:(fun input stage ->
      Input.Checkpoint stage, { stage; input; output_checkpoint = stage }) in
  declarations
;;

let to_yojson t =
  `Assoc
    [ "schema_version", `Int 3
    ; "stages", `List (List.map t.stages ~f:(fun stage -> `String (Stage.to_string stage)))
    ; "initial_boundary", Option.value_map t.initial_boundary ~default:`Null
        ~f:(fun stage -> `String (Stage.to_string stage))
    ]
;;

let to_string t = Yojson.Safe.to_string (to_yojson t)
