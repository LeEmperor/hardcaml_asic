open! Core
module J = Flow.Plan_json

let contract = "hardcaml-asic.hardware-variant"
let limit = 1_000_000_000
let max_bytes = 128 * 1024
let identifier s =
  let lower c = Char.(c >= 'a' && c <= 'z') in
  if String.is_empty s || String.length s > 128
     || not (lower s.[0])
     || not (String.for_all s ~f:(fun c ->
       lower c || Char.is_digit c || Char.equal c '_' || Char.equal c '.' || Char.equal c '-'))
  then J.fail "invalid hardware parameter identifier"
;;

let unique xs ~compare =
  if Option.is_some (List.find_a_dup xs ~compare) then J.fail "duplicate hardware declaration key/value"
;;
let bounded xs =
  if List.is_empty xs || List.length xs > 64 then J.fail "hardware declaration requires 1..64 entries"
;;

module Value = struct
  type t = Int of int | Bool of bool | Enum of string
end

module Parameter = struct
  type kind = Integer of { minimum : int; maximum : int }
            | Boolean | Enumeration of string list
  type t = { key : string; kind : kind }
  let create ~key ~kind = J.decode (fun () ->
    identifier key;
    let kind = match kind with
      | Integer {minimum; maximum} ->
        if minimum < -limit || maximum > limit || minimum > maximum then
          J.fail "invalid hardware integer bounds";
        kind
      | Boolean -> kind
      | Enumeration values ->
        bounded values;
        List.iter values ~f:identifier;
        unique values ~compare:String.compare;
        Enumeration (List.sort values ~compare:String.compare)
    in
    {key; kind})
  let key t = t.key
  let kind t = t.kind
end

module Schema = struct
  type t = { design_id : string; schema_id : string; parameters : Parameter.t list }
  let create ~design_id ~schema_id ~parameters = J.decode (fun () ->
    identifier design_id; identifier schema_id; bounded parameters;
    unique parameters ~compare:(fun a b -> String.compare (Parameter.key a) (Parameter.key b));
    { design_id; schema_id;
      parameters = List.sort parameters ~compare:(fun a b -> String.compare (Parameter.key a) (Parameter.key b)) })
  let design_id t = t.design_id
  let schema_id t = t.schema_id
  let parameters t = t.parameters
end

type t = { schema : Schema.t; assignments : (string * Value.t) list; identity : string }
let schema t = t.schema
let assignments t = t.assignments
let identity t = t.identity
let value_json = function
  | Value.Int n -> `Int n | Bool b -> `Bool b | Enum s -> `String s
let parameter_json p =
  let fields = match Parameter.kind p with
    | Integer {minimum; maximum} -> ["type", `String "integer"; "minimum", `Int minimum; "maximum", `Int maximum]
    | Boolean -> ["type", `String "boolean"]
    | Enumeration values -> ["type", `String "enum"; "values", `List (List.map values ~f:(fun s -> `String s))]
  in `Assoc (("key", `String (Parameter.key p)) :: fields)
let payload schema assignments = `Assoc
  [ "contract", `String contract; "schema_version", `Int 1
  ; "design_id", `String (Schema.design_id schema); "schema_id", `String (Schema.schema_id schema)
  ; "parameters", `List (List.map (Schema.parameters schema) ~f:parameter_json)
  ; "assignments", `Assoc (List.map assignments ~f:(fun (k,v) -> k, value_json v)) ]
let create ~schema ~assignments = J.decode (fun () ->
  if List.length assignments > 64 then J.fail "too many hardware assignments";
  unique assignments ~compare:(fun (a,_) (b,_) -> String.compare a b);
  let assignments = List.sort assignments ~compare:(fun (a,_) (b,_) -> String.compare a b) in
  if not (List.equal String.equal (List.map assignments ~f:fst)
    (List.map (Schema.parameters schema) ~f:Parameter.key)) then J.fail "hardware assignments must exactly match schema";
  List.iter2_exn (Schema.parameters schema) assignments ~f:(fun p (_,v) ->
    match Parameter.kind p, v with
    | Integer {minimum; maximum}, Value.Int n when n >= minimum && n <= maximum -> ()
    | Boolean, Bool _ -> ()
    | Enumeration values, Enum s when List.mem values s ~equal:String.equal -> ()
    | _ -> J.fail ("invalid hardware assignment: " ^ Parameter.key p));
  let unsigned = payload schema assignments in
  let identity = J.checked (J.identity ~contract unsigned) in
  let encoded = match unsigned with
    | `Assoc xs -> `Assoc (xs @ ["identity", `String identity])
    | _ -> assert false in
  if String.length (J.checked (J.canonical encoded)) > max_bytes
  then J.fail "hardware declaration exceeds 128 KiB";
  {schema; assignments; identity})
