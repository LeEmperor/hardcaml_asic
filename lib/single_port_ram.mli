(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "single_port_ram.mli" *)
(* Single-port 1RW synchronous-read RAM, registered as a project resource.

   One shared address, one enable and one write-enable describe either a read or a write
   at each rising edge, never both. Read data lands one cycle after the operation:

   {v
   enable  write_enable  operation                 read data in the following cycle
   0       any           none                      holds its previous value
   1       0             read [address]            the addressed word
   1       1             write [write_data]        unspecified
   v}

   docs/program-memory-contract.md is normative; this interface summarizes it. Do NOT
   infer permitted behavior from the implementation, and do NOT depend on an unspecified
   value: the output after a write, a read of an unwritten word, or anything about an
   address at or above [depth]. There is no reset, no write mask, no simultaneous read and
   write, and no validity tracking; program validity belongs to the consumer.

   Failures happen at two points:
   1. declaration: {!Config.create_exn} raises on an unsupported shape;
   2. construction: {!create} raises on a port width mismatch, an invalid or duplicate
      name, a policy the technology cannot satisfy, or a selected macro in Implementation
      mode.

   The registered request has kind [single_port_ram] and a contract listing [width],
   [depth], [read_latency], [port], [disabled_output] and [write_output] in that order. A
   technology mapping must match it exactly, including field order (see
   {!Technology.exact_mapping}).

   Not yet present: a hard macro backend, which is blocked until a usable CMOS5L SRAM
   macro is established (phase S; contract section 8).
*)

open! Core
open! Hardcaml

(** The compile-time shape of one RAM instance.

    [t] is private, so every shape has passed {!Config.create_exn}. A shape that cannot be
    built is rejected, never rounded to a nearby one. *)
module Config : sig
  type t = private
    { width : int (** Bits per word; also the width of [write_data] and the read data. *)
    ; depth : int (** Number of words; need not be a power of two. *)
    ; read_latency : int (** Cycles from an enabled read to its data; 1 in v0.1. *)
    }
  [@@deriving sexp_of]

  (** [create_exn ~width:8 ~depth:256 ~read_latency:1]

      Raises, naming the offending value, if [width < 1], if [depth < 2], or if
      [read_latency <> 1]. Only the first failing check is reported. Latency is explicit
      so the call site states it and a future backend can offer another value. *)
  val create_exn : width:int -> depth:int -> read_latency:int -> t

  (** Width of the [address] port, [Int.ceil_log2 depth]. When [depth] is not a power of
      two, addresses at or above [depth] fit in the port but are out of contract. *)
  val address_bits : t -> int

  (** Total stored bits, [width * depth]. Meant for comparing candidate shapes, not for a
      design to branch on. *)
  val storage_bits : t -> int
end

(** [create context config ~clock ~enable ~write_enable ~address ~write_data]

    Register and build one RAM in the context's current scope, and return its read data,
    [Config.width] bits wide. All ports are in the [clock] domain.

    The default [name] is ["ram"], so a second unnamed RAM in the same scope is a
    duplicate and raises; give each RAM in a scope a distinct [name].

    What gets built depends on the elaboration mode and the selected implementation:
    - Simulation: a behavioral model, whatever was selected. Memory starts filled with an
      alternating-bit poison pattern, and a write or an out-of-range access outputs poison
      the next cycle. Poison is an ordinary two-state value; reading it does not fail by
      itself, so verify that the consumer never depends on it.
    - Implementation with flops: explicit word registers with no reset and no
      initialization. The selection is recorded even though there is no macro collateral.
    - Implementation with a macro: raises; there is no macro backend yet.

    Raises:
    - with the instance, port and both widths, if [clock], [enable] or [write_enable] is
      not one bit, if [address] is not [Config.address_bits] wide, or if [write_data] is
      not [Config.width] wide; ports are checked before registration, so the RAM never
      enters the inventory;
    - naming the component, if [name] is not a valid identifier (see
      {!Resource_id.create_exn});
    - with the instance and request, if [name] duplicates an instance already registered
      in this scope or the policy cannot be satisfied (see
      {!Elaboration_context.register_exn});
    - with the instance and macro, if a macro is selected in Implementation mode. *)
val create
  :  Elaboration_context.t
  -> ?name:string
  -> Config.t
  -> clock:Signal.t
  -> enable:Signal.t
  -> write_enable:Signal.t
  -> address:Signal.t
  -> write_data:Signal.t
  -> Signal.t
