let operations =
  [ Operation.make "synthesis.lint" Check "RTL lint and lint policy checks"
      "RTL sources and resolved lint configuration" "Lint diagnostics checked"
  ; Operation.make "synthesis.netlist" Transform "Generate RTL header and synthesized netlist"
      "RTL sources, technology libraries and synthesis configuration" "Header and mapped netlist available"
  ]
