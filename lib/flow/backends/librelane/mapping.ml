let tested_image_id = "sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a"
type step =
  { id : string; implementation : string; inputs : string list; outputs : string list
  ; gates : (string * bool) list }
type occurrence =
  { occurrence_id : string; stage : Stage_id.t; operation : Operation.t; step : step }
type setting =
  { name : string; kind : string; units : string option; default : string option; pdk : bool
  ; allowed_values : string list option }
let setting ?units ?default ?(pdk=false) ?allowed_values name kind = {name;kind;units;default;pdk;allowed_values}
let settings implementation = match implementation with
  | "Yosys.Synthesis" ->
    [setting ~default:(Parameter.Strategy.to_string Parameter.Strategy.Area_0)
       ~allowed_values:(List.map Parameter.Strategy.to_string Parameter.Strategy.all) "SYNTH_STRATEGY" "enum";
     setting ~default:"false" "SYNTH_ABC_BUFFERING" "boolean"]
  | "OpenROAD.GlobalPlacement" | "OpenROAD.GlobalPlacementSkipIO" ->
    [setting ~units:"%" "PL_TARGET_DENSITY_PCT" "optional_decimal";
     setting ~default:"false" "PL_SKIP_INITIAL_PLACEMENT" "boolean";
     setting ~default:"0.25" "PL_WIRE_LENGTH_COEF" "decimal";
     setting ~units:"%" ~default:"50" "FP_CORE_UTIL" "decimal";
     setting ~units:"sites" ~pdk:true "GPL_CELL_PADDING" "integer"]
  | "OpenROAD.RepairDesignPostGPL" ->
    [setting ~default:"true" "DESIGN_REPAIR_BUFFER_INPUT_PORTS" "boolean";
     setting ~default:"true" "DESIGN_REPAIR_BUFFER_OUTPUT_PORTS" "boolean";
     setting ~default:"true" "DESIGN_REPAIR_TIE_FANOUT" "boolean";
     setting ~default:"false" "DESIGN_REPAIR_TIE_SEPARATION" "boolean";
     setting ~units:"µm" ~default:"0" "DESIGN_REPAIR_MAX_WIRE_LENGTH" "decimal";
     setting ~units:"%" ~default:"20" "DESIGN_REPAIR_MAX_SLEW_PCT" "decimal";
     setting ~units:"%" ~default:"20" "DESIGN_REPAIR_MAX_CAP_PCT" "decimal";
     setting ~default:"false" "DESIGN_REPAIR_REMOVE_BUFFERS" "boolean"]
  | "OpenROAD.DetailedPlacement" ->
    [setting ~default:"true" "PL_OPTIMIZE_MIRRORING" "boolean";
     setting ~units:"µm" ~default:"500" "PL_MAX_DISPLACEMENT_X" "integer";
     setting ~units:"µm" ~default:"100" "PL_MAX_DISPLACEMENT_Y" "integer";
     setting ~units:"sites" ~pdk:true "DPL_CELL_PADDING" "integer"]
  | _ -> []

let physical = ["odb"; "def"; "sdc"; "nl"; "pnl"]
let odb = ["odb"; "def"]
let gate name =
  name, not (List.mem name ["RUN_POST_GRT_DESIGN_REPAIR";
    "RUN_POST_GRT_RESIZER_TIMING"; "RUN_HEURISTIC_DIODE_INSERTION"; "RUN_EQY"])
let step ?(gates=[]) id inputs outputs =
  {id; implementation=id; inputs=List.sort String.compare inputs;
   outputs=List.sort String.compare outputs; gates=List.map gate gates}
let check ?gates id = step ?gates id [] []
let transform ?gates id = step ?gates id ["odb"] physical
let edit id = step id ["odb"] odb
let xor_gates = ["RUN_KLAYOUT_XOR"; "RUN_MAGIC_STREAMOUT"; "RUN_KLAYOUT_STREAMOUT"]

