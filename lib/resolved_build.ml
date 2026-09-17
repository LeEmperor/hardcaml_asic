(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "resolved_build.ml" *)
(* Source implementation of the flow resolution boundary. A resolved build is the answer
   to "is this build ready for a TT/LibreLane flow, and with exactly which settings?";

   Project.elaborate_for_flow elaborates in Implementation mode and hands the build to
   [resolve]. That calls Target.resolve for the pinned target, checks the TT top-level
   interface, the metadata, Pinout.validate_tiny_tapeout and the technology capabilities,
   converts the clock and I/O delays to nanoseconds, and merges the Flow LibreLane
   overrides over the settings it derives; Bundle then renders the result into the SDC,
   info.yaml, config.json and the manifest.

   Every fact here comes from one Project declaration, its elaborated circuit and the
   Target inputs; nothing is read from disk.

   It does NOT emit anything, that is Bundle's job, and it does NOT open or hash the files
   the target references; Bundle only records their pinned hashes. It is TT/LibreLane
   specific on purpose: the wrapper port names, the single "clk" clock and the protected
   keys all belong to that pair, and macro collateral is not supported yet.
*)

open! Core
open! Hardcaml

[@@@ocamlformat "disable"]

(* One resolved LibreLane configuration assignment, with where it came from;

   key   : LibreLane configuration variable name, "CLOCK_PERIOD" for example;
   value : the JSON value written for [key] into config.json;
   owner : which fact produced the setting; the manifest records it as provenance;
*)
module Setting = struct
  (* Where a setting's value came from;

     Design     : the elaborated circuit, such as its top module name;
     Target     : the resolved Target, such as the die area or the floorplan template;
     Clock      : the one resolved primary clock;
     Default    : a value this module picks; the only derived settings an override may
                  replace, since every other one sits under a protected key;
     Override r : a Flow.Librelane.Override.t set by hand, with [r] its declared reason;
  *)
  module Owner = struct
    type t =
      | Design
      | Target
      | Clock
      | Default
      | Override of string
    [@@deriving sexp_of]
  end

  type t =
    { key   : string
    ; value : Yojson.Safe.t
    ; owner : Owner.t
    }

  (* Written by hand since Yojson.Safe.t has no sexp_of; [value] is rendered as its JSON
     text, so a setting shows ((key PL_TARGET_DENSITY_PCT) (value 60) (owner ...)); *)
  let sexp_of_t { key; value; owner } =
    [%sexp
      { key   : string
      ; value = (Yojson.Safe.to_string value : string)
      ; owner : Owner.t
      }]
  ;;
end

(* The resolved build itself; the build plus everything checked and derived for the flow;

   build            : the Implementation build it was resolved from, unchanged;
   target           : the resolved target from Target.resolve, with every file pinned;
   clock            : the one primary clock, already known to be on "clk";
   clock_period_ns  : [clock]'s period in nanoseconds, fractions kept;
   clock_hz         : 1e9 /. [clock_period_ns];
   input_delays_ns  : (port, maximum ns) per input delay, sorted by port;
   output_delays_ns : (port, maximum ns) per output delay, sorted by port;
   settings         : derived settings merged with the overrides, sorted by key, one per
                      key;

   Careful: there is no mli, so this record is NOT private. Only [resolve] guarantees the
   fields agree ([clock_hz] matching [clock_period_ns], [settings] sorted and free of
   protected overrides); Bundle trusts all of that and checks none of it again.
*)
type t =
  { build            : Build.t
  ; target           : Target.Resolved.t
  ; clock            : Clock.t
  ; clock_period_ns  : float
  ; clock_hz         : float
  ; input_delays_ns  : (string * float) list
  ; output_delays_ns : (string * float) list
  ; settings         : Setting.t list
  }

(* The name a port is known by at the top level; its first Hardcaml name;

   The "<unnamed>" branch only keeps this total; Hardcaml names every port of a circuit
   built from an interface, so it should never show up in an error;
*)
let port_name signal =
  match Signal.names signal with
  | name :: _ -> name
  | [] -> "<unnamed>"
;;

