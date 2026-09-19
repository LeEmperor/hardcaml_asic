(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "tt_cmos5l.ml" *)
(* Source implementation of the Tiny Tapeout CMOS5L template. The template is the answer
   to "what does every TT CMOS5L design have to say the same way, and what does it get to
   decide?";

   Nothing in the library calls into this module. A consumer's declaration does:
   [I] and [O] become the design's own interfaces, so the ports Resolved_build.
   validate_interface checks are the ports the design was written against; [overrides]
   builds the Flow.Librelane.Override.t list that Project.create takes as [~flow], where
   Flow.Librelane.validate checks it and Resolved_build.resolve_settings merges it over
   the derived settings; [synchronised_reset] and [gate] are built inside the design's
   own [create], like any other Hardcaml combinator.

   WHY the overrides are values here rather than settings Resolved_build derives: they
   are the pinned template's tuning, not facts the declaration knows. A project that
   disagrees with one replaces it through [overrides] and its own [reason] is what the
   manifest records; a project that disagrees with a derived setting cannot, because
   every derived key is protected. Keeping the split is what lets the manifest say which
   values the library chose and which the consumer did.

   It does NOT validate anything. A key here is an ordinary override: Flow.Librelane.
   validate checks its shape at declaration time and Resolved_build.protected_key refuses
   it if it collides with a derived setting, and both of those run on a library default
   exactly as they would on a consumer's. It does NOT know the die, the clock or the
   pinout either; those come from Target, Clock and Pinout.
*)

open! Core
open! Hardcaml

[@@@ocamlformat "disable"]

(* The ttihp-verilog-template commit the values below were read out of; the same commit
   the two hand-copied override lists this module replaces were citing;
*)
let template_revision = "b86a2a781484bcab7ba522dc5de540086695a430"

(* The Tiny Tapeout user-module inputs; the TT template's ports, in its order;

   Resolved_build.expected_inputs is the same list of (name, width) pairs, and
   Resolved_build.validate_interface refuses anything else, so this is not a convenience
   spelling of the ports, it is the only spelling that resolves.

   Careful: [ena] and [rst_n] are phantom inputs for a design that ignores them. They are
   still ports of the emitted wrapper, and a timing delay may be declared on them; see
   Resolved_build.ports.
*)
module I = struct
  type 'a t =
    { ui_in  : 'a [@bits 8]
    ; uio_in : 'a [@bits 8]
    ; ena    : 'a
    ; clk    : 'a
    ; rst_n  : 'a
    }
  [@@deriving hardcaml]
end

(* The Tiny Tapeout user-module outputs; fixed the same way [I] is, and checked against
   Resolved_build.expected_outputs;
*)
module O = struct
  type 'a t =
    { uo_out  : 'a [@bits 8]
    ; uio_out : 'a [@bits 8]
    ; uio_oe  : 'a [@bits 8]
    }
  [@@deriving hardcaml]
end

(* [why] with the template revision appended, as one override's [reason];

   Every default says what the setting does and, where there is one, what would go wrong
   without it, then names the revision the value came from. Both halves are needed: the
   revision alone is what the two copied lists said, and it does not survive being read
   out of a manifest six months later; the explanation alone loses the provenance.
*)
let reason why = why ^ "; ttihp-verilog-template " ^ template_revision

