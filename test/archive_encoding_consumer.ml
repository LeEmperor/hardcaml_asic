open Hardcaml_asic_execution
let limits : Evidence_tar.limits =
  { max_members=100; max_member_bytes=1073741824L; max_tar_bytes=1100000000L
  ; max_pax_bytes=65536; max_name_bytes=16384 }
let () =
  try
    let mode=Sys.argv.(1) and gzip=Sys.argv.(2) and scratch=Sys.argv.(3)
    and output=Sys.argv.(4) in
    let runtime : Archive_encoding.runtime = {gzip;scratch;timeout=float_of_string Sys.argv.(5)} in
    let rec args i acc = if i=Array.length Sys.argv then List.rev acc else
      args (i+3) ((Sys.argv.(i),Sys.argv.(i+1),Sys.argv.(i+2))::acc) in
    let entries=args 6 [] in
    let expected=List.map (fun (n,_,h) -> n,h) entries in
    let sources=List.map (fun (name,path,h) : Evidence_tar.source -> {name;path;sha256=Some h}) entries in
    let members = match mode with
      | "bundle" -> Archive_encoding.write_input_bundle ~runtime ~output ~manifest:(List.hd sources) ~files:(List.tl sources)
      | "reports" -> Archive_encoding.write ~runtime ~normalized:false ~output sources
      | "verify" | "verify-reports" -> Archive_encoding.verify ~runtime ~limits ~normalized:(mode="verify") ~expected output
      | "verify-small" -> Archive_encoding.verify ~runtime ~limits:{limits with max_tar_bytes=2048L} ~normalized:true ~expected output
      | "verify-pax" -> Archive_encoding.verify ~runtime ~limits:{limits with max_pax_bytes=8} ~normalized:true ~expected output
      | "verify-name" -> Archive_encoding.verify ~runtime ~limits:{limits with max_name_bytes=8} ~normalized:true ~expected output
      | "verify-size" -> Archive_encoding.verify ~runtime ~limits:{limits with max_member_bytes=0L} ~normalized:true ~expected output
      | "verify-count" -> Archive_encoding.verify ~runtime ~limits:{limits with max_members=0} ~normalized:true ~expected output
      | "verify-input" -> Archive_encoding.verify_input_bundle ~runtime ~limits
          ~manifest_sha256:(List.assoc "manifest.json" expected)
          ~inventory:(List.filter (fun (n,_) -> n<>"manifest.json") expected) output
      | _ -> failwith "unknown mode" in
    List.iter (fun (m:Evidence_tar.member) -> Printf.printf "%s\t%Ld\t%s\n" m.name m.bytes m.sha256) members
  with
  | Archive_encoding.Gzip_failed (r,stderr) ->
    let outcome=match r.outcome with
      | Process_supervisor.Exited n -> "exit "^string_of_int n
      | Timed_out -> "timeout" | Cancelled _ -> "cancelled" | Signaled _ -> "signal"
      | Failed s -> "failed "^s in
    prerr_endline (outcome^": "^stderr); exit 2
  | exn -> prerr_endline (Printexc.to_string exn); exit 2
