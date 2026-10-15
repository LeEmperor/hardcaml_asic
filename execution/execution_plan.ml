module J = Identity_json
module Stage = Hardcaml_asic.Flow.Stage
module Recipe = Hardcaml_asic.Flow.Recipe

let ( let* ) = Result.bind
let codec = function Ok x -> Ok x | Error e -> Error (J.error_message e)
let checked = function Ok x -> x | Error e -> invalid_arg (J.error_message e)
let str s = checked (J.string s)
let obj fields = checked (J.object_ fields)
let strings xs = J.array (List.map str xs)
let integer n = checked (J.integer (string_of_int n))
let fields names value = codec (J.exact_object value ~fields:names)
let get fields name = List.assoc name fields
let string = function J.String s -> Ok s | _ -> Error "expected string"
let boolean = function J.Bool b -> Ok b | _ -> Error "expected boolean"
let rec map_result f = function
  | [] -> Ok []
  | x :: xs -> let* x = f x in let* xs = map_result f xs in Ok (x :: xs)
let array f = function J.Array xs -> map_result f xs | _ -> Error "expected array"
let stage value =
  let* s = string value in
  match Stage.of_string s with Ok s -> Ok s | Error e -> Error (Core.Error.to_string_hum e)
let boundary = function J.Null -> Ok None | value -> let* s = stage value in Ok (Some s)
let or_error = function Ok x -> Ok x | Error e -> Error (Core.Error.to_string_hum e)
let optional_stage = function None -> J.null | Some s -> str (Stage.to_string s)

module Action = struct
  type operation = Run | Postcheck | Collect | Report | Archive | Segment
  type gate = Success | Run_available | Accepted
  type phase = Implementation | Verification | Results | Acceptance | Retention
             | Physical of Stage.t
  type t =
    { key : string; operation : operation; stage : phase; label : string
    ; enabled : bool; requires : string list; gate : gate
    ; inputs : string list; outputs : string list }
  let operation_name = function
    | Run -> "run" | Postcheck -> "postcheck" | Collect -> "collect"
    | Report -> "report" | Archive -> "archive" | Segment -> "segment"
  let gate_name = function
    | Success -> "success" | Run_available -> "run_available" | Accepted -> "accepted"
  let phase_name = function
    | Implementation -> "implementation" | Verification -> "verification"
    | Results -> "results" | Acceptance -> "acceptance" | Retention -> "retention"
    | Physical s -> Stage.to_string s
  let to_json t = obj
    [ "key", str t.key; "operation", str (operation_name t.operation)
    ; "stage", str (phase_name t.stage); "label", str t.label
    ; "enabled", J.bool t.enabled; "requires", strings t.requires
    ; "gate", str (gate_name t.gate); "inputs", strings t.inputs
    ; "outputs", strings t.outputs ]
  let make ?(enabled=true) ?(requires=[]) ?(gate=Success) ~inputs ~outputs
      key operation stage label =
    { key; operation; stage; label; enabled; requires; gate; inputs; outputs }
end

module Coarse = struct
  type endpoint = Synthesis | Full
  type t = { endpoint : endpoint; actions : Action.t list }
  let endpoint t = t.endpoint
  let actions t = t.actions
  let name = function Synthesis -> "synthesis" | Full -> "full"
  let resolve ?(archive=false) endpoint =
    let open Action in
    let full = endpoint = Full in
    { endpoint; actions =
      [ make ~inputs:["bundle"; "runtime_requirements"]
          ~outputs:["run_record"; "implementation_workdir"]
          "implementation.librelane" Run Implementation "LibreLane"
      ; make ~enabled:full ~requires:["implementation.librelane"]
          ~inputs:["implementation_workdir"; "testbench"] ~outputs:["check_record"]
          "verification.postcheck" Postcheck Verification "Postcheck"
      ; make ~requires:(if full then ["implementation.librelane"; "verification.postcheck"]
                         else ["implementation.librelane"])
          ~gate:Run_available ~inputs:["run_record"; "implementation_workdir"] ~outputs:["results"]
          "results.collect" Collect Results "Collect"
      ; make ~requires:["results.collect"] ~inputs:["results"] ~outputs:["verdict"]
          "acceptance.report" Report Acceptance "Acceptance"
      ; make ~enabled:archive ~requires:["acceptance.report"] ~gate:Accepted
          ~inputs:["run_record"; "results"] ~outputs:["archive"]
          "retention.archive" Archive Retention "Archive" ] }
  let with_labels t labels =
    let* _ = map_result (fun s -> codec (J.string s)) labels in
    if List.length labels <> 5 then Error "expected five labels"
    else Ok { t with actions = List.map2 (fun a label -> { a with Action.label }) t.actions labels }
  let to_json t = obj ["schema_version", integer 1; "endpoint", str (name t.endpoint);
                       "actions", J.array (List.map Action.to_json t.actions)]
  let of_json value =
    let* f = fields ["schema_version"; "endpoint"; "actions"] value in
    let* () = match get f "schema_version" with J.Integer "1" -> Ok () | _ -> Error "expected integer schema 1" in
    let* endpoint = match get f "endpoint" with
      | J.String "synthesis" -> Ok Synthesis | J.String "full" -> Ok Full
      | _ -> Error "unsupported coarse endpoint" in
    let* raw = match get f "actions" with J.Array xs when List.length xs = 5 -> Ok xs
      | _ -> Error "expected five coarse actions" in
    let* parsed = map_result (fields ["key"; "operation"; "stage"; "label"; "enabled";
                                     "requires"; "gate"; "inputs"; "outputs"]) raw in
    let* archive = boolean (get (List.nth parsed 4) "enabled") in
    let expected = resolve ~archive endpoint in
    let* labels = map_result (fun (actual, contract) ->
      let* label = string (get actual "label") in
      let* _ = boolean (get actual "enabled") in
      let* _ = map_result (fun n -> array string (get actual n)) ["requires"; "inputs"; "outputs"] in
      let wanted = match Action.to_json contract with J.Object fs -> fs | _ -> assert false in
      if List.for_all (fun (n, v) -> n = "label" || get actual n = v) wanted
      then Ok label else Error "unsupported coarse action contract")
      (List.combine parsed expected.actions) in
    with_labels expected labels
