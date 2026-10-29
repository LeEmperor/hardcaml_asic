(* Deliberately not a Tcl interpreter. Only complete words in a closed native
   serialization grammar are accepted; no substitution/eval or tool invocation. *)
let fail x = invalid_arg ("native coverage: " ^ x)
let s x = `String x
let obj x = `Assoc x
let arr x = `List x
let get j k = match j with
  | `Assoc xs -> (match List.assoc_opt k xs with Some x -> x | None -> fail ("missing "^k))
  | _ -> fail "expected object"
let exact j keys = match j with
  | `Assoc xs when List.sort String.compare (List.map fst xs)=List.sort String.compare keys -> ()
  | _ -> fail "unexpected object fields"
let text = function
  | `String x when String.length x<=65536 && not (String.contains x '\000') -> x
  | _ -> fail "invalid bounded string"
let nonempty j = let x=text j in if String.trim x="" then fail "empty string";x
let list = function `List xs when List.length xs<=65536 -> xs | _ -> fail "invalid bounded array"
let count j n = if j<>`Int n then fail "count mismatch"
let strict raw =
  (* Bound structure before allocating either JSON tree. Strings remain checked
     by the Unicode/duplicate-key parser below. *)
  let quoted=ref false and escaped=ref false and depth=ref 0 and tokens=ref 0 in
  String.iter (fun c ->
    if !quoted then (
      if !escaped then escaped:=false
      else if c='\\' then escaped:=true
      else if c='"' then quoted:=false)
    else if c='"' then quoted:=true
    else (
      if c='{' || c='[' then incr depth;
      if c='}' || c=']' then decr depth;
      if List.mem c ['{';'[';',';':'] then incr tokens;
      if !depth>16 || !tokens>524288 then fail "JSON structural budget")) raw;
  (match Identity_json.parse raw with Ok _ -> () | Error e -> fail (Identity_json.error_message e));
  Yojson.Safe.from_string raw
let bounded raw = if String.length raw=0 || String.length raw>8*1024*1024 then fail "file byte budget"
let contract="hardcaml-asic.timing-native-coverage"
let profile="opensta-2.7-native-state-v2"
let categories=["no_input_delay";"no_output_delay";"multiple_clock";"no_clock";
                "unconstrained_endpoints";"loops";"generated_clocks"]

type word = Literal of string | Query of word list

