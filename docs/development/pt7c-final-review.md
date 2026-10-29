# PT.7c — independent retained native-v2 final review

2026-10-28. Reviewer: **B**, ordinary-flow integration owner, independently reading
C's actual retained products. Reviewed example `docs/pt7c_native_v2_final.md`,
`acceptance/pt7c/closeout-native-v2-01/`, the original run/bundle/native reports,
eleven native diagnostic controls, archive contents and the separate reader-only
R1b correction capture. No C verification/sealing/EDA script was executed or
imported. No C evidence, provider pointer or A implementation source was edited.

## Disposition

**No remaining blocker found for the stated bounded scalar/default-corner coarse
synthesis + linked pre-PNR STA evidence, read through the corrected LF-only
inspector.** A-NATIVE-R1/R1b/R2/R3 now reject their intended counterexamples.
The actual LF native-v2 artifacts replay unchanged with the current helper and
with C's durable corrected inspector. This is not timing closure: all three
declared downstream hold witnesses remain **−0.044244 ns**, and broader native
min-report samples include additional negative slack down to **−0.243063 ns**.

The scope is one macro-free scalar example, five original flops, one primary clock,
one explicitly selected typical corner, exact stored exception relations and
complete returned native diagnostic groups/endpoint inventory. It is not named
execution, P&R, post-PNR preservation, reset-effect/CDC adequacy, authenticated
execution or exhaustive timing-path/exception-effect coverage. Overall inspected
verdicts remain **unavailable**, never exhaustive-coverage pass.

## Exact execution and inspection identities

| Role | Directly checked identity |
| --- | --- |
| Original ordinary native run | `83a02bdcb4b34f22bbc03b0ec5223b41` at `.dev/asic-pt7c/runs/20261028T183412758171Z_83a02bdc` |
| Original installed execution generation | `4d4316e3a33942c2a577d6f55acaa34a` |
| Original execution receipt SHA-256 | `ec00d5619805de324201a23446a0dd5129eb2a8ef02713ed87bd5e1299809310` |
| Captured development snapshot assertion | `8d3fa9270712a47473c22615c2a7005d975b361db5f569dfbe8e911055ccbe89` |
| Bundle identity | `9d01f5c006c697dd103762c04038fd73e8322d3b546f2bf56dfcad0de19cc8c6` |
| Manifest SHA-256 | `225941cc67b4e2ff695c3350287b56839fa5bbfe13ce83330178ce57a91a6d1d` |
| Complete emitted SDC SHA-256 | `7d66fe0de02bd45b4c214585719e39d8dab253a7e5cecc5342090c170bb1a128` |
| Executed native-v2 producer SHA-256 | `8d886b2bde7e50f7781ef7f3f73bfdfa47a8d7beba947119dd66129a2d48b03e` |
| Fresh mapped netlist SHA-256 | `1fa6fc0404ac31a5c435d9fc2f4b33dbe95749d53618c3a14c5455ea414876e1` |
| Inner native audit SHA-256 | `3601a22810b532ae0c3495b96dc00b214480ce5d333fcb6f1c12d4d99ac06884` |
| Native-data schema2 SHA-256 | `a1535be06542033176d28e2465abf0b4bf01223f9d0e541550cc2c42e204e9ec` |
| Native-written state SHA-256 | `5246923433cd2051b6ddba578cba771d513b6e38db370aad9092b2ca941bbe92` |
| Separate corrected-inspector generation | `4c9ae1a7a50444179c8ab69469443c19` |
| Corrected-inspector receipt SHA-256 | `24be25d1041477025792a92f0cca3268a85e2ce64f1650b6dbcf9e0a1f3de56a` |
| Current/captured corrected parser SHA-256 | `f141b57575d48c4c09678fea34aa499f1adfc797a20b0839c3269928fd9b9f07` |

The execution generation actually contains parser `aa8554bd…`, not `f141b575…`.
That distinction is retained. C's `pt7c_reader_r1b_final.md` correctly records a
separate reader capture, not another synthesis/STA execution. I checked its
installed parser and `tested-reader.ml` against the current source hash, and
directly compared the producer/runtime sources between the two generations:
they are byte-identical. The corrected reader's positive result equals the
original LF-product result; no historical execution is attributed to new code.

