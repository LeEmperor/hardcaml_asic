(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "test_selection.ml" *)
(* P0.3: requested contract, technology capability and project policy.

   The technology below is a test input describing a hypothetical exact mapping. It is not
   evidence of any real macro backend. *)

open! Core
open! Hardcaml
open! Hardcaml_asic
open! Expect_test_helpers_core

let fixture_macro : Technology.Macro.t =
  { name = "fixture_macro_8"
  ; collateral =
      [ { role = Simulation_model; reference = "fixture/macro_8.v" }
      ; { role = Black_box; reference = "fixture/macro_8_bb.v" }
      ; { role = Timing_model { corner = "typ" }; reference = "fixture/macro_8.lib" }
      ; { role = Physical_abstract; reference = "fixture/macro_8.lef" }
      ]
  }
;;

let technology_with_width_8_mapping =
  Technology.create_exn
    ~name:"fixture-tech"
    ~resource_mappings:
      [ { request = Fixture.Store.request ~width:8; macro = fixture_macro } ]
;;

let elaborate ?(mode = Elaboration_mode.Implementation) ?design ~technology policy =
  let%bind.Or_error policy in
  let%bind.Or_error project = Fixture.project ?design ~technology ~policy () in
  Project.elaborate project ~mode
;;

let show ?mode ?design ~technology policy =
  match elaborate ?mode ?design ~technology policy with
  | Ok build -> Fixture.print_inventory build
  | Error error -> print_s [%sexp (error : Error.t)]
;;

let rule selector requirement = { Resource_policy.Rule.selector; requirement }
let instance = Resource_policy.Selector.instance_exn
let subtree = Resource_policy.Selector.subtree_exn

let%expect_test "exact mapping is selected and carries its collateral" =
  let build =
    elaborate
      ~technology:technology_with_width_8_mapping
      (Resource_policy.create ~default:Exact [])
    |> ok_exn
  in
  let status = List.last_exn (Build.resources build) in
  print_s [%sexp (status : Resource_record.t)];
  [%expect
    {|
    ((id status)
     (request ((kind fixture_store) (contract ((width 8)))))
     (requirement Exact)
     (policy      Default)
     (selection (
       (implementation (Macro fixture_macro_8))
       (reason (Exact_mapping (technology fixture-tech)))))
     (elaborated_as Selected_implementation)
     (sources (
       (Collateral (
         (role      Simulation_model)
         (reference fixture/macro_8.v)))
       (Collateral (
         (role      Black_box)
         (reference fixture/macro_8_bb.v)))
       (Collateral (
         (role (Timing_model (corner typ))) (reference fixture/macro_8.lib)))
       (Collateral (
         (role      Physical_abstract)
         (reference fixture/macro_8.lef))))))
    |}]
;;

let%expect_test "missing exact mapping fails with the instance and requested contract" =
  show ~technology:Technology.ihp_sg13cmos5l (Resource_policy.create ~default:Exact []);
  [%expect
    {|
    (("design construction failed"
       (project fixture)
       (mode    Implementation))
     (("resource selection failed"
        (instance left/buf)
        (request ((kind fixture_store) (contract ((width 8))))))
      ("technology has no exact implementation for the requested contract, and flop fallback is not permitted"
       (technology ihp-sg13cmos5l))))
    |}]
;;

let%expect_test "a different contract is not matched to a nearby mapping" =
  let technology =
    Technology.create_exn
      ~name:"fixture-tech"
      ~resource_mappings:
        [ { request = Fixture.Store.request ~width:16; macro = fixture_macro } ]
  in
  show ~technology (Resource_policy.create ~default:Exact_or_flop_fallback []);
  [%expect
    {|
    (left/buf Default
     ((implementation Flops)
      (reason (Flop_fallback (no_exact_mapping_in fixture-tech)))))
    (right/buf Default
     ((implementation Flops)
      (reason (Flop_fallback (no_exact_mapping_in fixture-tech)))))
    (status Default
     ((implementation Flops)
      (reason (Flop_fallback (no_exact_mapping_in fixture-tech)))))
    |}]
;;

let%expect_test "explicit flops are distinct from fallback, even with a mapping available"
  =
  show
    ~technology:technology_with_width_8_mapping
    (Resource_policy.create
       ~default:Exact_or_flop_fallback
       [ rule (instance "status") Flops ]);
  [%expect
    {|
    (left/buf Default
     ((implementation (Macro fixture_macro_8))
      (reason (Exact_mapping (technology fixture-tech)))))
    (right/buf Default
     ((implementation (Macro fixture_macro_8))
      (reason (Exact_mapping (technology fixture-tech)))))
    (status (Rule (Instance status))
     ((implementation Flops) (reason Explicit_flops)))
    |}]
