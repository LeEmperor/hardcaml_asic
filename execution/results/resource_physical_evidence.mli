(** Retained physical measurements. All I/O goes through the caller's contained,
    bounded reader, which owns source identities and archive closure. *)
type reader =
  { read : string -> string -> string * Evidence_json.t
  ; exists : string -> bool
  }

val collect
  :  reader:reader
  -> flow:string
  -> snapshot:bool
  -> manifest:Evidence_json.t
  -> resources:Evidence_json.t list
  -> instances:(string * string) list option
  -> checks:Evidence_json.t option
  -> checker_ref:Evidence_json.t
  -> final_netlist:Evidence_json.t
  -> Evidence_json.t * (string * Evidence_json.t) list

(** Strict shape, numeric, reference and arithmetic consistency checks. Source
    replay remains necessary to establish agreement with retained source bytes. *)
val validate : refs:Evidence_json.t list -> Evidence_json.t -> unit
val validate_geometry : refs:Evidence_json.t list -> Evidence_json.t -> unit
