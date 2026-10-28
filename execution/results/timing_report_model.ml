type role = Data | Launch_clock | Capture_clock
type point = {
  line : int; name : string; instance : string option; pin : string option;
  master : string option; role : role; edge : string; fanout : int option;
  capacitance : float option; slew : float; delay : float; arrival : float;
}
type path = {
  first_line : int; last_line : int; fields : (string * string) list;
  points : point list; data_start : point; data_end : point;
}

let words s = Str.split (Str.regexp "[ \t\r]+") (String.trim s)
let identity s = match words s with x::_ -> x | [] -> ""
let matches header p = identity header = p.name || Some (identity header) = p.instance
let finite label s = match float_of_string_opt s with
  | Some f when Float.is_finite f -> f
  | _ -> invalid_arg ("invalid/nonfinite " ^ label)
let slice line a b =
  if String.length line < b then invalid_arg "truncated timing point columns";
  String.sub line a (b-a) |> String.trim
let optional f s = if s="" then None else Some (f s)
let positive label s = let f=finite label s in
  if f<0. then invalid_arg ("negative "^label); f
let fanout s = match int_of_string_opt s with
  | Some n when n>=0 && String.for_all (function '0'..'9' -> true | _ -> false) s -> n
  | _ -> invalid_arg "invalid timing point fanout"
let parse_point line raw =
  if String.length raw<57 || raw.[54]<>' ' || raw.[56]<>' ' ||
    not (List.mem raw.[55] ['^';'v']) then invalid_arg "unsupported timing point alignment";
  let name,master = match words (String.sub raw 57 (String.length raw-57)) with
    | [name;kind] when String.length kind>2 && kind.[0]='(' && kind.[String.length kind-1]=')' ->
      let kind=String.sub kind 1 (String.length kind-2) in
      name,(if List.mem kind ["in";"out";"inout"] then None else Some kind)
    | _ -> invalid_arg "unsupported timing point identity/master" in
  let instance,pin = match String.rindex_opt name '/' with
    | Some i when i>0 && i+1<String.length name ->
      Some (String.sub name 0 i),Some (String.sub name (i+1) (String.length name-i-1))
    | _ -> None,None in
  {line;name;instance;pin;master;role=Data;
   edge=(if raw.[55]='^' then "rise" else "fall");
   fanout=optional fanout (slice raw 0 6);
   capacitance=optional (positive "reported load") (slice raw 6 18);
   slew=positive "slew" (slice raw 18 30);
   delay=finite "incremental delay" (slice raw 30 42);
   arrival=finite "point arrival" (slice raw 42 54)}

type parsed = {
  paths : path list; diagnostics : string list; consumed_points : int;
  point_limit_reached : bool; no_paths : (string * string) option;
}

type phase = Table | Capture | Required | Summary_required | Summary_arrival | Summary_end | Slack | Done
let near a b = abs_float (a-.b)<=0.000002
let separator line c = String.length line>=3 && String.for_all ((=) c) line
let corner_line line =
  let re=Str.regexp "^=+[ \t]+\\([^ \t]+\\)[ \t]+Corner[ \t]+=+[ \t\r]*$" in
  if Str.string_match re line 0 then Some (Str.matched_group 1 line) else None
let empty_native raw =
  let command=ref None and corner=ref None and found=ref false and valid=ref true in
  String.split_on_char '\n' raw |> List.iter (fun raw -> let line=String.trim raw in
    if line="" || separator line '=' then ()
    else match corner_line line with
    | Some c when !command<>None && !corner=None && not !found -> corner:=Some c
    | _ -> match line with
      | "report_checks -path_delay min (Hold)" when !command=None && !corner=None -> command:=Some "min"
      | "report_checks -path_delay max (Setup)" when !command=None && !corner=None -> command:=Some "max"
      | "No paths found." when !command<>None && !corner<>None && not !found -> found:=true
      | _ -> valid:=false);
  match !valid,!found,!corner,!command with true,true,Some c,Some m -> Some (c,m) | _ -> None

