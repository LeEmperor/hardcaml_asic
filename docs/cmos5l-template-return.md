# Return: the TT/CMOS5L template module

Answers `docs/cmos5l-template-handoff.md` section "What to hand back". Every
number here came from a command run against this tree on 2026-09-19, not from
reading the diff.

## 1. The new `asic_revision`

**`a257424c3ae31fd6ee10cea052cc7577f15d2677`**, on `main`. This is the revision
to install from; `scaf/tinytapeout/asic-dependencies.lock` has been moved off
`414b7f4f92a201bd9bceb6864579dc3ee475101f` onto it.

`scripts/` is byte-identical between the two revisions (`git diff 414b7f4
a257424 -- scripts/` is empty), so the `Adapted from ... at revision
414b7f4f...` docstrings in `adopted_phase4.py` and `adopted_report.py` still
describe their contents correctly. They were left alone; bumping them to track
the lock is cosmetic and is the consumer's call. `adopted_archive.py` already
points at the lock rather than a literal revision.

One packaging change rides with it: **`ppx_hardcaml` moved from `:with-test` to
a regular dependency** in `dune-project`, because `lib/tt_cmos5l.ml` derives the
wrapper interfaces. `hardcaml_asic.opam` was regenerated. protemu already
depends on `ppx_hardcaml`, so this changes nothing for it, but it is a new
transitive requirement for any other consumer.

## 2. The API surface

Module `Hardcaml_asic.Tt_cmos5l`, in `lib/tt_cmos5l.ml` and `lib/tt_cmos5l.mli`,
beside `flow.ml` / `harness.ml` / `target.ml` as the handoff asked.

```ocaml
val template_revision : string   (* "b86a2a781484bcab7ba522dc5de540086695a430" *)

module I : sig
  type 'a t =
    { ui_in : 'a [@bits 8]; uio_in : 'a [@bits 8]; ena : 'a; clk : 'a; rst_n : 'a }
  [@@deriving hardcaml]
end

module O : sig
  type 'a t = { uo_out : 'a [@bits 8]; uio_out : 'a [@bits 8]; uio_oe : 'a [@bits 8] }
  [@@deriving hardcaml]
end

val template_overrides : Flow.Librelane.Override.t list

val overrides
  :  ?without:string list
  -> ?extra:Flow.Librelane.Override.t list
  -> unit
  -> Flow.Librelane.Override.t list

val synchronised_reset
  :  ?stages:int -> clock:Signal.t -> rst_n:Signal.t -> unit -> Signal.t

val gate : enable:Signal.t -> Signal.t -> Signal.t
```

**How defaults are obtained.** `Tt_cmos5l.overrides ()` is the whole list.
`template_overrides` is the same list exposed for reading, not for editing a
copy of.

**How one default is replaced without restating the rest.** `~extra` replaces by
key and appends anything new; `~without` drops a default so LibreLane's own
default applies instead:

```ocaml
Tt_cmos5l.overrides
  ~extra:
    [ { key = "RUN_KLAYOUT_DRC"; value = `Int 1; reason = "in-flow signoff for tapeout" } ]
  ()
```

`overrides` raises, naming the keys, if `~without` names a key that is not a
template default (a typo cannot silently leave the default in the bundle) or if
`~without` and `~extra` name the same key. A key repeated inside `~extra` is
left to `Flow.Librelane.validate`, which already reports it at `Project.create`.

**How the fixed TT I/O is consumed: two aliases, no functor and no module type
to satisfy.**

```ocaml
module Design = struct
  module I = Tt_cmos5l.I
  module O = Tt_cmos5l.O
  ...
