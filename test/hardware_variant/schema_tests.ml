open! Core
open Hardcaml_asic
module H = Hardware_variant
module J = Flow.Plan_json
let ok = Or_error.ok_exn
let checks = ref 0
let check label b = incr checks; if not b then failwith label
let reject label r = check label (Or_error.is_error r)
let param key kind = ok (H.Parameter.create ~key ~kind)
let parameters =
  [param "depth" (Integer {minimum=128;maximum=256});param "enabled" Boolean;
   param "encoding" (Enumeration ["one_hot";"binary"])]
let schema ?(ps=parameters) ?(design_id="memory") ?(schema_id="memory.v1") () =
  H.Schema.create ~design_id ~schema_id ~parameters:ps |> ok
let assignments = ["depth",H.Value.Int 256;"enabled",Bool true;"encoding",Enum "binary"]
let create ?(s=schema ()) a = H.create ~schema:s ~assignments:a
let fields = function `Assoc xs -> xs | _ -> assert false
let set j key value = `Assoc (List.map (fields j) ~f:(fun (k,v) -> k,if String.equal k key then value else v))
let rec reverse = function
  | `Assoc xs -> `Assoc (List.rev_map xs ~f:(fun (k,v) -> k, reverse v))
  | `List xs -> `List (List.map xs ~f:reverse)
  | j -> j
