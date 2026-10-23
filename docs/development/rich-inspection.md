# Retained rich inspection (schema 1)

For terminal post-PNR evidence that survives a failed signoff without a checkpoint,
see [timing analysis v1](timing-analysis.md). It adds an exact analysis-digest index
selector to the existing timing/signoff invocation; legacy sources remain supported.

```sh
hardcaml-asic-flow inspect EXECUTION --domain timing --stage signoff --json
hardcaml-asic-flow inspect EXECUTION --domain timing --stage signoff \
  --row-id ID --expected-digest DIGEST --json
```

Domains are `timing`, `clocks`, `physical`, and `routing`. Stages are
`synthesis`, `floorplan`, `placement`, `cts`, `routing`, and `signoff`.
`EXECUTION` is an explicit execution JSON file. Inspection performs host-only
stage-report/checkpoint validation and reads retained files. It starts no EDA,
runtime, Python, or backend process and publishes no files.

## Envelope

The contract is `hardcaml-asic.inspection`, `schema_version: 1`. Every response
contains `execution_file` (canonical absolute path), `execution_sha256` (raw
execution bytes), `attempt_id`, `domain`, `stage`, `source_digest`,
`diagnostics` (strings), and `truncated` (boolean).

An index adds `rows`. Each row has string `id`, `category`, `producer`, `name`,
`status`, and `source`; nullable string `corner`, `group`, and `unit`; nullable
finite number `value`; and `fields`, an array of `[string,string]` pairs.
`source` is JSON-encoded provenance text. It records the report's absolute path,
raw SHA-256, one-based inclusive line span, exact returned step ID and occurrence,
producer boundary, carry-forward attribution, unit evidence,
and the `observed supplementary-not-checkpoint-inventoried` qualifier.
The envelope's `stage` supplies the requested boundary.
Configuration paths and unit-declaration paths in provenance are relative to the
report's directory. Configuration JSON pointers identify constraint references;
`input_references` rows expose the retained `state_in.json` design/netlist and
constraint references without reinterpreting library models as the design.

A detail request adds `row_id` and `detail` instead of `rows`. Both detail options
are required together. Its digest must match the freshly read current index;
stale digests and unknown IDs fail with no JSON on stdout. Detail contains the
full source path and a bounded, numbered raw report excerpt with context.

The source digest covers query identity, execution bytes, observed source hashes,
rows, and diagnostics. Files are checked for concurrent change. Row IDs hash
source provenance, span, domain, category and name, rather than list position.
Indexes are bounded to 4096 rows and 2 MiB of serialized JSON; detail text to
64 KiB. Missing and malformed evidence produce distinct diagnostics and never
synthetic zero measurements. `truncated` reports index/diagnostic/repetition
bounds; excerpts explicitly mark their own truncation.

Queries admit at most 64 MiB of captured/parsed input in aggregate, 32 MiB per
source, and 512 source admissions/reads. Checkpoint JSON metadata is admitted
before host validation; opaque inventoried artifacts are validated by streaming
hashes, outside the parsed-input working set. Producer discovery is bounded to
256 returned producers, corner selection to 64 occurrences, and log reads to
256. Directory enumeration is incremental and capped at 1024 entries. Text
sources are capped at 262144 lines before allocating line arrays. Timing, clock,
and native record extraction receives the remaining row budget and stops when
it is exhausted; JSON size exhaustion also stops further reports. Limits produce
explicit truncated diagnostics, or a query error if reached during required
execution/checkpoint validation. Final consistency checks stream hashes rather
than reloading every observed source into memory. Irrelevant producer classes
are filtered before decoding their configurations; retained producer records
keep compact metadata. Index queries retain no excerpts; detail queries retain
only the requested row's bounded excerpt.

## Selection and measurements

