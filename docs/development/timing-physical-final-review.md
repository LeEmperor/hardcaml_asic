# Independent actual physical timing evidence review

2026-10-29. Reviewer A implemented the endpoint contract, not B's flow/evidence
adapter or C's physical execution. Read-only review of the actual first full
attempt, following `timing_physical_full_result.md` and `timing_physical_findings.md`
in `hardcaml_asic_example/docs/`. No EDA, builds, provider changes or C evidence
edits were performed.

## Verdict

**Actual extracted setup/hold closure, five-stage preservation, narrow exceptions,
ordinary physical/electrical gates and TT/final functional checks are verified for
this bounded example/profile. No timing, topology or functional acceptance blocker
was found.** Original in-flow and linked native logs agree with their output States
at all three executed corners; passing public output is supported by raw sources.

**Final portable-source confirmation also passes.** The corrected archive includes
the seven formerly missing reports, restores the exact original423 raw artifacts,
and reproduces full public inspect/collect/report values with original source/PDK
paths hidden. All1196 original run files remain unchanged; the portable package
hash/inventory verifies. See the final closeout below.

The coordinator has accepted corrected historical accounting: repeated mid-PNR
STA steps36/38/43 requested6 within allocation6; dedicated all-corner and linked
STA used1. No claim is made that every historical STA occurrence used1. The
forward alias-bounding helper is distinct and **unexecuted** by this physical run.

**No remaining blocker in the bounded physical timing/portable-source acceptance
slice.** Nominal-RC, functional-only and non-exhaustive coverage limits below
remain; this is not a silicon-safety certification or general arbitrary-profile
qualification.

## Exact subject and executed review

Workspace prefix: `/home/wayne/devel/jane/hardcaml_asic_example/`.

| Identity | Actual value |
| --- | --- |
| Run | `.dev/asic-timing-physical/full-runs/20261029T075052976305Z_23a6954b` |
| Run ID | `23a6954b852d4205b542d3815634d772` |
| Build | `ac513e0e7e9cfa935f73d697caebca8f601aeeb4ea62c2a2ccf61c10a10789cd` |
| Captured provider generation | `4856e6af993642988c18c07f47a8c689` |
| Capture snapshot | `4a821a382619f33eda6be911cb1bddc9d71345a882e97c5fb5b5de68979153a3` |
| Runtime image | `sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a` |
| Native STA | OpenSTA2.7.0, LibreLane3.1.0.dev3 |
| Postcheck | `bc95939552ae415c9a5aaa8c1fff1cfe` |

Reproducible A-owned review: `test/timing_physical/review_actual.py`.

```sh
python3 -B test/timing_physical/review_actual.py
```

Final retained review output:
`/tmp/opencode/timing-physical-final-review-3gh6tr27/review.json`.
It records **1720 heterogeneous assertions**, full raw source hashes, per-corner
metric comparisons, native cell inventories/topology, nine TT test names, actual
command-thread observations and captured/current source comparison. This number
is not a count of independent EDA runs. Earlier diagnostic output remains intact.

The script invokes only the exact captured provider's public read-only
`timing-intent-inspect --kind coarse_run --json`, `collect --stdout --json` and
`report --json`. It stores stdout/stderr under the new `/tmp/opencode` directory.
Inspection exits1 solely for unavailable exhaustive coverage; collection and
report exit0. Their timing-intent values agree exactly. Every advertised outer
companion source, every inner audit source and every emitted bundle member was
hashed directly. Read evidence hashes were rechecked unchanged after review.

## Actual implementation and extracted-input chain

`project/runs/asic/` contains the actual ordered producers:
Yosys06 → global placement28 → detailed placement34 → CTS35 → ordinary timing
repair37 → detailed routing44 → fill52/cell-frequency53 → RCX54 → original
STAPostPNR55. Completion/runtime/State/config sources and command logs are present.

The linked Step's `timing-intent/corners/state_in.json` equals the original
`55-openroad-stapostpnr/state_in.json` exactly. Original and linked outputs preserve
its nl/SPEF/ODB; those views also agree with RCX54 output:

* Netlist: `52-openroad-fillinsertion/tt_um_pt7_timing.nl.v`.
* Database: `53-odb-cellfrequencytables/tt_um_pt7_timing.odb`.
* Parasitics: `54-openroad-rcx/nom/tt_um_pt7_timing.nom.spef`, State selector
  **`nom_*`**, consumed for each of the three actual cell-library corners.

