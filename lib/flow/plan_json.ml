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

(* Same standard-JSON admission grammar used by preparation's independent codec.
   Kept below Flow so hardware declarations need not depend on Elaboration. *)
let strict_syntax s =
  if not (Stdlib.String.is_valid_utf_8 s) then fail "invalid UTF-8";
  let n = String.length s and pos = ref 0 in
  let peek () = if !pos < n then s.[!pos] else '\000' in
  let take c = if Char.equal (peek ()) c then incr pos else fail "invalid JSON syntax" in
  let whitespace () =
    while !pos < n && (match peek () with ' ' | '\t' | '\r' | '\n' -> true | _ -> false) do incr pos done in
  let hex () =
    let value = ref 0 in
    for _ = 1 to 4 do
      let digit = match peek () with
        | '0'..'9' as c -> Char.to_int c - Char.to_int '0'
        | 'a'..'f' as c -> Char.to_int c - Char.to_int 'a' + 10
        | 'A'..'F' as c -> Char.to_int c - Char.to_int 'A' + 10
        | _ -> fail "invalid Unicode escape" in
      incr pos; value := (!value * 16) + digit
    done;
    !value in
  let string_token () =
    take '"';
    while !pos < n && not (Char.equal (peek ()) '"') do
      match peek () with
      | '\\' ->
        incr pos;
        (match peek () with
         | '"' | '\\' | '/' | 'b' | 'f' | 'n' | 'r' | 't' -> incr pos
         | 'u' ->
           incr pos;
           let code = hex () in
           if code >= 0xd800 && code <= 0xdbff then (
             take '\\'; take 'u';
             let low = hex () in
             if low < 0xdc00 || low > 0xdfff then fail "invalid surrogate pair")
           else if code >= 0xdc00 && code <= 0xdfff then fail "unpaired surrogate"
         | _ -> fail "invalid string escape")
      | c -> if Char.to_int c < 32 then fail "unescaped control character"; incr pos
    done;
    take '"' in
  let digit () = match peek () with '0'..'9' -> true | _ -> false in
  let digits () =
    if not (digit ()) then fail "expected number digit";
    while digit () do incr pos done in
  let number () =
    if Char.equal (peek ()) '-' then incr pos;
    (match peek () with
     | '0' -> incr pos
     | '1'..'9' -> digits ()
     | _ -> fail "invalid number");
    if Char.equal (peek ()) '.' then (incr pos; digits ());
    if Char.equal (peek ()) 'e' || Char.equal (peek ()) 'E' then (
      incr pos;
      if Char.equal (peek ()) '+' || Char.equal (peek ()) '-' then incr pos;
      digits ()) in
  let literal word = String.iter word ~f:take in
  let rec value depth =
    if depth > 256 then fail "JSON nesting exceeds 256";
    whitespace ();
    match peek () with
    | '"' -> string_token ()
    | '{' ->
      incr pos; whitespace ();
      if Char.equal (peek ()) '}' then incr pos
      else (
        member depth; whitespace ();
        while Char.equal (peek ()) ',' do
          incr pos; whitespace (); member depth; whitespace ()
        done; take '}')
    | '[' ->
      incr pos; whitespace ();
      if Char.equal (peek ()) ']' then incr pos
      else (
        value (depth + 1); whitespace ();
        while Char.equal (peek ()) ',' do incr pos; value (depth + 1); whitespace () done;
        take ']')
    | 'n' -> literal "null" | 't' -> literal "true" | 'f' -> literal "false"
    | '-' | '0'..'9' -> number ()
    | _ -> fail "invalid JSON value"
  and member depth = string_token (); whitespace (); take ':'; value (depth + 1) in
  value 0; whitespace ();
  if !pos <> n then fail "trailing JSON data"
;;

let parse f s =
  decode (fun () -> strict_syntax s; Yojson.Safe.from_string s) |> Or_error.bind ~f
