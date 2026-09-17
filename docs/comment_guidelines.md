# Comment and formatting guidelines

These conventions come from the modules in `lib/` that have already been commented.
When this document is unclear, copy what the reference files below do.

A comment here should let a reader understand a module without reading its callers:
what it is for, who calls it, what it deliberately does not do, why each decision was
made, and where the sharp edges are.

## 0. Reference files

Look at the file that matches what you are writing before starting.

| Looking for an example of | Look at |
| --- | --- |
| Small file: one record, no functions | `lib/target.ml` |
| Small file: nested module plus a one-constructor variant | `lib/harness.ml` |
| Small file: one record plus one validator, no `.mli` | `lib/metadata.ml` |
| Validator with several checks combined into one error | `lib/clock.ml` |
| Types only: multi-line constructor and field tables | `lib/resource_record.ml` |
| Accessors, a hand-written `sexp_of_t`, a `Private` constructor | `lib/build.ml` |
| Mid-size module: comparator, `Why:`, `A consequence:`, numbered parsing steps | `lib/resource_id.ml` |
| Large module: selectors, precedence, the "main sauce" function | `lib/resource_policy.ml` |
| Decision table, `TODO (...)` notes, commented match arms | `lib/selection.ml` |
| Nested modules, `create_exn` on module-level values, field-order pitfall | `lib/technology.ml` |
| *Mutable* state, `Private` module, re-raise handling, outcome tables | `lib/elaboration_context.ml` |
| `.mli`: every value documented, record field docs, "Raises ..." paragraphs | `lib/resource_id.mli` |
| `.mli`: constructor docs, a pitfall stated in the interface | `lib/technology.mli` |
| `.mli`: accessor docs with phase notes, `Private` sig | `lib/build.mli` |
| `.mli`: failure and lifecycle behavior | `lib/elaboration_context.mli` |

`lib/elaboration_context.ml` is still a good reference for structure, but many of its
lines run past 90 columns. Do not copy that (see section 7).

A file whose `.ml` header does not follow section 1 has not been through the comment
pass yet. Do not use it as an example.

## 1. File header

Every `.ml` and `.mli` starts with three single-line comments, followed by a block
comment describing the module:

```ocaml
(* University of Florida *)
(* Author: Bohdan Purtell *)
(* Module: "resource_policy.ml" *)
(* Source implementation of the project resource policy. A policy is the project's answer
   to "what am I willing to accept for this resource?";

   It is a default requirement plus a list of rules, where each rule points at one
   instance or at a whole scope subtree. Elaboration_context.register_exn asks it for a
   requirement through [lookup], and Private.finalize walks its [rules] to catch rules
   that never applied (matched nothing, or were always outranked);

   It does NOT know what the technology can do, that is Technology's job; Selection is
   where the two meet.
*)
```

The `Module:` line names the file, including its extension, in double quotes.

### `.ml` header: three paragraphs

1. **What it is.** Open with "Source implementation of ...", then frame the module
   as a question it answers: "A clock is the project's answer to "which input is a
   clock, and how fast does it run?";". Use "the answer to" when the question is not
   the project's (a build, a technology, an identity).
2. **Wiring.** Name the modules that call into it and the functions they call it
   through, in the order things happen: "Project.create takes the list through its
   optional [clocks] argument and checks it with [validate_list] ...; Build carries the
   list through unchanged ...".
3. **Boundary.** Say what it does NOT do and which module owns that job instead. Work
   deferred to a later phase is named by phase: "resolving those is P2 work".

Add a paragraph between 2 and 3 when a design choice affects the whole file, such as
`resource_id.ml` explaining why [is_valid_component] is shared "on purpose".

### `.mli` header: the contract

The `.mli` header describes what the module guarantees to callers, not how it works:

- what a value of the type represents;
- guarantees and ordering or precedence rules, with numbered lists where there is an
  order (`resource_policy.mli`);
- how it fails, and when (at declaration, registration or finalization);
- what is not present yet, by phase: "Not yet present: the resolved target and validated
  constraints (P2), and emitted artifacts and provenance (P3)." (`build.mli`);
- a `{v ... v}` diagram when a lifecycle has several stages (`project.mli`).

### Modules without an `.mli`

The `.ml` is then both the implementation and the contract. The header keeps the
"Source implementation" form. The type comment says the record is transparent and what
follows from that (see section 5, "Visibility").

## 2. Interface (`.mli`) versus implementation (`.ml`)