This qualifies three cell PVT corners with **one nominal extracted RC view**.
It is not three distinct RC extraction corners. The three processes are real and
not input-equivalence substitutions: their standard-cell and I/O libraries differ.

| Critical retained input | SHA256 |
| --- | --- |
| Manifest | `231cf9651682ffd508a27e4e420dc7dfe9eee3354b9e1bdc919d9f6805c2a32a` |
| Complete emitted SDC | `2f829d8bd384741abbb97e40f3318768bab5b5297fce11e5af16f49af796de00` |
| Final/STA/replay netlist | `f81bf5f9c2da65ee65f279e68d1025c06285549d8c602f5ca737791589e40a56` |
| Nominal extracted SPEF | `dcf886e5ec3dc5c45fa5ecb8dd05476704a612b8ea48b2a702432391f9476b7e` |
| Emitted native producer | `8d886b2bde7e50f7781ef7f3f73bfdfa47a8d7beba947119dd66129a2d48b03e` |

Each corner's `native-inputs.json` maps original inputs to actual retained consumed
paths/hash/byte counts. Those copies match original netlist, SPEF, SDC, libraries,
producer and driver bytes. **Native logs themselves** name those actual libraries,
netlist and SPEF reads; original in-flow logs name the corresponding original
inputs. Receipt/audit/process/native environment associations all agree.

Actual loaded order is standard-cell then I/O Liberty, both with ns units:

| Corner | Standard-cell SHA256 | I/O SHA256 |
| --- | --- | --- |
| Fast1.32V−40C | `af12d75a72d19648fa690027d29843fbae550aa91f4e40dd3339c7116d6e425d` | `f25da27e4cc0c94ffbce99e0654814a3af48d00c4ec571c9db5915208a7bbe07` |
| Typical1.20V25C | `34163f3e7de9f854afac57332ba06f1739b78e7ac35660a8a5ddd39c570124ad` | `e6b5adf1ce31db3a0c15e5ca069c62e7d9efb604a710b8f6582700f1721d2d98` |
| Slow1.08V125C | `3ee222c580ba33acb2131ac2bf224ff8ee9700751835b73aaec72b670bb31d3c` | `0dbb628168f9855eb88aee0d557da25c4cefb8c6b727a496fa2a02fd40da5cdb` |

## Raw all-corner closure, clock and annotation checks

Each corner has exactly one log record per required native metric, agreeing
numerically with **both original and linked output-State metrics**:

| Corner | Worst setup ns | Worst hold ns | Setup/hold violations | Slew/cap violations |
| --- | ---: | ---: | --- | --- |
| Fast | 16.058594908361634 | 0.10235321213620349 | 0 / 0 | 0 / 0 |
| Typical | 15.72907359990603 | 0.2766860707751655 | 0 / 0 | 0 / 0 |
| Slow | 15.113663637275028 | 0.5909271017549407 | 0 / 0 | 0 / 0 |

These whole-corner goals are distinct from the three selected interstage witness
reports. Configured=requested=executed fast/slow/typical, no missing/equivalent
corner, Step completion, native exit0 and linked cleanup all verify.

Native serialized SDC actually contains exactly one
`set_propagated_clock [get_clocks {clk}]`; native `clock-state.json` agrees, and
the input clock mode is propagated. Full-clock-expanded reports show nonzero
launch/capture network delay and actual delay-cell/net increments. Fast first
interstage hold has launch0.088903 ns, capture0.101238 ns, arrival0.422404 ns,
required0.320051 ns, uncertainty0.250000 ns and slack+0.102353 ns. Its data route
actually traverses `hold29/X`, not an invented direct synthesis path.

The complete emitted RTL and SDC match C's native-control emission byte-for-byte.
RTL hash is `dc387d8d445d55cbd75eb11d71bf5c36f4dc7ce395749e476e3614af55f2124a`.
20ns period,0.25ns uncertainty,0.15ns transition, early0.95/late1.05 derates,
0/1ns input and0/2ns output delays and6fF loads are preserved. Native writer
rounding of transition/derates is visible, not a new policy reduction.