(* The template's twenty LibreLane settings, in its src/config.json order;

   The template's four other settings are absent because the declaration owns them:
   CLOCK_PORT and CLOCK_PERIOD come from the project's Clock and are protected keys,
   FP_SIZING and RUN_LINTER are Resolved_build Default settings an override may replace.

   Values are exactly the template's. The two KLayout settings are the only ones this
   library keeps as a decision of its own rather than an inherited value, and their
   reasons say so; everything else is the template's tuning for a CMOS5L tile, restated
   here so it is read rather than copied.
*)
let template_overrides : Flow.Librelane.Override.t list =
  List.map
    ~f:(fun (key, value, why) ->
      { Flow.Librelane.Override.key; value; reason = reason why })
    [ "PL_TARGET_DENSITY_PCT", `Int 60
    , "global placement fills 60% of the core area, leaving room for the hold repair \
       buffers and the clock tree that the resizers and CTS add after it"

    ; "PL_RESIZER_HOLD_SLACK_MARGIN", `Float 0.1
    , "post placement hold repair targets 0.1 ns of slack instead of zero, so hold is \
       still met once CTS and routing replace the placement estimates"

    ; "GRT_RESIZER_HOLD_SLACK_MARGIN", `Float 0.05
    , "post global route hold repair targets 0.05 ns; lower than the placement margin \
       because routing estimates are in hand by then and the buffers cost area"

    ; "LINTER_INCLUDE_PDK_MODELS", `Int 1
    , "lint with the PDK cell models in scope, so a standard cell the netlist \
       instantiates is not reported as an undefined module"

    ; "RUN_KLAYOUT_XOR", `Int 0
    , "off: the XOR compares the Magic and KLayout GDS streams for tool disagreement, \
       which is not a rule check and is not what TT precheck repeats; set it to 1 to \
       have the flow catch a streamer disagreement itself"

    ; "RUN_KLAYOUT_DRC", `Int 0
    , "off: TT precheck runs the same KLayout decks over the submitted GDS after the \
       flow (478.64s, zero items on 2026-09-18), so in flow DRC buys about eight \
       minutes of duplicate coverage; the cost is that LibreLane records no \
       klayout__drc_error__count, so collect reports no KLayout metric; set it to 1 \
       when signoff has to be self contained"

    ; "DESIGN_REPAIR_BUFFER_OUTPUT_PORTS", `Int 0
    , "design repair does not put a buffer on every top level output; on a fixed TT tile \
       those buffers spend core area on a load OUTPUT_CAP_LOAD already states to timing \
       analysis"

    ; "TOP_MARGIN_MULT", `Int 1
    , "core area is inset from the top die edge by one standard cell row height"

    ; "BOTTOM_MARGIN_MULT", `Int 1
    , "core area is inset from the bottom die edge by one standard cell row height"

    ; "LEFT_MARGIN_MULT", `Int 6
    , "core area is inset from the left die edge by six site widths; wider than the \
       vertical insets, keeping the cell rows clear of the tile boundary it abuts"

    ; "RIGHT_MARGIN_MULT", `Int 6
    , "core area is inset from the right die edge by six site widths, matching the left \
       inset so the core stays centred in the tile"

    ; "GRT_ALLOW_CONGESTION", `Int 1
    , "global routing reports congestion instead of failing the run; the die is fixed by \
       the TT tile, so there is no floorplan to grow in response, and detailed routing \
       is what decides whether the congestion was real"

    ; "FP_IO_HLENGTH", `Int 2
    , "horizontal I/O pin shapes reach 2 um into the core, far enough for the router to \
       land on a pin placed by the tile's DEF template"

    ; "FP_IO_VLENGTH", `Int 2
    , "vertical I/O pin shapes reach 2 um into the core; the TT block DEF places this \
       tile's signal pins on its top edge, so this is the one that carries them"

    ; "FP_PDN_VPITCH", `Float 50.0
    , "vertical power straps every 50 um; with FP_PDN_VWIDTH this is how much routing \
       resource the power grid takes out of the tile"

    ; "FP_PDN_VWIDTH", `Float 2.1
    , "vertical power straps are 2.1 um wide, the width the TT tile's power grid is cut \
       for at the 50 um pitch above"

    ; "RUN_CTS", `Int 1
    , "run clock tree synthesis; this is LibreLane's own default, stated explicitly so a \
       change to that default cannot silently leave the design on the ideal clock net \
       synthesis assumed"

    ; "FP_PDN_MULTILAYER", `Int 0
    , "single layer power distribution; a multilayer PDN puts straps on TopMetal1, which \
       TT precheck forbids inside a tile"

    ; "MAGIC_DEF_LABELS", `Int 0
    , "Magic streams the GDS without copying the DEF's labels into it; the tile's pins \
       travel in the LEF that MAGIC_WRITE_LEF_PINONLY produces, not as GDS text"

    ; "MAGIC_WRITE_LEF_PINONLY", `Int 1
    , "Magic writes a pin only LEF for the tile, with no internal obstructions; that is \
       the abstract the TT top level abuts, and it describes the tile as its pins"
    ]
