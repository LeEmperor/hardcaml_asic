module J = Identity_json
module R = Runtime_contract
module T = Execution_transport
let unwrap = function Ok x -> x | Error e -> invalid_arg (J.error_message e)
let obj x = unwrap (J.object_ x)
let s x = unwrap (J.string x)
let protect f = try Ok (f ()) with Invalid_argument e -> Error e
let fields = function J.Object xs -> xs | _ -> invalid_arg "expected observation object"
let get j k = Option.value (List.assoc_opt k (fields j)) ~default:J.null
type tcl = { ready : bool; version : string option; error : string option }
type metadata =
  { python_version : string; librelane_version : string option
  ; requires_python : string option; metadata_error : string option
  ; tcl : tcl option; raw : J.t }
let metadata ?(host=false) j = protect (fun () ->
  let fs = fields j in
  let nullable j key = match List.assoc_opt key (fields j) with
    | Some (J.String _ | J.Null) -> ()
    | _ -> invalid_arg ("invalid or missing metadata: " ^ key) in
  List.iter (nullable j) ["python_version"; "librelane_version"; "requires_python"; "metadata_error"];
  (match List.assoc "python_version" fs with J.String _ -> () | _ -> invalid_arg "missing Python version");
  if host then (
    let tcl = get j "tcl" in
    (match get tcl "ready" with J.Bool _ -> () | _ -> invalid_arg "missing Tcl readiness");
    List.iter (nullable tcl) ["version"; "error"]);
  let string = function J.String x -> x | _ -> assert false in
  let optional j key = match get j key with J.String x -> Some x | _ -> None in
  let tcl = if not host then None else
    let value = get j "tcl" in
    Some {ready=(get value "ready" = J.bool true); version=optional value "version";
          error=optional value "error"} in
  {python_version=string (get j "python_version"); librelane_version=optional j "librelane_version";
   requires_python=optional j "requires_python"; metadata_error=optional j "metadata_error";
   tcl; raw=j})
let parse_metadata ?host text = match J.parse text with
  | Error e -> Error (J.error_message e) | Ok j -> metadata ?host j
let metadata_to_json j = j.raw
type evaluation = J.t
let evaluation_to_json j = j
let rows key j = match get j key with J.Array xs -> xs | _ -> assert false
let comparisons j = rows "comparisons" j
let issues j = rows "issues" j
let waivers j = rows "waivers" j
let policy_satisfied j = get j "issues" = J.array []
let evaluate_observations t ~host ?container ?native ?allow_python_mismatch () =
  match R.evaluate t ~host ?container ?native ?allow_python_mismatch () with
  | Error e -> Error e
  | Ok policy -> protect (fun () ->
    let tcl = get host "tcl" in
    let ready = if tcl = J.null && not (List.mem_assoc "tcl" (fields host))
      then J.null else get tcl "ready" in
    let rows = List.map (fun (field, expected, actual) ->
      obj ["role", s "host"; "field", s field; "expected", expected; "actual", actual;
           "status", s (if actual = expected then "pass" else "fail")])
      ["librelane_version", s t.librelane, get host "librelane_version";
       "tcl_ready", J.bool true, ready] in
    let base = R.evaluation_to_json policy in
    let append key extra = match get base key with J.Array xs -> J.array (xs @ extra) | _ -> assert false in
    obj (List.map (fun (k,v) -> k, match k with
      | "comparisons" -> append k rows
      | "issues" -> append k (List.filter (fun r -> get r "status" = s "fail") rows)
      | _ -> v) (fields base)))
let evaluate_container t container =
  match R.evaluate t ~host:(obj ["python_version", s (t.python_minor ^ ".0")]) ~container () with
  | Error e -> Error e
  | Ok result ->
    let base = R.evaluation_to_json result in
    Ok (obj (List.map (fun (k,v) -> k, match k,v with
      | ("comparisons" | "issues" | "waivers"), J.Array xs ->
        J.array (List.filter (fun r -> get r "role" = s "container") xs)
      | _ -> v) (fields base)))
