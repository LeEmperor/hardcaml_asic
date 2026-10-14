let pre_pnr = Operation.make "timing.pre_pnr" Analyze
  "Static timing analysis before physical implementation"
  "Synthesized netlist and validated timing constraints"
  "Timing metrics and derived timing views; no placement"
let mid_pnr = Operation.make "timing.mid_pnr" Analyze
  "Shared in-PNR static timing analysis"
  "Current physical database and resolved timing libraries/constraints"
  "Timing metrics for this occurrence; no design repair"
let post_pnr = Operation.make "timing.post_pnr" Analyze
  "Multi-corner extracted static timing analysis"
  "Routed netlist/database and extracted parasitics"
  "Timing metrics and derived SDF/SDC/library views"