| | `.mli` | `.ml` |
| --- | --- | --- |
| Comment syntax | `(** ... *)` doc comments on values, constructors and fields | `(* ... *)` |
| Audience | Callers of the module | Maintainers of the module |
| Content | Guarantees, failure behavior, examples of input | How it works, why, invariants, pitfalls |
| Cross-references | odoc style: `{!Project.elaborate}`, `{!in_scope}` | Qualified names: `Elaboration_context.register_exn` |
| Formatting | Left to `ocamlformat` | `ocamlformat` disabled (see section 7) |

Document every `val` in an `.mli` except `Private.create`-style values whose signature
says everything. A short doc comment can be just a usage example:

```ocaml
(** [instance_exn "a/b/name"] *)
val instance_exn : string -> t
```

When there is more to say, put the example first, then a blank line, then the failure
behavior spelled out per condition:

```ocaml
(** [create_exn ~path:["core"; "left"] ~name:"buf"]

    Raises, naming the offending component, if any label in [path] or the [name] is not a
    valid identifier. *)
val create_exn : path:string list -> name:string -> t
```

Constructors and record fields get trailing doc comments:

```ocaml
type t =
  | Simulation_model (** Model used to simulate the macro itself. *)
  | Black_box (** Empty module stub standing in for the macro during synthesis. *)
```

```ocaml
type t = private
  { path : string list
  (** Scope labels from the top, outermost first; empty at the top. *)
  ; name : string (** The resource's own name, as passed to registration. *)
  }
```

If a pitfall affects callers, state it in the `.mli` as well as the `.ml`. The `.mli`
version is shorter and says how to avoid it (compare `exact_mapping` in
`technology.mli` and `technology.ml`).

## 3. Comment above every module, type and function

Put a block comment directly above each definition. Its first line is a one-line
summary of what the definition *is* or *does*, ending in `;`:

```ocaml
(* Which resources a rule applies to;
```

```ocaml
(* One entry in the policy; "resources picked by [selector] get [requirement]"; *)
```

The comment for the main record or variant of a file usually opens with "The X
itself;" or "The selected X;".

### Where the comment goes

- A module that wraps a single `type t` gets its comment above the `module`, and that
  comment documents the type's constructors or fields. The `type t` inside needs no
  separate comment (`Requirement`, `Selector` in `resource_policy.ml`).
- A nested module gets its own comment above it, inside the parent (`Tiles` in
  `harness.ml`, `Role` in `technology.ml`).
- Functions inside a module each get their own comment, as at top level.

### Special cases

Mark the central function so a reader knows where to start. Every module that has one
uses the same phrase:

```ocaml
(* The main sauce here for policies; given a resource identity, return its requirement and
   which part of the policy chose it;
```

Trivial accessors still get a one-line comment, starting with "grab". Add the reason
anyone uses it, or a pointer, when there is one:

```ocaml
(* grab the rules out of a policy; Private.finalize uses this for its unused rule check *)
let rules t = t.rules

(* grab the resource inventory; already sorted by identity, see [Private.create] *)
let resources t = t.resources
```

A `Private` module's comment says who is supposed to call it:

```ocaml
(* The only way to make a build; Private by Jane convention, meaning only
   Project.elaborate is supposed to call it;
*)
module Private = struct
```

Module-level values say what they are and what follows from them:

```ocaml
(* IHP SG13 CMOS5L standard cells; no mappings, so every resource under it is flops or a
   selection error, depending on policy; *)
let ihp_sg13cmos5l = create_exn ~name:"ihp-sg13cmos5l" ~resource_mappings:[]
```

## 4. Structures inside comments

### Aligned definition tables

Document every variant constructor or record field as a `name : meaning;` table with
the colons aligned. Constructors with an argument name it: `Macro s`, `Collateral c`,
`Timing_model c`. Wrapped lines line up with the text after the colon:

```ocaml
(* An artifact a downstream step (simulation, synthesis, hardening) needs for a resource;

   Generated_behavioral_model : the behavioral model generated from the Hardcaml design;
                                what every resource gets in Simulation mode;
   Generated_synthesis_rtl    : synthesizable RTL generated from the Hardcaml design;
                                what a Flops selection gets in Implementation mode;
   Collateral c               : one file shipped with the selected hard macro; a Macro
                                selection in Implementation mode gets one per collateral
                                entry of its Technology.Macro.t;
*)
```

Records get the table even though their field declarations are already aligned. The
table says where each value comes from and what state it is in, which the type does not:

