module J = Identity_json
module D = Hardcaml_asic_flow_domain
module M = D.Backends.Librelane.Mapping
let checked = function Ok x -> x | Error e -> invalid_arg (J.error_message e)
let s x = checked (J.string x)
let obj xs = checked (J.object_ xs)
let strings xs = J.array (List.map s xs)
let step_json (step : M.step) = obj
  ["id",s step.id; "implementation",s step.implementation;
   "inputs",strings step.inputs; "outputs",strings step.outputs;
   "gates",J.array (List.map (fun (name,default) -> obj ["name",s name; "default",J.bool default]) step.gates)]
let inventory () = J.array (List.map (fun (o : M.occurrence) -> step_json o.step) M.all)
let setting_json (x : M.setting) = obj
  ["name",s x.name; "kind",s x.kind;
   "units",(match x.units with None -> J.null | Some x -> s x);
   "default",(match x.default with None -> J.null | Some x -> s x); "pdk",J.bool x.pdk]
let settings implementation = J.array (List.map setting_json (M.settings implementation))
let validate_settings value =
  let equal a b = J.canonical a = J.canonical b in
  match value with
  | J.Object fields ->
    if List.for_all (fun (o : M.occurrence) ->
      match M.settings o.step.implementation with
      | [] -> true
      | expected -> match List.assoc_opt o.step.implementation fields with
        | Some (J.Array actual) -> List.for_all (fun (setting : M.setting) ->
            let matches = List.filter (function J.Object fields ->
              List.assoc_opt "name" fields = Some (s setting.name) | _ -> false) actual in
            match matches with [one] -> equal (setting_json setting) one | _ -> false) expected
        | _ -> false) M.all then Ok ()
    else Error "Unsupported LibreLane placement configuration type/unit/default drift"
  | _ -> Error "Missing LibreLane placement configuration contracts"
let validate_inventory value =
  (* Exact JSON equality also rejects missing/extra fields, types, gate/default
     drift and array reordering. Object key order is presentation-only. *)
  if J.canonical value = J.canonical (inventory ()) then Ok ()
  else Error "Unsupported LibreLane Classic ordered step/artifact/gate inventory"
let occurrence_json (o : M.occurrence) = obj
  ["occurrence_id",s o.occurrence_id; "stage",s (D.Stage_id.to_string o.stage);
   "operation",s o.operation.key; "description",s o.operation.description;
   "effect",s (match o.operation.effect with Transform -> "transform" | Analyze -> "analysis" | Check -> "check");
   "precondition",s o.operation.precondition; "postcondition",s o.operation.postcondition;
   "backend",step_json o.step;
   "settings",settings o.step.implementation;
   "configuration",s "unchanged resolved LibreLane configuration; native defaults/validation";
   "execution_evidence",J.null; "durable_checkpoint",J.bool false]
let groups () = obj (List.map (fun stage -> D.Stage_id.to_string stage,
  J.array (List.map occurrence_json (M.composition stage))) D.Stage_id.all)
let sequence stages = J.array (List.concat_map (fun stage ->
  List.map occurrence_json (M.composition stage)) stages)
