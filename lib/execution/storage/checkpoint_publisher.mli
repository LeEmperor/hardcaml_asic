module Stage = Hardcaml_asic.Flow.Stage
type runtime_outcome = Validated | Failed of string | Interrupted of int
type runtime_request = private
  { staging : string; location : string; boundary : Stage.t; compatibility : Identity_json.t }
type publication = private
  { path : string; checkpoint : Checkpoint.t; runtime_validation : [ `Not_required | `Validated ] }

(** Existing Python publication-reference format; runtime-validation outcome is
    separately explicit in the typed record, not added to persisted schemas. *)
val to_json : publication -> Identity_json.t
type error =
  | Publication_failed of string
  | Runtime_failed of string
  | Runtime_interrupted of int
  | Cleanup_failed of error * string
(** If both an exception and owned cleanup fail, preserves both; otherwise the
    original exception and backtrace propagate. *)
exception Cleanup_error of exn * string
val error_message : error -> string

(** Publish a candidate into an existing caller-owned store, using the unchanged
    schema-2 manifest. Only [Ok] after atomic no-replace promotion is ready.

    REQUIRED CALLER EVIDENCE: the remembered execute request for this candidate,
    successful actual supervised process/cleanup outcome, a strictly correlated
    protocol-v1 completed reply and reverified artifact bytes, and rechecked
    transported bridge/support digests. Candidate files must still match that
    evidence when calling. This function does not authenticate execution. It
    independently checks outer completed status/boundary/bridge, native views,
    public metrics, closure, inventory, compatibility and exact tested image.
    Candidate must be unpublished backend output, with no manifest.json entry;
    historical checkpoints (including schema 1) are not restart/publication inputs.

    If image-only /nix/store/ closure exists, [validate_runtime] is mandatory. It
    must use the selected exact-image transport, a fresh validate_publication
    request, successful supervised process/cleanup outcome, correlated validated
    reply and matching artifact evidence. Return [Validated] only on all of those;
    return failures/interruption explicitly. No readiness may be reported by the
    callback. It must not mutate staging. Host validation and source checks repeat
    after it. Callback exceptions propagate unchanged, after owned cleanup.

    View copies are streaming and checked before/after against source/destination
    hashes and stat identities. All candidate metadata is similarly checked.
    Files become 0444 and directories 0555 before Linux renameat2(RENAME_NOREPLACE).
    Unsupported atomic no-replace fails closed; there is no racy rename fallback.
    Ordinary failures remove only this invocation's private staging. Exceptions
    (including caller interruption) propagate after cleanup; SIGKILL may leave
    private staging. No signal handlers, fsync or crash durability promise.
    Parent directories must remain stable and trusted; this is not a hostile
    filesystem sandbox. Readonly permissions do not constrain the file owner.

    [name] supplies a NUL-free single-component unique suffix (default random).
    It supports deterministic collision checks; existing destinations are never
    adopted, overwritten or cleaned, including empty directories and symlinks. *)
val publish : ?name:(unit -> string)
  -> ?validate_runtime:(runtime_request -> runtime_outcome)
  -> candidate:string -> store:string -> compatibility:Identity_json.t
  -> boundary:Stage.t -> unit -> (publication, error) result
