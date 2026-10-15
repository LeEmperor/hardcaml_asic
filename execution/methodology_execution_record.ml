module M = Hardcaml_asic.Methodology_plan
module J = Identity_json
type t = { raw : J.t; plan : M.t }
let to_json t = t.raw
let plan t = t.plan
let checked = function Ok x -> x | Error e -> failwith e
let codec = function Ok x -> x | Error e -> failwith (J.error_message e)
let s x = codec (J.string x)
let get j k = match j with J.Object xs -> List.assoc k xs | _ -> failwith "methodology reference object required"
let text = function J.String x -> x | _ -> failwith "methodology reference string required"
let read path =
  if (Unix.lstat path).Unix.st_kind <> Unix.S_REG then failwith "regular methodology snapshot required";
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () -> really_input_string ic (in_channel_length ic))
let decode bytes = match M.of_string bytes with Ok p -> p | Error e -> failwith (Core.Error.to_string_hum e)
let sha bytes = Hardcaml_asic.Flow.Plan_json.sha256 bytes
let publish ~directory ~attempt_id ~expected plan =
  if expected <> M.plan_identity plan then invalid_arg "expected methodology identity mismatch";
  let path = directory ^ "/methodology-plan.json" in
  let bytes = M.to_string plan in
  let temporary = path ^ ".pending" in
  let fd = Unix.openfile temporary [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL] 0o400 in
  let oc = Unix.out_channel_of_descr fd in
  Fun.protect ~finally:(fun () -> close_out_noerr oc; try Unix.unlink temporary with _ -> ()) (fun () ->
    output_string oc bytes; close_out oc;
    (* link is atomic and cannot replace an existing destination. *)
    Unix.link temporary path);
  { plan; raw = codec (J.object_
      [ "contract",s "hardcaml-asic.methodology-execution-reference"; "schema_version",codec (J.integer "1")
      ; "attempt_id",s attempt_id; "snapshot_path",s path; "snapshot_sha256",s (sha bytes)
      ; "expected_plan_identity",s expected; "plan_identity",s (M.plan_identity plan)
      ; "methodology_hash",s (M.methodology_hash plan); "bundle_identity",s (M.bundle_identity plan) ]) }
let decode ~attempt_id ?plan raw =
  try
    ignore (codec (J.exact_object raw ~fields:["contract";"schema_version";"attempt_id";"snapshot_path";"snapshot_sha256";"expected_plan_identity";"plan_identity";"methodology_hash";"bundle_identity"]));
    if get raw "contract" <> s "hardcaml-asic.methodology-execution-reference" || get raw "schema_version" <> codec (J.integer "1")
       || text (get raw "attempt_id") <> attempt_id then failwith "methodology reference contract/attempt mismatch";
    let path = text (get raw "snapshot_path") in
    if Filename.is_relative path || checked (Checkpoint.absolute_path path) <> path || Unix.realpath path <> path
    then failwith "canonical absolute methodology snapshot required";
    let bytes = read path in
    if sha bytes <> text (get raw "snapshot_sha256") then failwith "methodology snapshot checksum mismatch";
    let p = decode bytes in
    List.iter (fun (key,actual) -> if text (get raw key) <> actual then failwith ("methodology reference mismatch: " ^ key))
      ["expected_plan_identity",M.plan_identity p;"plan_identity",M.plan_identity p;"methodology_hash",M.methodology_hash p;"bundle_identity",M.bundle_identity p];
    let derived = Execution_plan.Stage_plan.of_recipe (M.recipe p) in
    Option.iter (fun plan ->
      if J.canonical (Execution_plan.Stage_plan.to_json derived) <> J.canonical (Execution_plan.Stage_plan.to_json plan)
      then failwith "methodology execution stage plan mismatch") plan;
    Ok {raw;plan=p}
  with exn -> Error (Printexc.to_string exn)
let of_json ~attempt_id ~plan raw = decode ~attempt_id ~plan raw
let of_reference_json ~attempt_id raw = decode ~attempt_id raw
