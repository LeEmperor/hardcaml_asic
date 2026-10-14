type metadata = { mode : int; uid : int64; gid : int64; uname : string; gname : string; mtime : string }
type member = { name : string; bytes : int64; sha256 : string; metadata : metadata }
type source = { path : string; name : string; sha256 : string option }
type limits = { max_members : int; max_member_bytes : int64; max_tar_bytes : int64; max_pax_bytes : int; max_name_bytes : int }
let fail s = failwith ("Evidence_tar: " ^ s)
let require b s = if not b then fail s
let normalized = { mode=0o644; uid=0L; gid=0L; uname=""; gname=""; mtime="0" }
let utf8 s =
  let byte i=Char.code s.[i] in
  let rec loop i = if i<String.length s then (
    let a=byte i in
    if a<128 then loop (i+1) else (
      let n,lo,hi = if a>=0xc2 && a<=0xdf then 2,0x80,0xbf
        else if a>=0xe0 && a<=0xef then 3,(if a=0xe0 then 0xa0 else 0x80),(if a=0xed then 0x9f else 0xbf)
        else if a>=0xf0 && a<=0xf4 then 4,(if a=0xf0 then 0x90 else 0x80),(if a=0xf4 then 0x8f else 0xbf)
        else (fail "invalid UTF-8") in
      require (i+n<=String.length s && byte (i+1)>=lo && byte (i+1)<=hi) "invalid UTF-8";
      for j=i+2 to i+n-1 do require (byte j>=0x80 && byte j<=0xbf) "invalid UTF-8" done;
      loop (i+n))) in loop 0
let validate_name s =
  utf8 s;
  require (s<>"" && not (String.contains s '\000') && not (String.contains s '\\')) "unsafe name";
  List.iter (fun p -> require (p<>"" && p<>"." && p<>"..") "unsafe name") (String.split_on_char '/' s)
let validate_inventory xs =
  let seen = Hashtbl.create 16 in
  List.iter (fun (n,h) -> validate_name n;
    require (not (Hashtbl.mem seen n)) "duplicate inventory name";
    require (String.length h=64 && String.for_all (function '0'..'9'|'a'..'f' -> true | _ -> false) h) "invalid SHA-256";
    Hashtbl.add seen n ()) xs;
  List.iter (fun (n,_) ->
    let rec parents p = let d=Filename.dirname p in
      if d<>"." then (require (not (Hashtbl.mem seen d)) "conflicting inventory names"; parents d) in
    parents n) xs