;;

(* The main sauce here for the template; the defaults with a consumer's changes merged
   over them by key;

   1. [without] names a key that is not a default -> raise, every one reported together;
   2. [without] and [extra] name the same key -> raise, likewise;
   3. drop every default whose key is in [without] or is set by [extra];
   4. append [extra].

   Raises rather than returning Or_error since a project's override list is a module
   level value in its declaration file, where there is nothing to thread an error
   through; the same reason Technology.create_exn raises. Step 1 exists because the
   alternative is silent: "RUN_KLAYOUT_DRC " with a stray space would drop nothing and
   leave the default in the bundle.

   A key repeated inside [extra] is NOT checked; Flow.Librelane.validate reports it when
   Project.create runs, with the same message a hand written list would get.
*)
let overrides ?(without = []) ?(extra = []) () =

  let key (o : Flow.Librelane.Override.t) = o.key in
  let extra_keys = List.map extra ~f:key in

  (* Step 1 *)
  let unknown =
    List.filter without ~f:(fun k ->
      not (List.mem (List.map template_overrides ~f:key) k ~equal:String.equal))
  in

  (* Step 2 *)
  let contradicted =
    List.filter without ~f:(fun k -> List.mem extra_keys k ~equal:String.equal)
  in

  if not (List.is_empty unknown)
  then
    raise_s
      [%message
        "no TT CMOS5L template default has this key; drop it from [without], or pass it \
         in [extra] to set a key the template does not"
          (unknown : string list)];

  if not (List.is_empty contradicted)
  then
    raise_s
      [%message
        "a key cannot be both dropped and set; keep it in [extra] alone, which already \
         replaces the template default"
          (contradicted : string list)];

  (* Steps 3 and 4 *)
  List.filter template_overrides ~f:(fun o ->
    not
      (List.mem without o.key ~equal:String.equal
       || List.mem extra_keys o.key ~equal:String.equal))
  @ extra
;;

(* The TT wrapper's reset idiom; an active high core reset, asserted asynchronously with
   [rst_n] and released [stages] rising edges after it;

   A chain of [stages] bits, reset to all ones and shifting a zero in at the bottom
   towards the top; the top bit is the result, so it stays high for [stages] edges after
   the asynchronous reset releases. The harness drives [rst_n] with no relation to
   [clock], so a core released straight from it can resolve a metastable release in one
   flop and not another, leaving parts of the design a cycle apart.

   Raises rather than returning Or_error since this is called inside a design
   constructor, where an Or_error would have to be threaded through every level of the
   hierarchy; the same reason Single_port_ram.create raises. [stages] below 2 is the only
   failure: one stage resynchronises nothing, and accepting it would build exactly the
   flop this function exists to avoid.
*)
let synchronised_reset ?(stages = 2) ~clock ~rst_n () =

  if stages < 2
  then
    raise_s
      [%message
        "a reset synchroniser needs at least two stages; one stage resynchronises \
         nothing"
          (stages : int)];

  let open Signal in

  (* All ones at reset, a zero shifted up per edge; [previous] drops its top bit *)
  let chain =
    reg_fb
      (Reg_spec.create ~clock ~reset:((~:) rst_n) ())
      ~reset_to:(Bits.of_int_trunc ~width:stages (-1))
      ~width:stages
      ~f:(fun previous ->
        concat_msb [ select previous ~high:(stages - 2) ~low:0; zero 1 ])
  in

  bit chain ~pos:(stages - 1)
;;

(* The other half of the TT wrapper idiom; [signal] while [enable] is high, zero
   otherwise;

   Every design on the die shares the pins, so one that is not selected ([ena] low), or
   is still in reset, has to drive zeros rather than whatever its core happens to hold.

   One gate per output on purpose, rather than one call gating a whole O.t: the three
   outputs are not always gated on the same condition, and a design that holds uo_out low
   through its core reset but lets the bidirectional pins follow [ena] alone would have
   to unpick a combined version.
*)
let gate ~enable signal = Signal.mux2 enable signal (Signal.zero (Signal.width signal))

[@@@ocamlformat "enable"]
