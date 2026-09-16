(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "single_port_ram.ml" *)
(* Single-port (1RW) synchronous-read RAM.

   v0.1 status: {!Config} is implemented and enforced. {!create} is NOT implemented. The
   interface and the normative contract in docs/program-memory-contract.md are settled
   first so that the behavioural model, the flop fallback, and any technology macro are
   all written against one written-down specification rather than against each other.
*)

open! Core
open! Hardcaml

module Config = struct
  type t =
    { width : int
    ; depth : int
    ; read_latency : int
    }
  [@@deriving sexp_of]

  let address_bits t = Int.ceil_log2 t.depth
  let storage_bits t = t.width * t.depth

  let create_exn ~width ~depth ~read_latency =
    if width < 1 then raise_s [%message "[width] must be at least 1" (width : int)];
    (* depth = 1 would give a zero-width address port, which is not a memory. *)
    if depth < 2 then raise_s [%message "[depth] must be at least 2" (depth : int)];
    if read_latency <> 1
    then
      raise_s
        [%message
          "v0.1 implements [read_latency = 1] only; see docs/program-memory-contract.md"
            (read_latency : int)];
    { width; depth; read_latency }
  ;;
end

let create
  ?name:_
  (_ : Config.t)
  ~clock:_
  ~enable:_
  ~write_enable:_
  ~address:_
  ~write_data:_
  =
  failwith
    "Single_port_ram.create is unimplemented in v0.1. The contract it must satisfy is in \
     docs/program-memory-contract.md."
;;