end
```

So `module I` / `module O` shrink from ~25 lines to 2 rather than disappearing.
`Project.Design` requires the two submodules, and a functor would have taken the
design's own `create` as a parameter for no gain while making a design that
wants a different interface harder to write. A test asserts
`Tt_cmos5l.I.port_names_and_widths` equals `Resolved_build.expected_inputs`, so
the two cannot drift apart.

**`Project.create`: no labelled argument changed name or type.** Nothing else in
the library's public surface changed.

## 3. Byte-level verdict on the emitted configuration

What was diffed:

1. `scaf/flow_results/20260918-230920-05f65042/reports.tar.gz` →
   `project/src/config.json`, the file the 2026-09-18 flow actually consumed,
   against the freshly emitted `src/config.json`.
   **Result: `diff` reports no difference. Identical bytes.**
2. The whole bundle emitted before the change against the whole bundle emitted
   after it, both from this working tree. **Result: `src/config.json`,
   `constraints/top.sdc`, `info.yaml`, `src/tt_um_leemperor_hardcaml_protemu.v`
   and `simulation/tt_um_leemperor_hardcaml_protemu.v` are byte-identical.**
   Only the two changed input copies and `manifest.json` differ.

A control run was taken first: the new library with the *old* declaration emits
a bundle identical to the pre-change one in every byte including the identity,
so nothing in the library change moves the output by itself.

Identity moved in two steps, both confined to `source_inputs`:

| Identity | State |
| --- | --- |
| `243496ecf0d7add46f1840f12be8425f8b4c47b66ecc606bc22dc62fa4193d62` | before, declaration and lock untouched |
| `083956e74fe46b8ee532c4007968bbaea492e5583414865cb427b308c4c29c36` | declaration rewritten, lock still on `414b7f4` |
| **`6448596657bac8a0802e8aac28039c0aac12dbb2dc26c19a4b23820e5d7122f1`** | lock pinned to `a257424`; **this is the one to adopt** |

The second step moves nothing but `inputs/tinytapeout/asic-dependencies.lock`
and its manifest entry; `src/config.json` is still byte-identical to the
archived one at that identity, re-checked after the pin.

**`6448596657…` was measured from a dirty protemu tree and will move once
`bin/asic_bundle.ml` and the lock are committed**, because the manifest records
`source_revision` (protemu's HEAD) and each input's `git_status` (` M <path>`
while uncommitted, empty once clean). Re-emit after that commit and take the
identity it prints as the one to adopt. Nothing outside `source_inputs` moves
with it: `src/config.json`, `top.sdc`, `info.yaml` and both RTL files are fixed
by the declaration, not by git state.

(None of the three is `5edf30f9…`; that bundle and this tree differ only in
`source_revision`, because protemu's HEAD moved after the adopted run. No
declared input's content differed at the point the baseline was taken.)

### The manifest delta, field by field

| Field | Changed | What |
| --- | --- | --- |
| `source_inputs` | yes | `bin/asic_bundle.ml` and `tinytapeout/asic-dependencies.lock` hashes, plus their `git_status` |
| `files` | yes | two entries, `inputs/bin/asic_bundle.ml` and `inputs/tinytapeout/asic-dependencies.lock` |
| `resolved_settings` | **owner text only** | see below |
| `generated_settings` | no | |
| `flow_configuration` | no | |
| `target`, `resources`, `simulation_resources` | no | |
| `requested_tools`, `synthesis_sources`, `simulation_sources` | no | |
| `schema_version`, `project`, `top_module` | no | |

**`resolved_settings` needs stating plainly, because the handoff expected it
unchanged.** Every key and every value is identical — checked as a set and
key-by-key. What changed is the `owner` field of the twenty override entries:
`(Override "P0 CMOS5L template b86a2a78…")` became `(Override "<what the setting
does>; ttihp-verilog-template b86a2a78…")`.

This was unavoidable, not incidental. The two copied lists already disagreed on
that string (`"P0 CMOS5L template b86a2a78…"` against the example's `"TT CMOS5L
template src/config.json at b86a2a7"`), so one of them had to move whichever
list became the library's. Preserving protemu's wording would have put `P0` in a
library shipped to every consumer, and the handoff's own constraint — "`reason`
stops being a copied string and starts meaning something" — asked for the
opposite. The `reason` field reaches the manifest and nothing else: it is not in
`config.json`, so no tool input changed.

## 4. The `RUN_KLAYOUT_DRC` / `RUN_KLAYOUT_XOR` decision

**Both stay `0`.** No results-schema change on the consumer side: `collect`
still finds no `klayout__drc_error__count`, and a full flow is not eight minutes
longer. The new reasons:

> `RUN_KLAYOUT_DRC` — *off: TT precheck runs the same KLayout decks over the
> submitted GDS after the flow (478.64s, zero items on 2026-09-18), so in flow
> DRC buys about eight minutes of duplicate coverage; the cost is that LibreLane
> records no `klayout__drc_error__count`, so collect reports no KLayout metric;
> set it to 1 when signoff has to be self contained; ttihp-verilog-template
> b86a2a781484bcab7ba522dc5de540086695a430*

> `RUN_KLAYOUT_XOR` — *off: the XOR compares the Magic and KLayout GDS streams
> for tool disagreement, which is not a rule check and is not what TT precheck
> repeats; set it to 1 to have the flow catch a streamer disagreement itself;
> ttihp-verilog-template b86a2a781484bcab7ba522dc5de540086695a430*

Reversing it is one line in the declaration, and the manifest then records the
consumer's own reason in place of the library's:

```ocaml
Tt_cmos5l.overrides
  ~extra:
    [ { key = "RUN_KLAYOUT_DRC"; value = `Int 1; reason = "..." }
    ; { key = "RUN_KLAYOUT_XOR"; value = `Int 1; reason = "..." }
    ]
  ()
```

## 5. Defaults whose value moved

**None.** All twenty keys and values are exactly the pinned template's, which is
what makes the `config.json` comparison in section 3 meaningful. Only the
`reason` strings were rewritten, and they reach the manifest only.

## 6. Whether the manifest schema moved

**No.** `schema_version` is still `1`. No field was renamed, renested, added or
removed. Every field `adopted_phase4.py` reads (`files`, `identity`,
`requested_tools`, `target`, `top_module`) and every field
`check-adopted-bundle.py` additionally reads (`project`, `source_revision`,
`source_inputs`, `synthesis_sources`, `simulation_sources`) is untouched in name
and shape. Re-pin, do not re-vendor.

## 7. Whether `phase4.py`, `report.py` or `archive.py` changed

**No.** `scripts/` is untouched by this work (`git diff --stat -- scripts/` is
empty). The three vendored copies and their 79, 11 and 27 line deltas stand.

## 8. Whether the conflict diagnostics were reworded

**No.** No error message in `lib/resolved_build.ml` or `lib/flow.ml` was
touched, and the protected-key list is unchanged. Verified by running, not by
reading:

- `asic_bundle --check-conflicts` → `PASS clock, source-list, and target
  configuration conflicts`;
- `tinytapeout/scripts/check-adopted-bundle.py` (full, including the pinned
  LibreLane container) → `PASS repeatable bundle, manifest, metadata, and
  conflict checks`, `PASS p0 wrapper reset/disable/pin/timer trace`, `PASS
  emitted RTL wrapper trace, lint, and synthesis`;
- `dune build @runtest` in both repositories.

`--check-conflicts` now builds its negative case as
`Tt_cmos5l.overrides ~extra:[ conflicting ] ()`, which is the only line of it
that changed.

## The library's own example

`examples/tt_bundle_example.ml` was moved onto the module too: 201 → 151 lines,
its `module I` / `module O` replaced by aliases and its copy of the twenty
overrides deleted. A third copy turned up in
`test/test_resolved_build.ml`'s "reference project settings fit the override
boundary" test; it now resolves `Tt_cmos5l.overrides ()` itself, which also makes
it test the settings actually shipped rather than a transcription of them.

**No declaration carries a copy of the override list any more.** What remains is
`lib/tt_cmos5l.ml`, the expect test that pins its values
(`test/test_tt_cmos5l.ml`), and — outside both repositories' OCaml — protemu's
pre-adoption `tinytapeout/src/config.json`, which `stage-project.sh` still copies
for the legacy non-bundle path. That file was not touched; whether the legacy
path is still wanted is the consumer's call. The duplication this work targeted is
removed, not halved.

## Where the line count landed, and why not 90

`scaf/bin/asic_bundle.ml` went 208 → **153** lines, not the ~90 the handoff
estimated. The estimate counted "~35 lines of `Design.create` reset-synchroniser
and pad-gating"; of those 35, about 22 are the `P0_observable` instantiation and
its port map, which is the design and stays. The three items the handoff asked
for removed what they could:

| Was | Now |
| --- | --- |
| ~25 lines of `module I` / `module O` | 2 alias lines |
| 24 lines of override list | 1 line, `Tt_cmos5l.overrides ()` |
| 8 lines of reset synchroniser | 1 line |
| 3 × 4 lines of pad-gating `mux2` | 3 × 1–4 lines via `Tt_cmos5l.gate` |

What is left that is still not a decision about this chip is the **bundle CLI
entry point**: the 19 line `let () = match argv` that elaborates, renders, writes
and prints the identity, plus the 24 line `check_conflicts`. Both are byte-for-byte
the same shape in `examples/tt_bundle_example.ml`. Folding them into the library
(a `Bundle.main`-style entry, and moving the negative conflict assertion into the
library's own tests) would take the declaration to roughly 110 lines. That is the
obvious next removal, and it is outside what this handoff asked for, so it was
not done.
