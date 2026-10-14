"""Private Python runtime bridge installed with the `hardcaml_asic` opam package.

This package is not a separately released Python distribution. It is installed
by Dune next to the OCaml library, under
`$PREFIX/lib/hardcaml_asic/flow/hardcaml_asic_flow/`, and is reached through the
native `hardcaml-asic-flow` command when Python runtime probes are needed.
Only nine runtime modules ship. Retired service/reader/planner APIs remain in
SOURCE for deprecated reference/oracle imports, not installed Python support.
Use the native CLI or OCaml execution library for production services.

Host helpers use the Python standard library and explicit paths; the LibreLane
bridge imports official upstream APIs in its explicitly selected runtime. Runtime
data (the generic provisioner and its lock) is resolved package-relative by
`paths`, never from the caller's cwd, a `.git` directory, or a sibling checkout.
"""

# Minimum for private runtime payloads and retained source references.
MINIMUM_PYTHON = (3, 9)