let parse_with_usage ?(max_paths=4096) ?(max_points=65536) raw =
  let empty diagnostics no_paths = {paths=[];diagnostics;consumed_points=0;point_limit_reached=false;no_paths} in
  if String.length raw>32*1024*1024 then empty ["timing source byte bound exceeded"] None
  else if String.length raw>=2 && raw.[0]='\031' && raw.[1]='\139' then
    empty ["compressed timing report is unsupported (gzip)"] None
  else if String.exists (fun c -> Char.code c<32 && not (List.mem c ['\n';'\r';'\t'])) raw then
    empty ["binary/unrecognized timing report"] None
  else
  let summaries,diagnostics=Inspection_service.timing_records ~max_records:max_paths raw in
  if summaries=[] then (
    if diagnostics<>[] then empty diagnostics None else
    match empty_native raw with
    | Some _ as native -> empty [] native
    | None -> empty [if String.trim raw="" then "empty timing report" else "unrecognized timing report; no supported native path records"] None)
  else
  let lines=Array.of_list (String.split_on_char '\n' raw) in
  let diagnostics=ref diagnostics and point_count=ref 0 and stopped=ref false in
  let limit=max 0 (min 65536 max_points) in
  let diagnostic s = if List.length !diagnostics<256 then diagnostics:= !diagnostics@[s] in
  let paths=List.filter_map (fun (first_line,last_line,fields) ->
    if !stopped then None else try
      let header=ref false and points=ref [] and phase=ref Table in
      let launched=ref false and capture_clock=ref false and primary_arrival=ref None and primary_required=ref None in
      let quantity line label =
        if slice line 0 42<>"" || String.trim (String.sub line 54 (String.length line-54))<>label then
          invalid_arg ("unsupported "^label^" summary columns");
        finite label (slice line 42 54) in
      for i=first_line-1 to last_line-1 do
        let line=lines.(i) in
        let trimmed=String.trim line in
        if String.starts_with ~prefix:"Fanout" trimmed then (
          if !header || line<>"Fanout         Cap        Slew       Delay        Time   Description" then
            invalid_arg "unsupported/duplicate timing table header";
          header:=true);
        if !header && separator trimmed '-' then (
          match !phase with
          | Table when !points=[] -> ()
          | Required -> phase:=Summary_required
          | Summary_end -> phase:=Slack
          | _ -> invalid_arg "out-of-order timing section boundary");
        let description=if String.length line>=57 then String.sub line 57 (String.length line-57) |> String.trim else "" in
        let clock_header=String.starts_with ~prefix:"clock " description &&
          (String.ends_with ~suffix:"(rise edge)" description || String.ends_with ~suffix:"(fall edge)" description) in
        if clock_header then (
          match !phase with
          | Table when not !launched -> ()
          | Capture -> capture_clock:=true
          | _ -> invalid_arg "capture clock block before primary data arrival or after required time");
        if String.ends_with ~suffix:"data arrival time" trimmed then (
          let value=quantity line "data arrival time" in
          match !phase with
          | Table when !launched ->
            (match !points with (p,_)::_ when p.line=i && near p.arrival value -> ()
             | _ -> invalid_arg "primary arrival must follow and match the actual data endpoint");
            primary_arrival:=Some value;phase:=Capture
          | Summary_arrival ->
            (match !primary_arrival with Some expected when near value (-.expected) -> ()
             | _ -> invalid_arg "subtraction summary/primary arrival mismatch");
            phase:=Summary_end
          | _ -> invalid_arg "missing/out-of-order primary data arrival; subtraction row cannot be primary");
        if String.ends_with ~suffix:"data required time" trimmed then (
          let value=quantity line "data required time" in
          match !phase with
          | Capture when !capture_clock -> primary_required:=Some value;phase:=Required
          | Summary_required ->
            (match !primary_required with Some expected when near value expected -> ()
             | _ -> invalid_arg "summary/primary required time mismatch");
            phase:=Summary_arrival
          | _ -> invalid_arg "missing/out-of-order primary required time");
        if Str.string_match (Str.regexp ".*slack (.*") trimmed 0 then (
          if !phase<>Slack then invalid_arg "incomplete/out-of-order timing summary before slack";
          phase:=Done);
        let has_edge=try ignore (Str.search_forward (Str.regexp "[ \t][\\^v][ \t]") line 0);true with Not_found -> false in
        if has_edge then (
          if not !header then invalid_arg "timing point before supported table header";
          if not (List.mem !phase [Table;Capture]) then invalid_arg "pin point outside data/capture sections";
          if String.length line>=57 && String.sub line 57 (String.length line-57)="input external delay" then (
            (* Native STA annotates this arithmetic row with an edge, but it is
               not a design pin and has no Fanout/Cap/Slew measurements. *)
            if slice line 0 30<>"" then invalid_arg "malformed input external delay columns";
            ignore (finite "input external delay" (slice line 30 42));
            ignore (finite "input external arrival" (slice line 42 54)))
          else (
            if !point_count>=limit then (
              stopped:=true;invalid_arg "timing point bound exceeded");
            incr point_count;
            let p=parse_point (i+1) line in
            if !phase=Table && matches (List.assoc "startpoint" fields) p && p.fanout<>None then launched:=true;
            points:=(p,!phase=Capture)::!points))
      done;
      if not !header then invalid_arg "missing supported timing table header";
      if !phase<>Done then invalid_arg "incomplete ordered data/capture/summary sections";
      (match !primary_arrival,!primary_required with
       | Some a,Some r when near a (float_of_string (List.assoc "arrival" fields)) && near r (float_of_string (List.assoc "required" fields)) -> ()
       | _ -> invalid_arg "legacy summary/primary measurement mismatch");
      let points=List.rev !points in
      let start=List.find_opt (fun (p,after) -> not after &&
        matches (List.assoc "startpoint" fields) p && p.fanout<>None) points in
      let start=match start with Some (p,_) -> p | None -> invalid_arg "missing exact data launch point" in
      let points=List.map (fun (p,after) -> {p with role=
        (if after then Capture_clock else if p.line<start.line then Launch_clock else Data)}) points in
      let data=List.filter (fun p -> p.role=Data) points in
      let data_start=List.hd data and data_end=List.hd (List.rev data) in
      if not (matches (List.assoc "endpoint" fields) data_end) then invalid_arg "data endpoint/header mismatch";
      if List.exists (fun (p:point) -> p.role<>Data &&
        (p.name=data_start.name || p.name=data_end.name)) points then
        invalid_arg "clock pin cannot be a data endpoint";
      let slack=float_of_string (List.assoc "slack" fields) in
      if (slack<0.)<>(List.assoc "status" fields="violated") then invalid_arg "timing slack/status conflict";
      Some {first_line;last_line;fields;points;data_start;data_end}
    with Invalid_argument e -> diagnostic (Printf.sprintf "timing path lines %d-%d: %s" first_line last_line e);None) summaries in
  {paths;diagnostics= !diagnostics;consumed_points= !point_count;
   point_limit_reached= !stopped || !point_count>=limit;no_paths=None}

let parse ?max_paths ?max_points raw =
  let result=parse_with_usage ?max_paths ?max_points raw in result.paths,result.diagnostics
