open Hardcaml_asic_execution
module J = Identity_json
module S = Result_store
let get = function Ok x -> x | Error e -> failwith (J.error_message e)
let str s = get (J.string s)
let obj f = get (J.object_ f)
let main request =
  let f = match request with J.Object f -> f | _ -> failwith "object required" in
  let value k = List.assoc k f in
  let string k = match value k with J.String s -> s | _ -> failwith k in
  let clock () = match value "time" with J.Float n -> n | J.Integer n -> float_of_string n | _ -> failwith "time" in
  let ids = ref (match List.assoc_opt "ids" f with Some (J.Array xs) -> xs | _ -> []) in
  let id_factory () = match !ids with J.String s :: rest -> ids := rest; s | _ -> failwith "ids exhausted" in
  let attempts = match List.assoc_opt "attempts" f with Some (J.Integer n) -> int_of_string n | _ -> 8 in
  match string "op" with
  | "allocate" ->
    let a = S.allocate ~clock ~id_factory ~max_attempts:attempts (string "path") in
    obj ["identity", str a.identity; "directory", str a.directory; "created_at", str a.created_at]
  | "random" ->
    let a = S.allocate (string "path") in
    obj ["identity", str a.identity; "directory", str a.directory; "created_at", str a.created_at]
  | "save" -> S.save_json (string "path") (value "value"); J.bool true
  | "read" -> get (S.read_json (string "path"))
  | "validate" -> str (S.validate_output (string "path"))
  | "pending" -> S.pending_report ~provenance:(value "provenance") ~bundle:(string "bundle") ()
  | "classify" ->
    (match S.classify_report (value "value") with
     | Ok (status, code) -> obj ["status", str (S.status_name status); "exit_code", get (J.integer (string_of_int code)); "result", value "value"]
     | Error e -> failwith e)
  | "begin" ->
    let a, report, receipt_path, receipt = S.begin_preflight ~clock ~id_factory ~max_attempts:attempts
        ~results_root:(string "path") ~bundle:(string "bundle") () in
    obj ["directory", str a.directory; "report_path", str report; "receipt_path", str receipt_path; "receipt", receipt]
  | "begin_fail" ->
    let save _ _ = failwith "injected receipt publication failure" in
    ignore (S.begin_preflight ~clock ~id_factory ~save ~results_root:(string "path") ~bundle:(string "bundle") ());
    failwith "unexpected success"
  | "finish" ->
    S.finish_receipt (value "value") ~status:S.Failed ~exit_code:1 ~ended_at:(string "ended_at") ~error:(string "error") ()
  | "write_many" ->
    for _ = 1 to 100 do S.save_json (string "path") (value "value") done; J.bool true
  | _ -> failwith "unknown operation"
let () =
  try
    while true do
      let line = read_line () in
      let result = try main (get (J.parse line)) with exn -> obj ["error", str (Printexc.to_string exn)] in
      print_endline (J.canonical result)
    done
  with End_of_file -> ()
