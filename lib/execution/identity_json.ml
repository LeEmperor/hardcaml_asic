type t =
  | Null | Bool of bool | String of string | Integer of string | Float of float
  | Array of t list | Object of (string * t) list

type error = Malformed of string | Duplicate_key of string | Invalid_unicode
           | Nonfinite | Unsupported_float
exception Invalid of error
let error_message = function
  | Malformed s -> "malformed: " ^ s
  | Duplicate_key s -> "duplicate key: " ^ s
  | Invalid_unicode -> "invalid or unsupported Unicode"
  | Nonfinite -> "nonfinite number"
  | Unsupported_float -> "unsupported float"
let fail e = raise (Invalid e)
let protect f = try Ok (f ()) with Invalid e -> Error e
let null = Null
let bool b = Bool b
let array xs = Array xs
let scalars s f =
  let rec loop i =
    if i < String.length s then (
      let d = String.get_utf_8_uchar s i in
      if not (Uchar.utf_decode_is_valid d) then fail Invalid_unicode;
      f (Uchar.to_int (Uchar.utf_decode_uchar d));
      loop (i + Uchar.utf_decode_length d))
  in loop 0
let string s = protect (fun () -> scalars s (fun _ -> ()); String s)
let digit c = c >= '0' && c <= '9'
let integer s = protect (fun () ->
  let n = String.length s in
  let start = if n > 0 && s.[0] = '-' then 1 else 0 in
  if start = n || (n - start > 1 && s.[start] = '0') then
    fail (Malformed "integer");
  for i = start to n - 1 do
    if not (digit s.[i]) then fail (Malformed "integer")
  done;
  Integer (if s = "-0" then "0" else s))
