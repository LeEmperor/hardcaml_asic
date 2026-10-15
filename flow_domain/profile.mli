open! Core
type t
(** Checks ID, nonblank display label and duplicate assignments. The owning
    entry additionally checks the methodology's configurable set. Descriptions
    may be empty; labels and descriptions are retained verbatim. *)
val create
  :  id:string
  -> label:string
  -> description:string
  -> assignments:Parameter.assignment list
  -> t Or_error.t
val id : t -> Selection.Id.t
val label : t -> string
val description : t -> string
val assignments : t -> Parameter.assignment list
