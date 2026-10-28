open Hardcaml_asic_execution
let () =
  let kind=ref "" and target=ref "" and query=ref "index" and resource_id=ref None
  and section=ref None and expected_digest=ref None and artifact_id=ref None
  and offset=ref 0 and limit=ref 16 in
  let opt r=Arg.String (fun s -> r:=Some s) in
  try
    Arg.parse ["--kind",Arg.Set_string kind,"Target kind";"--target",Arg.Set_string target,"Target";
      "--query",Arg.Set_string query,"index/detail/artifacts/bytes";
      "--resource-id",opt resource_id,"Resource ID";"--section",opt section,"Section";
      "--expected-digest",opt expected_digest,"Exact source digest";"--artifact-id",opt artifact_id,"Artifact ID";
      "--offset",Arg.Set_int offset,"Offset";"--limit",Arg.Set_int limit,"Limit";
      "--json",Arg.Unit (fun () -> ()),"JSON";"--verbose",Arg.Unit (fun () -> ()),"Verbose"]
      (fun s -> if !target<>"" then invalid_arg "one target required" else target:=s) "Read-only bounded resource inspection";
    match Resource_inspection_service.run ~kind:!kind ~target:!target ~query:!query
      ?resource_id:!resource_id ?section:!section ?expected_digest:!expected_digest ?artifact_id:!artifact_id
      ~offset:!offset ~limit:!limit () with
    | Error e -> prerr_endline ("resource-inspect: "^e);exit 2
    | Ok j -> print_endline (Yojson.Safe.to_string j);
      exit (if (match j with `Assoc xs -> List.assoc_opt "verdict" xs=Some (`String "fail") | _ -> false) then 1 else 0)
  with Invalid_argument e | Failure e -> prerr_endline e;exit 2
