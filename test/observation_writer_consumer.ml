open Hardcaml_asic_execution
module J = Identity_json
let get j k = match j with J.Object xs -> List.assoc k xs | _ -> failwith "object"
let text = function J.String x -> x | _ -> failwith "string"
let emit j = print_endline (J.canonical j); flush stdout
let () =
  try
    let request = match J.object_ [] with Ok x -> x | Error _ -> assert false in
    let timing = Array.length Sys.argv > 3 in
    let time = ref 0. in
    let clock () = time := !time +. 0.125; !time in
    let wall () = 1700000000.125 -. !time in
    let w = Observation_writer.create ?clock:(if timing then Some clock else None)
      ?wall_clock:(if timing then Some wall else None) ~root:Sys.argv.(1) ~workspace:Sys.argv.(2)
      ~checkpoint_store:(Sys.argv.(2) ^ "/checkpoints") ~request () in
    Fun.protect ~finally:(fun () -> Observation_writer.close w) (fun () ->
      emit (Observation_writer.allocation_receipt w);
      let rec loop () = match input_line stdin with
        | "close" -> Observation_writer.close w; print_endline "closed"; flush stdout
        | line ->
          (try let j = match J.parse line with Ok x -> x | Error e -> failwith (J.error_message e) in
            Observation_writer.append w ~name:(text (get j "event")) (get j "data"); print_endline "ok"
           with e -> print_endline ("error: " ^ Printexc.to_string e));
          flush stdout; loop ()
        | exception End_of_file -> () in loop ())
  with e -> prerr_endline (Printexc.to_string e); exit 2
