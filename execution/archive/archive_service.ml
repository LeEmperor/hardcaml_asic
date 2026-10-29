module E = Evidence_json
let fail = invalid_arg
let get x k = match x with `Assoc xs -> (match List.assoc_opt k xs with
  | Some v -> v | None -> fail ("missing "^k)) | _ -> fail "expected object"
let optional x k = match x with `Assoc xs -> Option.value (List.assoc_opt k xs) ~default:`Null
  | _ -> fail "expected object"
let text = function `String s -> s | _ -> fail "expected path string"
let array = function `List xs -> xs | _ -> fail "expected array"
let read p = E.value (E.read p)
let read_manifest p =
  let document=E.read_regular p in
  let manifest=E.value document and raw=E.raw_bytes document in
  (* Preserve genuine historical evidence decoding when the optional field is
     absent. Presence requires strict ORIGINAL bytes: last-wins decoding cannot
     establish duplicate-free top-level or nested hardware metadata. *)
  (match manifest with
   | `Assoc xs when List.mem_assoc "hardware_variant" xs ->
     (match Identity_json.parse raw with Ok _ -> () | Error e -> fail (Identity_json.error_message e));
     Manifest_metadata.validate manifest
   | _ -> ());
  manifest,Identity_json.sha256_bytes raw
let join root p = if Filename.is_relative p then Filename.concat root p else p
let resolve p =
  let rec walk current left = function
    | [] -> current | ""::xs | "."::xs -> walk current left xs
    | ".."::xs -> walk (Filename.dirname current) left xs
    | x::xs -> let path=Filename.concat current x in
      let link=try if (Unix.lstat path).Unix.st_kind=Unix.S_LNK then Some (Unix.readlink path) else None
        with Unix.Unix_error ((Unix.ENOENT|Unix.ENOTDIR),_,_) -> None in
      match link with None -> walk path left xs | Some target ->
        if left=0 then fail ("symlink loop: "^p);
        walk (if Filename.is_relative target then current else "/") (left-1)
          (String.split_on_char '/' target @ xs) in
  if p="" || String.contains p '\000' then fail "invalid archive path";
  walk "/" 40 (String.split_on_char '/' (join (Sys.getcwd ()) p))
let expanduser p =
  if p="~" || String.starts_with ~prefix:"~/" p then
    let home=try Sys.getenv "HOME" with Not_found -> (Unix.getpwuid (Unix.getuid ())).Unix.pw_dir in
    home ^ String.sub p 1 (String.length p-1)
  else if String.starts_with ~prefix:"~" p then
    let i=try String.index p '/' with Not_found -> String.length p in
    let home=try (Unix.getpwnam (String.sub p 1 (i-1))).Unix.pw_dir
      with Not_found -> fail ("could not determine home directory: "^p) in
    home ^ String.sub p i (String.length p-i) else p
let stat p = try Some (Unix.LargeFile.lstat p) with Unix.Unix_error ((Unix.ENOENT|Unix.ENOTDIR),_,_) -> None
let file p = try (Unix.stat p).Unix.st_kind=Unix.S_REG with Unix.Unix_error ((Unix.ENOENT|Unix.ENOTDIR),_,_) -> false
let directory p = try (Unix.stat p).Unix.st_kind=Unix.S_DIR with Unix.Unix_error ((Unix.ENOENT|Unix.ENOTDIR),_,_) -> false
let children p = Array.to_list (Sys.readdir p) |> List.sort String.compare
let no_links p label =
  let rec walk path = function [] -> () | ""::xs -> walk path xs | x::xs ->
    let path=Filename.concat path x in
    (match stat path with Some st when st.Unix.LargeFile.st_kind=Unix.S_LNK -> fail (label^": "^p) | _ -> ());
    walk path xs in walk "/" (String.split_on_char '/' (join (Sys.getcwd ()) p))
let hash p = match Checkpoint.file_record p with Ok x -> x.sha256 | Error s -> fail s
let regular p label = no_links p label; if not (file p) then fail ("missing regular file: "^p)
let safe s label =
  (try Evidence_tar.validate_name s with Invalid_argument _ | Failure _ -> fail ("unsafe "^label^": "^s)); s
