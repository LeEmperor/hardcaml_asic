module J = Identity_json
module Stage = Hardcaml_asic.Flow.Stage

let version = 1
let ( let* ) = Result.bind
let codec = function Ok x -> Ok x | Error e -> Error (J.error_message e)
let checked = function Ok x -> x | Error e -> invalid_arg (J.error_message e)
let str s = checked (J.string s)
let obj xs = checked (J.object_ xs)
let int s = checked (J.integer s)
let fields names value = codec (J.exact_object value ~fields:names)
let get = List.assoc
let string = function
  | J.String s when s <> "" && not (String.contains s '\000') -> Ok s
  | _ -> Error "expected nonempty protocol string"
let path value =
  let* s = string value in
  if s.[0] = '/' then Ok s else Error "expected absolute protocol path"
let sha value =
  let* s = string value in
  if String.length s = 64 && String.for_all (function '0'..'9' | 'a'..'f' -> true | _ -> false) s
  then Ok s else Error "expected lowercase SHA-256"
let stage value =
  let* s = string value in
  match Stage.of_string s with Ok s -> Ok s | Error e -> Error (Core.Error.to_string_hum e)
let optional f = function J.Null -> Ok None | v -> let* v = f v in Ok (Some v)
let option f = function None -> J.null | Some v -> f v
let stage_json s = str (Stage.to_string s)
type operation = Execute_segment | Validate_publication
let operation = function
  | J.String "execute_segment" -> Ok Execute_segment
  | J.String "validate_publication" -> Ok Validate_publication
  | _ -> Error "unsupported backend operation"
let operation_json = function Execute_segment -> str "execute_segment" | Validate_publication -> str "validate_publication"
let check_version = function J.Integer "1" -> Ok () | _ -> Error "unsupported backend protocol version"
type request =
  { operation : operation; request_id : string; reply_path : string
  ; boundary : Stage.t; checkpoint : string option; source_boundary : Stage.t option
  ; candidate : string; project : string; pdk_root : string; tag : string
  ; bridge_sha256 : string }
let request_fields = ["protocol_version"; "operation"; "request_id"; "reply_path";
                      "boundary"; "checkpoint"; "source_boundary"; "candidate";
                      "project"; "pdk_root"; "tag"; "bridge_sha256"]
let request_of_json value =
  let* f = fields request_fields value in
  let v n = get n f in
  let* () = check_version (v "protocol_version") in
  let* operation = operation (v "operation") in
  let* request_id = string (v "request_id") in
  let* reply_path = path (v "reply_path") in
  let* boundary = stage (v "boundary") in
  let* checkpoint = optional path (v "checkpoint") in
  let* source_boundary = optional stage (v "source_boundary") in
  let* candidate = path (v "candidate") in
  let* project = path (v "project") in
  let* pdk_root = path (v "pdk_root") in
  let* tag = string (v "tag") in
  let* bridge_sha256 = sha (v "bridge_sha256") in
  let valid_source = match operation, checkpoint, source_boundary with
    | Validate_publication, None, None -> true
    | Execute_segment, None, None -> boundary = Stage.Synthesis
    | Execute_segment, Some _, Some source ->
      (* Historical wire evidence remains decodable. The new bridge and
         checkpoint compatibility independently reject this old transition. *)
      (source = Stage.Routing && boundary = Stage.Signoff)
      || List.mem boundary (Stage.capability source).restart_targets
    | _ -> false in
  if not valid_source then Error "unsupported backend source transition"
  else if String.contains tag '/' || tag = "." || tag = ".." then Error "invalid backend tag"
  else if reply_path = candidate then Error "reply path aliases candidate"
  else Ok { operation; request_id; reply_path; boundary; checkpoint; source_boundary;
            candidate; project; pdk_root; tag; bridge_sha256 }
let request_to_json (t : request) = obj
  [ "protocol_version", int "1"; "operation", operation_json t.operation
  ; "request_id", str t.request_id; "reply_path", str t.reply_path
  ; "boundary", stage_json t.boundary; "checkpoint", option str t.checkpoint
  ; "source_boundary", option stage_json t.source_boundary; "candidate", str t.candidate
  ; "project", str t.project; "pdk_root", str t.pdk_root; "tag", str t.tag
  ; "bridge_sha256", str t.bridge_sha256 ]
