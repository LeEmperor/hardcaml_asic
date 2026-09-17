(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "bundle.ml" *)
(* Source implementation of the TT/LibreLane project bundle. A bundle is the answer to
   "what exactly would be handed to the flow, and where did every byte come from?";

   It is an in-memory list of files plus a manifest describing them. [render] builds one
   out of a Resolved_build.t (and optionally a separately elaborated simulation Build.t),
   reading the declared source inputs and git state under [source_root]; [write] then puts
   it on disk. examples/tt_bundle_example.ml is the caller today: it runs
   Project.elaborate_for_flow and Project.elaborate ~mode:Simulation, renders, writes, and
   prints the identity.

   Rendering and writing are split on purpose: everything that decides the bundle's
   contents happens in [render], without touching the output directory, so a bundle can be
   inspected through [file], [paths] and [manifest] before anything lands on disk, and a
   render failure (a missing input, no git commit) writes nothing.

   It does NOT validate the design, the target or the settings; Resolved_build already
   did, and this module leans on those guarantees (one clock on "clk", nonempty views, no
   override of a generated setting). It does NOT run any EDA tool, touch the PDK or link
   the TT support-tools checkout at OUTPUT/tt; running the flow is P4 work. Layout and
   manifest fields are described in docs/bundle-emission.md.
*)

(* Aliased before [open! Core] on purpose; Core shadows Unix with an empty, deprecated
   module, so after the open [Unix.realpath] would not even exist;
*)
module U = Unix
open! Core
open! Hardcaml

[@@@ocamlformat "disable"]

(* The bundle itself;

   files    : (bundle relative path, contents), sorted by path, with "manifest.json"
              appended last;
   manifest : the manifest JSON, identity field included; same bytes as "manifest.json"
              apart from pretty printing;
   identity : SHA-256 of the manifest payload without the identity field;

   Transparent here but abstract in the mli, so the only way to get one is [render], which
   means [files], [manifest] and [identity] always agree.
*)
type t =
  { files    : (string * string) list
  ; manifest : Yojson.Safe.t
  ; identity : string
  }

(* Lowercase hex SHA-256 of [contents]; Cryptokit hands back the 32 raw digest bytes, so
   they get hex encoded here. Same form sha256sum and Python's hexdigest print, which is
   what test/check_bundle.py compares against;
*)
let sha256 contents =
  Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) contents
  |> String.to_list
  |> List.map ~f:(fun c -> Printf.sprintf "%02x" (Char.to_int c))
  |> String.concat
;;

(* Pretty printed JSON plus a trailing newline; how every .json file is written; *)
let json value = Yojson.Safe.pretty_to_string value ^ "\n"

(* Shorthand for a JSON string, so manifest builders read as key/value tables; *)
let string value = `String value

(* Shorthand for a JSON object; field order is kept as given, and it is part of the
   identity (see [render]);
*)
let assoc fields = `Assoc fields

