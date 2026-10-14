open Hardcaml_asic_execution
let () =
  let bytes = input_line stdin in
  let value = match Evidence_json.parse bytes with Ok d -> Evidence_json.value d | Error s -> failwith s in
  let get k = match value with `Assoc xs -> Option.value (List.assoc_opt k xs) ~default:`Null | _ -> assert false in
  let output = match get "operation" with
    | `String "metric" ->
      let result=Collect_service.metric ~value:(get "value") ~reason:(get "reason")
        ~unit_:"count" ~definition:"fixture" ~stage:"fixture" ~source:"fixture" () in
      Collect_service.metric_json result
    | `String "decode" ->
      let raw=match get "raw" with `String s -> s | _ -> assert false in
      let d=match Evidence_json.parse raw with Ok d -> d | Error s -> failwith s in
      assert (Evidence_json.raw_bytes d=raw); Evidence_json.value d
    | _ ->
      let run=match get "run_dir" with `String s -> s | _ -> assert false in
      let context=match get "context" with `Null -> None | x -> Some x in
      let synthesis_state=match get "synthesis_state" with `String s -> Some s | _ -> None in
      Collect_service.collect ?context ?synthesis_state run |> Collect_service.to_json in
  print_string (Evidence_json.record_bytes output)
