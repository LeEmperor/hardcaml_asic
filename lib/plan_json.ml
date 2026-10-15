open! Core

let fail message = invalid_arg message
let checked = Or_error.ok_exn
let decode f = Or_error.try_with f

let rec normalize : Yojson.Safe.t -> Yojson.Safe.t = function
  | (`Null | `Bool _ | `Int _ | `String _) as j -> j
  | `Float f as j -> if Float.is_finite f then j else fail "nonfinite JSON number"
  | `List xs -> `List (List.map xs ~f:normalize)
  | `Assoc xs ->
    if Option.is_some
         (List.find_a_dup xs ~compare:(fun (a, _) (b, _) -> String.compare a b))
    then fail "duplicate JSON field";
    `Assoc
      (List.sort xs ~compare:(fun (a, _) (b, _) -> String.compare a b)
       |> List.map ~f:(fun (k, v) -> k, normalize v))
  | `Intlit _ | `Tuple _ | `Variant _ -> fail "non-JSON extension"
;;

let validate j = ignore (normalize j : Yojson.Safe.t)
let canonical j = decode (fun () -> Yojson.Safe.to_string (normalize j))

let sha256 s =
  Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) s
  |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
;;

let identity ~contract j =
  canonical
    (`Assoc [ "contract", `String contract; "schema_version", `Int 1; "payload", j ])
  |> Or_error.map ~f:sha256
;;

let object_ j ~fields =
  validate j;
  match j with
  | `Assoc xs
    when List.equal
           String.equal
           (List.sort (List.map xs ~f:fst) ~compare:String.compare)
           (List.sort fields ~compare:String.compare) -> ()
  | _ -> fail "object fields do not match versioned schema"
;;

let get j k =
  match j with
  | `Assoc xs ->
    (match List.Assoc.find xs k ~equal:String.equal with
     | Some v -> v
     | None -> fail ("missing field: " ^ k))
  | _ -> fail "expected object"
;;

let string = function
  | `String s -> s
  | _ -> fail "expected string"
;;

let array = function
  | `List xs -> xs
  | _ -> fail "expected array"
;;

let envelope j ~contract ~fields =
  object_ j ~fields:("contract" :: "schema_version" :: fields);
  if (not (String.equal (string (get j "contract")) contract))
     || not (Poly.equal (get j "schema_version") (`Int 1))
  then fail "unsupported wire contract/version"
;;

let equal a b = String.equal (checked (canonical a)) (checked (canonical b))
