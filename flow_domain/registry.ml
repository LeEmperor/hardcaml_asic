let operations = function
  | Stage_id.Synthesis -> Stages.Synthesis.Recipe.operations
  | Floorplan -> Stages.Floorplan.Recipe.operations
  | Placement -> Stages.Placement.Recipe.operations
  | Cts -> Stages.Cts.Recipe.operations
  | Routing -> Stages.Routing.Recipe.operations
  | Timing -> Stages.Timing.Recipe.operations
  | Signoff -> Stages.Signoff.Recipe.operations
;;

let restart_targets = function
  | Stage_id.Synthesis -> [ Stage_id.Floorplan; Placement ]
  | Floorplan -> [ Stage_id.Placement ]
  | Placement -> [ Stage_id.Cts ]
  | Cts -> [ Stage_id.Routing ]
  | Routing -> [ Stage_id.Timing ]
  | Timing -> [ Stage_id.Signoff ]
  | Signoff -> []
;;
