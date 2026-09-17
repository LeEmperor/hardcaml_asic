open! Core

module Delay = struct
  type t =
    { port : string
    ; maximum : Time_float.Span.t
    }
  [@@deriving sexp_of]
end

type t =
  { input_delays : Delay.t list
  ; output_delays : Delay.t list
  }
[@@deriving sexp_of]

let empty = { input_delays = []; output_delays = [] }
