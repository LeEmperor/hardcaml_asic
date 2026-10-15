open! Core

module Entry : sig
  type t
  (** Checks duplicate profiles, dangling default and every profile against the
      methodology's configurable parameter set. *)
  val create
    :  methodology:Methodology.t
    -> profiles:Profile.t list
    -> default_profile:string
    -> t Or_error.t
  val methodology : t -> Methodology.t
  val profiles : t -> Profile.t list
  val default_profile : t -> Selection.Id.t
end

type t
(** Explicit catalog default may differ from the flow's own default profile.
    Lists returned by the catalog are ordered by stable ID, never display label. *)
val create
  :  entries:Entry.t list
  -> default_flow:string
  -> default_profile:string
  -> t Or_error.t
val entries : t -> Entry.t list
val default : t -> Selection.t

type resolved
(** Selection, endpoint and all three assignment layers are checked before a
    resolved snapshot is returned. No project overrides are merged here. *)
val resolve
  :  ?selection:Selection.t
  -> ?request:Parameter.assignment list
  -> t
  -> endpoint:Stage_id.t
  -> unit
  -> resolved Or_error.t
val entry : resolved -> Entry.t
val profile : resolved -> Profile.t
val endpoint : resolved -> Stage_id.t
val stages : resolved -> Stage_id.t list
val parameters : resolved -> Parameter.resolved list
(** Complete immutable declaration snapshot, including both kinds of defaults,
    suitable for the next slice's serialization. *)
val declaration : resolved -> t