(* One selected-Classic mapping per domain operation. Repeated implementations
   acquire Classic's occurrence suffix globally, never by display label. *)
let steps (operation : Operation.t) = match operation.key with
  | "synthesis.lint" -> List.map (check ~gates:["RUN_LINTER"])
      ["Verilator.Lint"; "Checker.LintTimingConstructs"; "Checker.LintErrors"; "Checker.LintWarnings"]
  | "synthesis.netlist" -> [step "Yosys.JsonHeader" [] ["json_h"]; step "Yosys.Synthesis" [] ["nl"]]
  | "floorplan.checks" ->
      [check "Checker.YosysUnmappedCells"; check "Checker.YosysSynthChecks";
       step "Checker.NetlistAssignStatements" ["nl"] []; check "OpenROAD.CheckSDCFiles";
       step "OpenROAD.CheckMacroInstances" ["nl"] []]
  | "timing.pre_pnr" -> [step "OpenROAD.STAPrePNR" ["nl"] ["sdf"; "sdc"]]
  | "floorplan.initialize" -> [step "OpenROAD.Floorplan" ["nl"] physical]
  | "placement.setup" ->
      [step "OpenROAD.DumpRCValues" ["def"] physical;
       step "Odb.CheckMacroAntennaProperties" ["odb"] [];
       step "Odb.SetPowerConnections" ["json_h"; "odb"] odb;
       edit "Odb.ManualMacroPlacement"; edit "OpenROAD.CutRows"]
  | "placement.pdn" ->
      [transform ~gates:["RUN_TAP_ENDCAP_INSERTION"] "OpenROAD.TapEndcapInsertion";
       edit "Odb.AddPDNObstructions"; transform "OpenROAD.GeneratePDN";
       edit "Odb.RemovePDNObstructions"; edit "Odb.AddRoutingObstructions"]
  | "placement.io" ->
      [transform "OpenROAD.GlobalPlacementSkipIO"; transform "OpenROAD.IOPlacement";
       edit "Odb.CustomIOPlacement"; edit "Odb.ApplyDEFTemplate"]
  | "placement.global" -> [transform "OpenROAD.GlobalPlacement"]
  | "placement.header_checks" ->
      [step "Odb.WriteVerilogHeader" ["odb"; "json_h"] ["vh"]; check "Checker.PowerGridViolations"]
  | "timing.mid_pnr" -> [step "OpenROAD.STAMidPNR" ["odb"] []]
  | "placement.design_repair" ->
      [transform ~gates:["RUN_POST_GPL_DESIGN_REPAIR"] "OpenROAD.RepairDesignPostGPL"]
  | "placement.manual" -> [edit "Odb.ManualGlobalPlacement"]
  | "placement.detailed" -> [transform "OpenROAD.DetailedPlacement"]
  | "cts.tree" -> [transform ~gates:["RUN_CTS"] "OpenROAD.CTS"]
  | "routing.cts_timing_repair" ->
      [transform ~gates:["RUN_POST_CTS_RESIZER_TIMING"] "OpenROAD.ResizerTimingPostCTS"]
  | "routing.global" -> [edit "OpenROAD.GlobalRouting"; step "OpenROAD.CheckAntennas" ["odb"] []]
  | "routing.repair" ->
      [transform ~gates:["RUN_POST_GRT_DESIGN_REPAIR"] "OpenROAD.RepairDesignPostGRT";
       step "Odb.DiodesOnPorts" ["odb"] ["sdc"; "odb"; "nl"; "def"; "pnl"];
       step ~gates:["RUN_HEURISTIC_DIODE_INSERTION"] "Odb.HeuristicDiodeInsertion" ["odb"] ["sdc"; "odb"; "nl"; "def"; "pnl"];
       step ~gates:["RUN_ANTENNA_REPAIR"] "OpenROAD.RepairAntennas" ["odb"] odb;
       transform ~gates:["RUN_POST_GRT_RESIZER_TIMING"] "OpenROAD.ResizerTimingPostGRT"]
  | "routing.detailed" -> [transform ~gates:["RUN_DRT"] "OpenROAD.DetailedRouting"]
  | "signoff.route_checks" ->
      [edit "Odb.RemoveRoutingObstructions"; step "OpenROAD.CheckAntennas" ["odb"] [];
       check ~gates:["RUN_DRT"] "Checker.TrDRC"; edit "Odb.ReportDisconnectedPins";
       check "Checker.DisconnectedPins"; step "Odb.ReportWireLength" ["odb"] []; check "Checker.WireLength"]
  | "signoff.extract" ->
      [transform ~gates:["RUN_FILL_INSERTION"] "OpenROAD.FillInsertion";
       edit "Odb.CellFrequencyTables"; step ~gates:["RUN_SPEF_EXTRACTION"] "OpenROAD.RCX" ["def"] ["spef"]]
  | "timing.post_pnr" ->
      [step ~gates:["RUN_MCSTA"] "OpenROAD.STAPostPNR" ["nl"; "spef"; "odb"] ["sdf"; "sdc"; "lib"]]
  | "signoff.physical" ->
      [step ~gates:["RUN_IRDROP_REPORT"] "OpenROAD.IRDropReport" ["odb"; "spef"] [];
       step ~gates:["RUN_MAGIC_STREAMOUT"] "Magic.StreamOut" ["def"] ["gds"; "mag_gds"; "mag"];
       step ~gates:["RUN_KLAYOUT_STREAMOUT"] "KLayout.StreamOut" ["def"] ["gds"; "klayout_gds"];
       step "KLayout.Render" ["def"; "gds"] [];
       step ~gates:["RUN_MAGIC_WRITE_LEF"] "Magic.WriteLEF" ["gds"; "def"] ["lef"];
       step "Odb.CheckDesignAntennaProperties" ["odb"; "lef"] [];
       step ~gates:xor_gates "KLayout.XOR" ["mag_gds"; "klayout_gds"] [];
       check ~gates:xor_gates "Checker.XOR"]
  | "signoff.verification" ->
      [step ~gates:["RUN_MAGIC_DRC"] "Magic.DRC" ["def"; "gds"] [];
       step ~gates:["RUN_KLAYOUT_DRC"] "KLayout.DRC" ["gds"] [];
       check ~gates:["RUN_MAGIC_DRC"] "Checker.MagicDRC";
       check ~gates:["RUN_KLAYOUT_DRC"] "Checker.KLayoutDRC";
       step "Magic.SpiceExtraction" ["gds"; "def"] ["spice"]; check "Checker.IllegalOverlap";
       step ~gates:["RUN_LVS"] "Netgen.LVS" ["spice"; "pnl"] []; check ~gates:["RUN_LVS"] "Checker.LVS";
       step ~gates:["RUN_EQY"] "Yosys.EQY" ["nl"] [];
       check "Checker.SetupViolations"; check "Checker.HoldViolations";
       check "Checker.MaxSlewViolations"; check "Checker.MaxCapViolations"]
  | "signoff.report" -> [check "Misc.ReportManufacturability"]
  | key -> invalid_arg ("unmapped domain operation: " ^ key)

let all =
  let counts = Hashtbl.create 80 in
  List.concat_map (fun stage ->
    let ordinal = ref 0 in
    List.concat_map (fun operation -> List.map (fun step ->
      let count = Option.value (Hashtbl.find_opt counts step.implementation) ~default:0 in
      Hashtbl.replace counts step.implementation (count+1);
      let id = step.implementation ^ (if count=0 then "" else "-" ^ string_of_int count) in
      incr ordinal;
      {occurrence_id=Stage_id.to_string stage ^ "/" ^ string_of_int !ordinal ^ "/" ^ id;
       stage; operation; step={step with id}}) (steps operation)) (Registry.operations stage)) Stage_id.all
let composition stage = List.filter (fun o -> Stage_id.equal o.stage stage) all
let endpoint stage = (List.hd (List.rev (composition stage))).step.id
let successor stage =
  let rec next = function
    | [] | [_] -> None
    | a :: (b :: _ as rest) -> if Stage_id.equal a stage then Some (List.hd (composition b)).step.id else next rest
  in next Stage_id.all
let validate_inventory inventory =
  let expected = List.map (fun o -> o.step) all in
  if inventory = expected then Ok ()
  else Error "Unsupported LibreLane Classic drift: ordered IDs, implementations, artifacts or configured gates/defaults differ"
let validate_sequence ~initial_boundary stages =
  let remaining = match initial_boundary with
    | None -> Stage_id.all
    | Some source ->
      let rec after = function [] -> [] | x::xs -> if Stage_id.equal source x then xs else after xs in
      after Stage_id.all in
  let rec prefix stages remaining = match stages,remaining with
    | [],_ -> true | x::xs,y::ys when Stage_id.equal x y -> prefix xs ys | _ -> false in
  if stages <> [] && prefix stages remaining then Ok ()
  else Error "Only the trusted contiguous six-stage Classic composition is runnable"
