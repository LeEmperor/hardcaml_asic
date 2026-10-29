let validate = function
  | `Assoc fields ->
    (match List.filter (fun (k,_) -> k="hardware_variant") fields with
     | [] -> ()
     | [_,value] ->
       (* Evidence_json deliberately uses Intlit even for small integer tokens.
          Decode their exact JSON bytes with the strict main-library codec; never
          round through floats or weaken the hardware assignment grammar. *)
       (match Hardcaml_asic.Hardware_variant.of_string (Evidence_json.record_bytes value) with
        | Ok _ -> ()
        | Error e -> invalid_arg ("invalid hardware_variant: "^Core.Error.to_string_hum e))
     | _ -> invalid_arg "duplicate hardware_variant")
  | _ -> invalid_arg "bundle manifest must be an object"
