# PT.7 final r3 — independent retained-evidence review

2026-10-28. Reviewer: slice B agent, **not C's example/acceptance implementer**.
Reviewed `hardcaml_asic_example/acceptance/timing/closeout-final-r3/`,
`acceptance/timing/FINAL.md`, `docs/pt7_timing_final.md`, actual producer inputs,
native logs/reports, graph mutations and evidence-negative fixtures. The example
evidence was read only. Only this report was added to the ASIC checkout; review
automation/results are under `/tmp/opencode`. No EDA, Dune build, broad regression,
provider/configuration change or Git mutation was performed for this review.

## Disposition

**No blocker found for the stated bounded standalone synthesized-netlist timing
intent acceptance.** The retained r3 bit and scalar products support the claimed
exact-source resolution, narrow exception-command application and sampled
downstream timing preservation. Current-source and retained-provider public
inspection both return **exit 1 / coverage unavailable**, as required.

This is **not timing closure**: all three sampled hold paths in each main audit
remain violated at **−0.044244 ns**. It is not exhaustive native exception-effect
coverage, normal named-flow integration, post-PNR qualification, authenticated
execution, CDC/reset-protocol approval or Protemu qualification. Those broader
claims would remain blocked by absent evidence and/or the explicit violations.

The old A-REAL-1/A-REAL-2 native failures remain failures of their original
captures; the new r3 result is not an override or relabelling of them.

## What was independently executed

Read-only checker: `/tmp/opencode/pt7-final-independent-review.py`.
Retained result: `/tmp/opencode/pt7-final-independent-review-results.json`.

```sh
python3 -B /tmp/opencode/pt7-final-independent-review.py
```

The completed checker exits 0 and:

- Hashes and size-checks **2,141 final inventory entries / 258,048,307 bytes**.
  It checks that the actual evidence file set is exactly that inventory plus its
  own excluded `closeout-final-r3/checksums.json`, and checks the inventory again
  after public inspection. No evidence bytes changed.
- Independently rechecks both prior inventories: **570** `closeout-01` entries and
  **798** `closeout-r2` entries, then the five recorded protected files and seven
  old provider symlink targets. These are comparisons to the retained closeout
  observation, not an invented earlier filesystem baseline.
- Rechecks **20 installed binaries, 13 library archives and 7 emitter compiled
  artifacts** against `producer-identities.json`, plus current/installed A/B
  source equality and retained consumer-source equality.
- Verifies both complete bundles' member/input-copy hashes, current declared
  example source hashes, synthesis inputs/products, main native inputs and
  launcher pre/post hashes. It reads mapped JSON connectivity directly rather
  than relying only on C's `inventory.json` assertions.
- Rechecks raw launches/events for **34 graph cases**, **6 tap controls**, and
  **5 extra anchor/scope negatives**, plus the no-SDC unconstrained diagnostic.
- Makes **44 fresh read-only public CLI calls**, serialized with a 20-second
  per-call deadline: four baseline calls (retained provider and current workspace
  router for each form), 36 evidence rejections and four semantic equivalence
  controls. Every expected outcome and intended diagnostic matched.

This checker does not import or execute C's sealing/EDA scripts. Its native-event
JSON and controlled-netlist assertions are review checks, not a new production
timing parser/resolver. The actual public reader handles manifest/receipt/Tcl
replay validation.

## Exact source and producer association

Observed immutable provider path:
`.dev/asic-pt7/provider/generations/74e9a52b43a14c69bff2763325b39522`.
Its retained `receipt.json` bytes equal both the generation receipt and
`capture-03/stdout.log`; receipt SHA-256:
`10b8bf667b72adf1b1936f810a6df37ea8974ae3770bd6db736960cf1ba606ef`.
The receipt records source snapshot
`a6723afb6a88bce6152d7b05662ea614a6e1a75352b870b4e20391e7c2d3f684`
and observed base `e46bfd7609e0b119ad74a8b412a3e866da5297de`.
Its separate recorded dependency revision differs intentionally; dirty development
capture, not a clean source revision/P6 stamp, is the documented identity scope.

Verified byte equality between current ASIC source and actual installed provider:

