(* Pure native per-process metric interpretation. Input-state/inherited metrics
   and sampled report_checks paths are deliberately not measurement authority. *)
module L = Timing_intent_linked
let get = L.get
let s x = `String x
let finite = function
  | `Int n -> Some (float_of_int n)
  | `Intlit raw -> (match float_of_string_opt raw with Some n when Float.is_finite n -> Some n | _ -> None)
  | `Float n when Float.is_finite n -> Some n
  | _ -> None
let interpret ~corner ~log ~output_state ~libraries =
  let unit_ok = libraries<>[] && List.for_all (fun raw ->
    match Liberty_unit_evidence.parse raw with [(_,"1ns",_)],[] -> true | _ -> false) libraries in
  let lines=String.split_on_char '\n' log in
  L.require (List.length lines<=262144) "native metric log line bound";
  let observations=List.map (fun (label,key,count) ->
    let raw_key=key^"__corner:"^corner in
    let tokens=List.filter_map (fun (i,line) ->
      match Str.split (Str.regexp "[ \t]+") line with
      | tag::key::values when key=raw_key && String.starts_with ~prefix:"%OL_METRIC_" tag ->
        Some (i+1,tag,(match values with [value] -> Some value | _ -> None))
      | _ -> None) (List.mapi (fun i line -> i,line) lines) in
    let value=match tokens,finite (get (get output_state "metrics") raw_key) with
      | [(line,tag,Some raw)],Some state ->
        (match float_of_string_opt raw with
         | Some n when Float.is_finite n && abs_float n<1e30 && n=state &&
           (if count then tag="%OL_METRIC_I" && n>=0. && n<=9007199254740991. && floor n=n
            else tag="%OL_METRIC_F" && unit_ok) -> Some (n,line)
         | _ -> None)
      | _ -> None in
    `Assoc ["key",s label;"raw_key",s raw_key;"corner",s corner;
      "value",(match value with Some (n,_) -> `Float n | None -> `Null);
      "line",(match value with Some (_,n) -> `Int n | None -> `Null);
      "unit",(if count then s "count" else if unit_ok then s "ns" else `Null);
      "availability",s (if value=None then "unavailable" else "available")])
    ["setup_slack","timing__setup__ws",false;"hold_slack","timing__hold__ws",false;
     "setup_violations","timing__setup_vio__count",true;"hold_violations","timing__hold_vio__count",true;
     "max_slew_violations","design__max_slew_violation__count",true;
     "max_cap_violations","design__max_cap_violation__count",true] in
  let goal labels =
    let values=List.map (fun label -> let item=List.find (fun j -> get j "key"=s label) observations in finite (get item "value")) labels in
    if List.exists (function Some n -> n<0. | _ -> false) values then "fail"
    else if List.exists (fun label ->
      String.ends_with ~suffix:"violations" label &&
      let item=List.find (fun j -> get j "key"=s label) observations in
      match finite (get item "value") with Some n -> n>0. | None -> false) labels then "fail"
    else if List.for_all Option.is_some values then "pass" else "unknown" in
  `Assoc ["corner",s corner;"metrics",`List observations;
    "setup_goal",s (goal ["setup_slack";"setup_violations"]);
    "hold_goal",s (goal ["hold_slack";"hold_violations"]);
    "electrical_goal",s (goal ["max_slew_violations";"max_cap_violations"])]

let aggregate corners =
  let goals=List.concat_map (fun j -> [get j "setup_goal";get j "hold_goal"]) corners in
  if List.mem (s "fail") goals then "fail"
  else if goals<>[] && List.for_all ((=) (s "pass")) goals then "pass" else "unknown"
