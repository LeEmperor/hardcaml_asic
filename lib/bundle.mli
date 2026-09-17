open! Core

(** A deterministic Tiny Tapeout / LibreLane project bundle. [input_paths] are
    source files relative to [source_root]. Their exact bytes are copied into
    [inputs/] and included in the manifest, including dirty or untracked files. *)
type t

val render
  :  ?simulation_build:Build.t
  -> source_root:string
  -> input_paths:string list
  -> Resolved_build.t
  -> t Or_error.t

(** Write a bundle to a new or empty directory. Existing files are never
    replaced. This does not invoke any EDA tool or access the PDK. *)
val write : t -> output_dir:string -> unit Or_error.t

val file : t -> string -> string option
val paths : t -> string list
val manifest : t -> Yojson.Safe.t
val identity : t -> string
