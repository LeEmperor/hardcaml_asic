module E = Evidence_json
module J = Identity_json
type target = Bundle of string | Coarse_run of string | Execution of string
type axis = Hardware | Resource_policy | Flow_configuration | Descriptive
let s x = `String x
let obj xs = `Assoc xs
let arr xs = `List xs
let get j k = match j with `Assoc xs -> Option.value (List.assoc_opt k xs) ~default:`Null | _ -> `Null
let fields = function `Assoc xs -> xs | `Null -> [] | _ -> invalid_arg "comparison object required"
let list = function `List xs -> xs | `Null -> [] | _ -> invalid_arg "comparison array required"
let text = function `String x -> x | _ -> invalid_arg "comparison string required"
let checked = function Ok x -> x | Error e -> invalid_arg e
let wire x = Yojson.Safe.from_string (J.canonical x)
(* Evidence permits nonfinite observations; equality/digests retain their tokens,
   but the public comparison response is strict JSON with unavailable quantities. *)
let rec ordered = function
  | `Assoc xs -> obj (List.sort (fun (a,_) (b,_) -> String.compare a b) (List.map (fun (k,v) -> k,ordered v) xs))
  | `List xs -> arr (List.map ordered xs)
  | x -> x
let bytes x = E.record_bytes (ordered x)
let equal a b = bytes a=bytes b
let digest x = J.sha256_bytes (bytes x)
let rec json_safe = function
  | `Float f when not (Float.is_finite f) -> `Null
  | `Assoc xs -> obj (List.map (fun (k,v) -> k,json_safe v) xs)
  | `List xs -> arr (List.map json_safe xs)
  | x -> x
let axis_name = function Hardware -> "hardware" | Resource_policy -> "resource_policy"
  | Flow_configuration -> "flow_configuration" | Descriptive -> "descriptive"
let axis = function "hardware" -> Ok Hardware | "resource_policy" -> Ok Resource_policy
  | "flow_configuration" -> Ok Flow_configuration | "descriptive" -> Ok Descriptive
  | _ -> Error "invalid comparison axis"
let target ~kind ~path =
  if String.trim path="" then Error "comparison requires nonempty target paths" else
  match kind with "bundle" -> Ok (Bundle path) | "coarse_run" -> Ok (Coarse_run path)
    | "execution" -> Ok (Execution path) | _ -> Error "invalid comparison target kind"
let path = function Bundle p | Coarse_run p | Execution p -> p
let kind = function Bundle _ -> "bundle" | Coarse_run _ -> "coarse_run" | Execution _ -> "execution"
let resource_target = function Bundle p -> Resource_inspection_service.Bundle p
  | Coarse_run p -> Resource_inspection_service.Coarse_run p | Execution p -> Resource_inspection_service.Execution p
let read p =
  let raw=Retained_file.read p in
  (match J.parse raw with Ok _ -> () | Error e -> invalid_arg (J.error_message e)); raw
let read_json p = Yojson.Safe.from_string (read p)
let select keys j = obj (List.map (fun k -> k,get j k) keys)
let nonempty = function `Null | `List [] | `Assoc [] | `String "" -> false | _ -> true
let hashes refs = arr (List.map (fun r -> get r "sha256") refs)
let integer = function
  | `Int n -> Some (Z.of_int n)
  | `Intlit n -> (try Some (Z.of_string n) with Invalid_argument _ -> None)
  | _ -> None
let number ~count value = match integer value with
  | Some n when not count || Z.sign n>=0 -> Some (`Integer n)
  | Some _ -> None
  | None -> match value with
    | `Float f when Float.is_finite f && (not count || f>=0. && f<9007199254740992. && floor f=f) ->
      Some (if count then `Integer (Z.of_float f) else `Real f)
    | _ -> None
let delta ~count a b = match number ~count a,number ~count b with
  | Some (`Integer a),Some (`Integer b) -> Some (`Intlit (Z.to_string (Z.sub b a)))
  | Some (`Real a),Some (`Real b) -> let d=b-.a in if Float.is_finite d then Some (`Float d) else None
  (* Never round arbitrary-precision counts through float conversion. *)
  | _ -> None
let required_controls axis =
  ["source";"target";"libraries";"environment";"timing_environment";"rc"] @
  (if axis=Hardware then [] else ["hardware"]) @
  (if axis=Resource_policy then [] else ["resource_policy"]) @
  (if axis=Flow_configuration then [] else ["flow_configuration"]) @
  (if axis=Hardware then [] else ["resource_contracts"])
let public_metric m = if m=`Null then `Null else
  obj (("controls_digest",s (digest (get m "controls")))::List.remove_assoc "controls" (fields (json_safe m)))
let compare_metric ~axis ~left ~right =
  let l=get left "value" and r=get right "value" in
  let count=get left "quantity"=s "integer" in
  let classification=get left "classification" in
  let eligible=List.mem classification [s "observed";s "derived"] && get right "classification"=classification in
  let missing=ref [] and conflicts=ref [] in
  let unknown key = missing:= !missing@[s (key^": unknown or unavailable")] in
  let different key = conflicts:= !conflicts@[s (key^": differs")] in
  List.iter (fun key ->
    let a=get left key and b=get right key in
    if not (nonempty a && nonempty b) then unknown key else if not (equal a b) then different key)
    ["definition";"unit";"stage";"scope";"classification";"quantity"];
  List.iter (fun key ->
    let a=get (get left "controls") key and b=get (get right "controls") key in
    if not (nonempty a && nonempty b) then unknown key else if not (equal a b) then different key)
    (required_controls axis);
  if not eligible then unknown "measured observed/derived classification";
  let difference=delta ~count l r in
  if difference=None then unknown "finite compatible numeric values";
  let state=if !missing<>[] then "unavailable" else if !conflicts<>[] then "confounded" else "comparable" in
  obj ["metric_id",(if left=`Null then get right "metric_id" else get left "metric_id");
    "left",public_metric left;"right",public_metric right;"comparison",s state;
    "reasons",arr (!missing @ !conflicts);"right_minus_left",(if state="comparable" then Option.get difference else `Null)]

let rtl_identity manifest =
  let names=list (get manifest "synthesis_sources") in
  let refs=List.filter (fun r -> List.mem (get r "path") names) (list (get manifest "files")) in
  if names=[] || List.length names<>List.length refs then `Null else
  arr (List.map (select ["path";"sha256"]) refs)
let policies inventory = arr (List.map (fun r -> obj ["resource_id",get r "resource_id";
  "policy",get r "policy";"selection",get r "selection";"selected_implementation",get r "selected_implementation"]) inventory)
let contracts inventory = arr (List.map (fun r -> select ["resource_id";"requested_contract"] r) inventory)
let resource_registry = [
  "total_mapped_cells";"total_physical_netlist_cells";"macro_count";"standard_cell_count";
  "synthesis_standard_cell_area";"whole_design_sequential_area";"macro_library_area";"combined_cell_area_estimate";
  "final_standard_cell_area";"standard_cell_utilization";
  "native_all_component_area";"native_nonspacer_area";"native_spacer_area";"native_macro_area";
  "macro_footprint_area";"macro_component_area";"macro_component_count";
  "nonspacer_component_area";"nonspacer_component_count";"spacer_component_area";"spacer_component_count";
  "nonspacer_plus_macro_area";"all_component_area";"gross_core_area";"gross_die_area"]
let count_name name = List.mem name ["total_mapped_cells";"total_physical_netlist_cells";"macro_count";
  "standard_cell_count";"macro_component_count";"nonspacer_component_count";"spacer_component_count";
  "setup_violations";"hold_violations";"max_slew_violations";"max_cap_violations"]
let metric ~id ~name ~value ~classification ~unit_ ~stage ~definition ~scope ~controls ~sources =
  obj ["metric_id",s id;"name",s name;"value",value;"classification",classification;
    "quantity",s (if count_name name then "integer" else "real");"unit",unit_;"stage",stage;
    "definition",definition;"scope",scope;"controls",controls;"sources",sources]
let boundary_projection controls report = List.concat_map (fun checkpoint ->
  let boundary=get (get checkpoint "reference") "boundary" in
  List.filter_map (fun m ->
    let key=get m "raw_key" in
    if not (List.mem key [s "design__instance__count";s "design__instance__area"]) then None else
    let count=key=s "design__instance__count" in
    let name=if count then "total_mapped_cells" else "mapped_cell_area_estimate" in
    Some (metric ~id:("boundary/"^text boundary^"/"^name) ~name
      ~value:(if get m "availability"=s "available" then get m "value" else `Null)
      ~classification:(s (if count then "derived" else "estimate")) ~unit_:(get m "unit")
      ~stage:boundary ~definition:(s ("accumulated_boundary_snapshot."^text key))
      ~scope:(obj ["origin",s "boundary_snapshot_not_per_step_measurement";"boundary",boundary])
      ~controls ~sources:(get m "source"))) (list (get checkpoint "metrics"))) (list (get report "checkpoints"))
let control_update xs controls = obj (xs @ List.filter (fun (k,_) -> not (List.mem_assoc k xs)) (fields controls))
let corner_rows timing = list (get timing "corners")
let timing_projection controls timing = List.concat_map (fun row ->
  (* Only companion2's checked whole-design native metrics are authoritative.
     Historical/named native witnesses intentionally supply no scalar here. *)
  let native=get row "timing" in
  let sources=get native "metric_sources" in
  let corner=get row "corner" in
  let env=get (get row "inputs") "environment" in
  let libs=list (get sources "libraries") in
  let rc=if get timing "stage"=s "post_pnr" then get (get row "spef_selection") "retained"
    else if get timing "stage"=s "synthesized_netlist" then s "no_extracted_rc_pre_pnr" else `Null in
  let controls=control_update ["libraries",(if libs=[] then `Null else hashes libs);
    "environment",(if not (nonempty env && nonempty (get controls "environment")) then `Null
      else obj ["native",env;"execution",get controls "environment"]);
    "rc",rc] controls in
  List.filter_map (fun m ->
    let name=text (get m "key") in
    if not (List.mem name ["setup_slack";"hold_slack";"setup_violations";"hold_violations";"max_slew_violations";"max_cap_violations"]) then None else
    Some (metric ~id:("native/"^text corner^"/"^name) ~name ~value:(get m "value")
      ~classification:(s "observed") ~unit_:(get m "unit") ~stage:(get timing "stage")
      ~definition:(get m "raw_key") ~scope:(obj ["coverage",s "native_whole_design_metric";"corner",corner])
      ~controls ~sources)) (list (get native "metrics"))) (corner_rows timing)

type captured = { projection:E.t; metrics:E.t list; generation:string }
let capture target =
  let p=Unix.realpath (path target) in
  let target=match target with Bundle _ -> Bundle p | Coarse_run _ -> Coarse_run p | Execution _ -> Execution p in
  let resource=checked (Resource_inspection_service.comparison_snapshot (resource_target target) ()) in
  let index=get resource "index" and manifest=get resource "manifest" in
  if manifest<>`Null then Manifest_metadata.validate manifest;
  let inventory=list (get resource "inventory") in
  let record,methodology,timing,report,outcomes,report_metadata = match target with
    | Bundle _ -> `Null,`Null,`Null,`Null,obj ["execution",s "not_evaluated";"acceptance",s "not_evaluated"],[]
    | Coarse_run _ ->
      let record=read_json (p^"/run.json") in
      (* The service admits and consumes each actual descriptor once. No separate
         precheck followed by an unchecked reopen; comparison needs no human
         supplementary report reads. Stored resource assertions remain strict. *)
      let report=Report_service.run ~render_human:false ~strict_sources:true p in
      let stored=get report.results "resource_evidence" in
      if stored<>`Null then ignore (checked (Resource_evidence.verify_sources ~run_dir:p stored));
      let timing=if Timing_intent_flow.expected manifest || get record "timing_intent_expected"=`Bool true ||
        get record "timing_physical_expected"=`Bool true then checked (Timing_intent_flow.inspect ~run_dir:p ())
        else obj ["status",s "unavailable";"reason",s "historical run has no required linked timing evidence"] in
      record,`Null,timing,report.results,obj ["execution",get record "status";
        "acceptance",s (if Report_service.accepted report.verdict then "pass" else "fail");
        "acceptance_scope",s (match report.verdict.scope with Synthesis -> "synthesis" | Full -> "full" | Invalid -> "invalid");
        "resource_retention",get index "verdict";"postchecks",get report.results "postchecks"],report.metadata_sources
    | Execution _ ->
      let captured=read_json p in
      let report=checked (Stage_report_service.run (Stage_report_service.Stage_execution {path=p;selected_record=p})) in
      let report=wire report.envelope in
      let record=get report "execution" in
      if not (equal captured record) then invalid_arg "execution generation changed during comparison capture";
      record,get report "methodology",get report "timing_intent",report,
      obj ["execution",get record "status";"acceptance",get report "acceptance";
        "resource_retention",get report "resource_realization";"external_postcheck",get report "external_postcheck"],[] in
  let sources=list (get resource "sources") in
  let bundle_sources=list (get resource "bundle_sources") in
  let library_refs=List.filter (fun r -> get r "format"=s "liberty") sources in
  let source=get manifest "source_inputs" in
  let source=if source=`List [] then `Null else source in
  let hardware=match get manifest "hardware_variant" with
    | `Null -> rtl_identity manifest
    | declaration -> obj ["basis",s "checked_declared_configuration_not_semantic_use_proof";"declaration",declaration] in
  let sdc=List.filter (fun r -> get r "path"=s "constraints/top.sdc") (list (get manifest "files")) in
  let policy=if get index "inventory_status"=s "available" then
      (if inventory=[] then s "verified_empty_inventory" else policies inventory) else `Null in
  let controls=obj ["source",source;"target",get manifest "target";
    "hardware",hardware;"hardware_declaration",get manifest "hardware_variant";
    "resource_policy",policy;"resource_contracts",(if get index "inventory_status"<>s "available" then `Null
      else if inventory=[] then s "verified_empty_inventory" else contracts inventory);
    "flow_configuration",get manifest "flow_configuration";
    "timing_environment",(match sdc with [r] -> obj ["sdc_sha256",get r "sha256";"intent",get manifest "timing_intent"] | _ -> `Null);
    "libraries",(if library_refs=[] then `Null else hashes library_refs);
    "environment",get record "environment";"rc",`Null;"workload",`Null] in
  let resource_metrics=List.filter_map (fun m ->
    let name=text (get m "name") in
    if not (List.mem name resource_registry) then None else
    Some (metric ~id:("resource/"^text (get m "stage")^"/"^name) ~name ~value:(get m "value")
      ~classification:(get m "classification") ~unit_:(get m "unit") ~stage:(get m "stage")
      ~definition:(get m "definition") ~scope:(get m "scope") ~controls ~sources:(obj ["resource_source_digest",get index "source_digest"]))) (list (get resource "measurements")) in
  let metrics=resource_metrics @ boundary_projection controls report @ timing_projection controls timing in
  if List.length metrics>256 then invalid_arg "comparison metric count exceeds 256 per side";
  let ids=List.map (fun m -> text (get m "metric_id")) metrics in
  if List.length ids<>List.length (List.sort_uniq String.compare ids) then invalid_arg "duplicate comparison metric identity";
  let corner_outcomes=List.map (fun row ->
    let native=get row "timing" in
    obj (("corner",get row "corner")::fields (select ["setup_goal";"hold_goal";"electrical_goal";"annotation_goal"] native))) (corner_rows timing) in
  let timing_outcomes=obj (("corners",arr corner_outcomes)::fields (select ["status";"stage";"verdict";"exhaustive_coverage";"all_corner_timing_goal";
    "qualification_corner_coverage";"configured_corners";"executed_corners"] timing)) in
  let binding=obj ["resource",resource;"record",record;"report",report;"timing",timing;
    "consulted_metadata",arr report_metadata] in
  let generation=digest binding in
  let identities=obj ["bundle_identity",get manifest "identity";"run_id",get record "run_id";
    "attempt_id",get record "attempt_id";"methodology",get record "methodology";
    "occurrences",get record "occurrences";"publications",get record "artifacts";
    "record_sha256",(if record=`Null then `Null else
      let file=match target with Execution _ -> p | _ -> p^"/run.json" in
      let raw=read file in
      if not (equal (Yojson.Safe.from_string raw) record) then invalid_arg "record changed during comparison capture";
      s (J.sha256_bytes raw));
    "timing_provenance",select ["schema";"run_id";"attempt_id";"build_identity";"analysis_id";"stage";"status";
      "occurrence_id";"profile";"runtime_binding";"execution_provider"] (get timing "provenance");
    "timing_provenance_digest",(if timing=`Null then `Null else s (digest (get timing "provenance")))] in
  let producers=List.map (fun row ->
    let evidence=if get row "evidence"=`Null then row else get row "evidence" in
    let provenance=get evidence "provenance" in
    select ["producer";"corner";"stage";"schema";"audit_id";"build_identity"] provenance) (corner_rows timing) in
  let contexts=List.map (fun m -> let c=get m "controls" in digest c,c) metrics
    |> List.sort_uniq (fun (a,_) (b,_) -> String.compare a b) in
  let mapped_netlist=if get timing "synthesis"<>`Null then get (get timing "synthesis") "netlist"
    else get (get timing "originating_synthesis") "netlist" in
  let outputs=obj ["mapped_netlist",mapped_netlist;"implementation_netlist",get (get timing "implementation") "netlist"] in
  let projection=obj ["kind",s (kind target);"target",s p;"source_digest",s generation;
    "identities",identities;"hardware_variant",get manifest "hardware_variant";
    "hardware_metadata_status",s (if get manifest "hardware_variant"=`Null then "unavailable" else "recorded");
    "inventory_status",get index "inventory_status";"resources",arr inventory;
    "methodology",methodology;"controls",controls;"outcomes",obj (("timing",timing_outcomes)::fields outcomes);
    "metric_contexts",obj contexts;"resource_sources",arr sources;"outputs",outputs;
    "verified_bundle_sources",arr bundle_sources;"consulted_metadata",arr report_metadata;
    "timing_producers",arr producers;
    "source_count",`Int (List.length sources + List.length bundle_sources + List.length report_metadata + List.length (list (get timing "sources")));
    "source_count_scope",s "sum_of_reader_reference_lists_not_deduplicated";
    "timing_source_count",`Int (List.length (list (get timing "sources")));
    "source_authentication",s "hash_checked_retained_assertions_not_execution_attestation"] in
  {projection;metrics;generation}

let differences left right =
  let control_keys=["source";"target";"hardware";"hardware_declaration";"resource_policy";"resource_contracts";
    "flow_configuration";"libraries";"environment";"timing_environment";"rc";"workload"] in
  List.map (fun key ->
    let a=get (get left "controls") key and b=get (get right "controls") key in
    obj ["domain",s key;"key",s key;"left",a;"right",b;
      "state",s (if not (nonempty a && nonempty b) then "unavailable" else if equal a b then "equal" else "different")]) control_keys @
  [obj ["domain",s "resource_inventory";"key",s "resources";"left",get left "resources";"right",get right "resources";
    "state",s (if get left "inventory_status"<>s "available" || get right "inventory_status"<>s "available" then "unavailable"
      else if equal (get left "resources") (get right "resources") then "equal" else "different")];
   obj ["domain",s "methodology";"key",s "frozen_methodology";"left",get left "methodology";"right",get right "methodology";
    "state",s (if get left "methodology"=`Null || get right "methodology"=`Null then "unavailable"
      else if equal (get left "methodology") (get right "methodology") then "equal" else "different")]] @
  List.map (fun key -> let a=get (get left "outputs") key and b=get (get right "outputs") key in
    obj ["domain",s "output_bytes";"key",s key;"left",a;"right",b;
      "state",s (if get a "sha256"=`Null || get b "sha256"=`Null then "unavailable"
        else if get a "sha256"=get b "sha256" then "equal" else "different")]) ["mapped_netlist";"implementation_netlist"]
let inspect ~left ~right ~axis () =
  try
    let a=capture left and b=capture right in
    let keys=List.map (fun m -> text (get m "metric_id")) (a.metrics@b.metrics) |> List.sort_uniq String.compare in
    let find id xs=Option.value (List.find_opt (fun m -> get m "metric_id"=s id) xs) ~default:`Null in
    let metrics=List.map (fun id -> compare_metric ~axis ~left:(find id a.metrics) ~right:(find id b.metrics)) keys in
    let result=obj ["contract",s "hardcaml-asic.variant-comparison";"schema_version",`Int 1;
      "policy",s "bounded-pair-v1";"axis",s (axis_name axis);"left",a.projection;"right",b.projection;
      "differences",arr (differences a.projection b.projection);"metrics",arr metrics;
      "workload",obj ["status",s "unavailable";"reason",s "no verified generic workload-result contract";
        "metrics",arr (List.map s ["firmware_size";"fetch_count";"latency";"throughput"])];
      "truncated",`Bool false] |> json_safe in
    let result=obj (("comparison_digest",s (digest result))::fields result) in
    if String.length (E.record_bytes result)>1024*1024 then invalid_arg "comparison whole JSON exceeds 1MiB";
    (* Replay each complete source closure, not just an outer record hash. This also
       rejects a running generation changing while the opposite side is read. *)
    if (capture left).generation<>a.generation || (capture right).generation<>b.generation then
      invalid_arg "comparison source generation changed; retry explicit targets";
    Ok result
  with Invalid_argument e | Failure e | Sys_error e -> Error e
    | End_of_file -> Error "truncated comparison evidence"
    | Unix.Unix_error (e,f,p) -> Error (f^" "^p^": "^Unix.error_message e)
