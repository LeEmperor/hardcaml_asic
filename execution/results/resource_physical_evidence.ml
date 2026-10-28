module E = Evidence_json
let get j k = match j with `Assoc xs -> Option.value (List.assoc_opt k xs) ~default:`Null | _ -> `Null
let fields = function `Assoc xs -> xs | _ -> invalid_arg "physical: expected object"
let list = function `List xs -> xs | _ -> invalid_arg "physical: expected array"
let text = function `String s when s<>"" -> s | _ -> invalid_arg "physical: expected string"
let s x = `String x
let obj x = `Assoc x
let arr x = `List x
let f x = `Float x
let fail x = invalid_arg ("physical: "^x)
let require b x = if not b then fail x
let unique xs = require (List.length xs=List.length (List.sort_uniq compare xs)) "duplicate identities/fields"
let exact j keys = let ks=List.map fst (fields j) in unique ks;require (List.sort compare ks=List.sort compare keys) "unexpected/missing fields"
let num = function
  | `Int n -> float_of_int n
  | `Intlit n -> let v=float_of_string n in require (Float.is_finite v) "nonfinite number";v
  | `Float n when Float.is_finite n -> n
  | _ -> fail "invalid/nonfinite number"
let positive j = let n=num j in require (n>0.) "nonpositive number";n
let nonnegative j = let n=num j in require (n>=0.) "negative number";n
let integer = function `Int n -> n | `Intlit n -> int_of_string n | _ -> fail "integer required"
let equal a b = abs_float (a-.b) <= 1e-9 *. max 1. (max (abs_float a) (abs_float b))
let rounding_tolerance value =
  if value=0. then 1e-9 else max 1e-9 (0.500001 *. (10. ** (floor(log10(abs_float value))-.5.)))
let rounded_equal expected reported = abs_float(expected-.reported)<=rounding_tolerance expected
let unavailable why = obj ["status",s "unavailable";"reason",s why]
let json raw = match E.parse ~reject_duplicates:true raw with Ok d -> E.value d | Error e -> fail e
type reader = { read:string -> string -> string * E.t; exists:string -> bool }
let read_json r p = let raw,ref_=r.read p "json" in json raw,ref_
let first r xs = List.find_opt r.exists xs
let refs j = list (get j "evidence_refs")
let refcheck available rs = List.iter (fun r -> require (List.mem r available) "unclosed evidence reference") rs
let checked_unavailable j = exact j ["status";"reason"];require (get j "status"=s "unavailable") "invalid unavailable status";ignore (text (get j "reason"))
let measurement refs definition unit_ value reason = obj ["value",value;"unit",s unit_;"definition",s definition;
  "stage",s "final_physical";"scope",s definition;"evidence_refs",arr refs;"unavailable_reason",(if value=`Null then s reason else `Null)]
let measure refs definition value = measurement refs definition "um^2" (f value) ""
let check_measure available m =
  exact m ["value";"unit";"definition";"stage";"scope";"evidence_refs";"unavailable_reason"];
  require (get m "stage"=s "final_physical") "measurement stage";
  List.iter (fun k -> ignore(text(get m k))) ["unit";"definition";"scope"];
  refcheck available (refs m);
  if get m "value"=`Null then ignore(text(get m "unavailable_reason")) else (
    ignore(nonnegative(get m "value"));require (get m "unavailable_reason"=`Null && refs m<>[]) "available measurement provenance")

(* Deliberately restricted DEF grammar: complete component section, unique names,
   supported placement/source clauses. Unsupported clauses cannot hide instances. *)
let tokens raw =
  let b=Buffer.create (String.length raw) in
  String.iter (fun c -> if String.contains "();" c then (Buffer.add_char b ' ';Buffer.add_char b c;Buffer.add_char b ' ') else Buffer.add_char b c) raw;
  Str.split (Str.regexp "[ \t\r\n]+") (Buffer.contents b)
let matches re raw =
  let re=Str.regexp re in
  let rec loop pos acc = try let _=Str.search_forward re raw pos in
    let value=Str.matched_group 1 raw and stop=Str.match_end () in loop stop (value::acc) with Not_found -> List.rev acc in loop 0 []
let clean raw =
  (* LEF/DEF comments and strings cannot contribute geometry declarations. The
     supported grammar rejects multiline strings rather than interpreting them. *)
  let out=Buffer.create(String.length raw) in
  let rec scan i quoted comment = if i=String.length raw then require (not quoted) "unterminated physical string" else
    let c=raw.[i] in
    if comment then (if c='\n' then (Buffer.add_char out c;scan (i+1) false false) else scan (i+1) false true)
    else if quoted then (
      if c='\n' || c='\r' then fail "unsupported multiline physical string"
      else if c='\\' then (require(i+1<String.length raw) "unterminated physical string escape";scan (i+2) true false)
      else scan (i+1) (c<>'"') false)
    else if c='#' then scan (i+1) false true
    else if c='"' then (Buffer.add_string out "__quoted__";scan (i+1) true false)
    else (Buffer.add_char out c;scan (i+1) false false) in
  scan 0 false false;Buffer.contents out
type component = { name:string; master:string; x:int; y:int; orientation:string }
type def = { units:int; die:int list; components:component list }
let parse_def raw =
  let raw=clean raw in
  let one re = match matches re raw with [x] -> x | _ -> fail "missing/duplicate DEF declaration" in
  let units=int_of_string (one "UNITS[ \t\r\n]+DISTANCE[ \t\r\n]+MICRONS[ \t\r\n]+\\([0-9]+\\)[ \t\r\n]*;") in
  require (units>0 && units<=1000000) "DEF units bound";
  let die=match tokens (one "DIEAREA[ \t\r\n]+\\([^;]+\\);") with
    | ["(";a;b;")";"(";c;d;")"] -> List.map int_of_string [a;b;c;d] | _ -> fail "nonrectangular DEF die" in
  let start=Str.regexp "\n[ \t]*COMPONENTS[ \t]+\\([0-9]+\\)[ \t]*;" in
  let _=try Str.search_forward start ("\n"^raw) 0 with Not_found -> fail "missing DEF components" in
  let count=int_of_string(Str.matched_group 1 ("\n"^raw)) and pos=Str.match_end ()-1 in
  require (count<=1000000) "DEF component bound";
  let tail=String.sub raw pos (String.length raw-pos) in
  let end_=try Str.search_forward (Str.regexp "END[ \t\r\n]+COMPONENTS\\([ \t\r\n]\\|$\\)") tail 0 with Not_found -> fail "truncated DEF components" in
  require (List.length (matches "\\(COMPONENTS[ \t]+[0-9]+[ \t]*;\\)" raw)=1) "duplicate DEF components section";
  let body=String.sub tail 0 end_ in
  let statements=String.split_on_char ';' body in
  require (String.trim (List.hd (List.rev statements))="") "unterminated DEF component statement";
  let components=List.filter_map (fun statement -> match tokens statement with
    | [] -> None
    | "-"::name::master::rest ->
      let rec clauses source placement = function
        | [] -> (match placement with Some (x,y,orientation) -> {name;master;x;y;orientation} | None -> fail "unplaced DEF component")
        | "+"::"SOURCE"::_value::xs when not source -> clauses true placement xs
        | "+"::("PLACED"|"FIXED"|"COVER")::"("::x::y::")"::orientation::xs when placement=None ->
          require (List.mem orientation ["N";"S";"E";"W";"FN";"FS";"FE";"FW"]) "DEF orientation";
          clauses source (Some(int_of_string x,int_of_string y,orientation)) xs
        | _ -> fail "unsupported/malformed DEF component clauses" in
      Some (clauses false None rest)
    | _ -> fail "malformed DEF component statement") statements in
  require (List.length components=count) "DEF component count mismatch";
  unique (List.map (fun c -> c.name) components);
  {units;die;components}

let rect_values j = let xs=list j in require (List.length xs=4) "rectangle arity";
  let xs=List.map num xs in match xs with [a;b;c;d] -> require (a<c && b<d) "degenerate rectangle";xs | _ -> assert false
let rect_area = function [a;b;c;d] -> (c-.a)*.(d-.b) | _ -> fail "rectangle arity"
let rect_json xs = arr (List.map f xs)
let rect_dbu j = ignore(rect_values j);List.map integer (list j)
let convert units xs = List.map (fun n -> float_of_int n /. float_of_int units) xs
let geometry_scope="observed macro footprint; excludes halo, bridges, routing and surrounding cells; retained checker assertion, not fresh GDS analysis"
let validate_geometry ~refs:available j =
  if get j "status"=s "unavailable" then checked_unavailable j else (
    exact j ["status";"instances";"area_um2";"scope";"evidence_refs"];
    require (get j "status"=s "available" && get j "scope"=s geometry_scope && refs j<>[]) "geometry status/scope/provenance";
    refcheck available (refs j);
    let xs=list(get j "instances") in require (xs<>[]) "empty geometry";
    unique (List.map (fun i -> text(get i "instance")) xs);
    let sum=List.fold_left (fun total i ->
      exact i ["instance";"module";"orientation";"dbu_per_um";"origin_dbu";"bounds_dbu";"width_um";"height_um";"area_um2";"halo_dbu"];
      List.iter (fun k -> ignore(text(get i k))) ["instance";"module"];
      require (get i "orientation"=s "R0") "unsupported geometry orientation";
      let units=integer(get i "dbu_per_um") in require (units>0 && units<=1000000) "geometry DBU";
      let bounds=rect_dbu(get i "bounds_dbu") in
      require (get i "origin_dbu"=arr(List.map (fun n -> `Int n) (List.filteri (fun i _ -> i<2) bounds))) "geometry origin";
      require (integer(get i "halo_dbu")>=0) "geometry halo";
      let dims=convert units bounds in
      let w,h=match dims with [a;b;c;d] -> c-.a,d-.b | _ -> assert false in
      require (equal (positive(get i "width_um")) w && equal (positive(get i "height_um")) h && equal (positive(get i "area_um2")) (w*.h)) "geometry dimensions/area";
      total+.w*.h) 0. xs in
    require (equal (positive(get j "area_um2")) sum) "geometry area sum")