let relative root path =
  let prefix=root^"/" in
  if not (String.starts_with ~prefix path) then fail (path^" is not in the selected run directory");
  safe (String.sub path (String.length prefix) (String.length path-String.length prefix)) "archive path"
let inventory manifest =
  Manifest_metadata.validate manifest;
  let files=List.map (fun x -> let name=safe (text (get x "path")) "bundle path" in
    if name="manifest.json" then fail "manifest.json must not list itself";
    name,text (get x "sha256")) (array (get manifest "files")) in
  let names=Hashtbl.create (List.length files) in
  List.iter (fun (name,sha) ->
    if Hashtbl.mem names name then fail ("duplicate bundle path: "^name);
    if String.length sha<>64 || not (String.for_all (fun c -> (c>='0' && c<='9') || (c>='a' && c<='f')) sha)
      then fail ("invalid SHA-256 for bundle path: "^name);
    Hashtbl.add names name ()) files;
  List.iter (fun (name,_) -> let rec parents p = let parent=Filename.dirname p in
    if parent<>"." then (if Hashtbl.mem names parent then fail ("conflicting bundle paths: "^parent^" and "^name);parents parent) in parents name) files;
  Evidence_tar.validate_inventory files;
  List.iter (fun field -> let sources=List.map text (array (get manifest field)) in
    if List.length sources<>List.length (List.sort_uniq String.compare sources) then fail ("duplicate path in "^field);
    List.iter (fun n -> if not (List.mem_assoc n files) then fail (field^" path is absent from manifest files: "^n)) sources)
    ["synthesis_sources";"simulation_sources"];
  let copies=List.map (fun x -> let source=safe (text (get x "path")) "source input path" in
    let copy=safe (text (get x "copy")) "source input copy" in
    if copy<>"inputs/"^source then fail ("source input copy does not match its source path: "^copy);
    if List.assoc_opt copy files<>Some (text (get x "sha256")) then fail ("source input metadata disagrees with manifest files: "^copy);
    copy) (array (get manifest "source_inputs")) in
  if List.length copies<>List.length (List.sort_uniq String.compare copies) then fail "duplicate source input copy";
  let inputs=List.filter_map (fun (n,_) -> if String.starts_with ~prefix:"inputs/" n then Some n else None) files in
  if List.sort String.compare copies<>List.sort String.compare inputs then fail "source input metadata does not enumerate every inputs/ file";
  List.sort (fun (a,_) (b,_) -> String.compare a b) files
