open Hardcaml_asic_execution
module J=Identity_json
let checked = function Ok x -> x | Error e -> invalid_arg e
let codec = function Ok x -> x | Error e -> invalid_arg (J.error_message e)
let read p=codec (Result_store.read_json p)
let get j k=match j with J.Object xs -> List.assoc k xs | _ -> invalid_arg "object"
let text=function J.String s -> s | _ -> invalid_arg "string"
let () = try
  let binding ()=Execution_transport.docker ~executable:"/fixture/docker" ~rootless:true
    ~server_version:"fixture" ~declared_ref:"fixture-image"
    ~image_id:Hardcaml_asic_flow_domain.Backends.Librelane.Mapping.tested_image_id ~repo_digests:[]
    ~os:"linux" ~architecture:"amd64" ~flags:Execution_transport.Isolated () in
  let out=match Sys.argv.(1) with
  | "reference-plan" ->
    (* Fixture-only authority constructor. All identities use the public main
       algorithms and the final plan must pass the real strict plan decoder. *)
    let q=Yojson.Safe.from_file Sys.argv.(2) in
    let field j k=match j with `Assoc xs->List.assoc k xs | _->invalid_arg "object" in
    let set j k value=match j with `Assoc xs->`Assoc (List.map (fun (name,old)->name,if name=k then value else old) xs) | _->invalid_arg "object" in
    let plan=field q "plan" in
    let raw=match field plan "bundle_manifest" with `String s->s | _->invalid_arg "manifest" in
    let manifest=Yojson.Safe.from_string raw in
    let target=set (field manifest "target") "external_references" (field q "references") in
    let manifest=set manifest "target" target in
    let without_identity=match manifest with `Assoc xs->`Assoc (List.remove_assoc "identity" xs) | _->assert false in
    let bundle_identity=Hardcaml_asic.Flow.Plan_json.sha256 (Yojson.Safe.to_string without_identity) in
    let manifest=set manifest "identity" (`String bundle_identity) in
    let plan=set (set plan "bundle_manifest" (`String (Yojson.Safe.to_string manifest))) "bundle_identity" (`String bundle_identity) in
    let payload=match plan with `Assoc xs->`Assoc (List.remove_assoc "plan_identity" xs) | _->assert false in
    let plan_identity=match Hardcaml_asic.Flow.Plan_json.identity ~contract:"hardcaml-asic.plan-identity" payload with
      Ok s->s | Error e->invalid_arg (Core.Error.to_string_hum e) in
    let plan=set plan "plan_identity" (`String plan_identity) in
    let decoded=match Hardcaml_asic.Methodology_plan.of_yojson plan with Ok p->p | Error e->invalid_arg (Core.Error.to_string_hum e) in
    codec (J.parse (Hardcaml_asic.Methodology_plan.to_string decoded))
  | "binding" -> Execution_transport.to_json (binding ())
  | "methodology" ->
    let plan=match Hardcaml_asic.Methodology_plan.of_string Sys.argv.(4) with
      Ok p -> p | Error e -> invalid_arg (Core.Error.to_string_hum e) in
    Methodology_execution_record.to_json (Methodology_execution_record.publish ~directory:Sys.argv.(2)
      ~attempt_id:Sys.argv.(3) ~expected:(Hardcaml_asic.Methodology_plan.plan_identity plan) plan)
  | "argv" ->
    let q=read Sys.argv.(2) in
    let root=text (get q "root") in
    let d=match binding () with Docker d -> d | _ -> assert false in
    let args=Execution_transport.docker_command d ~project:root ~pdk_root:(text (get q "pdk"))
      ~workdir:(root^"/project") ~name:("hardcaml-asic-execution-"^String.make 32 'a')
      ?pdk:(match get q "technology" with J.Null -> None | j -> Some (text j))
      ~workers:6 ~uid:(Unix.getuid ()) ~gid:(Unix.getgid ()) () in
    let payload=match get q "payload" with J.Array xs -> List.map text xs | _ -> assert false in
    J.array (List.map (fun x -> codec (J.string x)) (args@["-I";"-B"]@payload))
  | "request_identity" ->
    codec (J.string (Backend_protocol.request_identity (checked (Backend_protocol.request_of_json (read Sys.argv.(2))))))
  | "publish" ->
    Timing_intent_execution.publish ~directory:Sys.argv.(2) ~succeeded:(Sys.argv.(3)="true")
      ~failure:(if Sys.argv.(3)="true" then J.null else read Sys.argv.(4)) ();J.null
  | "sources" -> codec (J.parse (Yojson.Safe.to_string (`List (checked (Timing_intent_execution.source_files ~execution:Sys.argv.(2) ())))))
  | "precheck" ->
    let q=read Sys.argv.(2) in
    let array=function J.Array xs -> List.map text xs | _ -> invalid_arg "paths array" in
    let paths,external_roots=match q with J.Array _ -> array q,[] | _ -> array (get q "paths"),array (get q "roots") in
    codec (J.parse (Yojson.Safe.to_string (checked (Timing_intent_execution.precheck_sources ~external_roots ~paths ()))))
  | "aliases" ->
    let q=read Sys.argv.(2) in
    let array=function J.Array xs -> List.map text xs | _ -> invalid_arg "paths array" in
    let aliases=Timing_intent_inventory.capture_aliases ~roots:(array (get q "roots")) ~paths:(array (get q "paths")) in
    codec (J.parse (Yojson.Safe.to_string (Timing_intent_inventory.aliases_to_json aliases)))
  | "decode" -> (checked (Stage_execution_record.read Sys.argv.(2))).raw
  | "snapshot-race" ->
    let path=Sys.argv.(2) in let before=(checked (Checkpoint.file_record path)).sha256 in
    let raw=read path in let record,checkpoints=checked (Stage_execution_record.validate_snapshot raw) in
    let replacement=read Sys.argv.(3) in Result_store.save_json path replacement;
    let result=Timing_intent_execution.inspect_snapshot ~execution:path ~execution_sha256:before ~raw ~record ~checkpoints () in
    (match result with Error e -> invalid_arg e | Ok _ -> invalid_arg "race incorrectly accepted")
  | _ -> invalid_arg "test command" in
  print_endline (J.canonical out)
with Invalid_argument e | Failure e | Sys_error e -> prerr_endline e;exit 2
