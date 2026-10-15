open! Core
module J = Plan_json
module C = Hardcaml_asic_flow_domain.Catalog
module M = Hardcaml_asic_flow_domain.Methodology
module P = Hardcaml_asic_flow_domain.Parameter
module S = Hardcaml_asic_flow_domain.Selection

let str s = `String s
let id x = str (S.Id.to_string x)
let arr f xs = `List (List.map xs ~f)
let obj xs = `Assoc xs
let wrap contract xs = obj ([ "contract", str contract; "schema_version", `Int 1 ] @ xs)

let value = function
  | P.Strategy s -> str (P.Strategy.to_string s)
  | P.Bool b -> `Bool b
;;

let assignment_to_yojson a =
  obj
    [ "key", str (P.Key.to_string (P.assignment_key a))
    ; "value", value (P.assignment_value a)
    ]
;;

let assignment_read j =
  J.object_ j ~fields:[ "key"; "value" ];
  let key = J.string (J.get j "key") in
  J.checked
    (match J.get j "value" with
     | `String s -> P.of_string_value ~key s
     | `Bool b -> P.of_bool_value ~key b
     | _ -> Or_error.error_string "typed assignment requires enum string or boolean")
;;

let assignment_of_yojson j = J.decode (fun () -> assignment_read j)
let assignments = arr assignment_to_yojson
let read_assignments j = List.map (J.array j) ~f:assignment_read

let selection_to_yojson s =
  obj
    [ "flow", Option.value_map (S.flow s) ~default:`Null ~f:id
    ; "profile", Option.value_map (S.profile s) ~default:`Null ~f:id
    ]
;;

let selection_read j =
  J.object_ j ~fields:[ "flow"; "profile" ];
  let opt k =
    match J.get j k with
    | `Null -> None
    | x -> Some (J.string x)
  in
  J.checked (S.create ?flow:(opt "flow") ?profile:(opt "profile") ())
;;

let selection_of_yojson j = J.decode (fun () -> selection_read j)

let methodology m =
  obj
    [ "id", id (M.id m)
    ; "label", str (M.label m)
    ; "description", str (M.description m)
    ; "backend_recipe", str (M.Backend_recipe.to_string (M.backend_recipe m))
    ; "input", str "fresh"
    ; "endpoints", arr (fun s -> str (Stage.to_string s)) (M.endpoints m)
    ; "configurable", arr (fun k -> str (P.Key.to_string k)) (M.configurable m)
    ; "defaults", assignments (M.defaults m)
    ]
;;

let methodology_read j =
  J.object_
    j
    ~fields:
      [ "id"
      ; "label"
      ; "description"
      ; "backend_recipe"
      ; "input"
      ; "endpoints"
      ; "configurable"
      ; "defaults"
      ];
  let text k = J.string (J.get j k) in
  if not (String.equal (text "input") "fresh") then J.fail "only fresh input supported";
  J.checked
    (M.create
       ~id:(text "id")
       ~label:(text "label")
       ~description:(text "description")
       ~backend_recipe:(J.checked (M.Backend_recipe.of_string (text "backend_recipe")))
       ~endpoints:
         (List.map
            (J.array (J.get j "endpoints"))
            ~f:(fun x -> J.checked (Stage.of_string (J.string x))))
       ~configurable:
         (List.map
            (J.array (J.get j "configurable"))
            ~f:(fun x -> J.checked (P.Key.of_string (J.string x))))
       ~defaults:(read_assignments (J.get j "defaults")))
;;

let profile p =
  obj
    [ "id", id (Hardcaml_asic_flow_domain.Profile.id p)
    ; "label", str (Hardcaml_asic_flow_domain.Profile.label p)
    ; "description", str (Hardcaml_asic_flow_domain.Profile.description p)
    ; "assignments", assignments (Hardcaml_asic_flow_domain.Profile.assignments p)
    ]
;;

let profile_read j =
  J.object_ j ~fields:[ "id"; "label"; "description"; "assignments" ];
  let text k = J.string (J.get j k) in
  J.checked
    (Hardcaml_asic_flow_domain.Profile.create
       ~id:(text "id")
       ~label:(text "label")
       ~description:(text "description")
       ~assignments:(read_assignments (J.get j "assignments")))
;;

let entry e =
  obj
    [ "methodology", methodology (C.Entry.methodology e)
    ; "profiles", arr profile (C.Entry.profiles e)
    ; "default_profile", id (C.Entry.default_profile e)
    ]
;;

let entry_read j =
  J.object_ j ~fields:[ "methodology"; "profiles"; "default_profile" ];
  J.checked
    (C.Entry.create
       ~methodology:(methodology_read (J.get j "methodology"))
       ~profiles:(List.map (J.array (J.get j "profiles")) ~f:profile_read)
       ~default_profile:(J.string (J.get j "default_profile")))
;;

let declaration_to_yojson c =
  wrap
    "hardcaml-asic.flow-catalog"
    [ "entries", arr entry (C.entries c); "default", selection_to_yojson (C.default c) ]
;;

let declaration_read j =
  J.envelope j ~contract:"hardcaml-asic.flow-catalog" ~fields:[ "entries"; "default" ];
  let s = selection_read (J.get j "default") in
  let required = function
    | Some x -> S.Id.to_string x
    | None -> J.fail "catalog default must be explicit"
  in
  J.checked
    (C.create
       ~entries:(List.map (J.array (J.get j "entries")) ~f:entry_read)
       ~default_flow:(required (S.flow s))
       ~default_profile:(required (S.profile s)))