let validate_bundle root record =
  let path=root^"/manifest.json" in regular path "bundle path is a symlink";
  let manifest,manifest_sha256=read_manifest path in
  if manifest_sha256<>text (get record "manifest_sha256") then fail ("bundle manifest does not match the run record: "^path);
  if not (List.mem (get manifest "schema_version") [`Int 1;`Intlit "1"]) || get manifest "adapter"<>`String "LibreLane" then fail ("unsupported bundle schema or adapter: "^path);
  if get manifest "identity"<>get record "build_identity" then fail ("bundle identity does not match the run record: "^path);
  let files=List.map (fun (name,sha256) -> let path=root^"/"^name in regular path "bundle path is a symlink";
    if hash path<>sha256 then fail ("changed bundle file: "^name);
    {Evidence_tar.path;name;sha256=Some sha256}) (inventory manifest) in manifest,files
let bundle_source run record =
  let original=expanduser (text (get record "bundle")) in
  let staged=join run (text (get (get record "outputs") "project")) in
  let candidates=(if directory original then ["original",resolve original] else []) @ ["staged",staged] in
  let rec loop errors = function
    | [] -> fail ("no complete valid immutable bundle is available; "^String.concat "; " (List.rev errors))
    | (kind,root)::xs -> try let manifest,files=validate_bundle root record in kind,root,manifest,files
      with (Invalid_argument _ | Sys_error _ | Unix.Unix_error _ | Yojson.Json_error _) as e ->
        loop ((kind^" bundle "^root^": "^Printexc.to_string e)::errors) xs in loop [] candidates
let check_dirs run = let p=run^"/checks" in
  no_links p "archive selection contains a symlink";
  if not (directory p) then [] else children p |> List.map (Filename.concat p) |> List.filter directory
let checks run = check_dirs run |> List.filter_map (fun d -> let p=d^"/postcheck.json" in
  if file p then (regular p "archive selection contains a symlink"; Some (d,read p)) else None)
let verify run record checks =
  let manifest=join run (text (get (get record "outputs") "project"))^"/manifest.json" in
  regular manifest "staged manifest is a symlink";
  let m,digest=read_manifest manifest in
  if digest<>text (get record "manifest_sha256") then fail ("staged manifest does not match the run record; archive the run that produced it, not a modified copy ("^manifest^")");
  if get m "identity"<>get record "build_identity" then fail "staged manifest identity does not match the run record";
  let flow=join run (text (get (get record "outputs") "flow")) and top=text (get m "top_module") in
  let verified=ref ["manifest_sha256",`String digest] in
  List.iter (fun (d,c) -> let inputs=match optional c "inputs" with `Null -> `Assoc [] | x -> x in
    List.iter (fun (field,p) -> let expected=optional inputs field in
      if expected<>`Null && file p then (
        regular p "archive selection contains a symlink";
        if `String (hash p)<>expected then fail (relative run p^" does not match "^field^" in "^relative run (d^"/postcheck.json")^"; the run directory was modified after the checks ran");
        verified := (field,expected)::List.remove_assoc field !verified))
      ["gds_sha256",flow^"/final/gds/"^top^".gds"; "netlist_sha256",flow^"/final/nl/"^top^".nl.v";
        "testbench_sha256",d^"/testbench.v"];
     (match optional c "artifacts" with
       | `Null -> ()
       | `Assoc artifacts -> List.iter (fun (name,digest) ->
           if not (Filename.is_relative name) || Filename.basename name<>name then fail "unsafe postcheck artifact";
           let path=d ^ "/" ^ name in regular path "postcheck artifact is missing or a symlink";
           if `String (hash path)<>digest then fail ("postcheck artifact changed: " ^ name)) artifacts
       | _ -> fail "malformed postcheck artifact inventory")) checks;
  `Assoc !verified
type inspection = { run_dir:string; reports:Evidence_tar.source list; omitted:string list;
  report_bytes:int64; bundle_source:string; bundle_root:string; bundle_files:Evidence_tar.source list }
type snapshot = { inspection:inspection; record:E.t; manifest:E.t; verified:E.t;
  records:Evidence_tar.source list; record_omissions:string list;
  authoritative_reports:Evidence_tar.source list }

(* Complete the explicit timing-full report closure from the same shallow native
   report namespace advertised by collection. Never turn a stored raw_artifacts
   string into filesystem authority or recursively walk an arbitrary directory. *)
let authoritative_reports ~run_dir ~flow =
  let bounded_children path =
    let d=Unix.opendir path in
    Fun.protect ~finally:(fun () -> Unix.closedir d) (fun () ->
      let rec loop count acc = match Unix.readdir d with
        | "." | ".." -> loop count acc
        | name -> if count>=1024 then fail "authoritative report directory exceeds1024 entries";
          loop (count+1) (name::acc)
        | exception End_of_file -> List.sort String.compare acc in
      loop 0 []) in
  let flow_path=join run_dir flow in
  let flow_relative=relative run_dir flow_path in
  no_links flow_path "authoritative report flow is a symlink";
  if not (directory flow_path) then fail "authoritative report flow is missing";
  let sources=Hashtbl.create 64 and total=ref 0L in
  let admit ~limit path =
    let name=relative run_dir path in
    regular path "authoritative report source is missing or a symlink";
    let size=(Unix.LargeFile.stat path).st_size in
    if size>limit then fail ("authoritative report source byte bound: "^name);
    if not (Hashtbl.mem sources name) then (
      if Hashtbl.length sources>=4096 then fail "authoritative report inventory exceeds4096 sources";
      total:=Int64.add !total size;
      if !total>268435456L then fail "authoritative report inventory exceeds256MiB");
    name,size in
  let retain name path digest =
    let source={Evidence_tar.path;name;sha256=Some digest} in
    (match Hashtbl.find_opt sources name with
     | Some old when old.Evidence_tar.sha256<>source.sha256 -> fail ("authoritative report source changed: "^name)
     | _ -> Hashtbl.replace sources name source);
    `Assoc ["path",`String name;"sha256",`String digest] in
  let metadata path =
    let name,size=admit ~limit:8388608L path in
    let ic=open_in_bin path in
    let raw=Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () -> really_input_string ic (Int64.to_int size)) in
    let digest=Identity_json.sha256_bytes raw in
    if hash path<>digest then fail ("authoritative report metadata changed: "^name);
    raw,retain name path digest in
  let json raw=match E.parse ~reject_duplicates:true raw with Ok j -> E.value j | Error e -> fail e in
  let module M=Hardcaml_asic_flow_domain.Backends.Librelane.Mapping in
  let known=List.map (fun (o:M.occurrence) -> o.step.implementation) M.all |> List.sort_uniq String.compare in
  let positive raw=raw<>"" && String.for_all (function '0'..'9' -> true | _ -> false) raw &&
    (match int_of_string_opt raw with Some n -> n>0 | None -> false) in
  let reports=ref [] in
  List.iter (fun step_name ->
    let step=flow_path^"/"^step_name in
    (match stat step with
     | Some st when st.Unix.LargeFile.st_kind=Unix.S_LNK ->
       (match String.index_opt step_name '-' with
        | Some i when positive (String.sub step_name 0 i) -> fail "authoritative report producer is a symlink"
        | _ -> ())
     | Some st when st.Unix.LargeFile.st_kind=Unix.S_DIR ->
       let report_dir=step^"/reports" in
       (match stat report_dir with
        | None -> ()
        | Some st when st.Unix.LargeFile.st_kind=Unix.S_DIR ->
          let names=bounded_children report_dir |> List.filter (fun name -> Filename.check_suffix name ".rpt" || Filename.check_suffix name ".json") in
          if names<>[] then (
            let slug=match String.index_opt step_name '-' with
              | Some i when positive (String.sub step_name 0 i) -> String.sub step_name (i+1) (String.length step_name-i-1)
              | _ -> fail ("unsupported authoritative report producer: "^step_name) in
            let config_raw,config_ref=metadata (step^"/config.json") in
            let meta=get (json config_raw) "meta" in
            let cls=text (get meta "step") in
            if get meta "librelane_version"<>`String "3.1.0.dev3" || not (List.mem cls known) then
              fail ("unsupported authoritative report metadata: "^step_name);
            let stem=String.lowercase_ascii (String.map (function '.' -> '-' | c -> c) cls) in
            if slug<>stem && not (String.starts_with ~prefix:(stem^"-") slug && positive (String.sub slug (String.length stem+1) (String.length slug-String.length stem-1))) then
              fail ("authoritative report producer/metadata mismatch: "^step_name);
            let state_raw,state_ref=metadata (step^"/state_out.json") in
            (match Backend_state.parse state_raw with Ok _ -> () | Error e -> fail ("incomplete authoritative report State: "^e));
            let runtime_raw,runtime_ref=metadata (step^"/runtime.txt") in
            ignore (Timing_analysis.native_runtime_seconds runtime_raw);
            List.iter (fun name ->
              let path=report_dir^"/"^name in
              let relative,size=admit ~limit:33554432L path in
              let ref_=retain relative path (hash path) in
              reports:=`Assoc ["source",ref_;"bytes",`Intlit (Int64.to_string size);
                "producer",`Assoc ["class_id",`String cls;"directory",`String (flow_relative^"/"^step_name);
                  "config",config_ref;"state_out",state_ref;"runtime",runtime_ref]]::!reports) names)
        | Some _ -> fail "authoritative report directory is linked or not a directory")
     | _ -> ())) (bounded_children flow_path);
  let reports=List.rev !reports in
  (* A cached advertisement can require a report to exist, but cannot authorize
     another path, an absolute path, a symlink, or a directory traversal. *)
  let cache=run_dir^"/results.json" in
  if file cache then (
    regular cache "advertised report inventory is a symlink";
    if (Unix.LargeFile.stat cache).st_size>8388608L then fail "advertised report metadata exceeds8MiB";
    match optional (read cache) "raw_artifacts" with
    | `Null -> ()
    | `List rows ->
      if List.length rows>8192 then fail "advertised report inventory exceeds8192 entries";
      List.iter (fun row ->
        let name=safe (text row) "advertised raw artifact" in
        let pre=flow_relative^"/" in
        if String.starts_with ~prefix:pre name then (
          let rest=String.sub name (String.length pre) (String.length name-String.length pre) in
          match String.split_on_char '/' rest with
          | [_;"reports";leaf] when Filename.check_suffix leaf ".rpt" || Filename.check_suffix leaf ".json" ->
            if not (List.exists (fun r -> get (get r "source") "path"=`String name) reports) then
              fail ("advertised authoritative report is missing or unsupported: "^name)
          | _ -> ())) rows
    | _ -> fail "malformed advertised raw artifact inventory");
  let sources=Hashtbl.fold (fun _ source acc -> source::acc) sources [] |> List.sort (fun a b -> String.compare a.Evidence_tar.name b.name) in
  sources,`Assoc ["schema_version",`Int 1;"profile",`String "librelane-native-direct-reports-v1";
    "reports",`List reports;"source_count",`Int (List.length sources);"source_bytes",`Intlit (Int64.to_string !total)]

