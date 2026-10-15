open! Core

(** Pure associations for the named classic v1 provider translation only. Does
    not read files, expand LibreLane expressions, or change legacy bundles. *)
val verify : manifest:Yojson.Safe.t -> configuration:string -> unit Or_error.t
