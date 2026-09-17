# P4.4 mapped memory synthesis, 2026-09-17

The emitted four-word, eight-bit single-port memory selected explicit flops.
Its build identity is
`86077c59cefc1b0459e653df9ed8f93f30d51afbe5a594d6dab08f7ba1f1b2dc`;
the separate run ID is `26e9180a14bf4e4d81d59f27d39c2abc`. The immutable
manifest, run record, structured results, and a compressed copy of the complete
staged bundle, logs, and synthesis reports are beside this note. The archive can
be unpacked with `tar -xzf full-run.tar.gz -C <empty-directory>`.

LibreLane `3.1.0.dev3` completed through `Yosys.Synthesis` using the pinned
`ihp-sg13cmos5l` PDK and support-tools revisions. Yosys reported 179 mapped
standard-cell instances, 3,480.0192 µm² mapped area, and 1,959.552 µm²
sequential area. Unmapped instances, synthesis check errors, and inferred latches
were all zero. Every cell type in `stat.json` begins `sg13cmos5l_`; the
selection record names `Explicit_flops`, and the build has no macro collateral.

The host launcher used Python 3.12.3 and the LibreLane image uses Python
3.13.13, while the bundle requested 3.11. The run used
`--allow-python-mismatch`; the [preflight report](preflight.json) records both
exceptions and the hashes of every referenced file. These differences do not
alter the build. This is synthesis-only evidence, so timing, layout,
physical checks, and TT precheck are unavailable for this run.
