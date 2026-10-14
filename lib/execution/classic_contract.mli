(** Pure discoverable selected-backend contracts. These are planned occurrences,
    not observed execution or new restart boundaries. *)
val inventory : unit -> Identity_json.t
val validate_inventory : Identity_json.t -> (unit, string) result
val validate_settings : Identity_json.t -> (unit, string) result
val groups : unit -> Identity_json.t
val sequence : Hardcaml_asic.Flow.Stage.t list -> Identity_json.t