(* Shorthand for a JSON list built by mapping [f] over [values]; *)
let list f values = `List (List.map values ~f)

(* An OCaml value as a JSON string holding its human readable sexp; the manifest records
   requests, selections and roles the same way the expect tests print them;
*)
let sexp to_sexp value = string (Sexp.to_string_hum (to_sexp value))

(* Run "git -C [root] [args]" and return its stdout; Or_error since a missing git or a
   [root] outside any repository is an ordinary [render] failure, not a bug;

   Only trailing newlines are dropped, never leading whitespace: porcelain status lines
   start with a meaningful space (" M lib/build.ml" is a modified, unstaged file), and
   test/check_bundle.py checks for exactly that prefix.

   git's own stderr is not captured; it goes straight to the process stderr.

   TODO (future fix): the failure message formats [args] into the string instead of
   attaching them as [%message] fields, against docs/comment_guidelines.md section 9, and
   it drops the exit status; see [read_input] for the other messages in this file;
*)
let run_git root args =
  let argv = Array.of_list ("git" :: "-C" :: root :: args) in
  Or_error.try_with (fun () ->
    let channel = U.open_process_args_in "git" argv in

    (* All of stdout, read before closing so git never blocks on a full pipe *)
    let output =
      Stdlib.In_channel.input_all channel
      |> String.rstrip ~drop:(Char.equal '\n')
    in

    match U.close_process_in channel with

    (* git exited cleanly; its output is the answer *)
    | U.WEXITED 0 -> output

    (* Nonzero exit, or killed by a signal; the output is discarded *)
    | _ -> failwithf "git failed: %s" (String.concat ~sep:" " args) ())
;;

(* Is [path] a plain relative path that stays under whatever it is joined onto?;

   ""             -> invalid;
   "/etc/passwd"  -> invalid, absolute;
   "lib//x.ml"    -> invalid, empty component;
   "./lib/x.ml"   -> invalid, "." component;
   "../x.ml"      -> invalid, ".." component;
   "lib/x.ml"     -> valid;

   Rejecting "." as well as ".." on purpose: every valid path then has exactly one
   spelling, so "inputs/<path>" in the bundle and "path" in the manifest are canonical.
   This is purely textual; symlinks are handled by [read_input].
*)
let valid_path path =
  not (String.is_empty path)
  && not (String.is_prefix path ~prefix:"/")
  && List.for_all (String.split path ~on:'/') ~f:(fun component ->
    not (String.is_empty component)
    && not (String.equal component ".")
    && not (String.equal component ".."))
;;

(* Read one declared source input's exact bytes;

   1. [path] fails [valid_path] -> error, before touching the file system;
   2. the joined path is missing or is a directory -> error;
   3. the resolved file is not under the resolved [source_root] -> error; this catches a
      symlink inside the root that points outside it;
   4. otherwise read the bytes, dirty or untracked alike;

   Careful: step 3 compares against [real_root ^ "/"], so a [source_root] of "/" becomes
   "//" and rejects every input. Nobody bundles from the file system root, but the error
   ("escapes source root") would be misleading if they did.

   TODO (future fix): these messages, [run_git]'s and [write]'s format paths into the
   string rather than attaching [%message] fields (docs/comment_guidelines.md section 9).
   test/check_bundle.py matches "source input is missing" in stderr, so change that
   assertion in the same commit;
*)
let read_input ~source_root path =
  if not (valid_path path)
  then Or_error.error_s [%message "invalid source input path" (path : string)]
  else (
    let full = Filename.concat source_root path in
    Or_error.try_with (fun () ->

      (* Step 2; a dangling symlink counts as missing, since file_exists follows it *)
      if not (Stdlib.Sys.file_exists full) || Stdlib.Sys.is_directory full
      then failwithf "source input is missing: %s" full ();

      (* Step 3 *)
      let real_root = U.realpath source_root in
      let real_file = U.realpath full in
      if not (String.is_prefix real_file ~prefix:(real_root ^ "/"))
      then failwithf "source input escapes source root: %s" path ();

      (* Step 4 *)
      In_channel.read_all full))
;;

(* Render constraints/top.sdc; one clock plus a max delay per declared I/O delay;

   The clock name and port are both hardcoded to "clk"; that is safe because
   Resolved_build.validate_timing only accepts exactly one clock, on "clk". Delays arrive
   already sorted by port from the same function, so the file is deterministic;

   Numbers print with "%.17g", enough digits to round trip any float exactly, so the SDC
   period is the same number as CLOCK_PERIOD in config.json (test/check_bundle.py checks
   this) rather than a rounded neighbour;
*)
let sdc (resolved : Resolved_build.t) =

  let number value = Printf.sprintf "%.17g" value in

  (* One "set_<direction>_delay" line for a (port, maximum ns) pair *)
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

(* Render the Tiny Tapeout info.yaml; project metadata, pinout and the single source file;

   Built as text rather than through a YAML library. Every user supplied string goes
   through [yaml_string], a JSON string literal, which is also a valid YAML double quoted
   scalar, so quotes, colons and non-ASCII text cannot break the document;

   clock_hz prints with "%.12g" rather than "%.17g": it is derived as 1e9 /. period, so a
   48 MHz clock would otherwise show float noise instead of "48000000"
   (test/check_bundle.py checks for exactly that);

   Fixed on purpose: discord is always empty, language is always "Verilog", source_files
   lists only [source_name] (the synthesis RTL, never the simulation RTL), and
   yaml_version is 6, the version the pinned TT support tools read;
*)
let info_yaml (resolved : Resolved_build.t) source_name =

  let build = resolved.build in
  let metadata = Build.metadata build in
  let yaml_string value = Yojson.Safe.to_string (`String value) in

  (* ui, then uo, then uio, the order TT's project_info.py reads them; no wildcard, so a
     new bank fails to compile here until someone places it *)
  let bank_order = function Pinout.Bank.Ui -> 0 | Uo -> 1 | Uio -> 2 in

  (* Pin lines sorted by bank, then bit, whatever order they were declared in *)
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

