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
  (** Exact raw identities of metadata actually consumed by [run], including
      stored results when present. Not a digest of only normalized results. *)
  metadata_sources : Evidence_json.t list;
}

(** Prefer stored results.json; otherwise collect in memory, without publishing.
     Metadata reads are bounded/nonblocking, descriptor-bound regular reads with
     no symlink traversal. [render_human=false] skips unused supplementary human
     report reads. [strict_sources=true] rejects corrupt stored resource assertions
     before fresh reconciliation; genuine recorded failed evidence stays readable.
     Defaults retain historical report verdict/rendering behavior. *)
val run : ?context:Evidence_json.t -> ?synthesis_state:string -> ?render_human:bool -> ?strict_sources:bool -> string -> result