let unwrap = function Ok v -> v | Error e -> fail e
let object_ xs = protect (fun () ->
  (* UTF-8 byte order on validated scalars equals Unicode code-point order. *)
  let xs = List.sort (fun (a, _) (b, _) -> String.compare a b) xs in
  let rec check = function
    | [] -> ()
    | (k, _) :: rest ->
      scalars k (fun _ -> ());
      (match rest with (k', _) :: _ when k = k' -> fail (Duplicate_key k) | _ -> ());
      check rest
  in check xs; Object xs)

(* Exact shortest-roundtrip conversion, using binary64 rounding intervals.
   All finite positive doubles are integers in units of 2^-1074. Twice those
   units express both midpoint bounds exactly, including the asymmetric bounds
   at powers of two and the virtual successor 2^1024 of max_float. Midpoints
   belong to the interval iff the significand is even (round-to-nearest-even).

   At each decimal precision, test floor and ceil of the exact scaled value.
   If either is in the interval, no more distant grid point can be preferable.
   Select the nearest admitted point, breaking exact decimal ties to even.
   The first successful precision is shortest; 17 digits always suffice for
   binary64. No floating arithmetic determines digits or interval membership.
   log10 only seeds an exponent which is corrected by exact comparisons. *)
let powers10 = Array.init 341 (fun n -> Z.pow (Z.of_int 10) n)
let unit_denominator = Z.shift_left Z.one 1074
let units bits =
  let exponent = Int64.to_int (Int64.shift_right_logical bits 52) in
  let fraction = Int64.logand bits 0x000fffffffffffffL in
  if exponent = 0 then Z.of_int64 fraction
  else Z.shift_left (Z.of_int64 (Int64.logor fraction 0x0010000000000000L)) (exponent - 1)

let float_text x =
  if not (Float.is_finite x) then fail Nonfinite;
  let negative = Float.sign_bit x in
  let a = abs_float x in
  let body =
    if a = 0. then "0.0"
    else (
      let bits = Int64.bits_of_float a in
      let u = units bits in
      let lower = Z.add u (units (Int64.pred bits)) in
      let successor =
        if bits = 0x7fefffffffffffffL then Z.shift_left Z.one 2098
        else units (Int64.succ bits)
      in
      let upper = Z.add u successor in
      let inclusive = Int64.logand bits 1L = 0L in
      let compare_power exponent =
        if exponent >= 0 then Z.compare u (Z.mul unit_denominator powers10.(exponent))
        else Z.compare (Z.mul u powers10.(-exponent)) unit_denominator
      in
      let exponent = ref (int_of_float (floor (log10 a))) in
      while compare_power !exponent < 0 do decr exponent done;
      while compare_power (!exponent + 1) >= 0 do incr exponent done;
      let rec shortest precision =
        assert (precision <= 17);
        let scale = !exponent - precision + 1 in
        let multiplier, divisor =
          if scale >= 0 then powers10.(scale), Z.one
          else Z.one, powers10.(-scale)
        in
        let numerator = Z.mul u divisor in
        let denominator = Z.mul unit_denominator multiplier in
        let q, remainder = Z.ediv_rem numerator denominator in
        let lower = Z.mul lower divisor and upper = Z.mul upper divisor in
        let admitted q =
          let candidate = Z.shift_left (Z.mul q denominator) 1 in
          let lo = Z.compare candidate lower and hi = Z.compare candidate upper in
          (lo > 0 || inclusive && lo = 0) && (hi < 0 || inclusive && hi = 0)
        in
        let next = Z.succ q in
        let down = admitted q and up = admitted next in
        if not down && not up then shortest (precision + 1)
        else (
          let comparison = Z.compare (Z.shift_left remainder 1) denominator in
          let chosen =
            if down && (not up || comparison < 0 || comparison = 0 && not (Z.testbit q 0))
            then q else next
          in
          Z.to_string chosen, scale)
      in
      let digits, scale = shortest 1 in
      let length = String.length digits in
      let exponent = length + scale - 1 in
      let rec trim n = if n > 1 && digits.[n - 1] = '0' then trim (n - 1) else n in
      let digits = String.sub digits 0 (trim length) in
      let n = String.length digits in
      if exponent < -4 || exponent >= 16 then
        String.sub digits 0 1
        ^ (if n = 1 then "" else "." ^ String.sub digits 1 (n - 1))
        ^ Printf.sprintf "e%c%02d" (if exponent < 0 then '-' else '+') (abs exponent)
      else (
        let point = exponent + 1 in
        if point <= 0 then "0." ^ String.make (-point) '0' ^ digits
        else if point >= n then digits ^ String.make (point - n) '0' ^ ".0"
        else String.sub digits 0 point ^ "." ^ String.sub digits point (n - point)))
  in (if negative then "-" else "") ^ body
let float x = protect (fun () -> if not (Float.is_finite x) then fail Nonfinite; Float x)

let quoted s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  scalars s (fun cp ->
    let add = Buffer.add_string b in
    (match cp with
    | 34 -> add "\\\"" | 92 -> add "\\\\"
    | 8 -> add "\\b" | 9 -> add "\\t" | 10 -> add "\\n"
    | 12 -> add "\\f" | 13 -> add "\\r"
    | cp when cp < 32 || cp >= 127 ->
      if cp <= 0xffff then add (Printf.sprintf "\\u%04x" cp)
      else (
        let cp = cp - 0x10000 in
        add (Printf.sprintf "\\u%04x\\u%04x" (0xd800 + (cp lsr 10)) (0xdc00 + (cp land 1023))))
    | cp -> Buffer.add_char b (Char.chr cp));
    ());
  Buffer.add_char b '"'; Buffer.contents b
let rec canonical = function
  | Null -> "null" | Bool true -> "true" | Bool false -> "false"
  | String s -> quoted s | Integer s -> s | Float x -> float_text x
  | Array xs -> "[" ^ String.concat "," (List.map canonical xs) ^ "]"
  | Object xs -> "{" ^ String.concat "," (List.map (fun (k,v) -> quoted k ^ ":" ^ canonical v) xs) ^ "}"
let sha256_bytes s =
  Cryptokit.transform_string (Cryptokit.Hexa.encode ())
    (Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) s)
let identity v = sha256_bytes (canonical v)
let exact_object v ~fields = protect (fun () ->
  let expected = List.sort_uniq String.compare fields in
  if List.length expected <> List.length fields then fail (Malformed "duplicate expected field");
  match v with
  | Object xs when List.map fst xs = expected -> xs
  | _ -> fail (Malformed "object fields"))
