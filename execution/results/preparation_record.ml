module J = Identity_json
type status = Running | Completed | Failed | Interrupted
type t = { attempt_id : string; status : status; phase : string;
           exit_code : int option; raw : J.t }
let contract = "hardcaml-asic.resource-preparation-operation"
let codec = function Ok x -> x | Error e -> invalid_arg (J.error_message e)
let s x = codec (J.string x)
let obj x = codec (J.object_ x)
let descriptor_version version = obj [
  "contract",s "hardcaml-asic.workflow-operation"; "schema_version",codec (J.integer (string_of_int version));
  "kind",s "elaborate_resolve_resources"; "category",s "preparation";
  "phases",J.array (List.map s (["constructing_project";"source_before";"construction";"finalization";"resolution";"circuit"] @
    (if version=1 then ["source_after";"snapshot"] else ["snapshot";"source_after"]) @ ["publishing";"finished"]));
  "prerequisites",J.array [s "project_owned_constructor";s "declared_source_inputs"];
  "result",s "immutable_resource_snapshot";
  "readiness",s "elaborated_and_resolved_only";
  "physical_stage",J.bool false; "requires_pdk",J.bool false;
  "requires_bundle",J.bool false]
let descriptor () = descriptor_version 2
let valid_identity x = String.length x = 64 && String.for_all (function '0'..'9'|'a'..'f' -> true | _ -> false) x
let get j k = match j with J.Object xs -> List.assoc k xs | _ -> invalid_arg "object required"
let text = function J.String s when s<>"" -> s | _ -> invalid_arg "nonempty string required"
let exact j fields = ignore (codec (J.exact_object j ~fields))
let timestamp j =
  let value=text j in
  if String.length value<>20 || value.[4]<>'-' || value.[7]<>'-' || value.[10]<>'T' ||
     value.[13]<>':' || value.[16]<>':' || value.[19]<>'Z' then invalid_arg "invalid UTC timestamp";
  let part start count = let x=String.sub value start count in
    if not (String.for_all (function '0'..'9'->true | _->false) x) then invalid_arg "invalid UTC timestamp";
    int_of_string x in
  let y=part 0 4 and m=part 5 2 and d=part 8 2 in
  let days=match m with 4|6|9|11->30 | 2->if y mod 4=0 && (y mod 100<>0 || y mod 400=0) then 29 else 28 | _->31 in
  if y=0 || m<1 || m>12 || d<1 || d>days || part 11 2>23 || part 14 2>59 || part 17 2>59 then invalid_arg "invalid UTC timestamp"
let of_json raw = try
  exact raw ["contract";"schema_version";"operation";"attempt_id";"status";"phase";"started_at";"ended_at";"exit_code";"request";"snapshot";"diagnostic"];
  if get raw "contract" <> s contract || get raw "schema_version" <> codec (J.integer "1") ||
     (get raw "operation" <> descriptor () && get raw "operation" <> descriptor_version 1) then invalid_arg "unsupported preparation operation contract";
  let attempt_id = text (get raw "attempt_id") in
  if String.length attempt_id<>32 || not (String.for_all (function '0'..'9'|'a'..'f' -> true | _ -> false) attempt_id) then invalid_arg "invalid attempt identity";
  let phase = text (get raw "phase") in
  if not (List.mem phase ["constructing_project";"source_before";"construction";"finalization";"resolution";"circuit";"source_after";"snapshot";"publishing";"finished"]) then invalid_arg "invalid preparation phase";
  timestamp (get raw "started_at");
  (match get raw "request" with J.Object _ -> () | _ -> invalid_arg "request must be an object");
  let status = match text (get raw "status") with "running"->Running | "completed"->Completed | "failed"->Failed | "interrupted"->Interrupted | _->invalid_arg "invalid preparation status" in
  let exit_code = match get raw "exit_code" with J.Null -> None | J.Integer n -> let n=int_of_string n in if n<0 || n>255 then invalid_arg "invalid exit code"; Some n | _ -> invalid_arg "invalid exit code" in
  let terminal = status<>Running in
  if terminal then timestamp (get raw "ended_at") else if get raw "ended_at"<>J.null then invalid_arg "running operation has end time";
  if terminal <> Option.is_some exit_code then invalid_arg "inconsistent terminal exit code";
  let snapshot=get raw "snapshot" and diagnostic=get raw "diagnostic" in
  (match status with
   | Completed ->
     if exit_code<>Some 0 || phase<>"finished" || diagnostic<>J.null then invalid_arg "invalid completed operation";
     exact snapshot ["path";"identity";"sha256";"bytes"];
     if get snapshot "path"<>s "resources.json" then invalid_arg "invalid snapshot path";
     List.iter (fun k -> if not (valid_identity (text (get snapshot k))) then invalid_arg "invalid snapshot digest") ["identity";"sha256"];
     (match get snapshot "bytes" with J.Integer n when Z.sign (Z.of_string n)>0 -> () | _ -> invalid_arg "invalid snapshot byte count")
   | Running -> if snapshot<>J.null || diagnostic<>J.null || phase="finished" then invalid_arg "invalid running operation"
   | Failed | Interrupted ->
     if snapshot<>J.null || exit_code=Some 0 then invalid_arg "failed operation advertises success";
     exact diagnostic ["phase";"code";"message";"detail";"signal"];
     List.iter (fun k -> ignore (text (get diagnostic k))) ["phase";"code";"message"];
     let code=text (get diagnostic "code") in
     if not (List.mem code ["preparation_rejected";"preparation_exception";"interrupted"]) ||
        ((status=Interrupted) <> (code="interrupted")) then invalid_arg "invalid diagnostic code";
     if code="preparation_rejected" && get diagnostic "detail"=J.null then invalid_arg "missing structured preparation failure";
     if code="preparation_exception" && get diagnostic "detail"<>J.null then invalid_arg "unexpected structured failure detail";
     if get diagnostic "phase"<>s phase then invalid_arg "diagnostic phase mismatch";
     (match get diagnostic "detail" with
      | J.Null -> ()
      | detail ->
        let parsed=Yojson.Safe.from_string (J.canonical detail) in
        (match Hardcaml_asic.Resource_preparation.Failure.of_json parsed with
         | Error e -> invalid_arg (Core.Error.to_string_hum e)
         | Ok failure ->
           if Hardcaml_asic.Resource_preparation.Phase.to_string failure.phase<>phase then invalid_arg "source failure phase mismatch"));
     (match status,get diagnostic "signal",exit_code with
      | Interrupted,J.Integer n,Some code when (n="2" || n="15") && code=128+int_of_string n -> ()
      | Failed,J.Null,_ -> () | _ -> invalid_arg "inconsistent interruption"));
  Ok {attempt_id;status;phase;exit_code;raw}
 with Invalid_argument e | Failure e -> Error e
let read directory = try
  let bytes=Preparation_storage.read_bytes ~limit:Preparation_storage.operation_limit (directory^"/operation.json") in
  match J.parse bytes with Error e -> Error (J.error_message e) | Ok j -> of_json j
 with Invalid_argument e | Failure e | Sys_error e -> Error e
    | Unix.Unix_error (e,f,p) -> Error (f^" "^p^": "^Unix.error_message e)
let to_json t = t.raw