The snapshot hashes are local captured-byte assertions. I did not reconstruct the
entire capture aggregate or establish P6 compiled-source/execution authentication.
Installed source/binary/archive bytes and the compiled example artifacts listed
below were directly hashed, rather than accepted from the Markdown tables.

## Independently executed review

Reviewer script:

```text
/tmp/opencode/pt7c-final-independent-review.py
```

Final result/command/stdout/stderr artifacts:

```text
/tmp/opencode/pt7c-final-independent-natxa0rq/results.json
/tmp/opencode/pt7c-final-independent-review-results.json
```

Executed `python3 -B /tmp/opencode/pt7c-final-independent-review.py`. The final
script completes **785 explicit consistency assertions** and **27 read-only
helper calls**, including six original R1b repro invocations and eleven native
control inspections. These counts are review operations, not EDA executions or
an additive count of heterogeneous regression tests. Original binary SDC/report
bytes are decoded without universal-newline translation: the review cannot hide
CR while claiming the LF-only reader accepted raw inputs.

The necessary current helpers and independent 256-probe adapter were built once
under switch `5.2.0+ox`, shared `/tmp/opencode/asic-pt7-build.lock`, explicit `-j6`.
No broad regression was repeated. The review launched no Yosys/OpenSTA/OpenROAD,
Docker daemon command, provisioning or design/bundle emission.

## Hash closure and documentary qualification

Direct inventory checks:

| Inventory | Observed result |
| --- | --- |
| Original execution generation installed files | **994/994** match recorded hashes, including actual binaries, libraries and installed source |
| Separate corrected-inspector installed files | **994/994** match |
| Recorded compiled example emitter/adapter/build files | **13/13** match current retained files |
| Emitted bundle members | **13/13** match; staged copies also **13/13** |
| Current declared consumer source inputs | **7/7** match the emitted source hashes |
| Main companion sources | **65/65** hash-match; current inspection also authorizes the companion itself |
| Original run | **199** actual files hashed before/after; unchanged |
| Original missing-receipt startup failure | **30/30** companion sources match; native exit remains **1**, companion remains failed |

There is one documentary qualification, explicitly checked rather than silently
waived: the original `closeout-native-v2-01/checksums.json` has **3,561** entries.
**3,558 current paths match**. Three current documentation files differ because C
subsequently added the reader-only R1b continuation:

```text
docs/pt7c_acceptance.md
docs/pt7c_native_findings.md
docs/pt7c_native_v2_final.md
```

For each, the original byte version is retained at
`acceptance/pt7c/r1b-history-baseline-01/continuation-sources/docs/` and matches the
original closeout hash. Thus all three original documentary versions are still
available, but it would be inaccurate to say all 3,561 **current paths** are
unchanged. All other listed paths match; the native products are unchanged.
Both current documentation hashes and the complete original-run inventory remain
unchanged across this review. The script records every original/current hash and
snapshot path.

This review did not independently rehash C's entire separate 10,398-file older
history inventory. Its retained preservation records are not promoted here to
new independently verified execution or physical evidence.

## Actual ordinary synthesis and linked Step route

I read `run.json`, the per-step native `config.json` files, synthesis state,
mapped netlist, resolved/effective configuration, analysis request, transport
launch/terminal records, native command/version/process receipts and raw logs.

The numbered synthesis directory contains exactly:

```text
Verilator.Lint
Checker.LintTimingConstructs
Checker.LintErrors
Checker.LintWarnings
Yosys.JsonHeader
Yosys.Synthesis
```

The parent argv stops at `--to Yosys.Synthesis`; supervised exit/code/success and
the run's recorded primary command agree. Mapped Verilog's native header reports
**Yosys 0.66**, commit `86f2ddebce7e98ce7cacc27e8a5c14cb53b51b51`.
There is no Floorplan/P&R step in that returned directory inventory.

The supplementary directory has genuine Step metadata
`OpenROAD.STAPrePNR`, LibreLane **3.1.0.dev3**, and native command:

```text
sta -threads 1 -no_splash -exit <historical run>/timing-intent/driver.tcl
```

The Step `COMMANDS` file and native process-result argv agree; native exit is 0.
Retained `sta -version` stdout is **2.7.0**, with a successful version-process
receipt and matching stdout hash. Both parent transports bind image
`sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a`.
Recorded Docker CPU quota/worker argv are six; linked `STA_THREADS=1`,
`OPENROAD_THREADS=1`, and native `-threads 1` are explicit. This verifies recorded
policy and source consistency, not independent OS scheduling attestation.

