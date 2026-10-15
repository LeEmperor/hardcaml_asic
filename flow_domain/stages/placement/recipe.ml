let operations =
  [ Operation.make "placement.setup" Transform "RC setup, macro checks, power connections, macro placement and row cutting"
      "Floorplan database and RTL header" "Rows/macros/power connectivity prepared"
  ; Operation.make "placement.pdn" Transform "Tap/endcap insertion and PDN obstruction/generation lifecycle"
      "Prepared rows and power configuration" "Power grid and routing obstructions prepared"
  ; Operation.make "placement.io" Transform "Skip-IO global placement, IO/custom IO placement and DEF template"
      "Powered database and resolved IO/template configuration" "IO/template preparation complete"
  ; Global_placement.operation
  ; Operation.make "placement.header_checks" Check "Write Verilog header and check power-grid violations"
      "Globally placed database and RTL header" "Verilog header available and grid metrics checked"
  ; Analysis.Timing.mid_pnr
  ; Design_repair.operation
  ; Operation.make "placement.manual" Transform "Apply configured manual global placement"
      "Globally placed/repaired database" "Manual overrides applied when configured"
  ; Detailed_placement.operation
  ]
