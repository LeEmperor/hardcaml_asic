(** Domain operations are descriptions of the trusted coarse composition, not
    executable arbitrary recipes. Backend artifact/config contracts live in
    [Backends.Librelane.Mapping]. Analysis can update reports/metrics and derived
    views; [Analyze] does not promise byte-identical native state. *)
type effect = Transform | Analyze | Check
type t = private
  { key : string
  ; description : string
  ; effect : effect
  ; precondition : string
  ; postcondition : string
  }
val make : string -> effect -> string -> string -> string -> t