let binding_from_observation ~native j =
  try T.of_json (obj (["schema_version", unwrap (J.integer "1");
      "execution_mode", s (if native then "native" else "dockerized");
      "interpreter", get j "interpreter"; "interpreter_flags", get j "interpreter_flags"] @
    if native then [] else ["image_identity", get j "image_identity"; "engine_identity", get j "engine_identity"]))
  with Invalid_argument e -> Error e
let verify_image (d : T.docker) ~actual_id =
  (* Python str.strip, including its Unicode whitespace and U+001C..U+001F. *)
  let whitespace = List.map (String.make 1) ['\t'; '\n'; '\011'; '\012'; '\r'; ' ';
    '\028'; '\029'; '\030'; '\031'] @
    ["\194\133"; "\194\160"; "\225\154\128"; "\226\128\168"; "\226\128\169";
     "\226\128\175"; "\226\129\159"; "\227\128\128"] @
    List.init 11 (fun i -> "\226\128" ^ String.make 1 (Char.chr (128+i))) in
  let rec strip x =
    match List.find_opt (fun prefix -> String.starts_with ~prefix x) whitespace with
    | Some prefix -> strip (String.sub x (String.length prefix) (String.length x - String.length prefix))
    | None -> (match List.find_opt (fun suffix -> String.ends_with ~suffix x) whitespace with
      | Some suffix -> strip (String.sub x 0 (String.length x - String.length suffix))
      | None -> x) in
  if strip actual_id = d.image_id then Ok () else Error "execution image ID mismatch"
let contains text needle =
  let rec loop i = i + String.length needle <= String.length text &&
    (String.sub text i (String.length needle) = needle || loop (i+1)) in loop 0
let docker_binding ~declared_ref ~executable ~info ~inspection ~observation =
  try
    ignore (fields info);
    let image = match inspection with J.Array [image] -> ignore (fields image); image
      | _ -> invalid_arg "invalid image inspection" in
    let digests = match get image "RepoDigests" with J.Null -> J.array [] | x -> x in
    let platform = obj ["os", get image "Os"; "architecture", get image "Architecture";
                        "variant", get image "Variant"] in
    let identity = obj ["declared_ref", s declared_ref; "image_id", get image "Id";
                       "repo_digests", digests; "platform", platform; "binding", s "local-image-id"] in
    let rootless = match get info "SecurityOptions" with
      | J.Array xs -> J.bool (List.exists (fun j -> contains (J.canonical j) "rootless") xs)
      | _ -> J.null in
    let engine = obj ["name", s "docker"; "executable", s executable;
      "server_version", get info "ServerVersion"; "rootless", rootless;
      "daemon_id", get info "ID"; "name_on_server", get info "Name"] in
    binding_from_observation ~native:false (obj ["interpreter", s "python3";
      "interpreter_flags", get observation "interpreter_flags";
      "image_identity", identity; "engine_identity", engine])
  with Invalid_argument e -> Error e
let verify_engine (d : T.docker) info = protect (fun () ->
  let security = match get info "SecurityOptions" with J.Array xs -> xs
    | _ -> invalid_arg "missing execution engine identity" in
  let actual = obj ["name", s "docker"; "executable", s d.executable;
    "rootless", J.bool (List.exists (fun j -> contains (J.canonical j) "rootless") security);
    "server_version", get info "ServerVersion"; "daemon_id", get info "ID";
    "name_on_server", get info "Name"] in
  let check key value = if get actual key <> value then invalid_arg ("execution engine identity changed: " ^ key) in
  check "server_version" (s d.server_version); check "rootless" (J.bool d.rootless);
  let optional key = function T.Value x -> check key (s x) | T.Absent | T.Null -> () in
  optional "daemon_id" d.daemon_id; optional "name_on_server" d.name_on_server;
  actual)
