open! Core
open! Hardcaml
open! Hardcaml_asic

let macro_name = "RM_IHPSG13_1P_256x16_c2_bm_bist"
let require label condition = if not condition then failwith label

module I = struct
  type 'a t =
    { clock : 'a
    ; enable : 'a
    ; write_enable : 'a
    ; address : 'a [@bits 8]
    ; write_data : 'a [@bits 16]
    }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t = { read_data : 'a [@bits 16] } [@@deriving hardcaml]
end

let config = Single_port_ram.Config.create_exn ~width:16 ~depth:256 ~read_latency:1

let design ?(two = false) ?(config = config) () : (module Project.Design) =
  (module struct
    module I = I
    module O = O

    let name = "sram_backend_top"

    let create context (i : _ I.t) =
      let ram context name =
        Single_port_ram.create context ~name config
          ~clock:i.clock ~enable:i.enable ~write_enable:i.write_enable
          ~address:i.address ~write_data:i.write_data
      in
      let read_data = ram context "program" in
      let read_data =
        if two then (
          let scope = Scope.sub_scope (Elaboration.Context.scope context) "core" in
          let other = ram (Elaboration.Context.in_scope context scope) "program" in
          Signal.(read_data ^: other))
        else read_data
      in
      { O.read_data }
    ;;
  end)
;;

let project ?(technology = Technology.ihp_sg13cmos5l) ?(two = false) ?config requirement =
  Project.create ~name:"sram_backend_fixture"
    ~metadata:{ title = "SRAM backend"; author = "test"; description = "Exact backend regression" }
    ~design:(design ~two ?config ())
    ~target:{ harness = Tiny_tapeout { tiles = T6x4 }; technology }
    ~flow:(Flow.librelane Hardening)
    ~policy:(Resource_policy.create ~default:requirement [] |> Or_error.ok_exn) ()
  |> Or_error.ok_exn
;;

let elaborate ?technology ?two requirement mode =
  Project.elaborate (project ?technology ?two requirement) ~mode |> Or_error.ok_exn
;;

let render elaborated =
  Rtl.create Verilog [ Elaborated_project.circuit elaborated ]
  |> Rtl.full_hierarchy |> Rope.to_string
;;

let check () =
  let request = Resource.Request.single_port_ram ~width:16 ~depth:256 ~read_latency:1 in
  require "canonical contract"
    (Sexp.equal request.contract
       (Sexp.of_string "((width 16) (depth 256) (read_latency 1) (port 1rw) (disabled_output hold) (write_output unspecified))"));
  let capability = Technology.exact_mapping Technology.ihp_sg13cmos5l request |> Option.value_exn in
  require "stock macro" (String.equal capability.macro.name macro_name);
  List.iter [ 8, 256, 1; 16, 128, 1; 16, 512, 1; 16, 256, 2 ]
    ~f:(fun (width, depth, read_latency) ->
      let unsupported = Resource.Request.single_port_ram ~width ~depth ~read_latency in
      require "unsupported exact request must fail"
        (Or_error.is_error
           (Resource.Selection.select ~technology:Technology.ihp_sg13cmos5l
              ~requirement:Exact unsupported));
      let fallback =
        Resource.Selection.select ~technology:Technology.ihp_sg13cmos5l
          ~requirement:Exact_or_flop_fallback unsupported |> Or_error.ok_exn
      in
      require "fallback selected only when permitted"
        (Resource.Selection.Implementation.equal fallback.implementation Flops);
      require "fallback explanation"
        (Resource.Selection.Reason.equal fallback.reason
           (Flop_fallback { no_exact_mapping_in = "ihp-sg13cmos5l" })));
  let id name = Resource.Id.of_string_exn name |> Resource.Id.rtl_instance_name in
  require "stable public instance label" (String.equal (id "program") "hc_resource_7_program");
  let names =
    [ "a_b/c"; "a/b_c"; "a/b/c"; "a_b_c"; "core/program"; "program" ]
    |> List.map ~f:id
  in
  require "injective path encoding"
    (List.length (List.dedup_and_sort names ~compare:String.compare) = List.length names);
  let exact = elaborate Exact Implementation in
  let record = Elaborated_project.resources exact |> List.hd_exn in
  require "exact selection reason"
    (Resource.Selection.Reason.equal record.selection.reason
       (Exact_mapping { technology = "ihp-sg13cmos5l" }));
  require "exact inventory uses canonical request" (Resource.Request.equal record.request request);
  require "collateral is complete"
    (List.equal Resource.Record.Source.equal record.sources
       (List.map capability.macro.collateral ~f:(fun c -> Resource.Record.Source.Collateral c)));
  let circuit = Elaborated_project.circuit exact in
  let inst = Circuit.instantiations circuit |> List.hd_exn in
  require "one physical macro" (List.length (Circuit.instantiations circuit) = 1);
  require "actual emitted name matches resource"
    (String.equal
       (Circuit.Name_for_rtl.instantiation_exn circuit inst |> Rtl.Name.backend_agnostic)
       (Resource.Id.rtl_instance_name record.id));
  require "no added registers or inferred storage"
    (Map.for_all (Circuit.signal_map circuit) ~f:(fun s ->
       not (Signal.Type.is_reg s || Signal.Type.is_mem s)));
  let rtl = render exact in
  require "no initialization" (not (String.is_substring rtl ~substring:"initial"));
  require "no preservation attributes" (not (String.is_substring rtl ~substring:"keep"));
  let repeated = elaborate Exact Implementation in
  require "repeatable RTL" (String.equal rtl (render repeated));
  let two = elaborate ~two:true Exact Implementation in
  let circuit = Elaborated_project.circuit two in
  let labels = Circuit.instantiations circuit
    |> List.map ~f:(fun inst ->
      Circuit.Name_for_rtl.instantiation_exn circuit inst |> Rtl.Name.backend_agnostic)
    |> List.sort ~compare:String.compare
  in
  let expected = Elaborated_project.resources two
    |> List.map ~f:(fun r -> Resource.Id.rtl_instance_name r.id)
    |> List.sort ~compare:String.compare
  in
  require "distinct scoped resources survive flattened naming" (List.equal String.equal labels expected);
  let simulation = elaborate Exact Simulation in
  require "simulation stays behavioral"
    (List.is_empty (Circuit.instantiations (Elaborated_project.circuit simulation)));
  let simulated_record = Elaborated_project.resources simulation |> List.hd_exn in
  require "behavioral sources only"
    (List.equal Resource.Record.Source.equal simulated_record.sources [ Generated_behavioral_model ]);
  let flops = elaborate Flops Implementation in
  require "explicit Flops bypass macro"
    (List.is_empty (Circuit.instantiations (Elaborated_project.circuit flops)));
  require "explicit flop reason"
    (Resource.Selection.Reason.equal
       (List.hd_exn (Elaborated_project.resources flops)).selection.reason Explicit_flops);
  let fallback = elaborate Exact_or_flop_fallback Implementation in
  require "fallback policy prefers exact macro"
    (Resource.Selection.Implementation.equal
       (List.hd_exn (Elaborated_project.resources fallback)).selection.implementation
       (Macro macro_name));
  let unknown = Technology.create_exn ~name:"unknown-test-macro"
    ~resource_mappings:[ { request; macro = { name = "unknown_macro"; collateral = [] } } ] in
  require "unknown selected macro still rejects"
    (Or_error.is_error (Project.elaborate (project ~technology:unknown Exact) ~mode:Implementation));
  (* A known name does not make an incompatible custom mapping executable. *)
  let small_request = Resource.Request.single_port_ram ~width:8 ~depth:3 ~read_latency:1 in
  require "stock mapping never rounds small memory"
    (Option.is_none (Technology.exact_mapping Technology.ihp_sg13cmos5l small_request));
  let incompatible = Technology.create_exn ~name:"incompatible-test-macro"
    ~resource_mappings:
      [ { request = Resource.Request.single_port_ram ~width:16 ~depth:192 ~read_latency:1
        ; macro = { name = macro_name; collateral = [] }
        } ]
  in
  let wrong_shape = Single_port_ram.Config.create_exn ~width:16 ~depth:192 ~read_latency:1 in
  (match Project.elaborate (project ~technology:incompatible ~config:wrong_shape Exact)
           ~mode:Implementation with
   | Ok _ -> failwith "known name with incompatible shape was accepted"
   | Error error ->
     require "backend, not port validation, rejected incompatible mapping"
       (String.is_substring (Error.to_string_hum error)
          ~substring:"single-port RAM macro backend is unavailable"));
  print_endline "PASS SRAM selection, collateral, architecture and stable naming"
;;

let () =
  check ();
  match Array.to_list (Sys.get_argv ()) with
  | [ _ ] -> ()
  | [ _; "--rtl"; mode; output ] ->
    let elaborated =
      match mode with
      | "macro" -> elaborate Exact Implementation
      | "flops" -> elaborate Flops Implementation
      | "behavioral" -> elaborate Exact Simulation
      | _ -> failwith "unknown RTL mode"
    in
    Out_channel.write_all output ~data:(render elaborated)
  | _ -> failwith "usage: backend_fixture [--rtl macro|flops|behavioral OUTPUT]"
;;
