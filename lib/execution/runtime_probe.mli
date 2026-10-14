(** Actual bounded probes, supervised by OCaml. Only import-dependent metadata is
    an external, version-1 Python payload. All stdout/stderr/argv are retained in
    the caller-owned evidence directory. No policy, staging or Python runner call. *)
type t
val create : directory:string -> environment:string list -> timeout:float -> t
val command : t -> prog:string -> arguments:string list -> string
val observe : t -> python:string -> docker:string -> payload:string
  -> pdk_root:string -> Runtime_contract.t
  -> Identity_json.t * Identity_json.t * Execution_transport.binding
val verify : t -> Execution_transport.binding -> (unit, string) result
(** Reprobe the bound engine and local image ID, never resolve a tag again. *)

val find_executable : environment:string list -> string -> string
