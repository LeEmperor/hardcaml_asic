(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "bundle.mli" *)
(* A deterministic Tiny Tapeout / LibreLane project bundle.

   A bundle is every file the flow needs for one design, plus a manifest recording where
   each byte came from. It is built in memory by {!render} and put on disk by {!write}:

   {v
   Resolved_build.t (+ optional Simulation Build.t)
     -> render     RTL, config, SDC and info.yaml generated; source inputs read and
                   hashed; manifest and identity computed; nothing written
     -> write      files created under a new or empty directory
   v}

   Guarantees:
   1. the same resolved build, simulation build, inputs and git state always render to the
      same bytes and the same {!identity};
   2. the identity changes when any emitted file, declared input, input git status or
      source revision changes;
   3. every declared input's exact bytes are copied under [inputs/], including dirty and
      untracked files, so the source that produced a bundle is retrievable from it;
   4. synthesis and simulation RTL sit in separate directories and are listed separately
      in the manifest; they are never meant to be compiled together.

   It does NOT validate the design or target; {!Resolved_build.resolve} already did. It
   does NOT invoke any EDA tool, access the PDK, or link the TT support-tools checkout
   expected at [OUTPUT/tt]; running the flow is P4 work. Layout and manifest fields are
   described in docs/bundle-emission.md.
*)

open! Core

(** Abstract; the only way to get one is {!render}, so the files, manifest and identity
    always agree. *)
type t

(** [render ~simulation_build ~source_root:"." ~input_paths:[ "lib/dune" ] resolved]

    [input_paths] are source files relative to [source_root], which must be inside a git
    checkout with at least one commit. Their order and repeats do not matter. Without
    [simulation_build], simulation consumers are pointed at the synthesis RTL.

    Returns an error, and writes nothing, if [simulation_build] is not a Simulation build
    of the same project and top module, if [input_paths] is empty, if any input path is
    absolute or contains an empty, ["."] or [".."] component, if any input is missing, a
    directory, or resolves outside [source_root], or if git fails. *)
val render
  :  ?simulation_build:Build.t
  -> source_root:string
  -> input_paths:string list
  -> Resolved_build.t
  -> t Or_error.t

(** Write a bundle under [output_dir], creating it and its parents when missing. Does not
    invoke any EDA tool or access the PDK.

    Returns an error if [output_dir] exists and is not a directory, or is not empty; so an
    existing file is never replaced. Writing is not atomic: a failure partway leaves a
    partial, non-empty directory that must be deleted before writing there again. *)
val write : t -> output_dir:string -> unit Or_error.t

(** [file t "src/config.json"]; the contents at a bundle relative path, if emitted. *)
val file : t -> string -> string option

(** Every bundle relative path, sorted, except ["manifest.json"], which is always last. *)
val paths : t -> string list

(** The manifest, including its [identity] field; the same value [manifest.json] holds. *)
val manifest : t -> Yojson.Safe.t

(** Lowercase hex SHA-256 of the manifest without its [identity] field. *)
val identity : t -> string