let zeros n = String.make n '\000'
let pad n = Int64.to_int (Int64.rem (Int64.sub 512L (Int64.rem n 512L)) 512L)
let hex h = Cryptokit.transform_string (Cryptokit.Hexa.encode ()) h
let copy ic oc size =
  let h=Cryptokit.Hash.sha256 () and b=Bytes.create 65536 in
  let rec loop left = if left>0L then (
    let n=Int64.to_int (Int64.min left 65536L) in
    really_input ic b 0 n; h#add_substring b 0 n;
    Option.iter (fun oc -> output oc b 0 n) oc; loop (Int64.sub left (Int64.of_int n))) in
  Fun.protect ~finally:(fun () -> h#wipe) (fun () -> loop size; hex h#result)
let octal b off len n =
  require (n>=0L) "negative header integer";
  let s=Printf.sprintf "%Lo" n in require (String.length s<len) "header integer overflow";
  Bytes.blit_string (String.make (len-1-String.length s) '0' ^ s ^ "\000") 0 b off len
let put b off len s = require (String.length s<=len && not (String.contains s '\000')) "header string overflow"; Bytes.blit_string s 0 b off (String.length s)
(* Magic contains its required NUL, unlike general strings. *)
let header name kind size m =
  let b=Bytes.make 512 '\000' in
  put b 0 100 name; octal b 100 8 (Int64.of_int m.mode); octal b 108 8 m.uid; octal b 116 8 m.gid;
  octal b 124 12 size; octal b 136 12 0L; Bytes.fill b 148 8 ' '; Bytes.set b 156 kind;
  Bytes.blit_string "ustar\00000" 0 b 257 8;
  put b 265 32 m.uname; put b 297 32 m.gname;
  let sum=ref 0 in Bytes.iter (fun c -> sum:= !sum+Char.code c) b;
  Bytes.blit_string (Printf.sprintf "%06o\000 " !sum) 0 b 148 8; Bytes.to_string b
let pax_record k v =
  let body=k^"="^v^"\n" in
  let rec length n = let next=String.length (string_of_int n)+1+String.length body in if next=n then n else length next in
  let n=length (String.length body+2) in string_of_int n ^ " " ^ body
let regular path =
  let rec check p = require ((Unix.lstat p).Unix.st_kind<>Unix.S_LNK) "symlink source";
    let d=Filename.dirname p in if d<>p then check d in
  check path; require ((Unix.stat path).Unix.st_kind=Unix.S_REG) "nonregular source"
let write ~normalized:normalize oc sources =
  validate_inventory (List.map (fun (s:source) -> s.name,Option.value s.sha256 ~default:(String.make 64 '0')) sources);
  let seen=Hashtbl.create 16 in
  let members=List.map (fun (s:source) ->
    validate_name s.name; require (not (Hashtbl.mem seen s.name)) "duplicate source"; Hashtbl.add seen s.name ();
    regular s.path;
    let ic=open_in_bin s.path in
    Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
      let st=Unix.LargeFile.fstat (Unix.descr_of_in_channel ic) in
      require (st.st_kind=Unix.S_REG) "nonregular descriptor";
      let m=if normalize then normalized else
        {mode=st.st_perm;uid=Int64.of_int st.st_uid;gid=Int64.of_int st.st_gid;
         uname=(try (Unix.getpwuid st.st_uid).pw_name with Not_found -> "");
         gname=(try (Unix.getgrgid st.st_gid).gr_name with Not_found -> "");mtime=Printf.sprintf "%.9f" st.st_mtime} in
      let pax=ref ["mtime",m.mtime] in
      let field k v len = if String.length v>len || not (String.for_all (fun c -> Char.code c<128) v)
        then (pax:= !pax @ [k,v]; "") else v in
      let name=field "path" s.name 100 and uname=field "uname" m.uname 32 and gname=field "gname" m.gname 32 in
      let size=if st.st_size>0o77777777777L then (pax:= !pax @ ["size",Int64.to_string st.st_size];0L) else st.st_size in
      let uid=if m.uid>0o7777777L then (pax:= !pax @ ["uid",Int64.to_string m.uid];0L) else m.uid in
      let gid=if m.gid>0o7777777L then (pax:= !pax @ ["gid",Int64.to_string m.gid];0L) else m.gid in
      let data=String.concat "" (List.map (fun (k,v) -> pax_record k v) !pax) in
      output_string oc (header "PaxHeader" 'x' (Int64.of_int (String.length data)) normalized);
      output_string oc data; output_string oc (zeros (pad (Int64.of_int (String.length data))));
      output_string oc (header (if name="" then "PaxFile" else name) '0' size {m with uid;gid;uname;gname});
      let sha256=copy ic (Some oc) st.st_size in
      require ((try ignore (input_char ic); false with End_of_file -> true)) "source grew";
      let after=Unix.LargeFile.fstat (Unix.descr_of_in_channel ic) in
      require ({after with st_atime=st.st_atime}=st) "source metadata changed";
      Option.iter (fun h -> require (h=sha256) ("source hash changed: "^s.name)) s.sha256;
      output_string oc (zeros (pad st.st_size)); {name=s.name;bytes=st.st_size;sha256;metadata=m})) sources in
  output_string oc (zeros 1024); flush oc; members
let text s off len =
  let part=String.sub s off len in
  match String.index_opt part '\000' with
  | None -> part
  | Some i -> require (String.for_all ((=) '\000') (String.sub part i (len-i))) "nonzero string padding"; String.sub part 0 i
let number s off len =
  let p=String.trim (String.map (fun c -> if c='\000' then ' ' else c) (String.sub s off len)) in
  require (p<>"" && String.for_all (function '0'..'7' -> true | _ -> false) p) "invalid octal";
  try let n=Int64.of_string ("0o"^p) in require (n>=0L) "integer overflow"; n with _ -> fail "integer overflow"
let decimal s =
  require (s<>"" && String.for_all (function '0'..'9' -> true | _ -> false) s) "invalid decimal";
  try let n=Int64.of_string s in require (n>=0L) "negative size"; n with _ -> fail "decimal overflow"
