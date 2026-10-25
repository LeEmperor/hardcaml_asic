module J = Identity_json
module P = Hardcaml_asic.Resource_preparation
type t = { directory:string; record:Preparation_record.t; snapshot:P.t option;
           comparison:string; current:string option }
let codec = function Ok x -> x | Error e -> invalid_arg (J.error_message e)
let s x = codec (J.string x)
let obj x = codec (J.object_ x)
let get j k = match j with J.Object xs -> List.assoc k xs | _ -> invalid_arg "object required"
let text = function J.String x -> x | _ -> invalid_arg "string required"
let checked = function Ok x -> x | Error e -> invalid_arg e
let inspect ?current_identity directory = try
  Option.iter (fun x -> if not (Preparation_record.valid_identity x) then invalid_arg "current identity must be a lowercase SHA-256 preparation identity") current_identity;
  let record=checked (Preparation_record.read directory) in
  let snapshot=match record.status with
    | Preparation_record.Completed ->
      let reference=get record.raw "snapshot" in
      let bytes=Preparation_storage.read_bytes ~limit:Preparation_storage.snapshot_limit (directory^"/resources.json") in
      if get reference "bytes"<>codec (J.integer (string_of_int (String.length bytes))) ||
         get reference "sha256"<>s (J.sha256_bytes bytes) then invalid_arg "preparation snapshot bytes changed";
      let value=match P.of_string bytes with Ok x->x | Error e -> invalid_arg (Core.Error.to_string_hum e) in
      if P.identity value<>text (get reference "identity") then invalid_arg "preparation snapshot identity mismatch";
      Some value
    | Running | Failed | Interrupted -> None in
  let comparison=match current_identity,snapshot with None,_->"not_requested" | Some _,None->"unavailable"
    | Some id,Some p -> if id=P.identity p then "matches" else "differs" in
  Ok {directory;record;snapshot;comparison;current=current_identity}
 with Invalid_argument e | Failure e | Sys_error e -> Error e
    | Unix.Unix_error (e,f,p) -> Error (f^" "^p^": "^Unix.error_message e)
let to_json t = obj ["contract",s "hardcaml-asic.preparation-inspection";
  "schema_version",codec (J.integer "1");"attempt",s t.directory;
  "operation",t.record.raw;
  "preparation",(match t.snapshot with None->J.null | Some p->codec (J.parse (P.to_string p)));
  "comparison",obj ["state",s t.comparison;"scope",s "preparation_identity";
    "current_identity",(match t.current with None->J.null | Some x->s x);
    "recorded_identity",(match t.snapshot with None->J.null | Some p->s (P.identity p))]]
let render t =
  let b=Buffer.create 1024 in
  let line k v=Buffer.add_string b (Printf.sprintf "%-22s %s\n" k v) in
  line "Operation" "Elaborate & Resolve Resources (preparation)";
  line "Attempt" t.directory;line "Attempt ID" t.record.attempt_id;
  line "Status" (match t.record.status with Running->"running (no terminal outcome recorded)" | Completed->"completed" | Failed->"failed" | Interrupted->"interrupted");
  line "Phase" t.record.phase;line "Current comparison" t.comparison;
  (match t.snapshot with
   | None -> line "Resources" "unavailable: no committed successful snapshot";
     let d=get t.record.raw "diagnostic" in if d<>J.null then (
       line "Diagnostic" (text (get d "message"));
       Buffer.add_string b (Result_store.record_bytes d))
   | Some p ->
     line "Preparation identity" (P.identity p);
     line "Source identity" (P.source_identity p);
     line "Configuration identity" (P.configuration_identity p);
     line "Circuit identity" (P.circuit_identity p);
     Buffer.add_string b "\nResource inventory (historical elaboration/resolution facts):\n";
     let resources=Hardcaml_asic.Resource_snapshot.to_json (P.resources p) in
     let field j k=match j with `Assoc xs->List.assoc k xs | _->assert false in
     let str=function `String s->s | j->Yojson.Safe.to_string j in
     List.iter (fun k->line k (str (field resources k))) ["project";"top";"mode";"scope"];
     (match field resources "resources" with
      | `List [] -> line "Resources" "0 (successful resource-free design)"
      | `List entries -> List.iter (fun entry ->
        Buffer.add_char b '\n';
        line "Resource" (str (field (field entry "id") "display"));
        line "Request kind" (str (field (field entry "request") "kind"));
        line "Contract" (str (field (field entry "request") "contract"));
        line "Requirement" (str (field entry "requirement"));
        line "Matched policy" (str (field entry "policy"));
        let selection=field entry "selection" in
        line "Implementation" (str (field selection "implementation"));
        line "Selection reason" (str (field selection "reason"));
        line "Elaborated as" (str (field entry "elaborated_as"));
        line "Actual instances" (str (field entry "actual_instances"));
        line "Source roles" (str (field entry "sources"));
        line "Collateral references" (str (field entry "collateral"));
        line "Physical intent" (str (field entry "physical_intent"))) entries
      | _->assert false));
  Buffer.add_string b "\nNo collateral-file verification, tool readiness, synthesis retention or physical acceptance is implied.\n";
  Buffer.contents b
