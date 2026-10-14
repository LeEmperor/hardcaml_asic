module J = Identity_json
module S = Execution_plan.Stage
type t = { raw:J.t; plan:Execution_plan.Stage_plan.t; occurrences:J.t list;
           references:J.t list; status:string }
let get j k = match j with J.Object xs -> Option.value (List.assoc_opt k xs) ~default:J.null | _ -> J.null
let text = function J.String s -> s | _ -> invalid_arg "execution: expected string"
let array = function J.Array xs -> xs | _ -> invalid_arg "execution: expected array"
let checked = function Ok x -> x | Error e -> invalid_arg e
let codec = function Ok x -> x | Error e -> invalid_arg (J.error_message e)
let code = function J.Integer n -> (try int_of_string n with _ -> invalid_arg "invalid execution exit code")
  | _ -> invalid_arg "invalid execution exit code"
let number = function J.Integer n -> float_of_string n | J.Float f -> f | _ -> invalid_arg "invalid execution duration"
let decode raw =
  let fields = match raw with J.Object xs -> xs | _ -> invalid_arg "expected execution object" in
  if List.exists (fun (k,_) -> not (List.mem k ["attempt_id";"plan";"occurrences";"status";"exit_code";"artifacts"])) fields
  then invalid_arg "not a segmented Runner record";
  let attempt = text (get raw "attempt_id") in
  if attempt="" || String.contains attempt '/' || String.contains attempt '\000' then invalid_arg "invalid execution attempt ID";
  let plan = checked (Execution_plan.Stage_plan.of_json (get raw "plan")) in
  let status = text (get raw "status") and exit = code (get raw "exit_code") in
  if not (match status with "completed"|"running" -> exit=0 | "failed" -> exit>0
    | "interrupted" -> exit>128 && exit<=255 | _ -> false) then invalid_arg "inconsistent execution status/exit";
  let occurrences = array (get raw "occurrences") in
  let actions = Execution_plan.Stage_plan.actions plan in
  if List.length occurrences<>List.length actions then invalid_arg "execution occurrence count/order mismatch";
  let blocked = ref false in
  List.iter2 (fun (a:Execution_plan.Action.t) o ->
    ignore (codec (J.exact_object o ~fields:["occurrence_id";"action_key";"status";"exit_code";"duration_seconds";"best_effort";"error";"verdict"]));
    if text (get o "action_key")<>a.key || text (get o "occurrence_id")<>attempt^"/"^a.key
    then invalid_arg "execution occurrence identity/order mismatch";
    if get o "best_effort"<>J.bool false || get o "verdict"<>J.null then invalid_arg "invalid segmented occurrence verdict/best_effort";
    (match get o "error" with J.Null | J.String _ -> () | _ -> invalid_arg "invalid occurrence error");
    let duration=number (get o "duration_seconds") in
    if not (Float.is_finite duration) || duration<0. then invalid_arg "invalid execution duration";
    let st=text (get o "status") and ex=get o "exit_code" in
    let terminal = match st with
      | "completed" -> ex=codec (J.integer "0")
      | "failed" -> code ex>0
      | "interrupted" -> let n=code ex in n>128 && n<=255
      | "running" | "unreached" -> ex=J.null && duration=0.
      | _ -> false in
    if not terminal then invalid_arg "inconsistent occurrence status/exit/duration";
    if (st="failed" || st="interrupted") && st<>status then invalid_arg "occurrence/outer execution status mismatch";
    if List.mem st ["completed";"running";"unreached"] && get o "error"<>J.null then invalid_arg "unexpected occurrence error";
    if !blocked && st<>"unreached" then invalid_arg "execution occurrences out of order";
    if st<>"completed" then blocked:=true;
    if status="completed" && st<>"completed" then invalid_arg "completed execution has incomplete occurrence") actions occurrences;
  (* Runner persists outer failure/cancellation before finalizing the active
     occurrence after a clock or lifecycle-hook error. Completed records still
     require every occurrence to be completed above. *)
  let references=match List.assoc_opt "artifacts" fields with None -> [] | Some v -> array v in
  let next=ref 0 in
  List.iter (fun r ->
    let boundary=match S.of_string (text (get r "boundary")) with Ok b -> b | Error _ -> invalid_arg "invalid reference boundary" in
    let reference=checked (Runner.reference ~boundary ~path:(text (get r "path")) ~identity:(text (get r "identity"))) in
    if J.canonical r<>J.canonical (Runner.reference_json reference) then invalid_arg "invalid checkpoint reference capabilities";
    let rec locate i = if i>=List.length actions then invalid_arg "checkpoint reference order/association mismatch"
      else let a=List.nth actions i in
        if a.stage=Execution_plan.Action.Physical boundary then i else locate (i+1) in
    let i=locate !next in
    (* Publication can precede an interruption, failed persistence, or the final
       occurrence update. It cannot belong to an unreached stage. *)
    if get (List.nth occurrences i) "status"=codec (J.string "unreached") then invalid_arg "checkpoint reference belongs to unreached occurrence";
    next:=i+1) references;
  List.iter2 (fun (a:Execution_plan.Action.t) o ->
    if get o "status"=codec (J.string "completed") && not (List.exists (fun r ->
      match a.stage with Physical b -> get r "boundary"=codec (J.string (S.to_string b)) | _ -> false) references)
    then invalid_arg "completed stage missing checkpoint publication") actions occurrences;
  {raw;plan;occurrences;references;status}
let protect f = try Ok (f ()) with Invalid_argument s | Failure s -> Error s
let of_json raw = protect (fun () -> decode raw)
let read path = match Result_store.read_json path with
  | Error e -> Error (J.error_message e) | Ok j -> of_json j
