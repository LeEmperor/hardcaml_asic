module J = Identity_json
let codec = function Ok x -> x | Error e -> invalid_arg (J.error_message e)
let str s = codec (J.string s)
let obj xs = codec (J.object_ xs)
let get j k = match j with `Assoc xs -> Option.value (List.assoc_opt k xs) ~default:`Null | _ -> `Null
let number field = function
  | `Int n when n>=0 -> float_of_int n
  | `Intlit s -> let f=float_of_string s in
    if not (Float.is_finite f) || f<0. then invalid_arg (field^": invalid number"); f
  | `Float f when Float.is_finite f && f>=0. -> f
  | _ -> invalid_arg (field^": expected finite nonnegative number, not boolean")
let count field v =
  let f=number field v in
  if floor f<>f then invalid_arg (field^": expected integral count");
  match v with
  | `Int n -> Z.of_int n
  | `Intlit s -> Z.of_string s
  | _ -> Z.of_float f
let integer z = codec (J.integer (Z.to_string z))
let area field design =
  match get design field with
  | `Null -> J.null
  | v -> obj ["value",codec (J.float (number field v));"unit",str "µm²"]
let scope = "retained producer report; not checkpoint-inventoried"
(* Evidence and Unix paths may contain arbitrary bytes. Never feed those bytes
   back to the strict identity codec from an exception handler. Escape only the
   diagnostic representation; the source and its raw-byte hash stay untouched. *)
let diagnostic_string s =
  match J.string s with
  | Ok j -> j
  | Error _ ->
    let b=Buffer.create 128 in
    for i=0 to min (String.length s) 1024 - 1 do
      let c=s.[i] in
      if Char.code c>=32 && Char.code c<127 && c<>'\\' then Buffer.add_char b c
      else Buffer.add_string b (Printf.sprintf "\\x%02x" (Char.code c))
    done;
    if String.length s>1024 then Buffer.add_string b "... [truncated]";
    str (Buffer.contents b)
let stable (a:Unix.stats) (b:Unix.stats) =
  a.st_dev=b.st_dev && a.st_ino=b.st_ino && a.st_kind=b.st_kind &&
  a.st_size=b.st_size && a.st_mtime=b.st_mtime && a.st_ctime=b.st_ctime
let validate_counts ~mapped_count design =
  let types=match get design "num_cells_by_type" with `Assoc xs -> xs | _ -> invalid_arg "design.num_cells_by_type: expected object" in
  let types=List.map (fun (k,v) -> if k="" then invalid_arg "empty cell-type key"; k,count ("cell type "^k) v) types
    |> List.sort (fun (a,_) (b,_) -> String.compare a b) in
  let total=List.fold_left (fun n (_,v) -> Z.add n v) Z.zero types in
  if not (Z.equal total (count "design.num_cells" (get design "num_cells"))) then invalid_arg "cell-type total disagrees with design.num_cells";
  (match mapped_count with None -> () | Some n -> if not (Z.equal total n) then invalid_arg "cell-type total disagrees with checkpoint mapped cell count");
  List.iter (fun key -> match get design key with `Null -> () | v -> ignore (number key v)) ["area";"sequential_area"];
  types,total
let read ~run_dir ~mapped_count =
  let path=Filename.concat run_dir "06-yosys-synthesis/reports/stat.json" in
  let hash=ref None in
  let diagnostic message = [],[obj ["kind",str "yosys_stat";"path",diagnostic_string path;
    "sha256",(match !hash with None -> J.null | Some s -> str s);
    "evidence_scope",str scope;"message",diagnostic_string message]] in
  try
    let ic = try Some (Unix.openfile path [Unix.O_RDONLY;Unix.O_NONBLOCK] 0 |> Unix.in_channel_of_descr) with
      | Unix.Unix_error ((Unix.ENOENT | Unix.ENOTDIR),_,_) -> None in
    match ic with None -> [],[] | Some ic ->
    let raw=Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
      let before=Unix.fstat (Unix.descr_of_in_channel ic) in
      if before.Unix.st_kind<>Unix.S_REG then invalid_arg "source is not a regular file";
      let raw=really_input_string ic (in_channel_length ic) in
      let after=Unix.fstat (Unix.descr_of_in_channel ic) in
      if not (stable before after && stable after (Unix.stat path)) then invalid_arg "source changed while reading";
      raw) in
    hash:=Some (Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) raw |> Cryptokit.transform_string (Cryptokit.Hexa.encode ()));
    let document=match Evidence_json.parse ~reject_duplicates:true raw with Ok d -> d | Error e -> invalid_arg e in
    let v=Evidence_json.value document in
    let tool=match get v "creator" with `String s when s<>"" -> s | _ -> invalid_arg "creator: expected nonempty tool string" in
    let design=get v "design" in
    let types,total=validate_counts ~mapped_count design in
    [obj ["kind",str "yosys_stat";"path",str path;"sha256",str (Option.get !hash);
      "evidence_scope",str scope;"tool",str tool;"design_area",area "area" design;
      "sequential_area",area "sequential_area" design;"mapped_cell_count",integer total;
      "mapped_cell_types",obj (List.map (fun (k,v) -> k,integer v) types)]],[]
  with
  | Invalid_argument s | Failure s | Sys_error s -> diagnostic s
  | End_of_file -> diagnostic "source truncated while reading"
  | Unix.Unix_error (e,f,p) -> diagnostic (f^" "^p^": "^Unix.error_message e)
