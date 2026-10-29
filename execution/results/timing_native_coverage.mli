(** Bounded, nonexecuting interpretation of retained native state. Resolved rows
    must first pass Timing_intent_evidence's request/resolution/application checks.
    [top] is the identity-verified manifest top. Exactly one matching leading
    native current_design is mandatory. Only native data/profile 2 is supported;
    profile 1 cannot corroborate diagnostic category identity and requires recapture.
    Qualified native SDC is LF-only: any CR byte rejects before tokenization,
    including CRLF or CR inside comments/quoted/braced values. Retained bytes are
    never newline-normalized before hashing or interpretation.
    No renderer replay, file access, tools, or exhaustive path-effect inference. *)
val inspect :
  top:string -> resolved:Evidence_json.t list -> native_sdc:string -> native_data:string ->
  native_checks:string -> native_endpoints:string ->
  (Evidence_json.t, string) result
