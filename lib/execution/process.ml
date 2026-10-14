type output = File of string | Descriptor of Unix.file_descr
type t =
  { prog : string
  ; argv : string list
  ; cwd : string
  ; environment : string list
  ; stdout : output
  ; stderr : output
  }

let check_string s =
  if String.contains s '\000' then invalid_arg "Process: NUL in string"
;;

let absolute s =
  check_string s;
  if s = "" || Filename.is_relative s then
    invalid_arg "Process: absolute path required"
;;

let make ~prog ~argv ~cwd ~environment ~stdout ~stderr =
  absolute prog;
  absolute cwd;
  if argv = [] then invalid_arg "Process: empty argv";
  List.iter check_string argv;
  let keys = Hashtbl.create 16 in
  List.iter
    (fun entry ->
       check_string entry;
       match String.index_opt entry '=' with
       | None | Some 0 -> invalid_arg "Process: expected KEY=VALUE"
       | Some i ->
         let key = String.sub entry 0 i in
         if Hashtbl.mem keys key then invalid_arg "Process: duplicate environment key";
         Hashtbl.add keys key ())
    environment;
  List.iter (function File p -> absolute p | Descriptor _ -> ()) [stdout; stderr];
  { prog; argv; cwd; environment; stdout; stderr }
;;
