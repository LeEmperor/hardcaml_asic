open Hardcaml_asic_execution
let checked = function Ok x -> x | Error e -> invalid_arg e
let () =
  try
    let args=Array.to_list Sys.argv |> List.tl in
    let result=match args with
      | ["variant"] ->
        let module H=Hardcaml_asic.Hardware_variant in
        let parameter=Core.Or_error.ok_exn (H.Parameter.create ~key:"depth" ~kind:(Integer {minimum=128;maximum=256})) in
        let schema=Core.Or_error.ok_exn (H.Schema.create ~design_id:"memory" ~schema_id:"memory.v1" ~parameters:[parameter]) in
        H.to_yojson (Core.Or_error.ok_exn (H.create ~schema ~assignments:["depth",H.Value.Int 256]))
      | ["collect";p] -> Collect_service.to_json (Collect_service.collect p)
      | ["report";p] ->
        let r=Report_service.run ~render_human:false p in
        `Assoc ["accepted",`Bool (Report_service.accepted r.verdict);"metadata",`List r.metadata_sources;"results",r.results]
      | ["archive-inspect";p] ->
        let r=Archive_service.inspect ~run_dir:p in
        `Assoc ["bundle_source",`String r.bundle_source;"members",`Int (List.length r.bundle_files)]
      | ["read-regular";p] -> `String (Retained_file.read p)
      | ["metric";p] ->
        let j=Evidence_json.value (Evidence_json.read p) in
        let get k=match j with `Assoc xs -> List.assoc k xs | _ -> assert false in
        Variant_comparison.compare_metric ~axis:(checked (Variant_comparison.axis (match get "axis" with `String s -> s | _ -> assert false)))
          ~left:(get "left") ~right:(get "right")
      | [axis;lk;lp;rk;rp] ->
        checked (Variant_comparison.inspect ~axis:(checked (Variant_comparison.axis axis))
          ~left:(checked (Variant_comparison.target ~kind:lk ~path:lp))
          ~right:(checked (Variant_comparison.target ~kind:rk ~path:rp)) ())
      | _ -> invalid_arg "arguments" in
    print_endline (Evidence_json.record_bytes result)
  with Invalid_argument e | Failure e | Sys_error e -> prerr_endline e;exit 2
    | Unix.Unix_error (e,f,p) -> prerr_endline (f^" "^p^": "^Unix.error_message e);exit 2