end

module Stage_plan = struct
  type t = { schema_version : int; recipe : Recipe.t }
  let schema_version t = t.schema_version
  let recipe t = t.recipe
  let endpoint t = Recipe.endpoint t.recipe
  let source_boundary t = Recipe.initial_boundary t.recipe
  let sequence t = Recipe.stages t.recipe
  let of_recipe recipe =
    (match Hardcaml_asic_flow_domain.Backends.Librelane.Mapping.validate_sequence
       ~initial_boundary:(Recipe.initial_boundary recipe) (Recipe.stages recipe) with
     | Ok () -> () | Error e -> invalid_arg e);
    { schema_version = 3; recipe }
  let resolve_sequence ?initial_boundary stages =
    let* recipe = or_error (Recipe.create ?initial_boundary stages) in Ok (of_recipe recipe)
  let through ?initial_boundary endpoint =
    let* recipe = or_error (Recipe.through ?initial_boundary endpoint) in Ok (of_recipe recipe)
  let resolve ?(resume=false) endpoint =
    let initial_boundary = if resume then Some Stage.Synthesis else None in
    let* recipe = or_error (Recipe.through ?initial_boundary endpoint) in
    Ok { schema_version = 2; recipe }
  let actions t =
    let rec loop previous = function
      | [] -> []
      | (d : Recipe.declaration) :: ds ->
        let name = Stage.to_string d.stage in
        let key = "implementation." ^ name in
        let inputs = match d.input with
          | Recipe.Input.Bundle -> ["bundle"]
          | Checkpoint s -> [Stage.to_string s ^ "_checkpoint"] in
        Action.make ~requires:(match previous with None -> [] | Some k -> [k])
          ~inputs ~outputs:[Stage.to_string d.output_checkpoint ^ "_checkpoint"]
          key Action.Segment (Action.Physical d.stage) name :: loop (Some key) ds in
    loop None (Recipe.declarations t.recipe)
  let to_json t =
    if t.schema_version = 2 then obj
      ["schema_version", integer 2; "endpoint", str (Stage.to_string (endpoint t));
       "resume", J.bool (source_boundary t <> None)]
    else obj ["schema_version", integer 3;
              "stages", strings (List.map Stage.to_string (sequence t));
              "initial_boundary", optional_stage (source_boundary t)]
  let of_json value =
    match value with
    | J.Object f when List.assoc_opt "schema_version" f = Some (integer 3) ->
      let* f = fields ["schema_version"; "stages"; "initial_boundary"] value in
      let* stages = array stage (get f "stages") in
      let* initial_boundary = boundary (get f "initial_boundary") in
      resolve_sequence ?initial_boundary stages
    | _ ->
      let* f = fields ["schema_version"; "endpoint"; "resume"] value in
      let* () = match get f "schema_version" with J.Integer "2" -> Ok () | _ -> Error "expected integer schema 2 or 3" in
      let* endpoint = stage (get f "endpoint") in
      let* resume = boolean (get f "resume") in
      resolve ~resume endpoint
end

type t = Coarse of Coarse.t | Stages of Stage_plan.t
let of_coarse p = Coarse p
let of_stages p = Stages p
let of_json value = match value with
  | J.Object f when List.assoc_opt "schema_version" f = Some (integer 1) ->
    let* p = Coarse.of_json value in Ok (Coarse p)
  | _ -> let* p = Stage_plan.of_json value in Ok (Stages p)
let parse text = let* value = codec (J.parse text) in of_json value
let to_json = function Coarse p -> Coarse.to_json p | Stages p -> Stage_plan.to_json p
let actions = function Coarse p -> Coarse.actions p | Stages p -> Stage_plan.actions p
let capabilities () = obj (List.map (fun s ->
  let c = Stage.capability s in
  Stage.to_string s, obj
    ["endpoint", str c.endpoint; "successor", (match c.successor with None -> J.null | Some s -> str s);
     "restart_supported", J.bool (c.restart_targets <> []);
     "restart_targets", strings (List.map Stage.to_string c.restart_targets);
     "tested_image_id", str c.tested_image_id;
     "closure_scope", (match c.closure_scope with Path_bound -> str "path_bound");
     "acceptance", (match c.acceptance with Not_evaluated -> str "not_evaluated")]) Stage.all)
let inspection t =
  let source, sequence = match t with
    | Coarse _ -> J.null, J.null
    | Stages p -> optional_stage (Stage_plan.source_boundary p),
                  strings (List.map Stage.to_string (Stage_plan.sequence p)) in
  obj ["plan", to_json t; "actions", J.array (List.map Action.to_json (actions t));
        "source_boundary", source; "sequence", sequence; "capabilities", capabilities ();
        "operation_groups", Classic_contract.groups ();
        "operation_sequence", (match t with Coarse _ -> J.null
          | Stages p -> Classic_contract.sequence (Stage_plan.sequence p))]