(* The circuit's top-level ports as (name, width), inputs then outputs;

   Phantom inputs are included on purpose: Hardcaml leaves an interface input the design
   never reads out of Circuit.inputs and records it as a phantom input instead, but it is
   still a port of the emitted wrapper. Without them a design that ignores "ena" would
   fail as missing it -> see expect tests (test/test_resolved_build.ml);
*)
let ports circuit =

  (* (name, width) for each port signal *)
  let of_signals signals =
    List.map signals ~f:(fun signal -> port_name signal, Signal.width signal)
  in

  ( of_signals (Circuit.inputs circuit) @ Circuit.phantom_inputs circuit
  , of_signals (Circuit.outputs circuit) )
;;

(* The Tiny Tapeout wrapper ports, as (name, width); the TT user module template has
   exactly these, so the design interface has to as well;
*)
let expected_inputs = [ "ui_in", 8; "uio_in", 8; "ena", 1; "clk", 1; "rst_n", 1 ]
let expected_outputs = [ "uo_out", 8; "uio_out", 8; "uio_oe", 8 ]

(* Check the circuit's top level is exactly the TT wrapper interface; returns Or_error
   rather than raising since [resolve] folds it into one combined TT error;

   Per direction, for every expected port:
   wrong width     : the port exists in this direction with another width;
   wrong direction : the port is missing here but exists in the other direction;
   missing         : the port exists in neither direction;
   and then:
   unexpected      : every port in this direction that is not expected, reported together;

   Both directions are checked and every problem is reported in one combined error.

   Careful: a port in the wrong direction is reported twice. The Wrong_direction fixture
   declares "rst_n" as an output, so the input check reports it as the wrong direction
   AND the output check reports it as unexpected. That is noise, not a missed error.

   TODO (future fix): these messages do not follow docs/comment_guidelines.md section 9,
   which wants "what went wrong; how to fix it". Something like "TT top-level port has
   the wrong width; match the TT user module template". Changing them changes the
   fragments test/test_resolved_build.ml looks for, so update those in the same commit;
*)
let validate_interface circuit =

  let inputs, outputs = ports circuit in

  (* Every error for one direction; [actual] is this direction's ports, [other] the
     opposite direction's, used only to tell a wrong direction from a missing port *)
  let check ~direction ~expected ~actual ~other =

    (* One error per expected port that is not present with the right width *)
    let errors =
      List.filter_map expected ~f:(fun (name, width) ->
        match List.Assoc.find actual name ~equal:String.equal with

        (* Present with the right width; nothing to report *)
        | Some actual_width when actual_width = width -> None

        (* Present in the right direction, but with another width *)
        | Some actual_width ->
          Some
            (Or_error.error_s
               [%message
                 "TT top-level port has the wrong width"
                   (name : string)
                   (direction : string)
                   (width : int)
                   (actual_width : int)])

        (* Not in this direction; either it is in the other one, or nowhere at all *)
        | None ->
          if List.Assoc.mem other name ~equal:String.equal
          then
            Some
              (Or_error.error_s
                 [%message
                   "TT top-level port has the wrong direction"
                     (name : string)
                     (direction : string)])
          else
            Some
              (Or_error.error_s
                 [%message
                   "TT top-level port is missing" (name : string) (direction : string)]))
    in

    (* Ports in this direction the wrapper does not have *)
    let unexpected =
      List.filter actual ~f:(fun (name, _) ->
        not (List.Assoc.mem expected name ~equal:String.equal))
    in

    errors
    @
    if List.is_empty unexpected
    then []
    else
      [ Or_error.error_s
          [%message
            "unexpected TT top-level ports"
              (direction : string)
              (unexpected : (string * int) list)]
      ]
  in

  Or_error.combine_errors_unit
    (check ~direction:"input" ~expected:expected_inputs ~actual:inputs ~other:outputs
     @ check ~direction:"output" ~expected:expected_outputs ~actual:outputs ~other:inputs
    )
;;

(* A span as a float number of nanoseconds; through seconds, so fractional nanoseconds
   survive (a 48 MHz period is 20.833... ns);
*)
let span_ns span = Time_float.Span.to_sec span *. 1e9

(* Resolve the declared clock and I/O delays against the elaborated ports; returns the
   clock, its period in nanoseconds and both delay lists as (port, maximum ns), sorted by
   port; returns Or_error rather than raising since [resolve] binds it after its other
   checks;

   1. exactly one clock, on "clk" -> otherwise error, and no delay is checked at all;
   2. per delay list, every delay whose maximum is not finite or is negative -> error;
   3. otherwise, every delay on "clk" or on a port not in that direction -> error;
   4. a port delayed more than once in the same list -> error; only the first repeat
      found is reported;
   5. no errors -> sort by port and convert each maximum to nanoseconds;

   Steps 2 to 4 run for both lists, and every problem found is reported in one combined
   error. Steps 2 and 3 are one if/else chain, so a delay with both a bad maximum and a
   bad port only reports the maximum.

   NOT checked: a maximum longer than the clock period, and a delay on a phantom input
   (those are real wrapper ports, see [ports]); both are accepted as declared.
*)
let validate_timing build =

  let circuit = Build.circuit build in
  let inputs, outputs = ports circuit in

  (* The one primary clock; TT wires its clock to "clk" and the SDC assumes it *)
  let%bind.Or_error clock =
    match Build.clocks build with
    | [ clock ] when String.equal clock.port "clk" -> Ok clock
    | clocks ->
      Or_error.error_s
        [%message
          "TT/LibreLane requires exactly one primary clock on clk"
            (clocks : Clock.t list)]
  in

  let period_ns = span_ns clock.period in
  let timing = Build.timing build in

  (* Steps 2 to 5 for one direction; [actual] is that direction's (name, width) ports *)
  let check_delays direction actual delays =

    (* Steps 2 and 3; one error per bad delay *)
    let errors =
      List.filter_map delays ~f:(fun (delay : Timing.Delay.t) ->
        let maximum_ns = span_ns delay.maximum in
        if (not (Float.is_finite maximum_ns)) || Float.(maximum_ns < 0.)
        then
          Some
            (Or_error.error_s
               [%message
                 "timing delay must be finite and nonnegative"
                   (direction : string)
                   (delay : Timing.Delay.t)])
        else if String.equal delay.port "clk"
                || not (List.Assoc.mem actual delay.port ~equal:String.equal)
        then
          Some
            (Or_error.error_s
               [%message
                 "timing delay must name a nonclock top-level port in the stated \
                  direction"
                   (direction : string)
                   (delay : Timing.Delay.t)])
        else None)
    in

    (* Step 4; compares [port] only, so the same port with two maximums is a duplicate *)
    let duplicate =
      List.find_a_dup delays ~compare:(fun a b -> String.compare a.port b.port)
    in

    (* The duplicate, if any, goes in front of the other errors *)
    let errors =
      match duplicate with
      | None -> errors
      | Some duplicate ->
        Or_error.error_s
          [%message
            "timing delay port declared more than once"
              (direction : string)
              (duplicate : Timing.Delay.t)]
        :: errors
    in

    (* Step 5 *)
    let%map.Or_error () = Or_error.combine_errors_unit errors in
    List.sort delays ~compare:(fun a b -> String.compare a.port b.port)
    |> List.map ~f:(fun delay -> delay.port, span_ns delay.maximum)
  in

  (* let%map ... and combines the errors of both lists, rather than stopping at inputs *)
  let%map.Or_error input_delays_ns = check_delays "input" inputs timing.input_delays
  and output_delays_ns = check_delays "output" outputs timing.output_delays in
  clock, period_ns, input_delays_ns, output_delays_ns
;;

(* The technology view roles a LibreLane [operation] cannot run without;

   Synthesis : PDK configuration, standard cell Liberty and Verilog;
   Hardening : all of the above, plus technology LEF and standard cell LEF and GDS;

   The list order is the order [validate_capabilities] reports missing roles in.

   An exhaustive match with no wildcard on purpose: a new Flow.Operation constructor fails
   to compile here until someone decides which views it needs.
*)
let required_views operation =
  let open Technology.Cmos5l.View.Role in
  match operation with
  | Flow.Operation.Synthesis ->
    [ Pdk_configuration; Standard_cell_liberty; Standard_cell_verilog ]
  | Hardening ->
    [ Pdk_configuration
    ; Technology_lef
    ; Standard_cell_lef
    ; Standard_cell_gds
    ; Standard_cell_verilog
    ; Standard_cell_liberty
    ]
;;

(* Check the build and resolved target can actually run the selected flow; returns
   Or_error rather than raising since [resolve] folds it into one combined TT error;

   mode    : the build must come from Implementation elaboration; a Simulation build
             carries behavioral models, not synthesis RTL;
   views   : every role [required_views] names for the flow's operation has a
             Technology_view in [target.views]; a Floorplan_def never counts;
   macros  : no resource may be selected as a Macro; this reference adapter does not
             emit macro collateral (MACROS, EXTRA_LEFS, ...) yet;
   sources : every resource carries Generated_synthesis_rtl; skipped for a Simulation
             build, since the mode check already fails and would otherwise be followed by
             every resource again;

   All four checks run even when another fails, so one call reports every problem.

   A consequence: in Implementation mode only a Macro resource lacks synthesis RTL (see
   Elaboration_context.sources_of), so a macro is reported by both [macros] and
   [sources]. The sources check stays as a guard in case sources_of changes.

   Taking the target separately rather than resolving it here lets a test hand it a
   target with a view removed -> see expect tests (test/test_resolved_build.ml);
*)
let validate_capabilities build target =

  let flow = Build.flow build in
  let operation = flow.operation in

  (* Required roles with no matching technology view in the target *)
  let missing =
    List.filter (required_views flow.operation) ~f:(fun role ->
      not
        (List.exists target.Target.Resolved.views ~f:(fun view ->
           match view.role with
           | Technology_view actual -> Technology.Cmos5l.View.Role.equal actual role
           | Floorplan_def -> false)))
  in

  let resources = Build.resources build in

  (* Resources selected as a hard macro *)
  let unsupported_macros =
    List.filter resources ~f:(fun resource ->
      match resource.selection.implementation with
      | Selection.Implementation.Macro _ -> true
      | Flops -> false)
  in

  (* Resources with no synthesis RTL; empty for a Simulation build, see above *)
  let missing_synthesis_sources =
    if Elaboration_mode.equal (Build.mode build) Elaboration_mode.Simulation
    then []
    else
      List.filter resources ~f:(fun resource ->
        not
          (List.mem
             resource.sources
             Resource_record.Source.Generated_synthesis_rtl
             ~equal:Resource_record.Source.equal))
  in

  (* Checking with the above in a list format, fold any errors into the result; *)
  Or_error.combine_errors_unit
    [ (if Elaboration_mode.equal (Build.mode build) Elaboration_mode.Implementation
       then Ok ()
       else
         Or_error.error_s
           [%message "flow resolution requires implementation elaboration"])

    ; (if List.is_empty missing
       then Ok ()
       else
         Or_error.error_s
           [%message
             "LibreLane operation lacks required technology views"
               (operation : Flow.Operation.t)
               (missing : Technology.Cmos5l.View.Role.t list)])

    ; (if List.is_empty unsupported_macros
       then Ok ()
       else
         Or_error.error_s
           [%message
             "TT/LibreLane macro collateral is not supported by this reference adapter"
               (unsupported_macros : Resource_record.t list)])

    ; (if List.is_empty missing_synthesis_sources
       then Ok ()
       else
         Or_error.error_s
           [%message
             "implementation resources need generated synthesis RTL"
               (missing_synthesis_sources : Resource_record.t list)])
    ]
;;

(* LibreLane keys an override may never set, because the value is a fact owned by the
   declaration rather than a tuning knob;

   design   : DESIGN_NAME;
   sources  : VERILOG_FILES, generated by Bundle.config;
   target   : DIE_AREA, FP_DEF_TEMPLATE, the power pins, PDK, STD_CELL_LIBRARY, every
              routing layer bound and FP_IO_*LAYER, FP_PIN_ORDER_CFG; fixed by the TT
              floorplan template and PDK, even where no setting is derived for them;
   clock    : CLOCK_PORT, CLOCK_PERIOD;
   resource : MACROS, EXTRA_LEFS, EXTRA_GDS_FILES, EXTRA_LIBS, EXTRA_VERILOG_MODELS,
              SYNTH_BLACKBOXES; macro collateral, which is not supported yet;

   Anything containing "SDC" is protected too, see [protected_key].

   Careful: this list is separate from what [resolve_settings] derives. A new derived
   setting whose key is not added here can be silently replaced by an override; that is
   only intended for the Default owned ones (FP_SIZING, RUN_LINTER).
*)
let protected_keys =
  [ "DESIGN_NAME"
  ; "VERILOG_FILES"
  ; "DIE_AREA"
  ; "FP_DEF_TEMPLATE"
  ; "VDD_PIN"
  ; "GND_PIN"
  ; "RT_MAX_LAYER"
  ; "RT_MIN_LAYER"
  ; "GRT_MIN_LAYER"
  ; "GRT_MAX_LAYER"
  ; "DRT_MIN_LAYER"
  ; "DRT_MAX_LAYER"
  ; "FP_IO_HLAYER"
  ; "FP_IO_VLAYER"
  ; "CLOCK_PORT"
  ; "CLOCK_PERIOD"
  ; "PDK"
  ; "STD_CELL_LIBRARY"
  ; "MACROS"
  ; "EXTRA_LEFS"
  ; "EXTRA_GDS_FILES"
  ; "EXTRA_LIBS"
  ; "EXTRA_VERILOG_MODELS"
  ; "SYNTH_BLACKBOXES"
  ; "FP_PIN_ORDER_CFG"
  ]
;;

(* Whether an override may NOT set [key]; any key in [protected_keys], or any key
   containing "SDC";

   The substring match is broad on purpose: timing constraints only come from Timing and
   Clock through Bundle.sdc, and Bundle.config generates PNR_SDC_FILE and
   SIGNOFF_SDC_FILE, so every SDC related key ("PNR_SDC_FILE", "SIGNOFF_SDC_FILE", ...)
   is rejected without listing each one;
*)
let protected_key key =
  List.mem protected_keys key ~equal:String.equal
  || String.is_substring key ~substring:"SDC"
;;

(* Derive the LibreLane settings and merge the overrides over them; returns Or_error
   rather than raising since [resolve] binds it as its last check;

   1. derive a setting per design, target and clock fact, plus two Default ones;
   2. pull the overrides out of the flow adapter;
   3. any override on a protected key -> error, every conflict reported together;
   4. drop each derived setting an override replaces, then add the overrides, owned by
      Override with their reason;
   5. sort by key;

   Why one setting per key: derived keys are distinct by construction, Flow.validate
   already rejected overrides that repeat a key, and step 4 drops every derived setting
   an override shares a key with. After step 3 only FP_SIZING and RUN_LINTER can be
   dropped that way.

   Careful: DIE_AREA prints each bound with "%.12g", so a coordinate with more than 12
   significant digits is rounded in the config; real TT die areas are far from that.
*)
let resolve_settings build target clock_period_ns =

  let mk key value owner : Setting.t = { key; value; owner } in
  let rect = target.Target.Resolved.die_area_um in

  (* Step 1; CLOCK_PORT can be "clk" outright since [validate_timing] already required
     it; FP_DEF_TEMPLATE is still support-tools relative, Bundle.config rewrites it *)
  (* TODO (possible fix): PDK repeats [target.technology_name] and STD_CELL_LIBRARY is a
     literal too; fine while only ihp-sg13cmos5l resolves, but both should come from the
     resolved target once a second technology does; *)
  let derived =
    [ mk "DESIGN_NAME" (`String (Circuit.name (Build.circuit build))) Design
    ; mk
        "DIE_AREA"
        (`String
          (String.concat
             ~sep:" "
             (List.map
                [ rect.x_min; rect.y_min; rect.x_max; rect.y_max ]
                ~f:(Printf.sprintf "%.12g"))))
        Target
    ; mk "FP_DEF_TEMPLATE" (`String target.floorplan.path) Target
    ; mk "VDD_PIN" (`String (fst target.harness_power_pins)) Target
    ; mk "GND_PIN" (`String (snd target.harness_power_pins)) Target
    ; mk "RT_MAX_LAYER" (`String target.top_routing_layer) Target
    ; mk "PDK" (`String "ihp-sg13cmos5l") Target
    ; mk "STD_CELL_LIBRARY" (`String "sg13cmos5l_stdcell") Target
    ; mk "CLOCK_PORT" (`String "clk") Clock
    ; mk "CLOCK_PERIOD" (`Float clock_period_ns) Clock
    ; mk "FP_SIZING" (`String "absolute") Default
    ; mk "RUN_LINTER" (`Int 1) Default
    ]
  in

  (* Step 2; no wildcard, so a new Flow.Adapter fails to compile here *)
  let overrides =
    match (Build.flow build).adapter with
    | Flow.Adapter.Librelane settings -> settings.overrides
  in

  (* Step 3 *)
  let conflicts = List.filter overrides ~f:(fun o -> protected_key o.key) in
  let%map.Or_error () =
    if List.is_empty conflicts
    then Ok ()
    else
      Or_error.error_s
        [%message
          "LibreLane override conflicts with a generated design, target, clock, source, \
           or resource fact"
            (conflicts : Flow.Librelane.Override.t list)]
  in

  (* Step 4 *)
  let entries =
    List.filter derived ~f:(fun entry ->
      not (List.exists overrides ~f:(fun o -> String.equal o.key entry.key)))
    @ List.map overrides ~f:(fun o -> mk o.key o.value (Override o.reason))
  in

  (* Step 5 *)
  List.sort entries ~compare:(fun a b -> String.compare a.key b.key)
;;

(* The main sauce here for flow resolution; given an Implementation build, check it
   against the TT/LibreLane flow and return everything Bundle needs;

   1. resolve the target -> an unsupported harness and technology pair stops here, with
      nothing else checked;
   2. check the interface, metadata, pinout and capabilities, every problem reported in
      one combined error;
   3. [validate_timing] -> resolved clock and delays;
   4. [resolve_settings] -> merged settings;
   5. assemble, deriving [clock_hz] from the period;

   Steps are bound in order, so a failure in one hides the ones after it; a protected
   override is only reported once the interface and timing are clean.

   Metadata author and description are checked here, not in Metadata.validate, which
   only requires a title; a TT submission needs both, a project that only simulates
   does not.

   Returns Or_error rather than raising since it runs after elaboration, outside any
   design constructor; Project.elaborate_for_flow tags the error with the project name.
   [inputs] passes straight through to Target.resolve, which defaults it to
   Target.Inputs.reference_cmos5l_6x4 -> see expect tests (test/test_resolved_build.ml);
*)
let resolve ?inputs build =

  let%bind.Or_error target = Target.resolve ?inputs (Build.target build) in
  let metadata = Build.metadata build in

  (* Step 2 *)
  let%bind.Or_error () =
    Or_error.combine_errors_unit
      [ validate_interface (Build.circuit build)

      ; (if String.is_empty (String.strip metadata.author)
            || String.is_empty (String.strip metadata.description)
         then
           Or_error.error_s
             [%message "TT metadata needs a nonblank author and description"]
         else Ok ())

      ; Pinout.validate_tiny_tapeout (Build.pinout build)

      ; validate_capabilities build target
      ]
  in

  (* Step 3 *)
  let%bind.Or_error clock, clock_period_ns, input_delays_ns, output_delays_ns =
    validate_timing build
  in

  (* Steps 4 and 5 *)
  let%map.Or_error settings = resolve_settings build target clock_period_ns in
  { build
  ; target
  ; clock
  ; clock_period_ns
  ; clock_hz = 1e9 /. clock_period_ns
  ; input_delays_ns
  ; output_delays_ns
  ; settings
  }
;;

[@@@ocamlformat "enable"]
