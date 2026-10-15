module J = Identity_json
let codec = function Ok x -> x | Error e -> invalid_arg (J.error_message e)
let str s = codec (J.string s)
let obj xs = codec (J.object_ xs)
let get j k = match j with J.Object xs -> Option.value (List.assoc_opt k xs) ~default:J.null | _ -> J.null
let show = function J.String s -> s | J.Null -> "not recorded" | j -> J.canonical j
let wrap state fields = obj (["contract",str "hardcaml-asic.historical-methodology";
  "schema_version",codec (J.integer "1");"state",str state] @ fields)
let not_recorded = wrap "not_recorded" []
let pending launch = wrap "pending" ["launch",launch;"validation",str "not_published"]
let recorded r =
  let p = Methodology_execution_record.plan r in
  let wire = codec (J.parse (Hardcaml_asic.Methodology_plan.to_string p)) in
  let methodology = get wire "methodology" in
  let snapshot = get methodology "snapshot" in
  wrap "recorded" ["flow",get (get snapshot "definition") "methodology";
    "profile",get snapshot "profile";"endpoint",get snapshot "endpoint";
    "methodology_hash",get wire "methodology_hash";"plan_identity",get wire "plan_identity";
    "bundle_identity",get wire "bundle_identity";
    "effective_parameters",get methodology "effective_parameters";
    "frozen_methodology",methodology;"reference",Methodology_execution_record.to_json r;
    "validation",str "host_only_snapshot_and_recorded_checkpoints";
    "unspecified",str "runtime-backend-default-not-observed"]
let human ?(verbose=false) j =
  let b = Buffer.create 512 in
  let line fmt = Printf.ksprintf (fun s -> Buffer.add_string b (s ^ "\n")) fmt in
  if get j "state" <> str "recorded" then line "METHODOLOGY  %s" (show (get j "state"))
  else (
    let flow = get j "flow" and profile = get j "profile" in
    line "METHODOLOGY  %s (%s) / %s (%s)" (show (get flow "id")) (show (get flow "label"))
      (show (get profile "id")) (show (get profile "label"));
    line "  endpoint: %s (request under fixed flow)" (show (get j "endpoint"));
    line "  plan identity: %s" (show (get j "plan_identity"));
    line "  %-26s %-14s %s" "Effective setting" "Value" "Origin";
    (match get j "effective_parameters" with J.Array xs -> List.iter (fun p ->
      let w = get p "winning" in let a = get w "assignment" in
      line "  %-26s %-14s %s" (show (get a "key")) (show (get a "value")) (show (get (get w "owner") "kind"));
      if verbose then line "    provenance: %s" (J.canonical p)) xs | _ -> ());
    line "  unspecified settings: runtime backend defaults not observed";
    if verbose then (
      line "  methodology hash: %s" (show (get j "methodology_hash"));
      line "  bundle identity: %s" (show (get j "bundle_identity"));
      line "  reference: %s" (J.canonical (get j "reference"));
      line "  frozen methodology: %s" (J.canonical (get j "frozen_methodology"))));
  Buffer.contents b