let commands raw =
  bounded raw;
  (* Tcl source channels normalize CR/CRLF before lexical comment decisions.
     The qualified native writer emits LF; reject other newline spellings before
     any token/comment handling rather than interpreting their bytes as spaces. *)
  if String.contains raw '\r' then fail "CR in native SDC is unsupported; qualified serialization is LF-only";
  if String.contains raw '\000' then fail "NUL in SDC";
  if not (String.ends_with ~suffix:"\n" raw) then fail "truncated native SDC (missing final newline)";
  let length=String.length raw and pos=ref 0 and tokens=ref 0 in
  let peek () = if !pos<length then raw.[!pos] else '\000' in
  let space = function ' '| '\t' | '\r' -> true | _ -> false in
  let continuation () = !pos+1<length && raw.[!pos]='\\' && raw.[!pos+1]='\n' in
  let indentation () =
    while !pos<length && (raw.[!pos]=' ' || raw.[!pos]='\t') do incr pos done in
  let rec whitespace () =
    if space (peek ()) then (incr pos;whitespace ())
    else if continuation () then (pos:= !pos+2;whitespace ()) in
  let boundary c = space c || List.mem c ['\n';';';']';'\000'] in
  let add b c = Buffer.add_char b c;
    if Buffer.length b>65536 then fail "SDC word budget" in
  let rec word depth =
    incr tokens;
    if depth>16 || !tokens>262144 then fail "SDC token/depth budget";
    let b=Buffer.create 32 in
    let result=match peek () with
    | '{' ->
      incr pos;
      let rec brace level =
        if !pos>=length then fail "unterminated braces";
        let c=peek () in incr pos;
        match c with
        | '{' -> if level>=16 then fail "brace depth budget";add b c;brace (level+1)
        | '}' -> if level>1 then (add b c;brace (level-1))
        | '\\' -> (* Braced Tcl preserves escapes except newline folding. *)
          if peek ()='\n' then (incr pos;indentation ();add b ' ';brace level)
          else (add b c;if !pos>=length then fail "truncated escape";
                add b (peek ());incr pos;brace level)
        | '\000' -> fail "NUL in SDC"
        | _ -> add b c;brace level in
      brace 1;Literal (Buffer.contents b)
    | '[' ->
      incr pos;
      let xs=words (depth+1) true in
      if peek ()<>']' then fail "unterminated query";
      incr pos;Query xs
    | '"' ->
      incr pos;
      let rec quoted () = match peek () with
        | '\000' -> fail "unterminated quote"
        | '"' -> incr pos
        | '$'|'[' -> fail "substitution in quoted word"
        | '\\' -> escape b;quoted ()
        | c -> incr pos;add b c;quoted () in
      quoted ();Literal (Buffer.contents b)
    | c when boundary c -> fail "empty SDC word"
    | _ ->
      let rec bare () = match peek () with
        | c when boundary c -> ()
        (* Tcl's pre-parser replaces backslash-newline plus indentation with
           whitespace. Outside quotes/braces it terminates the current word,
           even when the native writer omitted a preceding space. *)
        | '\\' when continuation () -> ()
        | '$'|'['|'{'|'}'|'"' -> fail "unsupported compound/substitution word"
        | '\\' -> escape b;bare ()
        | c -> incr pos;add b c;bare () in
      bare ();Literal (Buffer.contents b) in
    if not (boundary (peek ())) && not (continuation ()) then fail "compound SDC word";
    result
  and escape b =
    incr pos;
    if !pos>=length then fail "truncated escape";
    let c=peek () in incr pos;
    if c='\n' then (add b ' ';indentation ())
    else if List.mem c ['\\';'"';'[';']';'$';' ';'{';'}';';'] then add b c
    else fail "unsupported SDC escape"
  and words depth query =
    let rec loop acc =
      whitespace ();
      match peek () with
      | '\000' -> List.rev acc
      | ']' when query -> List.rev acc
      | '\n'|';' when query -> fail "multiple commands in query"
      | '\n'|';' -> List.rev acc
      | _ -> let w=word depth in loop (w::acc) in
    loop [] in
  let rec script n acc =
    if n>65536 then fail "SDC command budget";
    whitespace ();
    match peek () with
    | '\000' -> if !pos<>length then fail "NUL in SDC";List.rev acc
    | '\n'|';' -> incr pos;script n acc
    | '#' ->
      let start= !pos in
      while !pos<length && peek ()<>'\n' do incr pos done;
      let last=if !pos>start && raw.[!pos-1]='\r' then !pos-2 else !pos-1 in
      if last>=start && raw.[last]='\\' then
        fail "continued native SDC comment is unsupported";
      script n acc
    | ']' -> fail "unmatched query close"
    | _ -> let xs=words 0 false in script (n+1) (xs::acc) in
  script 0 []

let literal = function Literal x -> x | Query _ -> fail "expected literal word"
let name x =
  (* Qualified exact-name subset. Bracketed decimal bit suffixes are native bus
     names, not arbitrary glob character classes. No wildcard normalization. *)
  let n=String.length x in
  if n=0 then fail "empty selector";
  let rec check i = if i<n then match x.[i] with
    | 'a'..'z'|'A'..'Z'|'0'..'9'|'_'|'/'|'.'|':'|'$' -> check (i+1)
    | '[' ->
      let j=ref (i+1) in
      while !j<n && x.[!j]>='0' && x.[!j]<='9' do incr j done;
      if !j=i+1 || !j>=n || x.[!j]<>']' then fail "broad/unsupported selector";
      check (!j+1)
    | _ -> fail "broad/unsupported selector" in
  check 0;x
let selector_names raw =
  (* This qualified writer emits a simple whitespace-separated list of names.
     General nested Tcl lists and escaped identifiers are not silently guessed. *)
  String.split_on_char ' ' raw |> List.filter (fun x -> x<>"") |> List.map name
let rec selectors kind = function
  | Query (Literal "list"::xs) when xs<>[] -> List.concat_map (selectors kind) xs
  | Query [Literal command; Literal names] when command=kind ->
    let xs=selector_names names in if xs=[] then fail "empty selector list";xs
  | _ -> fail ("unsupported/broad "^kind^" selector")