| Unit | SHA-256 |
| --- | --- |
| `lib/elaboration/timing_tcl.ml` | `9c53a5b75313adacd979ea5b559fd17ad0c51d2961c4df6dc0a41813a88d25d2` |
| `lib/elaboration/timing_intent.ml` | `514f4e47c8723fe770a098fa1996a5cfab928d7f917f535d1ae1ad806eded6bc` |
| `execution/results/timing_intent_evidence.ml` | `74718f8df0e893894f339286c36520f1f7abd5d89aeae59ff7307eab02900a16` |
| `execution/results/timing_intent_evidence.mli` | `959ca6c7ed0471692c7367735d31ec716ac03cc1f80563012405b04b975ac730` |
| `execution/runtime/runtime_contract.ml` | `055fa934e465bae40ab4728030724a26e9e35463f71c0b590c49eaac6d9ddf39` |

The two retained A source copies also equal current source. Every retained
`consumer-sources` file equals its current example source counterpart. Actual
emitter hash is
`0ff4ef097819a3f854ae7a90a2343fa792aefebd776aff9e0de8abf6f7e69e31`;
the retained native evidence helper is
`e6a3dd3b2d1464638c4467a9ae728eb61a07163bb2ae144fd2554396c48d0344`.
Both hashes were checked against the actual available executables, not merely
copied from C's Markdown.

These are locally recorded/source-replayed associations, not cryptographic
execution authentication. I did not independently rebuild the emitter/provider or
reconstruct the entire refresh snapshot from a retained per-source-file capture
inventory. The receipt's aggregate snapshot hash remains a local producer
assertion; the installed units and compiled artifact hashes above are directly
observed checks. No fresh EDA execution is inferred from them alone.

## Main native baselines: exact builds and complete SDC

| Item | Bit | Scalar |
| --- | --- | --- |
| Build identity | `6db329a39eb1c1e4d500f1808bc0dbfb95a355561b919f1b810a4e299503fadb` | `a6e8bd78b9db84e12c71a9e312df34b01944f9669e955092289a7a1c1a684ddd` |
| Native audit ID | `sta-bit-r3` | `sta-scalar-r3` |
| Complete SDC SHA-256 | `47077f72e69b42bbb046c84ee0a8ac552035249eac68c7a830006b6fb5027db8` | `7d66fe0de02bd45b4c214585719e39d8dab253a7e5cecc5342090c170bb1a128` |
| Audit JSON SHA-256 | `162134bb581647d74db57a73f9f5ec8220d29e0447cf67edf8e979619ac7bd0c` | `eadd4162e90b0374bc353c861e5dcc143204fd5293faf8d82ad76648311f53e6` |
| Mapped Verilog SHA-256 | `d3858042fe1672eb9ba2fb97e7deaacf30b80385dc719ecde9d262c29d82f132` | `8d6459a26eda8a65c1a9d729ff2031cb675295f8449e5421f446e30822984e0b` |

Verified `sta-*-r3/manifest.json` equals the whole public bundle manifest;
`top.sdc` equals the bundle's **complete** `constraints/top.sdc`; synthesis
`emitted.v` equals its manifest-listed RTL; and audit `mapped.v` / `cells.lib`
equal the corresponding retained synthesis inputs/products. All audit source
entries hash-match. Public inspection also verifies ordered bundle identity,
selected envelope cross-links, entire SDC hash, strict event replay and current
library-owned Tcl serializer suffix. No patched SDC is used in either positive.

Read the actual `driver.tcl`: it reads receipt bytes, Liberty, mapped Verilog,
links `tt_um_pt7_timing`, and calls `read_sdc top.sdc` once. It does not override
native object-query commands or generated helper procedures. It catches failures
and exits 1; native report generation precedes its completion marker.

`sta-bit-r3/tool.log` and scalar counterpart show OpenSTA 2.7.0, receipt, `begin`,
five exact `stage` rows, two `resolved` rows, `validated`, two `applied`, `complete`,
then `PT7_AUDIT_COMPLETE`. They equal the respective captured stdout+stderr.
Launcher and process-result exits are 0, with unchanged pre/post input hashes.
This directly addresses the former common top-Pin/internal-Net baseline failure
for these exact new runs, rather than accepting every negative due to that bug.

### Hardware inventory and intended exception scope