let acquire ~verb ~include_records ~run_dir =
  let run_dir=resolve run_dir in
  regular (run_dir^"/run.json") "archive record is a symlink";
  let run_document=E.read (run_dir^"/run.json") in
  let record=E.value run_document and run_hash=Identity_json.sha256_bytes (E.raw_bytes run_document) in
  if get record "status"<>`String "completed" then fail ("run status is "^text (get record "status")^", not completed; "^verb^" a finished run");
  let checks=checks run_dir in
  let verified=verify run_dir record checks in
  let bundle_source,bundle_root,manifest,bundle_files=bundle_source run_dir record in
   let flow=text (get (get record "outputs") "flow") in
   let physical=match optional manifest "macro_contract" with `Assoc xs -> List.assoc_opt "execution" xs=Some (`String "fresh_full") | _ -> false in
   let physical_files=if physical then (
     let evidence=read (run_dir ^ "/physical-checks.json") in
     if `String (hash (run_dir ^ "/physical-checks.json"))<>get record "physical_checks_sha256" then fail "physical checker record changed";
     let artifacts=match get evidence "artifacts" with `Assoc xs -> xs | _ -> fail "physical artifacts missing" in
     List.map (fun (path,digest) ->
       if not (Filename.is_relative path) || List.mem ".." (String.split_on_char '/' path) then fail "unsafe physical artifact";
       let path=join run_dir (join flow path) in
       regular path "physical artifact is missing or a symlink";
       if `String (hash path)<>digest then fail "physical artifact changed";
       path) artifacts @ [run_dir ^ "/physical-checks.json";run_dir ^ "/physical-checks.log";run_dir ^ "/project/physical-runtime.py"] @
       (if optional record "macro_flow_sha256"=`Null then [] else (
         if optional record "macro_flow_sha256"<>`String (hash (run_dir ^ "/project/macro-flow.py")) then fail "macro reader adapter changed";
         [run_dir ^ "/project/macro-flow.py"])))
     else [] in
   let resource_files=match optional (if file (run_dir^"/results.json") then read (run_dir^"/results.json") else `Assoc []) "resource_evidence" with
     | `Null -> []
     | evidence ->
       (match Resource_evidence.verify_sources ~context:record ~run_dir evidence with Ok () -> () | Error e -> fail e);
       (* Source-aware replay validates the assertions, not acceptance: genuine
          failed reconciliations remain archivable with all advertised bytes. *)
       array (get evidence "evidence_refs") |> List.map (fun ref_ ->
         let name=safe (text (get ref_ "path")) "resource evidence path" in
         let path=join run_dir name in regular path "resource evidence is missing or a symlink";
         if `String (hash path)<>get ref_ "sha256" then fail ("resource evidence changed: "^name);path) in
   let timing_files=if not (Timing_intent_flow.expected manifest || optional record "timing_intent_expected"=`Bool true || optional record "timing_physical_expected"=`Bool true) then [] else
     (match Timing_intent_flow.source_files ~context:record ~run_dir () with
      | Error e -> fail ("timing intent archive: "^e)
       | Ok refs -> List.map (fun r -> join run_dir (text (get r "path"))) refs) in
   let report_sources,report_inventory=if Timing_physical_flow.enabled manifest && optional record "requested_stage"=`String "full" then
     authoritative_reports ~run_dir ~flow else [],`Null in
   let verified=if report_inventory=`Null then verified else match verified with
     | `Assoc fields -> `Assoc (("authoritative_report_inventory",report_inventory)::fields)
     | _ -> assert false in
   let candidates=List.map (join run_dir) (["execution.log";"project/src/config.json"] @
    List.map (fun p -> join flow p) ["final/metrics.csv";"final/metrics.json";"final/sdc";"final/gds";"final/nl";"06-yosys-synthesis";"55-openroad-stapostpnr"])
       @ physical_files @ resource_files @ timing_files
     @ List.concat_map (fun d -> List.map (Filename.concat d) (["postcheck.log";"testbench.v";"tt/precheck/reports"] @
        if physical || Timing_physical_flow.enabled manifest then List.filter (fun name -> String.starts_with ~prefix:"model-" name || List.mem name
         ["stdcell-functional.v";"stdcell-vendor.v";"replay-models.json";"physical-runtime.py";"tt-adaptation.json";"replay-trace.txt"])
         (children d) else [])) (check_dirs run_dir) in
  let source path name = {Evidence_tar.path;name;sha256=Some (hash path)} in
  let rec walk path = no_links path "archive selection contains a symlink";
    match stat path with
    | Some st when st.Unix.LargeFile.st_kind=Unix.S_DIR ->
      List.concat_map (fun n -> walk (Filename.concat path n)) (children path)
    | Some st when st.Unix.LargeFile.st_kind=Unix.S_REG -> [path]
    | Some _ -> fail ("archive selection is not regular: "^path) | None -> [] in
  let reports,omitted=List.fold_left (fun (selected,omitted) p ->
    let name=relative run_dir p in let files=walk p |> List.sort String.compare in
    selected @ List.map (fun p -> source p (relative run_dir p)) files,
     omitted @ if files=[] then [name] else []) ([],[]) candidates in
   let reports=List.fold_left (fun selected (source:Evidence_tar.source) ->
      match List.find_opt (fun (prior:Evidence_tar.source) -> prior.name=source.name) selected with
      | Some prior -> if prior.sha256<>source.sha256 then fail ("archive source changed during inventory: "^source.name);selected
      | None -> selected@[source]) [] (reports @ report_sources) in
  let record_omissions=ref [] in
  let records=if not include_records then [] else List.filter_map (fun name -> let p=run_dir^"/"^name in
    if file p then (regular p "archive record is a symlink"; Some (source p name))
    else (record_omissions:= !record_omissions@[name]; None)) ["run.json";"results.json";"preflight.json"]
    @ List.map (fun (d,_) -> source (d^"/postcheck.json")
      (if List.length checks=1 then "postcheck.json" else "postcheck-"^Filename.basename d^".json")) checks in
  let records=List.map (fun (s:Evidence_tar.source) -> if s.name="run.json" then {s with sha256=Some run_hash} else s) records in
  let report_bytes=List.fold_left (fun n (s:Evidence_tar.source) -> Int64.add n (Unix.LargeFile.stat s.path).st_size) 0L reports in
  {inspection={run_dir;reports;omitted;report_bytes;bundle_source;bundle_root;bundle_files};
   record;manifest;verified;records;record_omissions= !record_omissions;authoritative_reports=report_sources}
let inspect ~run_dir = (acquire ~verb:"list" ~include_records:false ~run_dir).inspection
let rec mkdir p = try Unix.mkdir p 0o777 with
  | Unix.Unix_error (Unix.ENOENT,_,_) -> mkdir (Filename.dirname p); mkdir p
  | Unix.Unix_error (Unix.EEXIST,_,_) -> if not (directory p) then fail ("not a directory: "^p)
let rec remove p = match stat p with None -> () | Some st ->
  if st.Unix.LargeFile.st_kind=Unix.S_DIR then (Unix.chmod p (st.st_perm lor 0o700);
    List.iter (fun n -> remove (Filename.concat p n)) (children p); Unix.rmdir p) else Unix.unlink p
let copy source target =
  let ic=open_in_bin source in Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
    let fd=Unix.openfile target [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL] 0o600 in
    let oc=Unix.out_channel_of_descr fd in Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
      let buf=Bytes.create 65536 in let rec loop () = let n=input ic buf 0 (Bytes.length buf) in
        if n>0 then (output oc buf 0 n;loop ()) in loop ();close_out oc));
  let st=Unix.stat source in Unix.chmod target st.st_perm; Unix.utimes target st.st_atime st.st_mtime
