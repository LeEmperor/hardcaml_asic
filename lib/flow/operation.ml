type effect = Transform | Analyze | Check
type t =
  { key : string
  ; description : string
  ; effect : effect
  ; precondition : string
  ; postcondition : string
  }

let make key effect description precondition postcondition =
  { key; effect; description; precondition; postcondition }