let to_yojson t = match payload t.schema t.assignments with
  | `Assoc xs -> `Assoc (xs @ ["identity", `String t.identity])
  | _ -> assert false
let to_string t = J.checked (J.canonical (to_yojson t))
let sexp_of_t t = Sexp.Atom (to_string t)
let get t key = match List.Assoc.find t.assignments key ~equal:String.equal with
  | Some v -> v | None -> J.fail ("unknown hardware parameter: " ^ key)
let get_int t ~key = J.decode (fun () -> match get t key with
  | Value.Int n -> n | _ -> J.fail "expected integer hardware parameter")
let get_bool t ~key = J.decode (fun () -> match get t key with
  | Value.Bool b -> b | _ -> J.fail "expected boolean hardware parameter")
let get_enum t ~key = J.decode (fun () -> match get t key with
  | Value.Enum s -> s | _ -> J.fail "expected enum hardware parameter")
let integer = function `Int n -> n | _ -> J.fail "expected integer JSON token"
let of_yojson j = J.decode (fun () ->
  let rec depth n = function
    | _ when n > 8 -> J.fail "hardware JSON nesting exceeds 8"
    | `Assoc xs -> List.iter xs ~f:(fun (_,v) -> depth (n+1) v)
    | `List xs -> List.iter xs ~f:(depth (n+1))
    | _ -> () in
  depth 0 j;
  if String.length (Yojson.Safe.to_string j) > max_bytes then J.fail "hardware declaration exceeds 128 KiB";
  J.envelope j ~contract ~fields:["design_id";"schema_id";"parameters";"assignments";"identity"];
  let parameters = J.array (J.get j "parameters") |> List.map ~f:(fun p ->
    let kind = match J.string (J.get p "type") with
      | "integer" ->
        J.object_ p ~fields:["key";"type";"minimum";"maximum"];
        Parameter.Integer {minimum=integer (J.get p "minimum");maximum=integer (J.get p "maximum")}
      | "boolean" -> J.object_ p ~fields:["key";"type"]; Parameter.Boolean
      | "enum" -> J.object_ p ~fields:["key";"type";"values"];
        Parameter.Enumeration (List.map (J.array (J.get p "values")) ~f:J.string)
      | _ -> J.fail "unsupported hardware parameter type"
    in J.checked (Parameter.create ~key:(J.string (J.get p "key")) ~kind)) in
  let schema = J.checked (Schema.create ~design_id:(J.string (J.get j "design_id"))
    ~schema_id:(J.string (J.get j "schema_id")) ~parameters) in
  let assignments = match J.get j "assignments" with
    | `Assoc xs -> List.map xs ~f:(fun (k,v) -> k, (match v with
        | `Int n -> Value.Int n | `Bool b -> Bool b | `String s -> Enum s
        | _ -> J.fail "unsupported hardware assignment scalar"))
    | _ -> J.fail "expected hardware assignments object" in
  let t = J.checked (create ~schema ~assignments) in
  if not (String.equal (J.string (J.get j "identity")) t.identity) then J.fail "hardware variant identity mismatch";
  t)
let of_string s =
  if String.length s > max_bytes then Or_error.error_string "hardware declaration exceeds 128 KiB"
  else J.parse of_yojson s