let () =
  let t = create assignments |> ok in
  let text = H.to_string t and j = H.to_yojson t in
  check "roundtrip" (String.equal text (H.to_string (ok (H.of_string text))));
  check "reordered objects" (String.equal text (H.to_string (ok (H.of_yojson (reverse j)))));
  let reordered = create ~s:(schema ~ps:(List.rev parameters) ()) (List.rev assignments) |> ok in
  check "schema/assignment order" (String.equal text (H.to_string reordered));
  check "enum ordering" (Poly.equal (H.Parameter.kind (List.nth_exn (H.Schema.parameters (H.schema t)) 2))
    (H.Parameter.Enumeration ["binary";"one_hot"]));
  let with_value key value = List.map assignments ~f:(fun (k,v) -> k,if String.equal k key then value else v) in
  List.iter [128;256] ~f:(fun n -> ignore (create (with_value "depth" (Int n)) |> ok : H.t));
  List.iter [127;257;-1_000_000_001;1_000_000_001] ~f:(fun n -> reject "integer bounds" (create (with_value "depth" (Int n))));
  List.iter [H.Value.Int 0;Bool false;Enum "other"] ~f:(fun v -> reject "enum closed/type" (create (with_value "encoding" v)));
  reject "boolean type" (create (with_value "enabled" (Int 1)));
  reject "integer type" (create (with_value "depth" (Bool true)));
  reject "missing" (create (List.tl_exn assignments));
  reject "unknown" (create (("unknown",Bool true)::assignments));
  reject "duplicate equal" (create (List.hd_exn assignments::assignments));
  check "typed int getter" (ok (H.get_int t ~key:"depth") = 256);
  check "typed bool getter" (ok (H.get_bool t ~key:"enabled"));
  check "typed enum getter" (String.equal (ok (H.get_enum t ~key:"encoding")) "binary");
  reject "getter wrong type" (H.get_int t ~key:"enabled");
  reject "getter unknown" (H.get_enum t ~key:"unknown");
  List.iter ["";"A";"1a";"a b";"λ";String.make 129 'a'] ~f:(fun key ->
    reject "invalid key" (H.Parameter.create ~key ~kind:Boolean);
    reject "invalid design" (H.Schema.create ~design_id:key ~schema_id:"v1" ~parameters));
  List.iter [H.Parameter.Integer {minimum=2;maximum=1};Integer {minimum= -1_000_000_001;maximum=0};
    Integer {minimum=0;maximum=1_000_000_001};Enumeration [];Enumeration ["a";"a"];
    Enumeration ["bad value"]; Enumeration (List.init 65 ~f:(fun n -> "e" ^ Int.to_string n))] ~f:(fun kind ->
    reject "invalid domain" (H.Parameter.create ~key:"x" ~kind));
  List.iter [[];parameters @ [List.hd_exn parameters];List.init 65 ~f:(fun n -> param ("p" ^ Int.to_string n) Boolean)] ~f:(fun parameters ->
    reject "schema cardinality" (H.Schema.create ~design_id:"d" ~schema_id:"s" ~parameters));
  (* Every semantic identity input changes the declaration digest, independently
     of any hardware-use claim. *)
  List.iter [create (with_value "depth" (Int 128));create (with_value "enabled" (Bool false));
    create (with_value "encoding" (Enum "one_hot"));create ~s:(schema ~design_id:"other" ()) assignments;
    create ~s:(schema ~schema_id:"memory.v2" ()) assignments;
    create ~s:(schema ~ps:(param "depth" (Integer {minimum=64;maximum=256})::List.tl_exn parameters) ()) assignments]
    ~f:(fun r -> check "identity coverage" (not (String.equal (H.identity t) (H.identity (ok r)))));
  let reordered_parameters = set j "parameters" (`List (List.rev (J.array (J.get j "parameters")))) in
  check "wire parameter order" (String.equal text (H.to_string (ok (H.of_yojson reordered_parameters))));
  let tamper_assignment v = set j "assignments" (set (J.get j "assignments") "depth" v) in
  List.iter [`Float 256.;`String "256";`Bool true;`Null;`List [];`Assoc [];`Intlit "256"] ~f:(fun v ->
    reject "strict integer scalar" (H.of_yojson (tamper_assignment v)));
  let assign key value = set j "assignments" (set (J.get j "assignments") key value) in
  List.iter [`Int 1;`String "true";`Null;`Float 1.] ~f:(fun v ->
    reject "strict boolean scalar" (H.of_yojson (assign "enabled" v)));
  List.iter [`Int 0;`Bool true;`Null;`String "unknown"] ~f:(fun v ->
    reject "strict enum scalar" (H.of_yojson (assign "encoding" v)));
  let ps = J.array (J.get j "parameters") in
  let mutate_first f = set j "parameters" (`List (f (List.hd_exn ps)::List.tl_exn ps)) in
  List.iter [mutate_first (fun p -> set p "minimum" (`Float 128.));
    mutate_first (fun p -> `Assoc (("minimum",`Int 128)::fields p));
    mutate_first (fun p -> `Assoc (("extra",`Bool true)::fields p));
    mutate_first (fun p -> set p "type" (`String "arbitrary"));
    set j "assignments" (`Assoc (List.tl_exn (fields (J.get j "assignments"))));
    set j "assignments" (`Assoc (("extra",`Int 0)::fields (J.get j "assignments")))]
    ~f:(fun bad -> reject "nested strict schema" (H.of_yojson bad));
  reject "valid value stale digest" (H.of_yojson (tamper_assignment (`Int 128)));
  List.iter [set j "schema_version" (`Int 2);set j "identity" (`String "bad");
    `Assoc (("unexpected",`Null)::fields j);`Assoc (("identity",J.get j "identity")::fields j);
    set j "assignments" (`Assoc (("depth",`Int 256)::fields (J.get j "assignments")));
    set j "parameters" (`List (List.hd_exn (J.array (J.get j "parameters"))::J.array (J.get j "parameters")))]
    ~f:(fun bad -> reject "strict wire" (H.of_yojson bad));
  List.iter [text ^ " {}";"/* comment */" ^ text;"{" ^ "\"identity\":\"duplicate\"," ^ String.drop_prefix text 1;
    "{\"bad\":\"\\ud800\"}";String.make (128*1024+1) ' ';
    String.make 300 '[' ^ "0" ^ String.make 300 ']'] ~f:(fun s -> reject "strict syntax/limit" (H.of_string s));
  (* Large legal per-field bounds cannot bypass the whole declaration limit. *)
  let big_enum = List.init 64 ~f:(fun n -> "e" ^ Int.to_string n ^ String.make 120 'x') in
  let ps = List.init 64 ~f:(fun n -> param ("p" ^ Int.to_string n) (Enumeration big_enum)) in
  let a = List.map ps ~f:(fun p -> H.Parameter.key p,H.Value.Enum (List.hd_exn big_enum)) in
  reject "total constructor bytes" (H.create ~schema:(schema ~ps ()) ~assignments:a);
  printf "hardware variant schema: %d checks passed\n" !checks
