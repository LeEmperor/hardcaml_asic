module J = Identity_json

let checked = function Ok x -> x | Error e -> invalid_arg (J.error_message e)
let text s = checked (J.string s)
let obj fields = checked (J.object_ fields)
let integer n = checked (J.integer (string_of_int n))
let path p =
  if p = "" || String.contains p '\000' then invalid_arg "invalid result-store path";
  if Filename.is_relative p then Filename.concat (Sys.getcwd ()) p else p
;;

let resolve p =
  let rec walk current remaining = function
    | [] -> current
    | "" :: rest | "." :: rest -> walk current remaining rest
    | ".." :: rest -> walk (Filename.dirname current) remaining rest
    | component :: rest ->
      let candidate = Filename.concat current component in
      let link =
        try if (Unix.lstat candidate).Unix.st_kind = Unix.S_LNK then Some (Unix.readlink candidate) else None
        with Unix.Unix_error (Unix.ENOENT, _, _) -> None in
      (match link with
       | None -> walk candidate remaining rest
       | Some target ->
         if remaining = 0 then raise (Unix.Unix_error (Unix.ELOOP, "resolve", p));
         walk (if Filename.is_relative target then current else "/") (remaining - 1)
           (String.split_on_char '/' target @ rest))
  in
  walk "/" 40 (String.split_on_char '/' p)
;;

let rec mkdirs p =
  try Unix.mkdir p 0o777 with
  | Unix.Unix_error (Unix.ENOENT, _, _) -> mkdirs (Filename.dirname p); mkdirs p
  | Unix.Unix_error (Unix.EEXIST, _, _) ->
    if (Unix.stat p).Unix.st_kind <> Unix.S_DIR
    then raise (Unix.Unix_error (Unix.ENOTDIR, "mkdir", p))
;;

let uuid () =
  let ic = open_in_bin "/dev/urandom" in
  let bytes = Fun.protect ~finally:(fun () -> close_in_noerr ic)
      (fun () -> Bytes.of_string (really_input_string ic 16)) in
  Bytes.set bytes 6 (Char.chr ((Char.code (Bytes.get bytes 6) land 15) lor 64));
  Bytes.set bytes 8 (Char.chr ((Char.code (Bytes.get bytes 8) land 63) lor 128));
  String.concat "" (List.init 16 (fun i -> Printf.sprintf "%02x" (Char.code (Bytes.get bytes i))))
;;

let identity s =
  let remove token s =
    let b = Buffer.create (String.length s) in
    let rec loop i =
      if i < String.length s then
        if i + String.length token <= String.length s
           && String.sub s i (String.length token) = token
        then loop (i + String.length token)
        else (Buffer.add_char b s.[i]; loop (i + 1)) in
    loop 0; Buffer.contents b in
  (* uuid.UUID(str(...)) strips these literal prefixes and edge braces before
     removing hyphens; it does not accept embedded braces or uppercase URNs. *)
  let s = remove "uuid:" (remove "urn:" s) in
  let brace = function '{' | '}' -> true | _ -> false in
  let first = ref 0 and last = ref (String.length s) in
  while !first < !last && brace s.[!first] do incr first done;
  while !last > !first && brace s.[!last - 1] do decr last done;
  let s = String.lowercase_ascii (remove "-" (String.sub s !first (!last - !first))) in
  if String.length s <> 32 || not (String.for_all (function '0'..'9' | 'a'..'f' -> true | _ -> false) s)
  then invalid_arg "invalid UUID";
  s
;;

let instant clock =
  let t = clock () in
  if not (Float.is_finite t) then invalid_arg "nonfinite result-store clock";
  let micros = Float.round (t *. 1e6) in
  let seconds = floor (micros /. 1e6) in
  let us = int_of_float (micros -. seconds *. 1e6) in
  let tm = Unix.gmtime seconds in
  let year = tm.Unix.tm_year + 1900 in
  if year < 1 || year > 9999 then invalid_arg "result-store clock year outside 1..9999";
  let name = Printf.sprintf "%04d%02d%02dT%02d%02d%02d%06dZ"
      year (tm.tm_mon + 1) tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec us in
  let created = Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d%s+00:00"
      year (tm.tm_mon + 1) tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec
      (if us = 0 then "" else Printf.sprintf ".%06d" us) in
  name, created
;;

type allocation = { identity : string; directory : string; created_at : string }

let allocate ?(clock = Unix.gettimeofday) ?(id_factory = uuid) ?(max_attempts = 8) root =
  if max_attempts < 1 then invalid_arg "max_attempts must be positive";
  let root = resolve (path root) in
  mkdirs root;
  let rec attempt remaining =
    if remaining = 0 then raise (Unix.Unix_error (Unix.EEXIST, "result allocation exhausted", root));
    let stamp, created_at = instant clock in
    let identity = identity (id_factory ()) in
    let directory = Filename.concat root (stamp ^ "_" ^ String.sub identity 0 8) in
    try Unix.mkdir directory 0o777; { identity; directory; created_at } with
    | Unix.Unix_error (Unix.EEXIST, _, _) -> attempt (remaining - 1)
  in
  attempt max_attempts
