# Concept: Gradual Nix Adoption for Reproducible Development Environments

## Context

Several of these repositories currently depend on a mixture of:

- OCaml / OxCaml compiler versions
- Dune
- Hardcaml and Jane Street libraries
- Verilator / Yosys / formal tools
- C/C++ toolchains
- Python utilities
- vendor or system-level dependencies

Today, some of this environment is implicitly defined by the machine it happens to run on: an opam switch, globally installed packages, apt packages, manually installed binaries, or local configuration.

The proposed direction is to investigate using **Nix as the outer reproducibility layer for development and CI environments**.

This is **not** a proposal to move development machines to NixOS, replace Dune, or immediately package every dependency in Nix.

---

## High-Level Goal

A repository should increasingly be able to support a workflow like:

```bash
git clone <repo>
cd <repo>
nix develop
dune build
dune runtest
```

where `nix develop` provides the expected versions of the compiler and supporting tools for that repository.

Conceptually:

```text
Ubuntu / normal host OS
        |
        +-- drivers / desktop / vendor tools
        |
        +-- Nix
              |
              +-- OCaml or OxCaml
              +-- Dune
              +-- Verilator
              +-- Yosys
              +-- Z3 / formal tools
              +-- clang / gcc
              +-- Python utilities
              +-- other reproducible project tooling
                        |
                        v
                      Dune
                        |
                        v
                 project build/tests
```

Nix defines the environment in which the normal project build system operates.

Dune remains responsible for building OCaml/Hardcaml code.

---

## Why Nix

The main motivation is reproducibility across:

- different developer machines
- different Git branches
- CI runners
- remote build servers
- future versions of the repository

For example, branch A should be able to use:

```text
OxCaml revision A
Dune version X
Verilator version Y
```

while branch B uses:

```text
OxCaml revision B
Dune version Z
Verilator version W
```

without globally reinstalling tools or mutating the host machine.

Nix can keep all of these versions side-by-side in `/nix/store` and expose the appropriate versions through the environment created by `nix develop`.

The repository's `flake.lock` can pin the exact Nix package-set revision and other inputs used to construct that environment.

---

## Intended Responsibility Split

### Host OS

Keep the host conventional, likely Ubuntu.

The host should continue to own things such as:

- Linux kernel
- NVIDIA / Mellanox drivers
- FPGA PCIe drivers
- desktop environment
- networking
- systemd
- large proprietary EDA installations where Nix packaging is not useful yet

### Nix

Nix should initially own reproducible developer tooling:

- compiler version
- Dune version
- Verilator
- Yosys
- formal tools
- linting / formatting tools
- C/C++ compiler versions where useful
- Python runtime and helper tools
- other deterministic command-line dependencies

### Dune

Dune should continue to own the build graph for OCaml/Hardcaml code.

Example:

```text
Nix
  -> provides OCaml/OxCaml + Dune + Verilator + tools

Dune
  -> builds Hardcaml generators
  -> runs tests
  -> generates RTL
  -> invokes simulation/test tooling where appropriate
```

Nix should not replace Dune merely for the sake of using Nix.

---

## Relationship With opam

Do not assume that introducing Nix requires immediately eliminating opam.

A reasonable transitional model is:

```text
Nix
  -> compiler
  -> opam
  -> system/native dependencies
  -> Verilator/Yosys/etc.

opam
  -> Core
  -> Hardcaml
  -> ppx_jane
  -> project-specific OCaml packages
```

This can later be revisited.

If moving the OCaml package graph itself into Nix becomes beneficial, that can be a later migration step rather than a prerequisite.

The first objective is reproducibility of the outer environment.

---

## Proposed Repository Shape

Potentially:

```text
repo/
├── flake.nix
├── flake.lock
├── dune-project
├── *.opam
├── src/
├── test/
└── ...
```

The flake should expose at minimum a development shell:

```bash
nix develop
```

Potential future outputs could include:

```bash
nix build
nix flake check
```

but these do not need to exist in the first migration.

---

## Migration Strategy

### Phase 1 — Development Shell Only

Add `flake.nix` and `flake.lock`.

Reproduce the currently expected development environment without changing the existing build flow.

Success criterion:

```bash
nix develop
dune build
dune runtest
```

works on a clean compatible Linux machine with substantially less manual setup.

### Phase 2 — CI Uses the Same Environment

Modify CI so that tests/builds run through the same pinned Nix environment used locally.

This removes divergence between:

```text
developer environment
```

and:

```text
CI environment
```

as much as practical.

### Phase 3 — Pin Non-OCaml RTL Tooling

Bring tools such as these under the Nix environment where useful:

- Verilator
- Yosys
- Z3
- Verible
- clang
- Python tooling
- waveform/test utilities

This is particularly useful for Hardcaml repositories whose tests cross language/tool boundaries.

### Phase 4 — Evaluate Deeper Packaging

Only after the simpler model is working, evaluate whether it is worth:

- packaging OxCaml revisions directly in Nix
- moving more OCaml dependencies away from opam
- exposing `nix build` as the canonical build entrypoint
- creating binary caches
- sharing toolchains across CI/build servers
- defining reusable internal Nix modules/flakes for multiple Hardcaml repositories

---

## Shared Hardcaml Toolchain Idea

If several repositories converge on similar requirements, consider creating a shared flake or Nix library.

Conceptually:

```text
hardcaml-nix-toolchain
├── OxCaml packaging
├── Dune
├── Verilator
├── Yosys
├── Z3
├── Verible
└── common shell helpers
```

Individual repositories could then pin that toolchain and add repo-specific dependencies.

This would avoid duplicating substantial Nix logic across:

- Hardcaml networking libraries
- ASIC tooling repositories
- financial acceleration projects
- FPGA test infrastructure
- future Hardcaml projects

The shared layer should remain small and composable rather than becoming a monolithic internal distribution.

---

## Important Non-Goals

For the initial migration, do **not**:

- move developer machines to NixOS
- replace Dune
- rewrite working build logic in Nix
- package Vivado/Quartus/Questa unless there is a clear benefit
- eliminate opam purely for architectural cleanliness
- force all repositories into one giant Nix monorepo
- make Nix knowledge a prerequisite for understanding the project itself

Nix should reduce environmental complexity, not move that complexity into a harder-to-debug layer.

---

## Questions for the Implementing Agent

When evaluating a repository, determine:

1. What exact compiler/tool versions are currently assumed?
2. Which dependencies come from apt/system packages?
3. Which dependencies come from opam?
4. Which dependencies are manually installed?
5. Which tools are reasonable to provide directly through nixpkgs?
6. Does OxCaml require a custom Nix derivation?
7. Can the existing Dune workflow remain unchanged?
8. Can CI reuse the same flake?
9. Are any dependencies proprietary or host-coupled enough that they should remain outside Nix?
10. Is there enough overlap with other repositories to justify a shared Hardcaml Nix toolchain?

---

## Desired Outcome

The desired long-term property is:

> The repository should carry enough information to reconstruct its intended development and test environment without depending heavily on undocumented machine-local state.

Nix is being considered as the mechanism for defining and pinning that environment.

The migration should be incremental, pragmatic, and compatible with existing Dune/opam workflows.
