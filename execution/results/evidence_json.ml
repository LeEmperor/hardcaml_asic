type t = Yojson.Safe.t
type document = { raw : string; value : t }
let value d = d.value
let raw_bytes d = d.raw
exception Decode of string
let parse ?(reject_duplicates=false) raw =
  let n = String.length raw and i = ref 0 in
  let error message at =
    let line = ref 1 and start = ref 0 in
    for j = 0 to min (at - 1) (n - 1) do
      if raw.[j] = '\n' then (incr line; start := j + 1)
    done;
    raise (Decode (Printf.sprintf "%s: line %d column %d (char %d)"
      message !line (at - !start + 1) at)) in
  let skip () = while !i < n && List.mem raw.[!i] [' '; '\n'; '\r'; '\t'] do incr i done in
  let starts s = !i + String.length s <= n && String.sub raw !i (String.length s) = s in
  let digit c = c >= '0' && c <= '9' in
  let string () =
    let start = !i in incr i;
    let rec scan () =
      if !i >= n then error "Unterminated string starting at" start;
      match raw.[!i] with
      | '"' -> incr i
      | '\\' -> i := !i + 2; scan ()
      | c when Char.code c < 32 -> error "Invalid control character at" !i
      | _ -> incr i; scan () in
    scan ();
    try match Yojson.Safe.from_string (String.sub raw start (!i-start)) with
      | `String s -> s | _ -> assert false
    with Yojson.Json_error _ -> error "Invalid \\escape" start in
  let rec json depth =
    if depth > 256 then raise (Decode "evidence nesting exceeds 256");
    skip ();
    if !i >= n then error "Expecting value" !i;
    match raw.[!i] with
    | '"' -> `String (string ())
    | '{' ->
      incr i; skip ();
      let rec members acc =
        if !i >= n || raw.[!i] <> '"' then error "Expecting property name enclosed in double quotes" !i;
        let key = string () in skip ();
        if !i >= n || raw.[!i] <> ':' then error "Expecting ':' delimiter" !i;
         incr i; let v = json (depth+1) in
         if reject_duplicates && List.mem_assoc key acc then
           error ("Duplicate property: "^key) !i;
        (* Python replaces a duplicate in place, preserving insertion order. *)
        let acc = if List.mem_assoc key acc then List.map (fun (k,x) -> k, if k=key then v else x) acc
          else acc @ [key,v] in
        skip ();
        if !i < n && raw.[!i] = '}' then (incr i; `Assoc acc)
        else if !i < n && raw.[!i] = ',' then (incr i; skip (); members acc)
        else error "Expecting ',' delimiter" !i in
      if !i < n && raw.[!i]='}' then (incr i; `Assoc []) else members []
    | '[' ->
      incr i; skip ();
      let rec items acc = let v = json (depth+1) in skip ();
        if !i < n && raw.[!i]=']' then (incr i; `List (List.rev (v::acc)))
        else if !i < n && raw.[!i]=',' then (incr i; items (v::acc))
        else error "Expecting ',' delimiter" !i in
      if !i < n && raw.[!i]=']' then (incr i; `List []) else items []
    | _ ->
      let literals = ["null", `Null; "true", `Bool true; "false", `Bool false;
        "NaN", `Float nan; "Infinity", `Float infinity; "-Infinity", `Float neg_infinity] in
      match List.find_opt (fun (s,_) -> starts s) literals with
      | Some (s,v) -> i := !i + String.length s; v
      | None ->
        let start = !i in
        if raw.[!i]='-' then incr i;
        if !i >= n || not (digit raw.[!i]) then error "Expecting value" start;
        if raw.[!i]='0' then incr i else while !i<n && digit raw.[!i] do incr i done;
        let floating = ref false in
        if !i+1<n && raw.[!i]='.' && digit raw.[!i+1] then (
          floating := true; incr i; while !i<n && digit raw.[!i] do incr i done);
        if !i<n && List.mem raw.[!i] ['e';'E'] then (
          let j = ref (!i+1) in
          if !j<n && List.mem raw.[!j] ['+';'-'] then incr j;
          if !j<n && digit raw.[!j] then (
            floating := true; i := !j; while !i<n && digit raw.[!i] do incr i done));
        let token = String.sub raw start (!i-start) in
        if !floating then `Float (float_of_string token)
        else `Intlit (Z.to_string (Z.of_string token)) in
  try let value = json 0 in skip (); if !i<n then error "Extra data" !i;
    Ok {raw; value}
  with Decode s -> Error s
let read path =
  let ic = open_in_bin path in
  let bytes = Fun.protect ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic)) in
  match parse bytes with Ok d -> d | Error s -> invalid_arg s
let read_regular path =
  match parse (Retained_file.read path) with Ok d -> d | Error s -> invalid_arg s
let scalar = function
  | `Float f when Float.is_nan f -> "NaN"
  | `Float f when not (Float.is_finite f) -> if f < 0. then "-Infinity" else "Infinity"
  | `Float f -> (match Identity_json.float f with Ok x -> Identity_json.canonical x | Error _ -> assert false)
  | `String s -> (match Identity_json.string s with Ok x -> Identity_json.canonical x
      | Error _ -> Yojson.Safe.to_string (`String s))
  | x -> Yojson.Safe.to_string x
let record_bytes value =
  let rec pretty depth = function
    | `Assoc [] -> "{}" | `List [] -> "[]"
    | `Assoc xs -> block depth "{" "}" (List.map (fun (k,v) -> scalar (`String k)^": "^pretty (depth+1) v)
        (List.sort (fun (a,_) (b,_) -> String.compare a b) xs))
    | `List xs -> block depth "[" "]" (List.map (pretty (depth+1)) xs)
    | x -> scalar x
  and block d l r xs = let indent = String.make ((d+1)*2) ' ' in
    l^"\n"^indent^String.concat (",\n"^indent) xs^"\n"^String.make (d*2) ' '^r in
  pretty 0 value ^ "\n"
let rec repr = function
  | `Null -> "None" | `Bool true -> "True" | `Bool false -> "False"
  | `Float f when Float.is_nan f -> "nan"
  | `Float f when not (Float.is_finite f) -> if f < 0. then "-inf" else "inf"
  | `String s ->
    let quote = if String.contains s '\'' && not (String.contains s '"') then '"' else '\'' in
    let b = Buffer.create 32 in Buffer.add_char b quote;
    String.iter (fun c -> match c with
      | '\n' -> Buffer.add_string b "\\n" | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t" | '\\' -> Buffer.add_string b "\\\\"
      | c when c=quote -> Buffer.add_char b '\\'; Buffer.add_char b c
      | c when Char.code c < 32 || Char.code c=127 -> Buffer.add_string b (Printf.sprintf "\\x%02x" (Char.code c))
      | c -> Buffer.add_char b c) s;
    Buffer.add_char b quote; Buffer.contents b
  | `List xs -> "["^String.concat ", " (List.map repr xs)^"]"
  | `Assoc xs -> "{"^String.concat ", " (List.map (fun (k,v) -> repr (`String k)^": "^repr v) xs)^"}"
  | x -> scalar x
