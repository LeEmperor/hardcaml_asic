# Comment and formatting guidelines

These conventions are taken from `lib/resource_policy.ml(i)` and
`lib/elaboration_context.ml(i)`. Use those modules as the reference examples when
this document is unclear.

The goal of a comment here is to let a reader understand a module without reading
its callers: what it is for, what it deliberately does not do, why each decision
was made, and where the sharp edges are.

## 1. File header

Every `.ml` and `.mli` starts with three single-line comments, then a block comment
describing the module:

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

- The `Module:` line names the file, including its extension, in double quotes.
- The `.mli` header describes the **contract**: what the module represents, its
  guarantees, precedence or ordering rules, and how it fails.
- The `.ml` header opens with "Source implementation of ..." and describes the
  **wiring**: which other modules call into it, through which functions.
- State the module's boundary explicitly: what it does **not** do and which module
  owns that job instead.

## 2. Interface (`.mli`) versus implementation (`.ml`)

| | `.mli` | `.ml` |
| --- | --- | --- |
| Comment syntax | `(** ... *)` doc comments on values and constructors | `(* ... *)` |
| Audience | Callers of the module | Maintainers of the module |
| Content | Guarantees, failure behavior, examples of input | How it works, why, invariants, pitfalls |
| Cross-references | odoc style: `{!Project.elaborate}`, `{!in_scope}` | Qualified names: `Elaboration_context.register_exn` |
| Formatting | Left to `ocamlformat` | `ocamlformat` disabled (see section 7) |

Short `.mli` doc comments may be just a usage example:

```ocaml
(** [instance_exn "a/b/name"] *)
val instance_exn : string -> t
```

Failure behavior belongs in the `.mli`, spelled out per condition:

```ocaml
(** Register one resource instance named [name] in the current scope and select its
    implementation.

    Raises, with the instance identity and requested contract, if the name duplicates an
    instance already registered in this scope, if no policy applies, or if the policy
    cannot be satisfied by the technology. *)
```

## 3. Comment above every module, type and function

Place a block comment directly above each definition. Its first line is a one-line
summary of what the thing *is* or *does*, ending in `;`.

```ocaml
(* Which resources a rule applies to;
```

```ocaml
(* One entry in the policy; "resources picked by [selector] get [requirement]"; *)
```

Trivial accessors still get a short one-line comment:

```ocaml
(* grab the rules out of a policy; Private.finalize uses this for its unused rule check *)
let rules t = t.rules
```

Mark the module's central function so a reader knows where to start:

```ocaml
(* The main sauce here for policies; given a resource identity, return its requirement and
   which part of the policy chose it;
```

## 4. Structures inside comments

### Aligned definition tables

Document every variant constructor or record field as a `Name : meaning;` table,
with the colons aligned. Wrapped lines are indented to line up with the text after
the colon.

```ocaml
(* What the project accepts for a resource;

   Flops                  : always build it out of flops, even if a macro exists;
   Exact                  : must be an exact technology macro, otherwise registration fails;
   Exact_or_flop_fallback : take the exact macro when there is one, otherwise flops,
                            and the selection records it as a fallback so it is never silent;
*)
```

