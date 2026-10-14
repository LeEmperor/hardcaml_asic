module J = Identity_json
type source = Legacy | Runtime_policy
type t = { source : source; python_minor : string; librelane : string }
let supported_minors = ["3.10"; "3.11"; "3.12"; "3.13"; "3.14"]
let requires_python = ">=3.10"
let image_ref t = "ghcr.io/librelane/librelane:" ^ t.librelane
let unwrap = function Ok x -> x | Error e -> invalid_arg (J.error_message e)
let s x = unwrap (J.string x)
let obj x = unwrap (J.object_ x)
let protect f = try Ok (f ()) with Invalid_argument e -> Error e
let object_fields = function J.Object x -> x | _ -> invalid_arg "expected object"
let get j k = Option.value (List.assoc_opt k (object_fields j)) ~default:J.null
let exact j keys = ignore (unwrap (J.exact_object j ~fields:keys))
let eq a b = if a <> b then invalid_arg "contradictory or unsupported runtime policy"
let str = function J.String x when x <> "" -> x | _ -> invalid_arg "invalid string"
let digits x = x <> "" && String.for_all (fun c -> c >= '0' && c <= '9') x
let number x = digits x && (String.length x = 1 || x.[0] <> '0')
let minor x = match String.split_on_char '.' x with [a;b] -> number a && number b | _ -> false
let python_minor = function
  | J.String x -> (match String.split_on_char '.' x with
    | [a;b;c] when number a && number b && number c -> Some (a ^ "." ^ b)
    | _ -> None)
  | _ -> None
let ll_version x =
  match String.split_on_char '.' x with
  | [a;b;c] -> List.for_all digits [a;b;c]
  | [a;b;c;d] -> List.for_all digits [a;b;c] &&
    List.exists (fun prefix -> String.starts_with ~prefix d &&
      digits (String.sub d (String.length prefix) (String.length d - String.length prefix)))
      ["dev"; "a"; "b"; "rc"]
  | _ -> false
let host t = obj ["python", obj ["policy", s "exact-minor"; "version", s t.python_minor]]
let implementation t =
  let policy, python = match t.source with
    | Legacy -> "legacy-exact-minor", obj ["policy", s "exact-minor"; "version", s t.python_minor]
    | Runtime_policy -> "official-librelane-image", obj
      ["policy", s "distribution-supported"; "requires_python", s requires_python;
       "supported_minors", J.array (List.map s supported_minors)] in
  obj ["native", obj ["policy", s "host-runtime"];
       "dockerized", obj ["policy", s policy; "image_ref", s (image_ref t); "python", python]]
let to_json t = obj ["schema_version", unwrap (J.integer "1");
  "source", s (match t.source with Legacy -> "legacy" | Runtime_policy -> "runtime-policy");
  "librelane", s t.librelane; "host", host t; "implementation", implementation t]
let requested j =
  let fields = object_fields j in
  let python_minor = str (get j "python") and librelane = str (get j "librelane") in
  if not (minor python_minor && ll_version librelane) then invalid_arg "invalid runtime version";
  let source = if List.mem_assoc "runtime_policy" fields then Runtime_policy else Legacy in
  let t = {source; python_minor; librelane} in
  (match source with Legacy -> () | Runtime_policy ->
    let p = get j "runtime_policy" in
    exact p ["schema_version"; "host"; "implementation"];
    eq (get p "schema_version") (unwrap (J.integer "1"));
    eq (get p "host") (host t);
    let impl = get p "implementation" in
    exact impl ["native"; "dockerized"];
    eq (get impl "native") (obj ["policy", s "host-runtime"]);
    let d = get impl "dockerized" in
    exact d ["policy"; "image_ref"; "python"];
    eq (get d "policy") (s "official-librelane-image");
    eq (get d "image_ref") (s (image_ref t));
    let dp = get d "python" in
    exact dp ["policy"; "requires_python"; "supported_minors"];
    eq (get dp "policy") (s "distribution-supported");
    eq (get dp "requires_python") (s requires_python);
    let minors = match get dp "supported_minors" with J.Array xs -> List.map str xs
      | _ -> invalid_arg "invalid supported minors" in
    eq (List.sort String.compare minors) supported_minors);
  t