let rec copy_user source target = match (Unix.lstat source).Unix.st_kind with
  | Unix.S_LNK -> Unix.symlink (Unix.readlink source) target
  | Unix.S_DIR -> Unix.mkdir target 0o700; List.iter (fun n -> copy_user (Filename.concat source n) (Filename.concat target n)) (children source);
    let st=Unix.stat source in Unix.chmod target st.st_perm; Unix.utimes target st.st_atime st.st_mtime
  | Unix.S_REG -> copy source target
  | _ -> fail ("cannot preserve special user entry: "^source)
let generated=["archive.json";"input-bundle.sha256";"input-bundle.tar.gz";"manifest.json";"preflight.json";"reports.tar.gz";"results.json";"run.json";"postcheck.json"]
let now () = let time=Unix.gettimeofday () in let sec=floor time in let t=Unix.gmtime sec in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d.%06d+00:00" (t.tm_year+1900) (t.tm_mon+1) t.tm_mday t.tm_hour t.tm_min t.tm_sec (int_of_float ((time-.sec)*.1000000.))
let owned n = List.mem n generated || (String.starts_with ~prefix:"postcheck-" n && Filename.check_suffix n ".json")
let private_dir parent prefix =
  let rec loop () = let p=Filename.temp_file ~temp_dir:parent prefix "" in
    Unix.unlink p; try Unix.mkdir p 0o700;p with Unix.Unix_error (Unix.EEXIST,_,_) -> loop () in loop ()