Original configured corners are fast, slow and typical. The retained delta
explicitly selects only **`nom_typ_1p20V_25C`**, changes OpenROAD threads 6→1,
retains STA threads 1→1 and installs the retained hook pointer. Requested and
actually executed analysis corner lists each contain only that typical corner.
No all-corner result is inferred from the original list.

## Actual consumed source association and startup ordering

The exact netlist named by completed synthesis state hash-matches the native
audit's `mapped.v`. Original/staged/inner manifest bytes match, as do the complete
emitted/retained SDC and identity-covered native-v2 producer.

`native-inputs.json`, the inner receipt and raw `sta.log` agree on the actual
ordered paths `<historical run>/timing-intent/corners/nom_typ_1p20V_25C/library-{0,1}.lib`:

| Slot | Native Liberty header | SHA-256 |
| --- | --- | --- |
| 0 | `sg13cmos5l_stdcell_typ_1p20V_25C` | `34163f3e7de9f854afac57332ba06f1739b78e7ac35660a8a5ddd39c570124ad` |
| 1 | `sg13cmos5l_io_typ_1p2V_3p3V_25C` | `e6b5adf1ce31db3a0c15e5ca069c62e7d9efb604a710b8f6582700f1721d2d98` |

Both headers declare `time_unit:"1ns"`, nominal temperature 25 °C and core nominal
voltage 1.2 V. The I/O library name also explicitly records its 3.3 V rail.
Actual paths map to their run-relative copies and hashes in order. Native log
lines 4–5 record loading those exact copies, followed by mapped-netlist loading
and linking `tt_um_pt7_timing`.

The retained native wrapper loads `_TCL_ENV_IN`, reads/prints one receipt, then
sources its retained `librelane-corner.tcl`; it does not itself read SDC. The
actual log records **one** design-constraints read and one begin-to-complete
resolution/application block. Receipt precedes that block; native V2 completion
precedes standard min/max report generation; enclosing `PT7_AUDIT_COMPLETE`
follows the reports. Process and Step completion are separately present, so a
successful hook alone is not the acceptance proof.

## Five original stages and six stored relations

The emitted RTL has five `keep=1` register anchors and five ordinary clock/reset
always blocks. Reading the actual flat mapped Verilog independently confirms
five `sg13cmos5l_dfrbpq_1` cells, each with primary `clk`, direct active-low `rst_n`,
the reported unique Q anchor and these D connections:

| Stage | Cell | Actual D input |
| --- | --- | --- |
| capture first | `_06_` | `ena` |
| capture second | `_05_` | `hc_pt7_capture_first` |
| capture third | `_04_` | `hc_pt7_capture_second` |
| control first | `_03_` | `ui_in[1]` |
| control second | `_02_` | `hc_pt7_control_first` |

Raw stage/resolved/applied rows agree. I independently unfolded only the actual
native writer's line continuations and literal selector form, rather than using
C's summary, to check the native state has exactly two false-path commands and
these **six** unrestricted relations:

- `ena -> _06_/D` only.
- `rst_n -> _02_/RESET_B`, `_03_/RESET_B`, `_04_/RESET_B`, `_05_/RESET_B`,
  `_06_/RESET_B` only.

The native state is LF-only and selects `current_design tt_um_pt7_timing`.
No baseline disable/case-analysis/clock-group/min/max-delay masking command is
present. These are native **stored relations**, distinct from exhaustive effects
on all paths or proof of safe reset release.

## Raw diagnostics, native controls and witnesses

All seven baseline categories are explicitly present and empty. I rebuilt the
fixed V2 header, per-category BEGIN/END framing and preserved native group/detail
bytes independently and compared the **original report bytes** exactly. The
endpoint report contains the same sorted unique **12** pins as native data,
including five D, five RESET_B and two active output endpoints. This inventory
is not an unconstrained-endpoint count.

For **all eleven actual `controls-v2-01-*` native attempts**, I checked successful
exit, native OpenSTA banner, producer/control completion, recorded one-CPU /
one-thread argv, unchanged before/after input hashes against current retained
bytes, and equality of the two native writer captures (`observed.sdc` and
`native-state.sdc`). All actual control states are LF-only. Every control's framed
raw diagnostics/endpoint bytes agree with structured output. Current pure-reader
interpretation gives four supported-dimension positives and seven intended
scope/restriction/masking rejections.

