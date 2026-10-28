open! Core

(** Project timing intent. Construction is pure; resolution validates against the
    actual elaborated circuit. No declaration inserts hardware. *)
module Delay : sig
  type t = { port : string; minimum : Time_float.Span.t; maximum : Time_float.Span.t }
  [@@deriving sexp_of]
end

module Port : sig
  type direction = Input | Output [@@deriving sexp_of, equal]
  type t = private { direction : direction; port : string; bit : int option }
  [@@deriving sexp_of, equal]
  val input : string -> t
  val output : string -> t
  (** Select exactly one bit, never a pattern. Selection of a scalar or an invalid
      index is rejected at resolution; repeated selection raises immediately. *)
  val bit : t -> int -> t
end

module Stage : sig
  type t = private { id : string; chain : string; index : int }
  [@@deriving sexp_of, equal]
  val create : id:string -> chain:string -> index:int -> t
  val anchor : t -> string
end

module Exception : sig
  type kind = Async_capture | Async_reset [@@deriving sexp_of, equal]
  type t = private
    { id : string; reason : string; kind : kind; source : Port.t; targets : Stage.t list }
  [@@deriving sexp_of]
  val async_capture : id:string -> reason:string -> source:Port.t -> first_stage:Stage.t -> t
  (** Enumerate asynchronous controls only, including later stages if the circuit
      resets them asynchronously. The supported mapped RESET_B subset requires
      externally active-low, reset-to-zero controls. Interstage data paths remain
      timed. Unsupported polarity is rejected rather than guessed after mapping. *)
  val async_reset : id:string -> reason:string -> source:Port.t -> targets:Stage.t list -> t
  val kind_string : kind -> string
end

type t =
  { input_delays : Delay.t list
  ; output_delays : Delay.t list
  ; stages : Stage.t list
  ; exceptions : Exception.t list
  }
[@@deriving sexp_of]

val create : ?input_delays:Delay.t list -> ?output_delays:Delay.t list
  -> ?stages:Stage.t list -> ?exceptions:Exception.t list -> unit -> t
val empty : t
