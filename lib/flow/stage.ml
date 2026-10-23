open! Core

type t = Hardcaml_asic_flow_domain.Stage_id.t =
  | Synthesis
  | Floorplan
  | Placement
  | Cts
  | Routing
  | Timing
  | Signoff
[@@deriving compare, equal, sexp_of]

let all = Hardcaml_asic_flow_domain.Stage_id.all
let to_string = Hardcaml_asic_flow_domain.Stage_id.to_string
let of_string = Hardcaml_asic_flow_domain.Stage_id.of_string

module Closure_scope = struct
  type t = Path_bound [@@deriving equal, sexp_of]
end

module Acceptance = struct
  type t = Not_evaluated [@@deriving equal, sexp_of]
end

type capability =
  { endpoint : string
  ; successor : string option
  ; restart_targets : t list
  ; tested_image_id : string
  ; closure_scope : Closure_scope.t
  ; acceptance : Acceptance.t
  }
[@@deriving sexp_of]

let capability stage =
  let module D = Hardcaml_asic_flow_domain in
  let endpoint = D.Backends.Librelane.Mapping.endpoint stage in
  let successor = D.Backends.Librelane.Mapping.successor stage in
  let restart_targets = D.Registry.restart_targets stage in
  { endpoint
  ; successor
  ; restart_targets
  ; tested_image_id = D.Backends.Librelane.Mapping.tested_image_id
  ; closure_scope = Path_bound
  ; acceptance = Not_evaluated
  }
;;
