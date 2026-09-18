#!/usr/bin/env bash
# Build this checkout as an installed package, then link it from an unrelated project.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=$(mktemp -d /tmp/hardcaml-asic-consumer.XXXXXX)
trap 'rm -rf "$stage"' EXIT

cd "$repo_root"
dune build @install
dune install --prefix "$stage/prefix" hardcaml_asic

mkdir "$stage/consumer"
cat > "$stage/consumer/dune-project" <<'EOF'
(lang dune 3.17)
(name asic_package_consumer)
EOF
cat > "$stage/consumer/dune" <<'EOF'
(executable
 (name main)
 (libraries hardcaml_asic))
EOF
cat > "$stage/consumer/main.ml" <<'EOF'
let () =
  let config =
    Hardcaml_asic.Single_port_ram.Config.create_exn
      ~width:8 ~depth:4 ~read_latency:1
  in
  Printf.printf "address=%d storage=%d\n"
    (Hardcaml_asic.Single_port_ram.Config.address_bits config)
    (Hardcaml_asic.Single_port_ram.Config.storage_bits config)
EOF

cd "$stage/consumer"
OCAMLPATH="$stage/prefix/lib${OCAMLPATH:+:$OCAMLPATH}" dune build
actual=$(_build/default/main.exe)
if [[ "$actual" != 'address=2 storage=32' ]]; then
  printf 'unexpected consumer output: %s\n' "$actual" >&2
  exit 1
fi
printf 'external consumer: %s\n' "$actual"
