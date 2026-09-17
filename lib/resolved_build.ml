(* Validation boundary between a portable elaboration and TT/LibreLane emission. All facts
   here come from one Project declaration and its elaborated circuit. *)
open! Core
open! Hardcaml

module Setting = struct
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
    { key : string
    ; value : Yojson.Safe.t
    ; owner : Owner.t
    }

  let sexp_of_t { key; value; owner } =
    [%sexp
      { key : string; value = (Yojson.Safe.to_string value : string); owner : Owner.t }]
  ;;
end

type t =
  { build : Build.t
  ; target : Target.Resolved.t
  ; clock : Clock.t
  ; clock_period_ns : float
  ; clock_hz : float
  ; input_delays_ns : (string * float) list
  ; output_delays_ns : (string * float) list
  ; settings : Setting.t list
  }

let port_name signal =
  match Signal.names signal with
  | name :: _ -> name
  | [] -> "<unnamed>"
;;

let ports circuit =
  let of_signals signals =
    List.map signals ~f:(fun signal -> port_name signal, Signal.width signal)
  in
  ( of_signals (Circuit.inputs circuit) @ Circuit.phantom_inputs circuit
  , of_signals (Circuit.outputs circuit) )
;;

let expected_inputs = [ "ui_in", 8; "uio_in", 8; "ena", 1; "clk", 1; "rst_n", 1 ]
let expected_outputs = [ "uo_out", 8; "uio_out", 8; "uio_oe", 8 ]

let validate_interface circuit =
  let inputs, outputs = ports circuit in
  let check ~direction ~expected ~actual ~other =
    let errors =
      List.filter_map expected ~f:(fun (name, width) ->
        match List.Assoc.find actual name ~equal:String.equal with
        | Some actual_width when actual_width = width -> None
        | Some actual_width ->
          Some
            (Or_error.error_s
               [%message
                 "TT top-level port has the wrong width"
                   (name : string)
                   (direction : string)
                   (width : int)
                   (actual_width : int)])
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

let span_ns span = Time_float.Span.to_sec span *. 1e9

let validate_timing build =
  let circuit = Build.circuit build in
  let inputs, outputs = ports circuit in
  let%bind.Or_error clock =
    match Build.clocks build with
    | [ clock ] when String.equal clock.port "clk" -> Ok clock
    | clocks ->
      Or_error.error_s
        [%message
          "TT/LibreLane requires exactly one primary clock on clk" (clocks : Clock.t list)]
  in
  let period_ns = span_ns clock.period in
  let timing = Build.timing build in
  let check_delays direction actual delays =
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
    let duplicate =
      List.find_a_dup delays ~compare:(fun a b -> String.compare a.port b.port)
    in
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
    let%map.Or_error () = Or_error.combine_errors_unit errors in
    List.sort delays ~compare:(fun a b -> String.compare a.port b.port)
    |> List.map ~f:(fun delay -> delay.port, span_ns delay.maximum)
  in
  let%map.Or_error input_delays_ns = check_delays "input" inputs timing.input_delays
  and output_delays_ns = check_delays "output" outputs timing.output_delays in
  clock, period_ns, input_delays_ns, output_delays_ns
;;

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

let validate_capabilities build target =
  let flow = Build.flow build in
  let operation = flow.operation in
  let missing =
    List.filter (required_views flow.operation) ~f:(fun role ->
      not
        (List.exists target.Target.Resolved.views ~f:(fun view ->
           match view.role with
           | Technology_view actual -> Technology.Cmos5l.View.Role.equal actual role
           | Floorplan_def -> false)))
  in
  let resources = Build.resources build in
  let unsupported_macros =
    List.filter resources ~f:(fun resource ->
      match resource.selection.implementation with
      | Selection.Implementation.Macro _ -> true
      | Flops -> false)
  in
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
  Or_error.combine_errors_unit
    [ (if Elaboration_mode.equal (Build.mode build) Elaboration_mode.Implementation
       then Ok ()
       else
         Or_error.error_s [%message "flow resolution requires implementation elaboration"])
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

let protected_key key =
  List.mem protected_keys key ~equal:String.equal
  || String.is_substring key ~substring:"SDC"
;;

let resolve_settings build target clock_period_ns =
  let mk key value owner : Setting.t = { key; value; owner } in
  let rect = target.Target.Resolved.die_area_um in
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
  let overrides =
    match (Build.flow build).adapter with
    | Flow.Adapter.Librelane settings -> settings.overrides
  in
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
  let entries =
    List.filter derived ~f:(fun entry ->
      not (List.exists overrides ~f:(fun o -> String.equal o.key entry.key)))
    @ List.map overrides ~f:(fun o -> mk o.key o.value (Override o.reason))
  in
  List.sort entries ~compare:(fun a b -> String.compare a.key b.key)
;;

let resolve ?inputs build =
  let%bind.Or_error target = Target.resolve ?inputs (Build.target build) in
  let metadata = Build.metadata build in
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
  let%bind.Or_error clock, clock_period_ns, input_delays_ns, output_delays_ns =
    validate_timing build
  in
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
