(* Shared by rich inspection and terminal timing normalization. *)
exception Query_stop of string

let starts ~prefix s = String.starts_with ~prefix s

let contains s token =
  try
    ignore (Str.search_forward (Str.regexp_string token) s 0);
    true
  with
  | Not_found -> false
;;

let bounded_lines ~max_lines raw =
  let count = String.fold_left (fun n c -> if c = '\n' then n + 1 else n) 1 raw in
  if count > max_lines
  then Error "line count bound exceeded"
  else Ok (Array.of_list (String.split_on_char '\n' raw))
;;

let parse raw =
  if String.length raw > 32 * 1024 * 1024
  then [], [ "Liberty source byte bound exceeded" ]
  else (
    match bounded_lines ~max_lines:262144 raw with
    | Error message -> [], [ "Liberty " ^ message ]
    | Ok lines ->
      let declarations = ref []
      and diagnostics = ref [] in
      let diagnostic message =
        if List.length !diagnostics >= 256
        then raise (Query_stop "Liberty diagnostic bound exceeded")
        else diagnostics := message :: !diagnostics
      in
      let block = ref false
      and quoted = ref false
      and escaped = ref false in
      let attribute =
        Str.regexp "^[ \t]*time_unit[ \t]*:[ \t]*\"\\([^\"]*\\)\"[ \t]*;[ \t\r]*$"
      in
      (try
         Array.iteri
           (fun i line ->
             let initially_quoted = !quoted in
             let b = Buffer.create (String.length line)
             and pos = ref 0 in
             while !pos < String.length line do
               let c = line.[!pos] in
               let pair a b =
                 c = a && !pos + 1 < String.length line && line.[!pos + 1] = b
               in
               if !block
               then
                 if pair '*' '/'
                 then (
                   block := false;
                   Buffer.add_string b "  ";
                   pos := !pos + 2)
                 else (
                   Buffer.add_char b ' ';
                   incr pos)
               else if !quoted
               then (
                 Buffer.add_char b c;
                 if !escaped
                 then escaped := false
                 else if c = '\\'
                 then escaped := true
                 else if c = '"'
                 then quoted := false;
                 incr pos)
               else if pair '/' '*'
               then (
                 block := true;
                 Buffer.add_string b "  ";
                 pos := !pos + 2)
               else if pair '/' '/'
               then (
                 Buffer.add_string b (String.make (String.length line - !pos) ' ');
                 pos := String.length line)
               else (
                 if c = '"' then quoted := true;
                 Buffer.add_char b c;
                 incr pos)
             done;
             let clean = Buffer.contents b in
             let trimmed = String.trim clean in
             let candidate =
               (not initially_quoted)
               && starts ~prefix:"time_unit" trimmed
               && (String.length trimmed = 9 || List.mem trimmed.[9] [ ' '; '\t'; ':' ])
             in
             if candidate
             then
               if Str.string_match attribute clean 0
                  && Str.match_end () = String.length clean
               then (
                 let unit = Str.matched_group 1 clean in
                 if contains unit "\\"
                 then
                   diagnostic
                     (Printf.sprintf
                        "malformed Liberty time_unit declaration line %d: escaped unit"
                        (i + 1))
                 else (
                   if List.length !declarations >= 64
                   then raise (Query_stop "Liberty declaration bound exceeded (64)");
                   declarations := (i + 1, unit, line) :: !declarations))
               else
                 diagnostic
                   (Printf.sprintf
                      "malformed Liberty time_unit declaration line %d: expected quoted \
                       unit and semicolon"
                      (i + 1)))
           lines
       with
       | Query_stop message -> diagnostics := message :: !diagnostics);
      if !block
      then
        diagnostics
        := "malformed Liberty unit evidence: unterminated block comment" :: !diagnostics;
      List.rev !declarations, List.rev !diagnostics)
;;