let base_commands = ["current_design";"create_clock";"set_clock_uncertainty";
  "set_clock_latency";"set_clock_transition";"set_input_delay";"set_output_delay";
  "set_driving_cell";"set_load";"set_input_transition";"set_operating_conditions";
  "set_max_transition";"set_max_fanout";"set_max_capacitance";"set_min_capacitance";
  "set_voltage";"set_units";"set_wire_load_mode";"set_wire_load_model";
  "set_wire_load_selection_group";"set_port_fanout_number";"set_drive";"set_resistance"]
let rec base_word = function
  | Literal _ -> ()
  | Query [Literal "current_design"] -> ()
  | Query (Literal "list"::xs) -> List.iter base_word xs
  | Query (Literal command::xs) when List.mem command
      ["get_ports";"get_pins";"get_clocks";"get_lib_cells";"get_lib_pins";"get_nets"] ->
    List.iter (fun x -> ignore (literal x)) xs
  | _ -> fail "unsupported base query"
let timing_derate = function
  (* Qualify the observed global native writer forms only. No object-scoped,
     incremental, transition/check-type, or other guessed options. In particular
     zero/negative/nonfinite factors must not masquerade as ordinary derating. *)
  | [Literal direction; Literal value] when List.mem direction ["-early";"-late"] ->
    let decimal =
      let digits=ref 0 and dots=ref 0 in
      String.iter (function
        | '0'..'9' -> incr digits
        | '.' -> incr dots
        | _ -> dots:=2) value;
      !digits>0 && !dots<=1 in
    if not decimal then fail "unsupported timing derate factor";
    let factor=try float_of_string value with Failure _ -> fail "invalid timing derate factor" in
    if not (Float.is_finite factor) || factor<=0. ||
       (direction="-early" && factor>1.) || (direction="-late" && factor<1.)
    then fail "unsupported timing derate factor/range"
  | _ -> fail "unsupported timing derate scope/options"
module Relations = Set.Make(struct type t=string*string let compare=compare end)
let relation_set ~top native_sdc =
  ignore (name top);
  let body=match commands native_sdc with
    | (Literal "current_design"::[Literal design])::body ->
      ignore (name design);
      if design<>top then fail "native current_design differs from manifest top";
      body
    | _ -> fail "missing leading native current_design" in
  let relations=ref Relations.empty and expanded=ref 0 in
  List.iter (function
    | Literal "set_false_path"::args ->
      let rec options from targets = function
        | [] -> (match from,targets with
          | Some f,Some t -> f,t | _ -> fail "missing exact false-path source/targets")
        | Literal "-from"::value::rest when from=None -> options (Some (selectors "get_ports" value)) targets rest
        | Literal "-to"::value::rest when targets=None -> options from (Some (selectors "get_pins" value)) rest
        | _ -> fail "restricted/unsupported false-path option (transition/setup/hold/broad scope)" in
      let from,targets=options None None args in
      List.iter (fun f -> List.iter (fun t ->
        incr expanded;if !expanded>65536 then fail "expanded relation budget";
        relations:=Relations.add (f,t) !relations) targets) from
    | Literal "set_timing_derate"::args -> timing_derate args
    | Literal "current_design"::_ -> fail "repeated/ambiguous current_design selection"
    | Literal command::args when List.mem command base_commands && args<>[] -> List.iter base_word args
    | Literal command::_ -> fail ("unsupported native SDC command: "^command)
    | _ -> fail "invalid native SDC command") body;
  !relations
let expected_set resolved =
  if List.length resolved>256 then fail "resolved inventory budget";
  let set=ref Relations.empty in
  List.iter (fun row ->
    let from=nonempty (get row "source") in
    let targets=list (get row "targets") in
    if List.length targets>256 then fail "resolved target budget";
    List.iter (fun target -> set:=Relations.add (from,nonempty target) !set) targets) resolved;
  !set
let relation_json relations =
  Relations.elements relations |> List.map (fun (from,target) -> obj [
    "source",s from;"target",s target;"min_max",s "both";
    "source_transition",s "both";"target_transition",s "both"])

