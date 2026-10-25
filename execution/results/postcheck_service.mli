(** External TT precheck and exact-image Icarus replay. No acceptance or journal.
    Main-thread synchronous scope; owns SIGINT/SIGTERM and restricts inherited
    Linux CPU affinity to at most 20 CPUs. Launches are sequential. Tool timeout
     defaults to none (1800 seconds per tool for the stock physical profile);
     that profile restricts affinity/containers/tools to six workers.
     Cleanup has a separate five-second budget. *)
type outcome = private
  { check_id : string; check_dir : string; check_record : string
  ; status : string; exit_code : int }
val outcome_json : outcome -> Identity_json.t
val run : run_dir:string -> support_tools:string -> pdk_root:string
  -> precheck_python:string -> testbench:string -> testbench_top:string
  -> environment:string list -> ?context:Evidence_json.t -> ?replay_trace:string
   -> ?timeout:float -> ?resources:string -> unit -> outcome