At **all three corners**, native raw unannotated-driver count is15 and filtered
wired-net count is0. This is the explicitly qualified native ODB connected-net
filter scope, not a claim that all raw drivers are annotated. The actual consumed
`checks.rpt` hash, retained bootstrap/filter/dependencies, actual filter argv,
ODB/LEF bytes, successful process and filter metric/output-State agreement are
present. Filter ODB equals original STA input and RCX ODB bytes. Separate hook
`parasitic-annotation.rpt` is retained without substituting for actual filter input.

## Five original stages and actual post-CTS repair

Independent restricted parsing of the actual flat named-pin netlists (not a
production timing parser) confirms these same five `sg13cmos5l_dfrbpq_1` instances
at synthesis, CTS, repair and final:

`capture_first=_06_`, `capture_second=_05_`, `capture_third=_04_`,
`control_first=_03_`, `control_second=_02_`.

There are zero delay gates at synthesis/CTS and exactly nine
`sg13cmos5l_dlygate4sd3_1` after repair37 and at final. The exact instance-set
delta CTS→repair is **hold26…hold34**, with no removed/added flop, sizing change or
clone. The native repair log says six hold-violating endpoints, then nine inserted
hold buffers, resized0/cloned0, final WNS+0.103 and no setup violations. Repair
input nl/ODB identifies CTS35 output: **CTS35 is pre-repair**, not repaired timing.

| Original data link | Synthesis/CTS | After repair/final |
| --- | --- | --- |
| `_06_/Q → _05_/D` | direct | `hold29` |
| `_05_/Q → _04_/D` | direct | `hold34 → hold28` |
| `_03_/Q → _02_/D` | direct | `hold30` |

All five clocks still trace to primary `clk` through supported buffers, resets to
external `rst_n`, first capture D to `ena`, synchronous control D to `ui_in[1]`.
Native checked inventory is exactly the five stages; maximum checked depth2 is
below bound8. The final cell-frequency report independently agrees: five flops,
nine delay cells, six BUF1, three BUF8, two AND2,22 ties and one CTS load inverter,
plus physical fill/decap. Only four of the nine delay gates are interstage: the
remainder repair other data paths. The checked trace subset is not the whole-chip
inserted-cell inventory.

No architectural state/latency/reset change is evidenced. This conclusion combines
unchanged emitted RTL, exact sequential inventory, recovered predecessor/source
topology and the functional replay below; it is not a new formal equivalence proof.

## Exception narrowness and downstream timed paths

Independent reading of actual native serialized selectors yields precisely:

* `ena → _06_/D`.
* `rst_n → {_02_,_03_,_04_,_05_,_06_}/RESET_B`.

Two stored commands, six unrestricted min/max relations, no masking clock-group,
disable-timing/case-analysis or downstream min/max waiver. All seven native
diagnostic categories return no groups. Endpoint inventory truthfully has13,
including the combinational CTS-load `clkload0/Y`; it is not a sixth register.

Each corner's retained downstream min **and** max report has three nonempty
matching register-pair paths, all MET:

| Corner | Three hold witnesses ns | Three setup witnesses ns |
| --- | --- | --- |
| Fast | 0.102353 / 0.336137 / 0.111441 | 19.299553 / 19.044508 / 19.300367 |
| Typical | 0.276686 / 0.623378 / 0.290489 | 19.074339 / 18.688152 / 19.075085 |
| Slow | 0.590927 / 1.140763 / 0.613301 | 18.666981 / 18.047829 / 18.667179 |

These support bounded downstream preservation, not exhaustive exception-effect
classification. Reset-control waivers are not recovery/removal release safety,
and ordinary STA is not metastability/MTBF, CDC or bus-coherence qualification.

## Existing physical gates and ordinary postcheck provenance

Final native metrics give antenna nets/pins0, detailed-route DRC0, Magic DRC0 and
LVS errors0. Raw Magic report has COUNT0; raw Netgen top result is **Circuits match
uniquely**, with retained normal supplied standard-cell/SPICE comparison scope.
Its cell/primitive placeholder warnings are not analog transistor qualification.
The original raw antenna, Magic and LVS reports exist in the run; their archive
omission remains a separate source-closure issue. No SRAM macro/waiver contract
is present.

The normal postcheck's XML has **nine successful cases, no failure/error/skip**:
pin-label overlap, CMOS5L KLayout DRC, zero-area, KLayout checks, pins, boundary,
layers, cell names and analog pins. The raw CMOS5L DRC/overlap/zero-area XMLs have
no violation items. The execution log shows actual KLayout DRC running with six
threads and completion, then TT precheck pass—not just a summary Boolean.

