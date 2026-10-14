open Hardcaml_asic_execution
module J = Identity_json
module C = Checkpoint
let codec = function Ok x -> x | Error e -> failwith (J.error_message e)
let unwrap = function Ok x -> x | Error s -> failwith s
let get j k = match j with J.Object xs -> List.assoc k xs | _ -> failwith "object required"
let string = function J.String s -> s | _ -> failwith "string required"
let optional j k = match j with J.Object xs -> List.assoc_opt k xs | _ -> None
let stage j = let name = string j in
  match List.find_opt (fun s -> C.Stage.to_string s = name) C.Stage.all with
  | Some s -> s | None -> failwith "unknown boundary"
let () =
  let output = try
    let q = codec (J.parse (read_line ())) in
    let path = string (get q "path") in
    let t = match string (get q "op") with
      | "read" -> unwrap (C.read path)
      | "parse" -> unwrap (C.of_json (get q "manifest"))
      | "validate" ->
        let restart = optional q "restart" = Some (J.bool true) in
        let check_external = optional q "check_external" <> Some (J.bool false) in
        let restart_to = Option.map stage (optional q "restart_to") in
        let location = Option.map string (optional q "location") in
        unwrap (C.validate ~restart ?restart_to ~check_external ?location
          ~compatibility:(get q "compatibility") path)
      | _ -> failwith "unknown operation" in
    assert (J.canonical (C.to_json t) = J.canonical (C.to_json (unwrap (C.parse (J.canonical (C.to_json t))))));
    assert (t.identity <> "" && t.files <> [] && t.external_files <> []);
    List.iter (fun (name, expected) ->
      let actual = unwrap (C.file_record (Filename.concat path name)) in
      assert (actual.sha256 = expected.C.sha256 && actual.bytes = expected.bytes))
      (match string (get q "op") with "parse" -> [] | _ -> t.files);
    C.inspection ~compatibility_source:`Expected t
  with Failure s -> codec (J.object_ ["error", codec (J.string s)]) in
  print_endline (J.canonical output)
