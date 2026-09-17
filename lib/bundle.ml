module U = Unix

open! Core
open! Hardcaml

type t =
  { files : (string * string) list
  ; manifest : Yojson.Safe.t
  ; identity : string
  }

let sha256 contents =
  Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) contents
  |> String.to_list
  |> List.map ~f:(fun c -> Printf.sprintf "%02x" (Char.to_int c))
  |> String.concat
;;

let json value = Yojson.Safe.pretty_to_string value ^ "\n"
let string value = `String value
let assoc fields = `Assoc fields
let list f values = `List (List.map values ~f)
let sexp to_sexp value = string (Sexp.to_string_hum (to_sexp value))

let run_git root args =
  let argv = Array.of_list ("git" :: "-C" :: root :: args) in
  Or_error.try_with (fun () ->
    let channel = U.open_process_args_in "git" argv in
    let output =
      Stdlib.In_channel.input_all channel
      |> String.rstrip ~drop:(Char.equal '\n')
    in
    match U.close_process_in channel with
    | U.WEXITED 0 -> output
    | _ -> failwithf "git failed: %s" (String.concat ~sep:" " args) ())
;;

let valid_path path =
  not (String.is_empty path)
  && not (String.is_prefix path ~prefix:"/")
  && List.for_all (String.split path ~on:'/') ~f:(fun component ->
    not (String.is_empty component)
    && not (String.equal component ".")
    && not (String.equal component ".."))
;;

let read_input ~source_root path =
  if not (valid_path path)
  then Or_error.error_s [%message "invalid source input path" (path : string)]
  else (
    let full = Filename.concat source_root path in
    Or_error.try_with (fun () ->
      if not (Stdlib.Sys.file_exists full) || Stdlib.Sys.is_directory full
      then failwithf "source input is missing: %s" full ();
      let real_root = U.realpath source_root in
      let real_file = U.realpath full in
      if not (String.is_prefix real_file ~prefix:(real_root ^ "/"))
      then failwithf "source input escapes source root: %s" path ();
      In_channel.read_all full))
;;

let sdc (resolved : Resolved_build.t) =
  let number value = Printf.sprintf "%.17g" value in
  let delay direction (port, maximum) =
    Printf.sprintf
      "set_%s_delay -max %s -clock clk [get_ports {%s}]\n"
      direction
      (number maximum)
      port
  in
  Printf.sprintf
    "create_clock -name clk -period %s [get_ports {clk}]\n"
    (number resolved.clock_period_ns)
  ^ (List.map resolved.input_delays_ns ~f:(delay "input") |> String.concat)
  ^ (List.map resolved.output_delays_ns ~f:(delay "output") |> String.concat)
;;

let info_yaml (resolved : Resolved_build.t) source_name =
  let build = resolved.build in
  let metadata = Build.metadata build in
  let yaml_string value = Yojson.Safe.to_string (`String value) in
  let bank_order = function Pinout.Bank.Ui -> 0 | Uo -> 1 | Uio -> 2 in
  let pins =
    List.sort (Build.pinout build) ~compare:(fun a b ->
      let c = Int.compare (bank_order a.bank) (bank_order b.bank) in
      if c <> 0 then c else Int.compare a.bit b.bit)
    |> List.map ~f:(fun pin ->
      Printf.sprintf
        "  %s[%d]: %s\n"
        (Pinout.Bank.to_string pin.bank)
        pin.bit
        (yaml_string pin.description))
    |> String.concat
  in
  String.concat
    [ "project:\n"
    ; "  title: " ^ yaml_string metadata.title ^ "\n"
    ; "  author: " ^ yaml_string metadata.author ^ "\n"
    ; "  discord: \"\"\n"
    ; "  description: " ^ yaml_string metadata.description ^ "\n"
    ; "  language: \"Verilog\"\n"
    ; "  clock_hz: " ^ Printf.sprintf "%.12g" resolved.clock_hz ^ "\n"
    ; "  tiles: " ^ yaml_string resolved.target.tiles ^ "\n"
    ; "  top_module: " ^ yaml_string (Circuit.name (Build.circuit build)) ^ "\n"
    ; "  source_files:\n    - " ^ yaml_string source_name ^ "\n"
    ; "\npinout:\n"
    ; pins
    ; "\nyaml_version: 6\n"
    ]
