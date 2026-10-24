open! Core

type t =
  { resource : Resource.Id.t
  ; x_um : float
  ; y_um : float
  ; halo_um : float
  }
[@@deriving sexp_of]

let tt_cmos5l_r0 ~resource ~x_um ~y_um ?(halo_um = 2.) () =
  if not (Float.is_finite x_um && Float.is_finite y_um
          && Float.is_finite halo_um && Float.(halo_um >= 0.))
  then invalid_arg "macro placement requires finite coordinates and nonnegative halo";
  { resource; x_um; y_um; halo_um }
;;