```ocaml
   target       : the declared harness and technology selection, NOT a resolved target;
   resources    : the resource inventory, sorted by identity in [Private.create];
```

Add a paragraph after the table for anything that applies to the whole type (see
`Resource_record.t`: "The whole decision chain is kept rather than only the outcome,
so ...").

Use the same table form for the outcomes a function can produce, or the checks it runs:

```ocaml
   invalid   : every clock with an empty port or a period that is not positive, reported
               together;
   duplicate : a port declared more than once; only the first repeat found is reported;
```

### Decision tables

When a function's result depends on a combination of inputs, give the whole mapping as
a table with a header row. Include the error row (`selection.ml`):

```ocaml
   Requirement              Exact mapping   Result
   Flops                  , any          -> Flops, Explicit_flops;
   Exact                  , Some macro   -> Macro, Exact_mapping;
   Exact_or_flop_fallback , Some macro   -> Macro, Exact_mapping;
   Exact_or_flop_fallback , None         -> Flops, Flop_fallback;
   Exact                  , None         -> error;
```

### Numbered steps for algorithms

When a function makes a sequence of decisions, list them in order, including the
failure case:

```ocaml
   1. keep every rule whose selector matches [id];
   2. take the one with the highest precedence (instance, then deepest subtree);
   3. nothing matched -> fall back to the default;
   4. no default either -> error; register_exn tags it with the request and raises;
```

### Arrows for mappings

Use `->` to show an input and what it becomes:

```ocaml
(* "core/left/buf" -> { path = ["core"; "left"]; name = "buf" };
```

```ocaml
   Instance -> (2, 0)             : an instance rule beats any subtree rule;
   Subtree  -> (1, depth of path) : between subtrees, the deeper (more specific) one wins;
```

A short list of input conditions and their results works the same way:

```ocaml
   A title that is empty or only whitespace -> error;
   author and description are NOT checked, empty strings are accepted for both;
```

## 5. Explaining why

Every non-obvious decision gives its reason in the comment that introduces it.

- **Invariants the code relies on.** Say what makes the code correct. When the argument
  takes more than a sentence, put it in a `Why:` paragraph or a separate `Why:`
  comment:

  ```ocaml
  (* Equal precedence implies an identical selector, which [create] rejects, so the
     maximum is unique. *)
  (* Why: two matching instance rules would both name [id], and two matching subtree rules
     of the same depth are both prefixes of the same path with the same length, so they
     are the same path; either way it is a duplicate selector; *)
  ```

  `Why:` is also used for a guarantee kept even though it looks redundant
  (`Build.Private.create` sorts records that already arrive sorted, "so the mli promise
  does not silently depend on how the context stores records").

- **Choice of error style.** Every function that can fail says why it returns
  `Or_error.t` or raises, in terms of its caller:

  ```ocaml
  (* Build a policy; returns Or_error rather than raising since this runs when the project
     is declared, well before any design constructor, so there is nothing to thread it
     through;
  ```

  ```ocaml
  (* Build a technology; raises rather than returning Or_error since technologies are
     fixed values declared at module level (see [ihp_sg13cmos5l]), where there is nothing
     to thread an error through;
  ```

  `_exn` functions called inside design constructors explain that they raise so
  constructors do not have to thread `Or_error` through every hierarchy level.

- **What a check covers.** A validator or `create` starts with "The one check:" when
  there is a single check, then says what goes wrong without it. List what is NOT
  checked as well as what is, and say whether all the checks run when one fails ("Both
  checks run even when the other fails, so one call reports both problems.").

- **Deliberate restrictions.** When something is strict, absent or shaped a certain way
  on purpose, say "on purpose" and give the reason:

  ```ocaml
     default is optional on purpose: with no default, a resource that no rule covers fails
     at registration instead of quietly getting some implementation nobody asked for;
  ```

  ```ocaml
     A variant with one constructor on purpose: future harnesses (a bare die, for example)
     become new constructors instead of fields bolted onto the Tiny Tapeout case.
  ```

  An exhaustive match with no wildcard is a deliberate restriction too, so say so ("a new
  Requirement constructor fails to compile here until someone decides what it
  selects").

- **Consequences of a design choice.** Start them with `A consequence:`:

  ```ocaml
     A consequence: every subtree is contiguous in sorted order, since identities sharing
     a path prefix share a components prefix.
  ```

- **Visibility.** Say whether a type can be built by hand, and what that means:

  ```ocaml
     The type is private in the mli, so the only way to build one is through the _exn
     constructors below, which means every selector has already been validated.
  ```

  ```ocaml
     Careful: there is no mli, so this record is NOT private. Only [select] guarantees
     [implementation] and [reason] agree; ...
  ```

- **Hand-written derivers.** When `sexp_of_t`, `compare` or similar is written by hand
  instead of derived, say why (`Build.sexp_of_t`: "Circuit.t has no useful sexp").

- **Deferred work.** Name the phase it belongs to (`P2`, `P3`) and, when useful, the
  document that plans it ("see docs/architecture.md section 3").

## 6. Pitfalls, unreachable code, TODOs and emphasis

### `Careful:`

Start a warning about easy misuse with `Careful:`. Give a concrete example with real
identities or values, and say whether the mistake is caught, by what, and when:

```ocaml
   Careful: Subtree only ever looks at [id.path], never [id.name]. The resource
   "left/buf" has path ["left"] and name "buf", so subtree "left" matches it but subtree
   "left/buf" does not. That mistake is not silent though; the rule matches nothing and
   finalize reports it.
```

```ocaml
   Careful: nothing checks [port] against the circuit yet. A clock declared on "clk" for a
   design whose input is "clock" validates fine and ends up in the build as is; that is
   not caught until endpoint resolution lands in P2.
```

When a pitfall carries over into another function, the second `Careful:` points back to
the first instead of repeating it ("it inherits the field order pitfall described on
[exact_mapping]").

### Unreachable branches

Branches that cannot happen get a trailing comment explaining why:

```ocaml
  | [] -> assert false (* can never happen; String.split returns at least one piece; *)
```

```ocaml
  | Default -> None) (* unreachable; a matching rule always beats the default *)
```

If a branch is only unreachable because a caller behaves a certain way, not because
of the types, say so and consider a TODO (see `Selection.Implementation`).

### TODOs

Tag every TODO with its kind in parentheses. Say what is wrong, what the fix is, and
what else has to change with it:

```ocaml
  (* TODO (possible optimization): the mapping is scanned even though this arm ignores it;
     harmless while mapping lists are small, but the lookup could be skipped for Flops; *)
```

```ocaml
  (* TODO (future fix): the message does not follow docs/comment_guidelines.md section 9,
     ... Changing it changes expect test output, so update those in the same commit; *)
```

When a TODO spans two places, put the full explanation in one and have the other point
to it ("see Selection.Implementation").

### Emphasis

- Use CAPITALS for the one word a reader must not miss: `NOT`, `WHY`, `PATH`, `OR`,
  `AND`, `ORDER`.
- Use `*asterisks*` to flag mutable state in prose: `The *mutable* State of the
  context`.
- Point to tests that demonstrate the behavior, naming the file when you know it:
  `-> see expect tests (test/test_selection.ml)`, `-> see test/fixture.ml`.

## 7. Formatting

### `ocamlformat` in implementation files

`.ml` files disable `ocamlformat` after the `open!` lines and re-enable it at the end of
the file, with a blank line on each side of both attributes:

```ocaml
open! Core
open! Hardcaml

[@@@ocamlformat "disable"]

(* first definition comment; *)
...

[@@@ocamlformat "enable"]
```

`.mli` files leave `ocamlformat` on (profile `janestreet`), so their comments follow its
wrapping. Code inside a disabled region should still read like `janestreet`-profile
output, apart from the alignment below.

### Alignment

Align record field names, colons and types. This applies to type declarations, record
literals that span lines, and `[%sexp { ... }]` records:

```ocaml
type shared =
  { mode            : Elaboration_mode.t
  ; technology      : Technology.t
  ; policy          : Resource_policy.t
  ; database        : Circuit_database.t
  ; mutable state   : State.t
  ; mutable records : Resource_record.t Map.M(Resource_id).t
  }
```

```ocaml
    Ok
      { implementation = Macro macro.name
      ; reason         = Exact_mapping { technology = technology.name }
      }
```

Records that fit on one line stay unaligned:
`{ project_name; metadata; mode; target; flow; clocks; resources; circuit }`.

### Multi-line comments

- The closing `*)` goes on its own line. A comment that fits on one line closes on the
  same line.
- Separate paragraphs, tables and step lists with a blank line.
- Summary lines, table rows and step lines end in `;`. Prose paragraphs can end in `.`
  or `;`.
- Keep lines within the 90-column limit used by the `janestreet` profile, even where
  `ocamlformat` is disabled and will not wrap them. If an inline comment does not fit,
  move it into the block comment above the definition.

### Functions with several arguments

Put each labelled argument on its own line, with an inline comment when its role is not
obvious from the type. The return type annotation and the `=` each go on their own
line:

```ocaml
let select
    ~(technology : Technology.t) (* what the technology can map; *)
    ~(requirement : Resource_policy.Requirement.t) (* what the project accepts; *)
    (request : Resource_request.t) (* kind plus contract, technology independent; *)
  : t Or_error.t
  =
```

Short functions that fit on one line stay on one line
(`let create_exn ~name ~resource_mappings =`).

### Local `let` bindings

Any `let ... in` that spans more than one line gets a blank line before and after it,
so it does not run into the bindings next to it or the expression that uses them. Give
each one a short comment above it saying what it computes. One-line bindings can stay
stacked together without blank lines.

When a function's name and arguments fit on one line, leave a blank line right after
its `=`. When the arguments go down in a column, the `=` on its own line already sets
the body apart, so the body starts directly below it with no blank line.

```ocaml
let validate_list clocks =

  (* Who is invalid out of the clock defs? *)
  let invalid =
    List.filter clocks ~f:(fun { port; period } ->
      String.is_empty port || Time_ns.Span.( <= ) period Time_ns.Span.zero)
  in

  (* Are there any dups? *)
  let duplicate =
    List.find_a_dup clocks ~compare:(fun a b -> String.compare a.port b.port)
  in

  (* Checking with the above in a list format, fold any errors into the result; *)
  Or_error.combine_errors_unit
    [ (match invalid with
       ...)

    ; (match duplicate with
       ...)
    ]
```

In an `Or_error.combine_errors_unit` list, separate the entries with a blank line when
any of them spans several lines.

### Pattern matches

Put a comment above each non-trivial match arm explaining the case, with a blank line
between arms. Also leave a blank line between the `with` and the first commented arm:

```ocaml
  match requirement, Technology.exact_mapping technology request with

  (* Flops requested; any mapping is ignored, the project asked for flops explicitly *)
  | Flops, _ -> Ok { implementation = Flops; reason = Explicit_flops }

  (* A macro is allowed and the technology has one for exactly this contract; take it *)
  | (Exact | Exact_or_flop_fallback), Some { macro; _ } ->
```

Trivial arms such as `| None -> Ok ()` inside a validator need no comment and no blank
line.

Inline comments on record fields are fine when the value's source needs explaining:

```ocaml
        ; database = Scope.circuit_database scope (* from the Hardcaml scope *)
```

## 8. References inside comments

| Reference | Form | Example |
| --- | --- | --- |
| Value or field in scope | Square brackets | `[lookup]`, `[rules]`, `[id.path]` |
| Another module's function | Qualified name | `Elaboration_context.register_exn`, `Private.finalize` |
| Constructors, types and modules | Bare name | `Instance`, `Subtree`, `Or_error`, `Technology` |
| Literal input | Double quotes | `"a/b/name"`, `"a//b"` |
| Sexp or OCaml syntax as written | Square brackets | `[%sexp { width : int; depth : int }]`, `((width 8) (depth 4))` |
| Cross-reference in `.mli` | odoc link | `{!Private.finalize}`, `{!Resource_policy}` |
| Another document | Repo path plus section | `docs/program-memory-contract.md section 8` |
| Future work | Phase name | `P2`, `P3` |
| Tests | Arrow plus file | `-> see expect tests (test/test_selection.ml)` |

## 9. Error messages

Error text is read by users, so it gets the same care as comments:

- A lowercase sentence stating what went wrong, followed by `;` and how to fix it when
  there is a fix:

  ```ocaml
  "duplicate resource instance; give each instance in a scope a distinct name"
  ```

- A message that names a class of problem can start with that class and a colon:

  ```ocaml
  "ambiguous technology capability: more than one mapping for a request; keep one \
   mapping per request"
  ```

- Attach the identities involved as labelled `[%message]` fields
  (`~instance:(id : Resource_id.t)`, `~technology:(name : string)`), not by formatting
  them into the string.
- When an error passes through a layer, add that layer's context with `Error.tag_s` or
  `Or_error.tag_s` instead of replacing the message.
- Omit empty diagnostic lists with `[@sexp.omit_nil]` on the type annotation.
- Changing a message changes expect test output, so update the tests in the same
  commit.
