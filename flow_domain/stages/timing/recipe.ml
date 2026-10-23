let operations =
  [ Operation.make
      "signoff.route_checks"
      Check
      "Post-route checks"
      "Detailed routing database"
      "Checked routing database"
  ; Operation.make
      "signoff.extract"
      Transform
      "Fill and parasitic extraction"
      "Checked routing database"
      "Filled database and parasitics"
  ; Analysis.Timing.post_pnr
  ]
;;