let make_request ~operation ~request_id ~reply_path ~boundary ~checkpoint ~source_boundary
    ~candidate ~project ~pdk_root ~tag ~bridge_sha256 =
  (* Validate Unicode through the codec before constructing a private record. *)
  let raw = ["request_id", request_id; "reply_path", reply_path; "candidate", candidate;
             "project", project; "pdk_root", pdk_root; "tag", tag; "bridge_sha256", bridge_sha256]
            @ (match checkpoint with None -> [] | Some p -> ["checkpoint", p]) in
  let rec check = function
    | [] -> Ok ()
    | (_, s) :: rest -> let* _ = codec (J.string s) in check rest in
  let* () = check raw in
  request_of_json (request_to_json { operation; request_id; reply_path; boundary; checkpoint;
                                   source_boundary; candidate; project; pdk_root; tag; bridge_sha256 })
let parse_request text = let* json = codec (J.parse text) in request_of_json json
let request_identity t = J.identity (request_to_json t)
type outcome = Completed | Validated | Failed of string
type artifact = { path : string; sha256 : string; bytes : string }
type reply = { request : request; outcome : outcome; artifacts : (string * artifact) list }
let artifact_names = function
  | Execute_segment -> ["state.json"; "resolved.json"; "closure.json"; "segment.json"]
  | Validate_publication -> ["resolved.json"; "closure.json"]
let artifact_of_json ~expected value =
  let* f = fields ["path"; "sha256"; "bytes"] value in
  let* path = path (get "path" f) in
  let* sha256 = sha (get "sha256" f) in
  let* bytes = match get "bytes" f with
    | J.Integer s when s.[0] <> '-' -> Ok s
    | _ -> Error "expected nonnegative artifact byte count" in
  if path <> expected then Error "backend artifact path mismatch" else Ok { path; sha256; bytes }
let reply_of_json ~request value =
  let* f = fields ["protocol_version"; "operation"; "request_id"; "request_sha256";
                   "boundary"; "candidate"; "bridge_sha256"; "outcome"; "artifacts"; "error"] value in
  let v n = get n f in
  let* () = check_version (v "protocol_version") in
  let* operation = operation (v "operation") in
  let* request_id = string (v "request_id") in
  let* request_sha256 = sha (v "request_sha256") in
  let* boundary = stage (v "boundary") in
  let* candidate = path (v "candidate") in
  let* bridge_sha256 = sha (v "bridge_sha256") in
  if operation <> request.operation || request_id <> request.request_id
     || request_sha256 <> request_identity request || boundary <> request.boundary
     || candidate <> request.candidate || bridge_sha256 <> request.bridge_sha256
  then Error "backend reply/request mismatch"
  else
    let* outcome = match v "outcome", v "error", operation with
      | J.String "failed", error, _ -> let* error = string error in Ok (Failed error)
      | J.String "completed", J.Null, Execute_segment -> Ok Completed
      | J.String "validated", J.Null, Validate_publication -> Ok Validated
      | _ -> Error "inconsistent backend outcome" in
    let names = match outcome with Failed _ -> [] | _ -> artifact_names operation in
    let* evidence = fields names (v "artifacts") in
    let rec trim s = if String.length s > 0 && s.[String.length s - 1] = '/'
      then trim (String.sub s 0 (String.length s - 1)) else s in
    let rec parse = function
      | [] -> Ok []
      | (name, value) :: rest ->
        let* artifact = artifact_of_json ~expected:(trim candidate ^ "/" ^ name) value in
        let* rest = parse rest in Ok ((name, artifact) :: rest) in
    let* artifacts = parse evidence in Ok { request; outcome; artifacts }
let parse_reply ~request text = let* json = codec (J.parse text) in reply_of_json ~request json
let reply_to_json t =
  let r = t.request in
  let outcome, error = match t.outcome with
    | Completed -> "completed", J.null | Validated -> "validated", J.null
    | Failed error -> "failed", str error in
  obj [ "protocol_version", int "1"; "operation", operation_json r.operation
      ; "request_id", str r.request_id; "request_sha256", str (request_identity r)
      ; "boundary", stage_json r.boundary; "candidate", str r.candidate
      ; "bridge_sha256", str r.bridge_sha256; "outcome", str outcome; "error", error
      ; "artifacts", obj (List.map (fun (name, a) -> name,
          obj ["path", str a.path; "sha256", str a.sha256; "bytes", int a.bytes]) t.artifacts) ]
