(** Strict backend adapter wire version 1. Legacy unversioned bridge requests
    are not executable through this API. State/configuration contents remain
    opaque files, including native state containing Infinity.

    A successful reply describes candidate evidence, never checkpoint readiness
    or acceptance. The caller must additionally require successful process exit,
    verify artifact bytes and perform provider publication validation. Nonzero
    exits/signals/interruption take precedence over any reply; missing replies
    are not synthesized into completed responses. This module performs no IO. *)
module Stage = Hardcaml_asic.Flow.Stage

val version : int
type operation = Execute_segment | Validate_publication
type request = private
  { operation : operation
  ; request_id : string
  ; reply_path : string
  ; boundary : Stage.t
  ; checkpoint : string option
  ; source_boundary : Stage.t option
  ; candidate : string
  ; project : string
  ; pdk_root : string
  ; tag : string
  ; bridge_sha256 : string
  }

val make_request
  :  operation:operation
  -> request_id:string
  -> reply_path:string
  -> boundary:Stage.t
  -> checkpoint:string option
  -> source_boundary:Stage.t option
  -> candidate:string
  -> project:string
  -> pdk_root:string
  -> tag:string
  -> bridge_sha256:string
  -> (request, string) result

val request_of_json : Identity_json.t -> (request, string) result
val parse_request : string -> (request, string) result
val request_to_json : request -> Identity_json.t
val request_identity : request -> string

type outcome = Completed | Validated | Failed of string
(** Byte counts are arbitrary precision nonnegative decimal integers. *)
type artifact = private
  { path : string; sha256 : string; bytes : string }
type reply = private
  { request : request; outcome : outcome; artifacts : (string * artifact) list }

(** Closed schema and full request correlation, including canonical request
    SHA-256, source/input paths via that hash, and operation-specific evidence.
    Failed replies must have a nonempty error and no artifacts. *)
val reply_of_json : request:request -> Identity_json.t -> (reply, string) result
val parse_reply : request:request -> string -> (reply, string) result
val reply_to_json : reply -> Identity_json.t
