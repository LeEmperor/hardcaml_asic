(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "fixture.ml" *)
(* A small lifecycle fixture: a test-only registered resource inside a two-level design.

   [Store] exercises registration and selection only. It is always a register, whatever is
   selected, and its technology mappings are test inputs, not evidence of any backend. *)

open! Core
open! Hardcaml
open! Hardcaml_asic

module Store = struct
  let request ~width =
    Resource_request.create_exn ~kind:"fixture_store" ~contract:[%sexp { width : int }]
  ;;

  let create context ~name ~clock d =
    let (_ : Resource_record.t) =
      Elaboration_context.register_exn context ~name (request ~width:(Signal.width d))
    in
    Signal.reg (Signal.Reg_spec.create ~clock ()) d
  ;;
end

module I = struct
  type 'a t =
    { clock : 'a
    ; d : 'a [@bits 8]
    }
  [@@deriving hardcaml]
end

module Half = struct
  module O = struct
    type 'a t = { q : 'a [@bits 8] } [@@deriving hardcaml]
  end

  let create context scope (i : _ I.t) =
    let context = Elaboration_context.in_scope context scope in
    { O.q = Store.create context ~name:"buf" ~clock:i.clock i.d }
  ;;

  let hierarchical context ~instance i =
    let module H = Hierarchy.In_scope (I) (O) in
    H.hierarchical
      ~scope:(Elaboration_context.scope context)
      ~name:"half"
      ~instance
      (create context)
      i
  ;;
end

module O = struct
  type 'a t =
    { left : 'a [@bits 8]
    ; right : 'a [@bits 8]
    ; status : 'a [@bits 8]
    }
  [@@deriving hardcaml]
end

(* [order] changes registration order without changing the design. [within] places the
   whole body one level down in a named instance. [before] and [after] let tests capture
   the context or fail part-way through construction. *)
let design ?(order = `Forward) ?within ?(before = ignore) ?(after = ignore) ()
  : (module Project.Design)
  =
  (module struct
    module I = I
    module O = O

    let name = "fixture_top"

    let body context (i : _ I.t) =
      let left () = (Half.hierarchical context ~instance:"left" i).q in
      let right () = (Half.hierarchical context ~instance:"right" i).q in
      let status () = Store.create context ~name:"status" ~clock:i.clock i.d in
      let o =
        match order with
        | `Forward ->
          let left = left () in
          let right = right () in
          let status = status () in
          { O.left; right; status }
        | `Reverse ->
          let status = status () in
          let right = right () in
          let left = left () in
          { O.left; right; status }
      in
      o
    ;;

    let create context (i : _ I.t) =
      before context;
      let o =
        match within with
        | None -> body context i
        | Some instance ->
          let module H = Hierarchy.In_scope (I) (O) in
          H.hierarchical
            ~scope:(Elaboration_context.scope context)
            ~name:"wrapper"
            ~instance
            (fun scope -> body (Elaboration_context.in_scope context scope))
            i
      in
      after context;
      o
    ;;
  end)
;;

let flops_everywhere = Resource_policy.create ~default:Flops [] |> ok_exn

let project
  ?(design = design ())
  ?(technology = Technology.ihp_sg13cmos5l)
  ?(policy = flops_everywhere)
  ?(flow = Flow.librelane Hardening)
  ()
  =
  Project.create
    ~name:"fixture"
    ~metadata:
      { title = "Lifecycle fixture"
      ; author = "hardcaml_asic"
      ; description = "Exercises declaration, registration and finalization"
      }
    ~design
    ~target:{ harness = Tiny_tapeout { tiles = T1x1 }; technology }
    ~flow
    ~clocks:[ { port = "clock"; period = Time_ns.Span.of_int_ns 20 } ]
    ~policy
    ()
;;

let print_inventory build =
  List.iter (Build.resources build) ~f:(fun (r : Resource_record.t) ->
    print_s
      [%message
        ""
          ~_:(r.id : Resource_id.t)
          ~_:(r.policy : Resource_policy.Applied.t)
          ~_:(r.selection : Selection.t)])
;;