type publication={output:string;reports:string;selected:string list;omitted:string list;record:E.t}
external promote : string -> string -> unit = "hardcaml_asic_rename_noreplace"
let publish ?(rename : string -> string -> unit = fun a b -> Unix.rename a b) ~runtime ~run_dir ~output ~force () =
  let snap=acquire ~verb:"archive" ~include_records:true ~run_dir in let i=snap.inspection in
  let output=resolve output in
  let populated () = match stat output with None -> false | Some st ->
    if st.Unix.LargeFile.st_kind<>Unix.S_DIR then fail ("archive output is not a directory: "^output);
    children output<>[] in
  let check_output () = if populated () && not force then fail (output^" already has files; use --force to replace them") in
  check_output ();
  let parent=Filename.dirname output and base=Filename.basename output in mkdir parent;
  let lock=parent^"/."^base^".archive-lock" in Unix.mkdir lock 0o700;
  Fun.protect ~finally:(fun () -> Unix.rmdir lock) (fun () ->
    check_output ();
    let staging=private_dir parent ("."^base^".archive-") in
    Fun.protect ~finally:(fun () -> remove staging) (fun () ->
      let manifest_source={Evidence_tar.path=i.bundle_root^"/manifest.json";name="manifest.json";
        sha256=Some (text (get snap.record "manifest_sha256"))} in
      List.iter (fun (s:Evidence_tar.source) -> regular s.path "archive record is a symlink";
        copy s.path (staging^"/"^s.name);
        if Some (hash (staging^"/"^s.name))<>s.sha256 then fail ("record changed while copying: "^s.name)) (manifest_source::snap.records);
      let reports=staging^"/reports.tar.gz" in
      ignore (Archive_encoding.write ~runtime ~normalized:false ~output:reports i.reports);
      let input=staging^"/input-bundle.tar.gz" in
      let members=Archive_encoding.write_input_bundle ~runtime ~output:input ~manifest:manifest_source ~files:i.bundle_files in
      let inventory=List.map (fun (s:Evidence_tar.source) -> s.name,Option.get s.sha256) i.bundle_files in
      let max_member_bytes=List.fold_left (fun n (m:Evidence_tar.member) -> Int64.max n m.bytes) 0L members in
      (* Bound the reopen by actual encoded inventory, including PAX/header/block
         overhead. It is not an unconstrained decompression of arbitrary input. *)
      let max_tar_bytes=List.fold_left (fun n (m:Evidence_tar.member) ->
        Int64.add n (Int64.add m.bytes (Int64.of_int (4096+2*String.length m.name)))) 10240L members in
      let limits={Evidence_tar.max_members=List.length members;max_member_bytes;
        max_tar_bytes;max_pax_bytes=1048576;max_name_bytes=1048576} in
      ignore (Archive_encoding.verify_input_bundle ~runtime ~limits ~manifest_sha256:(Option.get manifest_source.sha256) ~inventory input);
       ignore (verify i.run_dir snap.record (checks i.run_dir));
       List.iter (fun (source:Evidence_tar.source) ->
         regular source.path "authoritative report source changed during publication";
         if Some (hash source.path)<>source.sha256 then fail ("authoritative report source changed during publication: "^source.name))
         snap.authoritative_reports;
      let digest=hash input in
      Result_store.save_bytes (staging^"/input-bundle.sha256") (digest^"  input-bundle.tar.gz\n");
      let strings xs=`List (List.map (fun s -> `String s) xs) and str s=`String s in
      let bytes p=`Intlit (Int64.to_string (Unix.LargeFile.stat p).st_size) in
      let omitted=i.omitted@snap.record_omissions in
      let records=children staging |> List.filter (fun n -> Filename.check_suffix n ".json") in
      let record=`Assoc ["schema_version",`Int 1;"run_id",get snap.record "run_id";"build_identity",get snap.record "build_identity";
        "created_at",str (now ());
        "source_run",str i.run_dir;"archive",str "reports.tar.gz";"archive_bytes",bytes reports;
        "input_bundle",`Assoc ["archive",str "input-bundle.tar.gz";"archive_bytes",bytes input;"sha256",str digest;
          "root",str "bundle";"source",str i.bundle_source;"manifest_sha256",get snap.record "manifest_sha256";
          "build_identity",get snap.manifest "identity";"manifest_files_verified",`Int (List.length i.bundle_files);
          "source_inputs_verified",`Int (List.length (array (get snap.manifest "source_inputs")));
          "members",strings (List.map (fun (m:Evidence_tar.member) -> m.name) members)];
        "verified",snap.verified;"members",strings (List.sort String.compare (List.map (fun (s:Evidence_tar.source) -> s.name) i.reports));
        "omitted",strings (List.sort String.compare omitted);"records",strings records] in
      Result_store.save_bytes (staging^"/archive.json") (E.record_bytes record);
      check_output ();
      if directory output then List.iter (fun n -> if not (owned n) then copy_user (output^"/"^n) (staging^"/"^n)) (children output);
      let backup=private_dir parent ("."^base^".archive-backup-") in Unix.rmdir backup;
      let moved=ref false in
      (try if directory output then (rename output backup;moved:=true);
        (* For absent destinations, no-replace also protects against noncooperating
           writers creating a destination after the last check. *)
        if !moved then rename staging output else promote staging output
       with e -> if !moved && stat output=None then rename backup output; raise e);
      if !moved then (try remove backup with Sys_error _ | Unix.Unix_error _ -> ());
      {output;reports=output^"/reports.tar.gz";selected=List.map (fun (s:Evidence_tar.source) -> s.name) i.reports;omitted;record}))