;;

let config (resolved : Resolved_build.t) source_name =
  let settings =
    List.map resolved.settings ~f:(fun setting ->
      let value =
        if String.equal setting.key "FP_DEF_TEMPLATE"
        then `String ("dir::../tt/" ^ resolved.target.floorplan.path)
        else setting.value
      in
      setting.key, value)
  in
  let generated =
    [ "VERILOG_FILES", `List [ `String ("dir::" ^ source_name) ]
    ; "PNR_SDC_FILE", `String "dir::../constraints/top.sdc"
    ; "SIGNOFF_SDC_FILE", `String "dir::../constraints/top.sdc"
    ]
  in
  assoc
    (List.sort (settings @ generated) ~compare:(fun (a, _) (b, _) ->
       String.compare a b))
;;

let resource_json (resource : Resource_record.t) =
  assoc
    [ "id", string (Resource_id.to_string resource.id)
    ; "request", sexp Resource_request.sexp_of_t resource.request
    ; "requirement", sexp Resource_policy.Requirement.sexp_of_t resource.requirement
    ; "policy", sexp Resource_policy.Applied.sexp_of_t resource.policy
    ; "selection", sexp Selection.sexp_of_t resource.selection
    ; "elaborated_as", sexp Resource_record.Elaborated_as.sexp_of_t resource.elaborated_as
    ; "source_roles", list (sexp Resource_record.Source.sexp_of_t) resource.sources
    ]
;;

let reference_json (reference : Target.Reference.t) =
  assoc
    [ "source", sexp Target.Reference.Source.sexp_of_t reference.source
    ; "revision", string reference.revision
    ; "role", sexp Target.Reference.Role.sexp_of_t reference.role
    ; "path", string reference.path
    ; "sha256", Option.value_map reference.sha256 ~default:`Null ~f:string
    ; "corner", Option.value_map reference.corner ~default:`Null ~f:string
    ]
;;

let setting_json (setting : Resolved_build.Setting.t) =
  assoc
    [ "key", string setting.key
    ; "value", setting.value
    ; "owner", sexp Resolved_build.Setting.Owner.sexp_of_t setting.owner
    ]
;;

let render ?simulation_build ~source_root ~input_paths (resolved : Resolved_build.t) =
  let build = resolved.build in
  let top = Circuit.name (Build.circuit build) in
  let source_name = top ^ ".v" in
  let%bind.Or_error () =
    match simulation_build with
    | None -> Ok ()
    | Some simulation ->
      if Elaboration_mode.equal (Build.mode simulation) Simulation
         && String.equal (Build.project_name simulation) (Build.project_name build)
         && String.equal (Circuit.name (Build.circuit simulation)) top
      then Ok ()
      else
        Or_error.error_string
          "simulation build must have Simulation mode and the same project and top"
  in
  let rtl =
    Rtl.create Verilog [ Build.circuit build ] |> Rtl.full_hierarchy |> Rope.to_string
  in
  let simulation_rtl =
    Option.map simulation_build ~f:(fun simulation ->
      Rtl.create Verilog [ Build.circuit simulation ]
      |> Rtl.full_hierarchy
      |> Rope.to_string)
  in
  let flow_configuration = config resolved source_name in
  let input_paths = List.dedup_and_sort input_paths ~compare:String.compare in
  let%bind.Or_error () =
    if List.is_empty input_paths
    then Or_error.error_string "bundle needs at least one declared source input"
    else Ok ()
  in
  let%bind.Or_error source_revision = run_git source_root [ "rev-parse"; "HEAD" ] in
  let%bind.Or_error inputs =
    Or_error.all
      (List.map input_paths ~f:(fun path ->
         let%bind.Or_error contents = read_input ~source_root path in
         let%map.Or_error status =
           run_git source_root [ "status"; "--porcelain"; "--untracked-files=all"; "--"; path ]
         in
         path, contents, status))
  in
  let produced =
    [ "src/" ^ source_name, rtl
    ; "src/config.json", json flow_configuration
    ; "constraints/top.sdc", sdc resolved
    ; "info.yaml", info_yaml resolved source_name
    ]
    @ Option.value_map simulation_rtl ~default:[] ~f:(fun rtl ->
      [ "simulation/" ^ source_name, rtl ])
  in
  let copied = List.map inputs ~f:(fun (path, data, _) -> "inputs/" ^ path, data) in
  let files =
    List.sort (produced @ copied) ~compare:(fun (a, _) (b, _) -> String.compare a b)
  in
  let file_json (path, data) =
    assoc [ "path", string path; "sha256", string (sha256 data) ]
  in
  let inputs_json =
    list
      (fun (path, contents, status) ->
        assoc
          [ "path", string path
          ; "copy", string ("inputs/" ^ path)
          ; "sha256", string (sha256 contents)
          ; "git_status", string status
          ])
      inputs
  in
  let flow = Build.flow build in
  let payload =
    assoc
      [ "schema_version", `Int 1
      ; "project", string (Build.project_name build)
      ; "top_module", string top
      ; "source_revision", string source_revision
      ; "source_inputs", inputs_json
      ; "files", list file_json files
      ; "synthesis_sources", `List [ string ("src/" ^ source_name) ]
      ; "simulation_sources", `List [ string
          ((if Option.is_some simulation_rtl then "simulation/" else "src/") ^ source_name) ]
      ; "resources", list resource_json (Build.resources build)
      ; "simulation_resources", Option.value_map simulation_build ~default:(`List [])
          ~f:(fun simulation -> list resource_json (Build.resources simulation))
      ; "target", assoc
          [ "harness", sexp Harness.sexp_of_t resolved.target.harness
          ; "technology", string resolved.target.technology_name
          ; "tiles", string resolved.target.tiles
          ; "corner", string resolved.target.corner
          ; "external_references", list reference_json
              (resolved.target.floorplan :: resolved.target.views)
          ]
      ; "adapter", string "LibreLane"
      ; "operation", sexp Flow.Operation.sexp_of_t flow.operation
      ; "resolved_settings", list setting_json resolved.settings
      ; "flow_configuration", flow_configuration
      ; "generated_settings", assoc
          [ "VERILOG_FILES", `List [ string ("dir::" ^ source_name) ]
          ; "PNR_SDC_FILE", string "dir::../constraints/top.sdc"
          ; "SIGNOFF_SDC_FILE", string "dir::../constraints/top.sdc"
          ]
      ; "requested_tools", assoc
          [ "support_tools_revision", string resolved.target.floorplan.revision
          ; "pdk_revision", string
              (match resolved.target.views with
               | view :: _ -> view.revision
               | [] -> "")
          ; "librelane", string "3.1.0.dev3"
          ; "python", string "3.11"
          ]
      ]
  in
  let identity = sha256 (Yojson.Safe.to_string payload) in
  let manifest =
    match payload with
    | `Assoc fields -> assoc (("identity", string identity) :: fields)
    | _ -> assert false
  in
  Ok { files = files @ [ "manifest.json", json manifest ]; manifest; identity }
;;

let file t path = List.Assoc.find t.files path ~equal:String.equal
let paths t = List.map t.files ~f:fst
let manifest t = t.manifest
let identity t = t.identity

let rec mkdir_p path =
  if not (Stdlib.Sys.file_exists path)
  then (
    mkdir_p (Filename.dirname path);
    U.mkdir path 0o755)
;;

let write t ~output_dir =
  Or_error.try_with (fun () ->
    if Stdlib.Sys.file_exists output_dir
    then (
      if not (Stdlib.Sys.is_directory output_dir)
      then failwithf "bundle output is not a directory: %s" output_dir ();
      if Array.length (Stdlib.Sys.readdir output_dir) <> 0
      then failwithf "bundle output directory is not empty: %s" output_dir ());
    List.iter t.files ~f:(fun (path, data) ->
      let full = Filename.concat output_dir path in
      mkdir_p (Filename.dirname full);
      Out_channel.write_all full ~data))
;;