let pax data =
  let rec loop off acc = if off=String.length data then acc else (
    let sp=try String.index_from data off ' ' with _ -> fail "PAX length" in
    let n64=decimal (String.sub data off (sp-off)) in
    require (n64<=Int64.of_int (String.length data-off)) "PAX truncation";
    let n=Int64.to_int n64 in require (n>sp-off+2 && data.[off+n-1]='\n') "PAX record";
    let body=String.sub data (sp+1) (off+n-sp-2) in
    let eq=try String.index body '=' with _ -> fail "PAX key" in
    let k=String.sub body 0 eq and v=String.sub body (eq+1) (String.length body-eq-1) in
    require (List.mem k ["path";"size";"mtime";"uid";"gid";"uname";"gname"] && not (List.mem_assoc k acc) && not (String.contains v '\000')) "unsupported/duplicate PAX key";
    loop (off+n) ((k,v)::acc)) in loop 0 []
let verify ~limits:l ~normalized:normalize ~expected ic =
  require (l.max_members>=0 && l.max_member_bytes>=0L && l.max_tar_bytes>=1024L && l.max_pax_bytes>0 && l.max_name_bytes>0) "invalid limits";
  validate_inventory expected; require (List.length expected<=l.max_members) "inventory count limit";
  let seen=Hashtbl.create 16 and inventory=Hashtbl.create 16 and total=ref 0L in
  List.iter (fun (n,h) -> Hashtbl.add inventory n h) expected;
  let account n = require (n>=0L && n<=Int64.sub l.max_tar_bytes !total) "tar byte limit"; total:=Int64.add !total n in
  let read n = account (Int64.of_int n); really_input_string ic n in
  let zero s = String.for_all ((=) '\000') s in
  let padding n = require (zero (read (pad n))) "nonzero data padding" in
  let rec loop pending count acc =
    let h=read 512 in
    if zero h then (
      require (pending=None && zero (read 512)) "missing tar terminator";
      let b=Bytes.create 65536 in
      let rec drain () = let n=input ic b 0 65536 in if n>0 then (account (Int64.of_int n); for i=0 to n-1 do require (Bytes.get b i='\000') "trailing nonzero data" done; drain ()) in
      drain (); require (Int64.rem !total 512L=0L) "partial trailing block";
      require (Hashtbl.length seen=List.length expected) "missing members"; List.rev acc)
    else (
      let sum=ref 0 in String.iteri (fun i c -> sum:= !sum + if i>=148 && i<156 then 32 else Char.code c) h;
      require (number h 148 8=Int64.of_int !sum) "tar checksum";
      require (String.sub h 257 8="ustar\00000") "unsupported tar format";
      require (text h 157 100="" && zero (String.sub h 500 12)) "link/extension header";
      List.iter (fun off -> require (zero (String.sub h off 8) || number h off 8=0L) "nonzero device number") [329;337];
      let size=number h 124 12 in
      let m={mode=Int64.to_int (number h 100 8);uid=number h 108 8;gid=number h 116 8;uname=text h 265 32;gname=text h 297 32;mtime=Int64.to_string (number h 136 12)} in
      match h.[156] with
      | 'x' ->
        require (pending=None && size<=Int64.of_int l.max_pax_bytes) "PAX bound/sequence";
        let p=pax (read (Int64.to_int size)) in padding size; loop (Some p) count acc
      | '0' | '\000' ->
        require (count<l.max_members) "member count limit";
        let p=Option.value pending ~default:[] in
        let get k fallback=Option.value (List.assoc_opt k p) ~default:fallback in
        let prefix=text h 345 155 in
        let raw=text h 0 100 in let name=get "path" (if prefix="" then raw else prefix^"/"^raw) in
        require (String.length name<=l.max_name_bytes) "name limit"; validate_name name;
        require (not (Hashtbl.mem seen name)) "duplicate member";
        let wanted=try Hashtbl.find inventory name with Not_found -> fail ("extra member: "^name) in
        let size=match List.assoc_opt "size" p with None -> size | Some s -> decimal s in
        require (size<=l.max_member_bytes) "member size limit";
        let m={m with uid=decimal (get "uid" (Int64.to_string m.uid));gid=decimal (get "gid" (Int64.to_string m.gid));uname=get "uname" m.uname;gname=get "gname" m.gname;mtime=get "mtime" m.mtime} in
        let time=try float_of_string m.mtime with _ -> fail "invalid mtime" in
        require (Float.is_finite time) "nonfinite mtime";
        if normalize then require (m.mode=0o644 && m.uid=0L && m.gid=0L && m.uname="" && m.gname="" && time=0.) "nonnormalized metadata";
        account size; let sha256=copy ic None size in padding size;
        require (sha256=wanted) ("hash mismatch: "^name); Hashtbl.add seen name ();
        loop None (count+1) ({name;bytes=size;sha256;metadata=m}::acc)
      | _ -> fail "nonregular/unsupported member type") in
  loop None 0 []