(* Parse direct LEF macro attributes with checked nested scope/terminators.
   Every consumed master must have an explicit supported class, zero origin and
   dimensions exactly representable at the DEF DBU scale. *)
type master = { cls:string; width:int; height:int }
let parse_lef units raw =
  let lines=String.split_on_char '\n' (clean raw) in
  let table=Hashtbl.create 128 in
  let scaled token =
    require (String.length token<=64 && Str.string_match
      (Str.regexp "^[+-]?[0-9]+\\(\\.[0-9]+\\)?\\([eE][+-]?[0-9]+\\)?$") token 0) "invalid LEF decimal";
    let parts=Str.split (Str.regexp "[eE]") token in
    let mantissa,exponent=match parts with [v] -> v,0 | [v;e] -> v,int_of_string e | _ -> fail "invalid LEF decimal" in
    require (abs exponent<=12) "LEF decimal exponent bound";
    let digits,places=match String.split_on_char '.' mantissa with
      | [v] -> v,0 | [whole;frac] -> whole^frac,String.length frac | _ -> fail "invalid LEF decimal" in
    let power=exponent-places in
    let numerator=Z.mul (Z.of_string digits) (Z.of_int units) in
    let numerator,denominator=if power>=0 then Z.mul numerator (Z.pow (Z.of_int 10) power),Z.one
      else numerator,Z.pow (Z.of_int 10) (-power) in
    let value,remainder=Z.ediv_rem numerator denominator in
    require (Z.equal remainder Z.zero && Z.compare (Z.abs value) (Z.of_string "10000000000")<0) "LEF dimension not exactly representable in DEF DBU";
    Z.to_int value in
  let rec scan = function
    | [] -> ()
    | line::rest -> (match tokens line with
      | ["MACRO";name] ->
        require (not(Hashtbl.mem table name)) "duplicate LEF macro";
        let rec body stack cls origin size = function
          | [] -> fail "truncated LEF macro"
          | line::rest -> match tokens line with
            | ["END";n] when n=name && stack=[] ->
              let cls=match cls with Some c -> c | None -> fail "missing LEF class" in
              require (origin=Some (0,0)) "missing/nonzero LEF origin";
              let width,height=match size with Some x -> x | None -> fail "missing LEF size" in
              require (width>0 && height>0) "nonpositive LEF dimensions";
              Hashtbl.add table name {cls;width;height};scan rest
            | ["END"] -> (match stack with
              | None::stack -> body stack cls origin size rest
              | _ -> fail "unmatched LEF unnamed END")
            | ["END";n] -> (match stack with
              | Some expected::stack when n=expected -> body stack cls origin size rest
              | _ -> fail "mismatched/unclosed LEF scope")
            | "END"::_ -> fail "malformed LEF terminator"
            | ["PIN";pin] when stack=[] -> body [Some pin] cls origin size rest
            | ["PORT"] when (match stack with [Some _] -> true | _ -> false) -> body (None::stack) cls origin size rest
            | ["OBS"] | ["DENSITY"] when stack=[] -> body [None] cls origin size rest
            | ("PIN"|"PORT"|"OBS"|"DENSITY"|"TIMING")::_ -> fail "unsupported/malformed nested LEF scope"
            | "CLASS"::xs when stack=[] ->
              require (cls=None) "duplicate LEF class";
              let c=match xs with ["CORE";";"] -> "nonspacer" | ["CORE";"SPACER";";"] -> "spacer" | ["BLOCK";";"] -> "macro" | _ -> "unsupported" in
              body stack (Some c) origin size rest
            | ["ORIGIN";x;y;";"] when stack=[] -> require (origin=None) "duplicate LEF origin";body stack cls (Some(scaled x,scaled y)) size rest
            | ["SIZE";x;"BY";y;";"] when stack=[] -> require (size=None) "duplicate LEF size";body stack cls origin (Some(scaled x,scaled y)) rest
            | ("CLASS"|"ORIGIN"|"SIZE")::_ when stack=[] -> fail "malformed direct LEF attribute"
            | "MACRO"::_ -> fail "nested/truncated LEF macro"
            | _ -> body stack cls origin size rest in
        body [] None None None rest
      | _ -> scan rest) in
  scan lines;table

