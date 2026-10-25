let note = "source-artifact identity is not implemented until P6.5: this build carries no stamp, so the revision, checkout state and source-inventory digest are unknown and the library/executor artifact match is unverified"
let describe () =
  let module_dir=Flow_cli_paths.resources () in
  let data_dir=module_dir^"/data" in
  let version,source=try
    let ic=open_in (data_dir^"/version.txt") in
    let s=Fun.protect ~finally:(fun () -> close_in ic) (fun () -> String.trim (really_input_string ic (in_channel_length ic))) in
    if s="" then "0.1.0","source-tree-declaration" else s,"installed-package-metadata"
    with Sys_error _ | End_of_file -> "0.1.0","source-tree-declaration" in
  let strings xs = `List (List.map (fun s -> `String s) xs) in
  `Assoc ["tool",`String "hardcaml-asic-flow";"identity_schema",`Int 1;
    "package_version",`String version;"package_version_source",`String source;
    "supported_record_schemas",`List [`Int 1];
    "source",`Assoc ["stamped",`Bool false;"revision",`Null;"state",`String "unknown";
      "inventory_digest",`Null;"library_artifact_match",`Null;"note",`String note];
    "module_dir",`String module_dir;"data_dir",`String data_dir;
    "toolchain_lock",`String (data_dir^"/toolchain.lock");
    "toolchain_lock_present",`Bool (try (Unix.stat (data_dir^"/toolchain.lock")).Unix.st_kind=Unix.S_REG with Unix.Unix_error _ -> false);
    "cli_contract",`Assoc ["version",`Int 4;"default_output",`String "human";"json_option",`String "--json";
      "results_defaults",`Assoc ["root",`String "<caller-cwd>/_flow_results";"operations",`String "<results-root>/operations";
        "runs",`String "<results-root>/runs";"stage_observations",`String "<resolved-workspace-parent>/observations"];
      "capabilities",`Assoc [
         "namedflow1",`Bool true;
         "preparation1",`Bool true;
        "inspection1",`Bool true;
        "timing_analysis1",`Bool true;
        "timing_stage1",`Bool true;
        "json_commands",strings ["preflight";"run";"postcheck";"collect";"report";"inspect";"execute";"archive";"stages";"checkpoint-inspect";
          "observation describe";"observation inspect";"observation read-updates";"observation watch";"finalize";"finalization-inspect";"preparation-inspect"];
        "json_lines_commands",strings ["stages";"finalize";"observation watch"];
        "observation_watch",`Assoc ["incremental",`Bool true;"interval_seconds",`Float 0.5;
          "envelopes",strings ["updates";"status"];"records_flushed",`Bool true;
          "reconnect",`String "stream-id_and_after_together";
          "exit_codes",`Assoc ["terminal",`Int 0;"writer_lost_or_unknown",`Int 3;"query_error",`Int 2;"reader_interrupt",`Int 130]];
        "stage_observation_default",`Bool true;"stage_observation_schemas",`Assoc ["write",`Int 2;"read",`List [`Int 1;`Int 2]];
        "producer_event_timestamps",`Bool true;"monotonic_elapsed_seconds",`Bool true;
        "stage_observation_opt_out",`String "--no-observation";"stage_terminal_error_event",`String "observation_terminal";
        "stage_json_records_flushed",`Bool true;"json_flag_placements",strings ["global";"command";"observation-query"];
        "verbose_diagnostics",`String "stderr";"runs_override",`Bool true;"preflight_explicit_output",`String "file-existing-parent";
        "collect_json_writes_results",`Bool true;"collect_stdout",`String "legacy-read-only-json";
        "archive_json_list",`Bool false;"provision_json",`Bool false]]]
let report json =
  let j=describe () in
  if json then print_endline (Yojson.Basic.pretty_to_string j) else (
    let get k=match j with `Assoc xs -> (match List.assoc k xs with `String s -> s | _ -> "") | _ -> assert false in
    Printf.printf "hardcaml-asic-flow %s (hardcaml_asic package version, %s)\n" (get "package_version") (get "package_version_source");
    print_endline "source identity   unstamped; revision unknown, library artifact match unverified (P6.5)";
    print_endline "record schemas    1\nCLI contract      4; human output by default, --json for machine output";
    Printf.printf "modules           %s\nruntime data      %s\n" (get "module_dir") (get "data_dir"))
