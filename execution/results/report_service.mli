(** Read-only acceptance of our normalized evidence, not a tool/STA implementation.
    Evidence (including unknown and nonfinite raw fields) uses [Evidence_json].
    Malformed service inputs/IO raise [Invalid_argument], [Sys_error] or Unix errors. *)
type scope = Synthesis | Full | Invalid
type verdict = private { scope : scope; problems : string list }
val evaluate : context:Evidence_json.t -> Evidence_json.t -> verdict
val accepted : verdict -> bool
val exit_code : verdict -> int
val number : ?digits:int -> Evidence_json.t -> string

(** Supplementary CSV, Markdown, resizer and SDC displays never alter the verdict.
    Rendering may fail on unreadable supplementary evidence. *)
val render : run_dir:string -> context:Evidence_json.t -> results:Evidence_json.t ->
  source:string -> verdict -> string
type result = private {
  results : Evidence_json.t;
  source : string;
  verdict : verdict;
  human : string;
}

(** Prefer stored results.json; otherwise collect in memory, without publishing.
    Optional context/state support the next native finalization service. *)
val run : ?context:Evidence_json.t -> ?synthesis_state:string -> string -> result
