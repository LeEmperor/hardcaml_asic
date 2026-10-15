open! Core

module Key = struct
  type t = Synth_strategy | Synth_abc_buffering [@@deriving compare, equal, sexp_of]
  let all = [ Synth_abc_buffering; Synth_strategy ]
  let to_string = function Synth_strategy -> "SYNTH_STRATEGY" | Synth_abc_buffering -> "SYNTH_ABC_BUFFERING"
  let of_string s =
    match List.find all ~f:(fun k -> String.equal s (to_string k)) with
    | Some k -> Ok k
    | None -> Or_error.errorf "Unsupported parameter %S; use SYNTH_STRATEGY or SYNTH_ABC_BUFFERING" s
end

module Strategy = struct
  type t = Area_0 | Area_1 | Area_2 | Area_3 | Delay_0 | Delay_1 | Delay_2 | Delay_3 | Delay_4
  [@@deriving compare, equal, sexp_of]
  let all = [ Area_0; Area_1; Area_2; Area_3; Delay_0; Delay_1; Delay_2; Delay_3; Delay_4 ]
  let to_string = function
    | Area_0 -> "AREA 0" | Area_1 -> "AREA 1" | Area_2 -> "AREA 2" | Area_3 -> "AREA 3"
    | Delay_0 -> "DELAY 0" | Delay_1 -> "DELAY 1" | Delay_2 -> "DELAY 2"
    | Delay_3 -> "DELAY 3" | Delay_4 -> "DELAY 4"
  let of_string s =
    match List.find all ~f:(fun v -> String.equal s (to_string v)) with
    | Some v -> Ok v
    | None -> Or_error.errorf "Invalid SYNTH_STRATEGY %S; use AREA 0..3 or DELAY 0..4 (with one space)" s
end

type value = Strategy of Strategy.t | Bool of bool [@@deriving equal, sexp_of]
type value_type = Enum | Boolean [@@deriving equal, sexp_of]
type descriptor =
  { key : Key.t
  ; value_type : value_type
  ; allowed_values : value list
  ; backend_default : value
  ; meaning : string
  }

let descriptors =
  [ { key = Synth_abc_buffering; value_type = Boolean
    ; allowed_values = [ Bool false; Bool true ]; backend_default = Bool false
    ; meaning = "Enable ABC cell buffering during synthesis technology mapping" }
  ; { key = Synth_strategy; value_type = Enum
    ; allowed_values = List.map Strategy.all ~f:(fun v -> Strategy v)
    ; backend_default = Strategy Area_0
    ; meaning = "ABC logic synthesis and technology mapping strategy; area or delay oriented" }
  ]
;;
let key t = t.key
let value_type t = t.value_type
let allowed_values t = t.allowed_values
let backend_default t = t.backend_default
let units _ = None
let meaning t = t.meaning
let backend_consumer _ = "LibreLane 3.1.0.dev3 / Yosys.Synthesis / scripts/pyosys/construct_abc_script.py"
let descriptor k = List.find_exn descriptors ~f:(fun d -> Key.equal d.key k)

type assignment = { key : Key.t; value : value } [@@deriving equal, sexp_of]
let synth_strategy v = { key = Synth_strategy; value = Strategy v }
let synth_abc_buffering v = { key = Synth_abc_buffering; value = Bool v }
let assignment_key t = t.key
let assignment_value t = t.value

let of_string_value ~key value =
  let open Or_error.Let_syntax in
  let%bind key = Key.of_string key in
  match key with
  | Synth_strategy -> Strategy.of_string value >>| synth_strategy
  | Synth_abc_buffering -> Or_error.error_string "SYNTH_ABC_BUFFERING requires a boolean scalar, not a string"
;;
let of_bool_value ~key value =
  let open Or_error.Let_syntax in
  let%bind key = Key.of_string key in
  match key with
  | Synth_abc_buffering -> Ok (synth_abc_buffering value)
  | Synth_strategy -> Or_error.error_string "SYNTH_STRATEGY requires an enum string, not a boolean"
;;

let of_scalar ~key = function
  | `String value -> of_string_value ~key value
  | `Bool value -> of_bool_value ~key value
  | `Int _ | `Float _ | `Null ->
    let open Or_error.Let_syntax in
    let%bind _ = Key.of_string key in
    Or_error.errorf "Parameter %s does not accept numeric or null scalars; use its exact declared type" key
;;

let compare_key a b = String.compare (Key.to_string a) (Key.to_string b)
let check_keys keys =
  match List.find_a_dup keys ~compare:compare_key with
  | Some k -> Or_error.errorf "Duplicate configurable parameter %s; declare each key once" (Key.to_string k)
  | None -> Ok (List.sort keys ~compare:compare_key)
;;
let check_assignments ~configurable assignments =
  let open Or_error.Let_syntax in
  let%bind _ = check_keys configurable in
  let%bind _ = check_keys (List.map assignments ~f:assignment_key) in
  match List.find assignments ~f:(fun a -> not (List.mem configurable a.key ~equal:Key.equal)) with
  | Some a -> Or_error.errorf "Parameter %s is not configurable in this methodology" (Key.to_string a.key)
  | None -> Ok (List.sort assignments ~compare:(fun a b -> compare_key a.key b.key))
;;

type origin = Methodology | Profile | Request [@@deriving equal, sexp_of]
type contribution = { assignment : assignment; origin : origin }
type resolved = { winning : contribution; overridden : contribution list }
let assignment t = t.assignment
let origin t = t.origin
let winning t = t.winning
let overridden t = t.overridden

let resolve ~configurable ~methodology ~profile ~request =
  let open Or_error.Let_syntax in
  let%bind methodology = check_assignments ~configurable methodology |> Or_error.tag ~tag:"Methodology defaults" in
  let%bind profile = check_assignments ~configurable profile |> Or_error.tag ~tag:"Profile assignments" in
  let%bind request = check_assignments ~configurable request |> Or_error.tag ~tag:"Request assignments" in
  let contributions =
    List.concat_map [ Methodology, methodology; Profile, profile; Request, request ]
      ~f:(fun (origin, values) -> List.map values ~f:(fun assignment -> { assignment; origin }))
  in
  Ok (List.filter_map Key.all ~f:(fun key ->
    let values = List.filter contributions ~f:(fun c -> Key.equal key c.assignment.key) in
    match List.rev values with
    | [] -> None
    | winning :: rest -> Some { winning; overridden = List.rev rest }))
;;
