module U = Unix
open! Core
module J = Preparation_json
type t = Yojson.Safe.t
let to_json t = t
let identity t = J.get t "identity" |> J.string
let valid_path path =
  not (String.is_empty path) && Filename.is_relative path
  && List.for_all (String.split path ~on:'/') ~f:(fun c ->
    not (String.is_empty c) && not (String.equal c ".") && not (String.equal c ".."))
;;
let git root args =
  let argv = Array.of_list ("git" :: "-C" :: root :: args) in
  let channel = U.open_process_args_in "git" argv in
  let output = Stdlib.In_channel.input_all channel in
  match U.close_process_in channel with
  | U.WEXITED 0 -> String.rstrip output ~drop:(Char.equal '\n')
  | _ -> J.fail "Git observation failed"
;;
let observe ~source_root ~input_paths = Or_error.try_with (fun () ->
  let paths = List.dedup_and_sort input_paths ~compare:String.compare in
  if List.is_empty paths then J.fail "nonempty declared source inventory required";
  List.iter paths ~f:(fun p -> if not (valid_path p) then J.fail "invalid source path");
  let root = U.realpath source_root in
  let prefix = if String.equal root "/" then root else root ^ "/" in
  let revision = git root ["rev-parse"; "HEAD"] in
  let inputs = List.map paths ~f:(fun path ->
    let full = Filename.concat root path in
    let real = U.realpath full in
    if not (String.is_prefix real ~prefix) then J.fail "source escapes root";
    if not (Poly.equal (U.stat full).st_kind U.S_REG) then J.fail "source is not a regular file";
    let contents = In_channel.read_all full in
    let status = git root ["status"; "--porcelain"; "--untracked-files=all"; "--"; path] in
    J.obj ["path", J.str path; "sha256", J.str (J.sha256 contents);
           "git_status", J.str status]) in
  let payload = ["schema_version", `Int 1; "source_revision", J.str revision;
                 "inputs", `List inputs] in
  J.obj (("identity", J.str (J.hash "source" (J.obj payload))) :: payload))
;;
let of_json = J.checked (fun j ->
  J.exact j ["schema_version"; "identity"; "source_revision"; "inputs"];
  J.expect (J.get j "schema_version") (`Int 1);
  let revision = J.get j "source_revision" |> J.string in
  if not (List.mem [40;64] (String.length revision) ~equal:Int.equal)
     || not (String.for_all revision ~f:(function '0'..'9' | 'a'..'f' -> true | _ -> false))
  then J.fail "invalid source revision";
  let paths = J.get j "inputs" |> J.list |> List.map ~f:(fun input ->
    J.exact input ["path"; "sha256"; "git_status"];
    ignore (J.digest (J.get input "sha256") : string);
    ignore (J.string (J.get input "git_status") : string);
    let path = J.get input "path" |> J.string in
    if not (valid_path path) then J.fail "invalid source path";
    path) in
  if List.is_empty paths || not (List.equal String.equal paths (List.dedup_and_sort paths ~compare:String.compare))
  then J.fail "source paths must be nonempty, unique and sorted";
  let payload = J.obj (List.filter (J.fields j) ~f:(fun (k, _) -> not (String.equal k "identity"))) in
  if not (String.equal (J.digest (J.get j "identity")) (J.hash "source" payload))
  then J.fail "source identity mismatch";
  j)
