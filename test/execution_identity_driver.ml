module J = Hardcaml_asic_execution.Identity_json
let get = function Ok x -> x | Error e -> failwith (J.error_message e)
let () =
  (* Exercise smart constructors and closed-object helpers, not only parsing. *)
  let v = get (J.object_ ["identity", get (J.string "signature");
                         "value", J.array [get (J.integer "-0"); get (J.float (-0.))]]) in
  assert (J.canonical (get (J.unsigned v ~field:"identity")) = "{\"value\":[0,-0.0]}");
  ignore (get (J.exact_object v ~fields:["value"; "identity"]));
  assert (Result.is_error (J.exact_object v ~fields:["value"]));
  assert (Result.is_error (J.exact_object v ~fields:["value"; "identity"; "extra"]));
  assert (Result.is_error (J.exact_object J.null ~fields:[]));
  assert (Result.is_error (J.exact_object v ~fields:["value"; "value"]));
  assert (Result.is_error (J.unsigned v ~field:"absent"));
  assert (Result.is_error (J.unsigned J.null ~field:"identity"));
  assert (Result.is_error (J.object_ ["a", J.null; "a", J.bool true]));
  assert (Result.is_error (J.integer "01"));
  assert (Result.is_error (J.integer ""));
  assert (Result.is_error (J.string "\255"));
  assert (Result.is_error (J.parse "\"\255\""));
  assert (Result.is_error (J.parse "\"\192\128\""));
  assert (Result.is_error (J.parse "\"\237\160\128\""));
  assert (Result.is_error (J.float infinity));
  assert (Result.is_error (J.float neg_infinity));
  assert (Result.is_error (J.float nan));
  assert (J.canonical (get (J.float 0.1)) = "0.1");
  assert (J.sha256_bytes "abc" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  try while true do
    let line = read_line () in
    let result =
      if String.starts_with ~prefix:"UNSIGNED:" line then (
        let split = String.index line '\t' in
        let field = String.sub line 9 (split - 9) in
        let text = String.sub line (split + 1) (String.length line - split - 1) in
        match J.parse text with Error e -> Error e | Ok v -> J.unsigned v ~field)
      else if String.starts_with ~prefix:"BITS:" line then
        J.float (Int64.float_of_bits (Int64.of_string ("0x" ^ String.sub line 5 (String.length line - 5))))
      else J.parse line
    in
    (match result with
     | Error e -> Printf.printf "ERR:%s\n" (J.error_message e)
     | Ok v -> Printf.printf "%s\t%s\n" (J.canonical v) (J.identity v))
  done with End_of_file -> ()
