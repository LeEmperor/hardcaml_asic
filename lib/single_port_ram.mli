(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "single_port_ram.mli" *)
(* Single-port (1RW) synchronous-read RAM. The first concrete memory primitive in
   hardcaml_asic.

   One address bus, one enable, one write-enable. A cycle is either a read or a write,
   never both, so this primitive cannot express a simultaneous read and write and does not
   need a read-during-write policy. That restriction is deliberate: it is the cheapest and
   most widely available compiled-macro shape, and it is exactly what the protocol
   emulator's program memory needs.

   The full cycle-by-cycle contract, including the reasoning behind every decision and the
   behaviours that are deliberately NOT promised, lives in
   [docs/program-memory-contract.md]. That document is normative; this interface is a
   summary of it. Do not infer permitted behaviour from the implementation.

   Current status: Config validation is implemented; create remains unimplemented. The
   contract describes the planned context-taking API for project registration; the
   signature below has not yet migrated to that API.
*)

open! Core
open! Hardcaml

(** Compile-time shape of one memory instance.

    [t] is [private] so that every instance passes {!Config.create_exn}. A backend may
    refuse a shape it cannot build, but it may never silently substitute a different one. *)
module Config : sig
  type t = private
    { width : int (** Bits per word. *)
    ; depth : int (** Words. Not required to be a power of two. *)
    ; read_latency : int (** Cycles from address to data. v0.1 requires exactly 1. *)
    }
  [@@deriving sexp_of]

  (** Raises if [width < 1], [depth < 2], or [read_latency <> 1].

      [read_latency] is a parameter rather than a constant because the concept note calls
      for latency to be explicit at the call site, and because a future backend may offer
      a registered-output macro at latency 2. v0.1 implements only latency 1 and rejects
      anything else rather than quietly rounding. *)
  val create_exn : width:int -> depth:int -> read_latency:int -> t

  (** Width of the [address] port: [Int.ceil_log2 depth]. Addresses at or above [depth]
      are out of contract; see the normative document. *)
  val address_bits : t -> int

  (** [width * depth]. Provided for the area sweep in the emulator's construction plan
      (128 vs 256 program words), not for the design itself to branch on. *)
  val storage_bits : t -> int
end

(** Instantiate one memory.

    All ports are in the [clock] domain. There is no reset port: memory contents are not
    resettable, by contract.

    Returns the read-data signal, [Config.width] bits wide.

    Port semantics, with [Config.read_latency = 1] — the value returned in cycle [n]
    reflects the operation presented in cycle [n - 1]:

    - [enable = 0]: no access. Read data {b holds} its previous value.
    - [enable = 1], [write_enable = 0]: read. [mem.(address)] appears next cycle.
    - [enable = 1], [write_enable = 1]: write [write_data] to [address]. Read data next
      cycle is {b unspecified}; the planned simulation model drives a poison pattern to
      help expose accidental dependencies. Poison is an ordinary bit pattern and does not
      guarantee a failure; consumer verification must check valid use.

    [address] must be [Config.address_bits] wide and [write_data] must be [Config.width]
    wide; [enable] and [write_enable] must be one bit. Mismatches raise at elaboration.

    [name] is an optional instance name used for waveform naming now and for the macro
    instance name once a technology backend exists. Supply one per instance when a design
    holds more than one memory. *)
val create
  :  ?name:string
  -> Config.t
  -> clock:Signal.t
  -> enable:Signal.t
  -> write_enable:Signal.t
  -> address:Signal.t
  -> write_data:Signal.t
  -> Signal.t