let collect ~reader:r ~flow ~snapshot ~manifest ~resources ~instances ~checks ~checker_ref ~final_netlist =
  let missing reason = unavailable reason,List.map (fun row -> text(get row "resource_id"),unavailable reason) resources in
  match checks,instances with
  | None,_ | _,None -> missing "verified physical checker/final instance evidence unavailable"
  | Some checks,Some instances ->
    require (get checks "status"=s "pass" && get checks "checking_profile"=s "cmos5l_real_gds_v1") "unverified physical checker";
    let artifacts=fields(get checks "artifacts") in
    let choose suffix = match List.filter (fun (p,_) -> String.ends_with ~suffix p) artifacts with
      | [] -> None | [p,digest] -> let raw,ref_=r.read (flow^"/"^p) (if suffix=".def" then "def" else "json") in
        require (get ref_ "sha256"=digest) "checker source digest mismatch";Some(raw,ref_)
      | _ -> fail ("ambiguous checker artifact "^suffix) in
    match choose "/macro-power-geometry.json",choose ".def" with
    | None,_ | _,None -> missing "checker-bound geometry/DEF unavailable"
    | Some(graw,gref),Some(draw,dref) ->
    let base_refs=[gref;dref;checker_ref;final_netlist] in
    require (get gref "sha256"=get checks "power_geometry_sha256" && get checks "final_power_geometry"=s "retained_in_real_gds") "geometry checker binding";
    let geometry=json graw and def=parse_def draw in
    require (integer(get geometry "schema_version")=1 && get geometry "strategy"=s "cmos5l_m4_edge_access_v1") "geometry schema/strategy";
    let units=integer(get geometry "dbu_per_um") in require (units=def.units) "geometry/DEF unit mismatch";
    let grid=integer(get geometry "manufacturing_grid_dbu") in require (grid>0) "geometry grid";
    let declared=List.concat_map (fun row -> List.map (fun i -> text(get row "resource_id"),text(get i "instance"),text(get i "module")) (list(get row "instances"))) resources in
    let macros=list(get geometry "macros") in
    let actual=List.map (fun m -> text(get m "resource"),text(get m "instance"),text(get m "module")) macros in
    unique actual;require (List.sort compare actual=List.sort compare declared) "geometry resource identity/type/count mismatch";
    let observed=List.map (fun c -> c.name,c.master) def.components in
    require (List.sort compare observed=List.sort compare instances) "DEF/final netlist instance inventory mismatch";
    let geos=List.map (fun row ->
      let id=text(get row "resource_id") in
      let ms=List.filter (fun m -> get m "resource"=s id) macros in
      let geo=if ms=[] then unavailable "no exact macro resource ownership" else (
        require (get row "status"=s "matched") "geometry resource not reconciled";
        let items=List.map (fun m ->
          let name=text(get m "instance") and typ=text(get m "module") in
          let c=List.find (fun c -> c.name=name) def.components in
          require (c.master=typ && c.orientation="N" && get m "orientation"=s "R0") "macro master/orientation mismatch";
          let bounds=rect_dbu(get m "footprint_dbu") in
          require (List.for_all (fun n -> n mod grid=0) bounds) "off-grid macro footprint";
          let x,y,w,h=match bounds with [x;y;right;top] -> x,y,float_of_int(right-x)/.float_of_int units,float_of_int(top-y)/.float_of_int units | _ -> assert false in
          require (typ="RM_IHPSG13_1P_256x16_c2_bm_bist" && equal w 236.8 && equal h 118.78)
            "footprint differs from supported retained cmos5l checker master dimensions";
          require (x=c.x && y=c.y) "DEF/geometry macro placement mismatch";
          let db=def.die in
          (match bounds,db with [a;b;c;d],[e;g;h;i] -> require (a>=e && b>=g && c<=h && d<=i) "macro outside die" | _ -> assert false);
          let area=match bounds with [a;b;c;d] -> Z.to_float(Z.mul (Z.of_int(c-a)) (Z.of_int(d-b)))/.(float_of_int units ** 2.) | _ -> assert false in
          obj ["instance",s name;"module",s typ;"orientation",s "R0";"dbu_per_um",`Int units;
            "origin_dbu",arr[`Int x;`Int y];"bounds_dbu",get m "footprint_dbu";"width_um",f w;"height_um",f h;"area_um2",f area;"halo_dbu",get m "halo_dbu"]) ms in
        obj ["status",s "available";"instances",arr items;"area_um2",f(List.fold_left(fun a i -> a+.num(get i "area_um2")) 0. items);
          "scope",s geometry_scope;"evidence_refs",arr base_refs]) in
      validate_geometry ~refs:base_refs geo;id,geo) resources in
    let used_refs=ref base_refs in
    let metrics=match first r ([flow^"/final/metrics.json"]@(if snapshot then ["metrics.json"] else [])) with
      | None -> None | Some p -> let j,ref_=read_json r p in used_refs:= !used_refs@[ref_];Some(j,ref_) in
    let measurements=ref [] in
    let add k m=measurements:= !measurements@[k,m] in
    let floor_rect key fallback = match metrics with
      | Some(j,ref_) when get j key<>`Null ->
        let xs=Str.split (Str.regexp "[ \t]+") (text(get j key)) |> List.map float_of_string in
        ignore(rect_values(rect_json xs));
        (match fallback with Some expected -> require (List.for_all2 equal xs expected) "DEF/native die bbox mismatch" | None -> ());
        obj ["bounds_um",rect_json xs;"area",measure [ref_] "gross native rectangle; not usable sites; includes halos/blockages" (rect_area xs)]
      | _ -> (match fallback with None -> unavailable "native core bbox unavailable" | Some xs ->
        obj ["bounds_um",rect_json xs;"area",measure [dref] "DEF die rectangle" (rect_area xs)]) in
    let die=floor_rect "design__die__bbox" (Some(convert units def.die)) in
    let core=floor_rect "design__core__bbox" None in
    if get core "status"<>s "unavailable" then (
      match rect_values(get core "bounds_um"),rect_values(get die "bounds_um") with
      | [a;b;c;d],[e;g;h;i] ->
        require (a>=e && b>=g && c<=h && d<=i) "native core outside die";
        List.iter(fun (_,geometry) -> if get geometry "status"=s "available" then
          List.iter(fun item -> match convert units (rect_dbu(get item "bounds_dbu")) with
            | [x;y;right;top] -> require (x>=a && y>=b && right<=c && top<=d) "observed macro outside native core"
            | _ -> assert false) (list(get geometry "instances"))) geos
      | _ -> assert false);
    let ma=List.fold_left(fun a (_,g) -> if get g "status"=s "available" then a+.num(get g "area_um2") else a) 0. geos in
    let rounded expected reported = require (rounded_equal expected (nonnegative reported)) "rounded native/derived area contradiction" in
    (match metrics with None -> () | Some(j,_) ->
      List.iter(fun (key,expected) -> let v=get j key in if v<>`Null then rounded expected v)
        ["design__instance__area__macros",ma;
         "design__die__area",num(get (get die "area") "value")];
      if get core "status"<>s "unavailable" then (
        let v=get j "design__core__area" in if v<>`Null then rounded (num(get (get core "area") "value")) v);
      let v=get j "design__instance__count" in if v<>`Null then require(integer v=List.length def.components) "native/DEF total count contradiction";
      let v=get j "design__instance__count__macros" in if v<>`Null then require(integer v=List.length declared) "native macro count contradiction");
    add "macro_footprint_area" (measure base_refs "sum of exact reconciled macro rectangles; excludes halos and integration cells" ma);
    (match metrics with None -> () | Some(j,ref_) ->
      List.iter(fun (key,native,unit_) -> let v=get j native in
        if v<>`Null then ignore(nonnegative v);
        add key (measurement [ref_] ("native rounded producer metric "^native^"; not reconstructed exact area") unit_ v "native metric absent"))
        ["native_all_component_area","design__instance__area","um^2";
         "native_nonspacer_area","design__instance__area__stdcell","um^2";
         "native_spacer_area","design__instance__area__class:fill_cell","um^2";
         "native_macro_area","design__instance__area__macros","um^2"]);
    (* Exact LEFs are optional and must be matched to retained preflight bytes. *)
    let preflight=first r ["preflight.json";"run-preflight.json";"public-preflight.json"] in
    let masters=Hashtbl.create 128 and lrefs=ref [] in
    let macro_lefs=List.concat_map(fun row ->
      let implementation=get row "selected_implementation" in
      if get implementation "kind"<>s "macro" then [] else
      let bindings=get (get (get (get manifest "flow_configuration") "MACROS") (text(get implementation "name"))) "lef" in
      if bindings=`Null then [] else List.map text (list bindings)) resources in
    (match preflight with None -> () | Some p ->
      let pre,pref=read_json r p in
      List.iter (fun binding ->
        let path=match get binding "path" with `String p -> p | _ -> "" in
        let reference=match get binding "reference" with `String p -> p | _ -> path in
        let role=get binding "role" in
        let selected=(role=s "(Technology_view Standard_cell_lef)") ||
          (role=s "macro:Physical_abstract" && List.mem reference macro_lefs) in
        if selected && String.ends_with ~suffix:".lef" reference then (
          let base=Filename.basename reference in
          let candidates=["baseline-inputs/"^base;"models/"^base;"bundle/"^base] @
            List.init 16 (fun i -> "baseline-inputs/"^string_of_int i^"-"^base) in
          match first r candidates with None -> () | Some lp ->
            let raw,ref_=r.read lp "lef" in
            require (get ref_ "sha256"=get binding "sha256") "retained LEF/preflight hash mismatch";
            if not(List.mem ref_ !lrefs) then (
              lrefs:= !lrefs@[ref_];
              let table=parse_lef units raw in
              Hashtbl.iter(fun name m -> require (not(Hashtbl.mem masters name)) "duplicate bound LEF master";Hashtbl.add masters name m) table))) (list(get pre "references"));
      if !lrefs<>[] then lrefs:=pref::!lrefs);
    used_refs:= !used_refs @ !lrefs;
    let exact_available=List.for_all(fun c -> Hashtbl.mem masters c.master) def.components in
    let sums=Hashtbl.create 3 and counts=Hashtbl.create 3 in
    List.iter(fun k -> Hashtbl.add sums k Z.zero;Hashtbl.add counts k 0) ["macro";"nonspacer";"spacer"];
    List.iter(fun c -> match Hashtbl.find_opt masters c.master with None -> () | Some m ->
      require (List.mem m.cls ["macro";"nonspacer";"spacer"]) "unsupported LEF class";
      let declared_macro=List.exists(fun (_,name,_) -> name=c.name) declared in
      require (declared_macro=(m.cls="macro")) "LEF class/resource macro conflict";
      if declared_macro then (
        let g=List.find(fun g -> get g "instance"=s c.name) (List.concat_map(fun (_,g) -> if get g "status"=s "available" then list(get g "instances") else []) geos) in
        let b=rect_dbu(get g "bounds_dbu") in
        match b with [a;b;c;d] -> require (c-a=m.width && d-b=m.height) "LEF/geometry dimensions mismatch" | _ -> assert false);
      Hashtbl.replace counts m.cls (1+Hashtbl.find counts m.cls);
      Hashtbl.replace sums m.cls (Z.add (Hashtbl.find sums m.cls) (Z.mul (Z.of_int m.width) (Z.of_int m.height)))) def.components;
    let area cls = Z.to_float(Hashtbl.find sums cls)/.(float_of_int units ** 2.) in
    (* Completeness of standard-cell classes does not depend on retaining the
       macro LEF: exact macro identities/area are independently known from DEF and
       checker-bound geometry. Even incomplete classes establish lower bounds. *)
    let standard_complete=List.for_all(fun c ->
      List.exists(fun (_,name,_) -> name=c.name) declared || Hashtbl.mem masters c.master) def.components in
    (match metrics with None -> () | Some(j,_) ->
      let native key=match get j key with `Null -> None | v -> Some(nonnegative v) in
      let lower key known=match native key with None -> () | Some reported ->
        require (reported+.rounding_tolerance reported>=known) ("native area below proven lower bound: "^key) in
      List.iter(fun (cls,key,count_key) ->
        let known=area cls in
        lower key known;
        let n=get j count_key in
        if n<>`Null then (
          let n=integer n in
          require (n>=Hashtbl.find counts cls) "native category count below known DEF/LEF count";
          if standard_complete then require(n=Hashtbl.find counts cls) "native/DEF LEF category count contradiction");
        let category_complete=standard_complete || (n<>`Null && integer n=Hashtbl.find counts cls) in
        if category_complete then (match native key with None -> () | Some reported ->
          require(rounded_equal known reported) "rounded native/complete LEF category area contradiction"))
        ["nonspacer","design__instance__area__stdcell","design__instance__count__stdcell";
         "spacer","design__instance__area__class:fill_cell","design__instance__count__class:fill_cell"];
      lower "design__instance__area" (ma+.area "nonspacer"+.area "spacer");
      let area_keys=["design__instance__area__macros";"design__instance__area__stdcell";"design__instance__area__class:fill_cell"] in
      let other_area_keys=["design__instance__area__padcells";"design__instance__area__cover"] in
      let values=List.filter_map native (area_keys@other_area_keys) in
      (match native "design__instance__area" with None -> () | Some total ->
        let proven=List.fold_left(fun sum (key,known) -> sum +.
          (match native key with None -> known | Some value -> max known (value-.rounding_tolerance value))) 0.
          ["design__instance__area__macros",ma;"design__instance__area__stdcell",area "nonspacer";
           "design__instance__area__class:fill_cell",area "spacer"] in
        let proven=List.fold_left(fun sum key -> match native key with None -> sum | Some value -> sum+.max 0. (value-.rounding_tolerance value)) proven other_area_keys in
        require(total+.rounding_tolerance total>=proven) "native total below combined known/native category lower bounds";
        let sum=List.fold_left (+.) 0. values and tolerance=List.fold_left(fun n v -> n+.rounding_tolerance v) (rounding_tolerance total) values in
        require(total+.tolerance>=sum) "native total area below native category sum";
        if List.for_all(fun key -> native key<>None) area_keys then
          require(abs_float(total-.sum)<=tolerance) "native total/category area contradiction");
      let count_keys=["design__instance__count__macros";"design__instance__count__stdcell";"design__instance__count__class:fill_cell"] in
      let native_counts=List.filter_map(fun key -> match get j key with `Null -> None | v -> let n=integer v in require(n>=0 && n<=List.length def.components) "native category count outside complete DEF bounds";Some n)
        (count_keys@["design__instance__count__padcells";"design__instance__count__cover"]) in
      let sum=List.fold_left (+) 0 native_counts in
      require (sum<=List.length def.components) "native category counts exceed complete DEF count";
      let lower_count=List.fold_left(fun sum (key,known) -> sum+
        (match get j key with `Null -> known | value -> max known (integer value))) 0
        ["design__instance__count__macros",List.length declared;
         "design__instance__count__stdcell",Hashtbl.find counts "nonspacer";
         "design__instance__count__class:fill_cell",Hashtbl.find counts "spacer"] in
      let lower_count=List.fold_left(fun sum key -> match get j key with `Null -> sum | value -> sum+integer value) lower_count
        ["design__instance__count__padcells";"design__instance__count__cover"] in
      require (lower_count<=List.length def.components) "native counts plus known categories exceed complete DEF count";
      if List.for_all(fun key -> get j key<>`Null) count_keys then
        require(sum=List.length def.components) "native category/DEF total count contradiction");
    let exact_refs=base_refs @ !lrefs in
    List.iter(fun cls ->
      let reason="complete bound LEF CLASS/ORIGIN/SIZE coverage unavailable" in
      add (cls^"_component_area") (measurement exact_refs ("DEF count times bound LEF dimensions; "^cls^"; exact DBU squared sum, not routed coverage") "um^2" (if exact_available then f(area cls) else `Null) reason);
      add (cls^"_component_count") (measurement exact_refs ("complete DEF and bound LEF "^cls^" classification") "count" (if exact_available then `Int(Hashtbl.find counts cls) else `Null) reason)) ["macro";"nonspacer";"spacer"];
    if exact_available then (
      require (equal (area "macro") ma) "macro aggregate mismatch";
      List.iter(fun (cls,key) -> match metrics with None -> () | Some(j,_) ->
        let v=get j key in if v<>`Null then (
          let reported=nonnegative v in
          (* Native producer prints approximately six significant digits. *)
          require (rounded_equal (area cls) reported) "rounded native/LEF area contradiction"))
        ["macro","design__instance__area__macros";"nonspacer","design__instance__area__stdcell";"spacer","design__instance__area__class:fill_cell"];
      (match metrics with None -> () | Some(j,_) ->
        List.iter(fun (cls,key) -> let v=get j key in if v<>`Null then
          require (integer v=Hashtbl.find counts cls) "native/DEF LEF category count contradiction")
          ["macro","design__instance__count__macros";"nonspacer","design__instance__count__stdcell";"spacer","design__instance__count__class:fill_cell"];
        let v=get j "design__instance__count" in if v<>`Null then
          require (integer v=List.length def.components) "native/DEF total count contradiction";
        let v=get j "design__instance__area" in if v<>`Null then (
          let total=area "macro"+.area "nonspacer"+.area "spacer" in
          require (rounded_equal total (nonnegative v)) "rounded native/LEF total area contradiction"));
      let sum classes=Z.to_float(List.fold_left(fun a cls -> Z.add a (Hashtbl.find sums cls)) Z.zero classes)/.(float_of_int units ** 2.) in
      add "nonspacer_plus_macro_area" (measure exact_refs "nonspacer plus macro footprint sum; excludes all CORE SPACER fill/decap" (sum ["nonspacer";"macro"]));
      add "all_component_area" (measure exact_refs "all component footprints including CORE SPACER fill/decap and macros" (sum ["nonspacer";"spacer";"macro"])));
    let ratios=ref [] in
    let ratio name numerator denominator =
      let nv=positive(get numerator "value") and dv=positive(get denominator "value") in
      ratios:= !ratios@[obj["name",s name;"numerator",numerator;"denominator",denominator;
        "value",f(nv/.dv);"unit",s "ratio";"scope",s "sum of component rectangles / gross rectangle; not union, usable sites, routing or native-utilization formula"]] in
    List.iter(fun (label,rectangle) -> if get rectangle "status"<>s "unavailable" then (
      let den=get rectangle "area" in
      ratio ("macro_over_"^label) (List.assoc "macro_footprint_area" !measurements) den;
      if exact_available then List.iter(fun key -> ratio (key^"_over_"^label) (List.assoc key !measurements) den) ["nonspacer_plus_macro_area";"all_component_area"])) ["core",core;"die",die];
    let result=obj ["status",s "available";"reason",`Null;"floorplan",obj["core",core;"die",die];
      "measurements",obj !measurements;"ratios",arr !ratios;"evidence_refs",arr(List.sort_uniq compare !used_refs)] in
    result,geos

let validate ~refs:available j =
  if get j "status"=s "unavailable" then checked_unavailable j else if get j "status"=s "invalid" then (
    exact j ["status";"reason"];ignore(text(get j "reason"))) else (
    exact j ["status";"reason";"floorplan";"measurements";"ratios";"evidence_refs"];
    require (get j "status"=s "available" && get j "reason"=`Null && refs j<>[]) "physical status";
    refcheck available (refs j);
    let floorplan=get j "floorplan" in exact floorplan ["core";"die"];
    require (get (get floorplan "die") "status"<>s "unavailable") "available physical evidence requires DEF die";
    List.iter(fun k -> let rect=get floorplan k in if get rect "status"=s "unavailable" then checked_unavailable rect else (
      exact rect ["bounds_um";"area"];let xs=rect_values(get rect "bounds_um") in
      check_measure available (get rect "area");
      require (get (get rect "area") "unit"=s "um^2") "floorplan area unit";
      require (equal (positive(get (get rect "area") "value")) (rect_area xs)) "floorplan area")) ["core";"die"];
    let measurements=fields(get j "measurements") in unique(List.map fst measurements);
    List.iter(fun (_,m) -> check_measure available m) measurements;
    let required=["macro_footprint_area";"macro_component_area";"macro_component_count";"nonspacer_component_area";"nonspacer_component_count";"spacer_component_area";"spacer_component_count"] in
    let optional=["native_all_component_area";"native_nonspacer_area";"native_spacer_area";"native_macro_area";"nonspacer_plus_macro_area";"all_component_area"] in
    List.iter(fun k -> require(List.mem_assoc k measurements) "missing physical measurement") required;
    List.iter(fun (k,m) -> require(List.mem k (required@optional)) "unknown physical measurement";
      require(get m "unit"=s(if String.ends_with ~suffix:"_count" k then "count" else "um^2")) "physical measurement unit";
      if String.ends_with ~suffix:"_count" k && get m "value"<>`Null then let n=nonnegative(get m "value") in require (floor n=n) "fractional count") measurements;
    let value k=num(get (List.assoc k measurements) "value") in
    if get (List.assoc "macro_component_area" measurements) "value"<>`Null then (
      require(equal (value "macro_component_area") (value "macro_footprint_area")) "macro sums";
      require(equal (value "nonspacer_plus_macro_area") (value "nonspacer_component_area"+.value "macro_component_area")) "nonspacer sum";
      require(equal (value "all_component_area") (value "nonspacer_plus_macro_area"+.value "spacer_component_area")) "all sum");
    let exact_available=get (List.assoc "macro_component_area" measurements) "value"<>`Null in
    List.iter(fun k -> require ((get (List.assoc k measurements) "value"<>`Null)=exact_available) "partial exact component coverage")
      ["macro_component_count";"nonspacer_component_area";"nonspacer_component_count";"spacer_component_area";"spacer_component_count"];
    require (List.mem_assoc "nonspacer_plus_macro_area" measurements=exact_available && List.mem_assoc "all_component_area" measurements=exact_available) "exact aggregate coverage";
    let ratios=list(get j "ratios") in unique(List.map(fun r -> text(get r "name")) ratios);
    let expected_ratios=List.concat_map(fun label ->
      if get (get floorplan label) "status"=s "unavailable" then [] else
      ["macro_over_"^label] @ if List.mem_assoc "nonspacer_plus_macro_area" measurements then
        ["nonspacer_plus_macro_area_over_"^label;"all_component_area_over_"^label] else []) ["core";"die"] in
    require (List.sort compare expected_ratios=List.sort compare (List.map(fun r -> text(get r "name")) ratios)) "ratio coverage/names";
    List.iter(fun r ->
      exact r ["name";"numerator";"denominator";"value";"unit";"scope"];
      let name=text(get r "name") in
      require(get r "scope"=s "sum of component rectangles / gross rectangle; not union, usable sites, routing or native-utilization formula") "ratio scope";
      require(get r "unit"=s "ratio") "ratio unit";
      let n=get r "numerator" and d=get r "denominator" in
      check_measure available n;check_measure available d;
      require (List.exists(fun (_,m) -> m=n) measurements) "ratio numerator not a measurement";
      require(List.exists(fun k -> get (get floorplan k) "area"=d) ["core";"die"]) "ratio denominator not a gross rectangle";
      let suffix=if String.ends_with ~suffix:"_core" name then "core" else "die" in
      let key=if String.starts_with ~prefix:"macro_over_" name then "macro_footprint_area"
        else if String.starts_with ~prefix:"nonspacer_plus_macro_area_over_" name then "nonspacer_plus_macro_area" else "all_component_area" in
      require (n=List.assoc key measurements && d=get (get floorplan suffix) "area") "ratio operand/name mismatch";
      require(equal (nonnegative(get r "value")) (positive(get n "value")/.positive(get d "value"))) "ratio arithmetic") ratios)
