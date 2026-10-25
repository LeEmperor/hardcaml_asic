open! Core

(** Observations of declared working-tree files, not compiled-source proof or a
    P6 source-artifact stamp. No PDK/EDA discovery. Absolute roots are excluded. *)
type t
val observe : source_root:string -> input_paths:string list -> t Or_error.t
val identity : t -> string
val to_json : t -> Yojson.Safe.t
val of_json : Yojson.Safe.t -> t Or_error.t