(* Render the LibreLane configuration for src/config.json; the resolved settings plus the
   three settings only the bundle can know (where it put the RTL and the SDC);

   Every "dir::" path is relative to src/config.json itself:

   VERILOG_FILES   -> "dir::<top>.v", next to config.json;
   *_SDC_FILE      -> "dir::../constraints/top.sdc";
   FP_DEF_TEMPLATE -> rewritten from a support-tools relative path to "dir::../tt/<path>",
                      since the TT checkout is expected to be linked at OUTPUT/tt;

   Keys are sorted, so the JSON is deterministic whatever order Resolved_build produced.
   Why no duplicate keys: VERILOG_FILES and anything containing "SDC" are protected keys
   in Resolved_build, so no override can collide with a generated setting here;

   TODO (future fix): the three generated settings are written out again in [render]'s
   "generated_settings"; one shared list would stop the two from drifting apart;
*)
let config (resolved : Resolved_build.t) source_name =

  (* Resolved settings as (key, value), with only the floorplan path rewritten *)
  let settings =
    List.map resolved.settings ~f:(fun setting ->
      let value =
        if String.equal setting.key "FP_DEF_TEMPLATE"
        then `String ("dir::../tt/" ^ resolved.target.floorplan.path)
        else setting.value
      in
      setting.key, value)
  in

  (* Settings that point at files this bundle emits *)
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

(* One resource record as a manifest entry; identity as its string form, everything else
   as a sexp string (see [sexp]). The full decision chain is kept, request through source
   roles, so the manifest says WHY each resource was built the way it was;
*)
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

(* One external target reference (floorplan or PDK view) as a manifest entry; [sha256] and
   [corner] become JSON null when unknown, rather than being left out, so every entry has
   the same keys;
*)
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

(* One resolved setting as a manifest entry; unlike config.json, this keeps the [owner],
   so an override is recorded along with its reason;
*)
let setting_json (setting : Resolved_build.Setting.t) =
  assoc
    [ "key", string setting.key
    ; "value", setting.value
    ; "owner", sexp Resolved_build.Setting.Owner.sexp_of_t setting.owner
    ]
;;

(* The main sauce here for bundles; given a resolved build, produce every file of the
   bundle and a manifest that pins down where each byte came from;

   1. [simulation_build], if given, must be a Simulation build of the same project and
      top module -> otherwise error;
   2. generate synthesis RTL from the resolved build, and simulation RTL from
      [simulation_build] when there is one;
   3. dedup and sort [input_paths]; none left -> error;
   4. read git HEAD of [source_root] -> error when there is no repository or no commit;
   5. read every input's bytes (see [read_input]) and its git status -> every input that
      fails is reported in one combined error; an input whose read fails skips its git
      status;
   6. collect produced and copied files, sorted by path;
   7. build the manifest payload and hash it into the identity;
   8. prepend the identity to the payload, and append "manifest.json" to the files;

   Returns Or_error rather than raising since it reads the file system and runs git after
   elaboration is over, where a missing input is an ordinary user mistake; the example
   decides to [ok_exn]. Nothing is written on any path, success or failure;

   The identity is the SHA-256 of the compact payload, which is everything in the manifest
   except the identity itself. It covers the git revision, each input's git status and
   content hash, and every emitted file's hash, so the same design rendered from a
   different commit or a dirty tree gets a different identity -> see test/check_bundle.py.

   A consequence: the payload's field ORDER is part of the identity. Reordering fields,
   renaming one, or bumping a requested tool version below changes every identity even
   when no design changed; bump "schema_version" when that is intended.

   Careful: without [simulation_build], "simulation_sources" points at the synthesis RTL
   under src/, and "simulation_resources" is empty. A simulation consumer then compiles
   the synthesis RTL, without any simulation only behavior (the memory example's
   diagnostic initialisation, for one), and nothing says so apart from that path.
*)
let render
    ?simulation_build (* a separate Simulation elaboration of the same project; *)
    ~source_root (* git checkout that [input_paths] are relative to; *)
    ~input_paths (* generator sources to copy and hash; order and repeats ignored; *)
    (resolved : Resolved_build.t)
  =
  let build = resolved.build in
  let top = Circuit.name (Build.circuit build) in
  let source_name = top ^ ".v" in

  (* The simulation build must describe the same design, or the two RTL sets disagree *)
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

  (* Synthesis RTL, one file holding the full module hierarchy *)
  let rtl =
    Rtl.create Verilog [ Build.circuit build ] |> Rtl.full_hierarchy |> Rope.to_string
  in

  (* Simulation RTL from its own elaboration; never meant to be compiled with [rtl] *)
  let simulation_rtl =
    Option.map simulation_build ~f:(fun simulation ->
      Rtl.create Verilog [ Build.circuit simulation ]
      |> Rtl.full_hierarchy
      |> Rope.to_string)
  in

  (* config.json's value; also recorded in the manifest as "flow_configuration" *)
  let flow_configuration = config resolved source_name in

  (* Step 3; order and repeats in the declaration do not matter *)
  let input_paths = List.dedup_and_sort input_paths ~compare:String.compare in

  (* TODO (possible optimization): this check runs after both RTL sets are generated; it
     could move to the top, since it needs nothing computed above; *)
  (* TODO (future fix): this message and the simulation build one above use
     error_string with no fix, against docs/comment_guidelines.md section 9; see
     [read_input] for the other messages in this file; *)
  let%bind.Or_error () =
    if List.is_empty input_paths
    then Or_error.error_string "bundle needs at least one declared source input"
    else Ok ()
  in

  (* Step 4; the commit checked out, NOT where the inputs are read from, which is the
     working tree (so dirty files are copied as they are) *)
  let%bind.Or_error source_revision = run_git source_root [ "rev-parse"; "HEAD" ] in

  (* Step 5; (path, bytes, porcelain status) per input; status is "" for a clean tracked
     file;

     Careful: a file ignored by .gitignore also reports "", so it looks clean in the
     manifest. Its bytes are still copied and hashed, so the identity still covers it.

     TODO (possible optimization): one git status per input; a single call over all paths
     would do, if input lists grow;
  *)
  let%bind.Or_error inputs =
    Or_error.all
      (List.map input_paths ~f:(fun path ->
         let%bind.Or_error contents = read_input ~source_root path in
         let%map.Or_error status =
           run_git
             source_root
             [ "status"; "--porcelain"; "--untracked-files=all"; "--"; path ]
         in
         path, contents, status))
  in

  (* Files generated from the declaration; simulation/ only with a simulation build *)
  let produced =
    [ "src/" ^ source_name, rtl
    ; "src/config.json", json flow_configuration
    ; "constraints/top.sdc", sdc resolved
    ; "info.yaml", info_yaml resolved source_name
    ]
    @ Option.value_map simulation_rtl ~default:[] ~f:(fun rtl ->
      [ "simulation/" ^ source_name, rtl ])
  in

  (* Exact copies of the declared inputs; [valid_path] keeps them under inputs/ *)
  let copied = List.map inputs ~f:(fun (path, data, _) -> "inputs/" ^ path, data) in

  (* Every file except the manifest, sorted, so the inventory order is deterministic *)
  let files =
    List.sort (produced @ copied) ~compare:(fun (a, _) (b, _) -> String.compare a b)
  in

  (* Inventory entry for one emitted file *)
  let file_json (path, data) =
    assoc [ "path", string path; "sha256", string (sha256 data) ]
  in

  (* Provenance entry per input: where it came from, where the copy is, and its state *)
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

  (* Where simulation consumers compile from; falls back to src/, see Careful above *)
  let simulation_source =
    (if Option.is_some simulation_rtl then "simulation/" else "src/") ^ source_name
  in

  (* Only [operation] is used; the adapter is always LibreLane here *)
  let flow = Build.flow build in

  (* Step 7; the manifest without its identity; see the header for why field ORDER
     matters;

     pdk_revision: the first view's revision. The [] arm is unreachable in practice, since
     Resolved_build.validate_capabilities requires the PDK configuration view for every
     operation; if views ever come from different PDK revisions, only the first is kept.

     librelane and python are the versions the bundle asks for, NOT versions that ran;
     run records are P4 (docs/bundle-emission.md);
  *)
  let payload =
    assoc
      [ "schema_version", `Int 1
      ; "project", string (Build.project_name build)
      ; "top_module", string top
      ; "source_revision", string source_revision
      ; "source_inputs", inputs_json
      ; "files", list file_json files
      ; "synthesis_sources", `List [ string ("src/" ^ source_name) ]
      ; "simulation_sources", `List [ string simulation_source ]
      ; "resources", list resource_json (Build.resources build)
      ; ( "simulation_resources"
        , Option.value_map simulation_build ~default:(`List []) ~f:(fun simulation ->
            list resource_json (Build.resources simulation)) )
      ; ( "target"
        , assoc
            [ "harness", sexp Harness.sexp_of_t resolved.target.harness
            ; "technology", string resolved.target.technology_name
            ; "tiles", string resolved.target.tiles
            ; "corner", string resolved.target.corner
            ; ( "external_references"
              , list reference_json (resolved.target.floorplan :: resolved.target.views) )
            ] )
      ; "adapter", string "LibreLane"
      ; "operation", sexp Flow.Operation.sexp_of_t flow.operation
      ; "resolved_settings", list setting_json resolved.settings
      ; "flow_configuration", flow_configuration
      ; ( "generated_settings"
        , assoc
            [ "VERILOG_FILES", `List [ string ("dir::" ^ source_name) ]
            ; "PNR_SDC_FILE", string "dir::../constraints/top.sdc"
            ; "SIGNOFF_SDC_FILE", string "dir::../constraints/top.sdc"
            ] )
      ; ( "requested_tools"
        , assoc
            [ "support_tools_revision", string resolved.target.floorplan.revision
            ; ( "pdk_revision"
              , string
                  (match resolved.target.views with
                   | view :: _ -> view.revision
                   | [] -> "") )
            ; "librelane", string "3.1.0.dev3"
            ; "python", string "3.11"
            ] )
      ]
  in

  (* Hashed in compact form, so pretty printing of manifest.json never affects it *)
  let identity = sha256 (Yojson.Safe.to_string payload) in

  (* Step 8; the payload with "identity" as its first field *)
  let manifest =
    match payload with
    | `Assoc fields -> assoc (("identity", string identity) :: fields)
    | _ -> assert false (* can never happen; [payload] is built with [assoc] just above *)
  in

  (* manifest.json goes last and is NOT in its own inventory, since it holds the hashes *)
  Ok { files = files @ [ "manifest.json", json manifest ]; manifest; identity }
;;

(* grab one file's contents by bundle relative path; a linear scan, bundles are small *)
let file t path = List.Assoc.find t.files path ~equal:String.equal

(* grab every bundle relative path; sorted, except "manifest.json" which is always last *)
let paths t = List.map t.files ~f:fst

(* grab the manifest, identity included *)
let manifest t = t.manifest

(* grab the identity; the example prints this next to the output directory *)
let identity t = t.identity

(* "mkdir -p" for [path]; creates missing parents first, with mode 0o755;

   Careful: it only checks that [path] exists, not that it is a directory. A regular file
   in the way is not caught here; the next mkdir or write under it raises instead, which
   [write] turns into an error;
*)
let rec mkdir_p path =
  if not (Stdlib.Sys.file_exists path)
  then (
    mkdir_p (Filename.dirname path);
    U.mkdir path 0o755)
;;

(* Put a bundle on disk under [output_dir]; Or_error rather than raising since this is
   plain file system work at the end of a run, where the caller decides how to fail;

   not a directory : [output_dir] exists but is a file -> error;
   not empty       : [output_dir] has any entry -> error, nothing written;
   missing         : [output_dir] and its parents are created;

   The emptiness check is what guarantees no existing file is ever replaced; the writes
   themselves would happily truncate one. No path can escape [output_dir]: generated paths
   are fixed, and copied inputs passed [valid_path] in [render].

   Careful: writing is not atomic. A failure halfway (disk full, permissions) leaves a
   partial bundle behind, and since that directory is no longer empty, the next [write]
   to it refuses; delete it before retrying. A second writer racing between the check and
   the writes is not caught either.
*)
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

[@@@ocamlformat "enable"]
