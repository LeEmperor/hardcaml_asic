open! Core

(** Manual physical intent for the stock CMOS5L SRAM. Coordinates are in micrometres.
    This declaration performs no PDK reads. The initial execution capability is
    synthesis only: declaring intent does not authorize physical implementation. *)
type t = private
  { resource : Resource.Id.t
  ; x_um : float
  ; y_um : float
  ; halo_um : float
  }
[@@deriving sexp_of]

(** R0 placement, with both positive rails explicitly requested on VPWR and VSS!
    on VGND. The physical power strategy and real-GDS KLayout/CDL checks must be
    verified before hardening is supported; resolution currently rejects it.
    Finite coordinates and a finite nonnegative halo are required. *)
val tt_cmos5l_r0
  :  resource:Resource.Id.t
  -> x_um:float
  -> y_um:float
  -> ?halo_um:float
  -> unit
  -> t
