(* Coarse association remains a distinct adapter. The native linked-analysis
   verifier is shared with named execution without manufacturing a coarse record. *)
let expected manifest = Timing_intent_linked.expected manifest || Timing_physical_flow.enabled manifest
let physical ~run_dir =
  (* Either immutable marker or persisted expectation selects the new reader.
     Removal cannot downgrade advertised evidence to historical synthesis. *)
  let record=Timing_intent_linked.read (run_dir^"/run.json") in
  let manifest=Timing_intent_linked.read (run_dir^"/project/manifest.json") in
  Timing_physical_flow.enabled manifest || Timing_intent_linked.get record "timing_physical_expected"=`Bool true
let inspect ~run_dir () =
  match Timing_intent_linked.protect (fun () -> physical ~run_dir) with
  | Error e -> Error e
  | Ok true -> Timing_physical_flow.inspect ~run_dir ()
  | Ok false -> Timing_intent_linked.inspect ~run_dir ()
let source_files ~run_dir ~context () =
  if Timing_intent_linked.get context "timing_physical_expected"=`Bool true ||
     Timing_physical_flow.enabled (Timing_intent_linked.read (run_dir^"/project/manifest.json"))
  then Timing_physical_flow.source_files ~run_dir ~context ()
  else Timing_intent_linked.source_files ~run_dir ~context ()
let publish ~run_dir ~context ~succeeded () =
  if Timing_intent_linked.get context "timing_physical_expected"=`Bool true then
    Timing_physical_flow.publish ~run_dir ~context ~succeeded ()
  else Timing_intent_linked.publish ~run_dir ~context ~succeeded ()