Final GDS checked by TT hashes to
`fe9ceaa789bae7f11681bcdc29cba2c7ef0691dbd1ffae740807301067f2f3cc`.
The exact final netlist used by Icarus matches the native STA netlist hash above.
The actual retained testbench models three capture/two control stages, active-low
reset and output gating, checks both falling-edge/reset and rising-edge states,
and prints **512 observations PASS** in the raw postcheck log. All recorded
postcheck processes exit0 and owned cleanup succeeds.

Production profile is `cmos5l_physical_timing_used_cells_v1`, explicitly
`zero_delay_gate_functional`, with FUNCTIONAL/SIM defines. All11 used module names
match final netlist masters; exact vendor module hashes, vendor/UDP copies,
functional view, helper, manifest/preflight/netlist/testbench hashes are retained.
Only the reset flop's CLK/D/RESET_B delayed-reference bridge is adapted; the
other used cells have no delayed-reference adaptation. The reviewed functional
view hash is `105b2c405da40dba0bef9935ea1465297e5ec7a584b5b359571dd6aaaa395139`.
This establishes the actual digital replay, **not vendor specify/SDF timing
conformance or analog behavior**. Earlier failed vendor-model attempts and C's
native negative controls are not overwritten or rerun by this review.

## Resource observations and unresolved plan discrepancy

Actual full launcher had3600s TERM deadline +60s kill grace and exited0 after
1477.766903s. Docker CPUs6, flow jobs6, OpenROAD/KLayout settings6, serialized
standalone STA corners1, linked STA/filter native threads1 and cleanup evidence
verify. Postcheck records Nix max-jobs1/cores6, host affinity<=6, Docker CPUs6,
nested threads6 and1800s per-tool deadline; raw KLayout log confirms threads6.

**R-THREADS (methodology discrepancy, not a timing failure):**

| Actual command source | Requested native threads |
| --- | ---: |
| `31-openroad-stamidpnr/COMMANDS` | 1 |
| `36-openroad-stamidpnr-1/COMMANDS` | 6 |
| `38-openroad-stamidpnr-2/COMMANDS` | 6 |
| `43-openroad-stamidpnr-3/COMMANDS` | 6 |
| Original standalone pre/post STA commands | 1 |
| Linked corner STA and annotation filter | 1 |

The retained implementation wrapper replaces Classic step classes by exact
identity; these repeated mid-STA aliases were not all bounded to1 in this actual
run. The recorded six-thread commands are within C's allocation and container
ceiling. They contradict the stronger handoff/summary assertion that all mid-STA
commands are one-thread. The original in-flow post-PNR annotation-filter commands
omit an explicit `-threads`; the inspected fast filter process sampler reports
peak threads1. Do not conflate that original command with linked filter argv,
which explicitly sets1.

Final disposition: the coordinator accepted this historical six-thread mid-PNR
profile as within allocation6, with corrected disclosure of the earlier blanket
STA1 claim. A new forward helper bounds normalized aliases; it did not produce
this run and has not received a new native execution here. No second physical
attempt, historical command rewrite or new EDA was performed or implied.

## Captured versus current/tested source identity

This is a **development capture**, not a clean-tree/revision reproducibility claim.
Its receipt explicitly says captured bytes are not an atomic checkout and differ
from the recorded source snapshot/base. The recorded desired revision is
`1714764859274f80a9f5ad207421a04601824e99`; observed base is
`e44d44a3bf02a3253197e861a54a4f1e66166c3d`. Neither substitutes for the actual
capture snapshot/generation identity at the start of this report.

At the initial actual-review snapshot, all11 compared installed-source companions
equal current checked source bytes. This includes endpoint/intent/native producer,
physical reader/metrics/native grammar/schema3 reader, postcheck, both runtime
helpers and archive producer. Runtime/reader hashes equal those independently
verified for F1–F6 fixes in `timing-physical-flow-review.md`. For example:

