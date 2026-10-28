(** Structured extension of [Inspection_service.timing_records]. Summary grammar
    and one-based spans are shared with that legacy public parser. Only the native
    Fanout/Cap/Slew/Delay/Time fixed-width table is supported. *)
type role = Data | Launch_clock | Capture_clock
type point = {
  line : int;
  name : string;
  instance : string option;
  pin : string option;
  master : string option;
  role : role;
  edge : string;
  fanout : int option;
  capacitance : float option;
  slew : float;
  delay : float;
  arrival : float;
}
type path = {
  first_line : int;
  last_line : int;
  fields : (string * string) list;
  points : point list;
  data_start : point;
  data_end : point;
}
val parse : ?max_paths:int -> ?max_points:int -> string -> path list * string list

(** Query-wide budget seam. Attempted points in rejected paths consume the same
    budget as accepted points. A reached limit must stop subsequent report reads.
    [no_paths] is an explicitly recognized native (corner, min|max) empty report. *)
type parsed = {
  paths : path list;
  diagnostics : string list;
  consumed_points : int;
  point_limit_reached : bool;
  no_paths : (string * string) option;
}
val parse_with_usage : ?max_paths:int -> ?max_points:int -> string -> parsed
