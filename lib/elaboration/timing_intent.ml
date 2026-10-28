open! Core
open! Hardcaml
module T = Platform.Timing

type stage = { declaration : T.Stage.t; anchor : string; has_async : bool }
type t = { stages : stage list; exceptions : T.Exception.t list }

let identifier s =
  let first c = Char.is_alpha c || Char.equal c '_' in
  not (String.is_empty s) && first s.[0]
  && String.for_all s ~f:(fun c -> Char.is_alphanum c || Char.equal c '_')
  && String.for_all s ~f:(fun c -> Char.to_int c < 128)
;;

let fail s = invalid_arg ("timing intent: " ^ s)
let require condition message = if not condition then fail message
let same a b = Signal.Type.Uid.equal (Signal.uid a) (Signal.uid b)
let rec unwire = function
  | Signal.Type.Wire { driver = Some d; _ } -> unwire d
  | s -> s
;;

let resolve ~circuit ~(timing : T.t) ~registrations = Or_error.try_with (fun () ->
  if List.is_empty timing.stages && List.is_empty timing.exceptions
     && List.is_empty registrations then None
  else (
    let unique label names =
      require (Option.is_none (List.find_a_dup names ~compare:String.compare))
        (label ^ " declared more than once") in
    let declared = List.sort timing.stages ~compare:(fun a b -> String.compare a.id b.id) in
    unique "stage ID" (List.map declared ~f:(fun s -> s.id));
    List.iter declared ~f:(fun s ->
      require (identifier s.id && identifier s.chain && s.index >= 0)
        "stage IDs/chains must be ASCII identifiers and indices nonnegative");
    require (List.length declared = List.length registrations) "declared/registered stage inventory differs";
    let q (s : T.Stage.t) =
      match List.filter registrations ~f:(fun (r, _) -> T.Stage.equal r s) with
      | [_, q] -> q
      | _ -> fail ("stage missing or ambiguous registration: " ^ s.id) in
    let inputs = Circuit.inputs circuit in
    let input name =
      match List.filter inputs ~f:(fun s -> List.mem (Signal.names s) name ~equal:String.equal) with
      | [s] -> s
      | _ -> fail ("input missing or ambiguous in actual circuit: " ^ name) in
    let clock = input "clk" in
    let reg s = match q s with
      | Signal.Type.Reg r when Signal.width (q s) = 1 -> r
      | _ -> fail ("stage is not a scalar register: " ^ s.id) in
    let graph = Circuit.signal_graph circuit in
    let signals = Signal_graph.filter graph ~f:(fun _ -> true) in
    let stages = List.map declared ~f:(fun s ->
      let signal = q s in
      require (List.exists signals ~f:(same signal)) ("registered Q absent from circuit: " ^ s.id);
      let r = reg s in
      require (same (unwire r.register.clock.clock) (unwire clock)
        && Hardcaml.Edge.equal r.register.clock.clock_edge Rising)
        ("stage must use rising primary clk: " ^ s.id);
      require (Option.is_none r.register.enable && Option.is_none r.register.clear)
        ("stage enable/clear is unsupported: " ^ s.id);
      require (List.exists (Signal.attributes signal) ~f:(fun a ->
        String.equal (Rtl_attribute.name a) "keep"
        && Option.value_map (Rtl_attribute.value a) ~default:false ~f:(function Int 1 -> true | _ -> false)))
        ("stage lacks registered keep=1 intent: " ^ s.id);
      let raw = T.Stage.anchor s in
      require (List.count signals ~f:(fun node -> List.mem (Signal.names node) raw ~equal:String.equal) = 1)
        ("reserved anchor is missing or ambiguous: " ^ raw);
      let names = Circuit.Name_for_rtl.internal_signal_exn circuit signal
        |> List.map ~f:(fun n -> Rtl.Name.legalize n ~language:Verilog |> Rtl.Name.For_backend.to_string) in
      require (List.mem names raw ~equal:String.equal)
        ("reserved anchor was mangled; remove conflicting names: " ^ raw);
      { declaration = s; anchor = raw; has_async = Option.is_some r.register.reset }) in
    unique "registered Q" (List.map stages ~f:(fun s -> s.anchor));
    let chains = List.dedup_and_sort (List.map declared ~f:(fun s -> s.chain)) ~compare:String.compare in
    List.iter chains ~f:(fun chain ->
      let ss = List.filter declared ~f:(fun s -> String.equal s.chain chain)
        |> List.sort ~compare:(fun a b -> Int.compare a.index b.index) in
      require (List.length ss >= 2) "a synchronizer chain requires at least two declared stages";
      List.iteri ss ~f:(fun index s ->
        require (s.index = index) "chain stage indices must be unique and contiguous from zero";
        if index > 0 then
          require (same (unwire (reg s).d) (unwire (q (List.nth_exn ss (index - 1)))))
            ("downstream data must be previous stage Q: " ^ s.id)));
    let source (p : T.Port.t) =
      require (T.Port.equal_direction p.direction Input && not (String.equal p.port "clk"))
        "exception source must be a nonclock input";
      (* Names are literal. Restrict ports to the checked TT interface; no Tcl patterns. *)
      let signal = input p.port in
      (match p.bit with
       | None -> require (Signal.width signal = 1) "bus exception source needs one explicit bit"
       | Some bit -> require (Signal.width signal > 1 && bit >= 0 && bit < Signal.width signal)
           "exception source bit is out of range or selects a scalar");
      signal in
    let matches_source p candidate =
      let signal = source p in
      let candidate = unwire candidate in
      match p.T.Port.bit, candidate with
      | None, _ -> same (unwire signal) candidate
      | Some bit, Signal.Type.Select { arg; high; low; _ } ->
        high = bit && low = bit && same (unwire arg) (unwire signal)
      | _ -> false in
    let exceptions = List.sort timing.exceptions ~compare:(fun a b -> String.compare a.id b.id) in
    unique "exception ID" (List.map exceptions ~f:(fun e -> e.id));
    let scopes = ref [] in
    List.iter exceptions ~f:(fun e ->
      require (identifier e.id && not (String.is_empty (String.strip e.reason)))
        "exception requires an ASCII ID and nonblank reason";
      ignore (source e.source : Signal.t);
      require (not (List.is_empty e.targets)) "reset exception needs explicit targets";
      unique "exception target" (List.map e.targets ~f:(fun s -> s.id));
      List.iter e.targets ~f:(fun s ->
        require (List.exists declared ~f:(T.Stage.equal s)) "exception target is not declared";
        let scope = T.Exception.kind_string e.kind ^ "/" ^ s.id in
        require (not (List.mem !scopes scope ~equal:String.equal)) "overlapping exception target scope";
        scopes := scope :: !scopes;
        let r = reg s in
        match e.kind with
        | Async_capture ->
          require (List.length e.targets = 1 && s.index = 0) "async capture must target one first stage";
          require (matches_source e.source r.d) "capture data does not match declared source"
        | Async_reset ->
          match r.register.reset with
          | None -> fail ("reset exception target has no asynchronous control: " ^ s.id)
          | Some reset ->
            require (match reset.reset_to with
              | Signal.Type.Const { constant; _ } -> Bits.equal constant (Bits.zero 1)
              | _ -> false)
              "supported mapped async control resets to zero only";
            let control = unwire reset.reset in
            require ((matches_source e.source control)
              || (match control with Signal.Type.Not { arg; _ } -> matches_source e.source arg | _ -> false))
              "reset control does not match declared input or its inversion";
            let external_active_low =
              if matches_source e.source control then Hardcaml.Level.equal reset.reset_level Low
              else Hardcaml.Level.equal reset.reset_level High in
            require external_active_low
              "unsupported reset polarity: enumerated RESET_B scope requires an externally active-low source"));
    Some { stages; exceptions }))
;;

let str s = `String s
let to_json t =
  `Assoc [ "contract", str "hardcaml-asic.timing-intent"; "schema_version", `Int 1;
    "resolution_policy", str "scalar-q-driver-cmos5l-v1";
    "stages", `List (List.map t.stages ~f:(fun s -> `Assoc [
      "id", str s.declaration.id; "chain", str s.declaration.chain; "index", `Int s.declaration.index;
      "anchor", str s.anchor; "preservation", str "yosys_keep_1"]));
    "exceptions", `List (List.map t.exceptions ~f:(fun e -> `Assoc [
      "id", str e.id; "kind", str (T.Exception.kind_string e.kind); "reason", str e.reason;
      "source", `Assoc ["direction", str "input"; "port", str e.source.port;
        "bit", Option.value_map e.source.bit ~default:`Null ~f:(fun i -> `Int i)];
      "targets", `List (List.map (List.sort e.targets ~compare:(fun a b -> String.compare a.id b.id)) ~f:(fun s -> str s.id))]));
    "sdc", str "constraints/top.sdc" ]
;;

let sdc t = Timing_tcl.render
  ~stages:(List.map t.stages ~f:(fun s -> s.declaration, s.anchor, s.has_async))
  ~exceptions:t.exceptions