Representative direct counts, taken from native arrays and corroborated by their
category-bound raw reports:

| Native control | Independently checked returned details |
| --- | --- |
| Baseline | All seven categories empty |
| Remove input delays | 18 missing-input details; 2 unconstrained D details |
| Remove output delays | 2 missing-output details |
| Remove clock and associated delays | 5 unclocked CLK details; 7 unconstrained endpoints; also 19 missing-input and 2 missing-output details |

Baseline selected external-capture min/max reports contain no path records. Removing that
exception exposes both actual witnesses; setup-only retains min and suppresses
max, while hold-only retains max and suppresses min. Broad/extra relations,
setup/hold/rise restrictions and CLK→Q masking reject under the current generic
reader. These are bounded witness observations, not exhaustive exception effects.

The three main downstream reports contain actual Q→D pin rows and library
setup/hold checks, not merely copied summary numbers:

| Path | Setup/max slack | Hold/min slack |
| --- | ---: | ---: |
| `_06_/Q -> _05_/D` | +19.432287 ns | **−0.044244 ns** |
| `_05_/Q -> _04_/D` | +19.432287 ns | **−0.044244 ns** |
| `_03_/Q -> _02_/D` | +19.432287 ns | **−0.044244 ns** |

For example, hold arrival is 0.199838 ns versus required 0.244082 ns, with a
native library hold check and `VIOLATED` slack. The broader native `min.rpt`
contains six sampled negative slacks: −0.243063, −0.129626, −0.124797 and the three
−0.044244 values. **−0.044244 is not claimed as the run's worst hold result.**
Synthesis report exit 0 is synthesis acceptance, not physical timing closure.

## Independent current-helper archive/restore replay

I inspected the reports tar's member inventory and confirmed it contains every
advertised timing source, then extracted both retained archives into a fresh
review-owned `/tmp/opencode` root with regular-file/traversal checks. The complete
input bundle was overlaid into `project/`; no design was re-elaborated or rerendered.

The current helper's original coarse view equals the retained public inspection
JSON exactly (stdout SHA-256 `d5765238262fe74fa24976c6f65b39eef53c69320234bb48390166b2155809df`).
Standalone current inspection equals its inner corner view. Independently restored
current inspect/collect (`--stdout`)/report return **1/0/0**, with identical timing
evidence and unavailable overall coverage.

I then copied the **current** native reader/collector/reporter binaries into the
review directory and repeated all three in my own bubblewrap user/PID/network
namespace: original example root, its PDK/run/bundle/both provider stores, and the
ASIC source/build checkout are hidden. Only current helper copies and the fresh
restored evidence are rebound read-only at existing review-owned paths. All three
JSON results equal the unsandboxed results. No original host directory was renamed.
Historical execution-root labels and UID/GID therefore do not require current
source access during replay.

One early reviewer launcher tried to create a new alias mountpoint under a
read-only root and stopped before helper execution (`Can't mkdir /review-current`).
Using existing review-owned bind targets fixed the launcher; it was not a provider
or evidence failure. Earlier outputs remain under
`/tmp/opencode/pt7c-final-independent-66amkv65/`. The initial strict inventory
attempt also correctly exposed the three versioned document revisions described
above; none of the C files or checksums was repaired by the reviewer.

Finally, the six **original saved** R1b repros—not just regenerated counterparts—
now return LF-only errors through pure/full-schema2 APIs. Actual retained r3 scalar
**audit-schema1** history still returns native coverage unavailable with exit 1
through the current helper. No native-v1 history was upgraded or relabelled.

## Final scope and remaining limits

Accept this exact retained synthesized-netlist/native-v2 evidence and corrected
read-only replay within the stated slice. C's original execution identity and
separate corrected-inspector identity must remain distinct. No new EDA or bundle
emission is inferred from reinspection. Native group completeness is completeness
of the returned native algorithms, not all-check/path-effect coverage; hash-bound
receipts are producer assertions, not authenticated execution. No all-corner,
post-PNR, reset-effect, analog MTBF or consumer-specific system acceptance follows.
Negative hold remains a real violation and timing closure is not established.
