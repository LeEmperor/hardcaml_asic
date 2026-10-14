let operations =
  [ Operation.make "signoff.route_checks" Check "Remove routing obstructions and check antennas, DRC, pins and wire length"
      "Detailed routing database and routing metrics" "Post-routing checks and reports"
  ; Operation.make "signoff.extract" Transform "Fill insertion, cell tables and parasitic extraction"
      "Routed database and extraction technology" "Filled database and extracted parasitics when configured"
  ; Analysis.Timing.post_pnr
  ; Operation.make "signoff.physical" Analyze "IR drop, stream-outs, render, LEF, antenna properties and XOR"
      "Routed views and signoff technology/tool configuration" "Physical views and comparison metrics when configured"
  ; Operation.make "signoff.verification" Check "DRC, extraction, overlap, LVS, equivalence and timing checks"
      "Physical/netlist views and backend metrics" "Configured signoff checks evaluated"
  ; Operation.make "signoff.report" Analyze "Report manufacturability"
      "Backend signoff metrics" "Terminal backend report; external acceptance not evaluated"
  ]