let policy_from_requested j = protect (fun () -> requested j)
let policy_from_lock j = protect (fun () ->
  let g k = s (str (get j k)) in
  eq (g "runtime_policy_schema_version") (s "1");
  requested (obj ["python", g "python"; "librelane", g "librelane_version";
    "runtime_policy", obj ["schema_version", unwrap (J.integer "1");
      "host", obj ["python", obj ["policy", g "runtime_host_python_policy";
                                 "version", g "runtime_host_python_version"]];
      "implementation", obj ["native", obj ["policy", g "runtime_native_policy"];
        "dockerized", obj ["policy", g "runtime_dockerized_policy";
          "image_ref", g "runtime_dockerized_image_ref";
          "python", obj ["policy", g "runtime_dockerized_python_policy";
            "requires_python", g "runtime_dockerized_requires_python";
            "supported_minors", J.array (List.map s (String.split_on_char ','
              (str (get j "runtime_dockerized_supported_minors"))))]]]]]))
let of_json j = protect (fun () ->
  exact j ["schema_version"; "source"; "librelane"; "host"; "implementation"];
  eq (get j "schema_version") (unwrap (J.integer "1"));
  let h = get j "host" in
  exact h ["python"];
  exact (get h "python") ["policy"; "version"];
  let fields = ["python", get (get h "python") "version"; "librelane", get j "librelane"] in
  let fields = match str (get j "source") with
    | "legacy" -> fields
    | "runtime-policy" -> ("runtime_policy", obj ["schema_version", get j "schema_version";
        "host", h; "implementation", get j "implementation"]) :: fields
    | _ -> invalid_arg "unknown contract source" in
  let t = requested (obj fields) in
  eq j (to_json t); t)
let parse text = match J.parse text with Error e -> Error (J.error_message e) | Ok j -> of_json j
type role = Host | Container
type status = Pass | Fail | Waived
type comparison = {role : role; field : string; expected : J.t; actual : J.t; status : status}
type evaluation = {contract : t; native : bool; comparisons : comparison list;
                   issues : comparison list; waivers : comparison list}
let evaluate t ~host ?container ?(native=false) ?(allow_python_mismatch=false) () = protect (fun () ->
  ignore (object_fields host);
  let rows = ref [] in
  let compare role field expected actual passed waivable =
    let status = if passed then Pass else if waivable && allow_python_mismatch then Waived else Fail in
    rows := {role; field; expected; actual; status} :: !rows in
  let python role observation exact =
    let actual = get observation "python_version" in
    let m = python_minor actual in
    let expected = if exact then s t.python_minor else J.array (List.map s supported_minors) in
    let passed = match m with None -> false | Some m ->
      if exact then m = t.python_minor else List.mem m supported_minors in
    compare role "python_version" expected actual passed
      (m <> None && exact && t.source = Legacy) in
  python Host host true;
  if not native then (
    let c = match container with Some c -> c | None -> invalid_arg "missing container observation" in
    ignore (object_fields c);
    python Container c (t.source = Legacy);
    let actual = get c "librelane_version" in
    compare Container "librelane_version" (s t.librelane) actual (actual = s t.librelane) false;
    if t.source = Runtime_policy then (
      let actual = get c "requires_python" in
      compare Container "requires_python" (s requires_python) actual (actual = s requires_python) false));
  let comparisons = List.rev !rows in
  {contract=t; native; comparisons;
   issues=List.filter (fun r -> r.status = Fail) comparisons;
   waivers=List.filter (fun r -> r.status = Waived) comparisons})
let comparison_to_json r = obj ["role", s (match r.role with Host -> "host" | Container -> "container");
  "field", s r.field; "expected", r.expected; "actual", r.actual;
  "status", s (match r.status with Pass -> "pass" | Fail -> "fail" | Waived -> "waived")]
let evaluation_to_json r = obj ["contract", to_json r.contract; "native", J.bool r.native;
  "comparisons", J.array (List.map comparison_to_json r.comparisons);
  "issues", J.array (List.map comparison_to_json r.issues);
  "waivers", J.array (List.map comparison_to_json r.waivers)]
