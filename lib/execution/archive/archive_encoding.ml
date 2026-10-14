type runtime = { gzip : string; scratch : string; timeout : float }
exception Gzip_failed of Process_supervisor.result * string
let require b s = if not b then invalid_arg ("Archive_encoding: "^s)
let absolute p = require (not (Filename.is_relative p) && not (String.contains p '\000')) "absolute path required"
let remove p = try Unix.unlink p with Unix.Unix_error (Unix.ENOENT,_,_) -> ()
let with_scratch r f =
  absolute r.gzip; absolute r.scratch;
  require (Float.is_finite r.timeout && r.timeout>0.) "positive finite timeout required";
  let p=Filename.temp_file ~temp_dir:r.scratch "archive-encoding-" ".work" in
  Unix.unlink p; Unix.mkdir p 0o700;
  Fun.protect ~finally:(fun () ->
    Array.iter (fun n -> remove (p^"/"^n)) (Sys.readdir p); Unix.rmdir p) (fun () -> f p)
let diagnostics path =
  try let ic=open_in_bin path in Fun.protect ~finally:(fun () -> close_in_noerr ic)
    (fun () -> let b=Bytes.create 4096 in let n=input ic b 0 4096 in Bytes.sub_string b 0 n)
  with Sys_error _ -> ""
let gzip r dir ~decompress ~input ~output ~max_bytes =
  let stderr=dir^"/stderr" in
  let spec=Process.make ~prog:r.gzip
    ~argv:([r.gzip] @ (if decompress then ["-d";"-c"] else ["-n";"-9";"-c"]) @ ["--";input])
    ~cwd:dir ~environment:["LC_ALL=C"] ~stdout:(Process.File output) ~stderr:(Process.File stderr) in
  let exceeded=ref false in
  let cancel () = match max_bytes with None -> None | Some max ->
    let size=try (Unix.LargeFile.stat output).st_size with Unix.Unix_error (Unix.ENOENT,_,_) -> 0L in
    if size>max then (exceeded:=true;Some Sys.sigterm) else None in
  let result=Process_supervisor.run ~timeout:r.timeout ~cancel spec in
  if not (Process_supervisor.succeeded result) then raise (Gzip_failed (result,diagnostics stderr));
  require (not !exceeded) "decompression byte limit";
  Option.iter (fun max -> require ((Unix.LargeFile.stat output).st_size<=max) "decompression byte limit") max_bytes
let write ~runtime:r ~normalized ~output sources =
  absolute output;
  with_scratch r (fun dir ->
    let tar=dir^"/stream.tar" in
    let oc=open_out_bin tar in
    let members=Fun.protect ~finally:(fun () -> close_out_noerr oc)
      (fun () -> let members=Evidence_tar.write ~normalized oc sources in close_out oc; members) in
    (* Process.File is exclusive. Only remove a file that this invocation owns. *)
    require (not (Sys.file_exists output)) "output already exists";
    let fd=Unix.openfile output [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL] 0o600 in
    let successful=ref false in
    Fun.protect ~finally:(fun () -> Unix.close fd; if not !successful then remove output)
      (fun () ->
        let stderr=dir^"/stderr" in
        let spec=Process.make ~prog:r.gzip ~argv:[r.gzip;"-n";"-9";"-c";"--";tar]
          ~cwd:dir ~environment:["LC_ALL=C"] ~stdout:(Process.Descriptor fd) ~stderr:(Process.File stderr) in
        let result=Process_supervisor.run ~timeout:r.timeout spec in
        if not (Process_supervisor.succeeded result) then raise (Gzip_failed(result,diagnostics stderr));
        successful:=true; members))
let write_input_bundle ~runtime ~output ~(manifest:Evidence_tar.source) ~files =
  require (manifest.name="manifest.json") "manifest name must be manifest.json";
  let sources=manifest::List.sort (fun (a:Evidence_tar.source) b -> String.compare a.name b.name) files in
  let inventory=List.map (fun (s:Evidence_tar.source) ->
    require (s.sha256<>None) "input bundle requires expected hashes";
    s.name,Option.get s.sha256) sources in
  Evidence_tar.validate_inventory inventory;
  write ~runtime ~normalized:true ~output
    (List.map (fun (s:Evidence_tar.source) -> {s with name="bundle/"^s.name}) sources)
let verify ~runtime:r ~limits ~normalized ~expected input =
  absolute input;
  Evidence_tar.validate_inventory expected;
  require (limits.Evidence_tar.max_tar_bytes>=1024L) "invalid tar byte limit";
  with_scratch r (fun dir ->
    let output=dir^"/stream.tar" in
    gzip r dir ~decompress:true ~input ~output ~max_bytes:(Some limits.max_tar_bytes);
    let ic=open_in_bin output in
    Fun.protect ~finally:(fun () -> close_in_noerr ic)
      (fun () -> Evidence_tar.verify ~limits ~normalized ~expected ic))
let verify_input_bundle ~runtime ~limits ~manifest_sha256 ~inventory input =
  let inventory=("manifest.json",manifest_sha256)::List.sort (fun (a,_) (b,_) -> String.compare a b) inventory in
  Evidence_tar.validate_inventory inventory;
  let expected=List.map (fun (n,h) -> "bundle/"^n,h) inventory in
  let members=verify ~runtime ~limits ~normalized:true ~expected input in
  require (List.map (fun (m:Evidence_tar.member) -> m.name) members=List.map fst expected) "input bundle member order";
  members
