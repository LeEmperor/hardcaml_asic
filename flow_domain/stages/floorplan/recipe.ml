let operations =
  [ Operation.make "floorplan.checks" Check "Check synthesis, assignments, SDC and macros"
      "Synthesized netlist and resolved configuration" "Synthesis and floorplan prerequisites checked"
  ; Analysis.Timing.pre_pnr
  ; Operation.make "floorplan.initialize" Transform "Initialize die, core, rows and physical database"
      "Checked netlist, geometry and technology" "Initial floorplan database available"
  ]
