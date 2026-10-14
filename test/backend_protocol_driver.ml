module J = Hardcaml_asic_execution.Identity_json
module P = Hardcaml_asic_execution.Backend_protocol
let ( let* ) = Result.bind
let codec = function Ok x -> Ok x | Error e -> Error (J.error_message e)
let run text =
  let* json = codec (J.parse text) in
  let* f = codec (J.exact_object json ~fields:["request"; "reply"]) in
  let* request = P.request_of_json (List.assoc "request" f) in
  let* output = match List.assoc "reply" f with
    | J.Null -> Ok (P.request_to_json request)
    | value -> let* reply = P.reply_of_json ~request value in Ok (P.reply_to_json reply) in
  Ok (J.canonical output)
let () =
  let get = function Ok v -> v | Error e -> failwith e in
  let request = get (P.make_request ~operation:P.Execute_segment ~request_id:"api"
    ~reply_path:"/tmp/reply" ~boundary:P.Stage.Synthesis ~checkpoint:None
    ~source_boundary:None ~candidate:"/tmp/candidate" ~project:"/tmp/project"
    ~pdk_root:"/tmp/pdk" ~tag:"api" ~bridge_sha256:(String.make 64 '0')) in
  assert (get (P.parse_request (J.canonical (P.request_to_json request))) = request);
  assert (Result.is_error (P.make_request ~operation:P.Execute_segment ~request_id:"\255"
    ~reply_path:"/tmp/reply" ~boundary:P.Stage.Synthesis ~checkpoint:None
    ~source_boundary:None ~candidate:"/tmp/candidate" ~project:"/tmp/project"
    ~pdk_root:"/tmp/pdk" ~tag:"api" ~bridge_sha256:(String.make 64 '0')));
  try while true do
    match run (read_line ()) with
    | Ok output -> print_endline output
    | Error error -> print_endline ("ERR:" ^ error)
  done with End_of_file -> ()