The same table form describes the outcomes a function can produce (for example the
`unmatched` / `shadowed` split in `Private.finalize`).

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
(* "a/b" -> Subtree ["a"; "b"];
```

```ocaml
   Instance -> (2, 0)             : an instance rule beats any subtree rule;
   Subtree  -> (1, depth of path) : between subtrees, the deeper (more specific) one wins;
```

## 5. Explaining why

Every non-obvious decision states its reason in the comment that introduces it.

- **Invariants the code relies on.** Say what makes the code correct, with a separate
  `Why:` comment when the argument takes more than a sentence:

  ```ocaml
  (* Equal precedence implies an identical selector, which [create] rejects, so the
     maximum is unique. *)
  (* Why: two matching instance rules would both name [id], and two matching subtree rules
     of the same depth are both prefixes of the same path with the same length, so they
     are the same path; either way it is a duplicate selector; *)
  ```

- **Choice of error style.** Say why a function returns `Or_error.t` or raises:

  ```ocaml
  (* Build a policy; returns Or_error rather than raising since this runs when the project
     is declared, well before any design constructor, so there is nothing to thread it
     through;
  ```

  `_exn` functions explain that they raise so design constructors do not have to thread
  `Or_error` through every hierarchy level.

- **Deliberate restrictions.** When something is intentionally strict or absent, say
  so and give the reason:

  ```ocaml
     default is optional on purpose: with no default, a resource that no rule covers fails
     at registration instead of quietly getting some implementation nobody asked for;
  ```

- **Consequences of a design choice.** Introduce them with `A consequence:`.

## 6. Pitfalls and emphasis

- Start a warning about easy misuse with `Careful:`, give a concrete example with
  real identities, and say whether the mistake is caught:

  ```ocaml
     Careful: Subtree only ever looks at [id.path], never [id.name]. The resource
     "left/buf" has path ["left"] and name "buf", so subtree "left" matches it but subtree
     "left/buf" does not. That mistake is not silent though; the rule matches nothing and
     finalize reports it.
  ```

- Use CAPITALS for the one word a reader must not miss: `NOT`, `WHY`, `PATH`, `OR`.
- Use `*asterisks*` to flag mutable state in prose: `The *mutable* State of the context`.
- Point to tests that demonstrate behavior: `-> see expect tests`.

## 7. Formatting

### `ocamlformat` in implementation files

`.ml` files that rely on hand-aligned comments or records disable `ocamlformat`
after the `open!` lines and re-enable it at the end of the file:

```ocaml
open! Core
open! Hardcaml

[@@@ocamlformat "disable"]
...
[@@@ocamlformat "enable"]
```

`.mli` files leave `ocamlformat` on (profile `janestreet`), so their comments
follow its wrapping. Code inside a disabled region should still read like
`janestreet`-profile output apart from the alignment below.

### Alignment

Align record field names, colons and types:

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

### Multi-line comments

- The closing `*)` goes on its own line.
- Separate paragraphs, tables and step lists with a blank line.
- A one-line comment closes on the same line.
- Keep lines within the 90-column limit used by the `janestreet` profile, even where
  `ocamlformat` is disabled and will not wrap them. If an inline comment does not fit,
  move it into the block comment above the definition.

### Functions with several arguments

Put each labelled argument on its own line, with an inline comment when its role is
not obvious from the type. The `=` and the return type annotation go on their own
lines:

```ocaml
let sources_of
    ~(mode : Elaboration_mode.t)
    ~(technology : Technology.t) (* what the technology can map; *)
    (request : Resource_request.t) (* kind plus contract, technology independent; *)
    (selection : Selection.t)
  : Resource_record.Elaborated_as.t * Resource_record.Source.t list
  =
```

### Pattern matches

Put a comment above each non-trivial match arm explaining the case, with a blank line
between arms:

```ocaml
  (* sim generation; only care about behaviour *)
  | Simulation, _ -> Behavioral_model, [ Generated_behavioral_model ]

  (* Implementing with flops; *)
  | Implementation, Flops -> Selected_implementation, [ Generated_synthesis_rtl ]
```

Branches that cannot happen get a trailing comment saying why:

```ocaml
      | None -> [] (* can never happen; selection already failed for an unmapped macro; *)
```

Inline comments on record fields are fine when the source of the value needs
explaining:

```ocaml
        ; database = Scope.circuit_database scope (* from the Hardcaml scope *)
```

## 8. References to code inside comments

| Reference | Form | Example |
| --- | --- | --- |
| Value or field in scope | Square brackets | `[lookup]`, `[rules]`, `[id.path]` |
| Another module's function | Qualified name | `Elaboration_context.register_exn`, `Private.finalize` |
| Constructors and types | Bare name | `Instance`, `Subtree`, `Or_error` |
| Literal input | Double quotes | `"a/b/name"`, `"a//b"` |
| Cross-reference in `.mli` | odoc link | `{!Private.finalize}` |

## 9. Error messages

Error text is read by users, so it follows the same care as comments:

- A lowercase sentence stating what went wrong, followed by `;` and how to fix it
  when there is a fix:

  ```ocaml
  "duplicate resource instance; give each instance in a scope a distinct name"
  ```

- Attach the identities involved as labelled `[%message]` fields
  (`~instance:(id : Resource_id.t)`), not by formatting them into the string.
- When an error propagates through a layer, add that layer's context with
  `Error.tag_s` instead of replacing the message.
- Omit empty diagnostic lists with `[@sexp.omit_nil]` on the type annotation.