| Source | Captured/current SHA256 at review |
| --- | --- |
| `timing_physical_runtime.py` | `4df32ca20f61f94672d63c293f2a605cdbb68f8b130e0e9f014d1e68cdc679e2` |
| `timing_physical_flow.ml` | `8b11e769fe939e8da26e8cc1592fe26258c72d733b2d1bdc14759d67df6dc14d` |
| `timing_physical_metrics.ml` | `1c6286251ccb1815b9386934df737fb37270b71df245f45d0ef5a4bb257476b4` |
| `physical_runtime.py` / used postcheck helper | `20b4288ce4ecb89577454edcaa489583fd8eeaed14f663888b59c9eba7fa9048` |
| `archive_service.ml` (before pending fix) | `7c3bf39ed90296c8ae0ca492c6a0f65c9d93485830e9769609e14831ae359e47` |

Exact complete comparisons/hashes are in `review.json`; this is not a statement
that every checkout file equals the capture. A later archive/thread correction
will be a new source snapshot, not retrospectively the producer of this run.

## Initial archive item (historical)

The seven known original reports (four antenna, one Magic DRC, two Netgen LVS)
remain available and were read/hash-inventoried here. Original public collection
advertises them, while C's first archive restore omits them. B owns the fix;
this reviewer did not edit archive code, republish an archive or copy live-run
reports into a purported restored archive. Final archive/hidden-input exact
collect/report parity is **deferred**, not waived by timing pass.

Subject to those explicit archive and methodology dispositions, the actual
single-attempt result supports the intended bounded physical timing extension:
unchanged architecture/model, qualified ordinary combinational repair, real
propagated/extracted timing at three executed PVT corners, retained narrow
exceptions and ordinary physical/functional gates. No new timing/architecture/
functional blocker or need for another P&R run was found. The following final
verification supersedes the deferred archive disposition, preserving that history.

## Final corrected archive/package verification

2026-10-29. Read the updated C full-result document and
`evidence/portable-package-01/closeout.json`. Independently verified raw archives,
restoration, source identities and representative hold reports. No EDA/build or
broad suite was run. C's run, old/new archives, package and receipts were read-only.

Reproducible focused check:

```sh
python3 -B test/timing_physical/review_portable.py
```

Results: `/tmp/opencode/timing-physical-portable-review-o0y9xqar/review.json`.
The8993 heterogeneous assertions are primarily byte/hash inventory comparisons,
not8993 independent tests or EDA executions. All pass:

* All **1196 original run files** still match the pre-correction sealed inventory.
* Every one of the **449 report-tar members** matches both original run bytes and
  the restored file; descriptor/tar member sets are identical.
* Input-bundle members and exact loose run/preflight/postcheck records also match.
* Every one of the **423 unique original raw artifacts** exists in the restored
  tree and matches its original/pre-correction hash. Original list order and
  complete response values are preserved, not normalized to a reduced set.
* Independently re-executed the recorded corrected-reader inspect/collect/report
  invocations under `bwrap`: original example/PDK and ASIC source hidden, restored
  tree/provider read-only, network unshared. Exit codes1/0/0 respectively and
  **full JSON equality** with original execution responses and C's restored
  responses. Inspection's1 still denotes unavailable exhaustive coverage.
* Portable package SHA and its exact **4269 regular-file inventory** verify by
  decoding/hashing tar members without changing the package. Its packaged earlier
  review/documentation snapshots remain historical bytes; this final addendum is
  not retroactively substituted into the immutable package.

The seven originally omitted reports now have these independently checked hashes,
equal in original run, corrected tar and restored tree:

| Report under `project/runs/asic/` | SHA256 |
| --- | --- |
| `40-openroad-checkantennas/reports/antenna.rpt` | `88ceef0b63031420e468a911f7c57fd68d4c409b45a681c14667323216ceb4fb` |
| `40-openroad-checkantennas/reports/antenna_summary.rpt` | `bd4c6489f063ba0e337ce9356da7a70bf063e08c5713b64eac28b6f9cd496d6a` |
| `46-openroad-checkantennas-1/reports/antenna.rpt` | `88ceef0b63031420e468a911f7c57fd68d4c409b45a681c14667323216ceb4fb` |
| `46-openroad-checkantennas-1/reports/antenna_summary.rpt` | `bd4c6489f063ba0e337ce9356da7a70bf063e08c5713b64eac28b6f9cd496d6a` |
| `62-magic-drc/reports/drc.magic.rpt` | `9024d2903144f266af14ff365d68b9204d98d8ae34732710f2249ca0438e3b7b` |
| `66-netgen-lvs/reports/lvs.netgen.json` | `89f70f9c9e2aff1a639d3ba8cfbe4ed6ac6dd6432d780ab8094dc8c8b55a2ab4` |
| `66-netgen-lvs/reports/lvs.netgen.rpt` | `28496ffa33d62745b7420030d009bc8587773441b32267c189998099570dc11c` |