let inspect ~top ~resolved ~native_sdc ~native_data ~native_checks ~native_endpoints =
  try
    List.iter bounded [native_sdc;native_data;native_checks;native_endpoints];
    let actual=relation_set ~top native_sdc and expected=expected_set resolved in
    if not (Relations.is_empty (Relations.diff expected actual)) then fail "missing exception relations";
    if not (Relations.is_empty (Relations.diff actual expected)) then fail "extra exception relations";
    let data=strict native_data in
    exact data ["schema";"contract";"profile";"complete";"categories";"endpoint_count";"endpoints"];
    if get data "schema"=`Int 1 || get data "profile"=s "opensta-2.7-native-state-v1" then
      fail "unsupported legacy native profile 1; recapture with category-bound profile 2";
    if get data "schema"<>`Int 2 || get data "contract"<>s contract || get data "profile"<>s profile
       || get data "complete"<>`Bool true then fail "unsupported/incomplete native wire";
    let cats=list (get data "categories") in
    if List.map (fun cat -> text (get cat "name")) cats<>categories then fail "missing/reordered/duplicate diagnostic categories";
    let records=ref 0 and report=Buffer.create 256 in
    Buffer.add_string report "HC_ASIC_NATIVE_CHECKS_V2 opensta-2.7-native-state-v2\n";
    let diagnostic_text value =
      let value=text value in
      List.iter (fun line ->
        if String.starts_with ~prefix:"HC_ASIC_NATIVE_" (String.trim line) then
          fail "diagnostic contains reserved marker line") (String.split_on_char '\n' value);
      value in
    List.iter (fun cat ->
      exact cat ["name";"group_count";"groups"];
      let groups=list (get cat "groups") in
      count (get cat "group_count") (List.length groups);
      let category=text (get cat "name") in
      Buffer.add_string report ("HC_ASIC_NATIVE_CATEGORY_BEGIN "^category^"\n");
      List.iter (fun group ->
        exact group ["message";"details"];
        let message=diagnostic_text (get group "message") and details=list (get group "details") in
        if String.trim message="" then fail "empty diagnostic message";
        records:= !records+1+List.length details;
        if !records>65536 then fail "diagnostic record budget";
        Buffer.add_string report (message^"\n");
        List.iter (fun detail -> Buffer.add_string report ("  "^diagnostic_text detail^"\n")) details) groups;
      Buffer.add_string report ("HC_ASIC_NATIVE_CATEGORY_END "^category^"\n")) cats;
    Buffer.add_string report "HC_ASIC_NATIVE_CHECKS_V2_COMPLETE\n";
    if Buffer.contents report<>native_checks then fail "native check report differs from diagnostic groups";
    let endpoints=list (get data "endpoints") |> List.map nonempty in
    count (get data "endpoint_count") (List.length endpoints);
    (* Tcl -ascii compares Unicode code points; UTF-8 byte ordering agrees. *)
    if endpoints<>List.sort_uniq String.compare endpoints then fail "unsorted/duplicate native endpoints";
    let line_count=ref 0 in
    String.iter (fun c -> if c='\n' then incr line_count) native_endpoints;
    if !line_count>65537 then fail "endpoint report line budget";
    let lines=String.split_on_char '\n' native_endpoints in
    let rec endpoint_lines acc = function
      | ["HC_ASIC_NATIVE_ENDPOINTS_COMPLETE";""] -> List.rev acc
      | line::rest -> endpoint_lines (nonempty (strict line)::acc) rest
      | _ -> fail "missing endpoint report completion" in
    if endpoint_lines [] lines<>endpoints then fail "native endpoint report differs from inventory";
    Ok (obj ["status",s "interpreted_supported_dimensions";
      "profile",s profile;
      "native_design",s top;
      "stored_exception_scope",obj ["status",s "matched";"method",s "native_write_sdc";
        "relation_count",`Int (Relations.cardinal actual);"relations",arr (relation_json actual)];
      "diagnostics",obj ["status",s "complete_returned_native_groups";"categories",arr cats];
      "endpoints",obj ["status",s "complete_native_inventory";"count",`Int (List.length endpoints);"pins",arr (List.map s endpoints)];
      "per_check_analysis",s "unavailable";"exhaustive_exception_effect",s "unavailable";
      "timing_closure",s "not_established"])
  with Invalid_argument e | Failure e -> Error e
     | Yojson.Json_error e -> Error ("native coverage: invalid JSON: "^e)
