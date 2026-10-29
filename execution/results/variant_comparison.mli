(** Bounded, host-only comparison of exactly two explicit retained targets. No
    execution, publication, rendering or current catalog/PDK discovery. Unknown
    required controls withhold deltas; the intended axis never establishes cause.
    Whole response <=1MiB, without pagination or silent truncation. *)
type target = Bundle of string | Coarse_run of string | Execution of string
type axis = Hardware | Resource_policy | Flow_configuration | Descriptive
val inspect : left:target -> right:target -> axis:axis -> unit -> (Evidence_json.t, string) result

(** CLI codecs, rejecting unknown spellings and empty paths. *)
val target : kind:string -> path:string -> (target, string) result
val axis : string -> (axis, string) result

(** Pure registry-policy seam. Inputs are already verified measurement projections;
    this function does not grant source authority. Used by focused scope/arithmetic
    tests. Production [inspect] supplies projections only from retained readers. *)
val compare_metric : axis:axis -> left:Evidence_json.t -> right:Evidence_json.t -> Evidence_json.t