The selected checkpoint's inventoried `segment.json` supplies the exact
`run_dir` and `returned_steps`. Each numbered producer directory is associated
with that returned position and checked against its retained `config.json`
`meta.step`/`meta.id`. Registered class IDs may omit the returned occurrence's
numeric suffix. Ambiguous or mismatched metadata fails; no latest-directory
search or inferred source mapping is used. Escapes outside the exact run
directory are rejected. Physical inspection can carry forward explicitly
attributed floorplan and DetailedPlacement measurements from earlier published
checkpoints in the selected execution.

The captured execution value is the value validated. Captured manifests must
match the manifests returned by validation; every subsequently read segment is
checked against that captured validated manifest's inventory SHA-256 **before**
its `run_dir` or `returned_steps` is used. Final source rechecks also include the
captured execution and manifest bytes. A persistent replacement segment cannot
be legitimized by hashing only its replacement bytes at the end of a query.
Dispatch uses the validated registered class independently of the exact returned
occurrence ID, including suffixed post-PNR STA, floorplan, placement and antenna
producers. Rows continue to retain their occurrence-specific identity.

* Timing paths run from `Startpoint:` through their slack line. Setup/max and
  hold/min remain separate, as do producer occurrences and signoff corners.
  Startpoint, endpoint, group, path type, arrival, required time, and slack are
  retained in fields; detail retains pathpoints. A retained generated Liberty
  selected by the producer's exact `state_out.json` library/corner reference
  supplies `ns` through its `time_unit: "1ns"` declaration. Missing declarations leave units
  unknown. Checkpoint target corner is never used as a measurement unit/source.
  A report/directory corner conflict quarantines the record: raw fields and
  detail remain available, but numeric value and unit are null, status is
  `unavailable`, and no conflicting Liberty unit attribution is supplied.
* Clock network latency min/max and skew retain rise/fall transitions. Minimum
  period and fmax are parsed explicitly; `MHz` is labeled only with observed ns
  units. Setup/hold check skew includes uncertainty/CRPR and has a separate
  category. Virtual/propagated headers remain intact alongside STA-log
  propagation diagnostics. Constraints and coverage reports remain inspectable.
  Both `Clock: NAME` headers and `Clock NAME` latency sections establish clock
  context and reset transition/column context. Missing context is diagnosed.
  Sources, generated status and supplied generation relationships remain
  structured fields for that clock; unsupported relationships are not inferred.
  Extension headers remain verbatim `header:LABEL` fields rather than guessed
  relationships. Each clock retains at most 32 header attributes. Clock and
  setup/hold skew reports with conflicting corner headers are also quarantined.
* Physical native metrics include actual floorplan bounding boxes (coordinate
  fields and derived width/height), cell/macro counts and areas, utilization as
  a ratio, rows/sites, and placement analysis. DetailedPlacement's estimated
  wirelength is legalized HPWL before mirroring; its post-mirroring HPWL is
  separately attributed from the log.
* Routing includes per-layer final congestion resource/demand/usage and overflow,
  native counts, lengths and iteration metrics, and global routing log quantities.
  Detailed DRC and antenna evidence retain separate categories and producers.

Native OpenROAD metrics use a bounded flat scalar-object policy: each repeated
key is preserved with its original line span, up to 16 occurrences per key, with
diagnostics. Nested/malformed entries are diagnosed; nonfinite quantities have
null values and `unavailable` status. No last-key-wins normalization is applied.

The CLI version metadata advertises the additive capability
`cli_contract.capabilities.inspection1: true` and lists `inspect` among its
JSON commands.

## Parent-owned verification and installation

From the provider checkout, the focused fixture alias is:

```sh
dune build -j20 @test/inspection @test/ocaml-stage-report
```

The example's dependency helper supports the grouped source namespace and a
private store. From `hardcaml_asic_example`, using the parent's chosen store:

```sh
python3 -B scripts/asic_dependency.py --store /tmp/opencode/inspection-provider-store \
  refresh --source /home/wayne/devel/jane/hardcaml_asic --mode development \
  --remove-source-build-override
. /tmp/opencode/inspection-provider-store/current/activate.sh
```

Refresh builds and installs the captured development source into that store.
Re-activate in the parent shell before querying the installed CLI. These commands
are supplied for the parent; implementation work does not execute them.
