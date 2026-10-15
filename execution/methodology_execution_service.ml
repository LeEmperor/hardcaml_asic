module M = Hardcaml_asic.Methodology_plan
module J = Hardcaml_asic.Flow.Plan_json
let check ~bundle ~expected plan =
  try
    if expected <> M.plan_identity plan then failwith "stale methodology plan identity";
    let root = Unix.realpath bundle in
    let read relative =
      if relative = "" || not (Filename.is_relative relative)
         || List.exists (fun x -> x="" || x="." || x="..") (String.split_on_char '/' relative)
         || String.contains relative '\000' then failwith "unsafe methodology bundle path";
      let p = root ^ "/" ^ relative in
      if not (String.starts_with ~prefix:(root ^ "/") (Unix.realpath p))
         || (Unix.lstat p).Unix.st_kind <> Unix.S_REG then failwith "methodology bundle regular file required";
      let ic = open_in_bin p in
      Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () -> really_input_string ic (in_channel_length ic)) in
    let get j k = match j with `Assoc xs -> List.assoc k xs | _ -> failwith "object required" in
    let text = function `String s -> s | _ -> failwith "string required" in
    let wire = M.to_yojson plan in
    let manifest = Yojson.Safe.from_string (read "manifest.json") in
    let frozen = Yojson.Safe.from_string (text (get wire "bundle_manifest")) in
    if not (J.equal manifest frozen) then failwith "methodology plan/bundle manifest mismatch";
    (match Hardcaml_asic.Bundle.verify_manifest_identity manifest with Ok () -> () | Error e -> failwith (Core.Error.to_string_hum e));
    (match Hardcaml_asic.Flow.Methodology_inventory.verify ~manifest
      ~configuration:(text (get wire "configuration_bytes")) with
     | Ok () -> () | Error e -> failwith (Core.Error.to_string_hum e));
    if read "src/config.json" <> text (get wire "configuration_bytes") then failwith "methodology configuration bytes mismatch";
    (match get manifest "files" with `List files -> List.iter (fun f ->
       let path = text (get f "path") in
       if J.sha256 (read path) <> text (get f "sha256") then failwith ("changed methodology bundle file: " ^ path)) files
     | _ -> failwith "bundle inventory required");
    Ok (Execution_plan.of_stages (Execution_plan.Stage_plan.of_recipe (M.recipe plan)))
  with exn -> Error (Printexc.to_string exn)

let check_resolved plan path =
  try
    if (Unix.lstat path).Unix.st_kind <> Unix.S_REG then failwith "methodology resolved regular file required";
    let ic = open_in_bin path in
    let bytes = Fun.protect ~finally:(fun () -> close_in_noerr ic)
      (fun () -> really_input_string ic (in_channel_length ic)) in
    let fields = match Yojson.Safe.from_string bytes with `Assoc xs -> xs | _ -> failwith "methodology resolved object required" in
    List.iter (fun (p:Hardcaml_asic.Resolved_flow.Effective_parameter.t) ->
      let module P = Hardcaml_asic.Flow.Parameter in
      let assignment = p.winning.assignment in
      let key = P.Key.to_string (P.assignment_key assignment) in
      let expected = match P.assignment_value assignment with
        | P.Strategy v -> `String (P.Strategy.to_string v) | P.Bool b -> `Bool b in
      let actual = List.filter (fun (k,_) -> k=key) fields in
      if actual <> [key,expected] then failwith ("methodology resolved parameter mismatch: " ^ key)) (M.effective_parameters plan);
    Ok ()
  with exn -> Error (Printexc.to_string exn)
