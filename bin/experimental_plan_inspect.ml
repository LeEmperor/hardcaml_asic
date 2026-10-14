module P = Hardcaml_asic_execution.Execution_plan
module J = Hardcaml_asic_execution.Identity_json

let usage = "Usage: hardcaml-asic-experimental-plan-inspect [FILE|-]\n\
             Validate schema 1/2/3 JSON and print normalized plan, actions and static capabilities.\n\
             Omitted FILE or - reads stdin. No tools are probed or executed."
let read_all ic =
  let b = Buffer.create 4096 in
  let chunk = Bytes.create 4096 in
  let rec loop () = match input ic chunk 0 4096 with
    | 0 -> Buffer.contents b
    | n -> Buffer.add_subbytes b chunk 0 n; loop () in
  loop ()
let fail message = prerr_endline message; exit 2
let () =
  let path = match Array.to_list Sys.argv with
    | [_] -> "-"
    | [_; ("--help" | "-h")] -> print_endline usage; exit 0
    | [_; path] when path = "-" || not (String.starts_with ~prefix:"-" path) -> path
    | _ -> fail usage in
  try
    let text = if path = "-" then read_all stdin else
      let ic = open_in_bin path in
      Fun.protect ~finally:(fun () -> close_in ic) (fun () -> read_all ic) in
    match P.parse text with
    | Ok plan -> print_endline (J.canonical (P.inspection plan))
    | Error message -> fail ("Invalid execution plan: " ^ message)
  with Sys_error message -> fail message
