open Hardcaml_asic_execution
module J = Identity_json
module O = Observation
let get j k = match j with J.Object xs -> List.assoc k xs | _ -> failwith "object"
let str = function J.String s -> s | _ -> failwith "string"
let integer = function J.Integer s -> int_of_string s | _ -> failwith "integer"
let opt f = function J.Null -> None | j -> Some (f j)
let obj xs = match J.object_ xs with Ok j -> j | Error e -> failwith (J.error_message e)
let reader = ref None
let prefix = ref O.empty
let output = function Ok j -> obj ["ok",j] | Error e -> O.error_json e
let command j = match str (get j "op") with
  | "open" -> (match O.Reader.create ?stream_id:(opt str (get j "stream")) ?after:(opt integer (get j "after")) (str (get j "directory")) with
    | Error e -> Error e | Ok r -> reader:=Some r; O.snapshot (O.Reader.prefix r) ~writer_active:None)
  | "poll" -> (match O.Reader.poll (Option.get !reader) with Error e -> Error e | Ok (u,s) -> Ok (obj ["updates",u;"status",s]))
  | "reset" -> prefix:=O.empty;Ok J.null
  | "append" ->
    let old = !prefix in
    let old_state = Option.map (fun s -> J.canonical (O.state_json s)) (O.state old) in
    (match O.append_record old (get j "record") with
    | Error e -> Error e
    | Ok p ->
      prefix:=p;
      assert (old_state = Option.map (fun s -> J.canonical (O.state_json s)) (O.state old));
      (* Independently exercise the exported event/reducer/serializer boundary. *)
      let r=List.hd (List.rev (O.records p)) in
      let name,data=O.event_to_json r.event in
      let round=match O.event_of_json ~name data with Ok e->e|Error _->failwith "event roundtrip" in
      let reduced=match O.reduce_event (O.state old) ~stream_id:r.stream_id round with
        | Ok s -> s | Error _ -> failwith "reducer roundtrip" in
      assert (J.canonical (O.state_json reduced) = J.canonical (O.state_json (Option.get (O.state p))));
      let _,again=O.event_to_json round in
      assert (J.canonical data=J.canonical again);
      O.snapshot p ~writer_active:(opt (function J.Bool b->b|_->failwith "bool") (get j "active")))
  | "updates" -> O.updates !prefix ~stream_id:(str (get j "stream")) ~after:(integer (get j "after"))
  | "state" -> Ok (match O.state !prefix with None->J.null|Some s->O.state_json s)
  | _ -> failwith "unknown operation"
let () = try while true do
  let line=read_line () in
  let j=match J.parse line with Ok j->j|Error e->failwith (J.error_message e) in
  print_endline (J.canonical (output (command j)))
done with End_of_file -> ()
