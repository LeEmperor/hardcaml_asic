open Hardcaml_asic_execution
module J = Identity_json
module P = Checkpoint_publisher
let codec = function Ok x -> x | Error e -> failwith (J.error_message e)
let get j k = match j with J.Object xs -> List.assoc k xs | _ -> assert false
let string = function J.String s -> s | _ -> assert false
let str s = codec (J.string s)
let obj xs = codec (J.object_ xs)
let write p s = let oc = open_out_bin p in output_string oc s; close_out oc
let () =
  let q = codec (J.parse (input_line stdin)) in
  let candidate = string (get q "candidate") and store = string (get q "store") in
  let mode = string (get q "mode") in
  let boundary = List.find (fun s -> Hardcaml_asic.Flow.Stage.to_string s = string (get q "boundary")) Hardcaml_asic.Flow.Stage.all in
  let called = ref false in
  let callback (r:P.runtime_request) =
    called := true;
    assert (not (Sys.file_exists r.location));
    assert ((Unix.stat r.staging).Unix.st_perm = 0o700);
    let mutate p = write p "mutated" in
    (match mode with
    | "fail" -> ()
    | "interrupt" -> ()
    | "raise" -> raise (Sys_error "callback exception retained")
    | "break" -> raise Sys.Break
    | "cleanup-fail" -> Unix.rename r.staging (r.staging ^ ".retained")
    | "mutate" -> mutate (Filename.concat r.staging "views/00001-netlist")
    | "metadata" -> mutate (Filename.concat r.staging "segment.json")
    | "source" -> mutate (string (get q "source"))
    | "host" -> mutate (string (get q "host"))
    | "candidate" -> mutate (Filename.concat candidate "state.json")
    | "extra" -> write (Filename.concat r.staging "extra") "extra"
    | "empty-dir" -> Unix.mkdir (Filename.concat r.staging "empty") 0o700
    | "symlink" -> Unix.symlink "/missing" (Filename.concat r.staging "extra")
    | "resign" ->
      let m = codec (Result_store.read_json (Filename.concat r.staging "manifest.json")) in
      let xs = match codec (J.unsigned m ~field:"identity") with J.Object xs -> xs | _ -> assert false in
      let unsigned = obj (("metrics", obj []) :: List.remove_assoc "metrics" xs) in
      let xs = match unsigned with J.Object xs -> xs | _ -> assert false in
      write (Filename.concat r.staging "manifest.json") (J.canonical (obj (("identity", str (J.identity unsigned)) :: xs)))
    | "collision" -> Unix.mkdir r.location 0o755
    | "file-collision" -> write r.location "user-owned collision"
    | "link-collision" -> Unix.symlink (string (get q "host")) r.location
    | "pause" -> Unix.sleepf 0.15
    | "ok" -> ()
    | _ -> failwith "unknown callback mode");
    match mode with "fail" | "cleanup-fail" -> P.Failed "runtime failed explicitly"
      | "interrupt" -> P.Interrupted Sys.sigterm | _ -> P.Validated in
  let validate_runtime = if mode = "missing" then None else Some callback in
  let result = try
    match P.publish ~name:(fun () -> string (get q "name")) ?validate_runtime
      ~candidate ~store ~boundary ~compatibility:(get q "compatibility") () with
    | Ok p -> obj ["path", str p.path; "summary", P.to_json p; "manifest", Checkpoint.to_json p.checkpoint;
        "runtime", str (match p.runtime_validation with `Validated -> "validated" | `Not_required -> "not_required")]
    | Error e -> obj ["error", str (P.error_message e);
        "kind", str (match e with P.Runtime_failed _ -> "runtime_failed" | P.Runtime_interrupted _ -> "interrupted"
          | P.Cleanup_failed _ -> "cleanup_failed" | P.Publication_failed _ -> "publication_failed")]
    with exn -> obj ["exception", str (Printexc.to_string exn)] in
  let xs = match result with J.Object xs -> xs | _ -> assert false in
  print_endline (J.canonical (obj (("called", J.bool !called) :: xs)))
