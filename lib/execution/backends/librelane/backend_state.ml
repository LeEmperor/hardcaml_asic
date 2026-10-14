module J = Identity_json
type t = { views : (string * J.t) list; metrics : string }
exception Invalid of string
let fail s = raise (Invalid s)
let codec = function Ok x -> x | Error e -> fail (J.error_message e)
let delimit c = List.mem c [' '; '\n'; '\r'; '\t'; '{'; '}'; '['; ']'; ':'; ','; '"']
(* A syntax-only projection. The original metrics slice, never this projection,
   is serialized. Quoted content is not substituted. *)
let projection bytes =
  let b = Buffer.create (String.length bytes) in
  let n = String.length bytes in
  let rec loop i quoted escaped =
    if i < n then let c = bytes.[i] in
      if quoted then (Buffer.add_char b c;
        loop (i+1) (escaped || c <> '"') (not escaped && c = '\\'))
      else if c = '"' then (Buffer.add_char b c; loop (i+1) true false)
      else if delimit c then (Buffer.add_char b c; loop (i+1) false false)
      else (
        let j = ref i in
        while !j < n && not (delimit bytes.[!j]) do incr j done;
        let token = String.sub bytes i (!j-i) in
        let replacement = if List.mem token ["Infinity"; "-Infinity"; "NaN"] then "0"
          else match J.parse token with Error J.Nonfinite -> "0" | _ -> token in
        Buffer.add_string b replacement; loop !j false false)
  in loop 0 false false; codec (J.parse (Buffer.contents b))
let rec paths f = function
  | J.Null -> J.null
  | J.String s -> codec (J.string (f s))
  | J.Array xs -> J.array (List.map (paths f) xs)
  | J.Object xs -> codec (J.object_ (List.map (fun (k,v) -> k, paths f v) xs))
  | _ -> fail "invalid state view leaf"
let parse bytes = try
  let fields = match projection bytes with J.Object xs -> xs | _ -> fail "malformed official state" in
  (match List.assoc_opt "metrics" fields with Some (J.Object _) -> () | _ -> fail "malformed official state metrics");
  let views = List.filter (fun (k,_) -> k <> "metrics") fields in
  List.iter (fun (_,v) -> ignore (paths Fun.id v)) views;
  (* Split top-level members only after complete syntax validation. *)
  let n = String.length bytes in
  let skip i = let i = ref i in while !i < n && List.mem bytes.[!i] [' '; '\n'; '\r'; '\t'] do incr i done; !i in
  let quoted i =
    let rec loop j escaped = if j >= n then fail "unterminated string"
      else if bytes.[j] = '"' && not escaped then j+1
      else loop (j+1) (not escaped && bytes.[j] = '\\') in loop (i+1) false in
  let value_end i =
    let rec loop j depth =
      if j >= n then j else match bytes.[j] with
      | '"' -> loop (quoted j) depth
      | '{' | '[' -> loop (j+1) (depth+1)
      | '}' | ']' when depth > 0 -> loop (j+1) (depth-1)
      | ',' | '}' when depth = 0 -> j
      | _ -> loop (j+1) depth in loop i 0 in
  let rec members i =
    let i = skip i in
    let k_end = quoted i in
    let key = match codec (J.parse (String.sub bytes i (k_end-i))) with J.String s -> s | _ -> assert false in
    let start = skip (skip k_end + 1) in
    let finish = value_end start in
    if key = "metrics" then String.sub bytes start (finish-start)
    else members (finish+1) in
  Ok { views; metrics = members (skip 0 + 1) }
with Invalid s -> Error s
let views t = t.views
let map_paths t ~f = { t with views = List.map (fun (k,v) -> k, paths f v) t.views }
let serialize t =
  let key k = J.canonical (codec (J.string k)) in
  "{" ^ String.concat "," (List.map (fun (k,v) -> key k ^ ":" ^ J.canonical v) t.views
    @ ["\"metrics\":" ^ t.metrics]) ^ "}\n"