;;

let record_bytes value =
  let rec pretty depth = function
    | J.Object [] -> "{}"
    | J.Array [] -> "[]"
    | J.Object fields ->
      block depth "{" "}" (List.map (fun (k, v) -> J.canonical (text k) ^ ": " ^ pretty (depth + 1) v)
        (List.sort (fun (a, _) (b, _) -> String.compare a b) fields))
    | J.Array values -> block depth "[" "]" (List.map (pretty (depth + 1)) values)
    | scalar -> J.canonical scalar
  and block depth left right values =
    let indent = String.make ((depth + 1) * 2) ' ' in
    left ^ "\n" ^ indent ^ String.concat (",\n" ^ indent) values ^ "\n" ^ String.make (depth * 2) ' ' ^ right
  in pretty 0 value ^ "\n"
;;

let save_json destination value =
  let destination = path destination in
  let bytes = record_bytes value in
  let temporary, oc = Filename.open_temp_file ~mode:[Open_binary]
      ~temp_dir:(Filename.dirname destination) ("." ^ Filename.basename destination ^ ".") "" in
  Fun.protect ~finally:(fun () ->
    close_out_noerr oc;
    try Unix.unlink temporary with Unix.Unix_error (Unix.ENOENT, _, _) -> ())
    (fun () -> output_string oc bytes; close_out oc; Unix.rename temporary destination)
;;

let read_json p =
  let ic = open_in_bin (path p) in
  Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
    let buffer = Buffer.create 4096 in
    let chunk = Bytes.create 4096 in
    let rec loop () =
      let n = input ic chunk 0 4096 in
      if n > 0 then (Buffer.add_subbytes buffer chunk 0 n; loop ()) in
    loop (); J.parse (Buffer.contents buffer))
;;

let validate_output p =
  let p = path p in
  let parent = Filename.dirname p in
  if (Unix.stat parent).Unix.st_kind <> Unix.S_DIR then raise (Unix.Unix_error (Unix.ENOTDIR, "preflight output parent", parent));
  Unix.access parent [Unix.W_OK; Unix.X_OK];
  (try
     if (Unix.stat p).Unix.st_kind = Unix.S_DIR then raise (Unix.Unix_error (Unix.EISDIR, "preflight output", p));
     Unix.access p [Unix.W_OK]
   with Unix.Unix_error (Unix.ENOENT, _, _) -> ());
  p
;;

type status = Pending | Ready | Failed | Interrupted
let status_name = function Pending -> "pending" | Ready -> "ready" | Failed -> "failed" | Interrupted -> "interrupted"
let fields = function J.Object f -> f | _ -> invalid_arg "expected record object"
let update original changes = obj (changes @ List.filter (fun (k, _) -> not (List.mem_assoc k changes)) (fields original))

let diagnostic ?(provenance = obj []) ?interrupted_by ~bundle ~status ~issue () =
  let changes = ["status", text (status_name status); "bundle", text (resolve (path bundle))]
      @ (match interrupted_by with None -> [] | Some s -> ["interrupted_by", text s]) in
  obj ["ready", J.bool false; "issues", J.array [text issue]; "diagnostic", update provenance changes]
;;

let pending_report ?provenance ~bundle () =
  diagnostic ?provenance ~bundle ~status:Pending ~issue:"preflight pending; tool probes have not completed" ()
;;

let classify_report = function
  | J.Object f ->
    (match List.assoc_opt "ready" f, List.assoc_opt "issues" f with
     | Some (J.Bool ready), Some (J.Array _) -> Ok (if ready then Ready, 0 else Failed, 1)
     | _ -> Error "malformed preflight result: expected ready boolean and issues list")
  | _ -> Error "malformed preflight result: expected ready boolean and issues list"
;;

let operation_receipt allocation ~bundle =
  obj ["schema_version", integer 1; "record_type", text "preflight_operation";
       "operation_id", text allocation.identity; "bundle", text (resolve (path bundle));
       "started_at", text allocation.created_at; "ended_at", J.null;
       "status", text "pending"; "report", text "preflight.json"; "exit_code", J.null]
;;

let finish_receipt receipt ~status ~exit_code ~ended_at ?error () =
  update receipt (["status", text (status_name status); "exit_code", integer exit_code; "ended_at", text ended_at]
    @ (match error with None -> [] | Some s -> ["error", text s]))
;;

let begin_preflight ?clock ?id_factory ?max_attempts ?(save = save_json) ~results_root ~bundle () =
  let bundle = resolve (path bundle) in
  let allocation = allocate ?clock ?id_factory ?max_attempts (Filename.concat results_root "operations") in
  let report_path = Filename.concat allocation.directory "preflight.json" in
  let receipt_path = Filename.concat allocation.directory "operation.json" in
  let receipt = operation_receipt allocation ~bundle in
  save receipt_path receipt;
  allocation, report_path, receipt_path, receipt
;;