;;

let declaration_of_yojson j = J.decode (fun () -> declaration_read j)

let declaration_of_string s =
  J.decode (fun () -> declaration_read (Yojson.Safe.from_string s))
;;

let descriptors =
  arr
    (fun d ->
      obj
        [ "key", str (P.Key.to_string (P.key d))
        ; ( "type"
          , str
              (match P.value_type d with
               | Enum -> "enum"
               | Boolean -> "boolean") )
        ; "allowed_values", arr value (P.allowed_values d)
        ; "backend_documented_default", value (P.backend_default d)
        ; "unspecified", str "runtime-backend-default-not-observed"
        ; "units", Option.value_map (P.units d) ~default:`Null ~f:str
        ; "meaning", str (P.meaning d)
        ; "backend_consumer", str (P.backend_consumer d)
        ])
    P.descriptors
;;

let capabilities =
  obj
    [ "backend_recipe", str "librelane.classic.v1"
    ; "input", str "fresh"
    ; "stage_selection", str "complete-prefix-through-declared-endpoint"
    ; "continuation", `Bool false
    ; "arbitrary_overrides", `Bool false
    ; ( "selection"
      , obj
          [ "flow", str "stable-id-or-null"
          ; "profile", str "stable-id-or-null"
          ; "profile_requires_flow", `Bool true
          ; "unknown_selection", str "error"
          ; "no_selection", str "catalog-default-pair"
          ; "flow_only", str "entry-default-profile"
          ] )
    ]
;;

let list_to_yojson c =
  wrap
    "hardcaml-asic.flow-list"
    [ "declaration", declaration_to_yojson c
    ; "parameter_descriptors", descriptors
    ; "capabilities", capabilities
    ]
;;

let list_of_yojson j =
  J.decode (fun () ->
    J.envelope
      j
      ~contract:"hardcaml-asic.flow-list"
      ~fields:[ "declaration"; "parameter_descriptors"; "capabilities" ];
    if not (J.equal (J.get j "capabilities") capabilities)
    then J.fail "capability contract mismatch";
    if not (J.equal (J.get j "parameter_descriptors") descriptors)
    then J.fail "descriptor contract mismatch";
    declaration_read (J.get j "declaration"))
;;

let describe_to_yojson e =
  wrap
    "hardcaml-asic.flow-describe"
    [ "entry", entry e
    ; "parameter_descriptors", descriptors
    ; "capabilities", capabilities
    ]
;;

let describe_of_yojson j =
  J.decode (fun () ->
    J.envelope
      j
      ~contract:"hardcaml-asic.flow-describe"
      ~fields:[ "entry"; "parameter_descriptors"; "capabilities" ];
    if not (J.equal (J.get j "capabilities") capabilities)
    then J.fail "capability contract mismatch";
    if not (J.equal (J.get j "parameter_descriptors") descriptors)
    then J.fail "descriptor contract mismatch";
    entry_read (J.get j "entry"))
;;

let origin = function
  | P.Methodology -> "methodology"
  | Profile -> "profile"
  | Request -> "request"
;;

let contribution c =
  obj
    [ "assignment", assignment_to_yojson (P.assignment c)
    ; "origin", str (origin (P.origin c))
    ]
;;

let parameters r =
  arr
    (fun p ->
      obj
        [ "winning", contribution (P.winning p)
        ; "overridden", arr contribution (P.overridden p)
        ])
    (C.parameters r)
;;

let selected r =
  J.checked
    (S.create
       ~flow:(S.Id.to_string (M.id (C.Entry.methodology (C.entry r))))
       ~profile:(S.Id.to_string (Hardcaml_asic_flow_domain.Profile.id (C.profile r)))
       ())
;;

let request r =
  List.filter_map (C.parameters r) ~f:(fun p ->
    let w = P.winning p in
    if P.equal_origin (P.origin w) P.Request then Some (P.assignment w) else None)
;;

let resolved_to_yojson r =
  wrap
    "hardcaml-asic.flow-snapshot"
    [ "declaration", declaration_to_yojson (C.declaration r)
    ; "selected", selection_to_yojson (selected r)
    ; "definition", entry (C.entry r)
    ; "profile", profile (C.profile r)
    ; "endpoint", str (Stage.to_string (C.endpoint r))
    ; "stages", arr (fun s -> str (Stage.to_string s)) (C.stages r)
    ; "request", assignments (request r)
    ; "parameters", parameters r
    ]
;;

let resolved_of_yojson j =
  J.decode (fun () ->
    J.envelope
      j
      ~contract:"hardcaml-asic.flow-snapshot"
      ~fields:
        [ "declaration"
        ; "selected"
        ; "definition"
        ; "profile"
        ; "endpoint"
        ; "stages"
        ; "request"
        ; "parameters"
        ];
    let r =
      J.checked
        (C.resolve
           (declaration_read (J.get j "declaration"))
           ~selection:(selection_read (J.get j "selected"))
           ~request:(read_assignments (J.get j "request"))
           ~endpoint:(J.checked (Stage.of_string (J.string (J.get j "endpoint"))))
           ())
    in
    (* Re-encoding is also an exact recursive schema check for asserted evidence. *)
    if not (J.equal j (resolved_to_yojson r))
    then J.fail "snapshot differs from checked resolution";
    r)
;;
