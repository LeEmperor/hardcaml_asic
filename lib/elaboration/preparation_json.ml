(* Internal, version-1 preparation codec. Object keys are sorted; arrays and
   tagged sexps preserve order. This is deliberately independent of Bundle's
   order-sensitive manifest codec and execution's Python-compatible codec. *)
open! Core

let fail message = invalid_arg ("resource preparation: " ^ message)
let obj xs = `Assoc xs
let str s = `String s
let arr f xs = `List (List.map xs ~f)
let string = function `String s -> s | _ -> fail "expected string"
let list = function `List xs -> xs | _ -> fail "expected list"
let fields = function `Assoc xs -> xs | _ -> fail "expected object"
let get j key = List.Assoc.find_exn (fields j) key ~equal:String.equal
let exact j keys =
  let actual = List.map (fields j) ~f:fst |> List.sort ~compare:String.compare in
  if not (List.equal String.equal actual (List.sort keys ~compare:String.compare))
  then fail "unexpected, missing or duplicate fields"
;;
let expect j expected = if not (Poly.equal j expected) then fail "unexpected value"
let enum j choices =
  let s = string j in
  if not (List.mem choices s ~equal:String.equal) then fail "unsupported enum";
  s
;;
let utf8 s = if not (Stdlib.String.is_valid_utf_8 s) then fail "invalid UTF-8"
let rec validate_at depth j =
  if depth > 256 then fail "JSON nesting exceeds 256";
  match j with
  | `Assoc xs ->
    if Option.is_some (List.find_a_dup (List.map xs ~f:fst) ~compare:String.compare)
    then fail "duplicate object key";
    List.iter xs ~f:(fun (key, v) -> utf8 key; validate_at (depth + 1) v)
  | `List xs -> List.iter xs ~f:(validate_at (depth + 1))
  | `String s -> utf8 s
  | `Float f when not (Float.is_finite f) -> fail "nonfinite number"
  | `Null | `Bool _ | `Int _ | `Float _ -> ()
  | _ -> fail "unsupported JSON value"
;;
let validate j = validate_at 0 j
let rec canonical = function
  | `Assoc xs ->
    `Assoc (List.sort xs ~compare:(fun (a, _) (b, _) -> String.compare a b)
            |> List.map ~f:(fun (k, v) -> k, canonical v))
  | `List xs -> `List (List.map xs ~f:canonical)
  | j -> j
;;
let bytes j = validate j; Yojson.Safe.to_string (canonical j)
let sha256 s =
  Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) s
  |> String.to_list |> List.map ~f:(fun c -> Printf.sprintf "%02x" (Char.to_int c))
  |> String.concat
;;
let hash domain j = sha256 ("hardcaml_asic/" ^ domain ^ "/v1\000" ^ bytes j)
let digest j =
  let s = string j in
  if String.length s <> 64 || not (String.for_all s ~f:(function '0'..'9' | 'a'..'f' -> true | _ -> false))
  then fail "invalid SHA-256";
  s
;;
let rec sexp = function
  | Sexp.Atom s -> obj ["atom", str s]
  | List xs -> obj ["list", arr sexp xs]
;;
let rec read_sexp j =
  match fields j with
  | ["atom", `String s] -> Sexp.Atom s
  | ["list", `List xs] -> Sexp.List (List.map xs ~f:read_sexp)
  | _ -> fail "invalid tagged sexp"
;;
let checked f j = Or_error.try_with (fun () -> validate j; f j)
(* Yojson accepts comments and several OCaml extensions. Check the standard JSON
   grammar first, including scalar Unicode escapes, then use Yojson for values. *)
let strict_syntax s =
  utf8 s;
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
  Or_error.try_with (fun () -> strict_syntax s; Yojson.Safe.from_string s)
  |> Or_error.bind ~f
let pretty j = validate j; Yojson.Safe.pretty_to_string (canonical j) ^ "\n"