let unsigned v ~field = protect (fun () -> match v with
  | Object xs when List.mem_assoc field xs -> Object (List.remove_assoc field xs)
  | _ -> fail (Malformed "missing signature field"))

let parse s = protect (fun () ->
  let n = String.length s and pos = ref 0 in
  let bad () = fail (Malformed ("JSON at byte " ^ string_of_int !pos)) in
  let peek () = if !pos < n then s.[!pos] else '\000' in
  let take c = if peek () = c then incr pos else bad () in
  let space () = while !pos < n && List.mem (peek ()) [' '; '\n'; '\r'; '\t'] do incr pos done in
  let hex () =
    let v = ref 0 in
    for _ = 1 to 4 do
      let c = peek () in
      let d = if digit c then Char.code c - 48 else if c >= 'a' && c <= 'f' then Char.code c - 87 else if c >= 'A' && c <= 'F' then Char.code c - 55 else (bad ()) in
      incr pos; v := !v * 16 + d
    done; !v in
  let text () =
    take '"'; let b = Buffer.create 32 in
    while peek () <> '"' do
      if !pos >= n then bad ();
      let c = peek () in incr pos;
      if c = '\\' then (
        let e = peek () in incr pos;
        match e with
        | '"' | '\\' | '/' -> Buffer.add_char b e
        | 'b' -> Buffer.add_char b '\b' | 'f' -> Buffer.add_char b '\012'
        | 'n' -> Buffer.add_char b '\n' | 'r' -> Buffer.add_char b '\r' | 't' -> Buffer.add_char b '\t'
        | 'u' ->
          let cp = hex () in
          let cp = if cp >= 0xd800 && cp <= 0xdbff then (
            if peek () <> '\\' then fail Invalid_unicode;
            incr pos; if peek () <> 'u' then fail Invalid_unicode;
            incr pos; let low = hex () in
            if low < 0xdc00 || low > 0xdfff then fail Invalid_unicode;
            0x10000 + ((cp - 0xd800) lsl 10) + low - 0xdc00)
            else if cp >= 0xdc00 && cp <= 0xdfff then fail Invalid_unicode else cp in
          Buffer.add_utf_8_uchar b (Uchar.of_int cp)
        | _ -> bad ())
      else if Char.code c < 32 then bad () else Buffer.add_char b c
    done;
    take '"'; let value = Buffer.contents b in
    scalars value (fun _ -> ()); value in
  let items closing read =
    space ();
    if peek () = closing then (incr pos; []) else (
      let rec loop acc =
        let v = read () in space ();
        if peek () = closing then (incr pos; List.rev (v :: acc))
        else (take ','; loop (v :: acc))
      in loop [])
  in
  let rec value depth =
    if depth > 256 then fail (Malformed "nesting limit");
    space ();
    match peek () with
    | '"' -> String (text ())
    | '[' -> incr pos; Array (items ']' (fun () -> value (depth + 1)))
    | '{' -> incr pos; unwrap (object_ (items '}' (fun () ->
        space (); let k = text () in space (); take ':'; k, value (depth + 1))))
    | 'n' -> literal "null" Null | 't' -> literal "true" (Bool true) | 'f' -> literal "false" (Bool false)
    | '-' | '0'..'9' -> number ()
    | _ -> bad ()
  and literal word v =
    String.iter (fun c -> take c) word; v
  and number () =
    let start = !pos in
    if peek () = '-' then incr pos;
    if peek () = '0' then incr pos
    else (if peek () < '1' || peek () > '9' then bad ();
          while digit (peek ()) do incr pos done);
    let is_float = ref false in
    let digits () = if not (digit (peek ())) then bad (); while digit (peek ()) do incr pos done in
    if peek () = '.' then (is_float := true; incr pos; digits ());
    if peek () = 'e' || peek () = 'E' then (
      is_float := true; incr pos;
      if peek () = '+' || peek () = '-' then incr pos;
      digits ());
    let token = String.sub s start (!pos - start) in
    if !is_float then (
      let x = try float_of_string token with Failure _ -> bad () in
      unwrap (float x))
    else unwrap (integer token)
  in let v = value 0 in space (); if !pos <> n then bad (); v)
