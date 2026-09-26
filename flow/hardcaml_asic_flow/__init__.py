"""Private flow implementation installed with the `hardcaml_asic` opam package.

This package is not a separately released Python distribution. It is installed
by Dune next to the OCaml library, under
`$PREFIX/lib/hardcaml_asic/flow/hardcaml_asic_flow/`, and is reached through the
installed `hardcaml-asic-flow` launcher. The repository `scripts/*.py` files are
thin development adapters onto these same modules, so a source checkout and an
installation run one implementation, never two.

Modules here use only the Python standard library and explicit paths. Runtime
data (the generic provisioner and its lock) is resolved package-relative by
`paths`, never from the caller's cwd, a `.git` directory, or a sibling checkout.
"""

# Both the runner/collector and the archiver use `str.removeprefix` and
# `Path.is_relative_to`, which are 3.9 features. `cli.main` reports this
# explicitly rather than letting a 3.8 host fail with an AttributeError deep
# inside an operation.
MINIMUM_PYTHON = (3, 9)