Read `timing/timing_specimen.ml`, `timing/timing_project.ml`, emitted RTL and
mapped JSON/Verilog. The source has three capture and two control registers,
active-low reset-to-zero, no architectural registers inserted by registration.
The emitted RTL has exactly five keep annotations. Mapped JSON independently
confirms five distinct flop cells and five distinct scalar Q bits, exact anchors,
primary CLK/rst_n connections, and all three predecessor-Q/downstream-D links.

Native mapping: capture first/second/third = `_4_`/`_3_`/`_2_`, control
first/second = `_5_`/`_6_`, all `sg13cmos5l_dfrbpq_1`. Actual first D is
`ui_in[0]` for bit and `ena` for scalar; control first D remains `ui_in[1]`.

Raw resolution/application rows show exactly:

- Capture: selected external source → **`_4_/D` only**.
- Reset: `rst_n` → **`_4_/RESET_B`, `_3_/RESET_B`, `_2_/RESET_B`, `_5_/RESET_B`,
  `_6_/RESET_B` only**.

There is no whole-cell, downstream-D or Q-startpoint waiver in those rows.
`applied` establishes successful command return. It is not a native path-effect
coverage result. Exact declaration/reason facts remain separate in `requested`.

## Downstream min/max, hold failures and unavailable reports

Read the complete native `downstream_min.rpt` and `downstream_max.rpt` from both
baselines, checking actual pin rows and library check type, not only summary
slacks. Each retains the following three sampled paths:

| Actual pin path | Setup/max reported slack (ns) | Hold/min reported slack (ns) |
| --- | ---: | ---: |
| `_4_/Q` → `_3_/D` | +19.432287 MET | **−0.044244 VIOLATED** |
| `_3_/Q` → `_2_/D` | +19.432287 MET | **−0.044244 VIOLATED** |
| `_5_/Q` → `_6_/D` | +19.432287 MET | **−0.044244 VIOLATED** |

For example the first hold report explicitly contains 0.199838 ns arrival,
0.244082 ns required, a library hold check and negative slack. Setup reports have
library setup checks and ideal-clock timing. This is evidence that these sampled
downstream paths remain timed, **not timing closure or exhaustive downstream
coverage**. Selected external-capture min/max queries return `No paths found.`;
that is a sample consistent with the exception, not proof of exhaustive effect.

`exceptions.rpt` actually says `no commands match 'report_exceptions'`. It is
unsupported-command help output, not an empty successful exception enumeration.
B correctly exposes native coverage as unavailable. Native `check_setup -verbose`
and `report_checks -unconstrained` bytes are retained in the main audits; the
main report's timed sample does not establish an exhaustive absence of
unconstrained paths.

The separate same-netlist **no-SDC** diagnostic control really omits `read_sdc`.
Its native log retains 19 inputs missing `set_input_delay`, two outputs missing
`set_output_delay`, five unclocked register/latch pins and seven unconstrained
endpoints, followed by an unconstrained path sample. Its launcher exited 0;
warnings and counts are preserved, not interpreted as a passing timing audit.

## Mutations: raw identities and intended failures rechecked

All 34 connectivity and six tap launch records were checked against actual
retained input bytes, exits and native event streams. Every case uses the same
complete SDC hash as its parent baseline and the same driver bytes as its family
baseline. Changed netlists have different hashes; direct baselines are identical
to the corresponding actual synthesis product. No negative is qualified solely
by a common setup failure: each family has a successful direct baseline.

I additionally inspected/asserted the actual changed pin/gate text for both
forms: wrong/constant/disconnected/inverted clock, data and reset inputs; exact
eight/nine inserted buffer chains; interstage rewrite; and the Q output tap.
Representative independently read examples:

- Bit `clock-wrong-input`: only `_4_/CLK` becomes `ena`; the native log stops
  after `begin` with `mapped clock for capture_first: mapped source differs`.
- Scalar `capture-wrong-input`: `_4_/D` becomes `ui_in[0]` instead of `ena`;
  native stage resolution occurs, then capture-source mismatch, no validation.
- Bit `reset-inverted`: `_4_/RESET_B` uses `inverted_source` driven by an actual
  `sg13cmos5l_inv_1` from `rst_n`; the native reset-source diagnostic rejects the
  unsupported transform. A resolved capture row is not an application record.
