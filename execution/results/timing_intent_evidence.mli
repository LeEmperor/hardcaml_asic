(** Bounded, read-only inspection of a standalone retained synthesized-netlist STA
    audit. Does not launch tools, discover runs, write summaries, or qualify normal
    flow/post-PNR integration. All input and report bytes are retained and hash
    checked. Successful exception commands are distinguished from native
    path-effect coverage; unavailable coverage never yields a passing verdict.
    Checks the supported schema-1 bundle envelope's structural fields and selected
    cross-links (including RTL source roles, runtime policy and floorplan reference),
    not re-resolution of the project or target/base-clock-policy compatibility.
    Hashes the entire
    SDC against its identity-bound file entry; PT7 Tcl suffix replay is additional,
    not reconstruction of the whole base-SDC policy. Log processing retains only
    bounded receipt/wire state (65,536 lines, 64 KiB/line, 1,028 events/2 MiB wire).

    The producer contract is [docs/development/pt7-evidence-handoff.md]. Sources
    must not be mutated concurrently with inspection. Receipts are source-replayed
    producer assertions, not authenticated execution attestations. *)
val inspect : directory:string -> unit -> (Evidence_json.t, string) result