;;

let%expect_test "precedence: instance over deeper subtree over shallower subtree" =
  let design = Fixture.design ~within:"core" () in
  (* Listed in the reverse of their precedence: rule order is irrelevant. The default
     cannot be satisfied, so any instance falling through to it would fail. *)
  show
    ~design
    ~technology:technology_with_width_8_mapping
    (Resource_policy.create
       ~default:Exact
       [ rule (subtree "core") Exact_or_flop_fallback
       ; rule (subtree "core/left") Flops
       ; rule (instance "core/right/buf") Flops
       ]);
  [%expect
    {|
    (core/left/buf (Rule (Subtree (core left)))
     ((implementation Flops) (reason Explicit_flops)))
    (core/right/buf (Rule (Instance core/right/buf))
     ((implementation Flops) (reason Explicit_flops)))
    (core/status (Rule (Subtree (core)))
     ((implementation (Macro fixture_macro_8))
      (reason (Exact_mapping (technology fixture-tech)))))
    |}]
;;

let%expect_test "repeated selectors are ambiguous" =
  print_s
    [%sexp
      (Resource_policy.create [ rule (subtree "core") Flops; rule (subtree "core") Exact ]
       : Resource_policy.t Or_error.t)];
  [%expect
    {|
    (Error (
      "ambiguous implementation policy: selector appears in more than one rule"
      (selector (Subtree (core)))))
    |}]
;;

let%expect_test "an instance with no applicable policy fails" =
  show
    ~technology:Technology.ihp_sg13cmos5l
    (Resource_policy.create [ rule (subtree "left") Flops ]);
  [%expect
    {|
    (("design construction failed"
       (project fixture)
       (mode    Implementation))
     (("resource selection failed"
        (instance right/buf)
        (request ((kind fixture_store) (contract ((width 8))))))
      ("no implementation policy applies; add a default or a rule selecting this instance"
       (instance right/buf))))
    |}]
;;

let%expect_test "a rule matching no registered resource fails finalization" =
  show
    ~technology:Technology.ihp_sg13cmos5l
    (Resource_policy.create ~default:Flops [ rule (instance "left/bfu") Exact ]);
  [%expect
    {|
    (("elaboration validation failed"
       (project fixture)
       (mode    Implementation))
     ("implementation policy rules match no registered resource"
      (unmatched_rules (((selector (Instance left/bfu)) (requirement Exact))))
      (registered (left/buf right/buf status))))
    |}]
;;

let%expect_test "simulation elaboration still applies policy" =
  show
    ~mode:Simulation
    ~technology:Technology.ihp_sg13cmos5l
    (Resource_policy.create ~default:Exact []);
  [%expect
    {|
    (("design construction failed"
       (project fixture)
       (mode    Simulation))
     (("resource selection failed"
        (instance left/buf)
        (request ((kind fixture_store) (contract ((width 8))))))
      ("technology has no exact implementation for the requested contract, and flop fallback is not permitted"
       (technology ihp-sg13cmos5l))))
    |}];
  let build =
    elaborate
      ~mode:Simulation
      ~technology:technology_with_width_8_mapping
      (Resource_policy.create ~default:Exact [])
    |> ok_exn
  in
  let status = List.last_exn (Build.resources build) in
  print_s
    [%message
      ""
        ~selection:(status.selection : Selection.t)
        ~elaborated_as:(status.elaborated_as : Resource_record.Elaborated_as.t)
        ~sources:(status.sources : Resource_record.Source.t list)];
  [%expect
    {|
    ((selection (
       (implementation (Macro fixture_macro_8))
       (reason (Exact_mapping (technology fixture-tech)))))
     (elaborated_as Behavioral_model)
     (sources (Generated_behavioral_model)))
    |}]
;;

let%expect_test "malformed technology capability and selectors are rejected" =
  require_does_raise (fun () ->
    Technology.create_exn
      ~name:"fixture-tech"
      ~resource_mappings:
        [ { request = Fixture.Store.request ~width:8; macro = fixture_macro }
        ; { request = Fixture.Store.request ~width:8
          ; macro = { fixture_macro with name = "other" }
          }
        ]);
  require_does_raise (fun () -> subtree "core//left");
  require_does_raise (fun () -> instance "core/left/");
  [%expect
    {|
    ("ambiguous technology capability: more than one mapping for a request"
     (technology fixture-tech)
     (request ((kind fixture_store) (contract ((width 8))))))
    ("subtree selector must be a nonempty '/'-separated scope path"
     (selector core//left))
    ("resource identity components must be identifiers"
     (component "")
     (path (core left))
     (name ""))
    |}]
;;