- Buffered positive: actual `sg13cmos5l_buf_1` A/X cells feed clock, capture D and
  reset; it completes and retains three downstream min/max samples. Eight buffers
  also complete; nine reject explicitly at the depth bound.
- Q tap: the actual output assignment adds `hc_pt7_capture_first` without changing
  its unique flop driver; the new native run completes, closing the former R4
  false rejection for this case.

Across the 28 connectivity negatives the launcher exit is 1, the intended
role-specific diagnostic is present, and **validated/applied/complete are absent**.
Five extra anchor/scope negatives have the same pre-application property. Four
retain scalar SDC unchanged; downstream-capture scope intentionally uses a
separate diagnostic SDC copy and is not represented as a valid published bundle.

Fresh public inspection rechecked 36 evidence rejections: 14 ordinary negatives,
14 semantic negatives and eight R5/R6 envelope cases. Four object-order/INFO
equivalence controls remain exit 1/unavailable. I independently checked coherent
wrong-scope fixtures have hash-consistent source closure but falsely name
`_3_/D` in both resolved/applied capture rows; they reject on pin scope. The
whole-SDC-prefix fixtures update source/receipt hashes while retaining the
original complete manifest; they reject on the manifest SDC binding.

C's eight envelope negatives deliberately retain the original asserted payload
identity after changing manifest facts; they test the intended semantic rejection
**before** identity verification. They are invalid evidence fixtures, not freshly
emitted builds or new native runs. The separately recorded B regression covers
coherently rehashed equivalents; this review does not silently change C's claim.

## Producer limits, preservation, failures and exclusions

Actual retained launch argv binds the local image
`sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a`.
The synthesis log/header reports Yosys 0.66 commit
`86f2ddebce7e98ce7cacc27e8a5c14cb53b51b51`; STA reports 2.7.0. Linked typical
Liberty hash:
`34163f3e7de9f854afac57332ba06f1739b78e7ac35660a8a5ddd39c570124ad`.
The retained Liberty explicitly declares `time_unit : "1ns"`, capacitance unit
`(1,pf)`, nominal 1.2 V / 25 C and the typical 1p20V/25C operating condition;
the reported nanosecond slack units are not inferred only from C's labels.
Launcher records/argv consistently require no network, read-only image root,
one CPU, 4 GiB, 128 PIDs, thread-related environment values of 1, and explicit
STA `-threads 1`, within their recorded timeout. Inspected launcher source takes
the global PT7 tool flock and rechecks inputs after locking. These remain local
producer records/policy, not independent OS scheduling attestation.

Preservation rechecks include both old closeout inventories, not merely C's
`preservation.json` status. Earlier native failures, probes and old accepted
results remain byte-identical under those inventories. The current final
inventory remained unchanged through all public inspection calls. No historical
SRAM run was associated with r3, and no P&R acceptance is inferred.

No unexpected evidence failure or blocker was found. One initial reviewer script
assertion used the wrong literal warning spelling (`missing input delay` instead
of native `missing set_input_delay`); reading the actual control log corrected
that review-script assertion. It was not a tool failure or altered evidence.
No evidence-validation check was skipped for missing files. This review did not
re-run EDA, broad/installed suites, other corners, routed parasitics or any native
coverage command unavailable in the producer. Only the typical corner with ideal
clocks/no extracted interconnect parasitics is qualified here. Hold closure,
post-PNR retention, analog CDC/MTBF, reset-release protocol and consumer-specific
review remain explicitly unqualified.

## Review receipt

- Final C inventory SHA-256:
  `10950414a5da1c6c63a0be00289048c9cac81f12e1745fbecf2bb66a422699a5`.
- Reviewer script SHA-256:
  `d9aa0c064b0012eefe33380a6919b8da434a0fa896a4aaa04c0ac8311a5e4751`.
- Reviewer result JSON SHA-256:
  `a98320582b400af1fcf0ef245b70e5fab7dd217d41df7d8b28f01bd100a22781`.

`git diff --check` passed for the ASIC worktree after the report was added.

**Recommendation:** accept only the documented bounded PT.7 timing-intent
preservation/strict-audit subset for these exact r3 products, with native coverage
unavailable and negative hold slack retained. Do not promote it to timing closure
or unrestricted flow/CDC/reset qualification.
