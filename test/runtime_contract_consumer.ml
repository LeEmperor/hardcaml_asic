open Hardcaml_asic_execution
module J = Identity_json
module R = Runtime_contract
module E = Runtime_evidence
let unwrap = function Ok x -> x | Error e -> failwith e
let json = function Ok x -> x | Error e -> failwith (J.error_message e)
let obj xs = json (J.object_ xs)
let get j k = match j with J.Object xs -> Option.value (List.assoc_opt k xs) ~default:J.null | _ -> failwith "object"
let str = function J.String x -> x | _ -> failwith "string"
let flag j k = match get j k with J.Null -> false | J.Bool x -> x | _ -> failwith "flag"
let run j =
  let contract () = unwrap (R.of_json (get j "contract")) in
  let container = match get j "container" with J.Null -> None | x -> Some x in
  match str (get j "op") with
  | "requested" -> R.to_json (unwrap (R.policy_from_requested (get j "value")))
  | "lock" -> R.to_json (unwrap (R.policy_from_lock (get j "value")))
  | "contract" -> R.to_json (contract ())
  | "parse" -> R.to_json (unwrap (R.parse (str (get j "raw"))))
  | "metadata" ->
    let m = unwrap (E.parse_metadata ~host:(flag j "host") (str (get j "raw"))) in
    assert (get m.raw "python_version" = json (J.string m.python_version));
    E.metadata_to_json m
  | "evaluate" -> R.evaluation_to_json (unwrap (R.evaluate (contract ()) ~host:(get j "host")
      ?container ~native:(flag j "native") ~allow_python_mismatch:(flag j "waiver") ()))
  | "readiness" ->
    let e = unwrap (E.evaluate_observations (contract ()) ~host:(get j "host") ?container
      ~native:(flag j "native") ~allow_python_mismatch:(flag j "waiver") ()) in
    assert (E.policy_satisfied e = (get (E.evaluation_to_json e) "issues" = J.array []));
    assert (E.issues e = [] || not (E.policy_satisfied e));
    E.evaluation_to_json e
  | "container" -> E.evaluation_to_json (unwrap (E.evaluate_container (contract ()) (get j "container")))
  | "binding" -> Execution_transport.to_json (unwrap (E.binding_from_observation
      ~native:(flag j "native") (get j "value")))
  | "docker_binding" -> Execution_transport.to_json (unwrap (E.docker_binding
      ~declared_ref:(str (get j "ref")) ~executable:(str (get j "executable"))
      ~info:(get j "info") ~inspection:(get j "inspection") ~observation:(get j "value")))
  | "image" | "engine" as op ->
    let d = match unwrap (Execution_transport.of_json (get j "binding")) with
      | Execution_transport.Docker d -> d | _ -> failwith "Docker required" in
    if op = "image" then (unwrap (E.verify_image d ~actual_id:(str (get j "value"))); J.bool true)
    else unwrap (E.verify_engine d (get j "value"))
  | _ -> failwith "op"
let () =
  try while true do
    let line = read_line () in
    let reply = try run (json (J.parse line)) with Failure e | Invalid_argument e ->
      obj ["error", json (J.string e)] in
    print_endline (J.canonical reply)
  done with End_of_file -> ()
