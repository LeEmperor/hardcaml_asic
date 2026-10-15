open! Core

(** Pure strict version-1 catalog wires. No elaboration, Git or tools. Every reader
    constructs checked domain values; snapshots re-resolve and verify selected definitions
    and complete winner/history evidence. *)
val declaration_to_yojson : Flow.Catalog.t -> Yojson.Safe.t

val declaration_of_yojson : Yojson.Safe.t -> Flow.Catalog.t Or_error.t
val declaration_of_string : string -> Flow.Catalog.t Or_error.t
val list_to_yojson : Flow.Catalog.t -> Yojson.Safe.t
val list_of_yojson : Yojson.Safe.t -> Flow.Catalog.t Or_error.t
val describe_to_yojson : Flow.Catalog.Entry.t -> Yojson.Safe.t
val describe_of_yojson : Yojson.Safe.t -> Flow.Catalog.Entry.t Or_error.t
val selection_to_yojson : Flow.Selection.t -> Yojson.Safe.t
val selection_of_yojson : Yojson.Safe.t -> Flow.Selection.t Or_error.t
val descriptors : Yojson.Safe.t
val capabilities : Yojson.Safe.t
val resolved_to_yojson : Flow.Catalog.resolved -> Yojson.Safe.t
val resolved_of_yojson : Yojson.Safe.t -> Flow.Catalog.resolved Or_error.t
val assignment_to_yojson : Flow.Parameter.assignment -> Yojson.Safe.t
val assignment_of_yojson : Yojson.Safe.t -> Flow.Parameter.assignment Or_error.t
