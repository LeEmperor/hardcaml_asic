# SRAM S.2a evidence, 2026-09-20

This directory is the durable output of:

```sh
experiments/sram_model_conformance/run.sh \
  --pdk-root /home/wayne/devel/jane/hardcaml_asic/.toolchain/pdk \
  --output-dir evidence/sram-model-conformance
```

`outcomes.log` records exit statuses. `environment.log` records the clean pinned
PDK revision and Icarus paths/versions. `inputs.sha256` hashes every inspected or
compiled model input and all experiment sources without hashing itself. Each
compile/run log begins with its working directory and exact command.

The functional run passed 23 vectors and 86 checks. The intentional failure
returned status 1. Both exact timed-model compilations succeeded, while their
runs exposed Icarus's documented undriven delayed-signal limitation. The
controlled timing probe shows that `-gspecify` enables path delay but not timing
checks. See [`docs/sram-model-conformance.md`](../../docs/sram-model-conformance.md)
for interpretation and scope.

Generated `.vvp` files were deleted after the run. No ignored or external
artifact is required to reproduce or interpret this evidence.
