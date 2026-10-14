(** Domain-only registry. It depends on stage IDs and stage modules, never the
    public Flow facade, execution layer or backend mapping. *)
val operations : Stage_id.t -> Operation.t list
val restart_targets : Stage_id.t -> Stage_id.t list
