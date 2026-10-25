open! Core

(** Manual physical intent for the stock CMOS5L SRAM. Coordinates are in micrometres.
    This declaration performs no PDK reads. Hardening requires complete R0 intent
    with one common halo >=2 um, on the 0.005 um manufacturing grid. Actual usable
    core fit, supply access and real-GDS checking are execution obligations. *)
type t = private
  { resource : Resource.Id.t
  ; x_um : float
  ; y_um : float
  ; halo_um : float
  }
[@@deriving sexp_of]

(** R0 placement, with both positive rails explicitly requested on VPWR and VSS!
    on VGND. Hardening emits the versioned Metal4 edge-access and real-GDS checking
    plan. Unsupported geometry fails at execution rather than changing placement.
    Finite coordinates and a finite nonnegative halo are required at construction;
    the stricter hardening requirements are checked at resolution. *)
val tt_cmos5l_r0
  :  resource:Resource.Id.t
  -> x_um:float
  -> y_um:float
  -> ?halo_um:float
  -> unit
  -> t
