type token = Word of string | Quoted of string
exception Invalid of string
let invalid reason = raise (Invalid reason)

(* Bounded lexical scan: delimiters in comments/strings never change scope. *)
let tokens raw =
  let n=String.length raw and count=ref 0 in
  let white=function ' '| '\t'|'\r'|'\n' -> true | _ -> false in
  let punctuation c=String.contains "(){}:;," c in
  let rec lex i acc =
    if i>=n then List.rev acc else if white raw.[i] then lex (i+1) acc
    else if i+1<n && raw.[i]='/' && raw.[i+1]='*' then (
      let j=try Str.search_forward (Str.regexp_string "*/") raw (i+2) with Not_found -> invalid "unterminated Liberty comment" in
      lex (j+2) acc)
    else if i+1<n && raw.[i]='/' && raw.[i+1]='/' then (
      match String.index_from_opt raw (i+2) '\n' with None -> List.rev acc | Some j -> lex (j+1) acc)
    else (
      if !count>=1048576 then invalid "Liberty token bound exceeded";incr count;
      if raw.[i]='"' then (
        let b=Buffer.create 32 in
        let rec quoted j =
          if j>=n then invalid "unterminated Liberty string"
          else if raw.[j]='"' then j+1
          else if raw.[j]='\\' then (
            if j+1>=n then invalid "unterminated Liberty escape";
            Buffer.add_char b '\\';Buffer.add_char b raw.[j+1];quoted (j+2))
          else (Buffer.add_char b raw.[j];quoted (j+1)) in
        let stop=quoted (i+1) in lex stop (Quoted (Buffer.contents b)::acc))
      else if punctuation raw.[i] then lex (i+1) (Word (String.make 1 raw.[i])::acc)
      else (
        let j=ref (i+1) in
        while !j<n && not (white raw.[!j] || punctuation raw.[!j] || raw.[!j]='"' ||
          (!j+1<n && raw.[!j]='/' && List.mem raw.[!j+1] ['*';'/'])) do incr j done;
        lex !j (Word (String.sub raw i (!j-i))::acc))) in
  lex 0 []

let check raw = try
  if String.length raw>32*1024*1024 then invalid "Liberty byte bound exceeded";
  let lines=String.fold_left (fun n c -> if c='\n' then n+1 else n) 1 raw in
  if lines>262144 then invalid "Liberty line bound exceeded";
  let body=match tokens raw with
    | Word "library"::Word "("::(Word _|Quoted _)::Word ")"::Word "{"::rest -> rest
    | _ -> invalid "timing units require one explicit library scope" in
  let times=ref 0 and caps=ref 0 in
  let rec scan depth parens at_start = function
    | [] -> invalid "unbalanced/truncated Liberty library scope"
    | Word "}"::[] when depth=1 && parens=0 -> ()
    | Word "}"::rest when depth>1 && parens=0 -> scan (depth-1) 0 true rest
    | Word "}"::_ -> invalid "unbalanced/multiple Liberty library scopes"
    | Word "{"::rest when parens=0 ->
      if depth>=256 then invalid "Liberty nesting bound exceeded";
      scan (depth+1) 0 true rest
    | Word "{"::_ -> invalid "Liberty brace inside unbalanced parentheses"
    | Word "("::rest -> if parens>=256 then invalid "Liberty parentheses bound exceeded";
      scan depth (parens+1) false rest
    | Word ")"::rest when parens>0 -> scan depth (parens-1) false rest
    | Word ")"::_ -> invalid "unbalanced Liberty parentheses"
    | Word "time_unit"::rest ->
      if depth<>1 || parens<>0 || not at_start then invalid "time_unit is not a direct library attribute";
      (match rest with Word ":"::Quoted "1ns"::Word ";"::rest ->
        incr times;if !times<>1 then invalid "duplicate/conflicting library time_unit";scan depth 0 true rest
       | _ -> invalid "missing/conflicting/unsupported library time_unit (requires 1ns)")
    | Word "capacitive_load_unit"::rest ->
      if depth<>1 || parens<>0 || not at_start then invalid "capacitive_load_unit is not a direct library attribute";
      (match rest with Word "("::Word "1"::Word ","::Word "pF"::Word ")"::Word ";"::rest ->
        incr caps;if !caps<>1 then invalid "duplicate/conflicting library capacitance unit";scan depth 0 true rest
       | _ -> invalid "missing/conflicting/unsupported library capacitance unit (requires (1,pF))")
    | Word ";"::rest when parens=0 -> scan depth parens true rest
    | _::rest -> scan depth parens false rest in
  scan 1 0 true body;
  if !times<>1 || !caps<>1 then invalid "missing direct library time_unit/capacitive_load_unit";
  Ok ()
with Invalid reason -> Error reason
