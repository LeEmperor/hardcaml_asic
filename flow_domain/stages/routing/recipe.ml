let operations =
  [ Analysis.Timing.mid_pnr
  ; Operation.make "routing.cts_timing_repair" Transform "Post-CTS timing optimization"
      "Clock-tree database and timing constraints" "Timing-repaired database when configured"
  ; Analysis.Timing.mid_pnr
  ; Operation.make "routing.global" Transform "Global routing and antenna check"
      "Placed clock-tree database and routing technology" "Global routes and antenna metrics"
  ; Operation.make "routing.repair" Transform "Post-GRT design repair, port/heuristic diodes, antenna and timing repair"
      "Global routes, antenna/timing metrics and repair configuration" "Repaired globally routed database when configured"
  ; Analysis.Timing.mid_pnr
  ; Operation.make "routing.detailed" Transform "Detailed routing"
      "Globally routed/repaired database" "Detailed routing boundary when configured gate permits"
  ]