### Execution versus corrected archiver versus forward source

These are distinct authorities, not a retroactive physical rerun:

| Role | Identity |
| --- | --- |
| Actual execution generation | `4856e6af993642988c18c07f47a8c689` |
| Actual execution snapshot | `4a821a382619f33eda6be911cb1bddc9d71345a882e97c5fb5b5de68979153a3` |
| Corrected archive/reader generation | `1ba205c2a11c4904b03d98b0e7a3f616` |
| Corrected archive/reader snapshot | `454be3f35b6183bf5142913e224b5e5665d186a1fa251efbb8e3e31c2eef8512` |
| Old archive source SHA256 | `7c3bf39ed90296c8ae0ca492c6a0f65c9d93485830e9769609e14831ae359e47` |
| Corrected archive source SHA256 | `4c86b6516f31b0c1c18a07364ab85b7c38a9122633debec2cafeac93befb415d` |
| Executed helper retained by **both** captures | `4df32ca20f61f94672d63c293f2a605cdbb68f8b130e0e9f014d1e68cdc679e2` |
| Current forward helper, unexecuted here | `887985abdfb8a829d52f9eaccb081c56bb7d7e25bb4982dc6fcfe9fd9b0c23fa` |

Corrected archive:
`evidence/full-public-corrected-01/archive-output/`.
Restoration: `evidence/full-restore-corrected-01/restored/`.

| Published object | SHA256 |
| --- | --- |
| `reports.tar.gz` | `8f2bff91bb171b95f24d05142009619693ac80aa5ce358c4d5a66ba762b4e366` |
| `input-bundle.tar.gz` | `ab91f86aaf778631cb4533b10199c1cb4baab529173d5f0d04e7875915a0759d` |
| `physical-timing-portable.tar.gz` | `500d31c84ca8bfd6eb5599a4e449a5ab9952cee2cea54179d5b02317e64d5782` |

### Why actual post-CTS repair changed hold

Re-read each original `downstream_min.rpt`, first path `_06_/Q → _05_/D`.
The actual `hold29` delay is visible in the data path while the0.25ns uncertainty
remains unchanged. Values below are native six-digit ns, not an invented
counterfactual rerun:

| Cell-PVT corner | Launch CLK | Capture CLK | CLK→Q increment | Increment through hold29/X | Data arrival | Required | Hold slack |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Fast1.32V−40C | 0.088903 | 0.101238 | 0.101213 | 0.232137 | 0.422404 | 0.320051 | +0.102353 |
| Typical1.20V25C | 0.129149 | 0.146974 | 0.150138 | 0.345112 | 0.624542 | 0.347856 | +0.276686 |
| Slow1.08V125C | 0.204894 | 0.232585 | 0.239965 | 0.553051 | 0.998047 | 0.407120 | +0.590927 |

Required arrival includes capture clock +0.25 uncertainty, then native CRPR
−0.007107/−0.010061/−0.015374 and library hold
−0.024080/−0.039057/−0.060090ns respectively. The `hold29/X` increment in this
compact report includes the upstream net/cell contribution; detailed reports
separate those rows. Clock skew can hurt hold, while inserted data delay increases
earliest arrival. Wire delay and changed clock-to-Q/load assumptions also enter;
do not attribute the entire pre-PNR-to-routed difference solely to one cell.

Nine delay cells repair six initially violating endpoints across the design:
four are on the three declared interstage links, and five are on other data
paths. The second capture link contains two delay cells. All three downstream
min/max witnesses and full per-corner setup/hold/electrical goals remain passing;
there is no downstream waiver or architectural register insertion. These are
three actual cell-PVT analyses of **one nominal `nom_*` RC extraction**, not
three RC corners, analog metastability/MTBF, reset-release safety, or vendor-SDF
qualification. The512-observation replay remains zero-delay digital functional.

**Final disposition: bounded actual physical timing and portable-source acceptance
verified; no remaining blocker in this slice.** Historical mid-PNR6/dedicatedSTA1
accounting is accepted and preserved. The new forward helper receives no native
execution claim, and no additional physical attempt or artifact mutation was
needed to close the archive item.
